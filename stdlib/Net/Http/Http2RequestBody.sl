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

/// A request body written as DATA frames, each no larger than the peer's
/// frame size and never past either window.
internal sealed class Http2RequestBody : IStream
{
    private Http2Multiplexer _multiplexer;
    private Http2Stream _stream;
    private HttpExchange _exchange;
    private bool _failed = false;

    internal Http2RequestBody(Http2Multiplexer multiplexer, Http2Stream stream,
                              HttpExchange exchange)
    {
        _multiplexer = multiplexer;
        _stream = stream;
        _exchange = exchange;
    }

    internal bool HasFailed => _failed;

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
        if (!_multiplexer.WriteHttp2Body(_stream, _exchange, buffer, offset, count))
        {
            _failed = true;
            return 0u;
        }
        return count;
    }

    public long Position => -1;

    public long Length => -1;

    public bool Seek(long offset, SeekOrigin origin) => false;

    public void Flush() { }

    public void Close() { }

    public IOError Error => _failed ? IOError.Closed : IOError.None;
}
