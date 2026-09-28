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
internal sealed class HttpConnectionPool
{
    private Monitor<int> _lock = new Monitor<int>(0);
    private List<HttpIdleConnection> _idle = new List<HttpIdleConnection>();
    private Dictionary<String, nuint> _open = new Dictionary<String, nuint>();
    private nuint _maxPerServer;
    private TimeSpan _idleTimeout;
    private bool _disposed = false;

    internal HttpConnectionPool(nuint maxPerServer, TimeSpan idleTimeout)
    {
        _maxPerServer = maxPerServer == 0u ? 1u : maxPerServer;
        _idleTimeout = idleTimeout;
    }

    /// An idle connection on `key` to reuse, or a place for a new one, which
    /// the caller MUST then either make or give back with
    /// `CancelHttpReservation`.
    ///
    /// @failure HttpError.Timeout   the route stayed at its limit until the
    ///                              deadline
    /// @failure HttpError.Disposed  the pool has been closed
    internal HttpError ReserveHttpConnection(String key, HttpDeadline deadline, bool allowIdle,
                                             out IHttpConnection? idle)
    {
        idle = null;
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
                IHttpConnection? found = allowIdle ? TakeIdleHttpConnection(key, closing) : null;
                if (found != null)
                {
                    idle = found;
                    break;
                }
                nuint open = _open.GetValueOrDefault(key, 0u);
                if (open < _maxPerServer)
                {
                    _open.SetValue(key, open + 1u);
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

    /// Gives back a place `ReserveHttpConnection` made, for a connection that
    /// was never made.
    internal void CancelHttpReservation(String key)
    {
        var held = _lock.Enter();
        ForgetHttpConnection(key);
        held.PulseAll();
    }

    /// Takes a connection back after an exchange: to reuse when `reusable`,
    /// and to close otherwise.
    internal void ReleaseHttpConnection(IHttpConnection connection, bool reusable)
    {
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

    /// Closes every idle connection and refuses to hold any more. A busy one
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
            held.PulseAll();
        }
        foreach (var connection in closing)
            connection.CloseHttpConnection();
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

    private void ForgetHttpConnection(String key)
    {
        nuint open = _open.GetValueOrDefault(key, 0u);
        if (open <= 1u)
            _open.Remove(key);
        else
            _open.SetValue(key, open - 1u);
    }
}

/// An idle connection and when it became idle.
internal sealed class HttpIdleConnection
{
    internal IHttpConnection Connection;
    internal TimeSpan Since;

    internal HttpIdleConnection(IHttpConnection connection, TimeSpan since)
    {
        Connection = connection;
        Since = since;
    }
}
