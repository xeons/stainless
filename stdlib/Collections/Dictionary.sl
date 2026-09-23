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

/// The hash-table collections.
///
/// A module may span files, so these join Standard.Collections rather than
/// forming a module of their own. Both are open addressing with linear probing:
/// one array per column instead of an array of entries, because an entry would
/// have to be a class and that is an allocation per key.
///
/// Deletion shifts the following cluster back rather than leaving a tombstone,
/// so a table that is added to and removed from for a long time does not slowly
/// fill up with markers that only a rehash can clear.
module Standard.Collections;

/// Aborts with a message. Used where a container is asked for something it does
/// not have, which is a mistake in the caller rather than a value to return.
extern "C" void sl_fail(byte* message);

// -------------------------------------------------------------- dictionary

/// A map from keys to values.
///
/// `TKey` has to be equatable and hashable. A primitive, an enum and a String all
/// are without saying so, so `Dictionary<String, int>` needs nothing extra; a
/// class says so by implementing `IEquatable<T>` and `IHashable`.
///
/// @typeparam TKey    what an entry is found by: equatable and hashable, and
///                    the two must agree, since a probe hashes to a slot and
///                    then compares
/// @typeparam TValue  what an entry holds; nothing is asked of it
public class Dictionary<TKey, TValue> : IEnumerable<KeyValuePair<TKey, TValue>>
    where TKey : IEquatable<TKey>, IHashable
{
    TKey[] _keys;
    TValue[] _values;
    bool[] _filled;

    nuint _count;

    /// An empty dictionary with room for a few entries before it first grows.
    public Dictionary()
    {
        _keys = new TKey[8];
        _values = new TValue[8];
        _filled = new bool[8];
        _count = 0;
    }

    /// How many entries there are. O(1) -- it is a counter, not a scan.
    public nuint Count => _count;

    /// True when there are no entries.
    public bool IsEmpty => _count == 0;

    /// The number of slots the table has. Always a power of two, so the hash is
    /// reduced with a mask rather than a division.
    public nuint Capacity => _keys.Length;

    /// The slot holding `key`, or the first free slot it would take. Which one
    /// it is, is what `filled` at that index says.
    nuint FindSlot(TKey key)
    {
        nuint mask = _keys.Length - 1;
        nuint i = key.GetHashCode() & mask;

        while (_filled[i])
        {
            if (_keys[i].Equals(key))
                return i;
            i = (i + 1) & mask;
        }
        return i;
    }

    /// Whether `key` is there.
    ///
    /// One probe, but reach for `TryGetValue` when the value is what is wanted:
    /// `ContainsKey` and then `GetValue` probes twice for one answer.
    ///
    /// @see Dictionary.TryGetValue
    public bool ContainsKey(TKey key) => _filled[FindSlot(key)];

    /// The value for `key`, or `None` when there is none.
    ///
    /// **This is the one to reach for.** A key is data -- it arrives from a
    /// file, a socket or a user -- so a key that is not there is an ordinary
    /// outcome and not a mistake in the program, which is the line §2.6 draws
    /// between a value to return and a reason to stop. The answer is read the
    /// way any other variant is:
    ///
    ///     if (settings.TryGetValue(name) is Some value) { Use(value); }
    ///
    /// One probe, where `ContainsKey` followed by `GetValue` is two, and no sentinel
    /// to collide with a real value the way `GetValueOrDefault` has.
    ///
    /// @see Dictionary.GetValue
    /// @seealso Dictionary.GetValueOrDefault
    public Optional<TValue> TryGetValue(TKey key)
    {
        nuint i = FindSlot(key);
        if (!_filled[i])
            return None;
        return Some(_values[i]);
    }

    /// The value for `key`, aborting when there is none.
    ///
    /// The asserting form, and it asserts: use it only where the key is there
    /// by construction -- one set two lines above, or a name this code chose
    /// itself. `GetValue` means the same thing here as on `Optional`, which is that
    /// the caller is claiming the value exists and would rather stop than
    /// carry on if it does not. For a key that came from anywhere else, `Find`
    /// is the question and this is not.
    ///
    /// @see Dictionary.TryGetValue
    public TValue GetValue(TKey key)
    {
        nuint i = FindSlot(key);
        if (!_filled[i])
            sl_fail("Dictionary.GetValue: no such key");
        return _values[i];
    }

    /// The value for `key`, or `fallback` when there is none.
    ///
    /// @see Dictionary.TryGetValue
    public TValue GetValueOrDefault(TKey key, TValue fallback)
    {
        nuint i = FindSlot(key);
        if (!_filled[i])
            return fallback;
        return _values[i];
    }

    /// `map[key]`, which answers `Optional<TValue>` and never stops the program.
    ///
    /// Swift's design, and it is the right one for the same reason: a key is
    /// data rather than a position, so a lookup that misses is an answer. An
    /// indexer returning `TValue` would have to abort on a miss, and `map[key]`
    /// carries no verb to warn anyone that it might -- which is exactly the
    /// shape a reader trusts without thinking.
    ///
    ///     if (settings["timeout"] is Some found) { Use(found.Value); }
    ///     int port = settings["port"].GetValueOrDefault(8080);
    ///
    /// A getter and a setter share one type (§7.5), so the setter takes an
    /// `Optional<TValue>` too -- and that turns out to say something rather than
    /// being a cost. A value promotes to the optional holding it, so an
    /// ordinary write reads as one; and `None` is the absence of a value,
    /// which is what removing a key means.
    ///
    ///     settings["retries"] = 3;            // set
    ///     settings["retries"] = None;         // remove
    ///
    /// What this cannot do is `map[key] += 1`, because there is no value to
    /// add to when the key is absent. That is not a limitation so much as the
    /// question being asked out loud: `map[key] = map[key].GetValueOrDefault(0) + 1`
    /// says what should happen, and Swift's `dict[key, default: 0] += 1`
    /// exists for the same reason.
    ///
    /// @see Dictionary.TryGetValue
    /// @seealso Dictionary.SetValue
    public Optional<TValue> this[TKey key]
    {
        get => TryGetValue(key);
        set
        {
            if (value is Some held)
            {
                SetValue(key, held.Value);
            }
            else
            {
                Remove(key);
            }
        }
    }

    /// Adds the key or replaces what it maps to.
    ///
    /// @see Dictionary.Add
    public void SetValue(TKey key, TValue value)
    {
        nuint i = FindSlot(key);
        if (_filled[i])
        {
            _values[i] = value;
            return;
        }

        // Growing moves every entry, so the slot has to be found again after it.
        if ((_count + 1) * 4 > _keys.Length * 3)
        {
            GrowTable();
            i = FindSlot(key);
        }

        _keys[i] = key;
        _values[i] = value;
        _filled[i] = true;
        _count++;
    }

    /// Adds the key, or reports that it was already there and changes nothing.
    ///
    /// @returns true when the entry was added, false when the key was already
    ///          there
    /// @see Dictionary.SetValue
    /// @seealso Dictionary.Remove
    public bool Add(TKey key, TValue value)
    {
        if (_filled[FindSlot(key)])
            return false;
        SetValue(key, value);
        return true;
    }

    /// Removes the key, reporting whether it was there.
    ///
    /// @see Dictionary.Add
    public bool Remove(TKey key)
    {
        nuint i = FindSlot(key);
        if (!_filled[i])
            return false;

        nuint mask = _keys.Length - 1;
        nuint j = i;

        // Backward-shift deletion. Everything after the hole is examined, and
        // anything whose own probe would now run past the hole moves back into
        // it, which keeps every remaining key reachable without a tombstone.
        while (true)
        {
            j = (j + 1) & mask;
            if (!_filled[j])
                break;

            nuint home = _keys[j].GetHashCode() & mask;

            // Leave it where it is when its home lies cyclically in (i, j].
            bool settled = i <= j ? i < home && home <= j : i < home || home <= j;
            if (settled)
                continue;

            _keys[i] = _keys[j];
            _values[i] = _values[j];
            i = j;
        }

        // Cleared rather than merely abandoned: a slot still holding its old
        // reference keeps that object alive for as long as the table lives.
        _keys[i] = default(TKey);
        _values[i] = default(TValue);
        _filled[i] = false;
        _count--;
        return true;
    }

    /// Drops every entry. The arrays are replaced rather than blanked, so
    /// anything they held is released now.
    public void Clear()
    {
        _keys = new TKey[8];
        _values = new TValue[8];
        _filled = new bool[8];
        _count = 0;
    }

    /// Every key, in the table's own order.
    ///
    /// A fresh list, so changing it changes nothing here, and building it is a
    /// scan of every slot rather than of every entry -- O(capacity), not
    /// O(count). Pairs with `GetValues` position for position as long as nothing
    /// is written in between.
    ///
    /// @see Dictionary.GetValues
    public List<TKey> GetKeys()
    {
        var result = new List<TKey>();
        for (nuint i = 0; i < _filled.Length; i++)
        {
            if (_filled[i])
                result.Add(_keys[i]);
        }
        return result;
    }

    /// Every value, in the same order `GetKeys` gives.
    ///
    /// Values are not distinct: a value stored under two keys appears twice.
    ///
    /// @see Dictionary.GetKeys
    public List<TValue> GetValues()
    {
        var result = new List<TValue>();
        for (nuint i = 0; i < _filled.Length; i++)
        {
            if (_filled[i])
                result.Add(_values[i]);
        }
        return result;
    }

    /// A cursor over the entries, for `foreach`.
    ///
    /// The order is the table's and is not insertion order; it changes when
    /// the table grows. `Standard.Collections.OrderedDictionary` is the one
    /// that keeps an order. Adding or removing during a walk invalidates the
    /// cursor.
    ///
    /// @see DictionaryEnumerator
    /// @seealso OrderedDictionary
    public IEnumerator<KeyValuePair<TKey, TValue>> GetEnumerator()
    {
        return new DictionaryEnumerator<TKey, TValue>(this);
    }

    // What the enumerator needs and nothing else does: a slot's state, and the
    // entry in it. Not public, so the shape of the table stays inside the
    // module that has to keep it consistent.
    bool IsOccupied(nuint slot) => _filled[slot];

    KeyValuePair<TKey, TValue> GetPairAt(nuint slot) =>
        new KeyValuePair<TKey, TValue>(_keys[slot], _values[slot]);

    void GrowTable()
    {
        var oldKeys = _keys;
        var oldValues = _values;
        var oldFilled = _filled;

        _keys = new TKey[oldKeys.Length * 2];
        _values = new TValue[oldValues.Length * 2];
        _filled = new bool[oldFilled.Length * 2];
        _count = 0;

        for (nuint i = 0; i < oldFilled.Length; i++)
        {
            if (!oldFilled[i])
                continue;

            nuint j = FindSlot(oldKeys[i]);
            _keys[j] = oldKeys[i];
            _values[j] = oldValues[i];
            _filled[j] = true;
            _count++;
        }
    }
}
