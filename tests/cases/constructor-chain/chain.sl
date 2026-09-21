// SPDX-License-Identifier: 0BSD
//
// `: base(...)` and `: this(...)` after a constructor's parameters.
//
// The same call the body could have made as its first statement, written where
// C# writes it. What is pinned is that the two spellings do the same thing, in
// every shape a constructor comes in: a braced body, an arrow body, a body with
// nothing in it, and a chain that reaches the base through another constructor
// rather than directly.
module ConstructorChain;

import Standard.Console;
import Standard.Text;

class Shape
{
    public int Sides;
    public String Label;

    public Shape(int sides, String label)
    {
        Sides = sides;
        Label = label;
    }
}

class Square : Shape
{
    public double Side;

    /// The clause, with a braced body after it.
    public Square(double side) : base(4, "square")
    {
        Side = side;
    }

    /// The clause, with an arrow body after it.
    public Square(int whole) : base(4, "whole") => Side = (double)whole;

    /// Delegating to one of this class's own, which builds the base for it.
    public Square() : this(1.0) { }

    /// Two hops: to a constructor that itself chains to the base.
    public Square(bool unit) : this(unit ? 1.0 : 2.0) { }
}

class Triangle : Shape
{
    /// The statement form, which means the same and still works.
    public Triangle()
    {
        base(3, "triangle");
    }
}

/// A chain through three classes, so the order they run in is visible.
class Root
{
    public String Trail;
    public Root() { Trail = "root"; }
}

class Middle : Root
{
    public Middle() : base() { Trail = Trail + "/middle"; }
}

class Leaf : Middle
{
    public Leaf() : base() { Trail = Trail + "/leaf"; }
}

void Say(String what, String value)
{
    Console.WriteLine(what + " " + value);
}

int Main()
{
    var braced = new Square(2.5);
    Say("braced", braced.Label + " " + Text.FromInteger((long)braced.Sides)
                  + " " + Text.FromDouble(braced.Side));

    var arrow = new Square(7);
    Say("arrow", arrow.Label + " " + Text.FromDouble(arrow.Side));

    var delegated = new Square();
    Say("delegated", delegated.Label + " " + Text.FromDouble(delegated.Side));

    var twice = new Square(true);
    Say("twohops", twice.Label + " " + Text.FromDouble(twice.Side));

    var statement = new Triangle();
    Say("statement", statement.Label + " " + Text.FromInteger((long)statement.Sides));

    // The base runs before the body that chained to it, at every level.
    Say("order", new Leaf().Trail);

    return 0;
}
