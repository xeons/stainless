// SPDX-License-Identifier: 0BSD
module Shapes;

// A package's public surface is what `public` says it is. Everything else in
// here belongs to this module and stops at its edge, whichever way the package
// is linked.

public struct Size {
    public int Width;
    public int Height;

    public int Area() { return Width * Height; }
}

// A class crosses a library boundary with its fields, its properties, its
// methods and its destructor, and the reference count crosses with it: the
// object is made through this library's own TypeInfo, so it is destroyed by the
// destructor this library compiled, whoever drops the last reference to it.
public class Canvas {
    private Size size;
    private int drawn;

    public Canvas(int width, int height) {
        size.Width = width;
        size.Height = height;
        drawn = 0;
    }

    public Size Extent { get { return size; } }
    public int Drawn { get { return drawn; } }

    public void Draw(Size shape) {
        if (shape.Width <= size.Width && shape.Height <= size.Height) {
            drawn = drawn + 1;
        }
    }
}

public Size Square(int side) {
    Size s;
    s.Width = side;
    s.Height = side;
    return s;
}

// Not public: this is the package's own, and a consumer cannot see it however
// it is linked.
int Clamp(int value, int high) {
    return value > high ? high : value;
}
