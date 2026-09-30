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

/// How a line read ended.
internal enum HttpLineStatus
{
    /// A whole line, without its terminator.
    Line,

    /// The stream ended before any byte of the line.
    EndOfStream,

    /// The stream ended part-way through the line.
    Truncated,

    /// The line ran past its limit.
    TooLong,

    /// A CR not followed by LF, which RFC 9112 §2.2 lets a recipient refuse.
    Malformed,

    /// The stream failed.
    Failed,
}

/// Bytes from a stream, a block at a time, so that a head can be read a line
/// at a time and a body after it without either losing what the other read.
///
/// A line ends in LF, with or without a CR before it, as RFC 9112 §2.2 lets a
/// recipient accept; a CR anywhere else in it is refused.
internal sealed class HttpBufferedReader
{
    private IStream _inner;
    private byte[] _buffer;
    private nuint _start = 0u;
    private nuint _end = 0u;
    private bool _failed = false;
    private bool _ended = false;
    private ulong _consumed = 0u;
    private weak Http11Connection? _deadlineOwner;

    internal HttpBufferedReader(IStream inner, nuint capacity)
    {
        _inner = inner;
        _buffer = new byte[capacity];
    }

    /// Has `owner` set the socket's timeouts before every read of the
    /// stream, so that each read gets what is left of the deadline rather
    /// than all of it.
    internal void BindHttpDeadline(Http11Connection owner) => _deadlineOwner = owner;

    internal IStream Inner => _inner;

    /// How many bytes are held and not yet read.
    internal nuint BufferedCount => _end - _start;

    /// Whether the stream underneath failed, rather than ended.
    internal bool HasFailed => _failed;

    /// How many bytes have been taken out of this reader in all.
    internal ulong ConsumedCount => _consumed;

    /// Reads one more block from the stream. False at its end or on a
    /// failure, which `HasFailed` tells apart.
    internal bool FillHttpBuffer()
    {
        if (_ended || _failed)
            return false;
        if (_start == _end)
        {
            _start = 0u;
            _end = 0u;
        }
        else if (_end == _buffer.Length)
        {
            nuint held = _end - _start;
            if (_start > 0u)
            {
                memcpy(&_buffer[0u], &_buffer[_start], held);
            }
            else
            {
                var grown = new byte[_buffer.Length * 2u];
                memcpy(&grown[0u], &_buffer[0u], held);
                _buffer = grown;
            }
            _start = 0u;
            _end = held;
        }

        if (!ApplyHttpReadDeadline())
            return false;
        nuint got = _inner.Read(_buffer, _end, _buffer.Length - _end);
        if (got == 0u)
        {
            if (_inner.Error == IOError.None)
                _ended = true;
            else
                _failed = true;
            return false;
        }
        _end += got;
        return true;
    }

    /// The next line, without its CRLF, of at most `limit` bytes.
    internal HttpLineStatus ReadHttpLine(nuint limit, out String line)
    {
        line = "";
        nuint scanned = 0u;
        while (true)
        {
            for (nuint i = _start + scanned; i < _end; i++)
            {
                if (_buffer[i] != (byte)'\n')
                    continue;
                nuint length = i - _start;
                nuint textLength = length;
                if (textLength > 0u && _buffer[i - 1u] == (byte)'\r')
                    textLength--;
                if (textLength > limit)
                    return HttpLineStatus.TooLong;
                for (nuint j = _start; j < _start + textLength; j++)
                {
                    if (_buffer[j] == (byte)'\r')
                        return HttpLineStatus.Malformed;
                }
                line = ConvertHttpBytesToText(_buffer, _start, textLength);
                TakeHttpBytes(length + 1u);
                return HttpLineStatus.Line;
            }
            scanned = _end - _start;
            if (scanned > limit + 1u)
                return HttpLineStatus.TooLong;
            if (!FillHttpBuffer())
            {
                if (_failed)
                    return HttpLineStatus.Failed;
                return scanned == 0u ? HttpLineStatus.EndOfStream : HttpLineStatus.Truncated;
            }
        }
    }

    /// Up to `count` bytes: what is held first, and otherwise one read of the
    /// stream straight into `buffer`. Zero at the end or on a failure.
    internal nuint ReadHttpBytes(byte[] buffer, nuint offset, nuint count)
    {
        if (count == 0u)
            return 0u;
        if (_start == _end)
        {
            if (count >= _buffer.Length)
            {
                if (_ended || _failed || !ApplyHttpReadDeadline())
                    return 0u;
                nuint direct = _inner.Read(buffer, offset, count);
                if (direct == 0u)
                {
                    if (_inner.Error == IOError.None)
                        _ended = true;
                    else
                        _failed = true;
                }
                _consumed += (ulong)direct;
                return direct;
            }
            if (!FillHttpBuffer())
                return 0u;
        }
        nuint taken = _end - _start;
        if (taken > count)
            taken = count;
        memcpy(&buffer[offset], &_buffer[_start], taken);
        TakeHttpBytes(taken);
        return taken;
    }

    /// False, and failed, when the deadline has passed.
    private bool ApplyHttpReadDeadline()
    {
        Http11Connection? owner = _deadlineOwner;
        if (owner == null || owner.ApplyHttpDeadline())
            return true;
        _failed = true;
        return false;
    }

    private void TakeHttpBytes(nuint count)
    {
        _start += count;
        _consumed += (ulong)count;
    }
}
