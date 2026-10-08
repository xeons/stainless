// SPDX-License-Identifier: 0BSD
//
// A derived object goes into its base's weak slot as it goes into its base's
// variable, and comes out of a derived slot as its base; an object goes into
// the weak slot of an interface it implements; the slot still empties when
// the object goes.
module WeakDerived;

import Standard.Console;

interface INamed
{
    String Describe();
}

class Shape : INamed
{
    public String Name;
    public Shape(String name) => Name = name;
    public String Describe() => Name;
}

class Square : Shape
{
    public Square() => base("square");
}

class Holder
{
    public weak Shape? Any;
    public weak Square? Exact;
    public weak INamed? Named;
}

String Describe(Shape? shape) => shape == null ? "gone" : ((Shape)shape).Name;

int Main()
{
    var holder = new Holder();
    var square = new Square();
    holder.Any = square;
    holder.Exact = square;
    holder.Named = square;

    Shape? fromBase = holder.Any;
    Shape? fromDerived = holder.Exact;
    Console.WriteLine("held: " + Describe(fromBase) + ", " + Describe(fromDerived));
    INamed? fromInterface = holder.Named;
    Console.WriteLine("through the interface: "
                      + (fromInterface == null ? "gone" : ((INamed)fromInterface).Describe()));
    fromInterface = null;

    fromBase = null;
    fromDerived = null;
    square = new Square();
    Shape? after = holder.Any;
    INamed? afterNamed = holder.Named;
    Console.WriteLine("after: " + Describe(after) + ", " + (afterNamed == null ? "gone" : "held"));
    return 0;
}
