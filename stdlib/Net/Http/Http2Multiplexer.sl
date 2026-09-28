// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

module Standard.Net.Http;

import Standard.Collections;
import Standard.IO;
import Standard.Net;
import Standard.Net.Security;
import Standard.Text;
import Standard.Threading;
import Standard.Time;

/// The connection-wide receive window this end keeps open.
internal const long Http2ConnectionReceiveWindow = 16777216;

/// The most bytes a header block may reach across its CONTINUATION frames.
internal const nuint Http2MaxHeaderBlockLength = 1048576u;

/// How many streams this end remembers having reset, so that frames the
/// peer sent before it saw the reset are dropped rather than refused.
internal const nuint Http2RememberedResets = 128u;

/// How long a connection error waits for the write lock to send its GOAWAY.
internal const int Http2GoAwayWaitMilliseconds = 1000;

/// The frames and streams of one HTTP/2 connection (RFC 9113), shared by the
/// thread that reads it and the threads that send requests on it.
///
/// **Two locks, never taken the other way round.** `_writeLock` serialises
/// what goes on the wire, and with it the HPACK encoder and the next stream
/// identifier, since blocks MUST arrive in the order they were encoded and
/// identifiers MUST rise. `_state` guards every stream and every window. A
/// writer MAY take `_state` while it holds `_writeLock`; nothing takes
/// `_writeLock` while it holds `_state`.
///
/// **The reader thread never waits for `_writeLock`.** What it has to send —
/// a SETTINGS ack, a PING ack, a WINDOW_UPDATE, a RST_STREAM — goes on a
/// queue, and whichever thread next holds the lock writes it. Were the reader
/// to wait, a writer stuck behind a peer that is itself waiting to write
/// would never be relieved.
internal sealed threadsafe class Http2Multiplexer
{
    private String _key;
    private TcpClient _tcp;
    private IStream _stream;
    private TlsStream? _tls;
    private weak HttpConnectionPool? _pool;

    // The reader thread's own.
    private Http2FrameReader _frames;
    private HpackDecoder _decoder;
    private uint _headerStreamId = 0u;
    private Http2Buffer _headerBlock = new Http2Buffer(256u);
    private bool _headerEndStream = false;

    // Under _writeLock.
    private Mutex<int> _writeLock = new Mutex<int>(0);
    private HpackEncoder _encoder = new HpackEncoder(HpackDefaultTableSize);
    private uint _nextStreamId = 1u;

    // Under _state.
    private Monitor<int> _state = new Monitor<int>(0);
    private Dictionary<uint, Http2Stream> _streams = new Dictionary<uint, Http2Stream>();
    private List<uint> _resetStreams = new List<uint>();
    private List<byte[]> _control = new List<byte[]>();
    private uint _highestStreamId = 0u;
    private nuint _openedCount = 0u;
    private nuint _reserved = 0u;
    private bool _settingsReceived = false;
    private uint _peerMaxStreams = 4294967295u;
    private long _peerInitialWindow = Http2DefaultWindowSize;
    private nuint _peerMaxFrameSize = Http2DefaultMaxFrameSize;
    private bool _hasTableLimit = false;
    private nuint _tableLimit = HpackDefaultTableSize;
    private long _sendWindow = Http2DefaultWindowSize;
    private long _receiveWindow = Http2DefaultWindowSize;
    private long _connectionUnacknowledged = 0;
    private bool _goingAway = false;
    private uint _goAwayLastStreamId = Http2MaxStreamId;
    private bool _closing = false;
    private bool _goAwaySent = false;
    private bool _ended = false;
    private bool _shutDown = false;
    private HttpError _endError = HttpError.None;
    private String _endMessage = "";
    private uint _endCode = 0u;
    private TimeSpan _idleSince;
    private nuint _pingsAnswered = 0u;

    // What this end advertised.
    private long _streamWindow;
    private nuint _maxHeaderListSize;

    internal Http2Multiplexer(String key, TcpClient tcp, IStream stream, TlsStream? tls,
                              HttpConnectionPool pool, long streamWindow, nuint maxHeaderListSize)
    {
        _key = key;
        _tcp = tcp;
        _stream = stream;
        _tls = tls;
        _pool = pool;
        _frames = new Http2FrameReader(new HttpBufferedReader(stream, 65536u));
        _decoder = new HpackDecoder(HpackDefaultTableSize, maxHeaderListSize);
        _streamWindow = streamWindow;
        _maxHeaderListSize = maxHeaderListSize;
        _idleSince = Stopwatch.GetTimestamp();
    }

    internal String PoolKey => _key;

    internal TcpClient Tcp => _tcp;

    internal TlsStream? Tls => _tls;

    // ------------------------------------------------------------ starting

    /// Sends the preface, SETTINGS and the connection window's increase.
    /// False when the write failed.
    internal bool SendHttp2Preface()
    {
        var output = new Http2Buffer(128u);
        output.WriteText(s_http2ClientPreface);
        var settings = new List<uint>();
        settings.Add((uint)Http2Setting.HeaderTableSize);
        settings.Add((uint)HpackDefaultTableSize);
        settings.Add((uint)Http2Setting.EnablePush);
        settings.Add(0u);
        settings.Add((uint)Http2Setting.MaxConcurrentStreams);
        settings.Add(100u);
        settings.Add((uint)Http2Setting.InitialWindowSize);
        settings.Add((uint)_streamWindow);
        settings.Add((uint)Http2Setting.MaxHeaderListSize);
        settings.Add((uint)_maxHeaderListSize);
        WriteHttp2Settings(output, settings);
        WriteHttp2WindowUpdate(output, 0u, (uint)(Http2ConnectionReceiveWindow - Http2DefaultWindowSize));
        {
            var held = _state.Enter();
            _receiveWindow = Http2ConnectionReceiveWindow;
        }
        return WriteAllHttpBytes(_stream, output.Storage, 0u, output.Length);
    }

    /// Waits for the peer's first SETTINGS, which says how many streams it
    /// takes and how large its frames and windows are.
    ///
    /// @failure HttpError.Timeout  the deadline ran out first
    internal HttpError WaitForHttp2Settings(HttpExchange exchange)
    {
        var held = _state.Enter();
        while (!_settingsReceived && !_ended)
        {
            if (!WaitForHttp2Change(held, exchange.Deadline))
            {
                return exchange.Failure.RecordHttpFailure(HttpError.Timeout,
                    "the request timed out waiting for the server's HTTP/2 settings");
            }
        }
        if (_ended)
            return RecordHttp2EndLocked(exchange.Failure);
        return HttpError.None;
    }

    // ------------------------------------------------------------ the pool

    /// Whether it still takes new streams.
    internal bool IsHttp2Open
    {
        get
        {
            var held = _state.Enter();
            return !_ended && !_goingAway && !_closing;
        }
    }

    /// Whether it has carried a stream before the last one opened.
    internal bool HasCarriedHttp2Stream
    {
        get
        {
            var held = _state.Enter();
            return _openedCount > 1u;
        }
    }

    /// Takes a place for one more stream, within the peer's limit.
    internal bool TryReserveHttp2Stream()
    {
        var held = _state.Enter();
        if (_ended || _goingAway || _closing || !_settingsReceived)
            return false;
        if ((ulong)_reserved >= (ulong)_peerMaxStreams)
            return false;
        _reserved++;
        return true;
    }

    /// Whether it has had no stream for `timeout` or longer. A negative
    /// timeout never passes.
    internal bool HasHttp2IdleTimeoutPassed(TimeSpan now, TimeSpan timeout)
    {
        var held = _state.Enter();
        if (_reserved > 0u || timeout.IsNegative)
            return false;
        return now - _idleSince >= timeout;
    }

    /// How many PINGs from the peer have been answered.
    internal nuint PingsAnswered
    {
        get
        {
            var held = _state.Enter();
            return _pingsAnswered;
        }
    }

    // ------------------------------------------------------------ requests

    /// Opens `stream` with a HEADERS block of `fields`, pairs of name and
    /// value, ending the stream there when `endStream`. The place MUST have
    /// been reserved. A failure is recorded on the stream.
    internal bool OpenHttp2Stream(Http2Stream stream, List<String> fields, bool endStream)
    {
        bool written = false;
        {
            var writing = _writeLock.Enter();
            nuint maxFrameSize = Http2DefaultMaxFrameSize;
            bool limitTable = false;
            nuint tableLimit = 0u;
            {
                var held = _state.Enter();
                if (_ended || _goingAway || _closing || _nextStreamId > Http2MaxStreamId)
                {
                    _reserved--;
                    stream.IsUnprocessed = true;
                    stream.IsReleased = true;
                    stream.FailHttp2Stream(HttpError.ConnectionClosed,
                        "the HTTP/2 connection closed before the request was sent", 0u);
                    return false;
                }
                stream.Id = _nextStreamId;
                _nextStreamId += 2u;
                stream.SendWindow = _peerInitialWindow;
                stream.ReceiveWindow = _streamWindow;
                stream.LocalClosed = endStream;
                _streams.SetValue(stream.Id, stream);
                _highestStreamId = stream.Id;
                _openedCount++;
                maxFrameSize = _peerMaxFrameSize;
                limitTable = _hasTableLimit;
                tableLimit = _tableLimit;
                _hasTableLimit = false;
            }

            if (limitTable)
                _encoder.LimitHpackTableSize(tableLimit);
            var block = new Http2Buffer(256u);
            _encoder.BeginHpackHeaderBlock(block);
            for (nuint i = 0u; i + 1u < fields.Count; i += 2u)
                _encoder.EncodeHpackField(block, fields[i], fields[i + 1u]);
            var frames = new Http2Buffer(block.Length + 64u);
            WriteHttp2HeaderBlock(frames, stream.Id, block, endStream, maxFrameSize);
            written = WriteHttp2BufferLocked(frames);
        }
        FlushHttp2ControlFrames();
        if (!written)
            FailHttp2Transport();
        return written;
    }

    /// Sends `count` bytes of a request body as DATA, waiting for window
    /// where there is none. False when the stream or the connection failed,
    /// or the deadline ran out, which the stream then records.
    internal bool WriteHttp2Body(Http2Stream stream, HttpExchange exchange, byte[] buffer, nuint offset,
                                 nuint count)
    {
        nuint done = 0u;
        while (done < count)
        {
            nuint part = 0u;
            bool timedOut = false;
            {
                var held = _state.Enter();
                while (true)
                {
                    if (stream.IsReset || stream.Error != HttpError.None || _ended)
                        return false;
                    long window = stream.SendWindow < _sendWindow ? stream.SendWindow : _sendWindow;
                    if (window > 0)
                    {
                        part = count - done;
                        if ((long)part > window)
                            part = (nuint)window;
                        if (part > _peerMaxFrameSize)
                            part = _peerMaxFrameSize;
                        stream.SendWindow -= (long)part;
                        _sendWindow -= (long)part;
                        break;
                    }
                    if (!WaitForHttp2Change(held, exchange.Deadline))
                    {
                        ResetHttp2StreamLocked(stream, (uint)Http2ErrorCode.Cancel, HttpError.Timeout,
                                               "the request timed out waiting to send its body");
                        timedOut = true;
                        break;
                    }
                }
            }
            if (timedOut)
            {
                FlushHttp2ControlFrames();
                NotifyHttp2Pool();
                return false;
            }

            var frame = new Http2Buffer(part + Http2FrameHeaderLength);
            WriteHttp2Data(frame, stream.Id, buffer, offset + done, part, false);
            if (!SendHttp2Buffer(frame))
                return false;
            done += part;
        }
        return true;
    }

    /// Ends the request's side of the stream with an empty DATA frame.
    internal bool EndHttp2RequestBody(Http2Stream stream)
    {
        {
            var held = _state.Enter();
            if (stream.IsReset || stream.Error != HttpError.None || _ended)
                return false;
        }
        var frame = new Http2Buffer(Http2FrameHeaderLength);
        frame.WriteHttp2FrameHeader(0u, Http2FrameType.Data, Http2FlagEndStream, stream.Id);
        if (!SendHttp2Buffer(frame))
            return false;
        {
            var held = _state.Enter();
            stream.LocalClosed = true;
            if (stream.IsClosed)
                ReleaseHttp2StreamLocked(stream);
        }
        NotifyHttp2Pool();
        return true;
    }

    /// Waits for a 100 (Continue), a final head, or `milliseconds`, which
    /// ever is first.
    internal void WaitForHttp2Continue(Http2Stream stream, int milliseconds)
    {
        var deadline = new HttpDeadline(TimeSpan.FromMilliseconds((long)milliseconds));
        var held = _state.Enter();
        while (!stream.HasContinue && !stream.HasFinalHead && stream.Error == HttpError.None && !stream.IsReset)
        {
            if (!WaitForHttp2Change(held, deadline))
                return;
        }
    }

    /// Whether the final head has arrived.
    internal bool HasHttp2FinalHead(Http2Stream stream)
    {
        var held = _state.Enter();
        return stream.HasFinalHead;
    }

    /// Waits for the final head. A failure first is recorded on `exchange`.
    internal HttpError WaitForHttp2Head(Http2Stream stream, HttpExchange exchange)
    {
        HttpError error = HttpError.None;
        {
            var held = _state.Enter();
            while (!stream.HasFinalHead && stream.Error == HttpError.None)
            {
                if (!WaitForHttp2Change(held, exchange.Deadline))
                {
                    ResetHttp2StreamLocked(stream, (uint)Http2ErrorCode.Cancel, HttpError.Timeout,
                                           "the request timed out waiting for the response");
                    break;
                }
            }
            if (!stream.HasFinalHead)
            {
                error = stream.ReportHttp2Failure(exchange.Failure);
                if (stream.IsUnprocessed)
                    exchange.IsUnprocessed = true;
                if (stream.IsUnprocessed || (!stream.HasHeardFromPeer && _openedCount > 1u &&
                                             stream.Error == HttpError.ConnectionClosed))
                    exchange.IsRetryable = true;
            }
        }
        FlushHttp2ControlFrames();
        NotifyHttp2Pool();
        return error;
    }

    /// Reports the stream's failure onto `exchange`.
    internal HttpError ReportHttp2StreamFailure(Http2Stream stream, HttpExchange exchange)
    {
        var held = _state.Enter();
        if (stream.Error == HttpError.None)
            stream.FailHttp2Stream(HttpError.ConnectionClosed, "the HTTP/2 stream ended early", 0u);
        if (stream.IsUnprocessed)
        {
            exchange.IsUnprocessed = true;
            exchange.IsRetryable = true;
        }
        return stream.ReportHttp2Failure(exchange.Failure);
    }

    /// Up to `count` bytes of the body, waiting for some. Zero at the end,
    /// on a failure, or when the deadline runs out.
    internal nuint ReadHttp2Body(Http2Stream stream, HttpExchange exchange, byte[] buffer, nuint offset,
                                 nuint count)
    {
        nuint got = 0u;
        {
            var held = _state.Enter();
            while (stream.BufferedBytes == 0u && !stream.RemoteClosed && stream.Error == HttpError.None)
            {
                if (!WaitForHttp2Change(held, exchange.Deadline))
                {
                    ResetHttp2StreamLocked(stream, (uint)Http2ErrorCode.Cancel, HttpError.Timeout,
                                           "the request timed out while the body was being read");
                    break;
                }
            }
            if (stream.BufferedBytes > 0u)
            {
                got = stream.TakeHttp2Bytes(buffer, offset, count);
                CreditHttp2WindowsLocked(stream, (long)got);
            }
        }
        FlushHttp2ControlFrames();
        return got;
    }

    /// The body has been read to its end, or failed: what it ended with,
    /// the trailers copied out, and the stream reset if this end had not
    /// finished sending.
    internal HttpError FinishHttp2Body(Http2Stream stream, HttpExchange exchange, HttpResponseHeaders trailers)
    {
        HttpError error = HttpError.None;
        {
            var held = _state.Enter();
            if (stream.Error != HttpError.None)
            {
                error = stream.ReportHttp2Failure(exchange.Failure);
            }
            else if (stream.Trailers is HttpWireHeaders received)
            {
                foreach (var field in received.Fields)
                {
                    foreach (var value in field.Values)
                        trailers.AppendHttpValue(field.Name, value);
                }
            }
            if (!stream.IsReleased && !stream.LocalClosed)
            {
                ResetHttp2StreamLocked(stream, (uint)Http2ErrorCode.Cancel, HttpError.None,
                                       "the request body was not sent");
            }
        }
        FlushHttp2ControlFrames();
        NotifyHttp2Pool();
        return error;
    }

    /// Resets the stream with CANCEL unless it is over, and drops what it
    /// had buffered.
    internal void CancelHttp2Stream(Http2Stream stream, String message)
    {
        {
            var held = _state.Enter();
            if (!stream.IsReleased)
            {
                ResetHttp2StreamLocked(stream, (uint)Http2ErrorCode.Cancel, HttpError.ConnectionClosed, message);
            }
            else
            {
                CreditHttp2ConnectionLocked((long)stream.DiscardHttp2Bytes());
            }
        }
        FlushHttp2ControlFrames();
        NotifyHttp2Pool();
    }

    /// Gives back a place `TryReserveHttp2Stream` took for a stream that was
    /// never opened.
    internal void CancelHttp2Reservation()
    {
        {
            var held = _state.Enter();
            _reserved--;
            NoteHttp2IdleLocked();
        }
        NotifyHttp2Pool();
    }

    // ------------------------------------------------------------ closing

    /// Sends GOAWAY and takes no new stream. The connection ends once its
    /// streams have, and at once when it has none.
    internal void BeginHttp2Shutdown()
    {
        bool sendGoAway = false;
        bool endNow = false;
        {
            var held = _state.Enter();
            _closing = true;
            if (!_ended && !_goAwaySent)
            {
                _goAwaySent = true;
                sendGoAway = true;
            }
            endNow = _streams.IsEmpty;
            held.PulseAll();
        }
        if (sendGoAway)
        {
            var frame = new Http2Buffer(32u);
            WriteHttp2GoAway(frame, 0u, (uint)Http2ErrorCode.NoError, "");
            SendHttp2Buffer(frame);
        }
        if (endNow)
            ShutDownHttp2Transport();
        NotifyHttp2Pool();
    }

    /// Ends the connection now, whatever its streams are doing: the reader
    /// thread's read returns and it finishes.
    internal void AbortHttp2Connection()
    {
        BeginHttp2Shutdown();
        EndHttp2Connection(HttpError.ConnectionClosed, "the HTTP/2 connection was closed", 0u);
    }

    /// Stops both directions of the socket, which is what ends the reader
    /// thread's read. The socket itself is closed only once that thread has
    /// finished.
    internal void ShutDownHttp2Transport()
    {
        {
            var held = _state.Enter();
            if (_shutDown)
                return;
            _shutDown = true;
        }
        _tcp.Underlying.Shutdown(SocketShutdown.Both);
    }

    /// Closes the stream and the socket. Only once the reader has finished.
    internal void CloseHttp2Transport()
    {
        if (_tls is TlsStream tls)
            tls.Close();
        _tcp.Close();
    }

    // ------------------------------------------------------------ the reader

    /// The reader thread: frames until the connection ends, each applied to
    /// its stream.
    internal void RunHttp2Reader()
    {
        while (true)
        {
            Http2ReadStatus status = _frames.ReadHttp2Frame(Http2DefaultMaxFrameSize, out Http2Frame? read);
            if (status == Http2ReadStatus.EndOfStream || status == Http2ReadStatus.Failed)
            {
                EndHttp2ConnectionOnRead(status);
                break;
            }
            if (status == Http2ReadStatus.TooLarge)
            {
                FailHttp2Connection(Http2ErrorCode.FrameSizeError, "a frame was larger than SETTINGS_MAX_FRAME_SIZE");
                break;
            }
            var frame = (Http2Frame)read;
            if (!ProcessHttp2Frame(frame))
                break;
            FlushHttp2ControlFrames();
            NotifyHttp2Pool();
        }
        NotifyHttp2Pool();
    }

    private void EndHttp2ConnectionOnRead(Http2ReadStatus status)
    {
        bool closing = false;
        {
            var held = _state.Enter();
            closing = _closing || _shutDown;
        }
        if (closing)
        {
            EndHttp2Connection(HttpError.ConnectionClosed, "the HTTP/2 connection was closed", 0u);
            return;
        }
        if (status == Http2ReadStatus.EndOfStream)
        {
            EndHttp2Connection(HttpError.ConnectionClosed, "the server closed the HTTP/2 connection", 0u);
            return;
        }
        if (_tls is TlsStream tls)
        {
            TlsError tlsError = tls.TlsErrorCode;
            if (tlsError != TlsError.None && tlsError != TlsError.Io && tlsError != TlsError.Closed)
            {
                EndHttp2Connection(HttpError.TlsFailure, DescribeTlsError(tlsError) + " on the HTTP/2 connection", 0u);
                return;
            }
        }
        EndHttp2Connection(HttpError.ConnectionClosed, "the HTTP/2 connection failed", 0u);
    }

    /// Applies one frame. False when it ended the connection.
    private bool ProcessHttp2Frame(Http2Frame frame)
    {
        if (_headerStreamId != 0u &&
            (frame.Type != Http2FrameType.Continuation || frame.StreamId != _headerStreamId))
            return FailHttp2Connection(Http2ErrorCode.ProtocolError, "a header block was interrupted");

        bool settled = true;
        {
            var held = _state.Enter();
            settled = _settingsReceived;
        }
        if (!settled && (frame.Type != Http2FrameType.Settings || frame.HasFlag(Http2FlagAck)))
            return FailHttp2Connection(Http2ErrorCode.ProtocolError, "the server's first frame was not SETTINGS");

        switch (frame.Type)
        {
            case Http2FrameType.Data: return ProcessHttp2Data(frame);
            case Http2FrameType.Headers: return ProcessHttp2Headers(frame);
            case Http2FrameType.Priority: return ProcessHttp2Priority(frame);
            case Http2FrameType.RstStream: return ProcessHttp2RstStream(frame);
            case Http2FrameType.Settings: return ProcessHttp2Settings(frame);
            case Http2FrameType.PushPromise:
                return FailHttp2Connection(Http2ErrorCode.ProtocolError, "the server sent PUSH_PROMISE with push disabled");
            case Http2FrameType.Ping: return ProcessHttp2Ping(frame);
            case Http2FrameType.GoAway: return ProcessHttp2GoAway(frame);
            case Http2FrameType.WindowUpdate: return ProcessHttp2WindowUpdate(frame);
            case Http2FrameType.Continuation: return ProcessHttp2Continuation(frame);
        }
        // An unknown type is ignored (RFC 9113 §4.1).
        return true;
    }

    /// Ends the connection when `problem` names one; true when it is empty.
    private bool CheckHttp2Problem(String problem, Http2ErrorCode code)
    {
        if (problem.IsEmpty)
            return true;
        return FailHttp2Connection(code, problem);
    }

    /// Whether `id` names a stream that has never been opened: one the server
    /// would have to open, or one this end has not yet.
    private bool IsHttp2StreamIdleLocked(uint id) => (id & 1u) == 0u || id > _highestStreamId;

    private bool WasHttp2StreamResetLocked(uint id) => _resetStreams.Contains(id);

    /// The payload less padding, when the frame is PADDED; `start` is where
    /// the rest begins. False when the padding is as long as the payload.
    private bool RemoveHttp2Padding(Http2Frame frame, nuint start, out nuint from, out nuint length)
    {
        from = start;
        length = frame.Length - start;
        if (!frame.HasFlag(Http2FlagPadded))
            return true;
        if (frame.Length < start + 1u)
            return false;
        nuint padding = (nuint)frame.Payload[start];
        from = start + 1u;
        if (padding >= frame.Length - start)
            return false;
        length = frame.Length - start - 1u - padding;
        return true;
    }

    /// The stream a frame names, or null with `problem` set when the frame
    /// is a connection error: one on a stream never opened, or one closed
    /// by END_STREAM rather than by this end's reset.
    private Http2Stream? FindHttp2FrameStreamLocked(uint id, String what, out String problem,
                                                    out Http2ErrorCode code)
    {
        problem = "";
        code = Http2ErrorCode.NoError;
        Http2Stream? found = FindHttp2StreamLocked(id);
        if (found != null)
            return found;
        if (IsHttp2StreamIdleLocked(id))
        {
            problem = what + " on a stream never opened";
            code = Http2ErrorCode.ProtocolError;
        }
        else if (!WasHttp2StreamResetLocked(id))
        {
            problem = what + " on a closed stream";
            code = Http2ErrorCode.StreamClosed;
        }
        return null;
    }

    private bool ProcessHttp2Data(Http2Frame frame)
    {
        if (frame.StreamId == 0u)
            return FailHttp2Connection(Http2ErrorCode.ProtocolError, "DATA on stream 0");
        if (!RemoveHttp2Padding(frame, 0u, out nuint from, out nuint length))
            return FailHttp2Connection(Http2ErrorCode.ProtocolError, "DATA padded past its length");
        String problem = "";
        Http2ErrorCode code = Http2ErrorCode.NoError;
        {
            var held = _state.Enter();
            problem = ApplyHttp2DataLocked(frame, from, length, out code);
            held.PulseAll();
        }
        return CheckHttp2Problem(problem, code);
    }

    private String ApplyHttp2DataLocked(Http2Frame frame, nuint from, nuint length, out Http2ErrorCode code)
    {
        code = Http2ErrorCode.NoError;
        long size = (long)frame.Length;
        if (size > _receiveWindow)
        {
            code = Http2ErrorCode.FlowControlError;
            return "DATA past the connection's window";
        }
        _receiveWindow -= size;

        Http2Stream? found = FindHttp2FrameStreamLocked(frame.StreamId, "DATA", out String problem, out code);
        if (found == null)
        {
            CreditHttp2ConnectionLocked(size);
            return problem;
        }
        Http2Stream stream = found;
        stream.HasHeardFromPeer = true;
        if (stream.RemoteClosed)
        {
            CreditHttp2ConnectionLocked(size);
            ResetHttp2StreamLocked(stream, (uint)Http2ErrorCode.StreamClosed, HttpError.None, "DATA after END_STREAM");
            return "";
        }
        if (!stream.HasFinalHead)
        {
            CreditHttp2ConnectionLocked(size);
            ResetHttp2StreamLocked(stream, (uint)Http2ErrorCode.ProtocolError, HttpError.InvalidResponse,
                                   "the response sent DATA before its head");
            return "";
        }
        if (size > stream.ReceiveWindow)
        {
            CreditHttp2ConnectionLocked(size);
            ResetHttp2StreamLocked(stream, (uint)Http2ErrorCode.FlowControlError, HttpError.ProtocolError,
                                   "the server sent DATA past the stream's window");
            return "";
        }
        stream.ReceiveWindow -= size;
        // Padding is never read, so it is given back at once.
        long padding = size - (long)length;
        if (padding > 0)
            CreditHttp2WindowsLocked(stream, padding);

        if (length > 0u)
        {
            stream.ReceivedLength += (long)length;
            if (stream.IsHeadRequest)
            {
                CreditHttp2WindowsLocked(stream, (long)length);
            }
            else
            {
                var chunk = new byte[length];
                memcpy(&chunk[0u], &frame.Payload[from], length);
                stream.Chunks.Enqueue(chunk);
                stream.BufferedBytes += length;
            }
        }
        if (stream.DeclaredLength >= 0 && !stream.IsHeadRequest && stream.ReceivedLength > stream.DeclaredLength)
        {
            ResetHttp2StreamLocked(stream, (uint)Http2ErrorCode.ProtocolError, HttpError.InvalidResponse,
                                   "the response's body was longer than its content-length");
            return "";
        }
        if (frame.HasFlag(Http2FlagEndStream))
            CloseHttp2RemoteLocked(stream);
        return "";
    }

    /// The peer has ended its side: the body's length is checked and the
    /// stream released if this side is done too.
    private void CloseHttp2RemoteLocked(Http2Stream stream)
    {
        stream.RemoteClosed = true;
        bool bodyExpected = !stream.IsHeadRequest && stream.Status != 304 && stream.Status != 204;
        if (bodyExpected && stream.DeclaredLength >= 0 && stream.ReceivedLength != stream.DeclaredLength)
        {
            String message = "the response's body was not the length its content-length declared";
            stream.FailHttp2Stream(HttpError.InvalidResponse, message, 0u);
            if (!stream.LocalClosed)
            {
                ResetHttp2StreamLocked(stream, (uint)Http2ErrorCode.ProtocolError, HttpError.InvalidResponse,
                                       message);
                return;
            }
        }
        if (stream.IsClosed)
            ReleaseHttp2StreamLocked(stream);
    }

    private bool ProcessHttp2Headers(Http2Frame frame)
    {
        uint id = frame.StreamId;
        if (id == 0u)
            return FailHttp2Connection(Http2ErrorCode.ProtocolError, "HEADERS on stream 0");
        if (!RemoveHttp2Padding(frame, 0u, out nuint from, out nuint length))
            return FailHttp2Connection(Http2ErrorCode.ProtocolError, "HEADERS padded past its length");
        if (frame.HasFlag(Http2FlagPriority))
        {
            if (length < 5u)
                return FailHttp2Connection(Http2ErrorCode.FrameSizeError, "HEADERS too short for its priority");
            from += 5u;
            length -= 5u;
        }
        _headerBlock.Clear();
        _headerBlock.WriteArray(frame.Payload, from, length);
        _headerEndStream = frame.HasFlag(Http2FlagEndStream);
        if (!frame.HasFlag(Http2FlagEndHeaders))
        {
            _headerStreamId = id;
            return true;
        }
        return CompleteHttp2HeaderBlock(id);
    }

    private bool ProcessHttp2Continuation(Http2Frame frame)
    {
        if (_headerStreamId == 0u)
            return FailHttp2Connection(Http2ErrorCode.ProtocolError, "CONTINUATION with no header block open");
        _headerBlock.WriteArray(frame.Payload, 0u, frame.Length);
        if (_headerBlock.Length > Http2MaxHeaderBlockLength)
            return FailHttp2Connection(Http2ErrorCode.EnhanceYourCalm, "a header block past 1 MiB");
        if (!frame.HasFlag(Http2FlagEndHeaders))
            return true;
        uint id = _headerStreamId;
        _headerStreamId = 0u;
        return CompleteHttp2HeaderBlock(id);
    }

    /// Decodes a whole header block — always, so that the table stays in
    /// step — and applies it to its stream.
    private bool CompleteHttp2HeaderBlock(uint id)
    {
        var fields = new List<HpackField>();
        HpackStatus decoded = _decoder.DecodeHpackHeaderBlock(_headerBlock.Storage, 0u, _headerBlock.Length, fields);
        if (decoded == HpackStatus.Malformed)
            return FailHttp2Connection(Http2ErrorCode.CompressionError, "a header block could not be decoded");
        String problem = "";
        Http2ErrorCode code = Http2ErrorCode.NoError;
        {
            var held = _state.Enter();
            problem = ApplyHttp2HeaderBlockLocked(id, fields, decoded, out code);
            held.PulseAll();
        }
        return CheckHttp2Problem(problem, code);
    }

    private String ApplyHttp2HeaderBlockLocked(uint id, List<HpackField> fields, HpackStatus decoded,
                                               out Http2ErrorCode code)
    {
        Http2Stream? found = FindHttp2FrameStreamLocked(id, "HEADERS", out String problem, out code);
        if (found == null)
            return problem;
        Http2Stream stream = found;
        stream.HasHeardFromPeer = true;
        if (stream.RemoteClosed)
        {
            ResetHttp2StreamLocked(stream, (uint)Http2ErrorCode.StreamClosed, HttpError.None, "HEADERS after END_STREAM");
            return "";
        }
        if (decoded == HpackStatus.TooLarge)
        {
            ResetHttp2StreamLocked(stream, (uint)Http2ErrorCode.Cancel, HttpError.ResponseTooLarge,
                                   "the response's fields came to more than MaxResponseHeadersLength");
            return "";
        }

        if (!stream.HasFinalHead)
        {
            var head = new HttpWireHeaders();
            String malformed = ParseHttp2ResponseHead(fields, head, out int status);
            if (malformed.IsEmpty && status < 200 && _headerEndStream)
                malformed = "an interim response ended the stream";
            if (malformed.IsEmpty && status == 101)
                malformed = "101 (Switching Protocols) is not allowed in HTTP/2";
            long declared = -1;
            if (malformed.IsEmpty && status >= 200)
                malformed = ReadHttp2ContentLength(head, out declared);
            if (!malformed.IsEmpty)
            {
                ResetHttp2StreamLocked(stream, (uint)Http2ErrorCode.ProtocolError, HttpError.InvalidResponse,
                                       malformed);
                return "";
            }
            if (status < 200)
            {
                if (status == 100)
                    stream.HasContinue = true;
                return "";
            }
            stream.Status = status;
            stream.Head = head;
            stream.DeclaredLength = declared;
            stream.HasFinalHead = true;
        }
        else
        {
            var trailers = new HttpWireHeaders();
            String malformed = ParseHttp2Trailers(fields, trailers);
            if (malformed.IsEmpty && !_headerEndStream)
                malformed = "trailers did not end the stream";
            if (!malformed.IsEmpty)
            {
                ResetHttp2StreamLocked(stream, (uint)Http2ErrorCode.ProtocolError, HttpError.InvalidResponse,
                                       malformed);
                return "";
            }
            stream.Trailers = trailers;
        }
        if (_headerEndStream)
            CloseHttp2RemoteLocked(stream);
        return "";
    }

    private bool ProcessHttp2Priority(Http2Frame frame)
    {
        if (frame.StreamId == 0u)
            return FailHttp2Connection(Http2ErrorCode.ProtocolError, "PRIORITY on stream 0");
        if (frame.Length == 5u)
            return true;
        var held = _state.Enter();
        Http2Stream? found = FindHttp2StreamLocked(frame.StreamId);
        if (found != null)
        {
            ResetHttp2StreamLocked(found, (uint)Http2ErrorCode.FrameSizeError, HttpError.ProtocolError,
                                   "a PRIORITY frame was not five octets");
            held.PulseAll();
        }
        return true;
    }

    private bool ProcessHttp2RstStream(Http2Frame frame)
    {
        if (frame.StreamId == 0u)
            return FailHttp2Connection(Http2ErrorCode.ProtocolError, "RST_STREAM on stream 0");
        if (frame.Length != 4u)
            return FailHttp2Connection(Http2ErrorCode.FrameSizeError, "RST_STREAM was not four octets");
        String problem = "";
        Http2ErrorCode code = Http2ErrorCode.NoError;
        {
            var held = _state.Enter();
            problem = ApplyHttp2RstStreamLocked(frame.StreamId, frame.ReadHttp2Word(0u), out code);
            held.PulseAll();
        }
        return CheckHttp2Problem(problem, code);
    }

    private String ApplyHttp2RstStreamLocked(uint id, uint reason, out Http2ErrorCode code)
    {
        code = Http2ErrorCode.NoError;
        Http2Stream? found = FindHttp2StreamLocked(id);
        if (found == null)
        {
            if (!IsHttp2StreamIdleLocked(id))
                return "";
            code = Http2ErrorCode.ProtocolError;
            return "RST_STREAM on a stream never opened";
        }
        Http2Stream stream = found;
        stream.HasHeardFromPeer = true;
        stream.IsReset = true;
        if (reason == (uint)Http2ErrorCode.RefusedStream && !stream.HasFinalHead)
        {
            stream.IsUnprocessed = true;
            stream.FailHttp2Stream(HttpError.ConnectionClosed, "the server refused the stream (REFUSED_STREAM)",
                                   reason);
        }
        else if (reason != (uint)Http2ErrorCode.NoError || !stream.RemoteClosed)
        {
            stream.FailHttp2Stream(HttpError.ProtocolError,
                                   "the server reset the stream with " + DescribeHttp2ErrorCode(reason), reason);
        }
        ReleaseHttp2StreamLocked(stream);
        if (stream.Error != HttpError.None)
            CreditHttp2ConnectionLocked((long)stream.DiscardHttp2Bytes());
        return "";
    }

    private bool ProcessHttp2Settings(Http2Frame frame)
    {
        if (frame.StreamId != 0u)
            return FailHttp2Connection(Http2ErrorCode.ProtocolError, "SETTINGS on a stream");
        if (frame.HasFlag(Http2FlagAck))
        {
            if (frame.Length != 0u)
                return FailHttp2Connection(Http2ErrorCode.FrameSizeError, "a SETTINGS acknowledgement with a payload");
            return true;
        }
        if (frame.Length % 6u != 0u)
            return FailHttp2Connection(Http2ErrorCode.FrameSizeError, "SETTINGS not a multiple of six octets");
        String problem = "";
        Http2ErrorCode code = Http2ErrorCode.NoError;
        {
            var held = _state.Enter();
            problem = ApplyHttp2SettingsLocked(frame, out code);
            held.PulseAll();
        }
        return CheckHttp2Problem(problem, code);
    }

    private String ApplyHttp2SettingsLocked(Http2Frame frame, out Http2ErrorCode code)
    {
        code = Http2ErrorCode.NoError;
        for (nuint at = 0u; at < frame.Length; at += 6u)
        {
            uint setting = ((uint)frame.Payload[at] << 8) | (uint)frame.Payload[at + 1u];
            uint value = frame.ReadHttp2Word(at + 2u);
            switch (setting)
            {
                case 1u:
                    _hasTableLimit = true;
                    _tableLimit = (nuint)value;
                    break;
                case 2u:
                    if (value != 0u)
                    {
                        code = Http2ErrorCode.ProtocolError;
                        return "the server set ENABLE_PUSH";
                    }
                    break;
                case 3u:
                    _peerMaxStreams = value;
                    break;
                case 4u:
                {
                    if ((long)value > Http2MaxWindowSize)
                    {
                        code = Http2ErrorCode.FlowControlError;
                        return "INITIAL_WINDOW_SIZE past 2^31 - 1";
                    }
                    long delta = (long)value - _peerInitialWindow;
                    _peerInitialWindow = (long)value;
                    foreach (var stream in _streams.GetValues())
                    {
                        stream.SendWindow += delta;
                        if (stream.SendWindow > Http2MaxWindowSize)
                        {
                            code = Http2ErrorCode.FlowControlError;
                            return "INITIAL_WINDOW_SIZE took a stream's window past 2^31 - 1";
                        }
                    }
                    break;
                }
                case 5u:
                    if ((nuint)value < Http2DefaultMaxFrameSize || (nuint)value > Http2MaxAllowedFrameSize)
                    {
                        code = Http2ErrorCode.ProtocolError;
                        return "MAX_FRAME_SIZE out of range";
                    }
                    _peerMaxFrameSize = (nuint)value;
                    break;
            }
        }
        _settingsReceived = true;
        var ack = new Http2Buffer(Http2FrameHeaderLength);
        WriteHttp2SettingsAck(ack);
        _control.Add(ack.ToArray());
        return "";
    }

    private bool ProcessHttp2Ping(Http2Frame frame)
    {
        if (frame.StreamId != 0u)
            return FailHttp2Connection(Http2ErrorCode.ProtocolError, "PING on a stream");
        if (frame.Length != 8u)
            return FailHttp2Connection(Http2ErrorCode.FrameSizeError, "PING was not eight octets");
        if (frame.HasFlag(Http2FlagAck))
            return true;
        var answer = new Http2Buffer(Http2FrameHeaderLength + 8u);
        WriteHttp2Ping(answer, frame.Payload, true);
        var held = _state.Enter();
        _control.Add(answer.ToArray());
        _pingsAnswered++;
        return true;
    }

    private bool ProcessHttp2GoAway(Http2Frame frame)
    {
        if (frame.StreamId != 0u)
            return FailHttp2Connection(Http2ErrorCode.ProtocolError, "GOAWAY on a stream");
        if (frame.Length < 8u)
            return FailHttp2Connection(Http2ErrorCode.FrameSizeError, "GOAWAY shorter than eight octets");
        uint lastStreamId = frame.ReadHttp2Word(0u) & Http2MaxStreamId;
        uint code = frame.ReadHttp2Word(4u);

        bool empty = false;
        {
            var held = _state.Enter();
            _goingAway = true;
            if (lastStreamId < _goAwayLastStreamId)
                _goAwayLastStreamId = lastStreamId;
            if (code != (uint)Http2ErrorCode.NoError)
                _endCode = code;
            foreach (var stream in _streams.GetValues())
            {
                if (stream.Id <= _goAwayLastStreamId)
                    continue;
                stream.IsUnprocessed = true;
                stream.FailHttp2Stream(HttpError.ConnectionClosed,
                                       "the server sent GOAWAY before it processed the request", 0u);
                stream.IsReset = true;
                ReleaseHttp2StreamLocked(stream);
            }
            empty = _streams.IsEmpty;
            held.PulseAll();
        }
        if (empty)
            ShutDownHttp2Transport();
        return true;
    }

    private bool ProcessHttp2WindowUpdate(Http2Frame frame)
    {
        if (frame.Length != 4u)
            return FailHttp2Connection(Http2ErrorCode.FrameSizeError, "WINDOW_UPDATE was not four octets");
        String problem = "";
        Http2ErrorCode code = Http2ErrorCode.NoError;
        {
            var held = _state.Enter();
            problem = ApplyHttp2WindowUpdateLocked(frame.StreamId, (long)(frame.ReadHttp2Word(0u) & Http2MaxStreamId),
                                                   out code);
            held.PulseAll();
        }
        return CheckHttp2Problem(problem, code);
    }

    private String ApplyHttp2WindowUpdateLocked(uint id, long increment, out Http2ErrorCode code)
    {
        code = Http2ErrorCode.NoError;
        if (id == 0u)
        {
            if (increment == 0)
            {
                code = Http2ErrorCode.ProtocolError;
                return "a WINDOW_UPDATE of zero";
            }
            _sendWindow += increment;
            if (_sendWindow > Http2MaxWindowSize)
            {
                code = Http2ErrorCode.FlowControlError;
                return "the connection's window past 2^31 - 1";
            }
            return "";
        }

        Http2Stream? found = FindHttp2StreamLocked(id);
        if (found == null)
        {
            if (!IsHttp2StreamIdleLocked(id))
                return "";
            code = Http2ErrorCode.ProtocolError;
            return "WINDOW_UPDATE on a stream never opened";
        }
        Http2Stream stream = found;
        if (increment == 0)
        {
            ResetHttp2StreamLocked(stream, (uint)Http2ErrorCode.ProtocolError, HttpError.ProtocolError,
                                   "the server sent a WINDOW_UPDATE of zero");
            return "";
        }
        stream.SendWindow += increment;
        if (stream.SendWindow > Http2MaxWindowSize)
        {
            ResetHttp2StreamLocked(stream, (uint)Http2ErrorCode.FlowControlError, HttpError.ProtocolError,
                                   "the server took a stream's window past 2^31 - 1");
        }
        return "";
    }

    // ------------------------------------------------------------ failing

    /// A connection error (RFC 9113 §5.4.1): GOAWAY with `code`, then the
    /// end. Answers false, for the reader to stop.
    private bool FailHttp2Connection(Http2ErrorCode code, String message)
    {
        bool send = false;
        uint lastStreamId = 0u;
        {
            var held = _state.Enter();
            if (!_goAwaySent && !_ended)
            {
                _goAwaySent = true;
                send = true;
            }
        }
        if (send)
        {
            var frame = new Http2Buffer(64u);
            WriteHttp2GoAway(frame, lastStreamId, (uint)code, message);
            SendHttp2GoAwayPatiently(frame);
        }
        EndHttp2Connection(HttpError.ProtocolError, "HTTP/2 " + DescribeHttp2ErrorCode((uint)code) + ": " + message,
                           (uint)code);
        return false;
    }

    /// Writes a GOAWAY from the reader thread, waiting a little for the
    /// write lock rather than for ever.
    private void SendHttp2GoAwayPatiently(Http2Buffer frame)
    {
        for (int waited = 0; waited <= Http2GoAwayWaitMilliseconds; waited += 10)
        {
            if (TryWriteHttp2Buffer(frame))
                return;
            Sleep(10u);
        }
    }

    private bool TryWriteHttp2Buffer(Http2Buffer frame)
    {
        Guard<int>? writing = _writeLock.TryEnter();
        if (writing == null)
            return false;
        WriteHttp2BufferLocked(frame);
        return true;
    }

    /// Ends the connection: every stream not yet answered in full fails with
    /// `error`, and the socket is shut down.
    internal void EndHttp2Connection(HttpError error, String message, uint code)
    {
        {
            var held = _state.Enter();
            if (_ended)
                return;
            _ended = true;
            _endError = error;
            _endMessage = message;
            if (code != 0u)
                _endCode = code;
            var streams = _streams.GetValues();
            foreach (var stream in streams)
            {
                if (!stream.RemoteClosed || stream.Error != HttpError.None)
                {
                    if (!stream.HasHeardFromPeer && _goingAway && stream.Id > _goAwayLastStreamId)
                        stream.IsUnprocessed = true;
                    stream.FailHttp2Stream(error, message, code);
                }
                stream.IsReset = true;
                ReleaseHttp2StreamLocked(stream);
            }
            _control.Clear();
            held.PulseAll();
        }
        ShutDownHttp2Transport();
        NotifyHttp2Pool();
    }

    private HttpError RecordHttp2EndLocked(HttpFailure failure)
    {
        if (_endCode != 0u)
            failure.ProtocolErrorCode = (long)_endCode;
        HttpError error = _endError == HttpError.None ? HttpError.ConnectionClosed : _endError;
        return failure.RecordHttpFailure(error, _endMessage.IsEmpty ? "the HTTP/2 connection closed" : _endMessage);
    }

    /// A write failed: the socket goes, and the reader ends every stream.
    private void FailHttp2Transport() =>
        EndHttp2Connection(HttpError.ConnectionClosed, "the HTTP/2 connection failed while a request was sent", 0u);

    // ------------------------------------------------------------ streams

    private Http2Stream? FindHttp2StreamLocked(uint id)
    {
        if (_streams.TryGetValue(id) is Some found)
            return found.Value;
        return null;
    }

    /// Resets `stream` with `code` unless it is over already, failing it
    /// with `error` unless that is `None`, and gives back what it held.
    private void ResetHttp2StreamLocked(Http2Stream stream, uint code, HttpError error, String message)
    {
        if (error != HttpError.None)
            stream.FailHttp2Stream(error, message, 0u);
        if (!stream.IsReleased && stream.Id != 0u && !_ended)
        {
            var frame = new Http2Buffer(16u);
            WriteHttp2RstStream(frame, stream.Id, code);
            _control.Add(frame.ToArray());
            _resetStreams.Add(stream.Id);
            if (_resetStreams.Count > Http2RememberedResets)
                _resetStreams.RemoveAt(0u);
        }
        stream.IsReset = true;
        if (error != HttpError.None)
            CreditHttp2ConnectionLocked((long)stream.DiscardHttp2Bytes());
        ReleaseHttp2StreamLocked(stream);
    }

    /// Takes the stream out of the table and gives its place back.
    private void ReleaseHttp2StreamLocked(Http2Stream stream)
    {
        if (stream.IsReleased)
            return;
        stream.IsReleased = true;
        if (stream.Id != 0u)
            _streams.Remove(stream.Id);
        _reserved--;
        NoteHttp2IdleLocked();
        if ((_goingAway || _closing) && _streams.IsEmpty && !_shutDown)
            _control.Add(new byte[0u]);
    }

    private void NoteHttp2IdleLocked()
    {
        if (_reserved == 0u)
            _idleSince = Stopwatch.GetTimestamp();
    }

    /// Counts `count` bytes read out of `stream`, and queues WINDOW_UPDATEs
    /// once half a window has been read.
    private void CreditHttp2WindowsLocked(Http2Stream stream, long count)
    {
        stream.UnacknowledgedBytes += count;
        if (!stream.RemoteClosed && !stream.IsReset && stream.UnacknowledgedBytes >= _streamWindow / 2)
        {
            var frame = new Http2Buffer(16u);
            WriteHttp2WindowUpdate(frame, stream.Id, (uint)stream.UnacknowledgedBytes);
            _control.Add(frame.ToArray());
            stream.ReceiveWindow += stream.UnacknowledgedBytes;
            stream.UnacknowledgedBytes = 0;
        }
        CreditHttp2ConnectionLocked(count);
    }

    private void CreditHttp2ConnectionLocked(long count)
    {
        if (count <= 0 || _ended)
            return;
        _connectionUnacknowledged += count;
        if (_connectionUnacknowledged >= Http2ConnectionReceiveWindow / 2)
        {
            var frame = new Http2Buffer(16u);
            WriteHttp2WindowUpdate(frame, 0u, (uint)_connectionUnacknowledged);
            _control.Add(frame.ToArray());
            _receiveWindow += _connectionUnacknowledged;
            _connectionUnacknowledged = 0;
        }
    }

    // ------------------------------------------------------------ writing

    /// Writes `frames` under the write lock, after anything queued.
    private bool SendHttp2Buffer(Http2Buffer frames)
    {
        bool written = false;
        {
            var writing = _writeLock.Enter();
            written = WriteHttp2BufferLocked(frames);
        }
        FlushHttp2ControlFrames();
        if (!written)
            FailHttp2Transport();
        return written;
    }

    /// Writes what is queued, then `frames`. The caller holds the write lock.
    private bool WriteHttp2BufferLocked(Http2Buffer frames)
    {
        if (!WriteQueuedHttp2ControlFrames())
            return false;
        if (frames.Length == 0u)
            return true;
        if (!WriteAllHttpBytes(_stream, frames.Storage, 0u, frames.Length))
            return false;
        _stream.Flush();
        return true;
    }

    /// Writes every queued control frame. The caller holds the write lock.
    private bool WriteQueuedHttp2ControlFrames()
    {
        var output = new Http2Buffer(64u);
        bool shutDown = false;
        {
            var held = _state.Enter();
            if (_ended)
            {
                _control.Clear();
                return false;
            }
            foreach (var frame in _control)
            {
                if (frame.Length == 0u)
                    shutDown = true;
                else
                    output.WriteArray(frame, 0u, frame.Length);
            }
            _control.Clear();
        }
        bool written = true;
        if (output.Length > 0u)
        {
            written = WriteAllHttpBytes(_stream, output.Storage, 0u, output.Length);
            if (written)
                _stream.Flush();
        }
        if (shutDown)
            ShutDownHttp2Transport();
        return written;
    }

    /// Writes the queued control frames if the write lock is free. When it
    /// is not, its holder writes them on its way out.
    internal void FlushHttp2ControlFrames()
    {
        while (true)
        {
            {
                var held = _state.Enter();
                if (_control.IsEmpty)
                    return;
            }
            if (!TryWriteHttp2Buffer(new Http2Buffer(0u)))
                return;
        }
    }

    /// Wakes whoever in the pool waits for a stream or a connection.
    private void NotifyHttp2Pool()
    {
        HttpConnectionPool? pool = _pool;
        if (pool != null)
            pool.PulseHttpWaiters();
    }
}

/// Waits on `held` until something changes or the deadline passes. False
/// when it has passed.
internal bool WaitForHttp2Change(MonitorGuard<int> held, HttpDeadline deadline)
{
    if (!deadline.IsBounded)
    {
        held.Wait();
        return true;
    }
    long left = deadline.RemainingMilliseconds;
    if (left <= 0)
        return false;
    held.WaitFor((ulong)left);
    return true;
}
