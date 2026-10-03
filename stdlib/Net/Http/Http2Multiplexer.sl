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

/// How many streams the peer ended that this end remembers, so that a frame
/// after END_STREAM is still refused. A frame on any other stream this end
/// opened and no longer has is dropped: the peer may have sent it before it
/// saw this end's RST_STREAM.
internal const nuint Http2RememberedEndedStreams = 128u;

/// How long a GOAWAY waits for the write turn, and then for its write.
internal const int Http2GoAwayWaitMilliseconds = 1000;

/// How long a write of queued control frames may take when no request's
/// deadline is shorter. A peer that reads nothing for this long is gone.
internal const int Http2ControlWriteMilliseconds = 5000;

/// How long a request at or past its deadline still spends writing the
/// control frames queued, its own RST_STREAM among them.
internal const int Http2LateFlushMilliseconds = 100;

/// How many SETTINGS and PING acknowledgements may wait to be written, and
/// how many bytes of control frames in all. Past either the peer is sending
/// faster than it reads, and the connection ends with ENHANCE_YOUR_CALM
/// (RFC 9113 section 10.5).
internal const nuint Http2MaxPendingAcks = 1000u;
internal const nuint Http2MaxPendingControlBytes = 65536u;

/// The frames and streams of one HTTP/2 connection (RFC 9113), shared by the
/// thread that reads it and the threads that send requests on it.
///
/// **A write turn and a lock.** The write turn serialises what goes on the
/// wire, and with it the HPACK encoder and the next stream identifier, since
/// blocks MUST arrive in the order they were encoded and identifiers MUST
/// rise. `_state` guards every stream and every window, and the turn itself:
/// taking the turn is a wait on `_state` bounded by the caller's deadline,
/// and the turn is held without `_state` while the write runs.
///
/// **Every write is bounded.** The holder sets the socket's send timeout from
/// its deadline before it writes. A write that fails or times out part-way
/// ends the connection, since a partial frame corrupts it.
///
/// **The reader thread never waits for the turn.** What it has to send, a
/// SETTINGS ack, a PING ack, a WINDOW_UPDATE, a RST_STREAM, goes on a queue,
/// and whichever thread next holds the turn writes it. Were the reader to
/// wait, a writer stuck behind a peer that is itself waiting to write would
/// never be relieved. The queue is capped; see `Http2MaxPendingAcks`.
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

    // Under the write turn.
    private HpackEncoder _encoder = new HpackEncoder(HpackDefaultTableSize);

    // Under _state.
    private Monitor<int> _state = new Monitor<int>(0);
    private bool _writing = false;
    private Dictionary<uint, Http2Stream> _streams = new Dictionary<uint, Http2Stream>();
    private List<uint> _endedStreams = new List<uint>();
    private Http2Buffer _control = new Http2Buffer(64u);
    private Dictionary<uint, long> _windowUpdates = new Dictionary<uint, long>();
    private nuint _pendingAcks = 0u;
    private bool _controlOverflowed = false;
    private bool _shutDownQueued = false;
    private uint _highestStreamId = 0u;
    private nuint _openedCount = 0u;
    private nuint _reserved = 0u;
    private nuint _unopened = 0u;
    private bool _settingsReceived = false;
    private uint _peerMaxStreams = 4294967295u;
    private long _peerInitialWindow = Http2DefaultWindowSize;
    private nuint _peerMaxFrameSize = Http2DefaultMaxFrameSize;
    private bool _hasTableLimit = false;
    private nuint _tableLimit = HpackDefaultTableSize;
    private nuint _tableMinimum = HpackDefaultTableSize;

    // Under _state, and changed only under the write turn as well.
    private uint _nextStreamId = 1u;
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
        WriteHttp2WindowUpdate(output, 0u,
                               (uint)(Http2ConnectionReceiveWindow - Http2DefaultWindowSize));
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

    /// Whether it still takes new streams: not closing, and with stream ids
    /// left to give them.
    internal bool IsHttp2Open
    {
        get
        {
            var held = _state.Enter();
            return !_ended && !_goingAway && !_closing && RemainingHttp2StreamIds > 0u;
        }
    }

    /// Stream ids not yet used. The caller holds `_state`.
    private nuint RemainingHttp2StreamIds =>
        _nextStreamId > Http2MaxStreamId ? 0u : (nuint)((Http2MaxStreamId - _nextStreamId) / 2u + 1u);

    /// Whether it has carried a stream before the last one opened.
    internal bool HasCarriedHttp2Stream
    {
        get
        {
            var held = _state.Enter();
            return _openedCount > 1u;
        }
    }

    /// Takes a place for one more stream, within the peer's limit and the
    /// stream ids left.
    internal bool TryReserveHttp2Stream()
    {
        var held = _state.Enter();
        if (_ended || _goingAway || _closing || !_settingsReceived)
            return false;
        if ((ulong)_reserved >= (ulong)_peerMaxStreams)
            return false;
        if (_unopened >= RemainingHttp2StreamIds)
            return false;
        _reserved++;
        _unopened++;
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
    internal bool OpenHttp2Stream(Http2Stream stream, List<String> fields, bool endStream,
                                  HttpDeadline deadline)
    {
        Http2WriteOutcome outcome = Http2WriteOutcome.Expired;
        bool exhausted = false;
        {
            Http2WriteTurn? turn = TakeHttp2WriteTurn(deadline, out outcome);
            if (turn != null)
                outcome = OpenHttp2StreamLocked(stream, fields, endStream, deadline, out exhausted);
        }
        FlushHttp2ControlFrames(deadline);
        if (exhausted)
            BeginHttp2Shutdown();
        if (outcome == Http2WriteOutcome.Written)
            return true;
        if (outcome == Http2WriteOutcome.Dropped)
            return false;

        bool opened = true;
        {
            var held = _state.Enter();
            if (stream.Id == 0u && !stream.IsReleased)
            {
                opened = false;
                _reserved--;
                _unopened--;
                NoteHttp2IdleLocked();
                stream.IsReleased = true;
                if (outcome == Http2WriteOutcome.Expired)
                {
                    stream.FailHttp2Stream(HttpError.Timeout,
                                           "the request timed out before it was sent", 0u);
                }
                else
                {
                    stream.IsUnprocessed = true;
                    stream.FailHttp2Stream(HttpError.ConnectionClosed,
                        "the HTTP/2 connection closed before the request was sent", 0u);
                }
            }
        }
        if (opened)
            FailHttp2StreamWrite(stream, outcome, deadline, "the request timed out sending its head");
        else if (outcome == Http2WriteOutcome.Failed)
            FailHttp2Transport(deadline);
        NotifyHttp2Pool();
        return false;
    }

    /// Opens the stream and writes its head. The caller holds the write turn.
    private Http2WriteOutcome OpenHttp2StreamLocked(Http2Stream stream, List<String> fields,
                                                    bool endStream,
                                                    HttpDeadline deadline,
                                                    out bool exhausted)
    {
        exhausted = false;
        // What is queued goes first, so that a SETTINGS ack never precedes a
        // block encoded under the table size that SETTINGS replaced.
        Http2WriteOutcome flushed = WriteHttp2FramesLocked(new Http2Buffer(0u), null, deadline);
        if (flushed != Http2WriteOutcome.Written)
            return flushed;

        nuint maxFrameSize = Http2DefaultMaxFrameSize;
        bool limitTable = false;
        nuint tableLimit = 0u;
        nuint tableMinimum = 0u;
        {
            var held = _state.Enter();
            if (_ended || _goingAway || _closing || _nextStreamId > Http2MaxStreamId)
            {
                _reserved--;
                _unopened--;
                NoteHttp2IdleLocked();
                stream.IsUnprocessed = true;
                stream.IsReleased = true;
                stream.FailHttp2Stream(HttpError.ConnectionClosed,
                    "the HTTP/2 connection closed before the request was sent", 0u);
                return Http2WriteOutcome.Dropped;
            }
            stream.Id = _nextStreamId;
            _nextStreamId += 2u;
            _unopened--;
            exhausted = _nextStreamId > Http2MaxStreamId;
            stream.SendWindow = _peerInitialWindow;
            stream.ReceiveWindow = _streamWindow;
            stream.LocalClosed = endStream;
            _streams.SetValue(stream.Id, stream);
            _highestStreamId = stream.Id;
            _openedCount++;
            maxFrameSize = _peerMaxFrameSize;
            limitTable = _hasTableLimit;
            tableLimit = _tableLimit;
            tableMinimum = _tableMinimum;
            _hasTableLimit = false;
        }

        if (limitTable)
        {
            // The smallest size since the last block first, so that the
            // peer's decoder evicts what that size did (RFC 7541 section 4.2).
            if (tableMinimum < tableLimit)
                _encoder.LimitHpackTableSize(tableMinimum);
            _encoder.LimitHpackTableSize(tableLimit);
        }
        var block = new Http2Buffer(256u);
        _encoder.BeginHpackHeaderBlock(block);
        for (nuint i = 0u; i + 1u < fields.Count; i += 2u)
            _encoder.EncodeHpackField(block, fields[i], fields[i + 1u]);
        var frames = new Http2Buffer(block.Length + 64u);
        WriteHttp2HeaderBlock(frames, stream.Id, block, endStream, maxFrameSize);
        // The block is encoded, so it MUST be written whatever the deadline
        // says: a block not sent leaves the peer's table behind this one.
        if (!WriteHttp2BytesLocked(frames, deadline))
            return Http2WriteOutcome.Failed;
        return Http2WriteOutcome.Written;
    }

    /// Sends `count` bytes of a request body as DATA, waiting for window
    /// where there is none. False when the stream or the connection failed,
    /// or the deadline ran out, which the stream then records.
    internal bool WriteHttp2Body(Http2Stream stream, HttpExchange exchange, byte[] buffer,
                                 nuint offset,
                                 nuint count)
    {
        HttpDeadline deadline = exchange.Deadline;
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
                    if (deadline.HasExpired)
                    {
                        timedOut = true;
                        break;
                    }
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
                    if (!WaitForHttp2Change(held, deadline))
                    {
                        timedOut = true;
                        break;
                    }
                }
                if (timedOut)
                {
                    ResetHttp2StreamLocked(stream, Http2ErrorCode.Cancel, HttpError.Timeout,
                                           "the request timed out sending its body");
                }
            }
            if (timedOut)
            {
                FlushHttp2ControlFrames(deadline);
                NotifyHttp2Pool();
                return false;
            }

            var frame = new Http2Buffer(part + Http2FrameHeaderLength);
            WriteHttp2Data(frame, stream.Id, buffer, offset + done, part, false);
            Http2WriteOutcome outcome = SendHttp2Frames(frame, stream, deadline);
            if (outcome != Http2WriteOutcome.Written)
            {
                if (outcome != Http2WriteOutcome.Failed)
                {
                    var held = _state.Enter();
                    // Never sent, so the connection's window is not spent.
                    _sendWindow += (long)part;
                }
                FailHttp2StreamWrite(stream, outcome, deadline, "the request timed out sending its body");
                return false;
            }
            done += part;
        }
        return true;
    }

    /// Ends the request's side of the stream with an empty DATA frame.
    internal bool EndHttp2RequestBody(Http2Stream stream, HttpDeadline deadline)
    {
        {
            var held = _state.Enter();
            if (stream.IsReset || stream.Error != HttpError.None || _ended)
                return false;
        }
        var frame = new Http2Buffer(Http2FrameHeaderLength);
        frame.WriteHttp2FrameHeader(0u, Http2FrameType.Data, Http2FlagEndStream, stream.Id);
        Http2WriteOutcome outcome = SendHttp2Frames(frame, stream, deadline);
        if (outcome != Http2WriteOutcome.Written)
        {
            FailHttp2StreamWrite(stream, outcome, deadline, "the request timed out ending its body");
            return false;
        }
        {
            var held = _state.Enter();
            stream.LocalClosed = true;
            if (stream.IsClosed)
                ReleaseHttp2StreamLocked(stream);
        }
        NotifyHttp2Pool();
        return true;
    }

    /// A write for `stream` did not happen. When the deadline ran out the
    /// stream fails with Timeout: reset, if nothing was written, and with the
    /// connection ended, if the write failed part-way. `Dropped` needs
    /// nothing, since the stream already says why.
    private void FailHttp2StreamWrite(Http2Stream stream, Http2WriteOutcome outcome,
                                      HttpDeadline deadline,
                                      String message)
    {
        if (outcome == Http2WriteOutcome.Dropped || outcome == Http2WriteOutcome.Written)
            return;
        {
            var held = _state.Enter();
            if (outcome == Http2WriteOutcome.Expired)
                ResetHttp2StreamLocked(stream, Http2ErrorCode.Cancel, HttpError.Timeout, message);
            else if (HasHttp2WriteTimedOut(deadline))
                stream.FailHttp2Stream(HttpError.Timeout, message, 0u);
            held.PulseAll();
        }
        if (outcome == Http2WriteOutcome.Failed)
            FailHttp2Transport(deadline);
        else
            FlushHttp2ControlFrames(deadline);
        NotifyHttp2Pool();
    }

    /// Whether a failed write failed because its time ran out.
    private bool HasHttp2WriteTimedOut(HttpDeadline deadline) =>
        deadline.HasExpired || _tcp.SocketErrorCode == SocketError.TimedOut;

    /// Waits for a 100 (Continue), a final head, or `milliseconds`, which
    /// ever is first.
    internal void WaitForHttp2Continue(Http2Stream stream, int milliseconds)
    {
        var deadline = new HttpDeadline(TimeSpan.FromMilliseconds((long)milliseconds));
        var held = _state.Enter();
        while (!stream.HasContinue && !stream.HasFinalHead && stream.Error == HttpError.None
               && !stream.IsReset)
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
                    ResetHttp2StreamLocked(stream, Http2ErrorCode.Cancel, HttpError.Timeout,
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
        FlushHttp2ControlFrames(exchange.Deadline);
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
    internal nuint ReadHttp2Body(Http2Stream stream, HttpExchange exchange, byte[] buffer,
                                 nuint offset,
                                 nuint count)
    {
        nuint got = 0u;
        {
            var held = _state.Enter();
            while (stream.BufferedBytes == 0u && !stream.RemoteClosed
                   && stream.Error == HttpError.None)
            {
                if (!WaitForHttp2Change(held, exchange.Deadline))
                {
                    ResetHttp2StreamLocked(stream, Http2ErrorCode.Cancel, HttpError.Timeout,
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
        FlushHttp2ControlFrames(exchange.Deadline);
        return got;
    }

    /// The body has been read to its end, or failed: what it ended with,
    /// the trailers copied out, and the stream reset if this end had not
    /// finished sending.
    internal HttpError FinishHttp2Body(Http2Stream stream, HttpExchange exchange,
                                       HttpResponseHeaders trailers)
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
                ResetHttp2StreamLocked(stream, Http2ErrorCode.Cancel, HttpError.None,
                                       "the request body was not sent");
            }
        }
        FlushHttp2ControlFrames(exchange.Deadline);
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
                ResetHttp2StreamLocked(stream, Http2ErrorCode.Cancel, HttpError.ConnectionClosed,
                                       message);
            }
            else
            {
                CreditHttp2ConnectionLocked((long)stream.DiscardHttp2Bytes());
            }
        }
        FlushHttp2ControlFrames(null);
        NotifyHttp2Pool();
    }

    /// Gives back a place `TryReserveHttp2Stream` took for a stream that was
    /// never opened.
    internal void CancelHttp2Reservation()
    {
        {
            var held = _state.Enter();
            _reserved--;
            _unopened--;
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
            var deadline = new HttpDeadline(TimeSpan.FromMilliseconds((long)Http2GoAwayWaitMilliseconds));
            if (SendHttp2Frames(frame, null, deadline) == Http2WriteOutcome.Failed)
                FailHttp2Transport(deadline);
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
            Http2ReadStatus status = _frames.ReadHttp2Frame(Http2DefaultMaxFrameSize,
                                                            out Http2Frame? read);
            if (status == Http2ReadStatus.EndOfStream || status == Http2ReadStatus.Failed)
            {
                EndHttp2ConnectionOnRead(status);
                break;
            }
            if (status == Http2ReadStatus.TooLarge)
            {
                FailHttp2Connection(Http2ErrorCode.FrameSizeError,
                                    "a frame was larger than SETTINGS_MAX_FRAME_SIZE");
                break;
            }
            var frame = (Http2Frame)read;
            if (!ProcessHttp2Frame(frame))
                break;
            if (!FlushHttp2ControlFrames(null))
                break;
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
            EndHttp2Connection(HttpError.ConnectionClosed,
                               "the server closed the HTTP/2 connection", 0u);
            return;
        }
        if (_tls is TlsStream tls)
        {
            TlsError tlsError = tls.TlsErrorCode;
            if (tlsError != TlsError.None && tlsError != TlsError.Io && tlsError != TlsError.Closed)
            {
                EndHttp2Connection(HttpError.TlsFailure, DescribeTlsError(tlsError)
                                   + " on the HTTP/2 connection", 0u);
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
            return FailHttp2Connection(Http2ErrorCode.ProtocolError,
                                       "a header block was interrupted");

        bool settled = true;
        {
            var held = _state.Enter();
            settled = _settingsReceived;
        }
        if (!settled && (frame.Type != Http2FrameType.Settings || frame.HasFlag(Http2FlagAck)))
            return FailHttp2Connection(Http2ErrorCode.ProtocolError,
                                       "the server's first frame was not SETTINGS");

        switch (frame.Type)
        {
            case Http2FrameType.Data: return ProcessHttp2Data(frame);
            case Http2FrameType.Headers: return ProcessHttp2Headers(frame);
            case Http2FrameType.Priority: return ProcessHttp2Priority(frame);
            case Http2FrameType.RstStream: return ProcessHttp2RstStream(frame);
            case Http2FrameType.Settings: return ProcessHttp2Settings(frame);
            case Http2FrameType.PushPromise:
                return FailHttp2Connection(Http2ErrorCode.ProtocolError,
                                           "the server sent PUSH_PROMISE with push disabled");
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
    /// is a connection error: one on a stream never opened, or on one the
    /// peer recently ended. Null with no problem means the frame is dropped:
    /// its stream was reset, or ended too long ago to be remembered.
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
        else if (_endedStreams.Contains(id))
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

    private String ApplyHttp2DataLocked(Http2Frame frame, nuint from, nuint length,
                                        out Http2ErrorCode code)
    {
        code = Http2ErrorCode.NoError;
        long size = (long)frame.Length;
        if (size > _receiveWindow)
        {
            code = Http2ErrorCode.FlowControlError;
            return "DATA past the connection's window";
        }
        _receiveWindow -= size;

        Http2Stream? found = FindHttp2FrameStreamLocked(frame.StreamId, "DATA", out String problem,
                                                        out code);
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
            ResetHttp2StreamLocked(stream, Http2ErrorCode.StreamClosed, HttpError.None,
                                   "DATA after END_STREAM");
            return "";
        }
        if (!stream.HasFinalHead)
        {
            CreditHttp2ConnectionLocked(size);
            ResetHttp2StreamLocked(stream, Http2ErrorCode.ProtocolError, HttpError.InvalidResponse,
                                   "the response sent DATA before its head");
            return "";
        }
        if (size > stream.ReceiveWindow)
        {
            CreditHttp2ConnectionLocked(size);
            ResetHttp2StreamLocked(stream, Http2ErrorCode.FlowControlError, HttpError.ProtocolError,
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
            else if (length == frame.Length)
            {
                stream.Chunks.Enqueue(frame.Payload);
                stream.BufferedBytes += length;
            }
            else
            {
                var chunk = new byte[length];
                memcpy(&chunk[0u], &frame.Payload[from], length);
                stream.Chunks.Enqueue(chunk);
                stream.BufferedBytes += length;
            }
        }
        if (stream.DeclaredLength >= 0 && !stream.IsHeadRequest
            && stream.ReceivedLength > stream.DeclaredLength)
        {
            ResetHttp2StreamLocked(stream, Http2ErrorCode.ProtocolError, HttpError.InvalidResponse,
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
        if (bodyExpected && stream.DeclaredLength >= 0
            && stream.ReceivedLength != stream.DeclaredLength)
        {
            String message = "the response's body was not the length its content-length declared";
            stream.FailHttp2Stream(HttpError.InvalidResponse, message, 0u);
            if (!stream.LocalClosed)
            {
                ResetHttp2StreamLocked(stream, Http2ErrorCode.ProtocolError,
                                       HttpError.InvalidResponse,
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
            return FailHttp2Connection(Http2ErrorCode.ProtocolError,
                                       "HEADERS padded past its length");
        if (frame.HasFlag(Http2FlagPriority))
        {
            if (length < 5u)
                return FailHttp2Connection(Http2ErrorCode.FrameSizeError,
                                           "HEADERS too short for its priority");
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
            return FailHttp2Connection(Http2ErrorCode.ProtocolError,
                                       "CONTINUATION with no header block open");
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
        HpackStatus decoded = _decoder.DecodeHpackHeaderBlock(_headerBlock.Storage, 0u,
                                                              _headerBlock.Length, fields);
        if (decoded == HpackStatus.Malformed)
            return FailHttp2Connection(Http2ErrorCode.CompressionError,
                                       "a header block could not be decoded");
        String problem = "";
        Http2ErrorCode code = Http2ErrorCode.NoError;
        {
            var held = _state.Enter();
            problem = ApplyHttp2HeaderBlockLocked(id, fields, decoded, out code);
            held.PulseAll();
        }
        return CheckHttp2Problem(problem, code);
    }

    private String ApplyHttp2HeaderBlockLocked(uint id, List<HpackField> fields,
                                               HpackStatus decoded,
                                               out Http2ErrorCode code)
    {
        Http2Stream? found = FindHttp2FrameStreamLocked(id, "HEADERS", out String problem,
                                                        out code);
        if (found == null)
            return problem;
        Http2Stream stream = found;
        stream.HasHeardFromPeer = true;
        if (stream.RemoteClosed)
        {
            ResetHttp2StreamLocked(stream, Http2ErrorCode.StreamClosed, HttpError.None,
                                   "HEADERS after END_STREAM");
            return "";
        }
        if (decoded == HpackStatus.TooLarge)
        {
            ResetHttp2StreamLocked(stream, Http2ErrorCode.Cancel, HttpError.ResponseTooLarge,
                                   "the response's fields were past MaxResponseHeadersLength");
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
                ResetHttp2StreamLocked(stream, Http2ErrorCode.ProtocolError,
                                       HttpError.InvalidResponse,
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
                ResetHttp2StreamLocked(stream, Http2ErrorCode.ProtocolError,
                                       HttpError.InvalidResponse,
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
            ResetHttp2StreamLocked(found, Http2ErrorCode.FrameSizeError, HttpError.ProtocolError,
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
            return FailHttp2Connection(Http2ErrorCode.FrameSizeError,
                                       "RST_STREAM was not four octets");
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
            stream.FailHttp2Stream(HttpError.ConnectionClosed,
                                   "the server refused the stream (REFUSED_STREAM)",
                                   reason);
        }
        else if (reason != (uint)Http2ErrorCode.NoError || !stream.RemoteClosed)
        {
            String message = "the server reset the stream with " + DescribeHttp2ErrorCode(reason);
            stream.FailHttp2Stream(HttpError.ProtocolError, message, reason);
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
                return FailHttp2Connection(Http2ErrorCode.FrameSizeError,
                                           "a SETTINGS acknowledgement with a payload");
            return true;
        }
        if (frame.Length % 6u != 0u)
            return FailHttp2Connection(Http2ErrorCode.FrameSizeError,
                                       "SETTINGS not a multiple of six octets");
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
                    if (!_hasTableLimit || (nuint)value < _tableMinimum)
                        _tableMinimum = (nuint)value;
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
                    if ((nuint)value < Http2DefaultMaxFrameSize
                        || (nuint)value > Http2MaxAllowedFrameSize)
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
        QueueHttp2ControlLocked(ack, true);
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
        QueueHttp2ControlLocked(answer, true);
        _pingsAnswered++;
        return true;
    }

    private bool ProcessHttp2GoAway(Http2Frame frame)
    {
        if (frame.StreamId != 0u)
            return FailHttp2Connection(Http2ErrorCode.ProtocolError, "GOAWAY on a stream");
        if (frame.Length < 8u)
            return FailHttp2Connection(Http2ErrorCode.FrameSizeError,
                                       "GOAWAY shorter than eight octets");
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
                                       "the server sent GOAWAY before processing the request", 0u);
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
            return FailHttp2Connection(Http2ErrorCode.FrameSizeError,
                                       "WINDOW_UPDATE was not four octets");
        String problem = "";
        Http2ErrorCode code = Http2ErrorCode.NoError;
        long increment = (long)(frame.ReadHttp2Word(0u) & Http2MaxStreamId);
        {
            var held = _state.Enter();
            problem = ApplyHttp2WindowUpdateLocked(frame.StreamId, increment, out code);
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
            ResetHttp2StreamLocked(stream, Http2ErrorCode.ProtocolError, HttpError.ProtocolError,
                                   "the server sent a WINDOW_UPDATE of zero");
            return "";
        }
        stream.SendWindow += increment;
        if (stream.SendWindow > Http2MaxWindowSize)
        {
            ResetHttp2StreamLocked(stream, Http2ErrorCode.FlowControlError, HttpError.ProtocolError,
                                   "the server took a stream's window past 2^31 - 1");
        }
        return "";
    }

    // ------------------------------------------------------------ failing

    /// A connection error (RFC 9113 section 5.4.1): GOAWAY with `code`, then
    /// the end. Answers false, for the reader to stop.
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
            var deadline = new HttpDeadline(TimeSpan.FromMilliseconds((long)Http2GoAwayWaitMilliseconds));
            SendHttp2Frames(frame, null, deadline);
        }
        EndHttp2Connection(HttpError.ProtocolError, "HTTP/2 "
                           + DescribeHttp2ErrorCode((uint)code) + ": " + message,
                           (uint)code);
        return false;
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
            ClearHttp2ControlLocked();
            _shutDownQueued = false;
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
        String message = _endMessage.IsEmpty ? "the HTTP/2 connection closed" : _endMessage;
        return failure.RecordHttpFailure(error, message);
    }

    /// A write failed: the socket goes, and the reader ends every stream.
    private void FailHttp2Transport(HttpDeadline deadline)
    {
        String message = HasHttp2WriteTimedOut(deadline)
                         ? "a write on the HTTP/2 connection timed out"
                         : "a write on the HTTP/2 connection failed";
        EndHttp2Connection(HttpError.ConnectionClosed, message, 0u);
    }

    // ------------------------------------------------------------ streams

    private Http2Stream? FindHttp2StreamLocked(uint id)
    {
        if (_streams.TryGetValue(id) is Some found)
            return found.Value;
        return null;
    }

    /// Resets `stream` with `code` unless it is over already, failing it
    /// with `error` unless that is `None`, and gives back what it held.
    private void ResetHttp2StreamLocked(Http2Stream stream, Http2ErrorCode code, HttpError error,
                                        String message)
    {
        if (error != HttpError.None)
            stream.FailHttp2Stream(error, message,
                                   error == HttpError.ProtocolError ? (uint)code : 0u);
        if (!stream.IsReleased && stream.Id != 0u && !_ended)
        {
            var frame = new Http2Buffer(16u);
            WriteHttp2RstStream(frame, stream.Id, (uint)code);
            QueueHttp2ControlLocked(frame, false);
        }
        stream.IsReset = true;
        if (error != HttpError.None)
            CreditHttp2ConnectionLocked((long)stream.DiscardHttp2Bytes());
        ReleaseHttp2StreamLocked(stream);
    }

    /// Takes the stream out of the table and gives its place back. One the
    /// peer ended, and neither end reset, is remembered for a while.
    private void ReleaseHttp2StreamLocked(Http2Stream stream)
    {
        if (stream.IsReleased)
            return;
        stream.IsReleased = true;
        if (stream.Id != 0u)
        {
            _streams.Remove(stream.Id);
            if (stream.IsReset)
            {
                _windowUpdates.Remove(stream.Id);
            }
            else
            {
                _endedStreams.Add(stream.Id);
                if (_endedStreams.Count > Http2RememberedEndedStreams)
                    _endedStreams.RemoveAt(0u);
            }
        }
        _reserved--;
        NoteHttp2IdleLocked();
        if ((_goingAway || _closing) && _streams.IsEmpty && !_shutDown)
            _shutDownQueued = true;
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
        if (!stream.RemoteClosed && !stream.IsReset
            && stream.UnacknowledgedBytes >= _streamWindow / 2)
        {
            QueueHttp2WindowUpdateLocked(stream.Id, stream.UnacknowledgedBytes);
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
            QueueHttp2WindowUpdateLocked(0u, _connectionUnacknowledged);
            _receiveWindow += _connectionUnacknowledged;
            _connectionUnacknowledged = 0;
        }
    }

    // ------------------------------------------------------------ the queue

    /// Queues a control frame for the next holder of the write turn. Past the
    /// caps it is not queued, and the connection is marked to end with
    /// ENHANCE_YOUR_CALM.
    private void QueueHttp2ControlLocked(Http2Buffer frame, bool isAck)
    {
        if (_ended || _controlOverflowed)
            return;
        if (_control.Length + frame.Length > Http2MaxPendingControlBytes
            || (isAck && _pendingAcks >= Http2MaxPendingAcks))
        {
            _controlOverflowed = true;
            return;
        }
        _control.WriteArray(frame.Storage, 0u, frame.Length);
        if (isAck)
            _pendingAcks++;
    }

    /// Queues a WINDOW_UPDATE, adding it to one already queued for the same
    /// stream. Each is at most what the peer has sent, so a sum stays within
    /// a window.
    private void QueueHttp2WindowUpdateLocked(uint id, long increment)
    {
        if (_ended)
            return;
        _windowUpdates.SetValue(id, _windowUpdates.GetValueOrDefault(id, 0) + increment);
    }

    /// Whether anything waits to be written.
    private bool HasQueuedHttp2ControlLocked =>
        _control.Length > 0u || !_windowUpdates.IsEmpty || _shutDownQueued;

    /// Moves what is queued into `output`, WINDOW_UPDATEs first so that none
    /// follows a RST_STREAM on its stream.
    private void TakeHttp2ControlLocked(Http2Buffer output)
    {
        foreach (var pair in _windowUpdates)
            WriteHttp2WindowUpdate(output, pair.Key, (uint)pair.Value);
        output.WriteArray(_control.Storage, 0u, _control.Length);
        ClearHttp2ControlLocked();
    }

    private void ClearHttp2ControlLocked()
    {
        _windowUpdates.Clear();
        _control.Clear();
        _pendingAcks = 0u;
    }

    // ------------------------------------------------------------ writing

    /// Takes the write turn, waiting no longer than `deadline`. Null when the
    /// wait ran out, `outcome` `Expired`, or the connection ended, `Failed`.
    private Http2WriteTurn? TakeHttp2WriteTurn(HttpDeadline deadline, out Http2WriteOutcome outcome)
    {
        var held = _state.Enter();
        while (_writing && !_ended)
        {
            if (!WaitForHttp2Change(held, deadline))
            {
                outcome = Http2WriteOutcome.Expired;
                return null;
            }
        }
        if (_ended)
        {
            outcome = Http2WriteOutcome.Failed;
            return null;
        }
        _writing = true;
        outcome = Http2WriteOutcome.Written;
        return new Http2WriteTurn(this);
    }

    /// Takes the write turn only if it is free.
    private Http2WriteTurn? TryTakeHttp2WriteTurn()
    {
        var held = _state.Enter();
        if (_writing || _ended)
            return null;
        _writing = true;
        return new Http2WriteTurn(this);
    }

    /// Gives the write turn back. Only `Http2WriteTurn` calls it.
    internal void ReturnHttp2WriteTurn()
    {
        var held = _state.Enter();
        _writing = false;
        held.PulseAll();
    }

    /// Writes `frames` in the write turn, after anything queued, and then
    /// whatever was queued meanwhile if the turn is free.
    private Http2WriteOutcome SendHttp2Frames(Http2Buffer frames, Http2Stream? stream,
                                              HttpDeadline deadline)
    {
        Http2WriteOutcome outcome = Http2WriteOutcome.Expired;
        {
            Http2WriteTurn? turn = TakeHttp2WriteTurn(deadline, out outcome);
            if (turn != null)
                outcome = WriteHttp2FramesLocked(frames, stream, deadline);
        }
        FlushHttp2ControlFrames(deadline);
        return outcome;
    }

    /// Writes what is queued, then `frames` unless `stream` has been reset or
    /// has failed. The caller holds the write turn. Nothing is written once
    /// the deadline has passed.
    private Http2WriteOutcome WriteHttp2FramesLocked(Http2Buffer frames, Http2Stream? stream,
                                                     HttpDeadline deadline)
    {
        if (deadline.HasExpired)
            return Http2WriteOutcome.Expired;
        var output = new Http2Buffer(64u);
        bool shutDown = false;
        bool dropped = false;
        {
            var held = _state.Enter();
            if (_ended)
                return Http2WriteOutcome.Failed;
            TakeHttp2ControlLocked(output);
            shutDown = _shutDownQueued;
            _shutDownQueued = false;
            if (stream != null && (stream.IsReset || stream.Error != HttpError.None))
                dropped = true;
        }
        if (!WriteHttp2BytesLocked(output, deadline))
            return Http2WriteOutcome.Failed;
        if (!dropped && !WriteHttp2BytesLocked(frames, deadline))
            return Http2WriteOutcome.Failed;
        if (shutDown)
            ShutDownHttp2Transport();
        return dropped ? Http2WriteOutcome.Dropped : Http2WriteOutcome.Written;
    }

    /// Writes `bytes` alone, the socket's send timeout set from `deadline`.
    /// The caller holds the write turn. False when the write failed, which
    /// MUST end the connection.
    private bool WriteHttp2BytesLocked(Http2Buffer bytes, HttpDeadline deadline)
    {
        if (bytes.Length == 0u)
            return true;
        _tcp.Underlying.SetSendTimeout(deadline.SocketTimeoutMilliseconds);
        if (!WriteAllHttpBytes(_stream, bytes.Storage, 0u, bytes.Length))
            return false;
        _stream.Flush();
        return true;
    }

    /// Writes the queued control frames if the write turn is free. When it
    /// is not, its holder writes them on its way out. The write is bounded by
    /// `Http2ControlWriteMilliseconds`, or by `deadline` when that is sooner
    /// but never below `Http2LateFlushMilliseconds`. False when the
    /// connection has ended.
    internal bool FlushHttp2ControlFrames(HttpDeadline? deadline)
    {
        bool overflowed = false;
        {
            var held = _state.Enter();
            if (_ended)
                return false;
            overflowed = _controlOverflowed;
            if (overflowed)
            {
                // The flood is not answered; the GOAWAY goes alone.
                _controlOverflowed = false;
                ClearHttp2ControlLocked();
            }
        }
        if (overflowed)
        {
            return FailHttp2Connection(Http2ErrorCode.EnhanceYourCalm,
                                       "the server sent control frames faster than it read the answers");
        }

        long bound = (long)Http2ControlWriteMilliseconds;
        if (deadline != null && deadline.IsBounded)
        {
            long left = deadline.RemainingMilliseconds;
            if (left < (long)Http2LateFlushMilliseconds)
                left = (long)Http2LateFlushMilliseconds;
            if (left < bound)
                bound = left;
        }
        var control = new HttpDeadline(TimeSpan.FromMilliseconds(bound));
        while (true)
        {
            {
                var held = _state.Enter();
                if (!HasQueuedHttp2ControlLocked)
                    return !_ended;
            }
            Http2WriteOutcome outcome = Http2WriteOutcome.Expired;
            {
                Http2WriteTurn? turn = TryTakeHttp2WriteTurn();
                if (turn == null)
                    return true;
                outcome = WriteHttp2FramesLocked(new Http2Buffer(0u), null, control);
            }
            if (outcome == Http2WriteOutcome.Failed)
            {
                FailHttp2Transport(control);
                return false;
            }
            if (outcome == Http2WriteOutcome.Expired)
                return true;
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
