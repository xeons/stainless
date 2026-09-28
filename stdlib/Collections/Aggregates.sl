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

/// Reducing a sequence to one value: LINQ's `Sum`, `Average`, `Min`, `Max`,
/// `MinBy`, `MaxBy` and the `Aggregate` that takes no seed.
///
/// `Sum` and `Average` are written once per numeric type -- `int`, `long`,
/// `float` and `double` -- as C#'s are, since there is no constraint that says
/// "a number". An integer `Sum` is `checked` and aborts on overflow, where
/// C#'s throws; an `Average` of nothing aborts, as C#'s throws, and a `Sum` of
/// nothing is zero. `Min` and `Max` of nothing abort.
module Standard.Collections;

// --------------------------------------------------------------- sum and average

/// The total of the elements; zero when there are none.
public int Sum(ReadOnlySpan<int> items)
{
    int total = 0;
    foreach (var item in items)
        total = checked(total + item);
    return total;
}

/// The total of what `selector` gives for each element; zero when there are none.
///
/// @typeparam T  the element type; the selector reads the number off it
public int Sum<T>(ReadOnlySpan<T> items, Func<T, int> selector)
{
    int total = 0;
    foreach (var item in items)
        total = checked(total + selector(item));
    return total;
}

/// The mean of the elements, aborting when there are none.
public double Average(ReadOnlySpan<int> items)
{
    double total = 0;
    nuint count = 0u;
    foreach (var item in items)
    {
        total += (double)item;
        count++;
    }
    if (count == 0u)
        sl_fail("Average: the sequence is empty");
    return total / (double)count;
}

/// The mean of what `selector` gives for each element, aborting when there
/// are none.
///
/// @typeparam T  the element type; the selector reads the number off it
public double Average<T>(ReadOnlySpan<T> items, Func<T, int> selector)
{
    double total = 0;
    nuint count = 0u;
    foreach (var item in items)
    {
        total += (double)selector(item);
        count++;
    }
    if (count == 0u)
        sl_fail("Average: the sequence is empty");
    return total / (double)count;
}

/// The total of the elements; zero when there are none.
public int Sum(IEnumerable<int> items)
{
    int total = 0;
    foreach (var item in items)
        total = checked(total + item);
    return total;
}

/// The total of what `selector` gives for each element; zero when there are none.
///
/// @typeparam T  the element type; the selector reads the number off it
public int Sum<T>(IEnumerable<T> items, Func<T, int> selector)
{
    int total = 0;
    foreach (var item in items)
        total = checked(total + selector(item));
    return total;
}

/// The mean of the elements, aborting when there are none.
public double Average(IEnumerable<int> items)
{
    double total = 0;
    nuint count = 0u;
    foreach (var item in items)
    {
        total += (double)item;
        count++;
    }
    if (count == 0u)
        sl_fail("Average: the sequence is empty");
    return total / (double)count;
}

/// The mean of what `selector` gives for each element, aborting when there
/// are none.
///
/// @typeparam T  the element type; the selector reads the number off it
public double Average<T>(IEnumerable<T> items, Func<T, int> selector)
{
    double total = 0;
    nuint count = 0u;
    foreach (var item in items)
    {
        total += (double)selector(item);
        count++;
    }
    if (count == 0u)
        sl_fail("Average: the sequence is empty");
    return total / (double)count;
}

/// The total of the elements; zero when there are none.
public long Sum(ReadOnlySpan<long> items)
{
    long total = 0;
    foreach (var item in items)
        total = checked(total + item);
    return total;
}

/// The total of what `selector` gives for each element; zero when there are none.
///
/// @typeparam T  the element type; the selector reads the number off it
public long Sum<T>(ReadOnlySpan<T> items, Func<T, long> selector)
{
    long total = 0;
    foreach (var item in items)
        total = checked(total + selector(item));
    return total;
}

/// The mean of the elements, aborting when there are none.
public double Average(ReadOnlySpan<long> items)
{
    double total = 0;
    nuint count = 0u;
    foreach (var item in items)
    {
        total += (double)item;
        count++;
    }
    if (count == 0u)
        sl_fail("Average: the sequence is empty");
    return total / (double)count;
}

/// The mean of what `selector` gives for each element, aborting when there
/// are none.
///
/// @typeparam T  the element type; the selector reads the number off it
public double Average<T>(ReadOnlySpan<T> items, Func<T, long> selector)
{
    double total = 0;
    nuint count = 0u;
    foreach (var item in items)
    {
        total += (double)selector(item);
        count++;
    }
    if (count == 0u)
        sl_fail("Average: the sequence is empty");
    return total / (double)count;
}

/// The total of the elements; zero when there are none.
public long Sum(IEnumerable<long> items)
{
    long total = 0;
    foreach (var item in items)
        total = checked(total + item);
    return total;
}

/// The total of what `selector` gives for each element; zero when there are none.
///
/// @typeparam T  the element type; the selector reads the number off it
public long Sum<T>(IEnumerable<T> items, Func<T, long> selector)
{
    long total = 0;
    foreach (var item in items)
        total = checked(total + selector(item));
    return total;
}

/// The mean of the elements, aborting when there are none.
public double Average(IEnumerable<long> items)
{
    double total = 0;
    nuint count = 0u;
    foreach (var item in items)
    {
        total += (double)item;
        count++;
    }
    if (count == 0u)
        sl_fail("Average: the sequence is empty");
    return total / (double)count;
}

/// The mean of what `selector` gives for each element, aborting when there
/// are none.
///
/// @typeparam T  the element type; the selector reads the number off it
public double Average<T>(IEnumerable<T> items, Func<T, long> selector)
{
    double total = 0;
    nuint count = 0u;
    foreach (var item in items)
    {
        total += (double)selector(item);
        count++;
    }
    if (count == 0u)
        sl_fail("Average: the sequence is empty");
    return total / (double)count;
}

/// The total of the elements; zero when there are none.
public float Sum(ReadOnlySpan<float> items)
{
    float total = 0.0f;
    foreach (var item in items)
        total = total + item;
    return total;
}

/// The total of what `selector` gives for each element; zero when there are none.
///
/// @typeparam T  the element type; the selector reads the number off it
public float Sum<T>(ReadOnlySpan<T> items, Func<T, float> selector)
{
    float total = 0.0f;
    foreach (var item in items)
        total = total + selector(item);
    return total;
}

/// The mean of the elements, aborting when there are none.
public float Average(ReadOnlySpan<float> items)
{
    float total = 0;
    nuint count = 0u;
    foreach (var item in items)
    {
        total += (float)item;
        count++;
    }
    if (count == 0u)
        sl_fail("Average: the sequence is empty");
    return total / (float)count;
}

/// The mean of what `selector` gives for each element, aborting when there
/// are none.
///
/// @typeparam T  the element type; the selector reads the number off it
public float Average<T>(ReadOnlySpan<T> items, Func<T, float> selector)
{
    float total = 0;
    nuint count = 0u;
    foreach (var item in items)
    {
        total += (float)selector(item);
        count++;
    }
    if (count == 0u)
        sl_fail("Average: the sequence is empty");
    return total / (float)count;
}

/// The total of the elements; zero when there are none.
public float Sum(IEnumerable<float> items)
{
    float total = 0.0f;
    foreach (var item in items)
        total = total + item;
    return total;
}

/// The total of what `selector` gives for each element; zero when there are none.
///
/// @typeparam T  the element type; the selector reads the number off it
public float Sum<T>(IEnumerable<T> items, Func<T, float> selector)
{
    float total = 0.0f;
    foreach (var item in items)
        total = total + selector(item);
    return total;
}

/// The mean of the elements, aborting when there are none.
public float Average(IEnumerable<float> items)
{
    float total = 0;
    nuint count = 0u;
    foreach (var item in items)
    {
        total += (float)item;
        count++;
    }
    if (count == 0u)
        sl_fail("Average: the sequence is empty");
    return total / (float)count;
}

/// The mean of what `selector` gives for each element, aborting when there
/// are none.
///
/// @typeparam T  the element type; the selector reads the number off it
public float Average<T>(IEnumerable<T> items, Func<T, float> selector)
{
    float total = 0;
    nuint count = 0u;
    foreach (var item in items)
    {
        total += (float)selector(item);
        count++;
    }
    if (count == 0u)
        sl_fail("Average: the sequence is empty");
    return total / (float)count;
}

/// The total of the elements; zero when there are none.
public double Sum(ReadOnlySpan<double> items)
{
    double total = 0.0;
    foreach (var item in items)
        total = total + item;
    return total;
}

/// The total of what `selector` gives for each element; zero when there are none.
///
/// @typeparam T  the element type; the selector reads the number off it
public double Sum<T>(ReadOnlySpan<T> items, Func<T, double> selector)
{
    double total = 0.0;
    foreach (var item in items)
        total = total + selector(item);
    return total;
}

/// The mean of the elements, aborting when there are none.
public double Average(ReadOnlySpan<double> items)
{
    double total = 0;
    nuint count = 0u;
    foreach (var item in items)
    {
        total += (double)item;
        count++;
    }
    if (count == 0u)
        sl_fail("Average: the sequence is empty");
    return total / (double)count;
}

/// The mean of what `selector` gives for each element, aborting when there
/// are none.
///
/// @typeparam T  the element type; the selector reads the number off it
public double Average<T>(ReadOnlySpan<T> items, Func<T, double> selector)
{
    double total = 0;
    nuint count = 0u;
    foreach (var item in items)
    {
        total += (double)selector(item);
        count++;
    }
    if (count == 0u)
        sl_fail("Average: the sequence is empty");
    return total / (double)count;
}

/// The total of the elements; zero when there are none.
public double Sum(IEnumerable<double> items)
{
    double total = 0.0;
    foreach (var item in items)
        total = total + item;
    return total;
}

/// The total of what `selector` gives for each element; zero when there are none.
///
/// @typeparam T  the element type; the selector reads the number off it
public double Sum<T>(IEnumerable<T> items, Func<T, double> selector)
{
    double total = 0.0;
    foreach (var item in items)
        total = total + selector(item);
    return total;
}

/// The mean of the elements, aborting when there are none.
public double Average(IEnumerable<double> items)
{
    double total = 0;
    nuint count = 0u;
    foreach (var item in items)
    {
        total += (double)item;
        count++;
    }
    if (count == 0u)
        sl_fail("Average: the sequence is empty");
    return total / (double)count;
}

/// The mean of what `selector` gives for each element, aborting when there
/// are none.
///
/// @typeparam T  the element type; the selector reads the number off it
public double Average<T>(IEnumerable<T> items, Func<T, double> selector)
{
    double total = 0;
    nuint count = 0u;
    foreach (var item in items)
    {
        total += (double)selector(item);
        count++;
    }
    if (count == 0u)
        sl_fail("Average: the sequence is empty");
    return total / (double)count;
}

// ------------------------------------------------------------- the extremes

/// The smallest element, by its own ordering, aborting when there are none. The
/// first of equals wins.
///
/// @typeparam T  the element type, which must order itself
public T Min<T>(ReadOnlySpan<T> items) where T : IComparable<T>
{
    if (items.Length == 0u)
        sl_fail("Min: the sequence is empty");

    T best = items[0u];
    for (nuint i = 1u; i < items.Length; i++)
    {
        if (items[i].CompareTo(best) < 0)
            best = items[i];
    }
    return best;
}

/// The smallest of what `selector` gives for each element, aborting when there
/// are none.
///
/// @typeparam T        the element type; the selector reads the value off it
/// @typeparam TResult  what is compared, which must order itself
public TResult Min<T, TResult>(ReadOnlySpan<T> items, Func<T, TResult> selector)
    where TResult : IComparable<TResult>
{
    if (items.Length == 0u)
        sl_fail("Min: the sequence is empty");

    TResult best = selector(items[0u]);
    for (nuint i = 1u; i < items.Length; i++)
    {
        var value = selector(items[i]);
        if (value.CompareTo(best) < 0)
            best = value;
    }
    return best;
}

/// The element whose key is the smallest, or none when there are no elements.
/// The first of equal keys wins.
///
/// @typeparam T     the element type; the key selector reads the key off it
/// @typeparam TKey  the key, which must order itself
public Optional<T> MinBy<T, TKey>(ReadOnlySpan<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey>
{
    if (items.Length == 0u)
        return None;

    T best = items[0u];
    TKey bestKey = keySelector(best);
    for (nuint i = 1u; i < items.Length; i++)
    {
        var key = keySelector(items[i]);
        if (key.CompareTo(bestKey) < 0)
        {
            best = items[i];
            bestKey = key;
        }
    }
    return best;
}

/// The largest element, by its own ordering, aborting when there are none. The
/// first of equals wins.
///
/// @typeparam T  the element type, which must order itself
public T Max<T>(ReadOnlySpan<T> items) where T : IComparable<T>
{
    if (items.Length == 0u)
        sl_fail("Max: the sequence is empty");

    T best = items[0u];
    for (nuint i = 1u; i < items.Length; i++)
    {
        if (items[i].CompareTo(best) > 0)
            best = items[i];
    }
    return best;
}

/// The largest of what `selector` gives for each element, aborting when there
/// are none.
///
/// @typeparam T        the element type; the selector reads the value off it
/// @typeparam TResult  what is compared, which must order itself
public TResult Max<T, TResult>(ReadOnlySpan<T> items, Func<T, TResult> selector)
    where TResult : IComparable<TResult>
{
    if (items.Length == 0u)
        sl_fail("Max: the sequence is empty");

    TResult best = selector(items[0u]);
    for (nuint i = 1u; i < items.Length; i++)
    {
        var value = selector(items[i]);
        if (value.CompareTo(best) > 0)
            best = value;
    }
    return best;
}

/// The element whose key is the largest, or none when there are no elements.
/// The first of equal keys wins.
///
/// @typeparam T     the element type; the key selector reads the key off it
/// @typeparam TKey  the key, which must order itself
public Optional<T> MaxBy<T, TKey>(ReadOnlySpan<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey>
{
    if (items.Length == 0u)
        return None;

    T best = items[0u];
    TKey bestKey = keySelector(best);
    for (nuint i = 1u; i < items.Length; i++)
    {
        var key = keySelector(items[i]);
        if (key.CompareTo(bestKey) > 0)
        {
            best = items[i];
            bestKey = key;
        }
    }
    return best;
}

/// The smallest element, by its own ordering, aborting when there are none. The
/// first of equals wins.
///
/// @typeparam T  the element type, which must order itself
public T Min<T>(IEnumerable<T> items) where T : IComparable<T>
{
    var walk = items.GetEnumerator();
    if (!walk.MoveNext())
        sl_fail("Min: the sequence is empty");

    T best = walk.Current;
    while (walk.MoveNext())
    {
        T item = walk.Current;
        if (item.CompareTo(best) < 0)
            best = item;
    }
    return best;
}

/// The smallest of what `selector` gives for each element, aborting when there
/// are none.
///
/// @typeparam T        the element type; the selector reads the value off it
/// @typeparam TResult  what is compared, which must order itself
public TResult Min<T, TResult>(IEnumerable<T> items, Func<T, TResult> selector)
    where TResult : IComparable<TResult>
{
    var walk = items.GetEnumerator();
    if (!walk.MoveNext())
        sl_fail("Min: the sequence is empty");

    TResult best = selector(walk.Current);
    while (walk.MoveNext())
    {
        var value = selector(walk.Current);
        if (value.CompareTo(best) < 0)
            best = value;
    }
    return best;
}

/// The element whose key is the smallest, or none when there are no elements.
/// The first of equal keys wins.
///
/// @typeparam T     the element type; the key selector reads the key off it
/// @typeparam TKey  the key, which must order itself
public Optional<T> MinBy<T, TKey>(IEnumerable<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey>
{
    var walk = items.GetEnumerator();
    if (!walk.MoveNext())
        return None;

    T best = walk.Current;
    TKey bestKey = keySelector(best);
    while (walk.MoveNext())
    {
        T item = walk.Current;
        var key = keySelector(item);
        if (key.CompareTo(bestKey) < 0)
        {
            best = item;
            bestKey = key;
        }
    }
    return best;
}

/// The largest element, by its own ordering, aborting when there are none. The
/// first of equals wins.
///
/// @typeparam T  the element type, which must order itself
public T Max<T>(IEnumerable<T> items) where T : IComparable<T>
{
    var walk = items.GetEnumerator();
    if (!walk.MoveNext())
        sl_fail("Max: the sequence is empty");

    T best = walk.Current;
    while (walk.MoveNext())
    {
        T item = walk.Current;
        if (item.CompareTo(best) > 0)
            best = item;
    }
    return best;
}

/// The largest of what `selector` gives for each element, aborting when there
/// are none.
///
/// @typeparam T        the element type; the selector reads the value off it
/// @typeparam TResult  what is compared, which must order itself
public TResult Max<T, TResult>(IEnumerable<T> items, Func<T, TResult> selector)
    where TResult : IComparable<TResult>
{
    var walk = items.GetEnumerator();
    if (!walk.MoveNext())
        sl_fail("Max: the sequence is empty");

    TResult best = selector(walk.Current);
    while (walk.MoveNext())
    {
        var value = selector(walk.Current);
        if (value.CompareTo(best) > 0)
            best = value;
    }
    return best;
}

/// The element whose key is the largest, or none when there are no elements.
/// The first of equal keys wins.
///
/// @typeparam T     the element type; the key selector reads the key off it
/// @typeparam TKey  the key, which must order itself
public Optional<T> MaxBy<T, TKey>(IEnumerable<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey>
{
    var walk = items.GetEnumerator();
    if (!walk.MoveNext())
        return None;

    T best = walk.Current;
    TKey bestKey = keySelector(best);
    while (walk.MoveNext())
    {
        T item = walk.Current;
        var key = keySelector(item);
        if (key.CompareTo(bestKey) > 0)
        {
            best = item;
            bestKey = key;
        }
    }
    return best;
}

// ---------------------------------------------------------------- aggregate

/// Folds the elements from the first, aborting when there are none: the
/// first element is the seed, and `combine` takes it and each one after.
///
/// @typeparam T  the element type; `combine` does the work
public T Aggregate<T>(ReadOnlySpan<T> items, Func<T, T, T> combine)
{
    if (items.Length == 0u)
        sl_fail("Aggregate: the sequence is empty");

    T total = items[0u];
    for (nuint i = 1u; i < items.Length; i++)
        total = combine(total, items[i]);
    return total;
}

/// Folds the elements from the first, aborting when there are none: the
/// first element is the seed, and `combine` takes it and each one after.
///
/// @typeparam T  the element type; `combine` does the work
public T Aggregate<T>(IEnumerable<T> items, Func<T, T, T> combine)
{
    var walk = items.GetEnumerator();
    if (!walk.MoveNext())
        sl_fail("Aggregate: the sequence is empty");

    T total = walk.Current;
    while (walk.MoveNext())
        total = combine(total, walk.Current);
    return total;
}
