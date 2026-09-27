// SPDX-License-Identifier: 0BSD
//
// A field whose type was not found is reported once, where it is written,
// and a read of the variant it belongs to says nothing more about it.
module Bad;

variant Shape
{
    Circle(Doubel Radius);
    Rect(double Width);
}

double Width(Shape shape)
{
    if (shape.Circle)
        return shape.Width;
    return 0;
}

int Main() => 0;
