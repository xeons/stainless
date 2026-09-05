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

// Doing something to every element.
//
// A lambda takes its type from what it is assigned to, and an interface with
// exactly one method is one of the two things it may become (§2.14). So these
// are ordinary generic interfaces, and `Filter(names, n => n.Length() > 3u)`
// works with no function type in the language and no special case in the
// compiler.
//
// **Eager, not lazy.** Every one of these walks its input to the end and
// returns a `List<T>`, so `Filter(...)` then `Map(...)` builds two lists. Lazy
// chaining wants generators -- a `yield` that suspends a function mid-body --
// and Stainless has none. Saying so is better than implying otherwise with a
// name borrowed from a language that does.
module Standard.Collections;

// ------------------------------------------------------- the shapes of work

/// Turns a T into an R. The transform half of `Map`.
public interface IFunc<T, R> { R Apply(T value); }

/// Answers a question about a T.
public interface IPredicate<T> { bool Test(T value); }

/// Does something with a T and returns nothing.
public interface IAction<T> { void Run(T value); }

/// Folds one T into a running A. Two parameters rather than one, because a
/// fold is the one shape that carries something along with it.
public interface IFold<A, T> { A Apply(A total, T value); }

/// Orders two Ts: negative if `left` comes first, positive if `right` does,
/// zero if neither.
///
/// This is what lets a type be sorted more than one way, and what lets a type
/// that implements no interface be sorted at all.
public interface IComparer<T> { int Compare(T left, T right); }

// ---------------------------------------------------------- over an array

/// The elements the predicate keeps, in the order they were in.
///
/// An array converts to a slice of the whole of itself, so this takes both.
public List<T> Filter<T>(T[:] items, IPredicate<T> keep) {
    var kept = new List<T>();
    foreach (var item in items) {
        if (keep.Test(item)) { kept.Add(item); }
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
public List<R> Map<T, R>(T[:] items, IFunc<T, R> transform) {
    var mapped = new List<R>();
    foreach (var item in items) { mapped.Add(transform.Apply(item)); }
    return mapped;
}

/// Everything folded into one value, left to right. The seed decides the
/// result type, so `A` is settled before the lambda is looked at.
///
///     long total = Reduce(numbers, (long)0, (sum, n) => sum + (long)n);
public A Reduce<T, A>(T[:] items, A seed, IFold<A, T> combine) {
    var total = seed;
    foreach (var item in items) { total = combine.Apply(total, item); }
    return total;
}

/// Whether any element satisfies the predicate. Stops at the first that does.
public bool Any<T>(T[:] items, IPredicate<T> test) {
    foreach (var item in items) {
        if (test.Test(item)) { return true; }
    }
    return false;
}

/// Whether every element does. Stops at the first that does not, and is true
/// of an empty input.
public bool All<T>(T[:] items, IPredicate<T> test) {
    foreach (var item in items) {
        if (!test.Test(item)) { return false; }
    }
    return true;
}

/// How many satisfy the predicate.
public nuint CountWhere<T>(T[:] items, IPredicate<T> test) {
    nuint found = 0u;
    foreach (var item in items) {
        if (test.Test(item)) { found += 1u; }
    }
    return found;
}

/// The first element satisfying the predicate, or `fallback` if none does.
///
/// A fallback rather than a nullable, because `T` may be a struct and a
/// `T?` is only ever a reference (§2.5). It is also what the caller usually
/// has to hand anyway.
public T FirstOr<T>(T[:] items, IPredicate<T> test, T fallback) {
    foreach (var item in items) {
        if (test.Test(item)) { return item; }
    }
    return fallback;
}

/// The index of the first element satisfying the predicate, or the length when
/// none does -- the same convention as `IndexOf`.
public nuint IndexWhere<T>(T[:] items, IPredicate<T> test) {
    for (nuint i = 0u; i < items.Length; i += 1u) {
        if (test.Test(items[i])) { return i; }
    }
    return items.Length;
}

/// Runs the action over every element.
public void ForEach<T>(T[:] items, IAction<T> body) {
    foreach (var item in items) { body.Run(item); }
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
public List<T> Filter<T>(IEnumerable<T> items, IPredicate<T> keep) {
    var kept = new List<T>();
    foreach (var item in items) {
        if (keep.Test(item)) { kept.Add(item); }
    }
    return kept;
}

public List<R> Map<T, R>(IEnumerable<T> items, IFunc<T, R> transform) {
    var mapped = new List<R>();
    foreach (var item in items) { mapped.Add(transform.Apply(item)); }
    return mapped;
}

public A Reduce<T, A>(IEnumerable<T> items, A seed, IFold<A, T> combine) {
    var total = seed;
    foreach (var item in items) { total = combine.Apply(total, item); }
    return total;
}

public bool Any<T>(IEnumerable<T> items, IPredicate<T> test) {
    foreach (var item in items) {
        if (test.Test(item)) { return true; }
    }
    return false;
}

public bool All<T>(IEnumerable<T> items, IPredicate<T> test) {
    foreach (var item in items) {
        if (!test.Test(item)) { return false; }
    }
    return true;
}

public nuint CountWhere<T>(IEnumerable<T> items, IPredicate<T> test) {
    nuint found = 0u;
    foreach (var item in items) {
        if (test.Test(item)) { found += 1u; }
    }
    return found;
}

public T FirstOr<T>(IEnumerable<T> items, IPredicate<T> test, T fallback) {
    foreach (var item in items) {
        if (test.Test(item)) { return item; }
    }
    return fallback;
}

public void ForEach<T>(IEnumerable<T> items, IAction<T> body) {
    foreach (var item in items) { body.Run(item); }
}

/// Everything in the sequence, as a list. The one that makes a `Queue` or a
/// `HashSet` usable with the array overloads above.
public List<T> ToList<T>(IEnumerable<T> items) {
    var all = new List<T>();
    foreach (var item in items) { all.Add(item); }
    return all;
}
