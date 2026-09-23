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

// ------------------------------------------------------------------- lists

/// A sequence that knows its length and can be indexed, and cannot be changed
/// through this reference.
///
/// Read-only is about what this interface offers, not about the object: the
/// list behind it may well be a `List<T>` that someone else is still adding
/// to. Take this as a parameter type where a function reads and does not
/// write, which says so in the signature.
///
/// @typeparam T  the element type; nothing is asked of it
/// @see IList
public interface IReadOnlyList<T>
{
    /// How many items there are.
    nuint Count { get; }

    /// Whether there are none.
    bool IsEmpty { get; }

    /// The item at `index`, counting from zero. An index at or past `Count`
    /// aborts with the same message an array overrun gives.
    T this[nuint index] { get; }
}
