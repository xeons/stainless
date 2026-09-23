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

// ----------------------------------------------------------------- instant

/// A point on the wall clock, as nanoseconds since 1970-01-01 UTC.
///
///     var started = DateTimeOffset.UtcNow;
///     var waited = DateTimeOffset.UtcNow - started;
///
/// Subtracting two instants gives a `TimeSpan`, and adding a `TimeSpan` to one
/// gives another instant. Adding two instants is not defined, because the sum
/// of two dates is not a date -- which is exactly the thing a free function
/// named `Add` could not say.
public struct DateTimeOffset
{
    /// Nanoseconds since 1970-01-01 UTC, negative before it. The whole of the
    /// value, and the thing to hand a C API that wants an epoch count.
    public long Nanoseconds;

    /// What time it is now. It can go backwards between two calls; use `Stopwatch`
    /// to measure how long something took.
    ///
    /// @see Stopwatch
    public static DateTimeOffset UtcNow
    {
        get
        {
            DateTimeOffset at;
            at.Nanoseconds = sl_time_now();
            return at;
        }
    }

    /// 1970-01-01 00:00:00 UTC, which is where the count starts.
    public static DateTimeOffset UnixEpoch
    {
        get
        {
            DateTimeOffset at;
            at.Nanoseconds = 0;
            return at;
        }
    }

    /// An instant from whole seconds since the epoch -- what a `time_t`, a
    /// file timestamp and most C APIs carry.
    public static DateTimeOffset FromUnixTimeSeconds(long seconds)
    {
        DateTimeOffset at;
        at.Nanoseconds = seconds * NanosecondsPerSecond;
        return at;
    }

    /// An instant from milliseconds since the epoch, which is what JavaScript
    /// and most JSON APIs use.
    public static DateTimeOffset FromUnixTimeMilliseconds(long milliseconds)
    {
        DateTimeOffset at;
        at.Nanoseconds = milliseconds * NanosecondsPerMillisecond;
        return at;
    }

    /// A UTC date and time as an instant.
    public static DateTimeOffset FromUtc(int year, int month, int day,
                                  int hour, int minute, int second)
    {
        DateTimeOffset at;
        at.Nanoseconds = sl_time_from_parts((long)year, (long)month, (long)day,
                                            (long)hour, (long)minute, (long)second, 0, false);
        return at;
    }

    /// A local date and time as an instant. Ambiguous during the hour a clock
    /// goes back, and impossible during the hour it goes forward; the platform
    /// decides.
    ///
    /// @see DateTimeOffset.FromUtc
    public static DateTimeOffset FromLocal(int year, int month, int day,
                                    int hour, int minute, int second)
    {
        DateTimeOffset at;
        at.Nanoseconds = sl_time_from_parts((long)year, (long)month, (long)day,
                                            (long)hour, (long)minute, (long)second, 0, true);
        return at;
    }

    /// Whole seconds since the epoch, rounded toward the epoch. This is what a
    /// file's modification time is, and what most C APIs speak.
    public long ToUnixTimeSeconds() => Nanoseconds / NanosecondsPerSecond;

    /// Whole milliseconds since the epoch, rounded toward the epoch.
    public long ToUnixTimeMilliseconds() => Nanoseconds / NanosecondsPerMillisecond;

    /// This instant as a date and time in UTC.
    public DateTime UtcDateTime => ToDateTime(this, false);

    /// The same in the machine's local zone, with whatever the platform
    /// believes about daylight saving.
    ///
    /// @see DateTimeOffset.UtcDateTime
    public DateTime LocalDateTime => ToDateTime(this, true);

    /// ISO 8601, to the second: `2026-09-05T14:30:00Z`.
    ///
    /// @see DateTimeOffset.ParseIso
    public String FormatIso() => FormatIso8601(this);

    /// `2026-09-05T14:30:00Z` back to an instant.
    ///
    /// A `Result` rather than a nullable, because a `DateTimeOffset` is a
    /// struct and a struct is never null (SL0271) -- and because "that is not
    /// a date" and "that is not a real date" are worth telling apart.
    ///
    /// Deliberately strict: exactly the shape `FormatIso` writes, so a round
    /// trip is exact and anything else is refused rather than half-read.
    ///
    /// @failure TimeError.Malformed   not that shape: the wrong length, a
    ///                                separator out of place, or something
    ///                                that is not a digit where one belongs
    /// @failure TimeError.OutOfRange  that shape, and no real moment -- the
    ///                                31st of February, a month of 13, an hour
    ///                                of 24
    /// @see DateTimeOffset.FormatIso
    public static Result<DateTimeOffset, TimeError> ParseIso(String text)
    {
        return ParseIso8601(text);
    }

    /// How far ahead of UTC the local zone was at this instant. Negative west
    /// of Greenwich.
    public TimeSpan Offset =>
        TimeSpan.FromSeconds(sl_time_zone_offset(Nanoseconds));

    /// How long apart two instants are. Negative if the right one is later.
    public static TimeSpan operator -(DateTimeOffset later, DateTimeOffset earlier)
    {
        return TimeSpan.FromNanoseconds(later.Nanoseconds - earlier.Nanoseconds);
    }

    /// An instant moved forward by a length of time. Exact nanoseconds, so a
    /// day added is 24 hours and not a calendar day.
    public static DateTimeOffset operator +(DateTimeOffset at, TimeSpan span)
    {
        DateTimeOffset moved;
        moved.Nanoseconds = at.Nanoseconds + span.Nanoseconds;
        return moved;
    }

    /// An instant moved back by a length of time.
    public static DateTimeOffset operator -(DateTimeOffset at, TimeSpan span)
    {
        DateTimeOffset moved;
        moved.Nanoseconds = at.Nanoseconds - span.Nanoseconds;
        return moved;
    }

    /// Whether the two name the same nanosecond.
    public static bool operator ==(DateTimeOffset left, DateTimeOffset right)
    {
        return left.Nanoseconds == right.Nanoseconds;
    }

    /// Whether they name different nanoseconds.
    public static bool operator !=(DateTimeOffset left, DateTimeOffset right)
    {
        return left.Nanoseconds != right.Nanoseconds;
    }

    /// Whether `left` is the earlier.
    public static bool operator <(DateTimeOffset left, DateTimeOffset right)
    {
        return left.Nanoseconds < right.Nanoseconds;
    }

    /// Whether `left` is the later.
    public static bool operator >(DateTimeOffset left, DateTimeOffset right)
    {
        return left.Nanoseconds > right.Nanoseconds;
    }

    /// Whether `left` is no later than `right`.
    public static bool operator <=(DateTimeOffset left, DateTimeOffset right)
    {
        return left.Nanoseconds <= right.Nanoseconds;
    }

    /// Whether `left` is no earlier than `right`.
    public static bool operator >=(DateTimeOffset left, DateTimeOffset right)
    {
        return left.Nanoseconds >= right.Nanoseconds;
    }

    /// -1, 0 or 1, for sorting. The operators answer the question a program
    /// usually has; this answers the one a sort has.
    public static int Compare(DateTimeOffset left, DateTimeOffset right)
    {
        if (left.Nanoseconds < right.Nanoseconds)
            return -1;
        if (left.Nanoseconds > right.Nanoseconds)
            return 1;
        return 0;
    }
}
