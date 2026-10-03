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

/// A write-only stream into memory that refuses to grow past a limit.
internal sealed class HttpBoundedBufferStream : IStream
{
    private MemoryStream _memory = new MemoryStream();
    private long _limit;
    private bool _overLimit = false;

    internal HttpBoundedBufferStream(long limit) => _limit = limit;

    internal bool IsOverLimit => _overLimit;

    internal byte[] ToArray() => _memory.ToArray();

    public bool CanRead => false;

    public bool CanWrite => !_overLimit;

    public bool CanSeek => false;

    public nuint Read(byte[] buffer, nuint offset, nuint count) => 0u;

    public nuint Write(byte[] buffer, nuint offset, nuint count)
    {
        if (_overLimit)
            return 0u;
        if (_memory.Length + (long)count > _limit)
        {
            _overLimit = true;
            return 0u;
        }
        return _memory.Write(buffer, offset, count);
    }

    public long Position => -1;

    public long Length => -1;

    public bool Seek(long offset, SeekOrigin origin) => false;

    public void Flush() { }

    public void Close() { }

    public IOError Error => _overLimit ? IOError.Invalid : IOError.None;
}
