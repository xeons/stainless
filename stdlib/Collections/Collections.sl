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

// ---------------------------------------------------------------- algorithms

/// The largest item, by its own ordering. The list must not be empty.
///
/// @typeparam T  the element type, which must order itself
/// @see Collections.Min
public T Max<T>(IReadOnlyList<T> items) where T : IComparable<T>
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
///
/// @typeparam T  the element type, which must order itself
/// @see Collections.Max
public T Min<T>(IReadOnlyList<T> items) where T : IComparable<T>
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
///
/// @typeparam T  the element type, which must answer whether it equals another
/// @see Collections.Contains
/// @seealso OrderedDictionary.IndexOf
public Optional<nuint> IndexOf<T>(IReadOnlyList<T> items, T wanted) where T : IEquatable<T>
{
    for (nuint i = 0; i < items.Count; i++)
    {
        if (items[i].Equals(wanted))
            return Some(i);
    }
    return None;
}

/// Whether `wanted` is in the list at all. `List<T>.Contains` in .NET, and a
/// free function here for the reason `IndexOf` is.
///
/// @typeparam T  the element type, which must answer whether it equals another
/// @see Collections.IndexOf
public bool Contains<T>(IReadOnlyList<T> items, T wanted) where T : IEquatable<T>
{
    return IndexOf(items, wanted).HasValue;
}

/// Where the *last* item equal to `wanted` is, if it is there at all.
///
/// @typeparam T  the element type, which must answer whether it equals another
/// @see Collections.IndexOf
public Optional<nuint> LastIndexOf<T>(IReadOnlyList<T> items, T wanted)
    where T : IEquatable<T>
{
    for (nuint i = items.Count; i > 0u; i--)
    {
        if (items[i - 1u].Equals(wanted))
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
///
/// @typeparam T  the element type, which must answer whether it equals another
/// @see Collections.RemoveWhere
/// @seealso List.RemoveAt
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
///
/// @typeparam T  the element type; the predicate does the deciding, so nothing
///               is asked of it
/// @see Collections.RemoveFirst
/// @seealso List.RemoveAll
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
///
/// @typeparam T  the element type, which must order itself
/// @see Collections.BinarySearch
/// @seealso Collections.FindLowerBound
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
        SortRunByInsertion(items, start, stop);
    }

    for (nuint width = SmallRun; width < items.Length; width *= 2u)
    {
        for (nuint low = 0u; low + width < items.Length; low += width * 2u)
        {
            nuint middle = low + width;
            nuint high = middle + width;
            if (high > items.Length)
                high = items.Length;
            MergeRuns(items, scratch, low, middle, high);
        }
    }
}

/// Orders `[start, stop)` by insertion, which is what a short run wants.
void SortRunByInsertion<T>(T[:] items, nuint start, nuint stop) where T : IComparable<T>
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
void MergeRuns<T>(T[:] items, T[:] scratch, nuint low, nuint middle, nuint high)
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
///
/// @typeparam T  the element type; the comparer orders it, so nothing is asked
///               of it
/// @see Collections.OrderBy
public void Sort<T>(T[:] items, Comparison<T> order)
{
    if (items.Length < 2u)
        return;

    var scratch = new T[items.Length];

    for (nuint start = 0u; start < items.Length; start += SmallRun)
    {
        nuint stop = start + SmallRun;
        if (stop > items.Length)
            stop = items.Length;
        SortRunByInsertion(items, start, stop, order);
    }

    for (nuint width = SmallRun; width < items.Length; width *= 2u)
    {
        for (nuint low = 0u; low + width < items.Length; low += width * 2u)
        {
            nuint middle = low + width;
            nuint high = middle + width;
            if (high > items.Length)
                high = items.Length;
            MergeRuns(items, scratch, low, middle, high, order);
        }
    }
}

void SortRunByInsertion<T>(T[:] items, nuint start, nuint stop, Comparison<T> order)
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

void MergeRuns<T>(T[:] items, T[:] scratch, nuint low, nuint middle, nuint high,
                Comparison<T> order)
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
/// there.
///
/// Two functions rather than one with a found flag, because the language has
/// no `out` and a caller that wants the insertion point usually does not want
/// the search, and the other way round.
///
/// @typeparam T  the element type, which must order itself
/// @see Collections.FindLowerBound
/// @seealso Collections.Sort
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
///
/// @typeparam T  the element type, which must order itself
/// @see Collections.BinarySearch
public nuint FindLowerBound<T>(T[:] items, T wanted) where T : IComparable<T>
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
///
/// @typeparam T  the element type; nothing is asked of it
/// @see List.Reverse
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
///
/// @typeparam T  the element type, which must order itself
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
///
/// @typeparam T  the element type; the comparer orders it, so nothing is asked
///               of it
public void Sort<T>(IList<T> items, Comparison<T> order)
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
