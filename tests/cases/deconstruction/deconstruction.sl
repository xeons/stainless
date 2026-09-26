// SPDX-License-Identifier: 0BSD
//
// A tuple taken apart: into new names, into places that exist, or both. C#'s
// order holds -- the targets' receivers and indices left to right, then every
// value on the right, then the stores left to right -- so `(a, b) = (b, a)`
// swaps, and a store never sees a value another store has already changed.
module Deconstruction;

import Standard.Console;

class Holder
{
    public int F;
    public int P { get; set; }
    public int[] Cells = new int[3];
}

class Grid
{
    int[] _cells = new int[4];

    public int this[int at]
    {
        get => _cells[at];
        set => _cells[at] = value;
    }
}

struct Point
{
    public int X;
    public int Y;
}

static int s_total = 0;

(int, String) Make() => (7, "seven");

Holder Get(Holder holder, String why)
{
    Console.WriteLine($"get {why}");
    return holder;
}

int Log(String what, int value)
{
    Console.WriteLine(what);
    return value;
}

T SecondOf<T, U>((U, T) pair)
{
    var (_, second) = pair;
    return second;
}

void Show((int, int) pair) => Console.WriteLine($"show {pair.Item1} {pair.Item2}");

public int Main()
{
    // Declared, by type, by `var`, or both, with `_` for what is not wanted.
    var (count, name) = Make();
    (int typed, String written) = Make();
    (var first, var _) = Make();
    (long widened, _) = Make();
    Console.WriteLine($"a {count} {name} {typed} {written} {first} {widened}");

    // Nested, on either side.
    var (u, (v, w)) = (1, (2, "three"));
    Console.WriteLine($"b {u} {v} {w}");

    // Into what exists.
    int x = 1;
    int y = 2;
    (x, y) = (y, x);
    Console.WriteLine($"c {x} {y}");

    (x, (y, count)) = (10, (20, 30));
    Console.WriteLine($"d {x} {y} {count}");

    // Declaring and assigning in one.
    (x, int fresh) = (5, 6);
    Console.WriteLine($"e {x} {fresh}");

    // A field, an element, a property, an indexer and a static.
    var held = new Holder();
    var grid = new Grid();
    (held.F, held.Cells[1u], held.P, grid[2], s_total) = (1, 2, 3, 4, 5);
    Console.WriteLine($"f {held.F} {held.Cells[1u]} {held.P} {grid[2]} {s_total}");

    // A struct's fields swapped through one another.
    Point p;
    p.X = 3;
    p.Y = 4;
    (p.X, p.Y) = (p.Y, p.X);
    Console.WriteLine($"g {p.X} {p.Y}");

    // A tuple's own fields, swapped from the tuple: it is read whole first.
    var pair = (1, 2);
    (pair.Item2, pair.Item1) = pair;
    Console.WriteLine($"h {pair.Item1} {pair.Item2}");

    // Receivers and indices first, left to right, then the values.
    int i = 0;
    int[] cells = [10, 20, 30];
    (i, cells[i]) = (1, 99);
    Console.WriteLine($"i {i} {cells[0u]} {cells[1u]}");

    (Get(held, "left").F, Get(held, "right").P) = (Log("one", 1), Log("two", 2));
    (grid[Log("index", 0)], _) = (Log("value", 8), Log("discarded", 0));
    Console.WriteLine($"j {held.F} {held.P} {grid[0]}");

    // Its value is the tuple stored, so it chains and can be passed on.
    int c = 0;
    int d = 0;
    var both = (x, y) = (c, d) = (5, 6);
    Console.WriteLine($"k {x} {y} {c} {d} {both.Item1} {both.Item2}");
    Show((c, d) = (7, 8));

    // Anywhere a statement goes.
    for (var (low, high) = (0, 3); low < high; low++)
        Console.WriteLine($"l {low} {high}");

    var sum = int () =>
    {
        var (m, n) = (3, 4);
        return m + n;
    };
    int Product() => typed * fresh;
    Console.WriteLine($"m {sum()} {Product()} {SecondOf((1, "generic"))}");

    // A value converted to what it is stored as, element by element.
    String? maybe = "set";
    long wide = 0;
    (maybe, wide) = (null, 3);
    Console.WriteLine($"n {maybe ?? "none"} {wide}");

    bool flip = true;
    (c, d) = flip ? (1, 2) : (3, 4);
    Console.WriteLine($"o {c} {d}");
    return 0;
}
