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

/// Picking one element out of a sequence, and asking about it as a whole:
/// LINQ's `First`, `Last`, `Single`, `ElementAt`, `Any`, `Count`, `Contains`
/// and `SequenceEqual`.
///
/// Where C# throws because a sequence is empty or holds more than it should,
/// these abort, as an index out of range does: the caller asked for something
/// that is not there. The `OrDefault` forms take the value to answer instead,
/// since a struct has no null to stand for "none"; `Find` answers with an
/// `Optional` when "none" is an outcome rather than a mistake.
module Standard.Collections;

// ------------------------------------------------------------ over a span

/// The first element, aborting when there is none.
///
/// @typeparam T  the element type; nothing is asked of it
/// @see Collections.FirstOrDefault
public T First<T>(ReadOnlySpan<T> items)
{
    if (items.Length == 0u)
        sl_fail("First: the sequence is empty");
    return items[0];
}

/// The first element the predicate accepts, aborting when there is none.
///
/// @typeparam T  the element type; nothing is asked of it
/// @see Collections.Find
public T First<T>(ReadOnlySpan<T> items, Predicate<T> test)
{
    foreach (var item in items)
    {
        if (test(item))
            return item;
    }
    sl_fail("First: no element matches");
    return default(T);
}

/// The first element, or `fallback` when there is none.
///
/// @typeparam T  the element type; nothing is asked of it
public T FirstOrDefault<T>(ReadOnlySpan<T> items, T fallback) =>
    items.Length == 0u ? fallback : items[0];

/// The last element, aborting when there is none.
///
/// @typeparam T  the element type; nothing is asked of it
public T Last<T>(ReadOnlySpan<T> items)
{
    if (items.Length == 0u)
        sl_fail("Last: the sequence is empty");
    return items[^1];
}

/// The last element the predicate accepts, aborting when there is none.
///
/// @typeparam T  the element type; nothing is asked of it
public T Last<T>(ReadOnlySpan<T> items, Predicate<T> test)
{
    for (nuint i = items.Length; i > 0u; i--)
    {
        if (test(items[i - 1u]))
            return items[i - 1u];
    }
    sl_fail("Last: no element matches");
    return default(T);
}

/// The last element, or `fallback` when there is none.
///
/// @typeparam T  the element type; nothing is asked of it
public T LastOrDefault<T>(ReadOnlySpan<T> items, T fallback) =>
    items.Length == 0u ? fallback : items[^1];

/// The last element the predicate accepts, or `fallback` when there is none.
///
/// @typeparam T  the element type; nothing is asked of it
public T LastOrDefault<T>(ReadOnlySpan<T> items, Predicate<T> test, T fallback)
{
    for (nuint i = items.Length; i > 0u; i--)
    {
        if (test(items[i - 1u]))
            return items[i - 1u];
    }
    return fallback;
}

/// The only element, aborting when there is not exactly one.
///
/// @typeparam T  the element type; nothing is asked of it
public T Single<T>(ReadOnlySpan<T> items)
{
    if (items.Length != 1u)
        sl_fail("Single: the sequence does not hold exactly one element");
    return items[0];
}

/// The only element the predicate accepts, aborting when there is not
/// exactly one.
///
/// @typeparam T  the element type; nothing is asked of it
public T Single<T>(ReadOnlySpan<T> items, Predicate<T> test)
{
    if (FindOnly(items, test) is Some only)
        return items[only.Value];
    sl_fail("Single: no element matches");
    return default(T);
}

/// The only element, `fallback` when there is none, and an abort when there
/// is more than one.
///
/// @typeparam T  the element type; nothing is asked of it
public T SingleOrDefault<T>(ReadOnlySpan<T> items, T fallback)
{
    if (items.Length > 1u)
        sl_fail("SingleOrDefault: the sequence holds more than one element");
    return items.Length == 0u ? fallback : items[0];
}

/// The only element the predicate accepts, `fallback` when there is none,
/// and an abort when there is more than one.
///
/// @typeparam T  the element type; nothing is asked of it
public T SingleOrDefault<T>(ReadOnlySpan<T> items, Predicate<T> test, T fallback) =>
    FindOnly(items, test) is Some only ? items[only.Value] : fallback;

/// Where the one element the predicate accepts is, aborting when there are two.
Optional<nuint> FindOnly<T>(ReadOnlySpan<T> items, Predicate<T> test)
{
    Optional<nuint> found = None;
    for (nuint i = 0u; i < items.Length; i++)
    {
        if (!test(items[i]))
            continue;
        if (found.HasValue)
            sl_fail("Single: more than one element matches");
        found = Some(i);
    }
    return found;
}

/// The element at `index`, aborting past the end.
///
/// @typeparam T  the element type; nothing is asked of it
public T ElementAt<T>(ReadOnlySpan<T> items, nuint index) => items[index];

/// The element at `index`, or `fallback` past the end.
///
/// @typeparam T  the element type; nothing is asked of it
public T ElementAtOrDefault<T>(ReadOnlySpan<T> items, nuint index, T fallback) =>
    index < items.Length ? items[index] : fallback;

/// Whether there are any elements at all.
///
/// @typeparam T  the element type; nothing is asked of it
public bool Any<T>(ReadOnlySpan<T> items) => items.Length != 0u;

// ------------------------------------------------------ over any sequence

/// The first element, aborting when there is none.
///
/// @typeparam T  the element type; nothing is asked of it
/// @see Collections.FirstOrDefault
public T First<T>(IEnumerable<T> items)
{
    foreach (var item in items)
        return item;
    sl_fail("First: the sequence is empty");
    return default(T);
}

/// The first element the predicate accepts, aborting when there is none.
///
/// @typeparam T  the element type; nothing is asked of it
/// @see Collections.Find
public T First<T>(IEnumerable<T> items, Predicate<T> test)
{
    foreach (var item in items)
    {
        if (test(item))
            return item;
    }
    sl_fail("First: no element matches");
    return default(T);
}

/// The first element, or `fallback` when there is none.
///
/// @typeparam T  the element type; nothing is asked of it
public T FirstOrDefault<T>(IEnumerable<T> items, T fallback)
{
    foreach (var item in items)
        return item;
    return fallback;
}

/// The last element, aborting when there is none.
///
/// @typeparam T  the element type; nothing is asked of it
public T Last<T>(IEnumerable<T> items) => Last(ToArray(items));

/// The last element the predicate accepts, aborting when there is none.
///
/// @typeparam T  the element type; nothing is asked of it
public T Last<T>(IEnumerable<T> items, Predicate<T> test) => Last(ToArray(items), test);

/// The last element, or `fallback` when there is none.
///
/// @typeparam T  the element type; nothing is asked of it
public T LastOrDefault<T>(IEnumerable<T> items, T fallback) => LastOrDefault(ToArray(items), fallback);

/// The last element the predicate accepts, or `fallback` when there is none.
///
/// @typeparam T  the element type; nothing is asked of it
public T LastOrDefault<T>(IEnumerable<T> items, Predicate<T> test, T fallback) =>
    LastOrDefault(ToArray(items), test, fallback);

/// The only element, aborting when there is not exactly one.
///
/// @typeparam T  the element type; nothing is asked of it
public T Single<T>(IEnumerable<T> items) => Single(ToArray(items));

/// The only element the predicate accepts, aborting when there is not
/// exactly one.
///
/// @typeparam T  the element type; nothing is asked of it
public T Single<T>(IEnumerable<T> items, Predicate<T> test) => Single(ToArray(items), test);

/// The only element, `fallback` when there is none, and an abort when there
/// is more than one.
///
/// @typeparam T  the element type; nothing is asked of it
public T SingleOrDefault<T>(IEnumerable<T> items, T fallback) =>
    SingleOrDefault(ToArray(items), fallback);

/// The only element the predicate accepts, `fallback` when there is none,
/// and an abort when there is more than one.
///
/// @typeparam T  the element type; nothing is asked of it
public T SingleOrDefault<T>(IEnumerable<T> items, Predicate<T> test, T fallback) =>
    SingleOrDefault(ToArray(items), test, fallback);

/// The element at `index`, aborting past the end.
///
/// @typeparam T  the element type; nothing is asked of it
public T ElementAt<T>(IEnumerable<T> items, nuint index)
{
    nuint at = 0u;
    foreach (var item in items)
    {
        if (at == index)
            return item;
        at++;
    }
    sl_array_bounds_fail(index, at);
    return default(T);
}

/// The element at `index`, or `fallback` past the end.
///
/// @typeparam T  the element type; nothing is asked of it
public T ElementAtOrDefault<T>(IEnumerable<T> items, nuint index, T fallback)
{
    nuint at = 0u;
    foreach (var item in items)
    {
        if (at == index)
            return item;
        at++;
    }
    return fallback;
}

/// Whether there are any elements at all.
///
/// @typeparam T  the element type; nothing is asked of it
public bool Any<T>(IEnumerable<T> items)
{
    foreach (var item in items)
        return true;
    return false;
}

/// How many elements there are, walking them to find out.
///
/// @typeparam T  the element type; nothing is asked of it
public nuint Count<T>(IEnumerable<T> items)
{
    nuint count = 0u;
    foreach (var item in items)
        count++;
    return count;
}

/// Whether any element equals `value`.
///
/// @typeparam T  the element type, which must answer whether it equals another
public bool Contains<T>(IEnumerable<T> items, T value) where T : IEquatable<T>
{
    foreach (var item in items)
    {
        if (item.Equals(value))
            return true;
    }
    return false;
}

/// Whether the two hold equal elements in the same order.
///
/// @typeparam T  the element type, which must answer whether it equals another
public bool SequenceEqual<T>(IEnumerable<T> first, IEnumerable<T> second) where T : IEquatable<T> =>
    SequenceEqual(ToArray(first), ToArray(second));
