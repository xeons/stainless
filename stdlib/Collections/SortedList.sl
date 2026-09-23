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

// ------------------------------------------------------------- sorted list

/// A map kept in key order, over two parallel arrays.
///
/// Lookup is a binary search and iteration is in order, which is what a
/// `Dictionary` cannot do. Insertion moves the tail of the arrays, so this is
/// for maps that are read far more than they are written -- a lookup table
/// built once, rather than a counter updated in a loop.
///
/// @typeparam TKey    what an entry is found by, and what the order is over:
///                    comparable, since a lookup is a binary search
/// @typeparam TValue  what an entry holds; nothing is asked of it
/// @see Dictionary
public class SortedList<TKey, TValue> : IEnumerable<KeyValuePair<TKey, TValue>>
    where TKey : IComparable<TKey>
{
    TKey[] _keys;
    TValue[] _values;
    nuint _count;

    /// An empty map with room for a few entries before it first grows.
    public SortedList()
    {
        _keys = new TKey[8];
        _values = new TValue[8];
        _count = 0;
    }

    /// How many entries there are. O(1).
    public nuint Count => _count;

    /// True when there are no entries.
    public bool IsEmpty => _count == 0;

    /// The index `key` is at, or the index it would be inserted at, negated and
    /// offset by one so the two cases stay apart: a result below zero means
    /// "not found, and `-result - 1` is where it goes".
    ///
    /// @see SortedList.TryGetValue
    public nint IndexOfKey(TKey key)
    {
        nuint low = 0;
        nuint high = _count;

        while (low < high)
        {
            nuint middle = low + (high - low) / 2;
            int order = _keys[middle].CompareTo(key);

            if (order == 0)
                return (nint)middle;
            if (order < 0)
            {
                low = middle + 1;
            }
            else
            {
                high = middle;
            }
        }

        return -((nint)low) - 1;
    }

    /// Whether `key` is there. A binary search, O(log n). Reach for `TryGetValue`
    /// when the value is what is wanted, rather than searching twice.
    ///
    /// @see SortedList.TryGetValue
    public bool ContainsKey(TKey key) => IndexOfKey(key) >= 0;

    /// The key at a position in the ordering, counting from the smallest.
    ///
    /// @see SortedList.GetValueAt
    public TKey GetKeyAt(nuint index)
    {
        if (index >= _count)
            sl_array_bounds_fail(index, _count);
        return _keys[index];
    }

    /// The value at a position in the ordering, paired with `GetKeyAt` at the
    /// same index. Aborts past the end.
    ///
    /// @see SortedList.GetKeyAt
    public TValue GetValueAt(nuint index)
    {
        if (index >= _count)
            sl_array_bounds_fail(index, _count);
        return _values[index];
    }

    /// The value for `key`, or `None` when there is none. The one to reach
    /// for, for the reason `Dictionary.TryGetValue` gives: a key is data, so a key
    /// that is not there is an outcome rather than a mistake.
    ///
    /// @see SortedList.GetValue
    /// @seealso SortedList.GetValueOrDefault
    public Optional<TValue> TryGetValue(TKey key)
    {
        nint at = IndexOfKey(key);
        if (at < 0)
            return None;
        return Some(_values[(nuint)at]);
    }

    /// The value for `key`, aborting when there is none.
    ///
    /// The asserting form, for a key that is there by construction. `TryGetValue` is
    /// the question where it might not be, and `GetValueOrDefault` where a default will do.
    ///
    /// @see SortedList.TryGetValue
    /// @seealso SortedList.GetValueOrDefault
    public TValue GetValue(TKey key)
    {
        nint at = IndexOfKey(key);
        if (at < 0)
            sl_fail("SortedList.GetValue: no such key");
        return _values[(nuint)at];
    }

    /// The value for `key`, or `fallback` when there is none.
    ///
    /// Allocates nothing, at the cost of not distinguishing an absent key from
    /// one whose stored value equals the fallback. `TryGetValue` is the one that
    /// tells them apart.
    ///
    /// @see SortedList.TryGetValue
    public TValue GetValueOrDefault(TKey key, TValue fallback)
    {
        nint at = IndexOfKey(key);
        if (at < 0)
            return fallback;
        return _values[(nuint)at];
    }

    /// Sets the value of a key, adding it in order if it is new.
    ///
    /// An existing key costs a search. A new one costs the search plus a shift
    /// of everything after it -- O(n) -- which is what makes this collection a
    /// poor choice for a map that is written in a loop.
    ///
    /// @see SortedList.Remove
    public void SetValue(TKey key, TValue value)
    {
        nint at = IndexOfKey(key);
        if (at >= 0)
        {
            _values[(nuint)at] = value;
            return;
        }

        nuint slot = (nuint)(-at - 1);
        if (_count == _keys.Length)
            GrowStorage();

        // Shift the tail up by one. Counted down from the end so that no slot
        // is written before it has been copied.
        for (nuint i = _count; i > slot; i--)
        {
            _keys[i] = _keys[i - 1];
            _values[i] = _values[i - 1];
        }

        _keys[slot] = key;
        _values[slot] = value;
        _count++;
    }

    /// Removes a key, answering whether it was there. Closes the gap, so it
    /// is O(n) like `SetValue` on a new key.
    ///
    /// @see SortedList.SetValue
    public bool Remove(TKey key)
    {
        nint at = IndexOfKey(key);
        if (at < 0)
            return false;

        for (nuint i = (nuint)at; i + 1 < _count; i++)
        {
            _keys[i] = _keys[i + 1];
            _values[i] = _values[i + 1];
        }

        _count--;

        // The vacated slot still refers to the last entry; blanking it releases
        // that reference now rather than at the next insertion.
        var noKeys = new TKey[1];
        var noValues = new TValue[1];
        _keys[_count] = noKeys[0];
        _values[_count] = noValues[0];
        return true;
    }

    /// Drops every entry. The arrays are replaced rather than blanked, so
    /// anything they held is released now.
    public void Clear()
    {
        _keys = new TKey[8];
        _values = new TValue[8];
        _count = 0;
    }

    /// Every key, smallest first, as a fresh list.
    ///
    /// @see SortedList.GetValues
    public List<TKey> GetKeys()
    {
        var result = new List<TKey>();
        for (nuint i = 0; i < _count; i++)
            result.Add(_keys[i]);
        return result;
    }

    /// Every value, in key order, pairing with `GetKeys` position for position.
    ///
    /// @see SortedList.GetKeys
    public List<TValue> GetValues()
    {
        var result = new List<TValue>();
        for (nuint i = 0; i < _count; i++)
            result.Add(_values[i]);
        return result;
    }

    /// The entry at a position, in key order. What the cursor walks.
    KeyValuePair<TKey, TValue> GetPairAt(nuint index) =>
        new KeyValuePair<TKey, TValue>(_keys[index], _values[index]);

    /// A cursor over the entries in key order, for `foreach` -- the ordering
    /// a `Dictionary` cannot give. One `KeyValuePair` is built per step. Writing to
    /// the map during a walk invalidates it.
    ///
    /// @see SortedListEnumerator
    public IEnumerator<KeyValuePair<TKey, TValue>> GetEnumerator()
    {
        return new SortedListEnumerator<TKey, TValue>(this);
    }

    void GrowStorage()
    {
        var biggerKeys = new TKey[_keys.Length * 2];
        var biggerValues = new TValue[_values.Length * 2];

        for (nuint i = 0; i < _count; i++)
        {
            biggerKeys[i] = _keys[i];
            biggerValues[i] = _values[i];
        }

        _keys = biggerKeys;
        _values = biggerValues;
    }
}
