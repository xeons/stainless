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

import Standard.IO;

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
