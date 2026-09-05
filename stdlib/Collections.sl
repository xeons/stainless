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

// The Stainless standard collections.
//
// Unlike Standard.Text, nothing here needs runtime support: it is ordinary
// Stainless, compiled alongside your program. Generic declarations cost nothing
// until they are instantiated, so importing this module and using none of it
// emits no code at all.
//
// Interfaces are named with a leading I, as in C#.
module Standard.Collections;

/// Aborts with an index and a bound. Shared with the array bounds check, so a
/// list overrun reads the same as an array overrun.
extern "C" void sl_array_bounds_fail(nuint index, nuint length);

// ---------------------------------------------------------------- comparison

public interface IEquatable<T> {
    bool EqualTo(T other);
}

/// Returns a negative number, zero, or a positive number when this value orders
/// before, with, or after `other`.
public interface IComparable<T> {
    int CompareTo(T other);
}

/// A value that can be a key in a hash table.
///
/// Two values that are `EqualTo` each other must return the same `HashCode`;
/// two that are not may still collide, and the table handles it. A type that
/// implements this should implement `IEquatable<T>` as well, since a hash on
/// its own only narrows the search.
public interface IHashable {
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
public interface IEnumerator<T> {
    bool MoveNext();
    T Current();
}

public interface IEnumerable<T> {
    IEnumerator<T> GetEnumerator();
}

/// Walks anything that can be counted and indexed, so one enumerator serves
/// every list rather than each list writing its own.
public class ListEnumerator<T> : IEnumerator<T> {
    IReadOnlyList<T> source;
    nuint next;

    public ListEnumerator(IReadOnlyList<T> items) {
        source = items;
        next = 0;
    }

    public bool MoveNext() {
        if (next >= source.Count()) { return false; }
        next = next + 1;
        return true;
    }

    public T Current() { return source.At(next - 1); }
}

// ------------------------------------------------------------------- lists

public interface IReadOnlyList<T> {
    nuint Count();
    T At(nuint index);
}

/// Everything a read-only list offers, plus mutation. A value of this type can
/// be passed anywhere an IReadOnlyList is wanted, at no cost: an interface
/// reference is a plain pointer, and the object carries a table for both.
public interface IList<T> : IReadOnlyList<T> {
    void Add(T item);
    void Set(nuint index, T item);
    void Clear();
}

/// A growable list backed by a single array, doubling when it fills.
public class List<T> : IList<T>, IEnumerable<T> {
    T[] items;
    nuint count;

    public List() {
        items = new T[4];
        count = 0;
    }

    public nuint Count() { return count; }

    public bool IsEmpty() { return count == 0; }

    /// The number of items this list can hold before it must grow again.
    public nuint Capacity() { return items.Length; }

    public T At(nuint index) {
        if (index >= count) { sl_array_bounds_fail(index, count); }
        return items[index];
    }

    public void Add(T item) {
        if (count == items.Length) { Grow(); }
        items[count] = item;
        count = count + 1;
    }

    public void Set(nuint index, T item) {
        if (index >= count) { sl_array_bounds_fail(index, count); }
        items[index] = item;
    }

    public IEnumerator<T> GetEnumerator() { return new ListEnumerator<T>(this); }

    /// Drops every item. The backing array is replaced rather than merely
    /// forgotten, so any references it held are released now instead of
    /// lingering until the slots are overwritten.
    public void Clear() {
        items = new T[4];
        count = 0;
    }

    void Grow() {
        var bigger = new T[items.Length * 2];
        for (nuint i = 0; i < count; i = i + 1) { bigger[i] = items[i]; }
        items = bigger;
    }
}

// ---------------------------------------------------------------- algorithms

/// The largest item, by its own ordering. The list must not be empty.
public T Largest<T>(IReadOnlyList<T> items) where T : IComparable<T> {
    if (items.Count() == 0) { sl_array_bounds_fail(0, 0); }

    var best = items.At(0);
    for (nuint i = 1; i < items.Count(); i = i + 1) {
        if (items.At(i).CompareTo(best) > 0) { best = items.At(i); }
    }
    return best;
}

/// The smallest item, by its own ordering. The list must not be empty.
public T Smallest<T>(IReadOnlyList<T> items) where T : IComparable<T> {
    if (items.Count() == 0) { sl_array_bounds_fail(0, 0); }

    var best = items.At(0);
    for (nuint i = 1; i < items.Count(); i = i + 1) {
        if (items.At(i).CompareTo(best) < 0) { best = items.At(i); }
    }
    return best;
}

/// The index of the first item equal to `wanted`, or the list's length when
/// there is none.
public nuint IndexOf<T>(IReadOnlyList<T> items, T wanted) where T : IEquatable<T> {
    for (nuint i = 0; i < items.Count(); i = i + 1) {
        if (items.At(i).EqualTo(wanted)) { return i; }
    }
    return items.Count();
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
public void Sort<T>(T[:] items) where T : IComparable<T> {
    if (items.Length < 2u) { return; }

    var scratch = new T[items.Length];

    for (nuint start = 0u; start < items.Length; start += SmallRun) {
        nuint stop = start + SmallRun;
        if (stop > items.Length) { stop = items.Length; }
        InsertionSort(items, start, stop);
    }

    for (nuint width = SmallRun; width < items.Length; width *= 2u) {
        for (nuint low = 0u; low + width < items.Length; low += width * 2u) {
            nuint middle = low + width;
            nuint high = middle + width;
            if (high > items.Length) { high = items.Length; }
            Merge(items, scratch, low, middle, high);
        }
    }
}

/// Orders `[start, stop)` by insertion, which is what a short run wants.
void InsertionSort<T>(T[:] items, nuint start, nuint stop) where T : IComparable<T> {
    for (nuint i = start + 1u; i < stop; i += 1u) {
        var current = items[i];
        var j = i;

        while (j > start && items[j - 1u].CompareTo(current) > 0) {
            items[j] = items[j - 1u];
            j -= 1u;
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
        where T : IComparable<T> {
    nuint left = low;
    nuint right = middle;

    for (nuint at = low; at < high; at += 1u) {
        if (left < middle && (right >= high || items[left].CompareTo(items[right]) <= 0)) {
            scratch[at] = items[left];
            left += 1u;
        } else {
            scratch[at] = items[right];
            right += 1u;
        }
    }

    for (nuint at = low; at < high; at += 1u) { items[at] = scratch[at]; }
}

/// The same, ordered by a comparer rather than by the type itself.
///
/// This is the overload that sorts descending, sorts by a field, or sorts a
/// type that implements nothing at all:
///
///     Sort(people, (a, b) => a.Age - b.Age);
public void Sort<T>(T[:] items, IComparer<T> order) {
    if (items.Length < 2u) { return; }

    var scratch = new T[items.Length];

    for (nuint start = 0u; start < items.Length; start += SmallRun) {
        nuint stop = start + SmallRun;
        if (stop > items.Length) { stop = items.Length; }
        InsertionSortBy(items, start, stop, order);
    }

    for (nuint width = SmallRun; width < items.Length; width *= 2u) {
        for (nuint low = 0u; low + width < items.Length; low += width * 2u) {
            nuint middle = low + width;
            nuint high = middle + width;
            if (high > items.Length) { high = items.Length; }
            MergeBy(items, scratch, low, middle, high, order);
        }
    }
}

void InsertionSortBy<T>(T[:] items, nuint start, nuint stop, IComparer<T> order) {
    for (nuint i = start + 1u; i < stop; i += 1u) {
        var current = items[i];
        var j = i;

        while (j > start && order.Compare(items[j - 1u], current) > 0) {
            items[j] = items[j - 1u];
            j -= 1u;
        }

        items[j] = current;
    }
}

void MergeBy<T>(T[:] items, T[:] scratch, nuint low, nuint middle, nuint high,
                IComparer<T> order) {
    nuint left = low;
    nuint right = middle;

    for (nuint at = low; at < high; at += 1u) {
        if (left < middle && (right >= high || order.Compare(items[left], items[right]) <= 0)) {
            scratch[at] = items[left];
            left += 1u;
        } else {
            scratch[at] = items[right];
            right += 1u;
        }
    }

    for (nuint at = low; at < high; at += 1u) { items[at] = scratch[at]; }
}

/// Where `wanted` is in an already-ordered slice, or the length when it is not
/// there -- the same convention `IndexOf` follows, so the two read alike.
///
/// Two functions rather than one with a found flag, because the language has
/// no `out` and a caller that wants the insertion point usually does not want
/// the search, and the other way round.
public nuint BinarySearch<T>(T[:] items, T wanted) where T : IComparable<T> {
    nuint low = 0u;
    nuint high = items.Length;

    while (low < high) {
        nuint middle = low + (high - low) / 2u;
        int order = items[middle].CompareTo(wanted);

        if (order == 0) { return middle; }
        if (order < 0) { low = middle + 1u; } else { high = middle; }
    }

    return items.Length;
}

/// The first index at which `wanted` could be inserted and leave the slice
/// ordered: the length when it belongs at the end, and the index of the first
/// equal element when there is one.
public nuint LowerBound<T>(T[:] items, T wanted) where T : IComparable<T> {
    nuint low = 0u;
    nuint high = items.Length;

    while (low < high) {
        nuint middle = low + (high - low) / 2u;
        if (items[middle].CompareTo(wanted) < 0) { low = middle + 1u; } else { high = middle; }
    }

    return low;
}

/// Reverses part of an array in place.
public void Reverse<T>(T[:] items) {
    if (items.Length < 2) { return; }

    nuint low = 0;
    nuint high = items.Length - 1;

    while (low < high) {
        var swap = items[low];
        items[low] = items[high];
        items[high] = swap;
        low = low + 1;
        high = high - 1;
    }
}

/// Orders a list in place, smallest first.
///
/// Copied into an array, sorted there and copied back, rather than merge-sorted
/// through the interface. Every `At` and `Set` on an `IList<T>` is a virtual
/// call, and a sort makes O(n log n) of them; two linear passes to escape that
/// is the cheaper trade, and it gets the array version's stability for free.
public void Sort<T>(IList<T> items) where T : IComparable<T> {
    nuint count = items.Count();
    if (count < 2u) { return; }

    var flat = new T[count];
    for (nuint i = 0u; i < count; i += 1u) { flat[i] = items.At(i); }

    Sort(flat);

    for (nuint i = 0u; i < count; i += 1u) { items.Set(i, flat[i]); }
}

/// The same, ordered by a comparer.
public void Sort<T>(IList<T> items, IComparer<T> order) {
    nuint count = items.Count();
    if (count < 2u) { return; }

    var flat = new T[count];
    for (nuint i = 0u; i < count; i += 1u) { flat[i] = items.At(i); }

    Sort(flat, order);

    for (nuint i = 0u; i < count; i += 1u) { items.Set(i, flat[i]); }
}
