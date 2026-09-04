// SPDX-License-Identifier: 0BSD
module Bad;

public variant Shape {
    Circle(double Radius);
    Rect(double Width, double Height);
}

Shape Make() { return Shape.Circle(1.0); }

// Nothing has established which case it is.
double Unchecked(Shape shape) {
    return shape.Radius;
}

// It is known to be a Circle, so Width is the wrong case's field.
double WrongCase(Shape shape) {
    if (shape.Circle) { return shape.Width; }
    return 0.0;
}

// A call result is not something a check can be about.
double NotHeld() { return Make().Radius; }

// One value does not say what a generic variant's arguments are.
int Inferred() {
    var c = Circle(1.0);
    return 0;
}

// The wrong number of fields for the case.
Shape TooFew() { return Shape.Rect(1.0); }

// No such case.
Shape NoSuch() { return Shape.Blob(1.0); }

// A module-level function may not shadow a case name.
int Circle(int n) { return n; }

int Main() { return 0; }
