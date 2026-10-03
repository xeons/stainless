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
