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

// ---------------------------------------------------------------- duration

/// A length of time, positive or negative.
///
/// Made by naming the unit -- `TimeSpan.FromSeconds(30)` -- because a bare
/// number of nanoseconds at a call site says nothing about which unit was
/// meant, and this is the mistake that is silent when it happens.
///
///     var timeout = TimeSpan.FromSeconds(30);
///     if (waited > timeout) { ... }
public struct TimeSpan
{
    /// The length in nanoseconds, which is the whole of the value. Readable
    /// and writable because a struct's fields are, but a `From` method is what
    /// says which unit was meant.
    public long Nanoseconds;

    /// A length in nanoseconds. The others are this times a factor, so this is
    /// the one that cannot overflow on the way in.
    public static TimeSpan FromNanoseconds(long value)
    {
        TimeSpan span;
        span.Nanoseconds = value;
        return span;
    }

    /// A length in whole microseconds.
    public static TimeSpan FromMicroseconds(long value)
    {
        return FromNanoseconds(value * NanosecondsPerMicrosecond);
    }

    /// A length in whole milliseconds.
    public static TimeSpan FromMilliseconds(long value)
    {
        return FromNanoseconds(value * NanosecondsPerMillisecond);
    }

    /// A length in whole seconds.
    public static TimeSpan FromSeconds(long value)
    {
        return FromNanoseconds(value * NanosecondsPerSecond);
    }

    /// A length in whole minutes.
    public static TimeSpan FromMinutes(long value)
    {
        return FromNanoseconds(value * NanosecondsPerMinute);
    }

    /// A length in whole hours.
    public static TimeSpan FromHours(long value)
    {
        return FromNanoseconds(value * NanosecondsPerHour);
    }

    /// A length in whole days of 24 hours each. Past about 106,751 days the
    /// multiplication overflows a `long` of nanoseconds, silently.
    public static TimeSpan FromDays(long value)
    {
        return FromNanoseconds(value * NanosecondsPerDay);
    }

    // The whole length in one unit, fractions kept -- the same doubles .NET's
    // TimeSpan answers with. A caller counting whole units casts, which is
    // also the only spelling that says which way it wanted the remainder to
    // go.

    /// The whole length as microseconds.
    public double TotalMicroseconds => (double)Nanoseconds / 1000.0;

    /// The whole length as milliseconds.
    public double TotalMilliseconds => (double)Nanoseconds / 1000000.0;

    /// The whole length as seconds.
    public double TotalSeconds => (double)Nanoseconds / 1000000000.0;

    /// The whole length as minutes.
    public double TotalMinutes => TotalSeconds / 60.0;

    /// The whole length as hours.
    public double TotalHours => TotalSeconds / 3600.0;

    /// The whole length as 24-hour days. A calendar day across a
    /// daylight-saving change is not this.
    public double TotalDays => TotalSeconds / 86400.0;

    /// True when the length is below zero, which is what subtracting a later
    /// instant from an earlier one gives.
    public bool IsNegative => Nanoseconds < 0;

    /// Arithmetic, as arithmetic. Adding two lengths of time is what `+` means
    /// everywhere else, and spelling it `Time.Add(a, b)` only hid that.
    public static TimeSpan operator +(TimeSpan left, TimeSpan right)
    {
        return FromNanoseconds(left.Nanoseconds + right.Nanoseconds);
    }

    /// One length less another. The result may be negative.
    public static TimeSpan operator -(TimeSpan left, TimeSpan right)
    {
        return FromNanoseconds(left.Nanoseconds - right.Nanoseconds);
    }

    /// The same length the other way round.
    public static TimeSpan operator -(TimeSpan span)
    {
        return FromNanoseconds(0 - span.Nanoseconds);
    }

    /// Scaling by a count: half a timeout, or three retries' worth of one.
    public static TimeSpan operator *(TimeSpan span, long times)
    {
        return FromNanoseconds(span.Nanoseconds * times);
    }

    /// The same scaling with the operands the other way round.
    public static TimeSpan operator *(long times, TimeSpan span)
    {
        return FromNanoseconds(span.Nanoseconds * times);
    }

    /// A length split into `parts`, truncated toward zero. Dividing by zero
    /// ends the program, as integer division does.
    public static TimeSpan operator /(TimeSpan span, long parts)
    {
        return FromNanoseconds(span.Nanoseconds / parts);
    }

    /// Whether the two lengths are equal, to the nanosecond.
    public static bool operator ==(TimeSpan left, TimeSpan right)
    {
        return left.Nanoseconds == right.Nanoseconds;
    }

    /// Whether the two lengths differ.
    public static bool operator !=(TimeSpan left, TimeSpan right)
    {
        return left.Nanoseconds != right.Nanoseconds;
    }

    /// Whether `left` is the shorter. Signed, so a negative length is below a positive one.
    public static bool operator <(TimeSpan left, TimeSpan right)
    {
        return left.Nanoseconds < right.Nanoseconds;
    }

    /// Whether `left` is the longer.
    public static bool operator >(TimeSpan left, TimeSpan right)
    {
        return left.Nanoseconds > right.Nanoseconds;
    }

    /// Whether `left` is no longer than `right`.
    public static bool operator <=(TimeSpan left, TimeSpan right)
    {
        return left.Nanoseconds <= right.Nanoseconds;
    }

    /// Whether `left` is at least as long as `right`.
    public static bool operator >=(TimeSpan left, TimeSpan right)
    {
        return left.Nanoseconds >= right.Nanoseconds;
    }

    /// -1, 0 or 1, for sorting. The operators answer the question a program
    /// usually has; this answers the one a sort has.
    public static int Compare(TimeSpan left, TimeSpan right)
    {
        if (left.Nanoseconds < right.Nanoseconds)
            return -1;
        if (left.Nanoseconds > right.Nanoseconds)
            return 1;
        return 0;
    }

    /// `1h02m03.004s`, with the leading units dropped when they are zero --
    /// the way a log line wants it.
    public String Format() => FormatTimeSpan(this);
}
