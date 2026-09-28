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

// What a collection expression lowers to when it has a `..` in it. Nothing
// here is public: the compiler calls these, and a program writes `[..a, b]`.

/// The elements of a collection expression whose length is not known until
/// its spreads have been walked. It grows by doubling and hands over its own
/// array when that is exactly full.
///
/// @typeparam T  the element type of the array being built
class ArrayBuilder<T>
{
    private T[] _items;
    private nuint _count;

    /// @param capacity  the elements already known to be coming
    public ArrayBuilder(nuint capacity)
    {
        _items = new T[capacity < 4u ? 4u : capacity];
        _count = 0u;
    }

    /// Appends one element.
    public void Add(T item)
    {
        if (_count == _items.Length)
        {
            var grown = new T[_items.Length * 2u];
            _items[:_count].CopyTo(grown);
            _items = grown;
        }

        _items[_count] = item;
        _count++;
    }

    /// The elements added, as an array of exactly that many.
    public T[] ToArray()
    {
        if (_count == _items.Length)
            return _items;

        return _items[:_count].ToArray();
    }
}

/// `..source` into anything with `Add`: each element, in order.
void AddSpreadElements<TCollection, TSource>(TCollection into, TSource source)
{
    foreach (var item in source)
        into.Add(item);
}

/// `..source` into an array whose length was worked out beforehand: each
/// element stored from `at` on. Answers where the next one goes.
nuint CopySpreadElements<T, TSource>(T[] into, nuint at, TSource source)
{
    foreach (var item in source)
    {
        into[at] = item;
        at++;
    }

    return at;
}
