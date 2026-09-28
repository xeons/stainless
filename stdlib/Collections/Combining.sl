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

/// Joining, cutting and comparing sequences: LINQ's `Concat`, `Append`,
/// `Prepend`, `Zip`, `Chunk`, `TakeWhile`, `SkipWhile`, `TakeLast`,
/// `SkipLast`, `SelectMany`, `DistinctBy`, `Union`, `Intersect` and `Except`,
/// and the `By` forms of the last three.
///
/// Each answers with a new list and leaves its input alone. The set
/// operators keep the order elements were first met in, as C#'s do, and ask
/// of the element -- or of the key, for a `By` form -- what a `HashSet` asks.
module Standard.Collections;

// -------------------------------------------------------------- over a span

/// The elements of `first`, then those of `second`.
///
/// @typeparam T  the element type; nothing is asked of it
public List<T> Concat<T>(ReadOnlySpan<T> first, ReadOnlySpan<T> second)
{
    var joined = new List<T>();
    foreach (var item in first)
        joined.Add(item);
    foreach (var item in second)
        joined.Add(item);
    return joined;
}

/// The elements, then `element`.
///
/// @typeparam T  the element type; nothing is asked of it
public List<T> Append<T>(ReadOnlySpan<T> items, T element)
{
    var joined = ToList(items);
    joined.Add(element);
    return joined;
}

/// `element`, then the elements.
///
/// @typeparam T  the element type; nothing is asked of it
public List<T> Prepend<T>(ReadOnlySpan<T> items, T element)
{
    var joined = new List<T>();
    joined.Add(element);
    foreach (var item in items)
        joined.Add(item);
    return joined;
}

/// Pairs of elements at the same position, as long as the shorter lasts.
///
/// @typeparam TFirst   the first sequence's element type
/// @typeparam TSecond  the second's
public List<(TFirst, TSecond)> Zip<TFirst, TSecond>(ReadOnlySpan<TFirst> first, ReadOnlySpan<TSecond> second) =>
    Zip(first, second, (a, b) => (a, b));

/// What `combine` makes of the elements at each position, as long as the
/// shorter lasts.
///
/// @typeparam TFirst   the first sequence's element type
/// @typeparam TSecond  the second's
/// @typeparam TResult  what `combine` makes
public List<TResult> Zip<TFirst, TSecond, TResult>(
    ReadOnlySpan<TFirst> first, ReadOnlySpan<TSecond> second, Func<TFirst, TSecond, TResult> combine)
{
    TFirst[] left = ToArray(first);
    TSecond[] right = ToArray(second);
    nuint shorter = left.Length < right.Length ? left.Length : right.Length;

    var zipped = new List<TResult>();
    for (nuint i = 0u; i < shorter; i++)
        zipped.Add(combine(left[i], right[i]));
    return zipped;
}

/// The elements in arrays of `size`, the last holding what is left. Aborts
/// when `size` is zero.
///
/// @typeparam T  the element type; nothing is asked of it
public List<T[]> Chunk<T>(ReadOnlySpan<T> items, nuint size)
{
    if (size == 0u)
        sl_fail("Chunk: the size is zero");

    T[] all = ToArray(items);
    var chunks = new List<T[]>();
    for (nuint start = 0u; start < all.Length; start += size)
    {
        nuint length = all.Length - start < size ? all.Length - start : size;
        ReadOnlySpan<T> part = all[start:][:length];
        chunks.Add(part.ToArray());
    }
    return chunks;
}

/// The elements up to the first the predicate refuses.
///
/// @typeparam T  the element type; nothing is asked of it
public List<T> TakeWhile<T>(ReadOnlySpan<T> items, Predicate<T> keep)
{
    var taken = new List<T>();
    foreach (var item in items)
    {
        if (!keep(item))
            return taken;
        taken.Add(item);
    }
    return taken;
}

/// The elements from the first the predicate refuses.
///
/// @typeparam T  the element type; nothing is asked of it
public List<T> SkipWhile<T>(ReadOnlySpan<T> items, Predicate<T> skip)
{
    var rest = new List<T>();
    bool skipping = true;
    foreach (var item in items)
    {
        if (skipping && skip(item))
            continue;
        skipping = false;
        rest.Add(item);
    }
    return rest;
}

/// The last `count` elements, or all of them if there are fewer.
///
/// @typeparam T  the element type; nothing is asked of it
public List<T> TakeLast<T>(ReadOnlySpan<T> items, nuint count)
{
    T[] all = ToArray(items);
    nuint from = count < all.Length ? all.Length - count : 0u;
    return ToList(all[from:]);
}

/// All but the last `count` elements, or nothing if there are fewer.
///
/// @typeparam T  the element type; nothing is asked of it
public List<T> SkipLast<T>(ReadOnlySpan<T> items, nuint count)
{
    T[] all = ToArray(items);
    nuint to = count < all.Length ? all.Length - count : 0u;
    return ToList(all[:to]);
}

/// Every element of what `select` makes of each element, one after another.
///
/// @typeparam T        the element type
/// @typeparam TResult  the element type of what `select` makes
public List<TResult> SelectMany<T, TResult>(ReadOnlySpan<T> items, Func<T, IEnumerable<TResult>> select)
{
    var flat = new List<TResult>();
    foreach (var item in items)
    {
        foreach (var inner in select(item))
            flat.Add(inner);
    }
    return flat;
}

/// The first element of each key `keySelector` gives, in order.
///
/// @typeparam T     the element type; nothing is asked of it
/// @typeparam TKey  the key, which a `HashSet` must be able to hold
public List<T> DistinctBy<T, TKey>(ReadOnlySpan<T> items, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
{
    var seen = new HashSet<TKey>();
    var kept = new List<T>();
    foreach (var item in items)
    {
        if (seen.Add(keySelector(item)))
            kept.Add(item);
    }
    return kept;
}

/// The distinct elements of both, first's first.
///
/// @typeparam T  the element type, which a `HashSet` must be able to hold
public List<T> Union<T>(ReadOnlySpan<T> first, ReadOnlySpan<T> second) where T : IEquatable<T>, IHashable =>
    UnionBy(first, second, (item) => item);

/// The distinct elements of both, by key, first's first.
///
/// @typeparam T     the element type; nothing is asked of it
/// @typeparam TKey  the key, which a `HashSet` must be able to hold
public List<T> UnionBy<T, TKey>(ReadOnlySpan<T> first, ReadOnlySpan<T> second, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
{
    var seen = new HashSet<TKey>();
    var kept = new List<T>();
    foreach (var item in first)
    {
        if (seen.Add(keySelector(item)))
            kept.Add(item);
    }
    foreach (var item in second)
    {
        if (seen.Add(keySelector(item)))
            kept.Add(item);
    }
    return kept;
}

/// The distinct elements of `first` that are also in `second`.
///
/// @typeparam T  the element type, which a `HashSet` must be able to hold
public List<T> Intersect<T>(ReadOnlySpan<T> first, ReadOnlySpan<T> second) where T : IEquatable<T>, IHashable =>
    IntersectBy(first, second, (item) => item);

/// The distinct elements of `first` whose key is among `keys`.
///
/// @typeparam T     the element type; nothing is asked of it
/// @typeparam TKey  the key, which a `HashSet` must be able to hold
public List<T> IntersectBy<T, TKey>(ReadOnlySpan<T> first, ReadOnlySpan<TKey> keys, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
{
    var wanted = new HashSet<TKey>();
    foreach (var key in keys)
        wanted.Add(key);

    var kept = new List<T>();
    foreach (var item in first)
    {
        if (wanted.Remove(keySelector(item)))
            kept.Add(item);
    }
    return kept;
}

/// The distinct elements of `first` that are not in `second`.
///
/// @typeparam T  the element type, which a `HashSet` must be able to hold
public List<T> Except<T>(ReadOnlySpan<T> first, ReadOnlySpan<T> second) where T : IEquatable<T>, IHashable =>
    ExceptBy(first, second, (item) => item);

/// The distinct elements of `first` whose key is not among `keys`.
///
/// @typeparam T     the element type; nothing is asked of it
/// @typeparam TKey  the key, which a `HashSet` must be able to hold
public List<T> ExceptBy<T, TKey>(ReadOnlySpan<T> first, ReadOnlySpan<TKey> keys, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
{
    var seen = new HashSet<TKey>();
    foreach (var key in keys)
        seen.Add(key);

    var kept = new List<T>();
    foreach (var item in first)
    {
        if (seen.Add(keySelector(item)))
            kept.Add(item);
    }
    return kept;
}

// -------------------------------------------------------------- over any sequence

/// The elements of `first`, then those of `second`.
///
/// @typeparam T  the element type; nothing is asked of it
public List<T> Concat<T>(IEnumerable<T> first, IEnumerable<T> second)
{
    var joined = new List<T>();
    foreach (var item in first)
        joined.Add(item);
    foreach (var item in second)
        joined.Add(item);
    return joined;
}

/// The elements, then `element`.
///
/// @typeparam T  the element type; nothing is asked of it
public List<T> Append<T>(IEnumerable<T> items, T element)
{
    var joined = ToList(items);
    joined.Add(element);
    return joined;
}

/// `element`, then the elements.
///
/// @typeparam T  the element type; nothing is asked of it
public List<T> Prepend<T>(IEnumerable<T> items, T element)
{
    var joined = new List<T>();
    joined.Add(element);
    foreach (var item in items)
        joined.Add(item);
    return joined;
}

/// Pairs of elements at the same position, as long as the shorter lasts.
///
/// @typeparam TFirst   the first sequence's element type
/// @typeparam TSecond  the second's
public List<(TFirst, TSecond)> Zip<TFirst, TSecond>(IEnumerable<TFirst> first, IEnumerable<TSecond> second) =>
    Zip(first, second, (a, b) => (a, b));

/// What `combine` makes of the elements at each position, as long as the
/// shorter lasts.
///
/// @typeparam TFirst   the first sequence's element type
/// @typeparam TSecond  the second's
/// @typeparam TResult  what `combine` makes
public List<TResult> Zip<TFirst, TSecond, TResult>(
    IEnumerable<TFirst> first, IEnumerable<TSecond> second, Func<TFirst, TSecond, TResult> combine)
{
    TFirst[] left = ToArray(first);
    TSecond[] right = ToArray(second);
    nuint shorter = left.Length < right.Length ? left.Length : right.Length;

    var zipped = new List<TResult>();
    for (nuint i = 0u; i < shorter; i++)
        zipped.Add(combine(left[i], right[i]));
    return zipped;
}

/// The elements in arrays of `size`, the last holding what is left. Aborts
/// when `size` is zero.
///
/// @typeparam T  the element type; nothing is asked of it
public List<T[]> Chunk<T>(IEnumerable<T> items, nuint size)
{
    if (size == 0u)
        sl_fail("Chunk: the size is zero");

    T[] all = ToArray(items);
    var chunks = new List<T[]>();
    for (nuint start = 0u; start < all.Length; start += size)
    {
        nuint length = all.Length - start < size ? all.Length - start : size;
        ReadOnlySpan<T> part = all[start:][:length];
        chunks.Add(part.ToArray());
    }
    return chunks;
}

/// The elements up to the first the predicate refuses.
///
/// @typeparam T  the element type; nothing is asked of it
public List<T> TakeWhile<T>(IEnumerable<T> items, Predicate<T> keep)
{
    var taken = new List<T>();
    foreach (var item in items)
    {
        if (!keep(item))
            return taken;
        taken.Add(item);
    }
    return taken;
}

/// The elements from the first the predicate refuses.
///
/// @typeparam T  the element type; nothing is asked of it
public List<T> SkipWhile<T>(IEnumerable<T> items, Predicate<T> skip)
{
    var rest = new List<T>();
    bool skipping = true;
    foreach (var item in items)
    {
        if (skipping && skip(item))
            continue;
        skipping = false;
        rest.Add(item);
    }
    return rest;
}

/// The last `count` elements, or all of them if there are fewer.
///
/// @typeparam T  the element type; nothing is asked of it
public List<T> TakeLast<T>(IEnumerable<T> items, nuint count)
{
    T[] all = ToArray(items);
    nuint from = count < all.Length ? all.Length - count : 0u;
    return ToList(all[from:]);
}

/// All but the last `count` elements, or nothing if there are fewer.
///
/// @typeparam T  the element type; nothing is asked of it
public List<T> SkipLast<T>(IEnumerable<T> items, nuint count)
{
    T[] all = ToArray(items);
    nuint to = count < all.Length ? all.Length - count : 0u;
    return ToList(all[:to]);
}

/// Every element of what `select` makes of each element, one after another.
///
/// @typeparam T        the element type
/// @typeparam TResult  the element type of what `select` makes
public List<TResult> SelectMany<T, TResult>(IEnumerable<T> items, Func<T, IEnumerable<TResult>> select)
{
    var flat = new List<TResult>();
    foreach (var item in items)
    {
        foreach (var inner in select(item))
            flat.Add(inner);
    }
    return flat;
}

/// The first element of each key `keySelector` gives, in order.
///
/// @typeparam T     the element type; nothing is asked of it
/// @typeparam TKey  the key, which a `HashSet` must be able to hold
public List<T> DistinctBy<T, TKey>(IEnumerable<T> items, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
{
    var seen = new HashSet<TKey>();
    var kept = new List<T>();
    foreach (var item in items)
    {
        if (seen.Add(keySelector(item)))
            kept.Add(item);
    }
    return kept;
}

/// The distinct elements of both, first's first.
///
/// @typeparam T  the element type, which a `HashSet` must be able to hold
public List<T> Union<T>(IEnumerable<T> first, IEnumerable<T> second) where T : IEquatable<T>, IHashable =>
    UnionBy(first, second, (item) => item);

/// The distinct elements of both, by key, first's first.
///
/// @typeparam T     the element type; nothing is asked of it
/// @typeparam TKey  the key, which a `HashSet` must be able to hold
public List<T> UnionBy<T, TKey>(IEnumerable<T> first, IEnumerable<T> second, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
{
    var seen = new HashSet<TKey>();
    var kept = new List<T>();
    foreach (var item in first)
    {
        if (seen.Add(keySelector(item)))
            kept.Add(item);
    }
    foreach (var item in second)
    {
        if (seen.Add(keySelector(item)))
            kept.Add(item);
    }
    return kept;
}

/// The distinct elements of `first` that are also in `second`.
///
/// @typeparam T  the element type, which a `HashSet` must be able to hold
public List<T> Intersect<T>(IEnumerable<T> first, IEnumerable<T> second) where T : IEquatable<T>, IHashable =>
    IntersectBy(first, second, (item) => item);

/// The distinct elements of `first` whose key is among `keys`.
///
/// @typeparam T     the element type; nothing is asked of it
/// @typeparam TKey  the key, which a `HashSet` must be able to hold
public List<T> IntersectBy<T, TKey>(IEnumerable<T> first, IEnumerable<TKey> keys, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
{
    var wanted = new HashSet<TKey>();
    foreach (var key in keys)
        wanted.Add(key);

    var kept = new List<T>();
    foreach (var item in first)
    {
        if (wanted.Remove(keySelector(item)))
            kept.Add(item);
    }
    return kept;
}

/// The distinct elements of `first` that are not in `second`.
///
/// @typeparam T  the element type, which a `HashSet` must be able to hold
public List<T> Except<T>(IEnumerable<T> first, IEnumerable<T> second) where T : IEquatable<T>, IHashable =>
    ExceptBy(first, second, (item) => item);

/// The distinct elements of `first` whose key is not among `keys`.
///
/// @typeparam T     the element type; nothing is asked of it
/// @typeparam TKey  the key, which a `HashSet` must be able to hold
public List<T> ExceptBy<T, TKey>(IEnumerable<T> first, IEnumerable<TKey> keys, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
{
    var seen = new HashSet<TKey>();
    foreach (var key in keys)
        seen.Add(key);

    var kept = new List<T>();
    foreach (var item in first)
    {
        if (seen.Add(keySelector(item)))
            kept.Add(item);
    }
    return kept;
}
