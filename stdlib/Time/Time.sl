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

/// Time, of the two kinds that must not be confused.
///
/// A `DateTimeOffset` is a point on the wall clock: a date and a time of
/// day. It can jump, because a user sets the clock, NTP corrects it, or a
/// laptop wakes up. Never subtract two of them to find out how long
/// something took.
///
/// A `TimeSpan` is a length of time, and `Stopwatch` reads a monotonic
/// counter that only ever goes forward. That pair is what a measurement
/// wants.
///
/// Both are structs over a single `long` of nanoseconds, so they cost nothing,
/// travel in a register, and compare and subtract as the numbers they are.
/// Sixty-four bits of nanoseconds reaches 292 years either side of 1970, which
/// is not the reason anything here will go wrong.
module Standard.Time;

extern "C"
{
    long sl_time_now();
    long sl_time_monotonic();
    bool sl_time_parts(long nanoseconds, bool local, long* parts);
    long sl_time_from_parts(long year, long month, long day, long hour,
                            long minute, long second, long nanosecond, bool local);
    long sl_time_zone_offset(long nanoseconds);
}

// The conversion factors, public so that a count of nanoseconds bound for a C
// API can be written as a multiplication by a name.

/// Nanoseconds in a microsecond.
public const long NanosecondsPerMicrosecond = 1000;

/// Nanoseconds in a millisecond.
public const long NanosecondsPerMillisecond = 1000000;

/// Nanoseconds in a second.
public const long NanosecondsPerSecond = 1000000000;

/// Nanoseconds in a minute.
public const long NanosecondsPerMinute = 60000000000;

/// Nanoseconds in an hour.
public const long NanosecondsPerHour = 3600000000000;

/// Nanoseconds in a day, which is 24 hours exactly. A calendar day across a
/// daylight-saving change is not this, and nothing here pretends otherwise:
/// add a day to a `DateTimeOffset` and you have added 24 hours.
public const long NanosecondsPerDay = 86400000000000;

/// A duration written the way a log line wants it: `1h02m03.004s`, with the
/// leading units dropped when they are zero.
String FormatTimeSpan(TimeSpan span)
{
    var text = new StringBuilder();

    long left = span.Nanoseconds;
    if (left < 0)
    {
        text.Append("-");
        left = 0 - left;
    }

    long hours = left / NanosecondsPerHour;
    left = left % NanosecondsPerHour;
    long minutes = left / NanosecondsPerMinute;
    left = left % NanosecondsPerMinute;
    long seconds = left / NanosecondsPerSecond;
    long millis = (left % NanosecondsPerSecond) / NanosecondsPerMillisecond;

    if (hours > 0)
    {
        text.AppendInteger(hours);
        text.Append("h");
        text.Append(PadNumber(minutes, 2u));
        text.Append("m");
        text.Append(PadNumber(seconds, 2u));
    }
    else if (minutes > 0)
    {
        text.AppendInteger(minutes);
        text.Append("m");
        text.Append(PadNumber(seconds, 2u));
    }
    else
    {
        text.AppendInteger(seconds);
    }

    text.Append(".");
    text.Append(PadNumber(millis, 3u));
    text.Append("s");
    return text.ToText();
}

DateTime ToDateTime(DateTimeOffset at, bool local)
{
    long[9] parts;
    DateTime when;

    if (!sl_time_parts(at.Nanoseconds, local, &parts[0]))
    {
        // Outside what the platform can name. Zeroed rather than guessed at,
        // and the year of 0 is what says so.
        when.Year = 0;
        when.Month = 0;
        when.Day = 0;
        when.Hour = 0;
        when.Minute = 0;
        when.Second = 0;
        when.Nanosecond = 0;
        when.DayOfWeek = 0;
        when.DayOfYear = 0;
        return when;
    }

    when.Year = (int)parts[0];
    when.Month = (int)parts[1];
    when.Day = (int)parts[2];
    when.Hour = (int)parts[3];
    when.Minute = (int)parts[4];
    when.Second = (int)parts[5];
    when.Nanosecond = (int)parts[6];
    when.DayOfWeek = (int)parts[7];
    when.DayOfYear = (int)parts[8];
    return when;
}

/// Whether a year has 366 days, by the Gregorian rule.
public bool IsLeapYear(int year)
{
    if (year % 4 != 0)
        return false;
    if (year % 100 != 0)
        return true;
    return year % 400 == 0;
}

/// How many days a month has, which for February depends on the year.
///
/// @param year   the year the month is in, in full
/// @param month  the month, 1 to 12; anything else has no days
/// @see Time.IsLeapYear
public int DaysInMonth(int year, int month)
{
    if (month == 2)
    {
        if (IsLeapYear(year))
            return 29;
        return 28;
    }
    if (month == 4 || month == 6 || month == 9 || month == 11)
        return 30;
    if (month >= 1 && month <= 12)
        return 31;
    return 0;
}

// --------------------------------------------------------------- formatting

String PadNumber(long value, nuint width)
{
    return Text.FromInteger(value).PadLeft(width, "0");
}

/// ISO 8601, to the second: `2026-09-05T14:30:00Z`.
///
/// One format rather than a pattern language, because a pattern language is a
/// small parser and this is the format that machines exchange. Anything else
/// is a `StringBuilder` and the fields, which is what a pattern language would
/// have been doing anyway.
String FormatIso8601(DateTimeOffset at)
{
    var when = at.UtcDateTime;
    var text = new StringBuilder();

    text.Append(PadNumber((long)when.Year, 4u));
    text.Append("-");
    text.Append(PadNumber((long)when.Month, 2u));
    text.Append("-");
    text.Append(PadNumber((long)when.Day, 2u));
    text.Append("T");
    text.Append(PadNumber((long)when.Hour, 2u));
    text.Append(":");
    text.Append(PadNumber((long)when.Minute, 2u));
    text.Append(":");
    text.Append(PadNumber((long)when.Second, 2u));
    text.Append("Z");
    return text.ToText();
}

Result<DateTimeOffset, TimeError> ParseIso8601(String text)
{
    if (text.ByteLength() != 20u)
        return Fail(TimeError.Malformed);
    if (text.GetByteAt(4u) != (byte)'-' || text.GetByteAt(7u) != (byte)'-')
    {
        return Fail(TimeError.Malformed);
    }
    if (text.GetByteAt(10u) != (byte)'T' || text.GetByteAt(19u) != (byte)'Z')
    {
        return Fail(TimeError.Malformed);
    }
    if (text.GetByteAt(13u) != (byte)':' || text.GetByteAt(16u) != (byte)':')
    {
        return Fail(TimeError.Malformed);
    }

    int year = ParseDigits(text, 0u, 4u);
    int month = ParseDigits(text, 5u, 2u);
    int day = ParseDigits(text, 8u, 2u);
    int hour = ParseDigits(text, 11u, 2u);
    int minute = ParseDigits(text, 14u, 2u);
    int second = ParseDigits(text, 17u, 2u);

    if (year < 0 || month < 0 || day < 0 || hour < 0 || minute < 0 || second < 0)
    {
        return Fail(TimeError.Malformed);
    }

    if (month < 1 || month > 12 || day < 1 || day > DaysInMonth(year, month))
    {
        return Fail(TimeError.OutOfRange);
    }

    // 60 rather than 59: a leap second is a real reading of a real clock.
    if (hour > 23 || minute > 59 || second > 60)
        return Fail(TimeError.OutOfRange);

    return Ok(DateTimeOffset.FromUtc(year, month, day, hour, minute, second));
}

/// `count` digits from `start`, or -1 if any of them is not a digit.
int ParseDigits(String text, nuint start, nuint count)
{
    int value = 0;
    for (nuint i = 0u; i < count; i++)
    {
        byte digit = text.GetByteAt(start + i);
        if (digit < 48 || digit > 57)
            return -1;
        value = value * 10 + (int)(digit - 48);
    }
    return value;
}
