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

module Standard.Concurrent;

import Standard.Collections;
import Standard.Threading;

// -------------------------------------------------------------- dictionary

/// A map several threads may use at once.
///
/// @typeparam TKey    what entries are found by. It is compared and hashed on every lookup, so
///                    it must implement both `IEquatable<TKey>` and `IHashable`.
/// @typeparam TValue  what is stored against a key; nothing is required of it
public threadsafe class ConcurrentDictionary<TKey, TValue> where TKey : IEquatable<TKey>, IHashable
{
    Dictionary<TKey, TValue> _entries;
    byte* _gate;

    /// An empty map, with its own mutex.
    public ConcurrentDictionary()
    {
        _entries = new Dictionary<TKey, TValue>();
        _gate = sl_mutex_new();
    }

    ~ConcurrentDictionary() { sl_mutex_free(_gate); }

    /// Sets the value of a key, whether or not it was there. `Add` is the one
    /// that refuses to overwrite.
    public void SetValue(TKey key, TValue value)
    {
        sl_mutex_lock(_gate);
        _entries.SetValue(key, value);
        sl_mutex_unlock(_gate);
    }

    /// Adds the key only if it is absent, reporting whether it did. This is the
    /// operation `ContainsKey` followed by `SetValue` cannot be: between those two
    /// another thread can insert.
    public bool TryAdd(TKey key, TValue value)
    {
        sl_mutex_lock(_gate);
        bool added = _entries.Add(key, value);
        sl_mutex_unlock(_gate);
        return added;
    }

    /// The value for `key` if it is there. One lock rather than two, which is
    /// what makes it different from `ContainsKey` followed by a lookup:
    /// between those two another thread can remove the key.
    public Optional<TValue> TryGetValue(TKey key)
    {
        sl_mutex_lock(_gate);

        if (!_entries.ContainsKey(key))
        {
            sl_mutex_unlock(_gate);
            return None;
        }

        var value = _entries.GetValue(key);
        sl_mutex_unlock(_gate);
        return Some(value);
    }

    /// The value for `key`, or `fallback` when it is absent. No allocation,
    /// at the cost of being unable to tell an absent key from one whose value
    /// happens to equal the fallback.
    public TValue GetValueOrDefault(TKey key, TValue fallback)
    {
        sl_mutex_lock(_gate);
        var value = _entries.GetValueOrDefault(key, fallback);
        sl_mutex_unlock(_gate);
        return value;
    }

    /// Whether the key is there *now*. True here does not mean the next
    /// `TryGetValue` succeeds -- another thread may remove it in between -- so this
    /// is for reporting, and `TryGetValue` is for acting.
    public bool ContainsKey(TKey key)
    {
        sl_mutex_lock(_gate);
        bool present = _entries.ContainsKey(key);
        sl_mutex_unlock(_gate);
        return present;
    }

    /// Removes a key, answering whether it was there. The answer is exact:
    /// exactly one of several threads racing to remove the same key gets true.
    public bool TryRemove(TKey key)
    {
        sl_mutex_lock(_gate);
        bool removed = _entries.Remove(key);
        sl_mutex_unlock(_gate);
        return removed;
    }

    /// Drops every entry, under one lock.
    public void Clear()
    {
        sl_mutex_lock(_gate);
        _entries.Clear();
        sl_mutex_unlock(_gate);
    }

    /// How many entries there are *now*. For reporting rather than deciding.
    public nuint Count
    {
        get
        {
            sl_mutex_lock(_gate);
            nuint result = _entries.Count;
            sl_mutex_unlock(_gate);
            return result;
        }
    }

    /// Whether it is empty *now*, with the same caveat as `Count`.
    public bool IsEmpty => Count == 0;

    /// A snapshot of the keys. Out of date the moment it is returned, which is
    /// why it is a copy rather than a view.
    public List<TKey> GetKeys()
    {
        sl_mutex_lock(_gate);
        var copy = _entries.GetKeys();
        sl_mutex_unlock(_gate);
        return copy;
    }

    /// A snapshot of the values, in the same order as `GetKeys` when neither is
    /// interleaved with a write. Out of date the moment it is returned, and
    /// pairing the two lists after the fact is not safe -- iterate the map if
    /// the pairing matters.
    public List<TValue> GetValues()
    {
        sl_mutex_lock(_gate);
        var copy = _entries.GetValues();
        sl_mutex_unlock(_gate);
        return copy;
    }
}
