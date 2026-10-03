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
