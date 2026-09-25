// SPDX-License-Identifier: 0BSD
//
// `is` with a name, joined to the rest of a condition by `&&`.
//
// The name is in scope in every operand after the test and in the branch. The
// value tested is taken where the test is evaluated, so an `&&` that stops
// before the test takes nothing.
module IsBindingAnd;

import Standard.Collections;
import Standard.Console;
import Standard.Text;

extern "C" int printf(byte* format, ...);

public variant Value
{
    Null;
    Number(int Held);
}

class Tracked
{
    public String Name;
    public Tracked(String name) => Name = name;
    ~Tracked() { printf("~Tracked(%s)\n", Name.ToPointer()); }
}

class Shape
{
    public String Name;
    public Shape(String name) => Name = name;
}

class Circle : Shape
{
    public int Radius;
    public Circle(int radius)
    {
        base("circle");
        Radius = radius;
    }
}

class Source
{
    public int Calls;
    public Source() => Calls = 0;

    public Value Take(int held)
    {
        Calls++;
        return Value.Number(held);
    }

    public Shape Make(int radius)
    {
        Calls++;
        return radius > 0 ? new Circle(radius) : new Shape("plain");
    }
}

String Describe(Source source, int held)
{
    if (source.Take(held) is Number n && n.Held > 10)
        return "big " + Text.FromInteger(n.Held);
    return "small";
}

String Measure(Source source, int radius)
{
    if (source.Make(radius) is Circle c && c.Radius * 2 > 5 && c.Name == "circle")
        return "wide circle, radius " + Text.FromInteger(c.Radius);
    return "not a wide circle";
}

// Two names, each in scope after its own test.
String Sum(Source source, int left, int right)
{
    if (source.Take(left) is Number a && source.Take(right) is Number b && a.Held + b.Held > 0)
        return "sum " + Text.FromInteger(a.Held + b.Held);
    return "no sum";
}

// A reference held by a name is released once, whichever way the test went.
bool IsNamed(Shape? shape, String name)
{
    if (shape is Shape s && s.Name == name)
        return true;
    return false;
}

Optional<Tracked> TakeLast(List<Tracked> from)
{
    if (from.Count == 0u)
        return None;
    Tracked last = from[from.Count - 1u];
    from.RemoveAt(from.Count - 1u);
    return Some(last);
}

int Main()
{
    var source = new Source();

    // Short-circuit: the test after a false operand is never evaluated.
    bool never = false;
    if (never && source.Take(99) is Number skipped && skipped.Held == 99)
        Console.WriteLine("wrong");
    Console.WriteLine("calls after a false guard: " + Text.FromInteger(source.Calls));

    Console.WriteLine(Describe(source, 42));
    Console.WriteLine(Describe(source, 3));
    Console.WriteLine(Measure(source, 4));
    Console.WriteLine(Measure(source, 2));
    Console.WriteLine(Measure(source, 0));
    Console.WriteLine(Sum(source, 2, 5));
    Console.WriteLine("calls: " + Text.FromInteger(source.Calls));

    Console.WriteLine(IsNamed(new Shape("box"), "box") ? "named box" : "not box");
    Console.WriteLine(IsNamed(null, "box") ? "named nothing" : "nothing is not named");

    // A loop takes the value again on every pass.
    var queue = new List<Tracked>();
    queue.Add(new Tracked("unreached"));
    queue.Add(new Tracked("stop"));
    queue.Add(new Tracked("b"));
    queue.Add(new Tracked("a"));
    while (TakeLast(queue) is Some got && got.Value.Name != "stop")
        Console.WriteLine("got " + got.Value.Name);
    Console.WriteLine("left: " + Text.FromInteger((long)queue.Count));
    return 0;
}
