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
    /// The key half.
    public K Key { get; }

    /// The value half.
    public V Value { get; }

    /// Builds a pair. Iteration is what normally makes these -- one per entry
    /// visited, so a `foreach` over a large dictionary allocates one per step.
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

    nuint count;

    /// An empty dictionary with room for a few entries before it first grows.
    public Dictionary() {
        keys = new K[8];
        values = new V[8];
        filled = new bool[8];
        count = 0;
    }

    /// How many entries there are. O(1) -- it is a counter, not a scan.
    public nuint Count() { return count; }

    /// True when there are no entries.
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

    /// Whether `key` is there.
    ///
    /// One probe, but reach for `Find` when the value is what is wanted:
    /// `ContainsKey` and then `Get` probes twice for one answer.
    public bool ContainsKey(K key) { return filled[Probe(key)]; }

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
    public Optional<V> Find(K key) {
        nuint i = Probe(key);
        if (!filled[i]) { return None; }
        return Some(values[i]);
    }

    /// The value for `key`, aborting when there is none.
    ///
    /// The asserting form, and it asserts: use it only where the key is there
    /// by construction -- one set two lines above, or a name this code chose
    /// itself. `Get` means the same thing here as on `Optional`, which is that
    /// the caller is claiming the value exists and would rather stop than
    /// carry on if it does not. For a key that came from anywhere else, `Find`
    /// is the question and this is not.
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

    /// `map[key]`, which answers `Optional<V>` and never stops the program.
    ///
    /// Swift's design, and it is the right one for the same reason: a key is
    /// data rather than a position, so a lookup that misses is an answer. An
    /// indexer returning `V` would have to abort on a miss, and `map[key]`
    /// carries no verb to warn anyone that it might -- which is exactly the
    /// shape a reader trusts without thinking.
    ///
    ///     if (settings["timeout"] is Some found) { Use(found.Value); }
    ///     int port = settings["port"].ValueOr(8080);
    ///
    /// A getter and a setter share one type (§7.5), so the setter takes an
    /// `Optional<V>` too -- and that turns out to say something rather than
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
    public Optional<V> this[K key] {
        get { return Find(key); }
        set {
            if (value is Some held) { Set(key, held.Value); }
            else { Remove(key); }
        }
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
        count++;
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

        // Cleared rather than merely abandoned: a slot still holding its old
        // reference keeps that object alive for as long as the table lives.
        keys[i] = default(K);
        values[i] = default(V);
        filled[i] = false;
        count--;
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

    /// Every key, in the table's own order.
    ///
    /// A fresh list, so changing it changes nothing here, and building it is a
    /// scan of every slot rather than of every entry -- O(capacity), not
    /// O(count). Pairs with `Values` position for position as long as nothing
    /// is written in between.
    public List<K> Keys() {
        var result = new List<K>();
        for (nuint i = 0; i < filled.Length; i++) {
            if (filled[i]) { result.Add(keys[i]); }
        }
        return result;
    }

    /// Every value, in the same order `Keys` gives.
    ///
    /// Values are not distinct: a value stored under two keys appears twice.
    public List<V> Values() {
        var result = new List<V>();
        for (nuint i = 0; i < filled.Length; i++) {
            if (filled[i]) { result.Add(values[i]); }
        }
        return result;
    }

    /// A cursor over the entries, for `foreach`.
    ///
    /// The order is the table's and is not insertion order; it changes when
    /// the table grows. `Standard.Collections.OrderedDictionary` is the one
    /// that keeps an order. Adding or removing during a walk invalidates the
    /// cursor.
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

        for (nuint i = 0; i < oldFilled.Length; i++) {
            if (!oldFilled[i]) { continue; }

            nuint j = Probe(oldKeys[i]);
            keys[j] = oldKeys[i];
            values[j] = oldValues[i];
            filled[j] = true;
            count++;
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

    /// A cursor over `dictionary`, positioned before the first entry. The
    /// dictionary is held by reference and must not be written to while the
    /// cursor is live.
    public DictionaryEnumerator(Dictionary<K, V> dictionary) {
        source = dictionary;
        at = 0;
        scanned = 0;
    }

    /// Advances to the next occupied slot, answering false at the end. Each
    /// call skips however many empty slots lie between, so a walk costs
    /// O(capacity) overall rather than O(count).
    public bool MoveNext() {
        while (scanned < source.Capacity()) {
            at = scanned;
            scanned++;
            if (source.Occupied(at)) { return true; }
        }
        return false;
    }

    /// The entry the last `MoveNext` landed on, as a freshly built `Pair`.
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

    /// An empty set with room for a few items before it first grows.
    public HashSet() {
        items = new T[8];
        filled = new bool[8];
        noItem = new T[1];
        count = 0;
    }

    /// How many distinct items there are. O(1).
    public nuint Count() { return count; }

    /// True when there is nothing in it.
    public bool IsEmpty() { return count == 0; }

    /// The number of slots the table has. Always a power of two, so the hash
    /// is reduced with a mask rather than a division.
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

    /// Whether `item` is in the set. One probe, and the question the whole
    /// collection exists to answer.
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
        count++;
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
        count--;
        return true;
    }

    /// Drops every item. The arrays are replaced rather than blanked, so
    /// anything they held is released now.
    public void Clear() {
        items = new T[8];
        filled = new bool[8];
        count = 0;
    }

    /// Adds everything in `other` that is not here already.
    public void UnionWith(IReadOnlyList<T> other) {
        for (nuint i = 0; i < other.Count(); i++) { Add(other.At(i)); }
    }

    /// Removes everything in `other`.
    public void ExceptWith(IReadOnlyList<T> other) {
        for (nuint i = 0; i < other.Count(); i++) { Remove(other.At(i)); }
    }

    /// Keeps only what is also in `other`.
    public void IntersectWith(HashSet<T> other) {
        var doomed = new List<T>();
        for (nuint i = 0; i < filled.Length; i++) {
            if (filled[i] && !other.Contains(items[i])) { doomed.Add(items[i]); }
        }
        for (nuint i = 0; i < doomed.Count(); i++) { Remove(doomed.At(i)); }
    }

    /// Every item, in the table's own order -- which is not insertion order
    /// and changes when the table grows.
    ///
    /// A fresh list, and building it scans every slot: O(capacity), not
    /// O(count). `foreach` walks the set without building one.
    public List<T> ToList() {
        var result = new List<T>();
        for (nuint i = 0; i < filled.Length; i++) {
            if (filled[i]) { result.Add(items[i]); }
        }
        return result;
    }

    /// The two a cursor needs to walk the table: how many slots there are, and
    /// what is in one. A set has no index of its own, so neither is public.
    nuint SlotCount() { return filled.Length; }
    bool SlotFilled(nuint slot) { return filled[slot]; }
    T SlotValue(nuint slot) { return items[slot]; }

    /// A cursor over the items, for `foreach`. Allocates nothing beyond the
    /// cursor itself, unlike `ToList`. Adding or removing during a walk
    /// invalidates it.
    public IEnumerator<T> GetEnumerator() { return new HashSetCursor<T>(this); }

    void Grow() {
        var oldItems = items;
        var oldFilled = filled;

        items = new T[oldItems.Length * 2];
        filled = new bool[oldFilled.Length * 2];
        count = 0;

        for (nuint i = 0; i < oldFilled.Length; i++) {
            if (!oldFilled[i]) { continue; }

            nuint j = Probe(oldItems[i]);
            items[j] = oldItems[i];
            filled[j] = true;
            count++;
        }
    }
}

/// Walks a set's table, skipping the empty slots.
///
/// The same shape as `DictionaryEnumerator`, and for the same reason: the
/// materialising version built a whole `List<T>` before the first `MoveNext`,
/// so iterating a set allocated as much again as the set held.
public class HashSetCursor<T> : IEnumerator<T> where T : IEquatable<T>, IHashable {
    HashSet<T> source;
    nuint at;
    nuint scanned;

    /// A cursor over `set`, positioned before the first item. The set is held
    /// by reference and must not be written to while the cursor is live.
    public HashSetCursor(HashSet<T> set) {
        source = set;
        at = 0;
        scanned = 0;
    }

    /// Advances to the next occupied slot, answering false at the end.
    public bool MoveNext() {
        while (scanned < source.SlotCount()) {
            at = scanned;
            scanned++;
            if (source.SlotFilled(at)) { return true; }
        }
        return false;
    }

    /// The item the last `MoveNext` landed on.
    public T Current() { return source.SlotValue(at); }
}
