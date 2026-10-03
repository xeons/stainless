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

module Standard.Threading;

import Standard.Collections;

/// Says when work should stop, to everything holding one of its tokens.
/// .NET's `System.Threading.CancellationTokenSource`.
///
/// **Cancellation is a request, not an interruption.** Nothing stops a thread:
/// the work asks `IsCancellationRequested` between pieces, or sleeps in
/// `CancellationToken.WaitFor`, which wakes the moment the request arrives.
/// That is the only kind there is, because there is no exception to unwind a
/// thread with.
///
///     var stopping = new CancellationTokenSource();
///     var token = stopping.Token;
///     var worker = new Thread(() =>
///     {
///         while (!token.WaitFor(1000u))
///             PollForWork();
///     });
///     stopping.Cancel();
///     worker.Join();
///
/// A source is cancelled once, and stays cancelled.
public threadsafe class CancellationTokenSource
{
    bool _cancelled;
    byte* _handle;
    byte* _signal;
    List<Action> _callbacks = new List<Action>();
    List<long> _ids = new List<long>();
    long _lastId;

    /// What this source is listening to, for a linked one: undone when it goes.
    List<CancellationTokenRegistration> _links = new List<CancellationTokenRegistration>();

    /// A source not yet cancelled.
    public CancellationTokenSource()
    {
        _handle = sl_mutex_new();
        _signal = sl_condition_new();
    }

    ~CancellationTokenSource()
    {
        for (nuint i = 0u; i < _links.Count; i++)
            _links[i].Dispose();
        sl_condition_free(_signal);
        sl_mutex_free(_handle);
    }

    /// A token to hand to the work this source may stop.
    public CancellationToken Token => new CancellationToken(this);

    /// Whether `Cancel` has been called.
    public bool IsCancellationRequested
    {
        get
        {
            sl_mutex_lock(_handle);
            bool cancelled = _cancelled;
            sl_mutex_unlock(_handle);
            return cancelled;
        }
    }

    /// Asks everything holding a token to stop: wakes every `WaitFor`, then runs
    /// the registered callbacks on this thread, the latest first. A second call
    /// does nothing.
    public void Cancel()
    {
        sl_mutex_lock(_handle);
        if (_cancelled)
        {
            sl_mutex_unlock(_handle);
            return;
        }
        _cancelled = true;
        sl_condition_broadcast(_signal);
        var callbacks = _callbacks;
        _callbacks = new List<Action>();
        _ids = new List<long>();
        sl_mutex_unlock(_handle);

        // Outside the lock, so a callback may use this source.
        for (nuint i = callbacks.Count; i > 0u; i--)
        {
            var callback = callbacks[i - 1u];
            callback();
        }
    }

    /// Cancels once `milliseconds` have passed, from a thread of its own, unless
    /// something cancels first.
    ///
    /// @param milliseconds  how long until the cancellation
    public void CancelAfter(ulong milliseconds)
    {
        var source = this;
        var timer = new Thread(() =>
        {
            if (!source.WaitForCancellation(milliseconds))
                source.Cancel();
        });
        timer.Detach();
    }

    /// A source cancelled when either of two tokens is, or when it is
    /// cancelled itself: a request's own deadline beside the host's shutdown.
    ///
    /// @param first   one token to follow
    /// @param second  the other
    /// @returns a new source, which stops following both when it goes
    public static CancellationTokenSource CreateLinkedTokenSource(
        CancellationToken first, CancellationToken second)
    {
        var linked = new CancellationTokenSource();
        linked.FollowCancellation(first);
        linked.FollowCancellation(second);
        return linked;
    }

    // ---------------------------------------------------- for the token

    /// Waits until cancelled, or until `milliseconds` pass; answers whether it
    /// was cancelled.
    internal bool WaitForCancellation(ulong milliseconds)
    {
        long deadline = ComputeDeadlineAfter(milliseconds);
        sl_mutex_lock(_handle);
        while (!_cancelled)
        {
            if (!WaitBeforeDeadline(_signal, _handle, deadline))
            {
                sl_mutex_unlock(_handle);
                return false;
            }
        }
        sl_mutex_unlock(_handle);
        return true;
    }

    internal void WaitForCancellation()
    {
        sl_mutex_lock(_handle);
        while (!_cancelled)
            sl_condition_wait(_signal, _handle);
        sl_mutex_unlock(_handle);
    }

    /// Keeps `callback` for `Cancel`, or runs it now if that has happened.
    internal CancellationTokenRegistration RegisterCancellation(Action callback)
    {
        sl_mutex_lock(_handle);
        if (_cancelled)
        {
            sl_mutex_unlock(_handle);
            callback();
            return new CancellationTokenRegistration(null, 0);
        }
        _lastId++;
        long id = _lastId;
        _callbacks.Add(callback);
        _ids.Add(id);
        sl_mutex_unlock(_handle);
        return new CancellationTokenRegistration(this, id);
    }

    internal void UnregisterCancellation(long id)
    {
        sl_mutex_lock(_handle);
        for (nuint i = 0u; i < _ids.Count; i++)
        {
            if (_ids[i] == id)
            {
                _ids.RemoveAt(i);
                _callbacks.RemoveAt(i);
                break;
            }
        }
        sl_mutex_unlock(_handle);
    }

    /// Cancels this source when `token` is. The callback holds this source
    /// weakly, so following a long-lived token does not keep it alive.
    void FollowCancellation(CancellationToken token)
    {
        var follower = new CancellationFollower(this);
        _links.Add(token.Register(() => follower.CancelFollowed()));
    }
}

/// The weak hold a linked source's callback has on it.
sealed threadsafe class CancellationFollower
{
    weak CancellationTokenSource? _followed;

    public CancellationFollower(CancellationTokenSource followed)
    {
        _followed = followed;
    }

    public void CancelFollowed()
    {
        CancellationTokenSource? followed = _followed;
        if (followed != null)
            followed.Cancel();
    }
}
