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

/// Everything a read-only list offers, plus mutation. A value of this type can
/// be passed anywhere an IReadOnlyList is wanted, at no cost: an interface
/// reference is a plain pointer, and the object carries a table for both.
///
/// @typeparam T  the element type; nothing is asked of it
/// @see IReadOnlyList
public interface IList<T> : IReadOnlyList<T>
{
    /// The item at `index`, readable and writable. Redeclared because an
    /// interface cannot widen an inherited member from get-only to get-set.
    T this[nuint index] { get; set; }

    /// Appends to the end.
    void Add(T item);

    /// Removes the item at `index`, closing the gap.
    void RemoveAt(nuint index);

    /// Drops every item, leaving a length of zero.
    void Clear();
}
