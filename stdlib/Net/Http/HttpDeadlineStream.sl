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
import Standard.Net;

/// A connection with the deadline applied before every read and write, so a
/// peer trickling bytes cannot stretch an exchange past it: each call waits
/// only for what the deadline has left, and none starts once it has expired.
///
/// It stays under a TLS stream for the connection's life, so
/// `ReleaseHttpDeadline` MUST be called once the exchange that made it is
/// done with it. After that it passes every call straight through.
internal sealed class HttpDeadlineStream : IStream
{
    private TcpClient _inner;
    private HttpDeadline? _deadline;
    private bool _expired;

    internal HttpDeadlineStream(TcpClient inner, HttpDeadline deadline)
    {
        _inner = inner;
        _deadline = deadline.IsBounded ? deadline : null;
        _expired = false;
    }

    /// Stops applying the deadline, for the exchanges that reuse the
    /// connection with deadlines of their own.
    internal void ReleaseHttpDeadline() => _deadline = null;

    public bool CanRead => _inner.CanRead;

    public bool CanWrite => _inner.CanWrite;

    public bool CanSeek => false;

    public nuint Read(byte[] buffer, nuint offset, nuint count)
    {
        if (_deadline is HttpDeadline deadline)
        {
            if (deadline.HasExpired)
            {
                _expired = true;
                return 0u;
            }
            _inner.Underlying.SetReceiveTimeout(deadline.SocketTimeoutMilliseconds);
        }
        return _inner.Read(buffer, offset, count);
    }

    public nuint Write(byte[] buffer, nuint offset, nuint count)
    {
        if (_deadline is HttpDeadline deadline)
        {
            if (deadline.HasExpired)
            {
                _expired = true;
                return 0u;
            }
            _inner.Underlying.SetSendTimeout(deadline.SocketTimeoutMilliseconds);
        }
        return _inner.Write(buffer, offset, count);
    }

    public long Position => -1;

    public long Length => -1;

    public bool Seek(long offset, SeekOrigin origin) => false;

    public void Flush() => _inner.Flush();

    public void Close() => _inner.Close();

    /// `Unknown` once the deadline refused a call, so a reader does not take
    /// the refusal for the peer finishing.
    public IOError Error => _expired ? IOError.Unknown : _inner.Error;
}
