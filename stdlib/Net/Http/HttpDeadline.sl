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

import Standard.Time;

/// How long a request has left, measured on the monotonic clock from when it
/// began. One is made per `Send` and shared by every step: connecting, TLS,
/// writing, reading, the redirects that follow.
internal sealed class HttpDeadline
{
    private Stopwatch _clock = new Stopwatch();
    private long _budget;

    /// A deadline `timeout` from now. Zero or negative is none at all.
    internal HttpDeadline(TimeSpan timeout)
    {
        long milliseconds = timeout.Nanoseconds / NanosecondsPerMillisecond;
        _budget = milliseconds <= 0 ? -1 : milliseconds;
    }

    /// Whether there is a deadline at all.
    internal bool IsBounded => _budget >= 0;

    /// Milliseconds left, never below zero. Meaningless when not bounded.
    internal long RemainingMilliseconds
    {
        get
        {
            long elapsed = _clock.Elapsed.Nanoseconds / NanosecondsPerMillisecond;
            long left = _budget - elapsed;
            return left < 0 ? 0 : left;
        }
    }

    /// Whether the time has run out.
    internal bool HasExpired => IsBounded && RemainingMilliseconds == 0;

    /// What a socket timeout should be set to: the time left, at least one
    /// millisecond, or zero for none.
    internal int SocketTimeoutMilliseconds
    {
        get
        {
            if (!IsBounded)
                return 0;
            long left = RemainingMilliseconds;
            if (left < 1)
                return 1;
            if (left > 2147483647)
                return 2147483647;
            return (int)left;
        }
    }

    /// What a wait should be given: the time left, or -1 for forever.
    internal int WaitMilliseconds => IsBounded ? SocketTimeoutMilliseconds : -1;

    /// Stops timing, for a body the caller streams at its own pace.
    internal void RemoveHttpDeadline() => _budget = -1;
}
