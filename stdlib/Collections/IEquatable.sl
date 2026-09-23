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

// ---------------------------------------------------------------- comparison

/// A value that can be asked whether it equals another of its type.
///
/// `Equals` has to be an equivalence -- a value equals itself, equality runs
/// both ways, and two things equal to a third are equal to each other --
/// because the containers assume all three and none of them checks. A type
/// used as a dictionary key implements `IHashable` alongside this, and the two
/// must agree: equal values must hash alike.
///
/// @typeparam T  what a value is compared against, which is normally the type
///               implementing this
public interface IEquatable<T>
{
    /// True when this value and `other` are the same value. Implementations
    /// should answer without allocating; this runs once per probe.
    bool Equals(T other);
}
