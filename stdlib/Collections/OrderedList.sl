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

/// A list `OrderBy` made, which remembers the order so that `ThenBy` can
/// break its ties: C#'s `IOrderedEnumerable`.
///
///     var sorted = ThenBy(OrderBy(people, (p) => p.Surname), (p) => p.Given);
///
/// It is a `List<T>`, and anything that takes one takes it.
///
/// @typeparam T  the element type
public class OrderedList<T> : List<T>
{
    private Comparison<T> _order;

    OrderedList(Comparison<T> order)
    {
        _order = order;
    }

    /// The order the elements are in.
    public Comparison<T> Order => _order;
}

/// The elements in the order `order` gives, stably.
OrderedList<T> SortedBy<T>(T[] copy, Comparison<T> order)
{
    Sort(copy, order);
    var sorted = new OrderedList<T>(order);
    foreach (var item in copy)
        sorted.Add(item);
    return sorted;
}

/// Ties in `first` broken by `then`.
Comparison<T> Then<T>(Comparison<T> first, Comparison<T> then) =>
    (a, b) =>
    {
        int order = first(a, b);
        return order != 0 ? order : then(a, b);
    };

/// The elements of an ordered list, ties broken by the key `keySelector`
/// gives, smallest first.
///
/// @typeparam T     the element type; nothing is asked of it
/// @typeparam TKey  the key, which must order itself
public OrderedList<T> ThenBy<T, TKey>(OrderedList<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey> =>
    SortedBy(ToArray(items), Then(items.Order, (a, b) => keySelector(a).CompareTo(keySelector(b))));

/// The elements of an ordered list, ties broken by the key `keySelector`
/// gives, largest first.
///
/// @typeparam T     the element type; nothing is asked of it
/// @typeparam TKey  the key, which must order itself
public OrderedList<T> ThenByDescending<T, TKey>(OrderedList<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey> =>
    SortedBy(ToArray(items), Then(items.Order, (a, b) => keySelector(b).CompareTo(keySelector(a))));

/// The elements of an ordered list, ties broken by `order`.
///
/// @typeparam T  the element type; the comparison orders it
public OrderedList<T> ThenBy<T>(OrderedList<T> items, Comparison<T> order) =>
    SortedBy(ToArray(items), Then(items.Order, order));

/// The elements by the key `keySelector` gives, smallest first, stably.
///
/// @typeparam T     the element type; nothing is asked of it
/// @typeparam TKey  the key, which must order itself
/// @see Collections.ThenBy
public OrderedList<T> OrderBy<T, TKey>(ReadOnlySpan<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey> =>
    SortedBy(ToArray(items), (a, b) => keySelector(a).CompareTo(keySelector(b)));

/// The elements by the key `keySelector` gives, largest first, stably.
///
/// @typeparam T     the element type; nothing is asked of it
/// @typeparam TKey  the key, which must order itself
public OrderedList<T> OrderByDescending<T, TKey>(ReadOnlySpan<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey> =>
    SortedBy(ToArray(items), (a, b) => keySelector(b).CompareTo(keySelector(a)));

/// The elements by their own ordering, smallest first, stably.
///
/// @typeparam T  the element type, which must order itself
public OrderedList<T> Order<T>(ReadOnlySpan<T> items) where T : IComparable<T> =>
    SortedBy(ToArray(items), (a, b) => a.CompareTo(b));

/// The elements by their own ordering, largest first, stably.
///
/// @typeparam T  the element type, which must order itself
public OrderedList<T> OrderDescending<T>(ReadOnlySpan<T> items) where T : IComparable<T> =>
    SortedBy(ToArray(items), (a, b) => b.CompareTo(a));

/// The elements by the key `keySelector` gives, smallest first, stably.
///
/// @typeparam T     the element type; nothing is asked of it
/// @typeparam TKey  the key, which must order itself
/// @see Collections.ThenBy
public OrderedList<T> OrderBy<T, TKey>(IEnumerable<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey> =>
    SortedBy(ToArray(items), (a, b) => keySelector(a).CompareTo(keySelector(b)));

/// The elements by the key `keySelector` gives, largest first, stably.
///
/// @typeparam T     the element type; nothing is asked of it
/// @typeparam TKey  the key, which must order itself
public OrderedList<T> OrderByDescending<T, TKey>(IEnumerable<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey> =>
    SortedBy(ToArray(items), (a, b) => keySelector(b).CompareTo(keySelector(a)));

/// The elements by their own ordering, smallest first, stably.
///
/// @typeparam T  the element type, which must order itself
public OrderedList<T> Order<T>(IEnumerable<T> items) where T : IComparable<T> =>
    SortedBy(ToArray(items), (a, b) => a.CompareTo(b));

/// The elements by their own ordering, largest first, stably.
///
/// @typeparam T  the element type, which must order itself
public OrderedList<T> OrderDescending<T>(IEnumerable<T> items) where T : IComparable<T> =>
    SortedBy(ToArray(items), (a, b) => b.CompareTo(a));
