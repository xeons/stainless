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

module Standard;

import Standard.Collections;

/// Making, copying, searching and ordering arrays. C#'s `System.Array`.
///
///     String[] names = Array.Create(count, (i) => $"item {i}");
///     int[] zeros = Array.Repeat(0, 16);
///     Array.Sort(names);
///
/// `new T[n]` starts every element as the zero of `T`, and a `T` holding a
/// reference that is never null has no zero (section 2.16). `Create` and
/// `Repeat` are what such an array is made with instead; an array literal,
/// `[a, b, c]`, is the other way, and a `List<T>` and its `ToArray` the way for
/// a count not known in advance.
///
/// **Where .NET differs.** Indices and counts are `nuint`. A search answers
/// with an `Optional` rather than -1, and `BinarySearch` rather than a negative
/// complement. `Sort` is stable. A range that runs past the array aborts, as an
/// index out of range does. `Clear` and the growing `Resize` need a `T` with a
/// zero value, and are absent for any other.
///
/// Most of these are the span functions of `Standard.Collections` under
/// .NET's names: an array converts to a span, so `Sort(numbers)` and
/// `Array.Sort(numbers)` are the same call.
public static class Array
{
    // ------------------------------------------------------------ making

    /// `count` elements, the element at `i` being `make(i)`, called in order
    /// from zero. No element is ever seen before it has its value.
    ///
    /// @param count  how many elements
    /// @param make   the element at an index
    /// @typeparam T  the element type; nothing is asked of it
    /// @returns the array
    public static T[] Create<T>(nuint count, Func<nuint, T> make) => Create<T>(count, make);

    /// `count` copies of `value`.
    ///
    /// @param value  what each element is
    /// @param count  how many elements
    /// @typeparam T  the element type; nothing is asked of it
    /// @returns the array
    public static T[] Repeat<T>(T value, nuint count) => Create<T>(count, (i) => value);

    /// An array of no elements. A new one each call: there is no per-type
    /// static to cache it in, and it costs one small allocation.
    ///
    /// @typeparam T  the element type; nothing is asked of it
    public static T[] Empty<T>() => new T[0u];

    /// The array as a view that cannot be written through. .NET answers with a
    /// `ReadOnlyCollection<T>`; a `ReadOnlySpan<T>` holds the array it views,
    /// so it may be stored and returned the same way.
    ///
    /// @param array  the array to view
    /// @typeparam T  the element type; nothing is asked of it
    public static ReadOnlySpan<T> AsReadOnly<T>(T[] array) => array;

    /// A new array of each element of `array` passed through `converter`.
    ///
    /// @param array      the elements to convert
    /// @param converter  what each element becomes
    /// @typeparam TInput   the element type of `array`
    /// @typeparam TOutput  the element type of the result
    /// @returns the array, as long as `array`
    public static TOutput[] ConvertAll<TInput, TOutput>(TInput[] array,
        Func<TInput, TOutput> converter)
        => Create<TOutput>(array.Length, (i) => converter(array[i]));

    /// Gives `array` a new length, keeping the elements that fit. The elements
    /// past the old length are the zero of `T`. The same length leaves the
    /// array as it is; any other puts a new array in `array`, and whoever holds
    /// the old one still holds it unchanged.
    ///
    /// @param array    the array, replaced by the resized one
    /// @param newSize  the length it is to have
    /// @typeparam T  the element type, which must have a zero value
    public static void Resize<T>(ref T[] array, nuint newSize) where T : zeroable
    {
        if (newSize == array.Length)
            return;

        var made = new T[newSize];
        nuint kept = newSize < array.Length ? newSize : array.Length;
        array[:kept].CopyTo(made);
        array = made;
    }

    /// The same, with the elements past the old length set to `fill`. This is
    /// the one for a `T` with no zero value, such as `String`.
    ///
    /// @param array    the array, replaced by the resized one
    /// @param newSize  the length it is to have
    /// @param fill     what each new element is
    /// @typeparam T  the element type; nothing is asked of it
    public static void Resize<T>(ref T[] array, nuint newSize, T fill)
    {
        if (newSize == array.Length)
            return;

        T[] made = Repeat(fill, newSize);
        nuint kept = newSize < array.Length ? newSize : array.Length;
        array[:kept].CopyTo(made);
        array = made;
    }

    // ------------------------------------------------------------ copying

    /// Copies the first `length` elements of `sourceArray` to the start of
    /// `destinationArray`. Aborts, before anything is written, when either is
    /// shorter than `length`.
    ///
    /// @param sourceArray       where the elements come from
    /// @param destinationArray  where they go
    /// @param length            how many to copy
    /// @typeparam T  the element type; nothing is asked of it
    public static void Copy<T>(T[] sourceArray, T[] destinationArray, nuint length) =>
        sourceArray[:length].CopyTo(destinationArray);

    /// Copies `length` elements from `sourceIndex` in `sourceArray` to
    /// `destinationIndex` in `destinationArray`. The two may be the same array
    /// and the ranges may overlap: the elements land as they were before the
    /// copy began. Aborts, before anything is written, when either range runs
    /// past its array. .NET's `ConstrainedCopy` promises no more than this.
    ///
    /// @param sourceArray       where the elements come from
    /// @param sourceIndex       the first element copied
    /// @param destinationArray  where they go
    /// @param destinationIndex  where the first lands
    /// @param length            how many to copy
    /// @typeparam T  the element type; nothing is asked of it
    public static void Copy<T>(T[] sourceArray, nuint sourceIndex, T[] destinationArray,
        nuint destinationIndex, nuint length) =>
        sourceArray[sourceIndex:][:length].CopyTo(destinationArray[destinationIndex:]);

    /// Sets every element to the zero of `T`, releasing whatever they held.
    ///
    /// Only for a `T` with a zero value: an array of `String` has no `Clear`,
    /// since there is nothing its elements could be set to. `Fill` is the one
    /// for that.
    ///
    /// @param array  the array to clear
    /// @typeparam T  the element type, which must have a zero value
    public static void Clear<T>(T[] array) where T : zeroable
    {
        Span<T> whole = array;
        whole.Clear();
    }

    /// Sets `length` elements from `index` to the zero of `T`. Aborts when they
    /// run past the end.
    ///
    /// @param array   the array to clear part of
    /// @param index   the first element cleared
    /// @param length  how many to clear
    /// @typeparam T  the element type, which must have a zero value
    public static void Clear<T>(T[] array, nuint index, nuint length) where T : zeroable =>
        array[index:][:length].Clear();

    /// Sets every element to `value`.
    ///
    /// @param array  the array to fill
    /// @param value  what each element becomes
    /// @typeparam T  the element type; nothing is asked of it
    public static void Fill<T>(T[] array, T value)
    {
        Span<T> whole = array;
        whole.Fill(value);
    }

    /// Sets `count` elements from `startIndex` to `value`. Aborts when they run
    /// past the end.
    ///
    /// @param array       the array to fill part of
    /// @param value       what each element becomes
    /// @param startIndex  the first element set
    /// @param count       how many to set
    /// @typeparam T  the element type; nothing is asked of it
    public static void Fill<T>(T[] array, T value, nuint startIndex, nuint count) =>
        array[startIndex:][:count].Fill(value);

    /// Reverses the order of the elements in place.
    ///
    /// @param array  the array to reverse
    /// @typeparam T  the element type; nothing is asked of it
    public static void Reverse<T>(T[] array) => Standard.Collections.Reverse(array);

    /// Reverses `length` elements from `index` in place. Aborts when they run
    /// past the end.
    ///
    /// @param array   the array to reverse part of
    /// @param index   the first element of the part
    /// @param length  how many elements it covers
    /// @typeparam T  the element type; nothing is asked of it
    public static void Reverse<T>(T[] array, nuint index, nuint length) =>
        Standard.Collections.Reverse(array[index:][:length]);

    // ------------------------------------------------------------ ordering

    /// Orders the elements in place, smallest first. Stable, where .NET's is
    /// not: equal elements keep the order they had.
    ///
    /// @param array  the array to order
    /// @typeparam T  the element type, which must order itself
    /// @see Collections.Sort
    public static void Sort<T>(T[] array) where T : IComparable<T> =>
        Standard.Collections.Sort(array);

    /// Orders the elements in place by `comparison`. Stable.
    ///
    /// @param array       the array to order
    /// @param comparison  negative when its first argument comes first
    /// @typeparam T  the element type; nothing is asked of it
    public static void Sort<T>(T[] array, Comparison<T> comparison) =>
        Standard.Collections.Sort(array, comparison);

    /// Orders `length` elements from `index` in place, smallest first, and
    /// leaves the rest alone. Stable. Aborts when they run past the end.
    ///
    /// @param array   the array to order part of
    /// @param index   the first element of the part
    /// @param length  how many elements it covers
    /// @typeparam T  the element type, which must order itself
    public static void Sort<T>(T[] array, nuint index, nuint length) where T : IComparable<T> =>
        Standard.Collections.Sort(array[index:][:length]);

    /// Orders `length` elements from `index` in place by `comparison`. Stable.
    /// Aborts when they run past the end.
    ///
    /// @param array       the array to order part of
    /// @param index       the first element of the part
    /// @param length      how many elements it covers
    /// @param comparison  negative when its first argument comes first
    /// @typeparam T  the element type; nothing is asked of it
    public static void Sort<T>(T[] array, nuint index, nuint length, Comparison<T> comparison) =>
        Standard.Collections.Sort(array[index:][:length], comparison);

    /// Orders `keys` in place, smallest first, and moves each element of
    /// `items` to where its key went. Stable. The two MUST be the same length;
    /// the call aborts otherwise, where .NET allows `items` to be longer.
    ///
    /// @param keys   the keys to order by
    /// @param items  the elements that go with them
    /// @typeparam TKey    the key type, which must order itself
    /// @typeparam TValue  the item type; nothing is asked of it
    public static void Sort<TKey, TValue>(TKey[] keys, TValue[] items)
        where TKey : IComparable<TKey> =>
        Standard.Collections.Sort(keys, items);

    /// The same, with the keys ordered by `comparison`.
    ///
    /// @param keys        the keys to order by
    /// @param items       the elements that go with them
    /// @param comparison  negative when its first argument comes first
    /// @typeparam TKey    the key type; the comparison orders it
    /// @typeparam TValue  the item type; nothing is asked of it
    public static void Sort<TKey, TValue>(TKey[] keys, TValue[] items,
        Comparison<TKey> comparison) =>
        Standard.Collections.Sort(keys, items, comparison);

    /// Where `value` is in an array already ordered smallest first, if it is
    /// there. `Collections.FindLowerBound` answers where it would go instead,
    /// which .NET folds into a negative result.
    ///
    /// @param array  the ordered array
    /// @param value  what to look for
    /// @typeparam T  the element type, which must order itself
    /// @returns the index of an equal element, or `None`
    /// @see Collections.FindLowerBound
    public static Optional<nuint> BinarySearch<T>(T[] array, T value) where T : IComparable<T> =>
        Standard.Collections.BinarySearch(array, value);

    /// Where `value` is among `length` ordered elements from `index`, if it is
    /// there. The answer counts from the start of the array. Aborts when the
    /// range runs past the end.
    ///
    /// @param array   the array
    /// @param index   the first element searched
    /// @param length  how many elements are searched
    /// @param value   what to look for
    /// @typeparam T  the element type, which must order itself
    /// @returns the index of an equal element, or `None`
    public static Optional<nuint> BinarySearch<T>(T[] array, nuint index, nuint length, T value)
        where T : IComparable<T> =>
        MoveIndex(Standard.Collections.BinarySearch(array[index:][:length], value), index);

    // ------------------------------------------------------------ searching

    /// Where the first element equal to `value` is, if there is one.
    ///
    /// @param array  the array to search
    /// @param value  what to look for
    /// @typeparam T  the element type, which must answer whether it equals another
    public static Optional<nuint> IndexOf<T>(T[] array, T value) where T : IEquatable<T> =>
        Standard.Collections.IndexOf(array, value);

    /// Where the first element equal to `value` is, searching from
    /// `startIndex` to the end. Aborts when `startIndex` is past the end.
    ///
    /// @param array       the array to search
    /// @param value       what to look for
    /// @param startIndex  the first element searched
    /// @typeparam T  the element type, which must answer whether it equals another
    public static Optional<nuint> IndexOf<T>(T[] array, T value, nuint startIndex)
        where T : IEquatable<T> =>
        MoveIndex(Standard.Collections.IndexOf(array[startIndex:], value), startIndex);

    /// Where the first element equal to `value` is among `count` elements from
    /// `startIndex`. Aborts when they run past the end.
    ///
    /// @param array       the array to search
    /// @param value       what to look for
    /// @param startIndex  the first element searched
    /// @param count       how many elements are searched
    /// @typeparam T  the element type, which must answer whether it equals another
    public static Optional<nuint> IndexOf<T>(T[] array, T value, nuint startIndex, nuint count)
        where T : IEquatable<T> =>
        MoveIndex(Standard.Collections.IndexOf(array[startIndex:][:count], value), startIndex);

    /// Where the last element equal to `value` is, if there is one.
    ///
    /// @param array  the array to search
    /// @param value  what to look for
    /// @typeparam T  the element type, which must answer whether it equals another
    public static Optional<nuint> LastIndexOf<T>(T[] array, T value) where T : IEquatable<T> =>
        Standard.Collections.LastIndexOf(array, value);

    /// Where the last element equal to `value` is, searching backward from
    /// `startIndex` to the start. Aborts when `startIndex` is past the end.
    ///
    /// @param array       the array to search
    /// @param value       what to look for
    /// @param startIndex  the last element searched, where the search begins
    /// @typeparam T  the element type, which must answer whether it equals another
    public static Optional<nuint> LastIndexOf<T>(T[] array, T value, nuint startIndex)
        where T : IEquatable<T> =>
        LastIndexOf(array, value, startIndex, CountThrough(array.Length, startIndex));

    /// Where the last element equal to `value` is among the `count` elements
    /// that end at `startIndex`, searching backward. Aborts when they run past
    /// either end.
    ///
    /// @param array       the array to search
    /// @param value       what to look for
    /// @param startIndex  the last element searched, where the search begins
    /// @param count       how many elements are searched
    /// @typeparam T  the element type, which must answer whether it equals another
    public static Optional<nuint> LastIndexOf<T>(T[] array, T value, nuint startIndex,
        nuint count) where T : IEquatable<T>
    {
        nuint first = FindBackwardStart(array.Length, startIndex, count);
        return MoveIndex(Standard.Collections.LastIndexOf(array[first:][:count], value), first);
    }

    /// Whether any element satisfies `match`.
    ///
    /// @param array  the array to search
    /// @param match  what an element must satisfy
    /// @typeparam T  the element type; nothing is asked of it
    public static bool Exists<T>(T[] array, Predicate<T> match) =>
        Standard.Collections.Any(array, match);

    /// Whether every element satisfies `match`. True for an empty array.
    ///
    /// @param array  the array to test
    /// @param match  what each element must satisfy
    /// @typeparam T  the element type; nothing is asked of it
    public static bool TrueForAll<T>(T[] array, Predicate<T> match) =>
        Standard.Collections.All(array, match);

    /// The first element satisfying `match`, if there is one. An `Optional`
    /// where .NET answers `default(T)`, which a `T` that is never null does not
    /// have.
    ///
    /// @param array  the array to search
    /// @param match  what the element must satisfy
    /// @typeparam T  the element type; nothing is asked of it
    public static Optional<T> Find<T>(T[] array, Predicate<T> match) =>
        Standard.Collections.Find(array, match);

    /// The last element satisfying `match`, if there is one.
    ///
    /// @param array  the array to search
    /// @param match  what the element must satisfy
    /// @typeparam T  the element type; nothing is asked of it
    public static Optional<T> FindLast<T>(T[] array, Predicate<T> match)
    {
        for (nuint i = array.Length; i > 0u; i--)
        {
            if (match(array[i - 1u]))
                return Some(array[i - 1u]);
        }
        return None;
    }

    /// Every element satisfying `match`, in order, as a new array.
    ///
    /// @param array  the array to search
    /// @param match  what an element must satisfy
    /// @typeparam T  the element type; nothing is asked of it
    public static T[] FindAll<T>(T[] array, Predicate<T> match) =>
        Standard.Collections.Where(array, match).ToArray();

    /// Where the first element satisfying `match` is, if there is one.
    ///
    /// @param array  the array to search
    /// @param match  what the element must satisfy
    /// @typeparam T  the element type; nothing is asked of it
    public static Optional<nuint> FindIndex<T>(T[] array, Predicate<T> match) =>
        Standard.Collections.FindIndex(array, match);

    /// Where the first element satisfying `match` is, searching from
    /// `startIndex` to the end. Aborts when `startIndex` is past the end.
    ///
    /// @param array       the array to search
    /// @param startIndex  the first element searched
    /// @param match       what the element must satisfy
    /// @typeparam T  the element type; nothing is asked of it
    public static Optional<nuint> FindIndex<T>(T[] array, nuint startIndex, Predicate<T> match) =>
        MoveIndex(Standard.Collections.FindIndex(array[startIndex:], match), startIndex);

    /// Where the first element satisfying `match` is among `count` elements
    /// from `startIndex`. Aborts when they run past the end.
    ///
    /// @param array       the array to search
    /// @param startIndex  the first element searched
    /// @param count       how many elements are searched
    /// @param match       what the element must satisfy
    /// @typeparam T  the element type; nothing is asked of it
    public static Optional<nuint> FindIndex<T>(T[] array, nuint startIndex, nuint count,
        Predicate<T> match) =>
        MoveIndex(Standard.Collections.FindIndex(array[startIndex:][:count], match), startIndex);

    /// Where the last element satisfying `match` is, if there is one.
    ///
    /// @param array  the array to search
    /// @param match  what the element must satisfy
    /// @typeparam T  the element type; nothing is asked of it
    public static Optional<nuint> FindLastIndex<T>(T[] array, Predicate<T> match) =>
        FindLastIndex(array, array.Length == 0u ? 0u : array.Length - 1u, array.Length, match);

    /// Where the last element satisfying `match` is, searching backward from
    /// `startIndex` to the start. Aborts when `startIndex` is past the end.
    ///
    /// @param array       the array to search
    /// @param startIndex  the last element searched, where the search begins
    /// @param match       what the element must satisfy
    /// @typeparam T  the element type; nothing is asked of it
    public static Optional<nuint> FindLastIndex<T>(T[] array, nuint startIndex,
        Predicate<T> match) =>
        FindLastIndex(array, startIndex, CountThrough(array.Length, startIndex), match);

    /// Where the last element satisfying `match` is among the `count` elements
    /// that end at `startIndex`, searching backward. Aborts when they run past
    /// either end.
    ///
    /// @param array       the array to search
    /// @param startIndex  the last element searched, where the search begins
    /// @param count       how many elements are searched
    /// @param match       what the element must satisfy
    /// @typeparam T  the element type; nothing is asked of it
    public static Optional<nuint> FindLastIndex<T>(T[] array, nuint startIndex, nuint count,
        Predicate<T> match)
    {
        nuint first = FindBackwardStart(array.Length, startIndex, count);
        for (nuint i = first + count; i > first; i--)
        {
            if (match(array[i - 1u]))
                return Some(i - 1u);
        }
        return None;
    }

    /// Runs `action` over every element, in order.
    ///
    /// @param array   the array to walk
    /// @param action  what to do with each element
    /// @typeparam T  the element type; nothing is asked of it
    public static void ForEach<T>(T[] array, Action<T> action) =>
        Standard.Collections.ForEach(array, action);

    // ------------------------------------------------------------ ranges

    /// An index found in a part of an array, counted from the array's start.
    private static Optional<nuint> MoveIndex(Optional<nuint> found, nuint offset)
    {
        if (found is Some at)
            return Some(at.Value + offset);
        return None;
    }

    /// How many elements run from the start through `startIndex`: none in an
    /// empty array, which is the one place `startIndex` may equal the length.
    private static nuint CountThrough(nuint length, nuint startIndex) =>
        length == 0u ? 0u : startIndex + 1u;

    /// The first index of the `count` elements that end at `startIndex`, the
    /// range a backward search is given. Aborts when it does not fit.
    private static nuint FindBackwardStart(nuint length, nuint startIndex, nuint count)
    {
        if (length == 0u && startIndex == 0u && count == 0u)
            return 0u;
        if (startIndex >= length || count > startIndex + 1u)
            sl_fail("Array: a backward search runs past the array");
        return startIndex + 1u - count;
    }
}
