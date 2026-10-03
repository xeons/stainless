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

/// The half of a `CancellationTokenSource` the work holds: it can be asked
/// whether to stop, and waited on, but not cancelled. .NET's
/// `System.Threading.CancellationToken`.
///
/// A token copies freely and crosses threads; every copy follows the one
/// source. The zero value is `CancellationToken.None`, which nothing cancels.
public struct CancellationToken
{
    CancellationTokenSource? _source;

    internal CancellationToken(CancellationTokenSource source)
    {
        _source = source;
    }

    /// A token nothing cancels, for work that is never asked to stop.
    public static CancellationToken None => default(CancellationToken);

    /// Whether this token's source has been cancelled.
    public bool IsCancellationRequested
    {
        get
        {
            CancellationTokenSource? source = _source;
            return source != null && source.IsCancellationRequested;
        }
    }

    /// Whether anything can cancel this token: false for `None`.
    public bool CanBeCanceled => _source != null;

    /// Sleeps for `milliseconds`, waking the moment cancellation is requested.
    /// Answers whether it was: the shape of a worker's loop,
    /// `while (!token.WaitFor(1000u)) DoWork();`.
    ///
    /// @param milliseconds  how long to sleep at most
    /// @returns true when cancelled, false when the time ran out
    public bool WaitFor(ulong milliseconds)
    {
        CancellationTokenSource? source = _source;
        if (source == null)
        {
            sl_thread_sleep(milliseconds);
            return false;
        }
        return source.WaitForCancellation(milliseconds);
    }

    /// Blocks until cancellation is requested. On `None` that is never, so it
    /// returns at once rather than blocking for ever.
    public void Wait()
    {
        CancellationTokenSource? source = _source;
        if (source != null)
            source.WaitForCancellation();
    }

    /// Runs `callback` when cancellation is requested, on the thread that asks
    /// for it -- or now, on this thread, if it already has been.
    ///
    /// @param callback  what to run; it MUST NOT wait for the work being cancelled
    /// @returns a registration whose `Dispose` withdraws the callback. Letting it
    ///          go does not: the callback stays until the source is cancelled
    public CancellationTokenRegistration Register(Action callback)
    {
        CancellationTokenSource? source = _source;
        if (source == null)
            return new CancellationTokenRegistration(null, 0);
        return source.RegisterCancellation(callback);
    }
}
