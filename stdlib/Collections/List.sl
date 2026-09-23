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

import Standard.Limits;

/// A growable list backed by a single array, doubling when it fills.
///
/// **The shape is .NET's `List<T>`.** A standard library that renames what
/// everyone already knows charges for it at every lookup, so the members here
/// are spelled the way C# spells them and mean what C# means.
///
/// Two deliberate differences, both stated rather than discovered:
///
/// - **`IsEmpty` is a property and .NET has no such member at all.** It reads
///   better than `Count == 0` at the point of use, and
///   [docs/style.md](docs/style.md) is the reason it is a property and not a
///   method: a zero-argument side-effect-free getter is a property here.
/// - **The members that compare two `T`s are free functions below**, not
///   methods. `Contains`, `IndexOf`, `RemoveFirst`, `Sort` and `BinarySearch` all
///   need `T : IEquatable<T>` or `IComparable<T>`, and this class constrains
///   `T` not at all -- a `List<Control>` has to stay possible. A class cannot
///   demand of one method's type parameter what it does not demand of every
///   element. .NET reaches them through `EqualityComparer<T>.Default`, which is
///   a runtime lookup this language has no equivalent of.
///
/// The members taking a predicate need no constraint, so those are methods,
/// exactly as in .NET.
///
/// @typeparam T  the element type, constrained not at all so that a
///               `List<Control>` stays possible
public class List<T> : IList<T>, IEnumerable<T>
{
    T[] _items;
    nuint _count;

    /// An empty list. It allocates a small backing array up front, so the
    /// first few `Add`s do not grow it.
    public List()
    {
        _items = new T[4];
        _count = 0;
    }

    /// An empty list with room for `capacity` items already reserved, for when
    /// the size is known and the doubling would be waste.
    public List(nuint capacity)
    {
        _items = new T[capacity < 1u ? 1u : capacity];
        _count = 0;
    }

    /// How many items are in the list -- not how many it has room for, which
    /// is `Capacity`.
    public nuint Count => _count;

    /// Whether there is nothing in it.
    public bool IsEmpty => _count == 0;

    /// The number of items this list can hold before it must grow again.
    ///
    /// Settable, as in .NET: assigning reallocates to exactly that size. A
    /// value below `Count` is ignored rather than truncating, because losing
    /// items is not what anyone means by reserving room.
    public nuint Capacity
    {
        get => _items.Length;
        set
        {
            if (value < _count || value == _items.Length)
                return;
            ResizeStorage(value < 1u ? 1u : value);
        }
    }

    /// The item at `index`, aborting past the end.
    ///
    /// Checked against `Count` rather than against the backing array, so a
    /// slot that exists but holds nothing is out of range and says so.
    ///
    /// **This is the only way to reach an item.** There were `At` and `Set`
    /// methods beside it and they are gone: two spellings of one operation is
    /// how a codebase ends up using the longer one everywhere, which is what
    /// had happened here.
    public T this[nuint index]
    {
        get
        {
            if (index >= _count)
                sl_array_bounds_fail(index, _count);
            return _items[index];
        }
        set
        {
            if (index >= _count)
                sl_array_bounds_fail(index, _count);
            _items[index] = value;
        }
    }

    /// Appends to the end, growing the backing array when it is full.
    ///
    /// Doubling, so a run of appends costs constant time each on average; a
    /// single one can cost a copy of everything so far.
    ///
    /// @see List.RemoveAt
    /// @seealso List.AddRange
    public void Add(T item)
    {
        if (_count == _items.Length)
            GrowStorage();
        _items[_count] = item;
        _count++;
    }

    /// Appends every item of another sequence, in its order.
    ///
    /// The items are collected before any is added, so a list given itself
    /// doubles rather than chasing its own growing end.
    ///
    /// @see List.InsertRange
    public void AddRange(IEnumerable<T> items) => InsertRange(_count, items);

    /// Inserts at a position, moving everything after it up one.
    ///
    /// `index == Count` appends, which is what makes a loop that inserts in
    /// order need no special case at the end.
    public void Insert(nuint index, T item)
    {
        if (index > _count)
            sl_array_bounds_fail(index, _count);
        if (_count == _items.Length)
            GrowStorage();

        // Backwards, so a slot is read before the copy that overwrites it.
        for (nuint i = _count; i > index; i--)
            _items[i] = _items[i - 1u];

        _items[index] = item;
        _count++;
    }

    /// Removes the item at a position, closing the gap.
    ///
    /// The vacated slot is cleared rather than left holding what moved out of
    /// it: a list of references would otherwise keep the last one alive past
    /// its removal, which is a leak that only shows up under a profiler.
    ///
    /// @see List.Add
    /// @seealso List.RemoveRange
    public void RemoveAt(nuint index)
    {
        if (index >= _count)
            sl_array_bounds_fail(index, _count);

        for (nuint i = index; i + 1u < _count; i++)
            _items[i] = _items[i + 1u];

        _count--;
        _items[_count] = default(T);
    }

    /// Removes `count` items from `index` onwards.
    ///
    /// @see List.RemoveAt
    public void RemoveRange(nuint index, nuint count)
    {
        if (count == 0)
            return;
        if (index > _count || count > _count - index)
            sl_array_bounds_fail(RangeEnd(index, count), _count);

        for (nuint i = index; i + count < _count; i++)
            _items[i] = _items[i + count];

        for (nuint i = _count - count; i < _count; i++)
            _items[i] = default(T);
        _count = _count - count;
    }

    /// Removes every item the predicate accepts, and answers how many went.
    ///
    /// One pass that compacts in place, so removing half a list costs one
    /// traversal rather than one shuffle per removal.
    public nuint RemoveAll(Predicate<T> matches)
    {
        nuint kept = 0;
        for (nuint i = 0; i < _count; i++)
        {
            if (!matches(_items[i]))
            {
                _items[kept] = _items[i];
                kept++;
            }
        }

        nuint removed = _count - kept;
        for (nuint i = kept; i < _count; i++)
            _items[i] = default(T);
        _count = kept;
        return removed;
    }

    /// Reverses the list in place.
    public void Reverse()
    {
        for (nuint i = 0; i < _count / 2u; i++)
        {
            var swap = _items[i];
            _items[i] = _items[_count - 1u - i];
            _items[_count - 1u - i] = swap;
        }
    }

    /// The items as a new array, which the caller owns.
    ///
    /// @see List.CopyTo
    public T[] ToArray()
    {
        var answer = new T[_count];
        for (nuint i = 0; i < _count; i++)
            answer[i] = _items[i];
        return answer;
    }

    /// Copies the items into `into`, starting at `at`.
    ///
    /// @see List.ToArray
    public void CopyTo(T[] into, nuint at)
    {
        if (at > into.Length || _count > into.Length - at)
            sl_array_bounds_fail(RangeEnd(at, _count), into.Length);
        for (nuint i = 0; i < _count; i++)
            into[at + i] = _items[i];
    }

    /// A new list holding `count` items from `index` onwards.
    ///
    /// @see List.Slice
    public List<T> GetRange(nuint index, nuint count)
    {
        if (index > _count || count > _count - index)
            sl_array_bounds_fail(RangeEnd(index, count), _count);

        var answer = new List<T>(count);
        for (nuint i = 0; i < count; i++)
            answer.Add(_items[index + i]);
        return answer;
    }

    /// The first item the predicate accepts, or `default(T)` when there is
    /// none -- which is `null` for a reference type, as it is in .NET.
    ///
    /// @see List.FindIndex
    /// @seealso List.FindLast
    public T Find(Predicate<T> matches)
    {
        for (nuint i = 0; i < _count; i++)
        {
            if (matches(_items[i]))
                return _items[i];
        }
        return default(T);
    }

    /// The last item the predicate accepts, or `default(T)`.
    ///
    /// @see List.Find
    public T FindLast(Predicate<T> matches)
    {
        for (nuint i = _count; i > 0u; i--)
        {
            if (matches(_items[i - 1u]))
                return _items[i - 1u];
        }
        return default(T);
    }

    /// Every item the predicate accepts, in order.
    ///
    /// @see List.Find
    public List<T> FindAll(Predicate<T> matches)
    {
        var answer = new List<T>();
        for (nuint i = 0; i < _count; i++)
        {
            if (matches(_items[i]))
                answer.Add(_items[i]);
        }
        return answer;
    }

    /// Where the first item the predicate accepts is, or `None`.
    ///
    /// **An `Optional<nuint>`, where .NET answers -1.** The sentinel is the
    /// thing `Optional<T>` exists to retire, `IndexOf` below already answers
    /// this way, and an index that is a `nuint` cannot hold -1 at all. This is
    /// the one place the shape deliberately departs from C#, and it departs
    /// because C#'s shape is a workaround for a type it does not have.
    ///
    /// @see List.FindLastIndex
    /// @seealso Collections.IndexOf
    public Optional<nuint> FindIndex(Predicate<T> matches)
    {
        for (nuint i = 0; i < _count; i++)
        {
            if (matches(_items[i]))
                return Some(i);
        }
        return None;
    }

    /// Where the last item the predicate accepts is, or `None`.
    ///
    /// @see List.FindIndex
    public Optional<nuint> FindLastIndex(Predicate<T> matches)
    {
        for (nuint i = _count; i > 0u; i--)
        {
            if (matches(_items[i - 1u]))
                return Some(i - 1u);
        }
        return None;
    }

    /// Whether any item is accepted by the predicate.
    ///
    /// @see List.TrueForAll
    public bool Exists(Predicate<T> matches) => FindIndex(matches).HasValue;

    /// Whether every item is.
    ///
    /// @see List.Exists
    public bool TrueForAll(Predicate<T> matches)
    {
        for (nuint i = 0; i < _count; i++)
        {
            if (!matches(_items[i]))
                return false;
        }
        return true;
    }

    /// Runs `action` over each item, in order.
    ///
    /// The list is read as it goes, so an action that adds to it is a loop
    /// that does not end. .NET throws for this; there is nothing to throw
    /// here, and saying so is the whole of what can be done about it.
    public void ForEach(Action<T> action)
    {
        for (nuint i = 0; i < _count; i++)
        {
            action(_items[i]);
        }
    }

    /// Makes sure there is room for `capacity` items, and answers the capacity
    /// afterwards. Never shrinks.
    ///
    /// @see List.TrimExcess
    /// @seealso List.Capacity
    public nuint EnsureCapacity(nuint capacity)
    {
        if (capacity > _items.Length)
            ResizeStorage(capacity);
        return _items.Length;
    }

    /// Gives back the room past `Count`.
    ///
    /// @see List.EnsureCapacity
    public void TrimExcess()
    {
        if (_count < _items.Length)
            ResizeStorage(_count < 1u ? 1u : _count);
    }

    /// `count` items from `index`, as a new list. .NET's name for `GetRange`
    /// since ranges arrived, and the two are the same call.
    ///
    /// @see List.GetRange
    public List<T> Slice(nuint index, nuint count) => GetRange(index, count);

    /// Inserts every item of another sequence at `index`, in its order.
    ///
    /// Collected first, for the reason `AddRange` gives, and then moved into
    /// place with one shift of the tail rather than one per item.
    ///
    /// @see List.AddRange
    public void InsertRange(nuint index, IEnumerable<T> items)
    {
        if (index > _count)
            sl_array_bounds_fail(index, _count);

        var added = new List<T>();
        foreach (var item in items)
        {
            added.Add(item);
        }

        nuint count = added._count;
        if (count == 0u)
            return;
        // Doubling, as `Add` grows, so a loop of small ranges stays linear.
        nuint needed = _count + count;
        if (needed > _items.Length)
            ResizeStorage(needed > _items.Length * 2u ? needed : _items.Length * 2u);

        // Backwards, so a slot is read before the copy that overwrites it.
        for (nuint i = _count; i > index; i--)
            _items[i - 1u + count] = _items[i - 1u];
        for (nuint i = 0u; i < count; i++)
            _items[index + i] = added._items[i];
        _count = _count + count;
    }

    /// This list seen as something that cannot be changed through it.
    ///
    /// **The same object, not a copy.** .NET answers a `ReadOnlyCollection<T>`
    /// wrapper for the same reason this answers an interface: what it buys is a
    /// signature that says "I will not write to this", and neither stops the
    /// owner writing to it meanwhile.
    public IReadOnlyList<T> AsReadOnly() => this;

    /// A cursor over this list, for `foreach` and for passing it on as a
    /// sequence. The cursor reads the list as it goes rather than taking a
    /// copy, so changing the list during a walk changes what the walk sees.
    ///
    /// @see ListEnumerator
    public IEnumerator<T> GetEnumerator() => new ListEnumerator<T>(this);

    /// Drops every item. The backing array is replaced rather than merely
    /// forgotten, so any references it held are released now instead of
    /// lingering until the slots are overwritten.
    public void Clear()
    {
        _items = new T[4];
        _count = 0;
    }

    void GrowStorage() => ResizeStorage(_items.Length * 2u);

    void ResizeStorage(nuint room)
    {
        var bigger = new T[room];
        for (nuint i = 0; i < _count; i++)
            bigger[i] = _items[i];
        _items = bigger;
    }
}

/// The last position a range asks for.
///
/// `index + count - 1` wraps when `count` is near the top of `nuint`, and a
/// wrapped sum names a position inside the list -- which is how a range that
/// runs off the end got past a guard that added the two. This saturates
/// instead, and is what the failure reports: a range that overruns is a fault
/// in its length, and naming its start says the wrong thing.
nuint RangeEnd(nuint index, nuint count)
{
    if (count == 0u)
        return index;
    if (count - 1u > MaxNUInt - index)
        return MaxNUInt;
    return index + count - 1u;
}
