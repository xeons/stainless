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

// The conversion factors, public because a program that has to hand a count of
// nanoseconds to a C API should multiply by a name rather than by a literal
// with the wrong number of zeroes in it.

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
/// add a day to an `Instant` and you have added 24 hours.
public const long NanosecondsPerDay = 86400000000000;

// ---------------------------------------------------------------- duration

/// A length of time, positive or negative.
///
/// Made by naming the unit -- `Duration.FromSeconds(30)` -- because a bare
/// number of nanoseconds at a call site says nothing about which unit was
/// meant, and this is the mistake that is silent when it happens.
///
///     var timeout = Duration.FromSeconds(30);
///     if (waited > timeout) { ... }
public struct Duration {
    /// The length in nanoseconds, which is the whole of the value. Readable
    /// and writable because a struct's fields are, but a `From` method is what
    /// says which unit was meant.
    public long Nanoseconds;

    /// A length in nanoseconds. The others are this times a factor, so this is
    /// the one that cannot overflow on the way in.
    public static Duration FromNanoseconds(long value) {
        Duration span;
        span.Nanoseconds = value;
        return span;
    }

    /// A length in whole microseconds.
    public static Duration FromMicroseconds(long value) {
        return FromNanoseconds(value * NanosecondsPerMicrosecond);
    }

    /// A length in whole milliseconds.
    public static Duration FromMilliseconds(long value) {
        return FromNanoseconds(value * NanosecondsPerMillisecond);
    }

    /// A length in whole seconds.
    public static Duration FromSeconds(long value) {
        return FromNanoseconds(value * NanosecondsPerSecond);
    }

    /// A length in whole minutes.
    public static Duration FromMinutes(long value) {
        return FromNanoseconds(value * NanosecondsPerMinute);
    }

    /// A length in whole hours.
    public static Duration FromHours(long value) {
        return FromNanoseconds(value * NanosecondsPerHour);
    }

    /// A length in whole days of 24 hours each. Past about 106,751 days the
    /// multiplication overflows a `long` of nanoseconds, silently.
    public static Duration FromDays(long value) {
        return FromNanoseconds(value * NanosecondsPerDay);
    }

    /// Whole units, truncated toward zero. 1,500,000ns is 1 millisecond.
    public long TotalMilliseconds() { return Nanoseconds / NanosecondsPerMillisecond; }

    /// Whole seconds, truncated toward zero.
    public long TotalSeconds() { return Nanoseconds / NanosecondsPerSecond; }

    /// Whole minutes, truncated toward zero.
    public long TotalMinutes() { return Nanoseconds / NanosecondsPerMinute; }

    /// Whole hours, truncated toward zero.
    public long TotalHours() { return Nanoseconds / NanosecondsPerHour; }

    /// Whole 24-hour days, truncated toward zero.
    public long TotalDays() { return Nanoseconds / NanosecondsPerDay; }

    /// The same length with fractions kept, for a measurement being reported
    /// rather than counted.
    public double AsSeconds() { return (double)Nanoseconds / 1000000000.0; }

    /// The same length in milliseconds, fractions kept.
    public double AsMilliseconds() { return (double)Nanoseconds / 1000000.0; }

    /// True when the length is below zero, which is what subtracting a later
    /// instant from an earlier one gives.
    public bool IsNegative() { return Nanoseconds < 0; }

    /// Arithmetic, as arithmetic. Adding two lengths of time is what `+` means
    /// everywhere else, and spelling it `Time.Add(a, b)` only hid that.
    public static Duration operator +(Duration left, Duration right) {
        return FromNanoseconds(left.Nanoseconds + right.Nanoseconds);
    }

    /// One length less another. The result may be negative.
    public static Duration operator -(Duration left, Duration right) {
        return FromNanoseconds(left.Nanoseconds - right.Nanoseconds);
    }

    /// The same length the other way round.
    public static Duration operator -(Duration span) {
        return FromNanoseconds(0 - span.Nanoseconds);
    }

    /// Scaling by a count: half a timeout, or three retries' worth of one.
    public static Duration operator *(Duration span, long times) {
        return FromNanoseconds(span.Nanoseconds * times);
    }

    /// The same scaling with the operands the other way round.
    public static Duration operator *(long times, Duration span) {
        return FromNanoseconds(span.Nanoseconds * times);
    }

    /// A length split into `parts`, truncated toward zero. Dividing by zero
    /// ends the program, as integer division does.
    public static Duration operator /(Duration span, long parts) {
        return FromNanoseconds(span.Nanoseconds / parts);
    }

    /// Whether the two lengths are equal, to the nanosecond.
    public static bool operator ==(Duration left, Duration right) {
        return left.Nanoseconds == right.Nanoseconds;
    }

    /// Whether the two lengths differ.
    public static bool operator !=(Duration left, Duration right) {
        return left.Nanoseconds != right.Nanoseconds;
    }

    /// Whether `left` is the shorter. Signed, so a negative length is below a positive one.
    public static bool operator <(Duration left, Duration right) {
        return left.Nanoseconds < right.Nanoseconds;
    }

    /// Whether `left` is the longer.
    public static bool operator >(Duration left, Duration right) {
        return left.Nanoseconds > right.Nanoseconds;
    }

    /// Whether `left` is no longer than `right`.
    public static bool operator <=(Duration left, Duration right) {
        return left.Nanoseconds <= right.Nanoseconds;
    }

    /// Whether `left` is at least as long as `right`.
    public static bool operator >=(Duration left, Duration right) {
        return left.Nanoseconds >= right.Nanoseconds;
    }

    /// -1, 0 or 1, for sorting. The operators answer the question a program
    /// usually has; this answers the one a sort has.
    public static int Compare(Duration left, Duration right) {
        if (left.Nanoseconds < right.Nanoseconds) { return -1; }
        if (left.Nanoseconds > right.Nanoseconds) { return 1; }
        return 0;
    }

    /// `1h02m03.004s`, with the leading units dropped when they are zero --
    /// the way a log line wants it.
    public String Format() { return FormatDuration(this); }
}

/// A duration written the way a log line wants it: `1h02m03.004s`, with the
/// leading units dropped when they are zero.
String FormatDuration(Duration span) {
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
///
///     var started = Instant.Now();
///     var waited = Instant.Now() - started;
///
/// Subtracting two instants gives a `Duration`, and adding a `Duration` to one
/// gives another instant. Adding two instants is not defined, because the sum
/// of two dates is not a date -- which is exactly the thing a free function
/// named `Add` could not say.
public struct Instant {
    /// Nanoseconds since 1970-01-01 UTC, negative before it. The whole of the
    /// value, and the thing to hand a C API that wants an epoch count.
    public long Nanoseconds;

    /// What time it is now. It can go backwards between two calls; use `Clock`
    /// to measure how long something took.
    public static Instant Now() {
        Instant at;
        at.Nanoseconds = sl_time_now();
        return at;
    }

    /// 1970-01-01 00:00:00 UTC, which is where the count starts.
    public static Instant Epoch() {
        Instant at;
        at.Nanoseconds = 0;
        return at;
    }

    /// An instant from whole seconds since the epoch -- what a `time_t`, a
    /// file timestamp and most C APIs carry.
    public static Instant FromUnixSeconds(long seconds) {
        Instant at;
        at.Nanoseconds = seconds * NanosecondsPerSecond;
        return at;
    }

    /// An instant from milliseconds since the epoch, which is what JavaScript
    /// and most JSON APIs use.
    public static Instant FromUnixMilliseconds(long milliseconds) {
        Instant at;
        at.Nanoseconds = milliseconds * NanosecondsPerMillisecond;
        return at;
    }

    /// A UTC date and time as an instant.
    public static Instant FromUtc(int year, int month, int day,
                                  int hour, int minute, int second) {
        Instant at;
        at.Nanoseconds = sl_time_from_parts((long)year, (long)month, (long)day,
                                            (long)hour, (long)minute, (long)second, 0, false);
        return at;
    }

    /// A local date and time as an instant. Ambiguous during the hour a clock
    /// goes back, and impossible during the hour it goes forward; the platform
    /// decides.
    public static Instant FromLocal(int year, int month, int day,
                                    int hour, int minute, int second) {
        Instant at;
        at.Nanoseconds = sl_time_from_parts((long)year, (long)month, (long)day,
                                            (long)hour, (long)minute, (long)second, 0, true);
        return at;
    }

    /// Whole seconds since the epoch, rounded toward the epoch. This is what a
    /// file's modification time is, and what most C APIs speak.
    public long ToUnixSeconds() { return Nanoseconds / NanosecondsPerSecond; }

    /// Whole milliseconds since the epoch, rounded toward the epoch.
    public long ToUnixMilliseconds() { return Nanoseconds / NanosecondsPerMillisecond; }

    /// This instant as a date and time in UTC.
    public DateTime ToUtc() { return Broken(this, false); }

    /// The same in the machine's local zone, with whatever the platform
    /// believes about daylight saving.
    public DateTime ToLocal() { return Broken(this, true); }

    /// ISO 8601, to the second: `2026-09-05T14:30:00Z`.
    public String FormatIso() { return FormatInstantIso(this); }

    /// `2026-09-05T14:30:00Z` back to an instant.
    ///
    /// A `Result` rather than a nullable, because an `Instant` is a struct and
    /// a struct is never null (SL0271) -- and because "that is not a date" and
    /// "that is not a real date" are worth telling apart.
    ///
    /// Deliberately strict: exactly the shape `FormatIso` writes, so a round
    /// trip is exact and anything else is refused rather than half-read.
    public static Result<Instant, TimeError> ParseIso(String text) {
        return ParseInstantIso(text);
    }

    /// How far ahead of UTC the local zone was at this instant, in seconds.
    /// Negative west of Greenwich.
    public long ZoneOffsetSeconds() { return sl_time_zone_offset(Nanoseconds); }

    /// How long apart two instants are. Negative if the right one is later.
    public static Duration operator -(Instant later, Instant earlier) {
        return Duration.FromNanoseconds(later.Nanoseconds - earlier.Nanoseconds);
    }

    /// An instant moved forward by a length of time. Exact nanoseconds, so a
    /// day added is 24 hours and not a calendar day.
    public static Instant operator +(Instant at, Duration span) {
        Instant moved;
        moved.Nanoseconds = at.Nanoseconds + span.Nanoseconds;
        return moved;
    }

    /// An instant moved back by a length of time.
    public static Instant operator -(Instant at, Duration span) {
        Instant moved;
        moved.Nanoseconds = at.Nanoseconds - span.Nanoseconds;
        return moved;
    }

    /// Whether the two name the same nanosecond.
    public static bool operator ==(Instant left, Instant right) {
        return left.Nanoseconds == right.Nanoseconds;
    }

    /// Whether they name different nanoseconds.
    public static bool operator !=(Instant left, Instant right) {
        return left.Nanoseconds != right.Nanoseconds;
    }

    /// Whether `left` is the earlier.
    public static bool operator <(Instant left, Instant right) {
        return left.Nanoseconds < right.Nanoseconds;
    }

    /// Whether `left` is the later.
    public static bool operator >(Instant left, Instant right) {
        return left.Nanoseconds > right.Nanoseconds;
    }

    /// Whether `left` is no later than `right`.
    public static bool operator <=(Instant left, Instant right) {
        return left.Nanoseconds <= right.Nanoseconds;
    }

    /// Whether `left` is no earlier than `right`.
    public static bool operator >=(Instant left, Instant right) {
        return left.Nanoseconds >= right.Nanoseconds;
    }

    /// -1, 0 or 1, for sorting. The operators answer the question a program
    /// usually has; this answers the one a sort has.
    public static int Compare(Instant left, Instant right) {
        if (left.Nanoseconds < right.Nanoseconds) { return -1; }
        if (left.Nanoseconds > right.Nanoseconds) { return 1; }
        return 0;
    }
}

// ---------------------------------------------------------------- calendar

/// An instant broken into the parts a person reads.
///
/// Made by `ToUtc` or `ToLocal`, which is what says which zone the numbers are
/// in -- the struct itself does not carry that, because a date with no zone is
/// exactly as ambiguous as it sounds.
public struct DateTime {
    /// The year, in full. Zero means the instant was outside what the platform
    /// can name, and every other field is zero with it -- that is how this
    /// struct reports a failure, since it has no other way to.
    public int Year;

    /// The month, 1 to 12.
    public int Month;

    /// The day of the month, 1 to 31.
    public int Day;

    /// The hour, 0 to 23.
    public int Hour;

    /// The minute, 0 to 59.
    public int Minute;

    /// The second, 0 to 60 -- 60 because a leap second is a real reading of a
    /// real clock.
    public int Second;

    /// Nanoseconds within the second, 0 to 999,999,999.
    public int Nanosecond;

    /// The day of the week, 0 for Sunday through 6 for Saturday.
    public int DayOfWeek;

    /// The day of the year, 1 to 366.
    public int DayOfYear;

    /// The date alone: `2026-09-05`.
    public String FormatDate() {
        var text = new StringBuilder();
        text.Append(Pad((long)Year, 4u));
        text.Append("-");
        text.Append(Pad((long)Month, 2u));
        text.Append("-");
        text.Append(Pad((long)Day, 2u));
        return text.ToText();
    }

    /// The time of day alone: `14:30:00`.
    public String FormatTime() {
        var text = new StringBuilder();
        text.Append(Pad((long)Hour, 2u));
        text.Append(":");
        text.Append(Pad((long)Minute, 2u));
        text.Append(":");
        text.Append(Pad((long)Second, 2u));
        return text.ToText();
    }
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
String FormatInstantIso(Instant at) {
    var when = at.ToUtc();
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

/// Why a moment could not be read.
public enum TimeError {
    /// Nothing went wrong. Present so the enum has a zero value; a `Result`
    /// says success by being `Ok`, so this is not what a failure carries.
    None,

    /// Not the shape `FormatIso` writes -- the wrong length, or a separator
    /// in the wrong place, or something that is not a digit where one belongs.
    Malformed,

    /// The right shape and not a real moment: the 31st of February, a month of
    /// 13, an hour of 24.
    OutOfRange,
}

Result<Instant, TimeError> ParseInstantIso(String text) {
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

    return Ok(Instant.FromUtc(year, month, day, hour, minute, second));
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
///     Console.WriteLine(clock.Elapsed().Format());
public class Clock {
    long started;

    /// A clock that starts now. There is no separate `Start`: making one is
    /// what starts it.
    public Clock() { started = sl_time_monotonic(); }

    /// How long since it was made, or since `Restart`.
    public Duration Elapsed() {
        return Duration.FromNanoseconds(sl_time_monotonic() - started);
    }

    /// Starts again from now, returning what had passed until this moment.
    public Duration Restart() {
        long now = sl_time_monotonic();
        var span = Duration.FromNanoseconds(now - started);
        started = now;
        return span;
    }

    /// A reading of the monotonic counter, for code that would rather keep
    /// the number than an object. Meaningless on its own; subtract two.
    public static Duration Monotonic() {
        return Duration.FromNanoseconds(sl_time_monotonic());
    }
}
