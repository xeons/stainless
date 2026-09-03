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

/// Orders a list in place, smallest first. Insertion sort: short and stable,
/// which matters more than asymptotics until there is a reason to measure.
public void Sort<T>(IList<T> items) where T : IComparable<T> {
    for (nuint i = 1; i < items.Count(); i = i + 1) {
        var current = items.At(i);
        var j = i;

        while (j > 0 && items.At(j - 1).CompareTo(current) > 0) {
            items.Set(j, items.At(j - 1));
            j = j - 1;
        }

        items.Set(j, current);
    }
}
