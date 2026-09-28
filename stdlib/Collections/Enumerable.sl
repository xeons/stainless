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

/// Sequences made from nothing: C#'s `Enumerable.Range`, `Repeat` and `Empty`.
///
///     foreach (int i in Enumerable.Range(1, 10)) { ... }
///
/// Each answers with a list, as everything here does.
public static class Enumerable
{
    /// `count` integers counting up from `start`. Aborts when the last would
    /// not fit in an `int`.
    ///
    /// @param start  the first integer
    /// @param count  how many there are
    public static List<int> Range(int start, int count)
    {
        var made = new List<int>((nuint)count);
        for (int i = 0; i < count; i++)
            made.Add(checked(start + i));
        return made;
    }

    /// `element`, `count` times over.
    ///
    /// @param element  what is repeated
    /// @param count    how many times
    /// @typeparam T    the element type; nothing is asked of it
    public static List<T> Repeat<T>(T element, nuint count)
    {
        var made = new List<T>(count);
        for (nuint i = 0u; i < count; i++)
            made.Add(element);
        return made;
    }

    /// A list of nothing.
    ///
    /// @typeparam T  the element type; nothing is asked of it
    public static List<T> Empty<T>() => new List<T>();
}
