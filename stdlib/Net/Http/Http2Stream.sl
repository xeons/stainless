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

/// One request's stream on an HTTP/2 connection (RFC 9113 §5.1).
///
/// **Every field is guarded by the multiplexer's state lock.** The reader
/// thread fills it in as frames arrive; the thread that sent the request
/// waits on the same lock for what it needs.
internal sealed class Http2Stream
{
    internal uint Id = 0u;

    /// Whether the request was HEAD, whose response has no body whatever its
    /// `content-length` says.
    internal bool IsHeadRequest;

    /// What this end may still send, and what the peer may.
    internal long SendWindow = 0;
    internal long ReceiveWindow = 0;

    /// Bytes read out of the stream and not yet given back to the peer.
    internal long UnacknowledgedBytes = 0;

    /// Whether this end has sent END_STREAM, and whether the peer has.
    internal bool LocalClosed = false;
    internal bool RemoteClosed = false;

    /// Whether either end reset the stream.
    internal bool IsReset = false;

    /// Whether its slot has been given back and it has left the table.
    internal bool IsReleased = false;

    /// Whether any frame for it has arrived.
    internal bool HasHeardFromPeer = false;

    internal bool HasFinalHead = false;
    internal int Status = 0;
    internal HttpWireHeaders Head = new HttpWireHeaders();
    internal bool HasContinue = false;
    internal HttpWireHeaders? Trailers = null;

    /// The body as it arrived and has not yet been read.
    internal Queue<byte[]> Chunks = new Queue<byte[]>();
    internal nuint ChunkOffset = 0u;
    internal nuint BufferedBytes = 0u;

    /// The `content-length` the head declared, or -1, and what has arrived.
    internal long DeclaredLength = -1;
    internal long ReceivedLength = 0;

    /// Why the stream failed, or `None`.
    internal HttpError Error = HttpError.None;
    internal String ErrorMessage = "";
    internal uint ErrorCode = 0u;

    /// Whether the peer never processed the request, so that it may be sent
    /// again on another connection whatever its method (RFC 9113 §8.7).
    internal bool IsUnprocessed = false;

    internal Http2Stream(bool isHeadRequest) => IsHeadRequest = isHeadRequest;

    /// Whether the stream is over on the wire: both ends closed, or reset.
    internal bool IsClosed => IsReset || (LocalClosed && RemoteClosed);

    /// Records why the stream failed, keeping the first reason.
    internal void FailHttp2Stream(HttpError error, String message, uint code)
    {
        if (Error != HttpError.None)
            return;
        Error = error;
        ErrorMessage = message;
        ErrorCode = code;
    }

    /// Copies the failure onto `failure` for the caller to read.
    internal HttpError ReportHttp2Failure(HttpFailure failure)
    {
        if (ErrorCode != 0u)
            failure.ProtocolErrorCode = (long)ErrorCode;
        return failure.RecordHttpFailure(Error, ErrorMessage);
    }

    /// Takes up to `count` buffered bytes into `buffer`.
    internal nuint TakeHttp2Bytes(byte[] buffer, nuint offset, nuint count)
    {
        nuint taken = 0u;
        while (taken < count && !Chunks.IsEmpty)
        {
            byte[] chunk = Chunks.Peek();
            nuint left = chunk.Length - ChunkOffset;
            nuint part = count - taken;
            if (part > left)
                part = left;
            memcpy(&buffer[offset + taken], &chunk[ChunkOffset], part);
            taken += part;
            ChunkOffset += part;
            if (ChunkOffset == chunk.Length)
            {
                Chunks.Dequeue();
                ChunkOffset = 0u;
            }
        }
        BufferedBytes -= taken;
        return taken;
    }

    /// Drops what is buffered, and answers how much that was.
    internal nuint DiscardHttp2Bytes()
    {
        nuint dropped = BufferedBytes;
        Chunks.Clear();
        ChunkOffset = 0u;
        BufferedBytes = 0u;
        return dropped;
    }
}

/// A response body read from its stream: blocks until DATA arrives, gives
/// the window back as it is read, and ends at END_STREAM.
///
/// Closing it before the end resets the stream with CANCEL; the connection
/// carries on.
internal sealed class Http2ResponseBody : IHttpBodyStream
{
    private Http2Connection _connection;
    private Http2Stream _stream;
    private HttpExchange _exchange;
    private HttpResponseHeaders _trailers;
    private bool _finished = false;
    private HttpError _httpError = HttpError.None;

    internal Http2ResponseBody(Http2Connection connection, Http2Stream stream,
                               HttpExchange exchange,
                               HttpResponseHeaders trailers)
    {
        _connection = connection;
        _stream = stream;
        _exchange = exchange;
        _trailers = trailers;
    }

    ~Http2ResponseBody() { Close(); }

    public HttpError HttpErrorCode => _httpError;

    public bool IsHttpBodyComplete => _finished && _httpError == HttpError.None;

    public bool CanRead => !_finished;

    public bool CanWrite => false;

    public bool CanSeek => false;

    public nuint Read(byte[] buffer, nuint offset, nuint count)
    {
        if (_finished || count == 0u)
            return 0u;
        if (offset > buffer.Length || count > buffer.Length - offset)
            return 0u;
        nuint got = _connection.Multiplexer.ReadHttp2Body(_stream, _exchange, buffer, offset,
                                                          count);
        if (got > 0u)
            return got;

        _finished = true;
        HttpError error = _connection.Multiplexer.FinishHttp2Body(_stream, _exchange, _trailers);
        _httpError = error;
        return 0u;
    }

    public nuint Write(byte[] buffer, nuint offset, nuint count) => 0u;

    public long Position => -1;

    public long Length => -1;

    public bool Seek(long offset, SeekOrigin origin) => false;

    public void Flush() { }

    /// Stops reading. Before the end, that resets the stream.
    public void Close()
    {
        if (_finished)
            return;
        _finished = true;
        _connection.Multiplexer.CancelHttp2Stream(_stream, "the body was closed before its end");
    }

    public IOError Error
    {
        get
        {
            switch (_httpError)
            {
                case HttpError.None: return IOError.None;
                case HttpError.ConnectionClosed: return IOError.Closed;
                case HttpError.InvalidResponse: return IOError.InvalidData;
                case HttpError.ProtocolError: return IOError.InvalidData;
                default: return IOError.Unknown;
            }
        }
    }
}

/// A request body written as DATA frames, each no larger than the peer's
/// frame size and never past either window.
internal sealed class Http2RequestBody : IStream
{
    private Http2Multiplexer _multiplexer;
    private Http2Stream _stream;
    private HttpExchange _exchange;
    private bool _failed = false;

    internal Http2RequestBody(Http2Multiplexer multiplexer, Http2Stream stream,
                              HttpExchange exchange)
    {
        _multiplexer = multiplexer;
        _stream = stream;
        _exchange = exchange;
    }

    internal bool HasFailed => _failed;

    public bool CanRead => false;

    public bool CanWrite => !_failed;

    public bool CanSeek => false;

    public nuint Read(byte[] buffer, nuint offset, nuint count) => 0u;

    public nuint Write(byte[] buffer, nuint offset, nuint count)
    {
        if (_failed)
            return 0u;
        if (count == 0u)
            return 0u;
        if (!_multiplexer.WriteHttp2Body(_stream, _exchange, buffer, offset, count))
        {
            _failed = true;
            return 0u;
        }
        return count;
    }

    public long Position => -1;

    public long Length => -1;

    public bool Seek(long offset, SeekOrigin origin) => false;

    public void Flush() { }

    public void Close() { }

    public IOError Error => _failed ? IOError.Closed : IOError.None;
}
