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

/// Why a moment could not be read.
public enum TimeError
{
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
