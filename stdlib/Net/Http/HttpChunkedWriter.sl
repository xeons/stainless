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
