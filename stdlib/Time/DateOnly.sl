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

/// Days since 1970-01-01 of a date in the proleptic Gregorian calendar.
long DaysFromCivil(long year, long month, long day)
{
    // Howard Hinnant's algorithm: the year counted from March, so the leap
    // day is last.
    long y = month <= 2 ? year - 1 : year;
    long era = (y >= 0 ? y : y - 399) / 400;
    long yearOfEra = y - era * 400;
    long dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1;
    long dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear;
    return era * 146097 + dayOfEra - 719468;
}

/// The date that is `days` after 1970-01-01.
(long, long, long) CivilFromDays(long days)
{
    long z = days + 719468;
    long era = (z >= 0 ? z : z - 146096) / 146097;
    long dayOfEra = z - era * 146097;
    long yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146096) / 365;
    long dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100);
    long shifted = (5 * dayOfYear + 2) / 153;
    long day = dayOfYear - (153 * shifted + 2) / 5 + 1;
    long month = shifted < 10 ? shifted + 3 : shifted - 9;
    long year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0);
    return (year, month, day);
}

/// Days since 1970-01-01 of 0001-01-01, which is day number zero.
const long DayNumberEpoch = -719162;

/// A date and no time: C#'s `System.DateOnly`.
///
///     var due = new DateOnly(2026, 9, 30).AddMonths(1);  // 2026-10-30
///
/// From 0001-01-01 to 9999-12-31 in the Gregorian calendar, as C#'s. A date
/// outside that, or a day its month does not have, aborts where C# throws.
/// Written and read as ISO 8601, `2026-09-30`, rather than in a culture's form.
public struct DateOnly : IEquatable<DateOnly>, IComparable<DateOnly>, IHashable
{
    private int _dayNumber;

    /// `day` of `month` of `year`.
    public DateOnly(int year, int month, int day)
    {
        if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1 || day > DaysInMonth(year, month))
            sl_fail("DateOnly: no such date");
        _dayNumber = (int)(DaysFromCivil((long)year, (long)month, (long)day) - DayNumberEpoch);
    }

    /// 0001-01-01.
    public static DateOnly MinValue => default(DateOnly);

    /// 9999-12-31.
    public static DateOnly MaxValue => new DateOnly(9999, 12, 31);

    /// The date `dayNumber` days after 0001-01-01. Aborts outside the range.
    public static DateOnly FromDayNumber(int dayNumber)
    {
        if (dayNumber < 0 || dayNumber > MaxValue._dayNumber)
            sl_fail("DateOnly.FromDayNumber: out of range");
        DateOnly made;
        made._dayNumber = dayNumber;
        return made;
    }

    /// The date part of `when`.
    public static DateOnly FromDateTime(DateTime when) => new DateOnly(when.Year, when.Month, when.Day);

    /// Days since 0001-01-01.
    public int DayNumber => _dayNumber;

    (long, long, long) Parts => CivilFromDays((long)_dayNumber + DayNumberEpoch);

    /// The year, 1 to 9999.
    public int Year => (int)Parts.Item1;

    /// The month, 1 to 12.
    public int Month => (int)Parts.Item2;

    /// The day of the month, 1 to 31.
    public int Day => (int)Parts.Item3;

    /// The day of the week, 0 for Sunday through 6 for Saturday, as
    /// `DateTime.DayOfWeek` counts. 0001-01-01 was a Monday.
    public int DayOfWeek => (_dayNumber + 1) % 7;

    /// The day of the year, 1 to 366.
    public int DayOfYear =>
        _dayNumber - (int)(DaysFromCivil((long)Year, 1, 1) - DayNumberEpoch) + 1;

    /// `days` later, or earlier when negative. Aborts outside the range.
    public DateOnly AddDays(int days) => FromDayNumber(_dayNumber + days);

    /// `months` later, the day kept or, where the month is shorter, its last.
    public DateOnly AddMonths(int months)
    {
        int index = Year * 12 + (Month - 1) + months;
        int year = index / 12;
        int month = index % 12 + 1;
        int last = DaysInMonth(year, month);
        return new DateOnly(year, month, Day < last ? Day : last);
    }

    /// `years` later, 29 February becoming the 28th in a year without one.
    public DateOnly AddYears(int years) => AddMonths(years * 12);

    /// The date and `time` together.
    public DateTime ToDateTime(TimeOnly time)
    {
        DateTime when;
        when.Year = Year;
        when.Month = Month;
        when.Day = Day;
        when.Hour = time.Hour;
        when.Minute = time.Minute;
        when.Second = time.Second;
        when.Nanosecond = (int)(time.ToTimeSpan().Nanoseconds % NanosecondsPerSecond);
        when.DayOfWeek = DayOfWeek;
        when.DayOfYear = DayOfYear;
        return when;
    }

    /// The year, month and day.
    public void Deconstruct(out int year, out int month, out int day)
    {
        var (y, m, d) = Parts;
        year = (int)y;
        month = (int)m;
        day = (int)d;
    }

    /// `2026-09-30`.
    public String ToString() =>
        PadNumber((long)Year, 4u) + "-" + PadNumber((long)Month, 2u) + "-" + PadNumber((long)Day, 2u);

    /// Reads `yyyy-MM-dd`.
    ///
    /// @failure TimeError.Malformed   not that shape
    /// @failure TimeError.OutOfRange  that shape and no real date
    public static Result<DateOnly, TimeError> Parse(String text)
    {
        if (text.ByteLength() != 10u || text.GetByteAt(4u) != (byte)'-' || text.GetByteAt(7u) != (byte)'-')
            return Fail(TimeError.Malformed);

        int year = ParseDigits(text, 0u, 4u);
        int month = ParseDigits(text, 5u, 2u);
        int day = ParseDigits(text, 8u, 2u);
        if (year < 0 || month < 0 || day < 0)
            return Fail(TimeError.Malformed);
        if (year < 1 || month < 1 || month > 12 || day < 1 || day > DaysInMonth(year, month))
            return Fail(TimeError.OutOfRange);
        return Ok(new DateOnly(year, month, day));
    }

    public bool Equals(DateOnly other) => _dayNumber == other._dayNumber;
    public int CompareTo(DateOnly other) => _dayNumber < other._dayNumber ? -1 : _dayNumber > other._dayNumber ? 1 : 0;
    public nuint GetHashCode() => (nuint)_dayNumber;

    public static bool operator ==(DateOnly left, DateOnly right) => left._dayNumber == right._dayNumber;
    public static bool operator !=(DateOnly left, DateOnly right) => left._dayNumber != right._dayNumber;
    public static bool operator <(DateOnly left, DateOnly right) => left._dayNumber < right._dayNumber;
    public static bool operator >(DateOnly left, DateOnly right) => left._dayNumber > right._dayNumber;
    public static bool operator <=(DateOnly left, DateOnly right) => left._dayNumber <= right._dayNumber;
    public static bool operator >=(DateOnly left, DateOnly right) => left._dayNumber >= right._dayNumber;
}
