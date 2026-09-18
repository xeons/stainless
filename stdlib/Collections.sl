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

/// The Stainless standard collections.
///
/// Unlike Standard.Text, nothing here needs runtime support: it is ordinary
/// Stainless, compiled alongside your program. Generic declarations cost nothing
/// until they are instantiated, so importing this module and using none of it
/// emits no code at all.
///
/// Interfaces are named with a leading I, as in C#.
module Standard.Collections;

/// Aborts with an index and a bound. Shared with the array bounds check, so a
/// list overrun reads the same as an array overrun.
extern "C" void sl_array_bounds_fail(nuint index, nuint length);

// ---------------------------------------------------------------- comparison

/// A value that can be asked whether it equals another of its type.
///
/// `EqualTo` has to be an equivalence -- a value equals itself, equality runs
/// both ways, and two things equal to a third are equal to each other --
/// because the containers assume all three and none of them checks. A type
/// used as a dictionary key implements `IHashable` alongside this, and the two
/// must agree: equal values must hash alike.
public interface IEquatable<T>
{
    /// True when this value and `other` are the same value. Implementations
    /// should answer without allocating; this runs once per probe.
    bool EqualTo(T other);
}

/// Returns a negative number, zero, or a positive number when this value orders
/// before, with, or after `other`.
public interface IComparable<T>
{
    /// Negative when this orders before `other`, zero when they order
    /// together, positive when after. The sign is all that is read -- the
    /// magnitude means nothing, so returning a subtraction is fine as long as
    /// it cannot overflow.
    int CompareTo(T other);
}

/// A value that can be a key in a hash table.
///
/// Two values that are `EqualTo` each other must return the same `HashCode`;
/// two that are not may still collide, and the table handles it. A type that
/// implements this should implement `IEquatable<T>` as well, since a hash on
/// its own only narrows the search.
public interface IHashable
{
    /// A number standing in for this value. The same value must give the same
    /// number for as long as it is a key in a table, which means hashing only
    /// the parts a key is not going to have changed under it.
    nuint HashCode();
}



// **A primitive, an enum and a String implement all three without saying so.**
// None of them can carry a declaration -- a primitive is not a class, an enum
// is its integer, and String belongs to the runtime -- but they are exactly the
// types people sort by and use as keys. The compiler recognises `CompareTo`,
// `EqualTo` and `HashCode` on them and lowers each to a comparison or a runtime
// call, so `Sort(numbers)` works on a `List<int>` and `Dictionary<String, V>`
// needs nothing extra.

// -------------------------------------------------------------- enumeration

/// A cursor over a sequence. `MoveNext` advances and reports whether there was
/// anything to advance to; `Current` returns what it landed on.
///
/// `foreach` does not require this interface -- it looks for the methods by
/// name, so any type with a `GetEnumerator()` can be iterated. Naming the shape
/// is still worth doing, because it lets a sequence be passed around.
public interface IEnumerator<T>
{
    /// Advances to the next item and reports whether there was one. Must be
    /// called before the first `Current`: a fresh enumerator sits before the
    /// start rather than on the first item.
    bool MoveNext();

    /// What the last `MoveNext` landed on. Calling this before the first
    /// `MoveNext`, or after one that answered false, is a mistake the
    /// enumerator is not required to catch.
    T Current { get; }
}

/// Something that can be walked from the start, once per enumerator.
///
/// `foreach` does not need this interface -- it finds `GetEnumerator` by name
/// -- so implementing it is about being passable as a sequence, not about
/// being iterable.
public interface IEnumerable<T>
{
    /// A fresh cursor positioned before the first item. Each call gives an
    /// independent one, so a sequence can be walked twice; what is not
    /// promised is that the two walks see the same items, since a collection
    /// changed in between will say something different.
    IEnumerator<T> GetEnumerator();
}

/// Walks anything that can be counted and indexed, so one enumerator serves
/// every list rather than each list writing its own.
public class ListEnumerator<T> : IEnumerator<T>
{
    IReadOnlyList<T> _source;
    nuint _next;

    /// A cursor over `items`, positioned before the first one.
    ///
    /// The list is held by reference rather than copied, so adding to it or
    /// removing from it while this cursor is live changes what the cursor
    /// walks. The count is read on every `MoveNext`, so a removal can end the
    /// walk early and an insertion can extend it.
    public ListEnumerator(IReadOnlyList<T> items)
    {
        _source = items;
        _next = 0;
    }

    /// Advances, answering false at the end.
    public bool MoveNext()
    {
        if (_next >= _source.Count)
            return false;
        _next++;
        return true;
    }

    /// The item the last `MoveNext` landed on.
    public T Current => _source[_next - 1];
}

// ------------------------------------------------------------------- lists

/// A sequence that knows its length and can be indexed, and cannot be changed
/// through this reference.
///
/// Read-only is about what this interface offers, not about the object: the
/// list behind it may well be a `List<T>` that someone else is still adding
/// to. Take this as a parameter type where a function reads and does not
/// write, which says so in the signature.
public interface IReadOnlyList<T>
{
    /// How many items there are.
    nuint Count { get; }

    /// Whether there are none.
    bool IsEmpty { get; }

    /// The item at `index`, counting from zero. An index at or past `Count`
    /// aborts with the same message an array overrun gives.
    T this[nuint index] { get; }
}

/// Everything a read-only list offers, plus mutation. A value of this type can
/// be passed anywhere an IReadOnlyList is wanted, at no cost: an interface
/// reference is a plain pointer, and the object carries a table for both.
public interface IList<T> : IReadOnlyList<T>
{
    /// The item at `index`, readable and writable. Redeclared because an
    /// interface cannot widen an inherited member from get-only to get-set.
    T this[nuint index] { get; set; }

    /// Appends to the end.
    void Add(T item);

    /// Removes the item at `index`, closing the gap.
    void RemoveAt(nuint index);

    /// Drops every item, leaving a length of zero.
    void Clear();
}

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
///   methods. `Contains`, `IndexOf`, `Remove`, `Sort` and `BinarySearch` all
///   need `T : IEquatable<T>` or `IComparable<T>`, and this class constrains
///   `T` not at all -- a `List<Control>` has to stay possible. A class cannot
///   demand of one method's type parameter what it does not demand of every
///   element. .NET reaches them through `EqualityComparer<T>.Default`, which is
///   a runtime lookup this language has no equivalent of.
///
/// The members taking a predicate need no constraint, so those are methods,
/// exactly as in .NET.
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
            Resize(value < 1u ? 1u : value);
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
    public void Add(T item)
    {
        if (_count == _items.Length)
            Grow();
        _items[_count] = item;
        _count++;
    }

    /// Appends every item of another sequence, in its order.
    public void AddRange(IEnumerable<T> items)
    {
        foreach (var item in items)
        {
            Add(item);
        }
    }

    /// Inserts at a position, moving everything after it up one.
    ///
    /// `index == Count` appends, which is what makes a loop that inserts in
    /// order need no special case at the end.
    public void Insert(nuint index, T item)
    {
        if (index > _count)
            sl_array_bounds_fail(index, _count);
        if (_count == _items.Length)
            Grow();

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
    public void RemoveRange(nuint index, nuint count)
    {
        if (count == 0)
            return;
        if (index + count > _count)
            sl_array_bounds_fail(index, _count);

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
    public T[] ToArray()
    {
        var answer = new T[_count];
        for (nuint i = 0; i < _count; i++)
            answer[i] = _items[i];
        return answer;
    }

    /// Copies the items into `into`, starting at `at`.
    public void CopyTo(T[] into, nuint at)
    {
        if (at + _count > into.Length)
            sl_array_bounds_fail(at, into.Length);
        for (nuint i = 0; i < _count; i++)
            into[at + i] = _items[i];
    }

    /// A new list holding `count` items from `index` onwards.
    public List<T> GetRange(nuint index, nuint count)
    {
        if (index + count > _count)
            sl_array_bounds_fail(index, _count);

        var answer = new List<T>(count);
        for (nuint i = 0; i < count; i++)
            answer.Add(_items[index + i]);
        return answer;
    }

    /// The first item the predicate accepts, or `default(T)` when there is
    /// none -- which is `null` for a reference type, as it is in .NET.
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
    public bool Exists(Predicate<T> matches) => FindIndex(matches).HasValue;

    /// Whether every item is.
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
    public nuint EnsureCapacity(nuint capacity)
    {
        if (capacity > _items.Length)
            Resize(capacity);
        return _items.Length;
    }

    /// Gives back the room past `Count`.
    public void TrimExcess()
    {
        if (_count < _items.Length)
            Resize(_count < 1u ? 1u : _count);
    }

    /// `count` items from `index`, as a new list. .NET's name for `GetRange`
    /// since ranges arrived, and the two are the same call.
    public List<T> Slice(nuint index, nuint count) => GetRange(index, count);

    /// Inserts every item of another sequence at `index`, in its order.
    public void InsertRange(nuint index, IEnumerable<T> items)
    {
        nuint at = index;
        foreach (var item in items)
        {
            Insert(at, item);
            at++;
        }
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
    public IEnumerator<T> GetEnumerator() => new ListEnumerator<T>(this);

    /// Drops every item. The backing array is replaced rather than merely
    /// forgotten, so any references it held are released now instead of
    /// lingering until the slots are overwritten.
    public void Clear()
    {
        _items = new T[4];
        _count = 0;
    }

    void Grow() => Resize(_items.Length * 2u);

    void Resize(nuint room)
    {
        var bigger = new T[room];
        for (nuint i = 0; i < _count; i++)
            bigger[i] = _items[i];
        _items = bigger;
    }
}

// ---------------------------------------------------------------- algorithms

/// The largest item, by its own ordering. The list must not be empty.
public T Largest<T>(IReadOnlyList<T> items) where T : IComparable<T>
{
    if (items.Count == 0)
        sl_array_bounds_fail(0, 0);

    var best = items[0];
    for (nuint i = 1; i < items.Count; i++)
    {
        if (items[i].CompareTo(best) > 0)
            best = items[i];
    }
    return best;
}

/// The smallest item, by its own ordering. The list must not be empty.
public T Smallest<T>(IReadOnlyList<T> items) where T : IComparable<T>
{
    if (items.Count == 0)
        sl_array_bounds_fail(0, 0);

    var best = items[0];
    for (nuint i = 1; i < items.Count; i++)
    {
        if (items[i].CompareTo(best) < 0)
            best = items[i];
    }
    return best;
}

/// Where the first item equal to `wanted` is, if it is there at all.
///
///     if (IndexOf(names, "beta") is Some at) { names.RemoveAt(at.Value); }
///
/// An `Optional<nuint>` rather than the length standing in for "no": the
/// sentinel is the thing `Optional<T>` was added to retire, and its own
/// documentation names this function as the example. `OrderedDictionary.IndexOf`
/// has always answered this way; now they agree.
public Optional<nuint> IndexOf<T>(IReadOnlyList<T> items, T wanted) where T : IEquatable<T>
{
    for (nuint i = 0; i < items.Count; i++)
    {
        if (items[i].EqualTo(wanted))
            return Some(i);
    }
    return None;
}

/// Whether `wanted` is in the list at all. `List<T>.Contains` in .NET, and a
/// free function here for the reason `IndexOf` is.
public bool Contains<T>(IReadOnlyList<T> items, T wanted) where T : IEquatable<T>
{
    return IndexOf(items, wanted).HasValue;
}

/// Where the *last* item equal to `wanted` is, if it is there at all.
public Optional<nuint> LastIndexOf<T>(IReadOnlyList<T> items, T wanted)
    where T : IEquatable<T>
{
    for (nuint i = items.Count; i > 0u; i--)
    {
        if (items[i - 1u].EqualTo(wanted))
            return Some(i - 1u);
    }
    return None;
}

/// Removes the first item equal to `wanted`, answering whether there was one.
///
/// This is `List<T>.Remove` under another name, and it is a free function
/// rather than a method because it needs `T : IEquatable<T>` and a class
/// cannot constrain one method's type parameter to something the class itself
/// does not demand of every element.
public bool RemoveFirst<T>(List<T> items, T wanted) where T : IEquatable<T>
{
    if (IndexOf(items, wanted) is Some at)
    {
        items.RemoveAt(at.Value);
        return true;
    }
    return false;
}

/// Removes every item the predicate accepts, and answers how many went.
///
///     RemoveWhere(handlers, (h) => h == leaving);
///
/// A predicate rather than a value, which is what makes it work for a `T` that
/// implements nothing -- a `closure` is not `IEquatable`, so a list of
/// callbacks could not be removed from at all before this.
///
/// Walked from the end, so an index already passed cannot move.
public nuint RemoveWhere<T>(List<T> items, Predicate<T> match)
{
    nuint went = 0u;
    nuint i = items.Count;

    while (i > 0u)
    {
        i--;
        if (match(items[i]))
        {
            items.RemoveAt(i);
            went++;
        }
    }

    return went;
}

/// Below this many, a merge is not worth its bookkeeping and insertion sort
/// wins outright. It is also what keeps the merge from recursing to length 1.
const nuint SmallRun = 16u;

/// Orders part of an array in place, smallest first.
///
/// An array converts to a slice of the whole of itself, so `Sort(numbers)`
/// reaches this and `Sort(numbers[2:5])` orders three of them and leaves the
/// rest alone. Nothing is copied either way: a slice is a view.
///
/// **Stable, and O(n log n).** Merge sort, bottom-up, with insertion sort for
/// short runs. Stability is the property worth paying for -- sorting by one
/// key and then another is how a multi-key order gets built, and it only works
/// if the second sort leaves equal elements where the first put them. The
/// price is one scratch array as long as the input; an in-place quicksort
/// would avoid it and would not be stable.
public void Sort<T>(T[:] items) where T : IComparable<T>
{
    if (items.Length < 2u)
        return;

    var scratch = new T[items.Length];

    for (nuint start = 0u; start < items.Length; start += SmallRun)
    {
        nuint stop = start + SmallRun;
        if (stop > items.Length)
            stop = items.Length;
        InsertionSort(items, start, stop);
    }

    for (nuint width = SmallRun; width < items.Length; width *= 2u)
    {
        for (nuint low = 0u; low + width < items.Length; low += width * 2u)
        {
            nuint middle = low + width;
            nuint high = middle + width;
            if (high > items.Length)
                high = items.Length;
            Merge(items, scratch, low, middle, high);
        }
    }
}

/// Orders `[start, stop)` by insertion, which is what a short run wants.
void InsertionSort<T>(T[:] items, nuint start, nuint stop) where T : IComparable<T>
{
    for (nuint i = start + 1u; i < stop; i++)
    {
        var current = items[i];
        var j = i;

        while (j > start && items[j - 1u].CompareTo(current) > 0)
        {
            items[j] = items[j - 1u];
            j--;
        }

        items[j] = current;
    }
}

/// Merges the two ordered halves `[low, middle)` and `[middle, high)`.
///
/// `>` rather than `>=` when choosing the right half is what makes this
/// stable: on a tie the left element goes first, and the left element is the
/// one that was there first.
void Merge<T>(T[:] items, T[:] scratch, nuint low, nuint middle, nuint high)
        where T : IComparable<T>
{
    nuint left = low;
    nuint right = middle;

    for (nuint at = low; at < high; at++)
    {
        if (left < middle && (right >= high || items[left].CompareTo(items[right]) <= 0))
        {
            scratch[at] = items[left];
            left++;
        }
        else
        {
            scratch[at] = items[right];
            right++;
        }
    }

    for (nuint at = low; at < high; at++)
        items[at] = scratch[at];
}

/// The same, ordered by a comparer rather than by the type itself.
///
/// This is the overload that sorts descending, sorts by a field, or sorts a
/// type that implements nothing at all:
///
///     Sort(people, (a, b) => a.Age - b.Age);
public void Sort<T>(T[:] items, Comparer<T> order)
{
    if (items.Length < 2u)
        return;

    var scratch = new T[items.Length];

    for (nuint start = 0u; start < items.Length; start += SmallRun)
    {
        nuint stop = start + SmallRun;
        if (stop > items.Length)
            stop = items.Length;
        InsertionSortBy(items, start, stop, order);
    }

    for (nuint width = SmallRun; width < items.Length; width *= 2u)
    {
        for (nuint low = 0u; low + width < items.Length; low += width * 2u)
        {
            nuint middle = low + width;
            nuint high = middle + width;
            if (high > items.Length)
                high = items.Length;
            MergeBy(items, scratch, low, middle, high, order);
        }
    }
}

void InsertionSortBy<T>(T[:] items, nuint start, nuint stop, Comparer<T> order)
{
    for (nuint i = start + 1u; i < stop; i++)
    {
        var current = items[i];
        var j = i;

        while (j > start && order(items[j - 1u], current) > 0)
        {
            items[j] = items[j - 1u];
            j--;
        }

        items[j] = current;
    }
}

void MergeBy<T>(T[:] items, T[:] scratch, nuint low, nuint middle, nuint high,
                Comparer<T> order)
{
    nuint left = low;
    nuint right = middle;

    for (nuint at = low; at < high; at++)
    {
        if (left < middle && (right >= high || order(items[left], items[right]) <= 0))
        {
            scratch[at] = items[left];
            left++;
        }
        else
        {
            scratch[at] = items[right];
            right++;
        }
    }

    for (nuint at = low; at < high; at++)
        items[at] = scratch[at];
}

/// Where `wanted` is in an already-ordered slice, or the length when it is not
/// there -- the same convention `IndexOf` follows, so the two read alike.
///
/// Two functions rather than one with a found flag, because the language has
/// no `out` and a caller that wants the insertion point usually does not want
/// the search, and the other way round.
public nuint BinarySearch<T>(T[:] items, T wanted) where T : IComparable<T>
{
    nuint low = 0u;
    nuint high = items.Length;

    while (low < high)
    {
        nuint middle = low + (high - low) / 2u;
        int order = items[middle].CompareTo(wanted);

        if (order == 0)
            return middle;
        if (order < 0)
        {
            low = middle + 1u;
        }
        else
        {
            high = middle;
        }
    }

    return items.Length;
}

/// The first index at which `wanted` could be inserted and leave the slice
/// ordered: the length when it belongs at the end, and the index of the first
/// equal element when there is one.
public nuint LowerBound<T>(T[:] items, T wanted) where T : IComparable<T>
{
    nuint low = 0u;
    nuint high = items.Length;

    while (low < high)
    {
        nuint middle = low + (high - low) / 2u;
        if (items[middle].CompareTo(wanted) < 0)
        {
            low = middle + 1u;
        }
        else
        {
            high = middle;
        }
    }

    return low;
}

/// Reverses part of an array in place.
public void Reverse<T>(T[:] items)
{
    if (items.Length < 2)
        return;

    nuint low = 0;
    nuint high = items.Length - 1;

    while (low < high)
    {
        var swap = items[low];
        items[low] = items[high];
        items[high] = swap;
        low++;
        high--;
    }
}

/// Orders a list in place, smallest first.
///
/// Copied into an array, sorted there and copied back, rather than merge-sorted
/// through the interface. Every `At` and `Set` on an `IList<T>` is a virtual
/// call, and a sort makes O(n log n) of them; two linear passes to escape that
/// is the cheaper trade, and it gets the array version's stability for free.
public void Sort<T>(IList<T> items) where T : IComparable<T>
{
    nuint count = items.Count;
    if (count < 2u)
        return;

    var flat = new T[count];
    for (nuint i = 0u; i < count; i++)
        flat[i] = items[i];

    Sort(flat);

    for (nuint i = 0u; i < count; i++)
        items[i] = flat[i];
}

/// The same, ordered by a comparer.
public void Sort<T>(IList<T> items, Comparer<T> order)
{
    nuint count = items.Count;
    if (count < 2u)
        return;

    var flat = new T[count];
    for (nuint i = 0u; i < count; i++)
        flat[i] = items[i];

    Sort(flat, order);

    for (nuint i = 0u; i < count; i++)
        items[i] = flat[i];
}

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
    public TKey KeyAt(nuint index) => _keys[index];

    /// The value at a position, in insertion order.
    public TValue ValueAt(nuint index) => _values[index];

    /// Where a key is, or `None`.
    ///
    /// The one lookup a caller needs: asking whether a key is there and then
    /// asking for its value walks the collection twice. An `Optional` rather
    /// than a sentinel, because a position that means "no position" is a rule
    /// every caller has to know and none can be made to.
    public Optional<nuint> IndexOf(TKey key)
    {
        for (nuint i = 0u; i < _keys.Count; i++)
        {
            if (_keys[i].EqualTo(key))
                return Some(i);
        }
        return None;
    }

    /// Whether the key is there at all. A scan, like everything else here, so
    /// `IndexOf` once beats `Has` followed by a lookup.
    public bool Has(TKey key) => IndexOf(key).HasValue;

    /// Appends, without looking for the key first.
    ///
    /// A repeated key is kept rather than replaced, because a document that
    /// contains one said so and dropping either half would be this collection
    /// deciding what the document meant. `Set` is the one that replaces.
    public void Add(TKey key, TValue value)
    {
        _keys.Add(key);
        _values.Add(value);
    }

    /// Replaces the value of a key, or appends it. A replaced key keeps the
    /// position it had, which is the point of the collection.
    public void Set(TKey key, TValue value)
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
    public TValue Find(TKey key, TValue fallback)
    {
        if (IndexOf(key) is Some at)
            return _values[at.Value];
        return fallback;
    }

    /// Removes the first entry with that key, closing the gap. Answers whether
    /// there was one.
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
