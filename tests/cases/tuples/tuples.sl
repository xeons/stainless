// SPDX-License-Identifier: 0BSD
//
// `(int, String)` — several values travelling as one.
//
// **A tuple is a struct.** So layout, both ABI classifiers and the reference
// walk that retains and releases what a value holds all apply to it without a
// line of any of them being written for tuples. That is the same bargain
// `closure` made, and it is why this is a few dozen lines rather than a
// feature.
//
// **It is structural**: `(int, String)` written in two modules is one type,
// interned by its element types the way a slice is by its element.
//
// **The fields have no names of their own** — they are `Item1` upwards, as in
// C#. Named elements would either have to take part in the type's identity,
// making `(int a, int b)` and `(int x, int y)` different types, or not, leaving
// two names for one field. Where a name is wanted it is wanted at the *use*
// site, and that is what deconstruction is for.
module Tuples;

import Standard.Console;
import Standard.Collections;

class Loud
{
    public String Tag;
    public Loud(String tag) => Tag = tag;
    ~Loud() { Console.WriteLine($"  dropped {Tag}"); }
}

/// The shape a tuple is for: two answers that belong together, and no struct
/// declared for the sake of one function.
(int, int) MinMax(int[:] numbers)
{
    int low = numbers[0u];
    int high = numbers[0u];

    foreach (var n in numbers)
    {
        if (n < low)
            low = n;
        if (n > high)
            high = n;
    }

    return (low, high);
}

/// One that carries references, so ARC has something to do.
(String, String) SplitAt(String text, nuint at)
{
    return (text.Substring(0u, at), text.Substring(at, text.ByteLength() - at));
}

(Loud, Loud) Pair() { return (new Loud("first"), new Loud("second")); }

/// A tuple through a generic, to show it is an ordinary type.
T FirstOf<T, U>((T, U) pair) { return pair.Item1; }

public int Main()
{
    // Written out, and read by field.
    var pair = (1, "one");
    Console.WriteLine($"a {pair.Item1} {pair.Item2}");

    // Named as a type, and assigned across -- one type, not two.
    (int, String) declared = pair;
    Console.WriteLine($"b {declared.Item2}");

    // Returned.
    int[] numbers = [5, 2, 9, 1];
    var range = MinMax(numbers);
    Console.WriteLine($"c {range.Item1} {range.Item2}");

    // And taken apart, which is where the names go.
    var (low, high) = MinMax(numbers);
    Console.WriteLine($"d {low} {high}");

    var (head, tail) = SplitAt("together", 2u);
    Console.WriteLine($"e {head}|{tail}");

    // Three elements, of three types.
    var triple = (1, 2.5, "three");
    Console.WriteLine($"f {triple.Item1} {triple.Item2} {triple.Item3}");

    // Nested, because a tuple is a type like any other.
    var nested = ((1, 2), "outer");
    Console.WriteLine($"g {nested.Item1.Item2} {nested.Item2}");

    // Through a generic.
    Console.WriteLine($"h {FirstOf((7, "seven"))}");

    // In a container.
    var all = new List<(int, String)>();
    all.Add((1, "one"));
    all.Add((2, "two"));
    Console.WriteLine($"i {all.Count()} {all.At(1u).Item2}");

    // Structural: the same two element types, made two different ways.
    var made = MinMax(numbers);
    var written = (1, 9);
    Console.WriteLine($"j {made.Item1 == written.Item1 && made.Item2 == written.Item2}");

    // ---------------------------------------------------------------- ARC

    Console.WriteLine("held:");
    {
        var both = Pair();
        Console.WriteLine($"  {both.Item1.Tag} and {both.Item2.Tag}");
    }

    Console.WriteLine("taken apart:");
    {
        var (one, two) = Pair();
        Console.WriteLine($"  {one.Tag} and {two.Tag}");
    }

    Console.WriteLine("done");
    return 0;
}
