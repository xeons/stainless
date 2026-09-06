// SPDX-License-Identifier: 0BSD
//
// Generic closures and generic delegates.
//
// A `closure` is a method and the object it belongs to (§2.14.1); making one
// generic is what lets a library take "something to call" over a type it does
// not know. `Standard.Collections` is built on five of them, and before this
// existed it could not be: the only generic thing a lambda could become was an
// interface with one method, and an interface needs an *object* that
// implements it -- so passing a method that already existed meant declaring a
// class whose only purpose was to carry it.
//
// Each set of type arguments makes a real type the way `Box<int>` does. There
// is simply much less of it to make: a delegate is a signature and nothing
// else, so an instantiation resolves that signature under the substitution and
// stops -- no members to declare, no layout to compute, a delegate being one
// pointer and a closure always the same two.
module GenericClosures;

import Standard.Console;
import Standard.Collections;

// ------------------------------------------------------------ the shapes

public closure bool Keeps<T>(T value);
public closure R Turns<T, R>(T value);
public closure void Takes<T>(T value);
public closure A Folds<A, T>(A total, T value);

// A generic *delegate* is still one bare function pointer, so it may not
// capture -- which is exactly what makes it a C function pointer.
public delegate int Orders<T>(T left, T right);

// ------------------------------------------------------- what uses them

public List<T> Kept<T>(T[:] items, Keeps<T> ok) {
    var kept = new List<T>();
    foreach (var item in items) {
        if (ok(item)) { kept.Add(item); }
    }
    return kept;
}

/// `R` appears nowhere but in the closure's result, so working it out means
/// binding the lambda's body -- which cannot happen until `T` has given the
/// lambda its parameter type. The signature it is read off is the closure's
/// own rather than an interface method's.
public List<R> Turned<T, R>(T[:] items, Turns<T, R> change) {
    var made = new List<R>();
    foreach (var item in items) { made.Add(change(item)); }
    return made;
}

public void Each<T>(T[:] items, Takes<T> run) {
    foreach (var item in items) { run(item); }
}

public A Folded<A, T>(T[:] items, A seed, Folds<A, T> step) {
    var total = seed;
    foreach (var item in items) { total = step(total, item); }
    return total;
}

public int Best<T>(T[:] items, Orders<T> order) {
    int best = 0;
    for (nuint i = 1u; i < items.Length; i++) {
        if (order(items[i], items[(nuint)best]) > 0) { best = (int)i; }
    }
    return best;
}

// A generic closure held in a field, and one that mentions its own template.
public class Pipeline<T> {
    Keeps<T> allow;
    Takes<T> deliver;

    public Pipeline(Keeps<T> allow, Takes<T> deliver) {
        this.allow = allow;
        this.deliver = deliver;
    }

    public void Offer(T value) {
        if (allow(value)) { deliver(value); }
    }
}

// Somewhere for a bound method to come from.
class Tally {
    public int Count;
    public int Sum;

    public Tally() { Count = 0; Sum = 0; }

    public void Note(int value) { Count++; Sum += value; }
    public bool Under(int value) { return value < 100; }
}

int Wider(String a, String b) { return (int)a.ByteLength() - (int)b.ByteLength(); }

public int Main() {
    int[] numbers = [4, 1, 9, 2, 7];
    String[] words = ["alpha", "bb", "c", "delta"];

    // A lambda, at two different type arguments.
    Console.WriteLine($"kept     {Kept(numbers, (n) => n > 3).Count()}");
    Console.WriteLine($"words    {Kept(words, (w) => w.ByteLength() > 1u).Count()}");

    // The result type read off the lambda's body.
    var spelled = Turned(numbers, (n) => Text.FromInteger((long)n));
    Console.WriteLine($"spelled  {spelled.At(0u)} and {spelled.At(4u)}");

    var lengths = Turned(words, (w) => (int)w.ByteLength());
    Console.WriteLine($"lengths  {lengths.At(0u)} {lengths.At(2u)}");

    // A fold, whose two parameters are different types.
    Console.WriteLine($"sum      {Folded(numbers, 0, (total, n) => total + n)}");
    Console.WriteLine($"joined   {Folded(words, "", (all, w) => all + w)}");

    // The thing an interface made hard: a method that already exists, bound to
    // the object it belongs to.
    var tally = new Tally();
    Each(numbers, tally.Note);
    Console.WriteLine($"tally    {tally.Count} totalling {tally.Sum}");

    // The same method as a predicate, in a field of a generic class.
    var counted = new Tally();
    var pipe = new Pipeline<int>(counted.Under, counted.Note);
    pipe.Offer(5);
    pipe.Offer(500);
    pipe.Offer(50);
    Console.WriteLine($"pipeline {counted.Count} totalling {counted.Sum}");

    // A generic delegate, which cannot capture and so takes a plain function.
    Console.WriteLine($"widest   {words[Best(words, Wider)]}");

    // Two closures of one instantiated type compare by both words.
    Keeps<int> first = tally.Under;
    Keeps<int> again = tally.Under;
    Keeps<int> other = counted.Under;
    Console.WriteLine($"equal    {first == again} {first == other}");
    return 0;
}
