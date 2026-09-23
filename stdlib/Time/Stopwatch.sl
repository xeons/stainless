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

module Standard.Time;

// ------------------------------------------------------------------- clock

/// A stopwatch over the monotonic counter.
///
/// This is the only correct way to measure a duration: the wall clock can jump
/// while you are timing, and a measurement that came out negative because NTP
/// stepped the clock is a bug nobody finds.
///
///     var clock = new Stopwatch();
///     DoTheWork();
///     Console.WriteLine(clock.Elapsed.Format());
public class Stopwatch
{
    long _started;

    /// A clock that starts now. There is no separate `Start`: making one is
    /// what starts it.
    public Stopwatch() => _started = sl_time_monotonic();

    /// How long since it was made, or since `Restart`.
    public TimeSpan Elapsed => TimeSpan.FromNanoseconds(sl_time_monotonic() - _started);

    /// Starts again from now, returning what had passed until this moment.
    public TimeSpan Restart()
    {
        long now = sl_time_monotonic();
        var span = TimeSpan.FromNanoseconds(now - _started);
        _started = now;
        return span;
    }

    /// A reading of the monotonic counter, for code that would rather keep
    /// the number than an object. Meaningless on its own; subtract two.
    public static TimeSpan GetTimestamp()
    {
        return TimeSpan.FromNanoseconds(sl_time_monotonic());
    }
}
