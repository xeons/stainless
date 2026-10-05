// SPDX-License-Identifier: 0BSD
//
// A base constructor that calls a method its derived class overrides finds
// the derived fields set: they are given their values before the base runs,
// whichever way the base is written -- in the body, after the parameters, or
// left implicit. A late field is given its value once the object is whole.
module FirstPhase;

import Standard.Console;
import Standard.Collections;

public class Shape
{
    public String Seen;

    public Shape()
    {
        Seen = "";
        Seen = "base sees " + Describe();
    }

    public Shape(int sides)
    {
        Seen = "";
        Seen = "base sees " + Describe() + " with " + Standard.Text.FromInteger(sides) + " sides";
    }

    public virtual String Describe() => "a shape";
}

/// `base(...)` in the body, after the fields.
public class Square : Shape
{
    String _name;

    public Square(String name)
    {
        _name = name;
        base(4);
    }

    public override String Describe() => _name;
}

/// `: base(...)` after the parameters, run after the body's first phase.
public class Triangle : Shape
{
    List<String> _corners;

    public Triangle() : base(3)
    {
        _corners = ["a", "b", "c"];
    }

    public override String Describe() => Standard.Text.FromInteger((int)_corners.Count) + " corners";
}

/// The base left implicit: it runs before the first statement that reaches
/// the object.
public class Circle : Shape
{
    String _label;
    late Shape _twin;

    public Circle()
    {
        _label = "a circle";
        _twin = new Square("its twin");
        Seen = Seen + ", then " + _twin.Describe();
    }

    public override String Describe() => _label;
}

int Main()
{
    Console.WriteLine(new Square("a square").Seen);
    Console.WriteLine(new Triangle().Seen);
    Console.WriteLine(new Circle().Seen);
    return 0;
}
