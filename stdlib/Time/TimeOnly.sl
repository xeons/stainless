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

import Standard.Collections;

/// A time of day and no date: C#'s `System.TimeOnly`.
///
///     var opens = new TimeOnly(9, 30);
///     var closes = opens.Add(TimeSpan.FromHours(8));   // 17:30
///
/// To the nanosecond, from midnight to one nanosecond before the next.
/// Adding wraps round midnight, and a part out of range aborts where C#
/// throws. Written and read as `HH:mm:ss`, with a fraction when there is one.
public struct TimeOnly : IEquatable<TimeOnly>, IComparable<TimeOnly>, IHashable
{
    private long _nanoseconds;

    /// `hour`:`minute`.
    public TimeOnly(int hour, int minute) : this(hour, minute, 0, 0, 0) { }

    /// `hour`:`minute`:`second`.
    public TimeOnly(int hour, int minute, int second) : this(hour, minute, second, 0, 0) { }

    /// `hour`:`minute`:`second` and `millisecond`.
    public TimeOnly(int hour, int minute, int second, int millisecond) : this(hour, minute, second, millisecond, 0) { }

    /// `hour`:`minute`:`second`, `millisecond` and `microsecond`.
    public TimeOnly(int hour, int minute, int second, int millisecond, int microsecond)
    {
        if (hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59 ||
            millisecond < 0 || millisecond > 999 || microsecond < 0 || microsecond > 999)
            sl_fail("TimeOnly: a part is out of range");

        _nanoseconds = (long)hour * NanosecondsPerHour + (long)minute * NanosecondsPerMinute +
                       (long)second * NanosecondsPerSecond + (long)millisecond * NanosecondsPerMillisecond +
                       (long)microsecond * NanosecondsPerMicrosecond;
    }

    /// Midnight.
    public static TimeOnly MinValue => default(TimeOnly);

    /// One nanosecond before midnight.
    public static TimeOnly MaxValue => FromTimeSpan(TimeSpan.FromNanoseconds(NanosecondsPerDay - 1));

    /// The time `span` after midnight. Aborts unless it is within one day.
    public static TimeOnly FromTimeSpan(TimeSpan span)
    {
        if (span.Nanoseconds < 0 || span.Nanoseconds >= NanosecondsPerDay)
            sl_fail("TimeOnly.FromTimeSpan: not within one day");
        TimeOnly made;
        made._nanoseconds = span.Nanoseconds;
        return made;
    }

    /// The time part of `when`.
    public static TimeOnly FromDateTime(DateTime when) =>
        FromTimeSpan(TimeSpan.FromNanoseconds((long)when.Hour * NanosecondsPerHour +
            (long)when.Minute * NanosecondsPerMinute + (long)when.Second * NanosecondsPerSecond +
            (long)when.Nanosecond));

    /// How long after midnight it is.
    public TimeSpan ToTimeSpan() => TimeSpan.FromNanoseconds(_nanoseconds);

    /// The hour, 0 to 23.
    public int Hour => (int)(_nanoseconds / NanosecondsPerHour);

    /// The minute, 0 to 59.
    public int Minute => (int)(_nanoseconds / NanosecondsPerMinute % 60);

    /// The second, 0 to 59.
    public int Second => (int)(_nanoseconds / NanosecondsPerSecond % 60);

    /// The millisecond, 0 to 999.
    public int Millisecond => (int)(_nanoseconds / NanosecondsPerMillisecond % 1000);

    /// The microsecond within the millisecond, 0 to 999.
    public int Microsecond => (int)(_nanoseconds / NanosecondsPerMicrosecond % 1000);

    /// The nanosecond within the microsecond, 0 to 999.
    public int Nanosecond => (int)(_nanoseconds % 1000);

    /// Hundreds of nanoseconds since midnight, as C# counts ticks.
    public long Ticks => _nanoseconds / 100;

    /// `span` later, round midnight as often as it takes.
    public TimeOnly Add(TimeSpan span)
    {
        int wrapped;
        return Add(span, out wrapped);
    }

    /// `span` later, and how many midnights were passed: negative going back.
    public TimeOnly Add(TimeSpan span, out int wrappedDays)
    {
        long total = _nanoseconds + span.Nanoseconds;
        long days = total / NanosecondsPerDay;
        long within = total % NanosecondsPerDay;
        if (within < 0)
        {
            within += NanosecondsPerDay;
            days--;
        }
        wrappedDays = (int)days;
        TimeOnly made;
        made._nanoseconds = within;
        return made;
    }

    /// `hours` later, round midnight.
    public TimeOnly AddHours(double hours) =>
        Add(TimeSpan.FromNanoseconds((long)(hours * (double)NanosecondsPerHour)));

    /// `minutes` later, round midnight.
    public TimeOnly AddMinutes(double minutes) =>
        Add(TimeSpan.FromNanoseconds((long)(minutes * (double)NanosecondsPerMinute)));

    /// Whether this is from `start` up to but not including `end`, going round
    /// midnight when `end` is earlier than `start`.
    public bool IsBetween(TimeOnly start, TimeOnly end) =>
        start._nanoseconds <= end._nanoseconds
            ? _nanoseconds >= start._nanoseconds && _nanoseconds < end._nanoseconds
            : _nanoseconds >= start._nanoseconds || _nanoseconds < end._nanoseconds;

    /// The hour, minute and second.
    public void Deconstruct(out int hour, out int minute, out int second)
    {
        hour = Hour;
        minute = Minute;
        second = Second;
    }

    /// `HH:mm:ss`, and the fraction of a second when there is one.
    public String ToString()
    {
        String text = PadNumber((long)Hour, 2u) + ":" + PadNumber((long)Minute, 2u) + ":" + PadNumber((long)Second, 2u);
        long fraction = _nanoseconds % NanosecondsPerSecond;
        if (fraction == 0)
            return text;

        String digits = PadNumber(fraction, 9u);
        nuint length = 9u;
        while (digits.GetByteAt(length - 1u) == (byte)'0')
            length--;
        return text + "." + digits.Substring(0u, length);
    }

    /// Reads `HH:mm`, `HH:mm:ss` or `HH:mm:ss.fffffffff`.
    ///
    /// @failure TimeError.Malformed   not one of those shapes
    /// @failure TimeError.OutOfRange  that shape and no real time
    public static Result<TimeOnly, TimeError> Parse(String text)
    {
        nuint length = text.ByteLength();
        if (length < 5u || text.GetByteAt(2u) != (byte)':' || (length > 5u && (length < 8u || text.GetByteAt(5u) != (byte)':')))
            return Fail(TimeError.Malformed);

        int hour = ParseDigits(text, 0u, 2u);
        int minute = ParseDigits(text, 3u, 2u);
        int second = length >= 8u ? ParseDigits(text, 6u, 2u) : 0;
        if (hour < 0 || minute < 0 || second < 0)
            return Fail(TimeError.Malformed);

        long fraction = 0;
        if (length > 8u)
        {
            nuint digits = length - 9u;
            if (text.GetByteAt(8u) != (byte)'.' || digits == 0u || digits > 9u)
                return Fail(TimeError.Malformed);
            int read = ParseDigits(text, 9u, digits);
            if (read < 0)
                return Fail(TimeError.Malformed);
            fraction = (long)read;
            for (nuint i = digits; i < 9u; i++)
                fraction *= 10;
        }

        if (hour > 23 || minute > 59 || second > 59)
            return Fail(TimeError.OutOfRange);
        return Ok(FromTimeSpan(TimeSpan.FromNanoseconds((long)hour * NanosecondsPerHour +
            (long)minute * NanosecondsPerMinute + (long)second * NanosecondsPerSecond + fraction)));
    }

    public bool Equals(TimeOnly other) => _nanoseconds == other._nanoseconds;
    public int CompareTo(TimeOnly other) =>
        _nanoseconds < other._nanoseconds ? -1 : _nanoseconds > other._nanoseconds ? 1 : 0;
    public nuint GetHashCode() => (nuint)_nanoseconds;

    /// How long from `earlier` to `later`, going forward round midnight, so
    /// never negative.
    public static TimeSpan operator -(TimeOnly later, TimeOnly earlier)
    {
        long difference = later._nanoseconds - earlier._nanoseconds;
        return TimeSpan.FromNanoseconds(difference < 0 ? difference + NanosecondsPerDay : difference);
    }

    public static bool operator ==(TimeOnly left, TimeOnly right) => left._nanoseconds == right._nanoseconds;
    public static bool operator !=(TimeOnly left, TimeOnly right) => left._nanoseconds != right._nanoseconds;
    public static bool operator <(TimeOnly left, TimeOnly right) => left._nanoseconds < right._nanoseconds;
    public static bool operator >(TimeOnly left, TimeOnly right) => left._nanoseconds > right._nanoseconds;
    public static bool operator <=(TimeOnly left, TimeOnly right) => left._nanoseconds <= right._nanoseconds;
    public static bool operator >=(TimeOnly left, TimeOnly right) => left._nanoseconds >= right._nanoseconds;
}
