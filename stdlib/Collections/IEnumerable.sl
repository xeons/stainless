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

/// Something that can be walked from the start, once per enumerator.
///
/// `foreach` does not need this interface -- it finds `GetEnumerator` by name
/// -- so implementing it is about being passable as a sequence, not about
/// being iterable.
///
/// @typeparam T  what the sequence yields; nothing is asked of it
public interface IEnumerable<T>
{
    /// A fresh cursor positioned before the first item. Each call gives an
    /// independent one, so a sequence can be walked twice; what is not
    /// promised is that the two walks see the same items, since a collection
    /// changed in between will say something different.
    IEnumerator<T> GetEnumerator();
}
