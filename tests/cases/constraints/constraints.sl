// SPDX-License-Identifier: 0BSD
module Constraints;

import Standard.Console;
import Standard.Collections;    // IComparable<T> lives here
import Standard.Threading;

public interface IDescribable
{
    String Describe();
}

public class Money : IComparable<Money>, IDescribable
{
    int _cents;

    public Money(int amount) => _cents = amount;
    public int Cents() => _cents;

    public int CompareTo(Money other)
    {
        if (_cents < other.Cents())
            return -1;
        if (_cents > other.Cents())
            return 1;
        return 0;
    }

    public String Describe() => Text.FromInteger(_cents) + "c";
}

public class Tag : IComparable<Tag>, IDescribable
{
    String _name;

    public Tag(String value) => _name = value;
    public String Name => _name;

    public int CompareTo(Tag other)
    {
        if (_name == other.Name)
            return 0;
        return 1;
    }

    public String Describe() => _name;
}

// F-bounded: T must be comparable to itself.
T Largest<T>(T[] values) where T : IComparable<T>
{
    var best = values[0];
    for (nuint i = 1; i < values.Length; i = i + 1)
    {
        if (values[i].CompareTo(best) > 0)
            best = values[i];
    }
    return best;
}

// Two constraints on one parameter, on a generic class.
public class Ranked<T> where T : IComparable<T>, IDescribable
{
    T[] _items;
    nuint _count;

    public Ranked(nuint capacity)
    {
        _items = new T[capacity];
        _count = 0;
    }

    public void Add(T item)
    {
        _items[_count] = item;
        _count = _count + 1;
    }

    public String BestDescription()
    {
        var best = _items[0];
        for (nuint i = 1; i < _count; i = i + 1)
        {
            if (_items[i].CompareTo(best) > 0)
                best = _items[i];
        }
        return best.Describe();
    }
}

// ------------------------------------------------- the kinds that are not
//                                                    an interface

/// A base class constrains too: the argument must be it or derive from it.
public class Animal
{
    public Animal() { }
    public virtual String Says() => "...";
}

public class Dog : Animal
{
    public Dog() { }
    public override String Says() => "woof";
}

public struct Point
{
    public int X;
    public int Y;
}

/// `class`: a reference type, so it may be null and is counted.
T FirstOf<T>(T[] items) where T : class { return items[0]; }

/// `struct`: a value type, so an element is the value rather than a
/// reference to one, and there is no null to ask about before writing.
nuint FillWith<T>(T[] items, T value) where T : struct
{
    for (nuint i = 0u; i < items.Length; i = i + 1u)
        items[i] = value;
    return items.Length;
}

/// `new()`: the body may make one, so a template can replace what it was
/// handed rather than only read it.
T Blank<T>(T old) where T : new() { return new T(); }

/// A class that declares no constructor is given one taking no arguments, so
/// it satisfies `new()` exactly as `new Undeclared()` says it can be made. It
/// has no initializer either, which is what used to leave it with none at all.
public class Undeclared
{
    public String Label => "undeclared";
}

/// And the same constraint on a type rather than a function, which is checked
/// where the type is named.
public class Factory<T> where T : new()
{
    public T Make() => new T();
}

/// A base class, so the body may use what the base declares -- through the
/// vtable, so an override still wins.
String SaysOf<T>(T animal) where T : Animal { return animal.Says(); }

/// One parameter constrained by another, which is what lets two arguments be
/// required to line up rather than merely each be something.
String Louder<T, U>(T thing, U other) where T : U where U : Animal
{
    return other.Says() + "!";
}

/// `threadsafe`: the one constraint that is a hard error where the same fact
/// is only a warning at a `spawn`. A library author asking for it in their own
/// signature is not the compiler guessing.
long Counted<T>(T shared, long times) where T : threadsafe { return times; }

void Kinds()
{
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
    Console.WriteLine("implicit=" + new Factory<Undeclared>().Make().Label);

    // Dispatch still happens: T is Dog, and Dog overrides.
    Console.WriteLine("base=" + SaysOf(new Dog()));
    Console.WriteLine("related=" + Louder(new Dog(), new Animal()));

    var cell = new AtomicLong(4);
    Console.WriteLine("threadsafe=" + Text.FromInteger(Counted(cell, cell.Read())));
}

int Main()
{
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
    Contextual();
    return 0;
}

// ------------------------------------------------- `where` is not a keyword

// `where` is contextual: a keyword only where a constraint clause may begin,
// and an ordinary name everywhere else. It reads as a keyword twice on the
// next line and as a parameter once, which is the whole of the rule.
String Describe<T>(T thing, String where) where T : IDescribable
{
    // And as a local, shadowing nothing, in a body that also calls a method
    // on the constrained parameter.
    String what = thing.Describe();
    return what + "@" + where;
}

public class Landmark
{
    // As a field and as a property, both of which read the word in a position
    // a declaration starts -- where a reserved word fails differently again.
    String where;

    public Landmark(String at) => where = at;

    public String Where => where;
}

void Contextual()
{
    Console.WriteLine("where=" + Describe(new Money(45), "till"));
    Console.WriteLine("field=" + new Landmark("pier").Where);

    // A local of that name outside any generic, followed by a statement that
    // begins with an identifier -- the shape a contextual match could swallow.
    String where = "here";
    Console.WriteLine("local=" + where);
}
