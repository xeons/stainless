// Stainless - an experimental systems language.
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

// The hash-table collections.
//
// A module may span files, so these join Standard.Collections rather than
// forming a module of their own. Both are open addressing with linear probing:
// one array per column instead of an array of entries, because an entry would
// have to be a class and that is an allocation per key.
//
// Deletion shifts the following cluster back rather than leaving a tombstone,
// so a table that is added to and removed from for a long time does not slowly
// fill up with markers that only a rehash can clear.
module Standard.Collections;

/// Aborts with a message. Used where a container is asked for something it does
/// not have, which is a mistake in the caller rather than a value to return.
extern "C" void sl_fail(byte* message);

// ------------------------------------------------------------------- pairs

/// One key and one value. What a dictionary yields when it is iterated.
public class Pair<K, V> {
    public K Key { get; }
    public V Value { get; }

    public Pair(K key, V value) {
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
public class Dictionary<K, V> : IEnumerable<Pair<K, V>>
    where K : IEquatable<K>, IHashable
{
    K[] keys;
    V[] values;
    bool[] filled;

    // One zeroed element of each, to blank a slot with. The language has no
    // `default(T)`, and a slot that is merely abandoned would keep whatever
    // reference it held alive.
    K[] noKey;
    V[] noValue;

    nuint count;

    public Dictionary() {
        keys = new K[8];
        values = new V[8];
        filled = new bool[8];
        noKey = new K[1];
        noValue = new V[1];
        count = 0;
    }

    public nuint Count() { return count; }

    public bool IsEmpty() { return count == 0; }

    /// The number of slots the table has. Always a power of two, so the hash is
    /// reduced with a mask rather than a division.
    public nuint Capacity() { return keys.Length; }

    /// The slot holding `key`, or the first free slot it would take. Which one
    /// it is, is what `filled` at that index says.
    nuint Probe(K key) {
        nuint mask = keys.Length - 1;
        nuint i = key.HashCode() & mask;

        while (filled[i]) {
            if (keys[i].EqualTo(key)) { return i; }
            i = (i + 1) & mask;
        }
        return i;
    }

    public bool ContainsKey(K key) { return filled[Probe(key)]; }

    /// The value for `key`. Aborts when there is none; use `GetOr` or
    /// `ContainsKey` when a missing key is an ordinary outcome.
    public V Get(K key) {
        nuint i = Probe(key);
        if (!filled[i]) { sl_fail("Dictionary.Get: no such key"); }
        return values[i];
    }

    /// The value for `key`, or `fallback` when there is none.
    public V GetOr(K key, V fallback) {
        nuint i = Probe(key);
        if (!filled[i]) { return fallback; }
        return values[i];
    }

    /// Adds the key or replaces what it maps to.
    public void Set(K key, V value) {
        nuint i = Probe(key);
        if (filled[i]) {
            values[i] = value;
            return;
        }

        // Growing moves every entry, so the slot has to be found again after it.
        if ((count + 1) * 4 > keys.Length * 3) {
            Grow();
            i = Probe(key);
        }

        keys[i] = key;
        values[i] = value;
        filled[i] = true;
        count = count + 1;
    }

    /// Adds the key, or reports that it was already there and changes nothing.
    public bool Add(K key, V value) {
        if (filled[Probe(key)]) { return false; }
        Set(key, value);
        return true;
    }

    /// Removes the key, reporting whether it was there.
    public bool Remove(K key) {
        nuint i = Probe(key);
        if (!filled[i]) { return false; }

        nuint mask = keys.Length - 1;
        nuint j = i;

        // Backward-shift deletion. Everything after the hole is examined, and
        // anything whose own probe would now run past the hole moves back into
        // it, which keeps every remaining key reachable without a tombstone.
        while (true) {
            j = (j + 1) & mask;
            if (!filled[j]) { break; }

            nuint home = keys[j].HashCode() & mask;

            // Leave it where it is when its home lies cyclically in (i, j].
            bool settled = i <= j ? i < home && home <= j : i < home || home <= j;
            if (settled) { continue; }

            keys[i] = keys[j];
            values[i] = values[j];
            i = j;
        }

        keys[i] = noKey[0];
        values[i] = noValue[0];
        filled[i] = false;
        count = count - 1;
        return true;
    }

    /// Drops every entry. The arrays are replaced rather than blanked, so
    /// anything they held is released now.
    public void Clear() {
        keys = new K[8];
        values = new V[8];
        filled = new bool[8];
        count = 0;
    }

    public List<K> Keys() {
        var result = new List<K>();
        for (nuint i = 0; i < filled.Length; i = i + 1) {
            if (filled[i]) { result.Add(keys[i]); }
        }
        return result;
    }

    public List<V> Values() {
        var result = new List<V>();
        for (nuint i = 0; i < filled.Length; i = i + 1) {
            if (filled[i]) { result.Add(values[i]); }
        }
        return result;
    }

    public IEnumerator<Pair<K, V>> GetEnumerator() {
        return new DictionaryEnumerator<K, V>(this);
    }

    // What the enumerator needs and nothing else does: a slot's state, and the
    // entry in it. Not public, so the shape of the table stays inside the
    // module that has to keep it consistent.
    bool Occupied(nuint slot) { return filled[slot]; }

    Pair<K, V> PairAt(nuint slot) { return new Pair<K, V>(keys[slot], values[slot]); }

    void Grow() {
        var oldKeys = keys;
        var oldValues = values;
        var oldFilled = filled;

        keys = new K[oldKeys.Length * 2];
        values = new V[oldValues.Length * 2];
        filled = new bool[oldFilled.Length * 2];
        count = 0;

        for (nuint i = 0; i < oldFilled.Length; i = i + 1) {
            if (!oldFilled[i]) { continue; }

            nuint j = Probe(oldKeys[i]);
            keys[j] = oldKeys[i];
            values[j] = oldValues[i];
            filled[j] = true;
            count = count + 1;
        }
    }
}

/// Walks a dictionary's slots, skipping the empty ones.
///
/// The order is the table's own and says nothing about insertion order; adding
/// or removing during a walk invalidates it, as it does in C#.
public class DictionaryEnumerator<K, V> : IEnumerator<Pair<K, V>>
    where K : IEquatable<K>, IHashable
{
    Dictionary<K, V> source;
    nuint at;
    nuint scanned;

    public DictionaryEnumerator(Dictionary<K, V> dictionary) {
        source = dictionary;
        at = 0;
        scanned = 0;
    }

    public bool MoveNext() {
        while (scanned < source.Capacity()) {
            at = scanned;
            scanned = scanned + 1;
            if (source.Occupied(at)) { return true; }
        }
        return false;
    }

    public Pair<K, V> Current() { return source.PairAt(at); }
}

// ----------------------------------------------------------------- hash set

/// A set of distinct values, with membership in constant time.
///
/// The same table as `Dictionary`, without the values.
public class HashSet<T> : IEnumerable<T> where T : IEquatable<T>, IHashable {
    T[] items;
    bool[] filled;
    T[] noItem;
    nuint count;

    public HashSet() {
        items = new T[8];
        filled = new bool[8];
        noItem = new T[1];
        count = 0;
    }

    public nuint Count() { return count; }

    public bool IsEmpty() { return count == 0; }

    public nuint Capacity() { return items.Length; }

    nuint Probe(T item) {
        nuint mask = items.Length - 1;
        nuint i = item.HashCode() & mask;

        while (filled[i]) {
            if (items[i].EqualTo(item)) { return i; }
            i = (i + 1) & mask;
        }
        return i;
    }

    public bool Contains(T item) { return filled[Probe(item)]; }

    /// Adds the item, reporting whether it was new.
    public bool Add(T item) {
        nuint i = Probe(item);
        if (filled[i]) { return false; }

        if ((count + 1) * 4 > items.Length * 3) {
            Grow();
            i = Probe(item);
        }

        items[i] = item;
        filled[i] = true;
        count = count + 1;
        return true;
    }

    /// Removes the item, reporting whether it was there.
    public bool Remove(T item) {
        nuint i = Probe(item);
        if (!filled[i]) { return false; }

        nuint mask = items.Length - 1;
        nuint j = i;

        while (true) {
            j = (j + 1) & mask;
            if (!filled[j]) { break; }

            nuint home = items[j].HashCode() & mask;
            bool settled = i <= j ? i < home && home <= j : i < home || home <= j;
            if (settled) { continue; }

            items[i] = items[j];
            i = j;
        }

        items[i] = noItem[0];
        filled[i] = false;
        count = count - 1;
        return true;
    }

    public void Clear() {
        items = new T[8];
        filled = new bool[8];
        count = 0;
    }

    /// Adds everything in `other` that is not here already.
    public void UnionWith(IReadOnlyList<T> other) {
        for (nuint i = 0; i < other.Count(); i = i + 1) { Add(other.At(i)); }
    }

    /// Removes everything in `other`.
    public void ExceptWith(IReadOnlyList<T> other) {
        for (nuint i = 0; i < other.Count(); i = i + 1) { Remove(other.At(i)); }
    }

    /// Keeps only what is also in `other`.
    public void IntersectWith(HashSet<T> other) {
        var doomed = new List<T>();
        for (nuint i = 0; i < filled.Length; i = i + 1) {
            if (filled[i] && !other.Contains(items[i])) { doomed.Add(items[i]); }
        }
        for (nuint i = 0; i < doomed.Count(); i = i + 1) { Remove(doomed.At(i)); }
    }

    public List<T> ToList() {
        var result = new List<T>();
        for (nuint i = 0; i < filled.Length; i = i + 1) {
            if (filled[i]) { result.Add(items[i]); }
        }
        return result;
    }

    public IEnumerator<T> GetEnumerator() { return new ListEnumerator<T>(ToList()); }

    void Grow() {
        var oldItems = items;
        var oldFilled = filled;

        items = new T[oldItems.Length * 2];
        filled = new bool[oldFilled.Length * 2];
        count = 0;

        for (nuint i = 0; i < oldFilled.Length; i = i + 1) {
            if (!oldFilled[i]) { continue; }

            nuint j = Probe(oldItems[i]);
            items[j] = oldItems[i];
            filled[j] = true;
            count = count + 1;
        }
    }
}
