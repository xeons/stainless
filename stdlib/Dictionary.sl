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

// ------------------------------------------------------------------- pairs

/// One key and one value. What a dictionary yields when it is iterated.
public class Pair<TKey, TValue>
{
    /// The key half.
    public TKey Key { get; }

    /// The value half.
    public TValue Value { get; }

    /// Builds a pair. Iteration is what normally makes these -- one per entry
    /// visited, so a `foreach` over a large dictionary allocates one per step.
    public Pair(TKey key, TValue value)
    {
        Key = key;
        Value = value;
    }
}

// -------------------------------------------------------------- dictionary

/// A map from keys to values.
///
/// `K` has to be equatable and hashable. A primitive, an enum and a String all
/// are without saying so, so `Dictionary<String, int>` needs nothing extra; a
/// class says so by implementing `IEquatable<T>` and `IHashable`.
public class Dictionary<TKey, TValue> : IEnumerable<Pair<TKey, TValue>>
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
    nuint Probe(TKey key)
    {
        nuint mask = _keys.Length - 1;
        nuint i = key.HashCode() & mask;

        while (_filled[i])
        {
            if (_keys[i].EqualTo(key))
                return i;
            i = (i + 1) & mask;
        }
        return i;
    }

    /// Whether `key` is there.
    ///
    /// One probe, but reach for `Find` when the value is what is wanted:
    /// `ContainsKey` and then `Get` probes twice for one answer.
    public bool ContainsKey(TKey key) => _filled[Probe(key)];

    /// The value for `key`, or `None` when there is none.
    ///
    /// **This is the one to reach for.** A key is data -- it arrives from a
    /// file, a socket or a user -- so a key that is not there is an ordinary
    /// outcome and not a mistake in the program, which is the line §2.6 draws
    /// between a value to return and a reason to stop. The answer is read the
    /// way any other variant is:
    ///
    ///     if (settings.Find(name) is Some value) { Use(value); }
    ///
    /// One probe, where `ContainsKey` followed by `Get` is two, and no sentinel
    /// to collide with a real value the way `GetOr` has.
    public Optional<TValue> Find(TKey key)
    {
        nuint i = Probe(key);
        if (!_filled[i])
            return None;
        return Some(_values[i]);
    }

    /// The value for `key`, aborting when there is none.
    ///
    /// The asserting form, and it asserts: use it only where the key is there
    /// by construction -- one set two lines above, or a name this code chose
    /// itself. `Get` means the same thing here as on `Optional`, which is that
    /// the caller is claiming the value exists and would rather stop than
    /// carry on if it does not. For a key that came from anywhere else, `Find`
    /// is the question and this is not.
    public TValue Get(TKey key)
    {
        nuint i = Probe(key);
        if (!_filled[i])
            sl_fail("Dictionary.Get: no such key");
        return _values[i];
    }

    /// The value for `key`, or `fallback` when there is none.
    public TValue GetOr(TKey key, TValue fallback)
    {
        nuint i = Probe(key);
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
    ///     int port = settings["port"].ValueOr(8080);
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
    /// question being asked out loud: `map[key] = map[key].ValueOr(0) + 1`
    /// says what should happen, and Swift's `dict[key, default: 0] += 1`
    /// exists for the same reason.
    public Optional<TValue> this[TKey key]
    {
        get => Find(key);
        set
        {
            if (value is Some held)
            {
                Set(key, held.Value);
            }
            else
            {
                Remove(key);
            }
        }
    }

    /// Adds the key or replaces what it maps to.
    public void Set(TKey key, TValue value)
    {
        nuint i = Probe(key);
        if (_filled[i])
        {
            _values[i] = value;
            return;
        }

        // Growing moves every entry, so the slot has to be found again after it.
        if ((_count + 1) * 4 > _keys.Length * 3)
        {
            Grow();
            i = Probe(key);
        }

        _keys[i] = key;
        _values[i] = value;
        _filled[i] = true;
        _count++;
    }

    /// Adds the key, or reports that it was already there and changes nothing.
    public bool Add(TKey key, TValue value)
    {
        if (_filled[Probe(key)])
            return false;
        Set(key, value);
        return true;
    }

    /// Removes the key, reporting whether it was there.
    public bool Remove(TKey key)
    {
        nuint i = Probe(key);
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

            nuint home = _keys[j].HashCode() & mask;

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
    /// O(count). Pairs with `Values` position for position as long as nothing
    /// is written in between.
    public List<TKey> Keys()
    {
        var result = new List<TKey>();
        for (nuint i = 0; i < _filled.Length; i++)
        {
            if (_filled[i])
                result.Add(_keys[i]);
        }
        return result;
    }

    /// Every value, in the same order `Keys` gives.
    ///
    /// Values are not distinct: a value stored under two keys appears twice.
    public List<TValue> Values()
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
    public IEnumerator<Pair<TKey, TValue>> GetEnumerator()
    {
        return new DictionaryEnumerator<TKey, TValue>(this);
    }

    // What the enumerator needs and nothing else does: a slot's state, and the
    // entry in it. Not public, so the shape of the table stays inside the
    // module that has to keep it consistent.
    bool Occupied(nuint slot) => _filled[slot];

    Pair<TKey, TValue> PairAt(nuint slot) => new Pair<TKey, TValue>(_keys[slot], _values[slot]);

    void Grow()
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

            nuint j = Probe(oldKeys[i]);
            _keys[j] = oldKeys[i];
            _values[j] = oldValues[i];
            _filled[j] = true;
            _count++;
        }
    }
}

/// Walks a dictionary's slots, skipping the empty ones.
///
/// The order is the table's own and says nothing about insertion order; adding
/// or removing during a walk invalidates it, as it does in C#.
public class DictionaryEnumerator<TKey, TValue> : IEnumerator<Pair<TKey, TValue>>
    where TKey : IEquatable<TKey>, IHashable
{
    Dictionary<TKey, TValue> _source;
    nuint _at;
    nuint _scanned;

    /// A cursor over `dictionary`, positioned before the first entry. The
    /// dictionary is held by reference and must not be written to while the
    /// cursor is live.
    public DictionaryEnumerator(Dictionary<TKey, TValue> dictionary)
    {
        _source = dictionary;
        _at = 0;
        _scanned = 0;
    }

    /// Advances to the next occupied slot, answering false at the end. Each
    /// call skips however many empty slots lie between, so a walk costs
    /// O(capacity) overall rather than O(count).
    public bool MoveNext()
    {
        while (_scanned < _source.Capacity)
        {
            _at = _scanned;
            _scanned++;
            if (_source.Occupied(_at))
                return true;
        }
        return false;
    }

    /// The entry the last `MoveNext` landed on, as a freshly built `Pair`.
    public Pair<TKey, TValue> Current => _source.PairAt(_at);
}

// ----------------------------------------------------------------- hash set

/// A set of distinct values, with membership in constant time.
///
/// The same table as `Dictionary`, without the values.
public class HashSet<T> : IEnumerable<T> where T : IEquatable<T>, IHashable
{
    T[] _items;
    bool[] _filled;
    T[] _noItem;
    nuint _count;

    /// An empty set with room for a few items before it first grows.
    public HashSet()
    {
        _items = new T[8];
        _filled = new bool[8];
        _noItem = new T[1];
        _count = 0;
    }

    /// How many distinct items there are. O(1).
    public nuint Count => _count;

    /// True when there is nothing in it.
    public bool IsEmpty => _count == 0;

    /// The number of slots the table has. Always a power of two, so the hash
    /// is reduced with a mask rather than a division.
    public nuint Capacity => _items.Length;

    nuint Probe(T item)
    {
        nuint mask = _items.Length - 1;
        nuint i = item.HashCode() & mask;

        while (_filled[i])
        {
            if (_items[i].EqualTo(item))
                return i;
            i = (i + 1) & mask;
        }
        return i;
    }

    /// Whether `item` is in the set. One probe, and the question the whole
    /// collection exists to answer.
    public bool Contains(T item) => _filled[Probe(item)];

    /// Adds the item, reporting whether it was new.
    public bool Add(T item)
    {
        nuint i = Probe(item);
        if (_filled[i])
            return false;

        if ((_count + 1) * 4 > _items.Length * 3)
        {
            Grow();
            i = Probe(item);
        }

        _items[i] = item;
        _filled[i] = true;
        _count++;
        return true;
    }

    /// Removes the item, reporting whether it was there.
    public bool Remove(T item)
    {
        nuint i = Probe(item);
        if (!_filled[i])
            return false;

        nuint mask = _items.Length - 1;
        nuint j = i;

        while (true)
        {
            j = (j + 1) & mask;
            if (!_filled[j])
                break;

            nuint home = _items[j].HashCode() & mask;
            bool settled = i <= j ? i < home && home <= j : i < home || home <= j;
            if (settled)
                continue;

            _items[i] = _items[j];
            i = j;
        }

        _items[i] = _noItem[0];
        _filled[i] = false;
        _count--;
        return true;
    }

    /// Drops every item. The arrays are replaced rather than blanked, so
    /// anything they held is released now.
    public void Clear()
    {
        _items = new T[8];
        _filled = new bool[8];
        _count = 0;
    }

    /// Adds everything in `other` that is not here already.
    public void UnionWith(IReadOnlyList<T> other)
    {
        for (nuint i = 0; i < other.Count; i++)
            Add(other[i]);
    }

    /// Removes everything in `other`.
    public void ExceptWith(IReadOnlyList<T> other)
    {
        for (nuint i = 0; i < other.Count; i++)
            Remove(other[i]);
    }

    /// Keeps only what is also in `other`.
    public void IntersectWith(HashSet<T> other)
    {
        var doomed = new List<T>();
        for (nuint i = 0; i < _filled.Length; i++)
        {
            if (_filled[i] && !other.Contains(_items[i]))
                doomed.Add(_items[i]);
        }
        for (nuint i = 0; i < doomed.Count; i++)
            Remove(doomed[i]);
    }

    /// Every item, in the table's own order -- which is not insertion order
    /// and changes when the table grows.
    ///
    /// A fresh list, and building it scans every slot: O(capacity), not
    /// O(count). `foreach` walks the set without building one.
    public List<T> ToList()
    {
        var result = new List<T>();
        for (nuint i = 0; i < _filled.Length; i++)
        {
            if (_filled[i])
                result.Add(_items[i]);
        }
        return result;
    }

    /// The two a cursor needs to walk the table: how many slots there are, and
    /// what is in one. A set has no index of its own, so neither is public.
    nuint SlotCount => _filled.Length;
    bool SlotFilled(nuint slot) => _filled[slot];
    T SlotValue(nuint slot) => _items[slot];

    /// A cursor over the items, for `foreach`. Allocates nothing beyond the
    /// cursor itself, unlike `ToList`. Adding or removing during a walk
    /// invalidates it.
    public IEnumerator<T> GetEnumerator() => new HashSetCursor<T>(this);

    void Grow()
    {
        var oldItems = _items;
        var oldFilled = _filled;

        _items = new T[oldItems.Length * 2];
        _filled = new bool[oldFilled.Length * 2];
        _count = 0;

        for (nuint i = 0; i < oldFilled.Length; i++)
        {
            if (!oldFilled[i])
                continue;

            nuint j = Probe(oldItems[i]);
            _items[j] = oldItems[i];
            _filled[j] = true;
            _count++;
        }
    }
}

/// Walks a set's table, skipping the empty slots.
///
/// The same shape as `DictionaryEnumerator`, and for the same reason: the
/// materialising version built a whole `List<T>` before the first `MoveNext`,
/// so iterating a set allocated as much again as the set held.
public class HashSetCursor<T> : IEnumerator<T> where T : IEquatable<T>, IHashable
{
    HashSet<T> _source;
    nuint _at;
    nuint _scanned;

    /// A cursor over `set`, positioned before the first item. The set is held
    /// by reference and must not be written to while the cursor is live.
    public HashSetCursor(HashSet<T> set)
    {
        _source = set;
        _at = 0;
        _scanned = 0;
    }

    /// Advances to the next occupied slot, answering false at the end.
    public bool MoveNext()
    {
        while (_scanned < _source.SlotCount)
        {
            _at = _scanned;
            _scanned++;
            if (_source.SlotFilled(_at))
                return true;
        }
        return false;
    }

    /// The item the last `MoveNext` landed on.
    public T Current => _source.SlotValue(_at);
}
