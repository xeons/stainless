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

/// A day on which a zone's clocks change, as a yearly rule states it.
struct RulePoint
{
    /// 0: `Week` `Weekday` of `Month`, the fifth being the last. 1: day `Day`
    /// of 1 to 365, never counting 29 February. 2: day `Day` of 0 to 365,
    /// counting it. 3: `Day` of `Month`.
    public int Kind;
    public int Month;
    public int Week;
    public int Weekday;
    public int Day;

    /// The time of day, in the local time in force before the change.
    public long Seconds;
}
