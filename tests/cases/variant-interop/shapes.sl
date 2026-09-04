// SPDX-License-Identifier: 0BSD
//
// A variant carrying no references is a plain C value, so it crosses
// `export "C"` like any other struct: a tag, then the bytes of whichever case
// the tag names. The generated header says the shape and the C consumer reads
// it back, which is the only way to check that the two agree.
module Library.Shapes;

public variant Shape {
    Circle(double Radius);
    Rect(double Width, double Height);
    Empty;
}

export "C" Shape MakeCircle(double radius) { return Shape.Circle(radius); }
export "C" Shape MakeRect(double width, double height) { return Shape.Rect(width, height); }
export "C" Shape MakeEmpty() { return Shape.Empty; }

export "C" double Area(Shape shape) {
    switch (shape) {
        case Circle c: return 3.14159 * c.Radius * c.Radius;
        case Rect r:   return r.Width * r.Height;
        case Empty:    return 0.0;
    }
}
