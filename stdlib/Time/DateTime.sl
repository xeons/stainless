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

// ---------------------------------------------------------------- calendar

/// An instant broken into the parts a person reads.
///
/// Made by `UtcDateTime` or `LocalDateTime`, which is what says which zone the numbers are
/// in -- the struct itself does not carry that, because a date with no zone is
/// exactly as ambiguous as it sounds.
public struct DateTime
{
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
    public String FormatDate()
    {
        var text = new StringBuilder();
        text.Append(PadNumber((long)Year, 4u));
        text.Append("-");
        text.Append(PadNumber((long)Month, 2u));
        text.Append("-");
        text.Append(PadNumber((long)Day, 2u));
        return text.ToText();
    }

    /// The time of day alone: `14:30:00`.
    public String FormatTime()
    {
        var text = new StringBuilder();
        text.Append(PadNumber((long)Hour, 2u));
        text.Append(":");
        text.Append(PadNumber((long)Minute, 2u));
        text.Append(":");
        text.Append(PadNumber((long)Second, 2u));
        return text.ToText();
    }
}
