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
import Standard.Text;

/// Writes gathered into blocks, so that a head and a small body leave in one
/// segment, or one TLS record, rather than several.
internal sealed class HttpBufferedWriter : IStream
{
    private IStream _inner;
    private byte[] _buffer = new byte[HttpCopyBlockSize];
    private nuint _count = 0u;
    private bool _failed = false;

    internal HttpBufferedWriter(IStream inner) => _inner = inner;

    internal bool HasFailed => _failed;

    /// Sends what is gathered. False when the stream would not take it.
    internal bool FlushHttpBuffer()
    {
        if (_failed)
            return false;
        if (_count > 0u)
        {
            if (!WriteAllHttpBytes(_inner, _buffer, 0u, _count))
            {
                _failed = true;
                return false;
            }
            _count = 0u;
        }
        _inner.Flush();
        return true;
    }

    public bool CanRead => false;

    public bool CanWrite => !_failed;

    public bool CanSeek => false;

    public nuint Read(byte[] buffer, nuint offset, nuint count) => 0u;

    public nuint Write(byte[] buffer, nuint offset, nuint count)
    {
        if (_failed)
            return 0u;
        nuint done = 0u;
        while (done < count)
        {
            if (_count == _buffer.Length && !FlushHttpBuffer())
                return 0u;
            nuint room = _buffer.Length - _count;
            nuint part = count - done;
            if (part > room)
                part = room;
            memcpy(&_buffer[_count], &buffer[offset + done], part);
            _count += part;
            done += part;
        }
        return count;
    }

    public long Position => -1;

    public long Length => -1;

    public bool Seek(long offset, SeekOrigin origin) => false;

    public void Flush() => FlushHttpBuffer();

    public void Close() { }

    public IOError Error => _failed ? IOError.Closed : IOError.None;
}

/// A request body in chunks, for one whose length is not known before it is
/// sent (RFC 9112 §7.1).
internal sealed class HttpChunkedWriter : IStream
{
    private IStream _inner;
    private bool _failed = false;

    internal HttpChunkedWriter(IStream inner) => _inner = inner;

    /// Writes the last chunk and the empty trailer.
    internal bool FinishHttpChunks() => !_failed && WriteHttpText(_inner, "0\r\n\r\n");

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
        if (!WriteHttpText(_inner, FormatHttpHexadecimal((ulong)count) + "\r\n") ||
            !WriteAllHttpBytes(_inner, buffer, offset, count) ||
            !WriteHttpText(_inner, "\r\n"))
        {
            _failed = true;
            return 0u;
        }
        return count;
    }

    public long Position => -1;

    public long Length => -1;

    public bool Seek(long offset, SeekOrigin origin) => false;

    public void Flush() => _inner.Flush();

    public void Close() { }

    public IOError Error => _failed ? IOError.Closed : IOError.None;
}

/// A stream that counts what passes through it on the way to another, and
/// refuses, whole, any write that would take it past its limit.
///
/// A body longer than its `Content-Length` MUST NOT reach the wire: the
/// excess would be read by the server as the start of another request.
internal sealed class HttpCountingStream : IStream
{
    private IStream _inner;
    private long _counted = 0;
    private long _limit;
    private bool _overflowed = false;

    /// No limit.
    internal HttpCountingStream(IStream inner) : this(inner, -1) { }

    /// At most `limit` bytes; negative is no limit.
    internal HttpCountingStream(IStream inner, long limit)
    {
        _inner = inner;
        _limit = limit;
    }

    internal long CountedBytes => _counted;

    /// Whether a write was refused for going past the limit.
    internal bool HasOverflowed => _overflowed;

    public bool CanRead => false;

    public bool CanWrite => !_overflowed && _inner.CanWrite;

    public bool CanSeek => false;

    public nuint Read(byte[] buffer, nuint offset, nuint count) => 0u;

    public nuint Write(byte[] buffer, nuint offset, nuint count)
    {
        if (_overflowed)
            return 0u;
        if (_limit >= 0 && count > (nuint)(_limit - _counted))
        {
            _overflowed = true;
            return 0u;
        }
        nuint wrote = _inner.Write(buffer, offset, count);
        _counted += (long)wrote;
        return wrote;
    }

    public long Position => -1;

    public long Length => -1;

    public bool Seek(long offset, SeekOrigin origin) => false;

    public void Flush() => _inner.Flush();

    public void Close() { }

    public IOError Error => _overflowed ? IOError.InvalidData : _inner.Error;
}

/// A stream that answers bytes already read from another first, then the
/// other: what is left after a look at the start of a body.
internal sealed class HttpPrefixedStream : IStream
{
    private byte[] _prefix;
    private nuint _at = 0u;
    private IStream _inner;

    internal HttpPrefixedStream(byte[] prefix, IStream inner)
    {
        _prefix = prefix;
        _inner = inner;
    }

    public bool CanRead => _at < _prefix.Length || _inner.CanRead;

    public bool CanWrite => false;

    public bool CanSeek => false;

    public nuint Read(byte[] buffer, nuint offset, nuint count)
    {
        if (count == 0u)
            return 0u;
        if (_at < _prefix.Length)
        {
            nuint part = _prefix.Length - _at;
            if (part > count)
                part = count;
            memcpy(&buffer[offset], &_prefix[_at], part);
            _at += part;
            return part;
        }
        return _inner.Read(buffer, offset, count);
    }

    public nuint Write(byte[] buffer, nuint offset, nuint count) => 0u;

    public long Position => -1;

    public long Length => -1;

    public bool Seek(long offset, SeekOrigin origin) => false;

    public void Flush() { }

    public void Close() => _inner.Close();

    public IOError Error => _inner.Error;
}

/// `value` in lower-case hexadecimal, with no leading zeros.
internal String FormatHttpHexadecimal(ulong value)
{
    if (value == 0u)
        return "0";
    var digits = new StringBuilder();
    int shift = 60;
    bool started = false;
    while (shift >= 0)
    {
        int digit = (int)((value >> shift) & 0xFu);
        if (digit != 0 || started)
        {
            started = true;
            digits.Append("0123456789abcdef".Substring((nuint)digit, 1u));
        }
        shift -= 4;
    }
    return digits.ToText();
}
