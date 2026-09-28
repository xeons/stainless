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

/// Searching, comparing and trimming spans: C#'s `MemoryExtensions`.
///
/// Free functions rather than members, for C#'s reason: each asks something of
/// the element -- equality or an order -- that the span itself does not, and a
/// struct cannot ask it of one method alone. A call written on a span reaches
/// them all the same:
///
///     if (line.StartsWith("#"u8)) { ... }
///     var at = numbers.IndexOf(42);
///
/// Each takes a `ReadOnlySpan<T>`, which an array and a `Span<T>` convert to,
/// except where it writes. A position is an `Optional<nuint>` rather than -1.
module Standard.Collections;

import Standard.Unchecked;

// ------------------------------------------------------------------ one value

/// Where the first element equal to `value` is, if there is one.
///
/// @typeparam T  the element type, which must answer whether it equals another
/// @see Collections.LastIndexOf
public Optional<nuint> IndexOf<T>(ReadOnlySpan<T> span, T value) where T : IEquatable<T>
{
    for (nuint i = 0u; i < span.Length; i++)
    {
        if (span[i].Equals(value))
            return Some(i);
    }
    return None;
}

/// Where the last element equal to `value` is, if there is one.
///
/// @typeparam T  the element type, which must answer whether it equals another
/// @see Collections.IndexOf
public Optional<nuint> LastIndexOf<T>(ReadOnlySpan<T> span, T value) where T : IEquatable<T>
{
    for (nuint i = span.Length; i > 0u; i--)
    {
        if (span[i - 1u].Equals(value))
            return Some(i - 1u);
    }
    return None;
}

/// Whether any element equals `value`.
///
/// @typeparam T  the element type, which must answer whether it equals another
public bool Contains<T>(ReadOnlySpan<T> span, T value) where T : IEquatable<T> =>
    IndexOf(span, value).HasValue;

/// How many elements equal `value`.
///
/// @typeparam T  the element type, which must answer whether it equals another
public nuint Count<T>(ReadOnlySpan<T> span, T value) where T : IEquatable<T>
{
    nuint found = 0u;
    foreach (var element in span)
    {
        if (element.Equals(value))
            found++;
    }
    return found;
}

// ----------------------------------------------------------------- a sequence

/// Where `value` first appears as a run of elements. An empty `value`
/// appears at the start.
///
/// @typeparam T  the element type, which must answer whether it equals another
/// @see Collections.LastIndexOf
public Optional<nuint> IndexOf<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> value)
    where T : IEquatable<T>
{
    if (value.Length > span.Length)
        return None;

    for (nuint i = 0u; i <= span.Length - value.Length; i++)
    {
        if (SequenceEqual(span[i:][:value.Length], value))
            return Some(i);
    }
    return None;
}

/// Where `value` last appears as a run of elements. An empty `value`
/// appears at the end.
///
/// @typeparam T  the element type, which must answer whether it equals another
/// @see Collections.IndexOf
public Optional<nuint> LastIndexOf<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> value)
    where T : IEquatable<T>
{
    if (value.Length > span.Length)
        return None;

    for (nuint i = span.Length - value.Length + 1u; i > 0u; i--)
    {
        if (SequenceEqual(span[i - 1u:][:value.Length], value))
            return Some(i - 1u);
    }
    return None;
}

/// How many times `value` appears as a run of elements, counting runs that
/// do not overlap. An empty `value` appears nowhere.
///
/// @typeparam T  the element type, which must answer whether it equals another
public nuint Count<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> value) where T : IEquatable<T>
{
    if (value.Length == 0u)
        return 0u;

    nuint found = 0u;
    nuint from = 0u;
    while (IndexOf(span[from:], value) is Some at)
    {
        found++;
        from += at.Value + value.Length;
    }
    return found;
}

/// Whether the two hold equal elements in the same order.
///
/// @typeparam T  the element type, which must answer whether it equals another
public bool SequenceEqual<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> other) where T : IEquatable<T>
{
    if (span.Length != other.Length)
        return false;

    for (nuint i = 0u; i < span.Length; i++)
    {
        if (!span[i].Equals(other[i]))
            return false;
    }
    return true;
}

/// How the two order element by element: negative when `span` comes first,
/// zero when they are equal, positive when `other` does. A span that runs out
/// first comes first.
///
/// @typeparam T  the element type, which must order itself
public int SequenceCompareTo<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> other)
    where T : IComparable<T>
{
    nuint shorter = span.Length < other.Length ? span.Length : other.Length;
    for (nuint i = 0u; i < shorter; i++)
    {
        int order = span[i].CompareTo(other[i]);
        if (order != 0)
            return order;
    }

    if (span.Length == other.Length)
        return 0;
    return span.Length < other.Length ? -1 : 1;
}

/// Whether `span` begins with the elements of `value`.
///
/// @typeparam T  the element type, which must answer whether it equals another
public bool StartsWith<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> value) where T : IEquatable<T> =>
    value.Length <= span.Length && SequenceEqual(span[:value.Length], value);

/// Whether the first element equals `value`.
///
/// @typeparam T  the element type, which must answer whether it equals another
public bool StartsWith<T>(ReadOnlySpan<T> span, T value) where T : IEquatable<T> =>
    span.Length != 0u && span[0].Equals(value);

/// Whether `span` ends with the elements of `value`.
///
/// @typeparam T  the element type, which must answer whether it equals another
public bool EndsWith<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> value) where T : IEquatable<T> =>
    value.Length <= span.Length && SequenceEqual(span[span.Length - value.Length:], value);

/// Whether the last element equals `value`.
///
/// @typeparam T  the element type, which must answer whether it equals another
public bool EndsWith<T>(ReadOnlySpan<T> span, T value) where T : IEquatable<T> =>
    span.Length != 0u && span[^1].Equals(value);

/// How many elements at the start the two have in common.
///
/// @typeparam T  the element type, which must answer whether it equals another
public nuint CommonPrefixLength<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> other)
    where T : IEquatable<T>
{
    nuint shorter = span.Length < other.Length ? span.Length : other.Length;
    for (nuint i = 0u; i < shorter; i++)
    {
        if (!span[i].Equals(other[i]))
            return i;
    }
    return shorter;
}

// -------------------------------------------------------------- any of a set

/// Where the first element equal to either value is.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Optional<nuint> IndexOfAny<T>(ReadOnlySpan<T> span, T first, T second)
    where T : IEquatable<T> =>
    IndexOfAny(span, [first, second]);

/// Where the first element equal to any of the three is.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Optional<nuint> IndexOfAny<T>(ReadOnlySpan<T> span, T first, T second, T third)
    where T : IEquatable<T> =>
    IndexOfAny(span, [first, second, third]);

/// Where the first element equal to any of `values` is.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Optional<nuint> IndexOfAny<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> values)
    where T : IEquatable<T>
{
    for (nuint i = 0u; i < span.Length; i++)
    {
        if (Contains(values, span[i]))
            return Some(i);
    }
    return None;
}

/// Where the last element equal to either value is.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Optional<nuint> LastIndexOfAny<T>(ReadOnlySpan<T> span, T first, T second)
    where T : IEquatable<T> =>
    LastIndexOfAny(span, [first, second]);

/// Where the last element equal to any of the three is.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Optional<nuint> LastIndexOfAny<T>(ReadOnlySpan<T> span, T first, T second, T third)
    where T : IEquatable<T> =>
    LastIndexOfAny(span, [first, second, third]);

/// Where the last element equal to any of `values` is.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Optional<nuint> LastIndexOfAny<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> values)
    where T : IEquatable<T>
{
    for (nuint i = span.Length; i > 0u; i--)
    {
        if (Contains(values, span[i - 1u]))
            return Some(i - 1u);
    }
    return None;
}

/// Where the first element other than `value` is.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Optional<nuint> IndexOfAnyExcept<T>(ReadOnlySpan<T> span, T value)
    where T : IEquatable<T> =>
    IndexOfAnyExcept(span, [value]);

/// Where the first element equal to neither value is.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Optional<nuint> IndexOfAnyExcept<T>(ReadOnlySpan<T> span, T first, T second)
    where T : IEquatable<T> =>
    IndexOfAnyExcept(span, [first, second]);

/// Where the first element equal to none of the three is.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Optional<nuint> IndexOfAnyExcept<T>(ReadOnlySpan<T> span, T first, T second, T third)
    where T : IEquatable<T> =>
    IndexOfAnyExcept(span, [first, second, third]);

/// Where the first element equal to none of `values` is.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Optional<nuint> IndexOfAnyExcept<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> values)
    where T : IEquatable<T>
{
    for (nuint i = 0u; i < span.Length; i++)
    {
        if (!Contains(values, span[i]))
            return Some(i);
    }
    return None;
}

/// Where the last element other than `value` is.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Optional<nuint> LastIndexOfAnyExcept<T>(ReadOnlySpan<T> span, T value)
    where T : IEquatable<T> =>
    LastIndexOfAnyExcept(span, [value]);

/// Where the last element equal to neither value is.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Optional<nuint> LastIndexOfAnyExcept<T>(ReadOnlySpan<T> span, T first, T second)
    where T : IEquatable<T> =>
    LastIndexOfAnyExcept(span, [first, second]);

/// Where the last element equal to none of the three is.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Optional<nuint> LastIndexOfAnyExcept<T>(ReadOnlySpan<T> span, T first, T second, T third)
    where T : IEquatable<T> =>
    LastIndexOfAnyExcept(span, [first, second, third]);

/// Where the last element equal to none of `values` is.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Optional<nuint> LastIndexOfAnyExcept<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> values)
    where T : IEquatable<T>
{
    for (nuint i = span.Length; i > 0u; i--)
    {
        if (!Contains(values, span[i - 1u]))
            return Some(i - 1u);
    }
    return None;
}

/// Whether any element equals either value.
///
/// @typeparam T  the element type, which must answer whether it equals another
public bool ContainsAny<T>(ReadOnlySpan<T> span, T first, T second) where T : IEquatable<T> =>
    IndexOfAny(span, first, second).HasValue;

/// Whether any element equals any of the three.
///
/// @typeparam T  the element type, which must answer whether it equals another
public bool ContainsAny<T>(ReadOnlySpan<T> span, T first, T second, T third)
    where T : IEquatable<T> =>
    IndexOfAny(span, first, second, third).HasValue;

/// Whether any element equals any of `values`.
///
/// @typeparam T  the element type, which must answer whether it equals another
public bool ContainsAny<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> values) where T : IEquatable<T> =>
    IndexOfAny(span, values).HasValue;

/// Whether any element is other than `value`.
///
/// @typeparam T  the element type, which must answer whether it equals another
public bool ContainsAnyExcept<T>(ReadOnlySpan<T> span, T value) where T : IEquatable<T> =>
    IndexOfAnyExcept(span, value).HasValue;

/// Whether any element equals neither value.
///
/// @typeparam T  the element type, which must answer whether it equals another
public bool ContainsAnyExcept<T>(ReadOnlySpan<T> span, T first, T second)
    where T : IEquatable<T> =>
    IndexOfAnyExcept(span, first, second).HasValue;

/// Whether any element equals none of the three.
///
/// @typeparam T  the element type, which must answer whether it equals another
public bool ContainsAnyExcept<T>(ReadOnlySpan<T> span, T first, T second, T third)
    where T : IEquatable<T> =>
    IndexOfAnyExcept(span, first, second, third).HasValue;

/// Whether any element equals none of `values`.
///
/// @typeparam T  the element type, which must answer whether it equals another
public bool ContainsAnyExcept<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> values)
    where T : IEquatable<T> =>
    IndexOfAnyExcept(span, values).HasValue;

// ---------------------------------------------------------------- in a range

/// Whether `value` is between `low` and `high`, both included.
///
/// @typeparam T  the element type, which must order itself
bool IsInRange<T>(T value, T low, T high) where T : IComparable<T> =>
    value.CompareTo(low) >= 0 && value.CompareTo(high) <= 0;

/// Where the first element between `low` and `high`, both included, is.
///
/// @typeparam T  the element type, which must order itself
public Optional<nuint> IndexOfAnyInRange<T>(ReadOnlySpan<T> span, T low, T high)
    where T : IComparable<T>
{
    for (nuint i = 0u; i < span.Length; i++)
    {
        if (IsInRange(span[i], low, high))
            return Some(i);
    }
    return None;
}

/// Where the first element outside `low` to `high` is.
///
/// @typeparam T  the element type, which must order itself
public Optional<nuint> IndexOfAnyExceptInRange<T>(ReadOnlySpan<T> span, T low, T high)
    where T : IComparable<T>
{
    for (nuint i = 0u; i < span.Length; i++)
    {
        if (!IsInRange(span[i], low, high))
            return Some(i);
    }
    return None;
}

/// Where the last element between `low` and `high`, both included, is.
///
/// @typeparam T  the element type, which must order itself
public Optional<nuint> LastIndexOfAnyInRange<T>(ReadOnlySpan<T> span, T low, T high)
    where T : IComparable<T>
{
    for (nuint i = span.Length; i > 0u; i--)
    {
        if (IsInRange(span[i - 1u], low, high))
            return Some(i - 1u);
    }
    return None;
}

/// Where the last element outside `low` to `high` is.
///
/// @typeparam T  the element type, which must order itself
public Optional<nuint> LastIndexOfAnyExceptInRange<T>(ReadOnlySpan<T> span, T low, T high)
    where T : IComparable<T>
{
    for (nuint i = span.Length; i > 0u; i--)
    {
        if (!IsInRange(span[i - 1u], low, high))
            return Some(i - 1u);
    }
    return None;
}

/// Whether any element is between `low` and `high`, both included.
///
/// @typeparam T  the element type, which must order itself
public bool ContainsAnyInRange<T>(ReadOnlySpan<T> span, T low, T high) where T : IComparable<T> =>
    IndexOfAnyInRange(span, low, high).HasValue;

/// Whether any element is outside `low` to `high`.
///
/// @typeparam T  the element type, which must order itself
public bool ContainsAnyExceptInRange<T>(ReadOnlySpan<T> span, T low, T high)
    where T : IComparable<T> =>
    IndexOfAnyExceptInRange(span, low, high).HasValue;

// ------------------------------------------------------------------- writing

/// Replaces every element equal to `oldValue` with `newValue`, in place.
///
/// @typeparam T  the element type, which must answer whether it equals another
public void Replace<T>(Span<T> span, T oldValue, T newValue) where T : IEquatable<T>
{
    for (nuint i = 0u; i < span.Length; i++)
    {
        if (span[i].Equals(oldValue))
            span[i] = newValue;
    }
}

/// Copies `source` into the start of `destination` with every element equal
/// to `oldValue` replaced by `newValue`, aborting when `destination` is
/// shorter.
///
/// @typeparam T  the element type, which must answer whether it equals another
public void Replace<T>(ReadOnlySpan<T> source, Span<T> destination, T oldValue, T newValue)
    where T : IEquatable<T>
{
    Span<T> target = destination[:source.Length];
    source.CopyTo(target);
    Replace(target, oldValue, newValue);
}

/// Orders `keys` in place, smallest first, and moves each element of `items`
/// to where its key went. The two MUST be the same length.
///
/// @typeparam TKey    the key type, which must order itself
/// @typeparam TValue  the item type; nothing is asked of it
public void Sort<TKey, TValue>(Span<TKey> keys, Span<TValue> items) where TKey : IComparable<TKey> =>
    Sort(keys, items, (a, b) => a.CompareTo(b));

/// Orders `keys` in place by `order` and moves each element of `items` to
/// where its key went. Stable. The two MUST be the same length.
///
/// @typeparam TKey    the key type
/// @typeparam TValue  the item type; nothing is asked of it
public void Sort<TKey, TValue>(Span<TKey> keys, Span<TValue> items, Comparison<TKey> order)
{
    if (keys.Length != items.Length)
        sl_fail("Sort: the keys and the items are not the same length");

    TKey[] sortedKeys = keys.ToArray();
    var positions = new nuint[keys.Length];
    for (nuint i = 0u; i < positions.Length; i++)
        positions[i] = i;

    Sort(positions, (a, b) => order(sortedKeys[a], sortedKeys[b]));

    TValue[] sortedItems = NewUninitializedArray<TValue>(items.Length);
    for (nuint i = 0u; i < positions.Length; i++)
    {
        keys[i] = sortedKeys[positions[i]];
        sortedItems[i] = items[positions[i]];
    }

    ReadOnlySpan<TValue> moved = sortedItems;
    moved.CopyTo(items);
}

// ------------------------------------------------------------------ trimming

/// Where the part left after trimming starts and ends, as `[start, end)`.
(nuint, nuint) FindTrimmed<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> trimmed, bool front, bool back)
    where T : IEquatable<T>
{
    nuint start = 0u;
    nuint end = span.Length;

    if (front)
    {
        while (start < end && Contains(trimmed, span[start]))
            start++;
    }

    if (back)
    {
        while (end > start && Contains(trimmed, span[end - 1u]))
            end--;
    }

    return (start, end);
}

/// Without the elements equal to `value` at either end.
///
/// @typeparam T  the element type, which must answer whether it equals another
public ReadOnlySpan<T> Trim<T>(ReadOnlySpan<T> span, T value) where T : IEquatable<T> =>
    Trim(span, [value]);

/// Without the elements equal to any of `trimElements` at either end.
///
/// @typeparam T  the element type, which must answer whether it equals another
public ReadOnlySpan<T> Trim<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> trimElements)
    where T : IEquatable<T>
{
    var (start, end) = FindTrimmed(span, trimElements, true, true);
    return span[start:end];
}

/// Without the elements equal to `value` at the start.
///
/// @typeparam T  the element type, which must answer whether it equals another
public ReadOnlySpan<T> TrimStart<T>(ReadOnlySpan<T> span, T value) where T : IEquatable<T> =>
    TrimStart(span, [value]);

/// Without the elements equal to any of `trimElements` at the start.
///
/// @typeparam T  the element type, which must answer whether it equals another
public ReadOnlySpan<T> TrimStart<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> trimElements)
    where T : IEquatable<T>
{
    var (start, end) = FindTrimmed(span, trimElements, true, false);
    return span[start:end];
}

/// Without the elements equal to `value` at the end.
///
/// @typeparam T  the element type, which must answer whether it equals another
public ReadOnlySpan<T> TrimEnd<T>(ReadOnlySpan<T> span, T value) where T : IEquatable<T> =>
    TrimEnd(span, [value]);

/// Without the elements equal to any of `trimElements` at the end.
///
/// @typeparam T  the element type, which must answer whether it equals another
public ReadOnlySpan<T> TrimEnd<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> trimElements)
    where T : IEquatable<T>
{
    var (start, end) = FindTrimmed(span, trimElements, false, true);
    return span[start:end];
}

/// Without the elements equal to `value` at either end, still writable.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Span<T> Trim<T>(Span<T> span, T value) where T : IEquatable<T> => Trim(span, [value]);

/// Without the elements equal to any of `trimElements` at either end, still
/// writable.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Span<T> Trim<T>(Span<T> span, ReadOnlySpan<T> trimElements) where T : IEquatable<T>
{
    var (start, end) = FindTrimmed(span, trimElements, true, true);
    return span[start:end];
}

/// Without the elements equal to `value` at the start, still writable.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Span<T> TrimStart<T>(Span<T> span, T value) where T : IEquatable<T> =>
    TrimStart(span, [value]);

/// Without the elements equal to any of `trimElements` at the start, still
/// writable.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Span<T> TrimStart<T>(Span<T> span, ReadOnlySpan<T> trimElements) where T : IEquatable<T>
{
    var (start, end) = FindTrimmed(span, trimElements, true, false);
    return span[start:end];
}

/// Without the elements equal to `value` at the end, still writable.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Span<T> TrimEnd<T>(Span<T> span, T value) where T : IEquatable<T> => TrimEnd(span, [value]);

/// Without the elements equal to any of `trimElements` at the end, still
/// writable.
///
/// @typeparam T  the element type, which must answer whether it equals another
public Span<T> TrimEnd<T>(Span<T> span, ReadOnlySpan<T> trimElements) where T : IEquatable<T>
{
    var (start, end) = FindTrimmed(span, trimElements, false, true);
    return span[start:end];
}
