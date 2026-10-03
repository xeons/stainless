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

import Standard.Collections;
import Standard.Threading;
import Standard.Time;

/// The connections a handler keeps open, by route.
///
/// A route is a scheme, a host, a port and a proxy, and each route may have
/// at most `maxPerServer` connections open, idle or busy. A request that
/// finds none idle and the route at its limit waits, within its deadline, for
/// one to be given back. An idle connection is reused only while it has been
/// idle less than `idleTimeout` and still looks open.
///
/// **A multiplexed connection is shared, not lent.** An HTTP/2 connection
/// stays in the pool while requests run on it, and each request takes one of
/// its streams. While one is being opened to a route, a request that could
/// use it waits for it rather than opening another; while every stream of
/// the route's connection is busy, a request waits for one to end, unless
/// `allowsMultipleHttp2` lets it open a second connection. A request that
/// allows both versions opens a connection offering h2 rather than take an
/// idle HTTP/1.1 one, until a server of the route has answered without h2.
internal sealed class HttpConnectionPool
{
    private Monitor<int> _lock = new Monitor<int>(0);
    private List<HttpIdleConnection> _idle = new List<HttpIdleConnection>();
    private List<IHttpConnection> _shared = new List<IHttpConnection>();
    private Dictionary<String, nuint> _open = new Dictionary<String, nuint>();
    private Dictionary<String, nuint> _opening = new Dictionary<String, nuint>();
    private List<String> _http11Only = new List<String>();
    private nuint _maxPerServer;
    private TimeSpan _idleTimeout;
    private bool _allowsMultipleHttp2;
    private bool _disposed = false;

    internal HttpConnectionPool(nuint maxPerServer, TimeSpan idleTimeout, bool allowsMultipleHttp2)
    {
        _maxPerServer = maxPerServer == 0u ? 1u : maxPerServer;
        _idleTimeout = idleTimeout;
        _allowsMultipleHttp2 = allowsMultipleHttp2;
    }

    /// A connection on `key` to use — a shared one with a stream reserved,
    /// or an idle one — or a place for a new one, which the caller MUST then
    /// either make and hand to `AddHttpConnection` or give back with
    /// `CancelHttpReservation`.
    ///
    /// `mayAddHttp2` false makes a request wait for a stream on a busy
    /// shared connection even when `allowsMultipleHttp2` would let it open
    /// another: a request that has already opened one that came up with no
    /// stream free MUST NOT open more, or a server allowing no streams would
    /// have it open connections without end.
    ///
    /// @failure HttpError.Timeout   the route stayed at its limit until the
    ///                              deadline
    /// @failure HttpError.Disposed  the pool has been closed
    internal HttpError ReserveHttpConnection(String key, HttpDeadline deadline, HttpVersionChoice choice,
                                             bool allowIdle, bool mayAddHttp2, out IHttpConnection? found)
    {
        found = null;
        var closing = new List<IHttpConnection>();
        HttpError outcome = HttpError.None;
        {
            var held = _lock.Enter();
            while (true)
            {
                if (_disposed)
                {
                    outcome = HttpError.Disposed;
                    break;
                }
                bool wait = false;
                if (choice.AllowsHttp2)
                {
                    bool busy = false;
                    IHttpConnection? shared = TakeSharedHttpStream(key, closing, out busy);
                    if (shared != null)
                    {
                        found = shared;
                        break;
                    }
                    bool opening = _opening.GetValueOrDefault(key, 0u) > 0u && !_http11Only.Contains(key);
                    if ((busy && (!_allowsMultipleHttp2 || !mayAddHttp2)) || (opening && !busy))
                        wait = true;
                }
                // A request that may use HTTP/2 tries for it before it takes an
                // idle HTTP/1.1 connection, unless the route has refused h2.
                bool takesIdle = choice.AllowsHttp11 && (!choice.AllowsHttp2 || _http11Only.Contains(key));
                if (!wait && allowIdle && takesIdle)
                {
                    IHttpConnection? idle = TakeIdleHttpConnection(key, closing);
                    if (idle != null)
                    {
                        found = idle;
                        break;
                    }
                }
                nuint open = _open.GetValueOrDefault(key, 0u);
                if (!wait && open < _maxPerServer)
                {
                    _open.SetValue(key, open + 1u);
                    if (choice.AllowsHttp2)
                        _opening.SetValue(key, _opening.GetValueOrDefault(key, 0u) + 1u);
                    break;
                }
                if (deadline.HasExpired)
                {
                    outcome = HttpError.Timeout;
                    break;
                }
                held.WaitFor(deadline.IsBounded ? (ulong)deadline.RemainingMilliseconds : 1000u);
            }
        }
        foreach (var connection in closing)
            connection.CloseHttpConnection();
        return outcome;
    }

    /// Takes a connection that `ReserveHttpConnection` made a place for. A
    /// multiplexed one joins the shared connections, and a stream on it is
    /// reserved for the caller when it answers true. Once the pool has been
    /// closed, the connection is closed rather than added, and the answer is
    /// `Disposed`.
    internal HttpError AddHttpConnection(String key, IHttpConnection connection, HttpVersionChoice choice,
                                         out bool reserved)
    {
        reserved = false;
        bool close = false;
        {
            var held = _lock.Enter();
            EndHttpOpening(key, choice);
            if (_disposed)
            {
                ForgetHttpConnection(key);
                close = true;
            }
            else if (connection.IsMultiplexed)
            {
                _shared.Add(connection);
                reserved = connection.TryReserveHttpStream();
            }
            else if (choice.AllowsHttp2 && !_http11Only.Contains(key))
            {
                _http11Only.Add(key);
            }
            held.PulseAll();
        }
        if (!close)
            return HttpError.None;
        connection.CloseHttpConnection();
        return HttpError.Disposed;
    }

    /// Gives back a place `ReserveHttpConnection` made, for a connection that
    /// was never made.
    internal void CancelHttpReservation(String key, HttpVersionChoice choice)
    {
        var held = _lock.Enter();
        EndHttpOpening(key, choice);
        ForgetHttpConnection(key);
        held.PulseAll();
    }

    /// Takes a connection back after an exchange: to reuse when `reusable`,
    /// and to close otherwise. A multiplexed connection is never given back
    /// this way; its streams end by themselves.
    internal void ReleaseHttpConnection(IHttpConnection connection, bool reusable)
    {
        if (connection.IsMultiplexed)
            return;
        bool close = false;
        {
            var held = _lock.Enter();
            if (reusable && !_disposed)
            {
                _idle.Add(new HttpIdleConnection(connection, Stopwatch.GetTimestamp()));
            }
            else
            {
                ForgetHttpConnection(connection.PoolKey);
                close = true;
            }
            held.PulseAll();
        }
        if (close)
            connection.CloseHttpConnection();
    }

    /// Wakes every request waiting for a connection or a stream, after one
    /// has ended.
    internal void PulseHttpWaiters()
    {
        var held = _lock.Enter();
        held.PulseAll();
    }

    /// Closes every idle connection, and every shared one once its streams
    /// have ended, and refuses to hold any more. A busy HTTP/1.1 connection
    /// is closed when it is given back.
    internal void CloseAllHttpConnections()
    {
        var closing = new List<IHttpConnection>();
        {
            var held = _lock.Enter();
            _disposed = true;
            foreach (var entry in _idle)
            {
                ForgetHttpConnection(entry.Connection.PoolKey);
                closing.Add(entry.Connection);
            }
            _idle.Clear();
            foreach (var connection in _shared)
            {
                ForgetHttpConnection(connection.PoolKey);
                closing.Add(connection);
            }
            _shared.Clear();
            held.PulseAll();
        }
        foreach (var connection in closing)
            connection.CloseHttpConnection();
    }

    /// A shared connection on `key` with a stream now reserved, taking out
    /// every dead or expired one it passes into `closing`. `busy` says a live
    /// one was there with every stream in use. The caller holds the lock.
    private IHttpConnection? TakeSharedHttpStream(String key, List<IHttpConnection> closing, out bool busy)
    {
        busy = false;
        TimeSpan now = Stopwatch.GetTimestamp();
        nuint i = _shared.Count;
        while (i > 0u)
        {
            i--;
            IHttpConnection connection = _shared[i];
            if (connection.PoolKey != key)
                continue;
            if (!connection.IsHttpConnectionAlive() || connection.HasHttpIdleTimeoutPassed(now, _idleTimeout))
            {
                _shared.RemoveAt(i);
                ForgetHttpConnection(key);
                closing.Add(connection);
                continue;
            }
            if (connection.TryReserveHttpStream())
                return connection;
            busy = true;
        }
        return null;
    }

    /// The newest usable idle connection on `key`, taking out every stale one
    /// it passes into `closing`. The caller holds the lock.
    private IHttpConnection? TakeIdleHttpConnection(String key, List<IHttpConnection> closing)
    {
        TimeSpan now = Stopwatch.GetTimestamp();
        nuint i = _idle.Count;
        while (i > 0u)
        {
            i--;
            HttpIdleConnection entry = _idle[i];
            if (entry.Connection.PoolKey != key)
                continue;
            _idle.RemoveAt(i);
            bool expired = !_idleTimeout.IsNegative && now - entry.Since >= _idleTimeout;
            if (expired || !entry.Connection.IsHttpConnectionAlive())
            {
                ForgetHttpConnection(key);
                closing.Add(entry.Connection);
                continue;
            }
            return entry.Connection;
        }
        return null;
    }

    private void EndHttpOpening(String key, HttpVersionChoice choice)
    {
        if (!choice.AllowsHttp2)
            return;
        nuint opening = _opening.GetValueOrDefault(key, 0u);
        if (opening <= 1u)
            _opening.Remove(key);
        else
            _opening.SetValue(key, opening - 1u);
    }

    private void ForgetHttpConnection(String key)
    {
        nuint open = _open.GetValueOrDefault(key, 0u);
        if (open <= 1u)
            _open.Remove(key);
        else
            _open.SetValue(key, open - 1u);
    }
}
