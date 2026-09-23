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

// ------------------------------------------------------- ordered dictionary

/// A dictionary that remembers the order its keys were added in.
///
/// `Dictionary<K, V>` finds a key by hashing and has no order to give back;
/// this keeps the order and finds a key by scanning. The trade is the whole of
/// the difference, and it is the right one wherever the order is part of the
/// data: a parsed document read back the way it was written, a configuration a
/// person edits, a header list that has to go out as it came in.
///
/// **It is a scan.** Lookup is O(n), so this is for the sizes documents
/// actually are -- a handful of members to a few hundred -- and a program
/// holding something large enough for that to hurt wants a `Dictionary` beside
/// it as an index. That is a real limit rather than a temporary one: keeping a
/// hash index in step with an order would double the storage and every write,
/// which is not what the collection is for.
///
/// @typeparam TKey    what an entry is found by, which must answer whether it
///                    equals another: the lookup is a scan of the keys
/// @typeparam TValue  what an entry holds; nothing is asked of it
/// @see Dictionary
public class OrderedDictionary<TKey, TValue> where TKey : IEquatable<TKey>
{
    List<TKey> _keys;
    List<TValue> _values;

    /// An empty ordered dictionary.
    public OrderedDictionary()
    {
        _keys = new List<TKey>();
        _values = new List<TValue>();
    }

    /// How many entries there are. Entries rather than distinct keys: `Add`
    /// keeps a repeated key, so this can exceed the number of different keys.
    public nuint Count => _keys.Count;

    /// The key at a position, in insertion order.
    public TKey GetKeyAt(nuint index) => _keys[index];

    /// The value at a position, in insertion order.
    ///
    /// @see OrderedDictionary.GetKeyAt
    public TValue GetValueAt(nuint index) => _values[index];

    /// Where a key is, or `None`.
    ///
    /// The one lookup a caller needs: asking whether a key is there and then
    /// asking for its value walks the collection twice. An `Optional` rather
    /// than a sentinel, because a position that means "no position" is a rule
    /// every caller has to know and none can be made to.
    ///
    /// @see OrderedDictionary.ContainsKey
    public Optional<nuint> IndexOf(TKey key)
    {
        for (nuint i = 0u; i < _keys.Count; i++)
        {
            if (_keys[i].Equals(key))
                return Some(i);
        }
        return None;
    }

    /// Whether the key is there at all. A scan, like everything else here, so
    /// `IndexOf` once beats `ContainsKey` followed by a lookup.
    ///
    /// @see OrderedDictionary.IndexOf
    public bool ContainsKey(TKey key) => IndexOf(key).HasValue;

    /// Appends, without looking for the key first.
    ///
    /// A repeated key is kept rather than replaced, because a document that
    /// contains one said so and dropping either half would be this collection
    /// deciding what the document meant. `SetValue` is the one that replaces.
    ///
    /// @see OrderedDictionary.SetValue
    /// @seealso OrderedDictionary.Remove
    public void Add(TKey key, TValue value)
    {
        _keys.Add(key);
        _values.Add(value);
    }

    /// Replaces the value of a key, or appends it. A replaced key keeps the
    /// position it had, which is the point of the collection.
    ///
    /// @see OrderedDictionary.Add
    public void SetValue(TKey key, TValue value)
    {
        if (IndexOf(key) is Some at)
        {
            _values[at.Value] = value;
        }
        else
        {
            Add(key, value);
        }
    }

    /// The value of a key, or the fallback. There is no overload that aborts:
    /// a caller that wants to know writes `IndexOf`.
    ///
    /// @see OrderedDictionary.IndexOf
    public TValue GetValueOrDefault(TKey key, TValue fallback)
    {
        if (IndexOf(key) is Some at)
            return _values[at.Value];
        return fallback;
    }

    /// Removes the first entry with that key, closing the gap. Answers whether
    /// there was one.
    ///
    /// @see OrderedDictionary.Add
    public bool Remove(TKey key)
    {
        if (IndexOf(key) is Some at)
        {
            _keys.RemoveAt(at.Value);
            _values.RemoveAt(at.Value);
            return true;
        }
        return false;
    }

    /// Drops every entry, leaving a count of zero.
    public void Clear()
    {
        _keys.Clear();
        _values.Clear();
    }
}
