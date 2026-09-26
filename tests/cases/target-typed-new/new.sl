// SPDX-License-Identifier: 0BSD
//
// `new(...)` with the type left off, which takes it from where the value is
// going: a declared local, a field, a static, a return, an argument, an
// element, an assignment and either arm of a conditional.
//
// The arguments are bound where they are written, and the object is counted
// like any other, so a closure over one and a list of them both let go.
module TargetTypedNew;

import Standard.Console;
import Standard.Collections;

class Point
{
    public int X;
    public int Y;

    public Point()
    {
        X = 0;
        Y = 0;
    }

    public Point(int x, int y)
    {
        X = x;
        Y = y;
    }

    public String Describe() => $"({X}, {Y})";
}

struct Size
{
    public int Width;
    public int Height;

    public Size(int width, int height)
    {
        Width = width;
        Height = height;
    }
}

class Box<T>
{
    public T Value;

    public Box(T value)
    {
        Value = value;
    }
}

class Holder
{
    public Point Where = new(1, 2);
    public Point? Maybe = new(3, 4);
    public List<int> Numbers = new() { 5, 6, 7 };
}

closure Point Maker(int n);

static Size s_unit = new(1, 1);

Point MakeByExpression() => new(7, 8);

Point MakeByReturn()
{
    return new(9, 10);
}

String Show(Point point) => point.Describe();

// Two overloads, and only one of them can be made by `new`.
String Pick(Point point) => "point";
String Pick(int number) => "number";

T Build<T>() where T : new()
{
    T made = new();
    return made;
}

public int Main()
{
    Point a = new(1, 2);
    Console.WriteLine($"a {a.Describe()}");

    Point b = new() { Y = 5 };
    Console.WriteLine($"b {b.Describe()}");

    Size size = new(3, 4);
    Console.WriteLine($"c {size.Width}x{size.Height}");

    var holder = new Holder();
    Console.WriteLine($"d {holder.Where.Describe()} {holder.Maybe?.Describe() ?? "none"} " +
                      $"{holder.Numbers.Count}");

    Console.WriteLine($"e {MakeByExpression().Describe()} {MakeByReturn().Describe()}");
    Console.WriteLine($"f {Show(new(11, 12))} {Pick(new())}");
    Console.WriteLine($"g {s_unit.Width}x{s_unit.Height}");

    Point[] row = [new(1, 1), new(2, 2), new()];
    Console.WriteLine($"h {row[1].Describe()} {row.Length}");

    Point assigned;
    assigned = new(6, 6);
    Console.WriteLine($"i {assigned.Describe()}");

    bool flag = true;
    Point either = flag ? new(4, 4) : a;
    Point both = !flag ? new(5, 5) : new();
    Console.WriteLine($"j {either.Describe()} {both.Describe()}");

    var points = new List<Point>();
    points.Add(new(2, 3));
    points.Add(new());
    Console.WriteLine($"k {points[0].Describe()} {points.Count}");

    Box<Point> boxed = new(new(8, 9));
    Box<int> number = new(42);
    Console.WriteLine($"l {boxed.Value.Describe()} {number.Value}");

    // Captured by value, as any argument would be.
    int offset = 100;
    Maker maker = (n) => new(n + offset, n);
    Console.WriteLine($"m {maker(1).Describe()}");

    Point built = Build<Point>();
    Console.WriteLine($"n {built.Describe()}");
    return 0;
}
