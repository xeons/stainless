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
