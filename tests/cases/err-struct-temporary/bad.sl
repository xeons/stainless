// SPDX-License-Identifier: 0BSD
module Bad;

import Standard.Collections;

// A struct a call, a property or an indexer answered is a copy nothing keeps,
// so a write to one of its fields would be thrown away with it. An element of
// an array is storage, and is written in place.
struct Point
{
    public int X;
    public int Y;
}

class Shape
{
    public Point Origin { get; set; }
}

Point MakePoint()
{
    Point made;
    return made;
}

int Main()
{
    var points = new List<Point>();
    points.Add(MakePoint());
    points[0u].X = 5;

    var shape = new Shape();
    shape.Origin.X = 7;

    MakePoint().X = 3;
    MakePoint().Y += 3;
    MakePoint().X++;

    var stored = new Point[2];
    stored[1].X = 4;
    return stored[1].X;
}
