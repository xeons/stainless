// What a library's metadata cannot carry, said where the library is built.
//
// Each of these is public and each is left out, and the point of warning here
// rather than there is that the library's author can do something about it: a
// consumer would only find a public name that will not resolve.
module Warned;

public interface IShape { double Area(); }

/// A class implementing an interface. Its dispatch table is indexed by an id
/// assigned across a whole program, and a library and its consumer are two
/// programs -- so the table built there would be indexed by the wrong ids.
public class Circle : IShape {                  // SL0420
    public double Radius;
    Circle(double r) { Radius = r; }
    public double Area() { return 3.0 * Radius * Radius; }
}

/// A generic. A template emits nothing until it is instantiated, and a consumer
/// holding only the binary has nothing to instantiate.
public class Box<T> {                           // SL0419
    public T Held;
    Box(T value) { Held = value; }
}

/// A variant. Its cases are what a consumer would switch on, and the metadata
/// carries layouts rather than cases.
public variant Shape {                          // SL0441
    Round(double radius);
    Empty;
}

/// What does cross, so the consumer has something to be built against.
public struct Point {
    public double X;
    public double Y;
}

public Point Doubled(Point p) {
    Point result;
    result.X = p.X * 2.0;
    result.Y = p.Y * 2.0;
    return result;
}
