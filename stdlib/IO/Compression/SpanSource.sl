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

module Standard.IO.Compression;

import Standard.IO;

// A read-only stream over a span, for the one-shot calls to decompress from.
class SpanSource : IStream
{
    ReadOnlySpan<byte> _data;
    nuint _at;

    SpanSource(ReadOnlySpan<byte> data)
    {
        _data = data;
        _at = 0;
    }

    public bool CanRead => true;
    public bool CanWrite => false;
    public bool CanSeek => false;

    public nuint Read(byte[] buffer, nuint offset, nuint count)
    {
        nuint available = _data.Length - _at;
        nuint taking = count < available ? count : available;
        if (taking != 0u)
            _data[_at:_at + taking].CopyTo(buffer[offset:]);
        _at += taking;
        return taking;
    }

    public nuint Write(byte[] buffer, nuint offset, nuint count) => 0;
    public long Position => -1;
    public long Length => -1;
    public bool Seek(long offset, SeekOrigin origin) => false;
    public void Flush() { }
    public void Close() { }
    public IOError Error => IOError.None;
}
