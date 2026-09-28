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

module Standard;

import Standard.Unchecked;

/// Arrays made whole: every element given its value as the array is made.
///
///     String[] names = Array.Create(count, (i) => $"item {i}");
///     int[] zeros = Array.Repeat(0, 16);
///
/// `new T[n]` starts every element as the zero of `T`, and a `T` holding a
/// reference that is never null has no zero (§2.11.1). These are what such an
/// array is made with instead; an array literal, `[a, b, c]`, is the other
/// way, and a `List<T>` and its `ToArray` the way for a count not known in
/// advance.
public static class Array
{
    /// `count` elements, the element at `i` being `make(i)`, called in order
    /// from zero. No element is ever seen before it has its value.
    ///
    /// @param count  how many elements
    /// @param make   the element at an index
    /// @typeparam T  the element type; nothing is asked of it
    /// @returns the array
    public static T[] Create<T>(nuint count, Func<nuint, T> make)
    {
        T[] made = NewUninitializedArray<T>(count);
        for (nuint i = 0u; i < count; i++)
            made[i] = make(i);
        return made;
    }

    /// `count` copies of `value`.
    ///
    /// @param value  what each element is
    /// @param count  how many elements
    /// @typeparam T  the element type; nothing is asked of it
    /// @returns the array
    public static T[] Repeat<T>(T value, nuint count)
    {
        T[] made = NewUninitializedArray<T>(count);
        for (nuint i = 0u; i < count; i++)
            made[i] = value;
        return made;
    }
}
