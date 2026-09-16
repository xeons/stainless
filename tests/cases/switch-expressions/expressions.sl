// SPDX-License-Identifier: 0BSD
//
// `value switch { pattern => result, ... }`: the expression form, and the one
// that has to be exhaustive. A statement that matches nothing falls past
// itself; an expression that matched nothing would have no value to be, and
// there are no exceptions here to throw at the hole.
//
// It lowers to the value held in a name and a conditional per arm, which is
// what it means -- so nothing in it can do what a ternary chain could not.
module SwitchExpressions;

import Standard.Console;
import Standard.Text;

public enum Level { Low, Warning, Severe }

public variant Shape
{
    Circle(double Radius);
    Rect(double Width, double Height);
    Empty;
}

public class Node { }
public class Leaf : Node { public int Value = 4; }

String Describe(Level level)
{
    return level switch
    {
        Level.Low => "low",
        Level.Warning => "warning",
        _ => "severe",
    };
}

double Area(Shape shape)
{
    return shape switch
    {
        Circle c => 3.14159 * c.Radius * c.Radius,
        Rect r => r.Width * r.Height,
        Empty => 0.0,
    };
}

String Size(int n)
{
    return n switch
    {
        < 0 => "negative",
        0 => "zero",
        1 or 2 => "small",
        < 10 => "medium",
        _ => "large",
    };
}

String Guarded(Shape shape)
{
    return shape switch
    {
        Circle c when c.Radius > 10.0 => "big circle",
        Circle c => "circle " + Text.FromDouble(c.Radius),
        _ => "other",
    };
}

String Kind(Node node)
{
    return node switch
    {
        Leaf leaf => "leaf " + Text.FromInteger(leaf.Value),
        _ => "node",
    };
}

int Main()
{
    Console.WriteLine(Describe(Level.Low));
    Console.WriteLine(Describe(Level.Severe));

    Console.WriteLine(Text.FromDouble(Area(Circle(2.0))));
    Console.WriteLine(Text.FromDouble(Area(Rect(3.0, 4.0))));
    Console.WriteLine(Text.FromDouble(Area(Empty())));

    Console.WriteLine(Size(-3));
    Console.WriteLine(Size(0));
    Console.WriteLine(Size(2));
    Console.WriteLine(Size(7));
    Console.WriteLine(Size(70));

    Console.WriteLine(Guarded(Circle(20.0)));
    Console.WriteLine(Guarded(Circle(1.0)));
    Console.WriteLine(Guarded(Empty()));

    Console.WriteLine(Kind(new Leaf()));
    Console.WriteLine(Kind(new Node()));
    return 0;
}
