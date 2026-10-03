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

/// A response body read from its connection: to a length, chunk by chunk,
/// or to the close.
///
/// Reaching the end gives the connection back to its pool; closing before
/// the end, or a failure, closes the connection instead, since what is left
/// of the body would otherwise be read as the next response.
internal sealed class Http11BodyStream : IHttpBodyStream
{
    private Http11Connection _connection;
    private Http11Framing _framing;
    private long _remaining;
    private bool _keepAlive;
    private HttpResponseHeaders _trailers;
    private bool _chunkEndOwed = false;
    private bool _finished = false;
    private HttpError _httpError = HttpError.None;

    internal Http11BodyStream(Http11Connection connection, Http11Framing framing, long length,
                              bool keepAlive, HttpResponseHeaders trailers)
    {
        _connection = connection;
        _framing = framing;
        _remaining = framing == Http11Framing.Length ? length : 0;
        _keepAlive = keepAlive;
        _trailers = trailers;
    }

    ~Http11BodyStream() { Close(); }

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
        if (!_connection.ApplyHttpDeadline())
        {
            FailHttpBody(_connection.ClassifyHttpIoFailure("while the body was being read"));
            return 0u;
        }

        switch (_framing)
        {
            case Http11Framing.Length:
                return ReadHttpLengthBody(buffer, offset, count);
            case Http11Framing.Chunked:
                return ReadHttpChunkedBody(buffer, offset, count);
            default:
                return ReadHttpBodyToClose(buffer, offset, count);
        }
    }

    private nuint ReadHttpLengthBody(byte[] buffer, nuint offset, nuint count)
    {
        nuint wanted = count;
        if ((long)wanted > _remaining)
            wanted = (nuint)_remaining;
        nuint got = _connection.Reader.ReadHttpBytes(buffer, offset, wanted);
        if (got == 0u)
        {
            FailHttpBodyRead();
            return 0u;
        }
        _remaining -= (long)got;
        if (_remaining == 0)
            FinishHttpBody(_keepAlive);
        return got;
    }

    private nuint ReadHttpBodyToClose(byte[] buffer, nuint offset, nuint count)
    {
        HttpBufferedReader reader = _connection.Reader;
        nuint got = reader.ReadHttpBytes(buffer, offset, count);
        if (got == 0u)
        {
            if (reader.HasFailed)
                FailHttpBodyRead();
            else
                FinishHttpBody(false);
        }
        return got;
    }

    private nuint ReadHttpChunkedBody(byte[] buffer, nuint offset, nuint count)
    {
        HttpBufferedReader reader = _connection.Reader;
        while (_remaining == 0)
        {
            if (_chunkEndOwed)
            {
                HttpLineStatus ended = reader.ReadHttpLine(HttpMaxLineLength, out String empty);
                if (ended != HttpLineStatus.Line)
                {
                    FailHttpBody(_connection.FailHttpLine(ended, "inside a chunked body"));
                    return 0u;
                }
                if (!empty.IsEmpty)
                {
                    FailHttpBodySyntax("a chunk ran past its size");
                    return 0u;
                }
                _chunkEndOwed = false;
            }

            HttpLineStatus status = reader.ReadHttpLine(HttpMaxLineLength, out String line);
            if (status != HttpLineStatus.Line)
            {
                FailHttpBody(_connection.FailHttpLine(status, "inside a chunked body"));
                return 0u;
            }
            if (!TryParseHttpChunkSize(line, out long size))
            {
                FailHttpBodySyntax("a chunk size was malformed: " + DescribeHttpLine(line));
                return 0u;
            }
            if (size == 0)
            {
                HttpError trailer = _connection.ReadHttpFieldBlock(_trailers, 65536u, "in the trailer");
                if (trailer != HttpError.None)
                {
                    FailHttpBody(trailer);
                    return 0u;
                }
                FinishHttpBody(_keepAlive);
                return 0u;
            }
            _remaining = size;
        }

        nuint wanted = count;
        if ((long)wanted > _remaining)
            wanted = (nuint)_remaining;
        nuint got = reader.ReadHttpBytes(buffer, offset, wanted);
        if (got == 0u)
        {
            FailHttpBodyRead();
            return 0u;
        }
        _remaining -= (long)got;
        if (_remaining == 0)
            _chunkEndOwed = true;
        return got;
    }

    private void FailHttpBodyRead()
    {
        HttpBufferedReader reader = _connection.Reader;
        if (reader.HasFailed)
        {
            FailHttpBody(_connection.ClassifyHttpIoFailure("while the body was being read"));
            return;
        }
        FailHttpBody(_connection.RecordHttpExchangeFailure(HttpError.ConnectionClosed,
            "the connection ended before the body did"));
    }

    private void FailHttpBodySyntax(String message) =>
        FailHttpBody(_connection.RecordHttpExchangeFailure(HttpError.InvalidResponse, message));

    private void FailHttpBody(HttpError error)
    {
        _httpError = error;
        _connection.CloseHttpConnection();
        FinishHttpBody(false);
    }

    private void FinishHttpBody(bool reusable)
    {
        if (_finished)
            return;
        _finished = true;
        _connection.FinishHttpExchange(reusable);
    }

    public nuint Write(byte[] buffer, nuint offset, nuint count) => 0u;

    public long Position => -1;

    public long Length => -1;

    public bool Seek(long offset, SeekOrigin origin) => false;

    public void Flush() { }

    /// Stops reading. Before the end, that closes the connection.
    public void Close()
    {
        if (_finished)
            return;
        _connection.CloseHttpConnection();
        FinishHttpBody(false);
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
                case HttpError.ResponseTooLarge: return IOError.InvalidData;
                default: return IOError.Unknown;
            }
        }
    }
}

/// `1*HEXDIG [ BWS ; chunk-ext ]`, the size of the chunk that follows.
internal bool TryParseHttpChunkSize(String line, out long size)
{
    size = 0;
    nuint length = line.ByteLength();
    nuint at = 0u;
    while (at < length)
    {
        int digit = ParseHttpHexadecimalDigit(line.GetByteAt(at));
        if (digit < 0)
            break;
        if (at >= 15u)
            return false;
        size = size * 16 + (long)digit;
        at++;
    }
    if (at == 0u)
        return false;
    while (at < length && IsHttpWhitespace(line.GetByteAt(at)))
        at++;
    return at == length || line.GetByteAt(at) == (byte)';';
}
