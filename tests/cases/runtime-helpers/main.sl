// SPDX-License-Identifier: 0BSD
//
// `RuntimeHelpers.IsReferenceOrContainsReferences<T>()` over a type of each
// kind, and asked from inside a generic, where each instantiation has its own
// answer.
module RuntimeHelpersCase;

import Standard.Console;

class Thing
{
}

struct Plain
{
    public int A;
    public double B;
}

struct Holder
{
    public int A;
    public String Name;
}

struct Outer
{
    public Plain Inner;
    public Holder Held;
}

struct Watcher
{
    public weak Thing? Watched;
}

enum Colour
{
    Red,
    Green,
}

variant Shape
{
    Dot;
    Circle(double Radius);
}

variant Labelled
{
    Blank;
    Named(String Name);
}

void Show(String name, bool value) =>
    Console.WriteLine(name + ": " + (value ? "true" : "false"));

bool AskedInside<T>() => RuntimeHelpers.IsReferenceOrContainsReferences<T>();

int Main()
{
    Show("byte", RuntimeHelpers.IsReferenceOrContainsReferences<byte>());
    Show("double", RuntimeHelpers.IsReferenceOrContainsReferences<double>());
    Show("Colour", RuntimeHelpers.IsReferenceOrContainsReferences<Colour>());
    Show("int*", RuntimeHelpers.IsReferenceOrContainsReferences<int*>());
    Show("Thing", RuntimeHelpers.IsReferenceOrContainsReferences<Thing>());
    Show("Thing?", RuntimeHelpers.IsReferenceOrContainsReferences<Thing?>());
    Show("String", RuntimeHelpers.IsReferenceOrContainsReferences<String>());
    Show("int[]", RuntimeHelpers.IsReferenceOrContainsReferences<int[]>());
    Show("Plain", RuntimeHelpers.IsReferenceOrContainsReferences<Plain>());
    Show("Holder", RuntimeHelpers.IsReferenceOrContainsReferences<Holder>());
    Show("Outer", RuntimeHelpers.IsReferenceOrContainsReferences<Outer>());
    Show("Watcher", RuntimeHelpers.IsReferenceOrContainsReferences<Watcher>());
    Show("(int, long)", RuntimeHelpers.IsReferenceOrContainsReferences<(int, long)>());
    Show("(int, String)", RuntimeHelpers.IsReferenceOrContainsReferences<(int, String)>());
    Show("int[4]", RuntimeHelpers.IsReferenceOrContainsReferences<int[4]>());
    Show("Plain[2]", RuntimeHelpers.IsReferenceOrContainsReferences<Plain[2]>());
    Show("Func<int, int>", RuntimeHelpers.IsReferenceOrContainsReferences<Func<int, int>>());
    Show("Shape", RuntimeHelpers.IsReferenceOrContainsReferences<Shape>());
    Show("Labelled", RuntimeHelpers.IsReferenceOrContainsReferences<Labelled>());
    Show("Optional<int>", RuntimeHelpers.IsReferenceOrContainsReferences<Optional<int>>());
    Show("Optional<String>", RuntimeHelpers.IsReferenceOrContainsReferences<Optional<String>>());
    Show("Span<int>", RuntimeHelpers.IsReferenceOrContainsReferences<Span<int>>());

    Show("inside, int", AskedInside<int>());
    Show("inside, Thing", AskedInside<Thing>());
    return 0;
}
