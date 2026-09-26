// SPDX-License-Identifier: 0BSD
//
// What a deconstruction owns, and for how long. Every value on the right is
// read before anything is stored, and a value that was not made by this
// statement is held with a reference of its own while it waits: a store may
// release the last other owner of what the next store reads. Everything here
// runs under --leak-check.
module DeconstructionArc;

import Standard.Console;

class Loud
{
    public String Tag;
    public Loud(String tag) => Tag = tag;
    ~Loud() { Console.WriteLine($"  dropped {Tag}"); }
}

class Node
{
    public Loud Held;
    public Node(Loud held) => Held = held;
}

struct Labelled
{
    public Loud Tag;
    public int Value;
}

enum Oops { Bad }

class Shelf
{
    public Loud[] Slots = [new Loud("slot 0"), new Loud("slot 1")];

    public Loud Replace(String tag)
    {
        Console.WriteLine("  replacing the slots");
        Slots = [new Loud("new 0"), new Loud("new 1")];
        return new Loud(tag);
    }
}

(Loud, Loud) Pair(String left, String right) => (new Loud(left), new Loud(right));

String Describe(Result<Loud, Oops> result)
{
    switch (result)
    {
        case Ok ok: return ok.Value.Tag;
        default: return "failed";
    }
}

public int Main()
{
    Console.WriteLine("swap:");
    {
        var one = new Loud("one");
        var two = new Loud("two");
        (one, two) = (two, one);
        Console.WriteLine($"  {one.Tag} {two.Tag}");
    }

    Console.WriteLine("a temporary taken apart:");
    {
        var (left, right) = Pair("left", "right");
        Console.WriteLine($"  {left.Tag} {right.Tag}");
    }

    Console.WriteLine("a discarded element:");
    {
        var (kept, _) = Pair("kept", "discarded");
        Console.WriteLine($"  {kept.Tag}");
    }

    Console.WriteLine("overwritten:");
    {
        var held = new Loud("first");
        (held, _) = (new Loud("second"), 0);
        Console.WriteLine($"  {held.Tag}");
    }

    // The value on the right is the only thing keeping the second node's
    // Loud alive once `a` is overwritten; it is held until the statement ends.
    Console.WriteLine("the last owner overwritten first:");
    {
        var a = new Node(new Loud("a's"));
        Loud b = new Loud("b");
        (a, b) = (new Node(new Loud("replacement")), a.Held);
        Console.WriteLine($"  {a.Held.Tag} {b.Tag}");
    }

    Console.WriteLine("structs holding references:");
    {
        Labelled x;
        x.Tag = new Loud("x");
        Labelled y;
        y.Tag = new Loud("y");
        (x, y) = (y, x);
        Console.WriteLine($"  {x.Tag.Tag} {y.Tag.Tag}");

        var pair = (x, y);
        (pair.Item2, pair.Item1) = pair;
        Console.WriteLine($"  {pair.Item1.Tag.Tag} {pair.Item2.Tag.Tag}");
    }

    Console.WriteLine("variants:");
    {
        Result<Loud, Oops> good = Ok(new Loud("ok"));
        Result<Loud, Oops> bad = Fail(Oops.Bad);
        (good, bad) = (bad, good);
        Console.WriteLine($"  {Describe(good)} {Describe(bad)}");
    }

    // The array is reached before the value replaces it, so the store lands
    // in the array that was reached, which C# also does.
    Console.WriteLine("the container replaced by the value:");
    {
        var shelf = new Shelf();
        (shelf.Slots[0u], _) = (shelf.Replace("stored"), 0);
        Console.WriteLine($"  {shelf.Slots[0u].Tag}");
    }

    Console.WriteLine("done");
    return 0;
}
