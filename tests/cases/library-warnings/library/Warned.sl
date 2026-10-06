// What a library's metadata cannot carry, said where the library is built.
//
// Each of these is public and each is left out, and the point of warning here
// rather than there is that the library's author can do something about it: a
// consumer would only find a public name that will not resolve.
module Warned;

/// An interface. Dispatch through one is indexed by an id assigned across a
/// whole program, and a library and its consumer are two programs.
public interface IShape { double Area(); }      // SL0419

/// A com interface. This one is not about ids: what identifies a COM interface
/// is its IID and the order of its vtable, and a consumer states both for
/// itself, exactly as a C header does.
[Guid("3e5c1a08-7b42-4f96-8d13-c05a2e647b9f")]
public com interface ICounter { int Value(); }  // SL0419

/// A com class. Its vtables and adjustor thunks are internal symbols of the
/// library, and a consumer's `new` would have to point at them.
public com class Counter : ICounter // SL0419
{
    public int Value() => 1;
}

/// A class implementing an interface. Its dispatch table is indexed by an id
/// assigned across a whole program, and a library and its consumer are two
/// programs -- so the table built there would be indexed by the wrong ids.
public class Circle : IShape // SL0419
{
    public double Radius;
    Circle(double r) => Radius = r;
    public double Area() => 3.0 * Radius * Radius;
}

/// A generic. A template emits nothing until it is instantiated, and a consumer
/// holding only the binary has nothing to instantiate.
public class Box<T> // SL0419
{
    public T Held;
    Box(T value) => Held = value;
}

/// A variant. Its cases are what a consumer would switch on, and the metadata
/// carries layouts rather than cases.
public variant Shape // SL0419
{
    Round(double radius);
    Empty;
}

/// A class with a generic virtual method. Each instantiation the program calls
/// is a slot numbered after every other, and a class derived from it elsewhere
/// would put its own methods in those slots.
public class Formatter // SL0419
{
    Formatter() { }
    public virtual String Format<T>(T value) => "?";
}

/// What does cross, so the consumer has something to be built against.
public struct Point
{
    public double X;
    public double Y;
}

public Point Doubled(Point p)
{
    Point result;
    result.X = p.X * 2.0;
    result.Y = p.Y * 2.0;
    return result;
}
