// SPDX-License-Identifier: 0BSD
module Geometry;

public struct Vec2
{
    public double X;
    public double Y;

    public double Length2() => X * X + Y * Y;
}

public double Dot(Vec2 a, Vec2 b)
{
    return a.X * b.X + a.Y * b.Y;
}

public class Accumulator
{
    double _total;

    public Accumulator() => _total = 0.0;

    public void Add(double value) => _total += value;
    public double Total() => _total;
}
