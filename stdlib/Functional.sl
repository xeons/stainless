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

/// Doing something to every element.
///
/// Every one of these takes a `closure` (§2.14.1), which is a method and the
/// object it belongs to. That means both of these work, and mean the same
/// thing:
///
///     Filter(names, (n) => n.ByteLength() > 3u);   // a lambda that captures
///     ForEach(names, report.Add);                  // a method bound to an object
///
/// The second is what the older shape could not do. These were one-method
/// interfaces until closures could be generic, and an interface needs an object
/// that implements it -- so passing an existing method meant writing a class
/// whose only reason to exist was to carry it.
///
/// **Eager, not lazy.** Every one of these walks its input to the end and
/// returns a `List<T>`, so `Filter(...)` then `Map(...)` builds two lists. Lazy
/// chaining wants generators -- a `yield` that suspends a function mid-body --
/// and Stainless has none. Saying so is better than implying otherwise with a
/// name borrowed from a language that does.
module Standard.Collections;

// The shapes a lambda takes here -- `Func`, `Predicate`, `Action`, `Fold` and
// `Comparer` -- are declared in `Standard`, and need no import to reach.

// ---------------------------------------------------------- over an array

/// The elements the predicate keeps, in the order they were in.
///
/// An array converts to a slice of the whole of itself, so this takes both.
public List<T> Filter<T>(T[:] items, Predicate<T> keep) {
    var kept = new List<T>();
    foreach (var item in items) {
        if (keep(item)) { kept.Add(item); }
    }
    return kept;
}

/// Every element put through the transform.
///
///     var spelled = Map(numbers, n => Text.FromInteger((long)n));
///
/// `R` appears nowhere but in the transform's result, so working it out means
/// binding the lambda's body -- which cannot happen until `T` has given the
/// lambda its parameter type. The compiler does the two in that order.
public List<R> Map<T, R>(T[:] items, Func<T, R> transform) {
    var mapped = new List<R>();
    foreach (var item in items) { mapped.Add(transform(item)); }
    return mapped;
}

/// Everything folded into one value, left to right. The seed decides the
/// result type, so `A` is settled before the lambda is looked at.
///
///     long total = Reduce(numbers, (long)0, (sum, n) => sum + (long)n);
public A Reduce<T, A>(T[:] items, A seed, Fold<A, T> combine) {
    var total = seed;
    foreach (var item in items) { total = combine(total, item); }
    return total;
}

/// Whether any element satisfies the predicate. Stops at the first that does.
public bool Any<T>(T[:] items, Predicate<T> test) {
    foreach (var item in items) {
        if (test(item)) { return true; }
    }
    return false;
}

/// Whether every element does. Stops at the first that does not, and is true
/// of an empty input.
public bool All<T>(T[:] items, Predicate<T> test) {
    foreach (var item in items) {
        if (!test(item)) { return false; }
    }
    return true;
}

/// How many satisfy the predicate.
public nuint CountWhere<T>(T[:] items, Predicate<T> test) {
    nuint found = 0u;
    foreach (var item in items) {
        if (test(item)) { found += 1u; }
    }
    return found;
}

/// The first element satisfying the predicate, or `fallback` if none does.
///
/// The reader that needs no check, because it supplies its own answer. `Find`
/// is the one to reach for when "there was none" is a different outcome rather
/// than a different value.
public T FirstOr<T>(T[:] items, Predicate<T> test, T fallback) {
    foreach (var item in items) {
        if (test(item)) { return item; }
    }
    return fallback;
}

/// The first element satisfying the predicate, if there is one.
///
///     if (Find(people, (p) => p.Age > 65) is Some found) { ... }
///
/// An `Optional<T>` rather than a fallback: a struct has no null to stand for
/// "none" (§2.5), and inventing a value that means it is how a caller comes to
/// treat a real answer as a miss.
public Optional<T> Find<T>(T[:] items, Predicate<T> test) {
    foreach (var item in items) {
        if (test(item)) { return Some(item); }
    }
    return None;
}

/// Where the first element satisfying the predicate is, if it is there.
public Optional<nuint> IndexWhere<T>(T[:] items, Predicate<T> test) {
    for (nuint i = 0u; i < items.Length; i++) {
        if (test(items[i])) { return Some(i); }
    }
    return None;
}

/// Runs the action over every element.
public void ForEach<T>(T[:] items, Action<T> body) {
    foreach (var item in items) { body(item); }
}

/// The first `count` elements, or all of them if there are fewer.
public List<T> Take<T>(T[:] items, nuint count) {
    var taken = new List<T>();
    nuint limit = count < items.Length ? count : items.Length;
    for (nuint i = 0u; i < limit; i += 1u) { taken.Add(items[i]); }
    return taken;
}

/// Everything after the first `count` elements, or nothing if there are fewer.
public List<T> Skip<T>(T[:] items, nuint count) {
    var rest = new List<T>();
    for (nuint i = count; i < items.Length; i += 1u) { rest.Add(items[i]); }
    return rest;
}

// ------------------------------------------------------ over any sequence

/// The same, for anything with a `GetEnumerator()` that names its shape --
/// `List<T>`, `Queue<T>`, `Stack<T>`, `LinkedList<T>`, `HashSet<T>` and
/// `SortedList<K, V>` all do.
public List<T> Filter<T>(IEnumerable<T> items, Predicate<T> keep) {
    var kept = new List<T>();
    foreach (var item in items) {
        if (keep(item)) { kept.Add(item); }
    }
    return kept;
}

/// Every element put through the transform, over any sequence.
public List<R> Map<T, R>(IEnumerable<T> items, Func<T, R> transform) {
    var mapped = new List<R>();
    foreach (var item in items) { mapped.Add(transform(item)); }
    return mapped;
}

/// Everything folded into one value, left to right, over any sequence.
public A Reduce<T, A>(IEnumerable<T> items, A seed, Fold<A, T> combine) {
    var total = seed;
    foreach (var item in items) { total = combine(total, item); }
    return total;
}

/// Whether any element satisfies the predicate, over any sequence. Stops at
/// the first that does, so the rest of the sequence is never walked.
public bool Any<T>(IEnumerable<T> items, Predicate<T> test) {
    foreach (var item in items) {
        if (test(item)) { return true; }
    }
    return false;
}

/// Whether every element does, over any sequence. Stops at the first that
/// does not, and is true of an empty sequence.
public bool All<T>(IEnumerable<T> items, Predicate<T> test) {
    foreach (var item in items) {
        if (!test(item)) { return false; }
    }
    return true;
}

/// How many satisfy the predicate, over any sequence. Walks all of it.
public nuint CountWhere<T>(IEnumerable<T> items, Predicate<T> test) {
    nuint found = 0u;
    foreach (var item in items) {
        if (test(item)) { found += 1u; }
    }
    return found;
}

/// The first element satisfying the predicate, or `fallback` if none does,
/// over any sequence. A fallback equal to a real element is indistinguishable
/// from a miss; `Find` is the overload that tells them apart, and it takes a
/// slice rather than a sequence.
public T FirstOr<T>(IEnumerable<T> items, Predicate<T> test, T fallback) {
    foreach (var item in items) {
        if (test(item)) { return item; }
    }
    return fallback;
}

/// Runs the action over every element of any sequence.
public void ForEach<T>(IEnumerable<T> items, Action<T> body) {
    foreach (var item in items) { body(item); }
}

/// Everything in the sequence, as a list. The one that makes a `Queue` or a
/// `HashSet` usable with the array overloads above.
public List<T> ToList<T>(IEnumerable<T> items) {
    var all = new List<T>();
    foreach (var item in items) { all.Add(item); }
    return all;
}

/// And a slice, which an array converts to. Not an overload of the above by
/// accident: a slice is not an `IEnumerable`, so nothing is ever both.
public List<T> ToList<T>(T[:] items) {
    var all = new List<T>();
    foreach (var item in items) { all.Add(item); }
    return all;
}


// ------------------------------------------------------- ending a chain

// Everything above answers with a `List<T>`, so everything here takes one --
// as an `IEnumerable<T>`, which is what a `List` is and what a `Queue`, a
// `HashSet` and a `SortedList` are too. The slice overloads beside them are
// what an array reaches, an array converting to a slice and not to a sequence.

/// Everything in the sequence, as an array.
///
/// One `IEnumerable` overload rather than an `IReadOnlyList` one as well: a
/// `List<T>` is both, so a pair would be ambiguous at exactly the type a chain
/// hands over. That is why `ToList` takes only the sequence too.
public T[] ToArray<T>(IEnumerable<T> items) {
    var all = ToList(items);
    var array = new T[all.Count()];
    for (nuint i = 0u; i < all.Count(); i++) { array[i] = all.At(i); }
    return array;
}

/// The same for a slice, which is not an `IEnumerable` and so does not collide.
public T[] ToArray<T>(T[:] items) {
    var array = new T[items.Length];
    for (nuint i = 0u; i < items.Length; i++) { array[i] = items[i]; }
    return array;
}

/// The elements, in order, with later repeats left out.
///
/// O(n²) in comparisons, which is what asking nothing of `T` but `IEquatable`
/// costs. A `HashSet<T>` does it in one pass and wants `IHashable` as well;
/// this is the one to reach for at the sizes a chain works at.
public List<T> Distinct<T>(T[:] items) where T : IEquatable<T> {
    var seen = new List<T>();
    foreach (var item in items) {
        if (IndexOf(seen, item).IsEmpty()) { seen.Add(item); }
    }
    return seen;
}

/// The elements, in order, with later repeats left out, over any sequence.
/// O(n squared) in comparisons, as the slice overload is.
public List<T> Distinct<T>(IEnumerable<T> items) where T : IEquatable<T> {
    var seen = new List<T>();
    foreach (var item in items) {
        if (IndexOf(seen, item).IsEmpty()) { seen.Add(item); }
    }
    return seen;
}

/// The elements ordered by what `order` says, leaving the input alone.
///
/// `Sort` orders in place, which a chain cannot use: what is being chained
/// from is usually somebody else's array. This copies first, and is stable for
/// the reason `Sort` is.
public List<T> OrderBy<T>(T[:] items, Comparer<T> order) {
    var copy = new T[items.Length];
    for (nuint i = 0u; i < items.Length; i++) { copy[i] = items[i]; }

    Sort(copy, order);
    return ToList(copy);
}

/// The elements ordered by what `order` says, over any sequence, leaving the
/// input alone. Copies into an array first, so it costs one.
public List<T> OrderBy<T>(IEnumerable<T> items, Comparer<T> order) {
    var copy = ToArray(items);
    Sort(copy, order);
    return ToList(copy);
}

/// The first `count` elements, or all of them if there are fewer.
public List<T> Take<T>(IEnumerable<T> items, nuint count) {
    var kept = new List<T>();
    foreach (var item in items) {
        if (kept.Count() >= count) { return kept; }
        kept.Add(item);
    }
    return kept;
}

/// Everything after the first `count`.
public List<T> Skip<T>(IEnumerable<T> items, nuint count) {
    var kept = new List<T>();
    nuint seen = 0u;
    foreach (var item in items) {
        if (seen >= count) { kept.Add(item); }
        seen++;
    }
    return kept;
}

// ----------------------------------------------------------- other names

// The same work under the names C# gave it, for a reader arriving from LINQ.
//
// Each body is written out rather than calling the original: `Map(items,
// transform)` cannot infer `R` from a `Func<T, R>` value, because the
// inference reads a lambda's body and there is no lambda here.

/// `Filter`, spelled as LINQ spells it.
public List<T> Where<T>(T[:] items, Predicate<T> keep) {
    var kept = new List<T>();
    foreach (var item in items) {
        if (keep(item)) { kept.Add(item); }
    }
    return kept;
}

/// `Filter` over any sequence, spelled as LINQ spells it.
public List<T> Where<T>(IEnumerable<T> items, Predicate<T> keep) {
    var kept = new List<T>();
    foreach (var item in items) {
        if (keep(item)) { kept.Add(item); }
    }
    return kept;
}

/// `Map`, spelled as LINQ spells it.
public List<R> Select<T, R>(T[:] items, Func<T, R> transform) {
    var made = new List<R>();
    foreach (var item in items) { made.Add(transform(item)); }
    return made;
}

/// `Map` over any sequence, spelled as LINQ spells it.
public List<R> Select<T, R>(IEnumerable<T> items, Func<T, R> transform) {
    var made = new List<R>();
    foreach (var item in items) { made.Add(transform(item)); }
    return made;
}

/// `Reduce`, spelled as LINQ spells it.
public A Aggregate<T, A>(T[:] items, A seed, Fold<A, T> combine) {
    var total = seed;
    foreach (var item in items) { total = combine(total, item); }
    return total;
}

/// `Reduce` over any sequence, spelled as LINQ spells it.
public A Aggregate<T, A>(IEnumerable<T> items, A seed, Fold<A, T> combine) {
    var total = seed;
    foreach (var item in items) { total = combine(total, item); }
    return total;
}
