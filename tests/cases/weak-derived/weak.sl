// SPDX-License-Identifier: 0BSD
//
// A derived object goes into its base's weak slot as it goes into its base's
// variable, and comes out of a derived slot as its base; the slot still
// empties when the object goes.
module WeakDerived;

import Standard.Console;

class Shape
{
    public String Name;
    public Shape(String name) => Name = name;
}

class Square : Shape
{
    public Square() => base("square");
}

class Holder
{
    public weak Shape? Any;
    public weak Square? Exact;
}

String Describe(Shape? shape) => shape == null ? "gone" : ((Shape)shape).Name;

int Main()
{
    var holder = new Holder();
    var square = new Square();
    holder.Any = square;
    holder.Exact = square;

    Shape? fromBase = holder.Any;
    Shape? fromDerived = holder.Exact;
    Console.WriteLine("held: " + Describe(fromBase) + ", " + Describe(fromDerived));

    fromBase = null;
    fromDerived = null;
    square = new Square();
    Shape? after = holder.Any;
    Console.WriteLine("after: " + Describe(after));
    return 0;
}
