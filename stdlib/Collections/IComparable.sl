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

module Standard.Collections;

/// Returns a negative number, zero, or a positive number when this value orders
/// before, with, or after `other`.
///
/// @typeparam T  what a value is ordered against, which is normally the type
///               implementing this
public interface IComparable<T>
{
    /// Negative when this orders before `other`, zero when they order
    /// together, positive when after. The sign is all that is read -- the
    /// magnitude means nothing, so returning a subtraction is fine as long as
    /// it cannot overflow.
    int CompareTo(T other);
}
