// SPDX-License-Identifier: 0BSD
module Alpha;

import Standard.Collections;

public struct Point
{
    public int X;
    public int Y;
}

public T Same<T>(T value) => value;

public int SumAlpha()
{
    Point p;
    p.X = 1;
    p.Y = 2;

    var list = new List<Point>();
    list.Add(p);

    (Point, int) pair = (p, 10);
    Span<Point> slice = new Point[1];
    slice[0] = p;
    var measure = (Point q) => q.X + q.Y;
    Func<Point, int> fn = q => q.Y;
    List<Point*> addresses = new List<Point*>();
    addresses.Add(&p);

    return list[0].X + list[0].Y + pair.Item2 + slice[0].Y + measure(p) + fn(p)
        + Same(p).X + addresses[0]->Y;
}
