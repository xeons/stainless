// Stainless - an experimental systems language.
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

// Time, of the two kinds that must not be confused.
//
// An `Instant` is a point on the wall clock: a date and a time of day. It can
// jump, because a user sets the clock, NTP corrects it, or a laptop wakes up.
// Never subtract two of them to find out how long something took.
//
// A `Duration` is a length of time, and `Clock` reads a monotonic counter that
// only ever goes forward. That pair is what a measurement wants.
//
// Both are structs over a single `long` of nanoseconds, so they cost nothing,
// travel in a register, and compare and subtract as the numbers they are.
// Sixty-four bits of nanoseconds reaches 292 years either side of 1970, which
// is not the reason anything here will go wrong.
module Standard.Time;

extern "C" {
    long sl_time_now();
    long sl_time_monotonic();
    bool sl_time_parts(long nanoseconds, bool local, long* parts);
    long sl_time_from_parts(long year, long month, long day, long hour,
                            long minute, long second, long nanosecond, bool local);
    long sl_time_zone_offset(long nanoseconds);
}

public const long NanosecondsPerMicrosecond = 1000;
public const long NanosecondsPerMillisecond = 1000000;
public const long NanosecondsPerSecond = 1000000000;
public const long NanosecondsPerMinute = 60000000000;
public const long NanosecondsPerHour = 3600000000000;
public const long NanosecondsPerDay = 86400000000000;

// ---------------------------------------------------------------- duration

/// A length of time, positive or negative.
public struct Duration {
    public long Nanoseconds;
}

public Duration FromNanoseconds(long value) {
    Duration span;
    span.Nanoseconds = value;
    return span;
}

public Duration FromMicroseconds(long value) {
    return FromNanoseconds(value * NanosecondsPerMicrosecond);
}

public Duration FromMilliseconds(long value) {
    return FromNanoseconds(value * NanosecondsPerMillisecond);
}

public Duration FromSeconds(long value) {
    return FromNanoseconds(value * NanosecondsPerSecond);
}

public Duration FromMinutes(long value) {
    return FromNanoseconds(value * NanosecondsPerMinute);
}

public Duration FromHours(long value) { return FromNanoseconds(value * NanosecondsPerHour); }

public Duration FromDays(long value) { return FromNanoseconds(value * NanosecondsPerDay); }

/// Whole units, truncated toward zero. `Milliseconds` of 1,500,000ns is 1.
public long TotalMilliseconds(Duration span) {
    return span.Nanoseconds / NanosecondsPerMillisecond;
}

public long TotalSeconds(Duration span) { return span.Nanoseconds / NanosecondsPerSecond; }

public long TotalMinutes(Duration span) { return span.Nanoseconds / NanosecondsPerMinute; }

public long TotalHours(Duration span) { return span.Nanoseconds / NanosecondsPerHour; }

public long TotalDays(Duration span) { return span.Nanoseconds / NanosecondsPerDay; }

/// The same length with fractions kept, for a measurement being reported
/// rather than counted.
public double AsSeconds(Duration span) {
    return (double)span.Nanoseconds / 1000000000.0;
}

public double AsMilliseconds(Duration span) {
    return (double)span.Nanoseconds / 1000000.0;
}

public Duration Add(Duration left, Duration right) {
    return FromNanoseconds(left.Nanoseconds + right.Nanoseconds);
}

public Duration Subtract(Duration left, Duration right) {
    return FromNanoseconds(left.Nanoseconds - right.Nanoseconds);
}

public Duration Negate(Duration span) { return FromNanoseconds(0 - span.Nanoseconds); }

public bool IsNegative(Duration span) { return span.Nanoseconds < 0; }

public int Compare(Duration left, Duration right) {
    if (left.Nanoseconds < right.Nanoseconds) { return -1; }
    if (left.Nanoseconds > right.Nanoseconds) { return 1; }
    return 0;
}

/// A duration written the way a log line wants it: `1h02m03.004s`, with the
/// leading units dropped when they are zero.
public String FormatDuration(Duration span) {
    var text = new StringBuilder();

    long left = span.Nanoseconds;
    if (left < 0) { text.Append("-"); left = 0 - left; }

    long hours = left / NanosecondsPerHour;
    left = left % NanosecondsPerHour;
    long minutes = left / NanosecondsPerMinute;
    left = left % NanosecondsPerMinute;
    long seconds = left / NanosecondsPerSecond;
    long millis = (left % NanosecondsPerSecond) / NanosecondsPerMillisecond;

    if (hours > 0) {
        text.AppendInteger(hours);
        text.Append("h");
        text.Append(Pad(minutes, 2u));
        text.Append("m");
        text.Append(Pad(seconds, 2u));
    } else if (minutes > 0) {
        text.AppendInteger(minutes);
        text.Append("m");
        text.Append(Pad(seconds, 2u));
    } else {
        text.AppendInteger(seconds);
    }

    text.Append(".");
    text.Append(Pad(millis, 3u));
    text.Append("s");
    return text.ToText();
}

// ----------------------------------------------------------------- instant

/// A point on the wall clock, as nanoseconds since 1970-01-01 UTC.
public struct Instant {
    public long Nanoseconds;
}

/// What time it is now. It can go backwards between two calls; use `Clock` to
/// measure how long something took.
public Instant Now() {
    Instant at;
    at.Nanoseconds = sl_time_now();
    return at;
}

/// The instant at 1970-01-01 00:00:00 UTC, which is where the count starts.
public Instant Epoch() {
    Instant at;
    at.Nanoseconds = 0;
    return at;
}

public Instant FromUnixSeconds(long seconds) {
    Instant at;
    at.Nanoseconds = seconds * NanosecondsPerSecond;
    return at;
}

public Instant FromUnixMilliseconds(long milliseconds) {
    Instant at;
    at.Nanoseconds = milliseconds * NanosecondsPerMillisecond;
    return at;
}

/// Whole seconds since the epoch, rounded toward the epoch. This is what a
/// file's modification time is, and what most C APIs speak.
public long ToUnixSeconds(Instant at) { return at.Nanoseconds / NanosecondsPerSecond; }

public long ToUnixMilliseconds(Instant at) {
    return at.Nanoseconds / NanosecondsPerMillisecond;
}

/// How long after `earlier` the instant `later` is. Negative if it is before.
public Duration Since(Instant later, Instant earlier) {
    return FromNanoseconds(later.Nanoseconds - earlier.Nanoseconds);
}

public Instant Plus(Instant at, Duration span) {
    Instant moved;
    moved.Nanoseconds = at.Nanoseconds + span.Nanoseconds;
    return moved;
}

public Instant Minus(Instant at, Duration span) {
    Instant moved;
    moved.Nanoseconds = at.Nanoseconds - span.Nanoseconds;
    return moved;
}

public int CompareInstants(Instant left, Instant right) {
    if (left.Nanoseconds < right.Nanoseconds) { return -1; }
    if (left.Nanoseconds > right.Nanoseconds) { return 1; }
    return 0;
}

// ---------------------------------------------------------------- calendar

/// An instant broken into the parts a person reads.
///
/// Made by `ToUtc` or `ToLocal`, which is what says which zone the numbers are
/// in -- the struct itself does not carry that, because a date with no zone is
/// exactly as ambiguous as it sounds.
public struct DateTime {
    public int Year;
    public int Month;        // 1-12
    public int Day;          // 1-31
    public int Hour;         // 0-23
    public int Minute;       // 0-59
    public int Second;       // 0-60, because a leap second is a thing
    public int Nanosecond;
    public int DayOfWeek;    // 0 = Sunday
    public int DayOfYear;    // 1-366
}

DateTime Broken(Instant at, bool local) {
    long[9] parts;
    DateTime when;

    if (!sl_time_parts(at.Nanoseconds, local, &parts[0])) {
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

/// The instant as a date and time in UTC.
public DateTime ToUtc(Instant at) { return Broken(at, false); }

/// The instant as a date and time in the machine's local zone, with whatever
/// the platform believes about daylight saving.
public DateTime ToLocal(Instant at) { return Broken(at, true); }

/// A UTC date and time as an instant.
public Instant FromUtc(int year, int month, int day, int hour, int minute, int second) {
    Instant at;
    at.Nanoseconds = sl_time_from_parts((long)year, (long)month, (long)day,
                                        (long)hour, (long)minute, (long)second, 0, false);
    return at;
}

/// A local date and time as an instant. Ambiguous during the hour a clock goes
/// back, and impossible during the hour it goes forward; the platform decides.
public Instant FromLocal(int year, int month, int day, int hour, int minute, int second) {
    Instant at;
    at.Nanoseconds = sl_time_from_parts((long)year, (long)month, (long)day,
                                        (long)hour, (long)minute, (long)second, 0, true);
    return at;
}

/// How far ahead of UTC the local zone was at that instant, in seconds.
/// Negative west of Greenwich.
public long ZoneOffsetSeconds(Instant at) { return sl_time_zone_offset(at.Nanoseconds); }

/// Whether a year has 366 days, by the Gregorian rule.
public bool IsLeapYear(int year) {
    if (year % 4 != 0) { return false; }
    if (year % 100 != 0) { return true; }
    return year % 400 == 0;
}

/// How many days a month has, which for February depends on the year.
public int DaysInMonth(int year, int month) {
    if (month == 2) {
        if (IsLeapYear(year)) { return 29; }
        return 28;
    }
    if (month == 4 || month == 6 || month == 9 || month == 11) { return 30; }
    if (month >= 1 && month <= 12) { return 31; }
    return 0;
}

// --------------------------------------------------------------- formatting

String Pad(long value, nuint width) {
    return Text.FromInteger(value).PadLeft(width, "0");
}

/// ISO 8601, to the second: `2026-09-05T14:30:00Z`.
///
/// One format rather than a pattern language, because a pattern language is a
/// small parser and this is the format that machines exchange. Anything else
/// is a `StringBuilder` and the fields, which is what a pattern language would
/// have been doing anyway.
public String FormatIso(Instant at) {
    var when = ToUtc(at);
    var text = new StringBuilder();

    text.Append(Pad((long)when.Year, 4u));
    text.Append("-");
    text.Append(Pad((long)when.Month, 2u));
    text.Append("-");
    text.Append(Pad((long)when.Day, 2u));
    text.Append("T");
    text.Append(Pad((long)when.Hour, 2u));
    text.Append(":");
    text.Append(Pad((long)when.Minute, 2u));
    text.Append(":");
    text.Append(Pad((long)when.Second, 2u));
    text.Append("Z");
    return text.ToText();
}

/// The date alone: `2026-09-05`.
public String FormatDate(DateTime when) {
    var text = new StringBuilder();
    text.Append(Pad((long)when.Year, 4u));
    text.Append("-");
    text.Append(Pad((long)when.Month, 2u));
    text.Append("-");
    text.Append(Pad((long)when.Day, 2u));
    return text.ToText();
}

/// The time of day alone: `14:30:00`.
public String FormatTime(DateTime when) {
    var text = new StringBuilder();
    text.Append(Pad((long)when.Hour, 2u));
    text.Append(":");
    text.Append(Pad((long)when.Minute, 2u));
    text.Append(":");
    text.Append(Pad((long)when.Second, 2u));
    return text.ToText();
}

/// Why a moment could not be read.
public enum TimeError {
    None,
    Malformed,      // not the shape FormatIso writes
    OutOfRange,     // the shape, but not a date -- the 31st of February
}

/// `2026-09-05T14:30:00Z` back to an instant.
///
/// A `Result` rather than a nullable, because an `Instant` is a struct and a
/// struct is never null (SL0271) -- and because "that is not a date" and "that
/// is not a real date" are worth telling apart.
///
/// Deliberately strict: exactly the shape `FormatIso` writes, so a round trip
/// is exact and anything else is refused rather than half-read.
public Result<Instant, TimeError> ParseIso(String text) {
    if (text.ByteLength() != 20u) { return Fail(TimeError.Malformed); }
    if (text.ByteAt(4u) != (byte)'-' || text.ByteAt(7u) != (byte)'-') {
        return Fail(TimeError.Malformed);
    }
    if (text.ByteAt(10u) != (byte)'T' || text.ByteAt(19u) != (byte)'Z') {
        return Fail(TimeError.Malformed);
    }
    if (text.ByteAt(13u) != (byte)':' || text.ByteAt(16u) != (byte)':') {
        return Fail(TimeError.Malformed);
    }

    int year = Digits(text, 0u, 4u);
    int month = Digits(text, 5u, 2u);
    int day = Digits(text, 8u, 2u);
    int hour = Digits(text, 11u, 2u);
    int minute = Digits(text, 14u, 2u);
    int second = Digits(text, 17u, 2u);

    if (year < 0 || month < 0 || day < 0 || hour < 0 || minute < 0 || second < 0) {
        return Fail(TimeError.Malformed);
    }

    if (month < 1 || month > 12 || day < 1 || day > DaysInMonth(year, month)) {
        return Fail(TimeError.OutOfRange);
    }

    // 60 rather than 59: a leap second is a real reading of a real clock.
    if (hour > 23 || minute > 59 || second > 60) { return Fail(TimeError.OutOfRange); }

    return Ok(FromUtc(year, month, day, hour, minute, second));
}

/// `count` digits from `start`, or -1 if any of them is not a digit.
int Digits(String text, nuint start, nuint count) {
    int value = 0;
    for (nuint i = 0u; i < count; i += 1u) {
        byte digit = text.ByteAt(start + i);
        if (digit < 48 || digit > 57) { return -1; }
        value = value * 10 + (int)(digit - 48);
    }
    return value;
}

// ------------------------------------------------------------------- clock

/// A stopwatch over the monotonic counter.
///
/// This is the only correct way to measure a duration: the wall clock can jump
/// while you are timing, and a measurement that came out negative because NTP
/// stepped the clock is a bug nobody finds.
///
///     var clock = new Clock();
///     DoTheWork();
///     Console.WriteLine(Time.FormatDuration(clock.Elapsed()));
public class Clock {
    long started;

    public Clock() { started = sl_time_monotonic(); }

    /// How long since it was made, or since `Restart`.
    public Duration Elapsed() { return FromNanoseconds(sl_time_monotonic() - started); }

    /// Starts again from now, returning what had passed until this moment.
    public Duration Restart() {
        long now = sl_time_monotonic();
        var span = FromNanoseconds(now - started);
        started = now;
        return span;
    }
}

/// A reading of the monotonic counter, for code that would rather keep the
/// number than an object. Meaningless on its own; subtract two of them.
public Duration Monotonic() { return FromNanoseconds(sl_time_monotonic()); }
