// SPDX-License-Identifier: 0BSD
module Refs;

import Standard.Console;

public struct Point { public double X; public double Y; }

public class Trace {
    public String Name { get; }
    public Trace(String name) { Name = name; }
    ~Trace() { Console.WriteLine("~" + Name); }
}

// `ref` is the caller's storage, so writing to it writes the caller's variable.
void Bump(ref int n) { n = n + 1; }
void Swap(ref int a, ref int b) { int t = a; a = b; b = t; }
void Move(ref Point p, double dx, double dy) { p.X = p.X + dx; p.Y = p.Y + dy; }

// `in` is the same storage with a promise not to write it, which is what makes
// it a borrow: a struct crosses without being copied, and nothing may change it.
double LengthSquared(in Point p) { return p.X * p.X + p.Y * p.Y; }

// A `ref` to a counted reference reassigns the caller's slot, releasing what was
// there and retaining what replaces it.
void Rename(ref Trace t, String name) { t = new Trace(name); }
void Forget(ref Trace? t) { t = null; }

public interface IAdjust { void Adjust(ref int n); }
public class Doubler : IAdjust { public void Adjust(ref int n) { n = n * 2; } }

public delegate void Adjuster(ref int n);
void Triple(ref int n) { n = n * 3; }

// A `ref T` is a `T*` at the ABI, so this needs no shim in either direction.
extern "C" double modf(double value, ref double integral);

Point Made(double x) { Point p; p.X = x; p.Y = x; return p; }

int Main() {
    int n = 1;
    Bump(ref n);
    Bump(ref n);
    Console.WriteLine(Text.FromInteger(n));

    int a = 3;
    int b = 9;
    Swap(ref a, ref b);
    Console.WriteLine(Text.FromInteger(a) + "," + Text.FromInteger(b));

    Point p;
    p.X = 1.0;
    p.Y = 2.0;
    Move(ref p, 10.0, 20.0);
    Console.WriteLine(Text.FromDouble(p.X) + "," + Text.FromDouble(p.Y));
    Console.WriteLine(Text.FromDouble(LengthSquared(p)));

    // An `in` argument with no storage of its own is given a temporary.
    Console.WriteLine(Text.FromDouble(LengthSquared(Made(3.0))));

    // An element of an array has an address like anything else.
    var values = new int[3];
    values[1] = 5;
    Bump(ref values[1]);
    Console.WriteLine(Text.FromInteger(values[1]));

    Console.WriteLine("--- references ---");
    {
        Trace t = new Trace("first");
        Rename(ref t, "second");
        Console.WriteLine(t.Name);
        Console.WriteLine("leaving");
    }
    Console.WriteLine("left");

    {
        Trace? held = new Trace("optional");
        Forget(ref held);
        Console.WriteLine("cleared");
    }

    Console.WriteLine("--- dispatch ---");
    int m = 5;
    IAdjust adjust = new Doubler();
    adjust.Adjust(ref m);
    Console.WriteLine(Text.FromInteger(m));

    Adjuster fn = Triple;
    fn(ref m);
    Console.WriteLine(Text.FromInteger(m));

    double whole = 0.0;
    double fraction = modf(3.75, ref whole);
    Console.WriteLine(Text.FromDouble(whole) + " " + Text.FromDouble(fraction));

    return 0;
}
