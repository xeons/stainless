// SPDX-License-Identifier: 0BSD
//
// Every kind of type Stainless has, and every kind of member one may hold.
// Spec sections 2, 4, 6 and 7; the statements that use them are in Tour.sl.
//
// Read it as a catalogue rather than as a program: each declaration is the
// smallest one that shows what the feature is, and the `Show*` functions at
// the bottom of the file exercise them so that the output says whether the
// catalogue is true.
module Tour.Types;

import Standard.Collections;
import Standard.Console;
import Standard.Reflection;
import Tour.Platform;

#region values

// ==================================================================== §2.2

/// A value: copied on assignment, passed per the platform C ABI, laid out with
/// C's field order and padding.
public struct Point {
    public double X;
    public double Y;

    /// A struct may have methods. It has no constructor: `Point p;` is how one
    /// comes into being, and every field starts at zero.
    public double LengthSquared() { return X * X + Y * Y; }
}

/// A struct may hold a *reference*, and then copying it retains and dropping it
/// releases. What that costs is the C guarantee, and only for this struct.
public struct Labelled {
    public String Name;
    public int    Weight;
}

// ==================================================================== §2.3

/// `[Packed]` removes the padding, so the double is not 8-aligned.
[Packed]
public struct Squeezed {
    public byte   Flag;
    public double Value;
}

/// `[Align]` raises the alignment, and with it the size.
[Align(16)]
public struct Wide {
    public int A;
}

/// Bit-fields, laid out as the target's C ABI lays them out -- which is not the
/// same on Windows and on Linux, so the tour reads and writes them rather than
/// printing their size.
public struct Packet {
    public uint Kind  : 3;
    public uint Level : 5;
    public uint Rest  : 24;
}

// ==================================================================== §2.7

/// Every member at offset zero.
public union Word {
    public int   Signed;
    public uint  Unsigned;
    public float Real;
}

/// Nameless `struct` and `union` members, as C has them: the Windows headers
/// lean on these constantly.
public union LargeInteger {
    public struct {
        public uint Low;
        public int  High;
    }
    public long Quad;
}

// ==================================================================== §2.11

/// An inline fixed-size array: this *is* its elements, so the struct is
/// exactly as wide as the C one it mirrors.
public struct Matrix {
    public double[4] Cell;
}

#endregion
#region enumerations

// ==================================================================== §2.13

/// A distinct type over an integer, with a named base and explicit values.
public enum Level : byte {
    Low = 1,
    Warning = 10,
    Severe,          // 11, one past the last
    Fatal = 200,
}

/// `[Flags]` is what makes `HasFlag` and the bitwise operators legal.
[Flags]
public enum Access : uint {
    None    = 0u,
    Read    = 1u,
    Write   = 2u,
    Execute = 4u,
    All     = 7u,
}

#endregion
#region variants

// ==================================================================== §2.6

/// A value that is one of several things, each carrying what it needs.
public variant Shape {
    Circle(double Radius);
    Rect(double Width, double Height);
    Empty;
}

/// A variant may be generic, and a case may carry a counted reference -- so
/// copying one has to ask the tag what is really in there.
///
/// **A variant is a value**, and a value cannot contain itself, so the
/// recursion goes through a class: `Branch<T>` is a reference, which is one
/// pointer whatever the tree does. That is the same rule C has, arrived at from
/// the same place, and it is SL0216 when it is broken.
public variant Tree<T> {
    Leaf(T Item);
    Node(Branch<T> Pair);
    Nothing;
}

public class Branch<T> {
    public Tree<T> Left { get; }
    public Tree<T> Right { get; }

    public Branch(Tree<T> left, Tree<T> right) {
        Left = left;
        Right = right;
    }
}

#endregion
#region contracts

// ==================================================================== §2.10

public interface INamed {
    String Name();
}

/// An interface may extend another, and then implementing it means supplying
/// both.
public interface IDrawable : INamed {
    String Draw();
}

#endregion
#region classes

// ==================================================================== §2.4

/// A reference type, managed by ARC. `abstract` means it cannot be made
/// directly; `protected` is the base's own view.
public abstract class Figure : IDrawable {
    protected int sides;
    protected String tag;

    /// A constructor with no `public` is reachable only inside the module.
    Figure(int howMany, String called) {
        sides = howMany;
        tag = called;
    }

    /// No body, so a derived class has to supply one.
    public abstract double Area();

    /// A body, which a derived class may take or replace.
    public virtual String Name() { return "figure"; }

    public virtual String Draw() {
        return Name() + " with " + Text.FromInteger((long)sides) + " sides";
    }

    /// Not virtual, and reads a protected field.
    public int Sides() { return sides; }

    public String Tag { get { return tag; } }
}

public class Polygon : Figure {
    protected double width;

    Polygon(int howMany, double w) {
        base(howMany, "polygon");     // must be the first statement
        width = w;
    }

    public override double Area() { return width * width; }
    public override String Name() { return "polygon"; }

    /// Reaching the base's implementation, which the dispatch table would
    /// never find.
    public override String Draw() { return "a " + base.Draw(); }
}

/// `sealed` closes the chain, and `this(...)` delegates to another constructor
/// of the same class.
public sealed class Square : Polygon {
    public int Corners;

    public Square(double side) {
        base(4, side);
        Corners = 4;
    }

    public Square() { this(1.0); }
}

/// A destructor, which is the only way to watch a reference count from inside
/// the language.
public class Loud {
    public String Label { get; }

    public Loud(String label) { Label = label; }

    ~Loud() { Console.WriteLine("      dropped " + Label); }
}

/// A weak reference is the only way to break a cycle, ARC being unable to
/// collect one. The slot's type is what makes the store count weakly.
public class Child {
    public int Id;
    public weak Parent? Owner;

    public Child(int id) { Id = id; }
}

public class Parent {
    public int Id;
    public Child? Kid;

    public Parent(int id) { Id = id; }
}

// ==================================================================== §9.4

/// `foreach` is a shape rather than an interface: anything with a
/// `GetEnumerator()` whose answer has `MoveNext()` and `Current()` works, and
/// the standard library's `IEnumerable<T>` is one thing of that shape rather
/// than the definition of it.
public class Countdown {
    int from;

    public Countdown(int start) { from = start; }

    public CountdownCursor GetEnumerator() { return new CountdownCursor(from); }
}

public class CountdownCursor {
    int value;

    public CountdownCursor(int start) { value = start + 1; }

    public bool MoveNext() {
        value--;
        return value > 0;
    }

    public int Current() { return value; }
}

#endregion
