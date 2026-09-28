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

/// The elements `GroupBy` put together under one key: C#'s `IGrouping`.
///
///     foreach (var group in GroupBy(people, (p) => p.City))
///         Console.WriteLine(group.Key + ": " + Text.FromInteger((int)group.Count));
///
/// A sequence of its own, so every operator here works on one.
///
/// @typeparam TKey      what the elements share
/// @typeparam TElement  what was grouped
public class Grouping<TKey, TElement> : IEnumerable<TElement>
{
    private List<TElement> _elements;

    Grouping(TKey key)
    {
        Key = key;
        _elements = new List<TElement>();
    }

    /// What every element here was grouped by.
    public TKey Key { get; }

    /// How many elements share the key.
    public nuint Count => _elements.Count;

    /// The element at `index`, in the order they were met, aborting past the end.
    public TElement this[nuint index] => _elements[index];

    /// Walks the elements in the order they were met.
    public IEnumerator<TElement> GetEnumerator() => _elements.GetEnumerator();

    void Add(TElement element) => _elements.Add(element);
}

/// The elements put together by the key `keySelector` gives each, the groups
/// in the order their keys were first met.
///
/// @typeparam T     the element type; nothing is asked of it
/// @typeparam TKey  the key, which a `Dictionary` must be able to hold
public List<Grouping<TKey, T>> GroupBy<T, TKey>(ReadOnlySpan<T> items, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable =>
    GroupBy(items, keySelector, (item) => item);

/// What `elementSelector` makes of each element, put together by the key
/// `keySelector` gives it.
///
/// @typeparam T         the element type; nothing is asked of it
/// @typeparam TKey      the key, which a `Dictionary` must be able to hold
/// @typeparam TElement  what is grouped
public List<Grouping<TKey, TElement>> GroupBy<T, TKey, TElement>(
    ReadOnlySpan<T> items, Func<T, TKey> keySelector, Func<T, TElement> elementSelector)
    where TKey : IEquatable<TKey>, IHashable
{
    var byKey = new Dictionary<TKey, Grouping<TKey, TElement>>();
    var groups = new List<Grouping<TKey, TElement>>();
    foreach (var item in items)
    {
        var key = keySelector(item);
        if (byKey.TryGetValue(key) is not Some existing)
        {
            var made = new Grouping<TKey, TElement>(key);
            byKey.Add(key, made);
            groups.Add(made);
            made.Add(elementSelector(item));
            continue;
        }
        existing.Value.Add(elementSelector(item));
    }
    return groups;
}

/// A dictionary from the key `keySelector` gives each element to the element,
/// aborting on a key given twice.
///
/// @typeparam T     the element type; nothing is asked of it
/// @typeparam TKey  the key, which a `Dictionary` must be able to hold
public Dictionary<TKey, T> ToDictionary<T, TKey>(ReadOnlySpan<T> items, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable =>
    ToDictionary(items, keySelector, (item) => item);

/// A dictionary from the key `keySelector` gives each element to what
/// `valueSelector` makes of it, aborting on a key given twice.
///
/// @typeparam T       the element type; nothing is asked of it
/// @typeparam TKey    the key, which a `Dictionary` must be able to hold
/// @typeparam TValue  the value
public Dictionary<TKey, TValue> ToDictionary<T, TKey, TValue>(
    ReadOnlySpan<T> items, Func<T, TKey> keySelector, Func<T, TValue> valueSelector)
    where TKey : IEquatable<TKey>, IHashable
{
    var made = new Dictionary<TKey, TValue>();
    foreach (var item in items)
    {
        if (!made.Add(keySelector(item), valueSelector(item)))
            sl_fail("ToDictionary: a key was given twice");
    }
    return made;
}

/// The distinct elements, as a set.
///
/// @typeparam T  the element type, which a `HashSet` must be able to hold
public HashSet<T> ToHashSet<T>(ReadOnlySpan<T> items) where T : IEquatable<T>, IHashable
{
    var made = new HashSet<T>();
    foreach (var item in items)
        made.Add(item);
    return made;
}

/// The elements put together by the key `keySelector` gives each, the groups
/// in the order their keys were first met.
///
/// @typeparam T     the element type; nothing is asked of it
/// @typeparam TKey  the key, which a `Dictionary` must be able to hold
public List<Grouping<TKey, T>> GroupBy<T, TKey>(IEnumerable<T> items, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable =>
    GroupBy(items, keySelector, (item) => item);

/// What `elementSelector` makes of each element, put together by the key
/// `keySelector` gives it.
///
/// @typeparam T         the element type; nothing is asked of it
/// @typeparam TKey      the key, which a `Dictionary` must be able to hold
/// @typeparam TElement  what is grouped
public List<Grouping<TKey, TElement>> GroupBy<T, TKey, TElement>(
    IEnumerable<T> items, Func<T, TKey> keySelector, Func<T, TElement> elementSelector)
    where TKey : IEquatable<TKey>, IHashable
{
    var byKey = new Dictionary<TKey, Grouping<TKey, TElement>>();
    var groups = new List<Grouping<TKey, TElement>>();
    foreach (var item in items)
    {
        var key = keySelector(item);
        if (byKey.TryGetValue(key) is not Some existing)
        {
            var made = new Grouping<TKey, TElement>(key);
            byKey.Add(key, made);
            groups.Add(made);
            made.Add(elementSelector(item));
            continue;
        }
        existing.Value.Add(elementSelector(item));
    }
    return groups;
}

/// A dictionary from the key `keySelector` gives each element to the element,
/// aborting on a key given twice.
///
/// @typeparam T     the element type; nothing is asked of it
/// @typeparam TKey  the key, which a `Dictionary` must be able to hold
public Dictionary<TKey, T> ToDictionary<T, TKey>(IEnumerable<T> items, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable =>
    ToDictionary(items, keySelector, (item) => item);

/// A dictionary from the key `keySelector` gives each element to what
/// `valueSelector` makes of it, aborting on a key given twice.
///
/// @typeparam T       the element type; nothing is asked of it
/// @typeparam TKey    the key, which a `Dictionary` must be able to hold
/// @typeparam TValue  the value
public Dictionary<TKey, TValue> ToDictionary<T, TKey, TValue>(
    IEnumerable<T> items, Func<T, TKey> keySelector, Func<T, TValue> valueSelector)
    where TKey : IEquatable<TKey>, IHashable
{
    var made = new Dictionary<TKey, TValue>();
    foreach (var item in items)
    {
        if (!made.Add(keySelector(item), valueSelector(item)))
            sl_fail("ToDictionary: a key was given twice");
    }
    return made;
}

/// The distinct elements, as a set.
///
/// @typeparam T  the element type, which a `HashSet` must be able to hold
public HashSet<T> ToHashSet<T>(IEnumerable<T> items) where T : IEquatable<T>, IHashable
{
    var made = new HashSet<T>();
    foreach (var item in items)
        made.Add(item);
    return made;
}
