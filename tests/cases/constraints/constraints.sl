// SPDX-License-Identifier: 0BSD
module Constraints;

import Standard.Console;
import Standard.Collections;    // IComparable<T> lives here
import Standard.Threading;

public interface IDescribable {
    String Describe();
}

public class Money : IComparable<Money>, IDescribable {
    int cents;

    public Money(int amount) { cents = amount; }
    public int Cents() { return cents; }

    public int CompareTo(Money other) {
        if (cents < other.Cents()) { return -1; }
        if (cents > other.Cents()) { return 1; }
        return 0;
    }

    public String Describe() { return Text.FromInteger(cents) + "c"; }
}

public class Tag : IComparable<Tag>, IDescribable {
    String name;

    public Tag(String value) { name = value; }
    public String Name() { return name; }

    public int CompareTo(Tag other) {
        if (name == other.Name()) { return 0; }
        return 1;
    }

    public String Describe() { return name; }
}

// F-bounded: T must be comparable to itself.
T Largest<T>(T[] values) where T : IComparable<T> {
    var best = values[0];
    for (nuint i = 1; i < values.Length; i = i + 1) {
        if (values[i].CompareTo(best) > 0) { best = values[i]; }
    }
    return best;
}

// Two constraints on one parameter, on a generic class.
public class Ranked<T> where T : IComparable<T>, IDescribable {
    T[] items;
    nuint count;

    public Ranked(nuint capacity) {
        items = new T[capacity];
        count = 0;
    }

    public void Add(T item) {
        items[count] = item;
        count = count + 1;
    }

    public String BestDescription() {
        var best = items[0];
        for (nuint i = 1; i < count; i = i + 1) {
            if (items[i].CompareTo(best) > 0) { best = items[i]; }
        }
        return best.Describe();
    }
}

// ------------------------------------------------- the kinds that are not
//                                                    an interface

/// A base class constrains too: the argument must be it or derive from it.
public class Animal {
    public Animal() { }
    public virtual String Says() { return "..."; }
}

public class Dog : Animal {
    public Dog() { }
    public override String Says() { return "woof"; }
}

public struct Point {
    public int X;
    public int Y;
}

/// `class`: a reference type, so it may be null and is counted.
T FirstOf<T>(T[] items) where T : class { return items[0]; }

/// `struct`: a value type, so an element is the value rather than a
/// reference to one, and there is no null to ask about before writing.
nuint FillWith<T>(T[] items, T value) where T : struct {
    for (nuint i = 0u; i < items.Length; i = i + 1u) { items[i] = value; }
    return items.Length;
}

/// `new()`: the body may make one, so a template can replace what it was
/// handed rather than only read it.
T Blank<T>(T old) where T : new() { return new T(); }

/// A base class, so the body may use what the base declares -- through the
/// vtable, so an override still wins.
String SaysOf<T>(T animal) where T : Animal { return animal.Says(); }

/// One parameter constrained by another, which is what lets two arguments be
/// required to line up rather than merely each be something.
String Louder<T, U>(T thing, U other) where T : U where U : Animal {
    return other.Says() + "!";
}

/// `threadsafe`: the one constraint that is a hard error where the same fact
/// is only a warning at a `spawn`. A library author asking for it in their own
/// signature is not the compiler guessing.
long Counted<T>(T shared, long times) where T : threadsafe { return times; }

void Kinds() {
    var dogs = new Dog[1];
    dogs[0] = new Dog();
    Console.WriteLine("class=" + FirstOf(dogs).Says());

    Point p;
    p.X = 3;
    p.Y = 4;

    var points = new Point[3];
    nuint filled = FillWith(points, p);
    Console.WriteLine("struct=" + Text.FromInteger((long)filled) + " " +
                      Text.FromInteger(points[2].X + points[2].Y));

    // `new T()` inside the template, on a class whose constructor takes
    // nothing. The blank one is a different object from the one passed in.
    Console.WriteLine("new=" + Blank(new Dog()).Says());

    // Dispatch still happens: T is Dog, and Dog overrides.
    Console.WriteLine("base=" + SaysOf(new Dog()));
    Console.WriteLine("related=" + Louder(new Dog(), new Animal()));

    var cell = new AtomicLong(4);
    Console.WriteLine("threadsafe=" + Text.FromInteger(Counted(cell, cell.Load())));
}

int Main() {
    var prices = new Money[3];
    prices[0] = new Money(250);
    prices[1] = new Money(999);
    prices[2] = new Money(125);
    Console.WriteLine("largest=" + Largest(prices).Describe());

    var ranked = new Ranked<Money>(3);
    ranked.Add(new Money(10));
    ranked.Add(new Money(70));
    ranked.Add(new Money(40));
    Console.WriteLine("best=" + ranked.BestDescription());

    // The same template, a different type argument.
    var tags = new Ranked<Tag>(2);
    tags.Add(new Tag("alpha"));
    tags.Add(new Tag("beta"));
    Console.WriteLine("tag=" + tags.BestDescription());

    Kinds();
    return 0;
}
