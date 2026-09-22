// SPDX-License-Identifier: 0BSD
//
// A library whose structs are made with `new`. The constructor crosses as the
// symbol it is, called with the address of the consumer's own slot -- so the
// value is built in the consumer's frame and nothing is allocated either side.
module Library.Geometry;

public struct Point
{
    public int X;
    public int Y;

    public Point(int x, int y)
    {
        X = x;
        Y = y;
    }

    public Point(int both) : this(both, both) { }

    public int Sum => X + Y;
}

public struct Extent
{
    public nuint Width;
    public nuint Height;
    public nuint Margin;

    public Extent(nuint width, nuint height = 4u)
    {
        Width = width;
        Height = height;
    }

    public nuint Area() => Width * Height;
}
