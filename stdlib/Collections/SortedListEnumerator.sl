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

/// Walks a sorted list in key order.
///
/// One `KeyValuePair` is built per step, as the materialising version built one per
/// entry before the walk began -- the difference is that a loop that stops
/// early now stops allocating too.
///
/// @typeparam TKey    the key type of the map being walked, comparable as that
///                    map requires
/// @typeparam TValue  its value type
/// @see SortedList.GetEnumerator
public class SortedListEnumerator<TKey, TValue>
    : IEnumerator<KeyValuePair<TKey, TValue>> where TKey : IComparable<TKey>
{
    SortedList<TKey, TValue> _source;
    nuint _next;

    /// A cursor over `list`, positioned before the smallest key.
    public SortedListEnumerator(SortedList<TKey, TValue> list)
    {
        _source = list;
        _next = 0;
    }

    /// Advances to the next key in order, answering false at the end.
    public bool MoveNext()
    {
        if (_next >= _source.Count)
            return false;
        _next++;
        return true;
    }

    /// The entry the last `MoveNext` landed on, as a freshly built `KeyValuePair`.
    public KeyValuePair<TKey, TValue> Current => _source.GetPairAt(_next - 1);
}
