// SPDX-License-Identifier: 0BSD
module Bad;

public variant Shape {
    Circle(double Radius);
    Rect(double Width, double Height);
    Empty;
}

// Rect and Empty have no answer, and there is no default.
double Missing(Shape shape) {
    switch (shape) {
        case Circle c: return c.Radius;
    }
    return 0.0;
}

// The same case twice.
double Twice(Shape shape) {
    switch (shape) {
        case Circle: return 1.0;
        case Circle: return 2.0;
        default: return 0.0;
    }
}

// Two cases share the arm, so nothing has said what is in there to bind.
double Both(Shape shape) {
    switch (shape) {
        case Circle: case Rect r: return r.Width;
        default: return 0.0;
    }
}

// A case that carries nothing has nothing to bind.
double Nothing(Shape shape) {
    switch (shape) {
        case Empty e: return 0.0;
        default: return 1.0;
    }
}

// Not a variant at all.
int OnInt(int n) {
    switch (n) {
        case Circle c: return 1;
        default: return 0;
    }
}

int Main() { return 0; }
