// SPDX-License-Identifier: 0BSD
//
// `is` takes any pattern: `null`, `not null`, a range, a type with a name, a
// value taken apart. What a pattern names is in scope wherever the test is
// known to have come out the way that assigned it -- the rest of an `&&`, the
// arm of a conditional, the branch, and after an `if` whose other branch
// always leaves.
module PatternsIs;

import Standard.Console;
import Standard.Text;

public class Shape { public virtual String Name => "shape"; }

public class Circle : Shape
{
    public double Radius;
    public Circle(double radius) { Radius = radius; }
    public override String Name => "circle";
}

public class Square : Shape
{
    public double Side;
    public Square(double side) { Side = side; }
}

public class Tracked
{
    public String Name;
    public Tracked(String name) { Name = name; }
    ~Tracked() { Console.WriteLine("~" + Name); }
}

public class Box
{
    public Tracked? Held;
    public Box(Tracked? held) { Held = held; }
}

public variant Reading
{
    Missing;
    Value(int Amount);
}

String Describe(Shape? shape)
{
    if (shape is null)
        return "nothing";

    if (shape is Circle { Radius: > 1.0 } big)
        return "big circle " + Text.FromDouble(big.Radius);

    if (shape is Circle small)
        return "circle " + Text.FromDouble(small.Radius);

    // Named under `not`: assigned where the test is false, which is the
    // rest of the function once the `if` has returned.
    if (shape is not Square square)
        return "some " + shape.Name;

    return "square " + Text.FromDouble(square.Side);
}

String Range(int n) => n is > 0 and < 10 ? "digit" : n is 10 or 100 ? "round" : "other";

/// The value is taken once, and what it held has a name for as long as the
/// branch needs it.
String Holding(Box box)
{
    if (box.Held is { Name: var name } held && name.StartsWith("k"))
        return "kept " + held.Name;
    return "not kept";
}

int Amount(Reading reading)
{
    if (reading is not Value(var amount))
        return -1;
    return amount;
}

int Main()
{
    Console.WriteLine(Describe(null));
    Console.WriteLine(Describe(new Circle(2.0)));
    Console.WriteLine(Describe(new Circle(0.5)));
    Console.WriteLine(Describe(new Square(3.0)));
    Console.WriteLine(Describe(new Shape()));

    Console.WriteLine(Range(4));
    Console.WriteLine(Range(100));
    Console.WriteLine(Range(11));

    Console.WriteLine(Holding(new Box(new Tracked("kept"))));
    Console.WriteLine(Holding(new Box(new Tracked("lost"))));
    Console.WriteLine(Holding(new Box(null)));

    Console.WriteLine(Text.FromInteger(Amount(Reading.Value(7))));
    Console.WriteLine(Text.FromInteger(Amount(Reading.Missing)));

    // `is not null` and `is {}` narrow a local, as `!= null` does.
    Shape? maybe = new Circle(1.0);
    if (maybe is not null)
        Console.WriteLine("narrowed " + maybe.Name);
    if (maybe is { } present)
        Console.WriteLine("present " + present.Name);

    Tracked? gone = null;
    if (gone is null)
        Console.WriteLine("gone");

    // A name in a conditional's arm, and one after an early exit in a loop.
    Shape? next = new Square(2.0);
    Console.WriteLine(next is Square s ? "side " + Text.FromDouble(s.Side) : "no side");

    for (int i = 0; i < 3; i++)
    {
        var box = new Box(i == 1 ? null : new Tracked("pass" + Text.FromInteger(i)));
        if (box.Held is not Tracked passing)
            continue;
        Console.WriteLine("passing " + passing.Name);
    }

    Console.WriteLine("end");
    return 0;
}
