// SPDX-License-Identifier: 0BSD
//
// Operators and indexers, both in C#'s shape: declared inside the type they
// belong to, with every operand written out.
//
// The reason for `static` with both operands rather than an instance method
// with an implicit receiver is `3 * money`. An operator whose left operand is
// not the declaring type has nothing to hang a `this` off, and would be
// unwritable.
module Operators;

import Standard.Console;
import Standard.Collections;

extern "C" int printf(byte* format, ...);

// ------------------------------------------------------------------- a value

public struct Money {
    public long Cents;

    public static Money operator +(Money a, Money b) { return Cents(a.Cents + b.Cents); }
    public static Money operator -(Money a, Money b) { return Cents(a.Cents - b.Cents); }
    public static Money operator -(Money a) { return Cents(0 - a.Cents); }

    // Both ways round, so the multiplication reads either way it is written.
    public static Money operator *(Money a, long by) { return Cents(a.Cents * by); }
    public static Money operator *(long by, Money a) { return Cents(a.Cents * by); }

    public static Money operator /(Money a, long by) { return Cents(a.Cents / by); }

    public static bool operator ==(Money a, Money b) { return a.Cents == b.Cents; }
    public static bool operator !=(Money a, Money b) { return a.Cents != b.Cents; }
    public static bool operator <(Money a, Money b) { return a.Cents < b.Cents; }
    public static bool operator >(Money a, Money b) { return a.Cents > b.Cents; }
    public static bool operator <=(Money a, Money b) { return a.Cents <= b.Cents; }
    public static bool operator >=(Money a, Money b) { return a.Cents >= b.Cents; }
}

public Money Cents(long value) {
    Money made;
    made.Cents = value;
    return made;
}

// A class, to prove an operator is not only for structs -- and that a declared
// `==` is asked rather than the reference being compared behind its back.
public class Tag {
    public String Name { get; }

    public Tag(String name) { Name = name; }

    public static bool operator ==(Tag a, Tag b) { return a.Name == b.Name; }
    public static bool operator !=(Tag a, Tag b) { return a.Name != b.Name; }
}

// A set of bits, for the bitwise ones and the unary complement.
public struct Mask {
    public uint Bits;

    public static Mask operator |(Mask a, Mask b) { return Of(a.Bits | b.Bits); }
    public static Mask operator &(Mask a, Mask b) { return Of(a.Bits & b.Bits); }
    public static Mask operator ^(Mask a, Mask b) { return Of(a.Bits ^ b.Bits); }
    public static Mask operator ~(Mask a) { return Of(~a.Bits); }
    public static Mask operator <<(Mask a, int by) { return Of(a.Bits << (uint)by); }

    public static bool operator ==(Mask a, Mask b) { return a.Bits == b.Bits; }
    public static bool operator !=(Mask a, Mask b) { return a.Bits != b.Bits; }
}

public Mask Of(uint bits) {
    Mask made;
    made.Bits = bits;
    return made;
}

// --------------------------------------------------------------- indexers

public class Grid {
    int[] cells;
    nuint width;

    public Grid(nuint w, nuint h) {
        width = w;
        cells = new int[w * h];
    }

    /// One index, the flat one.
    public int this[nuint at] {
        get { return cells[at]; }
        set { cells[at] = value; }
    }
}

/// Overloaded on what it takes: by position, and by name.
public class Bag {
    List<String> items;

    public Bag() { items = new List<String>(); }

    public void Add(String item) { items.Add(item); }
    public nuint Count() { return items.Count(); }

    public String this[nuint at] {
        get { return items.At(at); }
        set { items.Set(at, value); }
    }

    public bool this[String wanted] {
        get {
            foreach (var one in items) { if (one == wanted) { return true; } }
            return false;
        }
        set { if (value) { items.Add(wanted); } }
    }
}

/// A read-only indexer, which is the common shape and needs no setter.
public class Squares {
    public nuint this[nuint n] { get { return n * n; } }
}

/// An indexer on a struct, which reaches its receiver by pointer.
public struct Triple {
    public int A;
    public int B;
    public int C;

    public int this[nuint at] {
        get {
            if (at == 0u) { return A; }
            if (at == 1u) { return B; }
            return C;
        }
        set {
            if (at == 0u) { A = value; }
            else if (at == 1u) { B = value; }
            else { C = value; }
        }
    }
}

/// Inherited like any other member.
public class Base {
    public int this[nuint at] { get { return (int)at * 10; } }
}

public class Derived : Base { }

int Main() {
    // ------------------------------------------------------------ arithmetic

    var a = Cents(250);
    var b = Cents(125);

    printf("sum       = %lld\n", (a + b).Cents);
    printf("diff      = %lld\n", (a - b).Cents);
    printf("negated   = %lld\n", (-a).Cents);
    printf("scaled    = %lld\n", (a * 3).Cents);
    printf("flipped   = %lld\n", (3 * a).Cents);
    printf("divided   = %lld\n", (a / 2).Cents);
    printf("chained   = %lld\n", (a + b - Cents(75)).Cents);

    // Compound assignment falls out of `+` with no second rule: `x += y` is
    // defined as `x = x + y` and picks up whatever `+` does.
    var running = Cents(0);
    running += a;
    running += b;
    running -= Cents(100);
    printf("running   = %lld\n", running.Cents);

    // -------------------------------------------------------------- comparing

    printf("equal     = %d\n", a == Cents(250));
    printf("notEqual  = %d\n", a != b);
    printf("less      = %d\n", b < a);
    printf("greater   = %d\n", a > b);
    printf("lessEq    = %d\n", a <= Cents(250));
    printf("greaterEq = %d\n", a >= Cents(250));

    // A declared `==` is asked rather than the addresses being compared, which
    // is the entire reason to declare one.
    var left = new Tag("same");
    var right = new Tag("same");
    printf("byValue   = %d\n", left == right);
    printf("different = %d\n", left != new Tag("other"));

    // ---------------------------------------------------------------- bits

    var low = Of(0x0Fu);
    var high = Of(0xF0u);

    printf("or        = %u\n", (low | high).Bits);
    printf("and       = %u\n", (low & Of(0x03u)).Bits);
    printf("xor       = %u\n", (low ^ Of(0xFFu)).Bits);
    printf("shifted   = %u\n", (low << 4).Bits);
    printf("complement= %u\n", (~low).Bits & 0xFFu);

    // --------------------------------------------------------------- indexers

    var grid = new Grid(3u, 3u);
    grid[0u] = 7;
    grid[4u] = 9;
    grid[4u] += 1;
    grid[8u] = grid[0u] + grid[4u];

    printf("grid0     = %d\n", grid[0u]);
    printf("grid4     = %d\n", grid[4u]);
    printf("grid8     = %d\n", grid[8u]);

    var bag = new Bag();
    bag.Add("alpha");
    bag.Add("beta");

    printf("byIndex   = %s\n", bag[1u].ToPointer());
    printf("byName    = %d\n", bag["alpha"]);
    printf("missing   = %d\n", bag["gamma"]);

    bag["gamma"] = true;
    printf("added     = %d\n", bag["gamma"]);
    printf("count     = %llu\n", (ulong)bag.Count());

    bag[0u] = "ALPHA";
    printf("replaced  = %s\n", bag[0u].ToPointer());

    var squares = new Squares();
    printf("readOnly  = %llu\n", (ulong)squares[7u]);

    Triple triple;
    triple[0u] = 1;
    triple[1u] = 2;
    triple[2u] = 3;
    printf("struct    = %d %d %d\n", triple[0u], triple[1u], triple[2u]);
    printf("fields    = %d %d %d\n", triple.A, triple.B, triple.C);

    var derived = new Derived();
    printf("inherited = %d\n", derived[4u]);

    // An index that is an expression, and one used inside an interpolation.
    nuint at = 1u;
    printf("computed  = %d\n", grid[at + 3u]);
    Console.WriteLine($"inside    = {grid[4u]}");

    printf("done\n");
    return 0;
}
