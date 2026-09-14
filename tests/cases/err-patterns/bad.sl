// SPDX-License-Identifier: 0BSD
//
// What a pattern may not ask, and what a switch expression may not leave out.
module Bad;

public variant Shape {
    Circle(double Radius);
    Empty;
}

public class Node { }
public interface IThing { void Do(); }

// An expression has to produce a value whatever it is given.
String Partial(int n) {
    return n switch {
        0 => "zero",
        1 => "one",
    };
}

// And so does one over a variant that leaves a case out.
double Uncovered(Shape shape) {
    return shape switch {
        Circle c => c.Radius,
    };
}

// A name under 'or' would have nothing to be: which side matched is not known.
String Named(Shape shape) {
    return shape switch {
        Circle c or Empty => "something",
        _ => "other",
    };
}

// A reference does not convert down to an interface, so there is nothing for
// the name to be.
String Contract(Node node) {
    return node switch {
        IThing thing => "thing",
        _ => "other",
    };
}

// A value is exactly what it was declared to be.
String OnInt(int n) {
    switch (n) {
        case Shape s: return "shape";
        default: return "other";
    }
}

// Nothing reaches an arm after one that matches everything.
String After(int n) {
    return n switch {
        _ => "anything",
        0 => "zero",
    };
}

int Main() { return 0; }
