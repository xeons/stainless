// SPDX-License-Identifier: 0BSD
//
// Arguments are evaluated in the order they were written, whatever order the
// names put them in, as C#'s are. Each is passed where its name says; a
// default the call left out is a constant and has no order to keep.
module NamedArgumentOrder;

import Standard.Console;

struct Point
{
    public int X;
    public int Y;

    public Point(int x, int y)
    {
        X = x;
        Y = y;
    }
}

class Pair
{
    public int First;
    public int Second;

    public Pair(int first, int second)
    {
        First = first;
        Second = second;
    }

    public String Describe(String prefix, int width) => $"{prefix}{First}/{Second} w{width}";
}

int Log(String what, int value)
{
    Console.WriteLine(what);
    return value;
}

String Show(int a, int b, int c = 30) => $"a={a} b={b} c={c}";

String Scaled(int scale, Point at) => $"({at.X * scale},{at.Y * scale})";

public int Main()
{
    Console.WriteLine(Show(b: Log("b", 2), a: Log("a", 1)));
    Console.WriteLine(Show(Log("a", 1), c: Log("c", 3), b: Log("b", 2)));

    // A class, a struct and a method with a receiver.
    var pair = new Pair(second: Log("second", 8), first: Log("first", 7));
    var point = new Point(y: Log("y", 4), x: Log("x", 3));
    Console.WriteLine(pair.Describe(width: Log("width", 9), prefix: "p"));
    Console.WriteLine($"{point.X},{point.Y}");

    // A struct argument is copied when it is evaluated, so a later argument
    // changing the variable does not reach it.
    Point moving = new Point(1, 1);
    Console.WriteLine(Scaled(at: moving, scale: (moving = new Point(5, 5)).X));
    return 0;
}
