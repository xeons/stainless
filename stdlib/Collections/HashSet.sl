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

// ----------------------------------------------------------------- hash set

/// A set of distinct values, with membership in constant time.
///
/// The same table as `Dictionary`, without the values.
///
/// @typeparam T  what the set holds: equatable and hashable, and the two must
///               agree, since membership is a hash to a slot and a comparison
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

    nuint FindSlot(T item)
    {
        nuint mask = _items.Length - 1;
        nuint i = item.GetHashCode() & mask;

        while (_filled[i])
        {
            if (_items[i].Equals(item))
                return i;
            i = (i + 1) & mask;
        }
        return i;
    }

    /// Whether `item` is in the set. One probe, and the question the whole
    /// collection exists to answer.
    ///
    /// @see HashSet.Add
    public bool Contains(T item) => _filled[FindSlot(item)];

    /// Adds the item, reporting whether it was new.
    ///
    /// @see HashSet.Remove
    /// @seealso HashSet.Contains
    public bool Add(T item)
    {
        nuint i = FindSlot(item);
        if (_filled[i])
            return false;

        if ((_count + 1) * 4 > _items.Length * 3)
        {
            GrowTable();
            i = FindSlot(item);
        }

        _items[i] = item;
        _filled[i] = true;
        _count++;
        return true;
    }

    /// Removes the item, reporting whether it was there.
    ///
    /// @see HashSet.Add
    public bool Remove(T item)
    {
        nuint i = FindSlot(item);
        if (!_filled[i])
            return false;

        nuint mask = _items.Length - 1;
        nuint j = i;

        while (true)
        {
            j = (j + 1) & mask;
            if (!_filled[j])
                break;

            nuint home = _items[j].GetHashCode() & mask;
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
    ///
    /// @see HashSet.ExceptWith
    /// @seealso HashSet.IntersectWith
    public void UnionWith(IReadOnlyList<T> other)
    {
        for (nuint i = 0; i < other.Count; i++)
            Add(other[i]);
    }

    /// Removes everything in `other`.
    ///
    /// @see HashSet.UnionWith
    /// @seealso HashSet.IntersectWith
    public void ExceptWith(IReadOnlyList<T> other)
    {
        for (nuint i = 0; i < other.Count; i++)
            Remove(other[i]);
    }

    /// Keeps only what is also in `other`.
    ///
    /// @see HashSet.UnionWith
    /// @seealso HashSet.ExceptWith
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
    ///
    /// @see HashSet.GetEnumerator
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
    bool IsSlotFilled(nuint slot) => _filled[slot];
    T GetSlotValue(nuint slot) => _items[slot];

    /// A cursor over the items, for `foreach`. Allocates nothing beyond the
    /// cursor itself, unlike `ToList`. Adding or removing during a walk
    /// invalidates it.
    ///
    /// @see HashSetEnumerator
    /// @seealso HashSet.ToList
    public IEnumerator<T> GetEnumerator() => new HashSetEnumerator<T>(this);

    void GrowTable()
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

            nuint j = FindSlot(oldItems[i]);
            _items[j] = oldItems[i];
            _filled[j] = true;
            _count++;
        }
    }
}
