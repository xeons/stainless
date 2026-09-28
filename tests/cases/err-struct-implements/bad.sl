// SPDX-License-Identifier: 0BSD
module Bad;

public interface IShape { double Area(); }

// A struct may implement an interface, and must supply its members.
public struct Point : IShape
{
    public double X;
    public double Area() => X;
}

public struct Hollow : IShape { }                       // SL0305

double Measure(IShape shape) => shape.Area();

int Main()
{
    Point p;
    p.X = 1.0;

    // It still cannot become a reference to the interface.
    IShape held = p;                                    // SL0302
    return (int)Measure(p);                             // SL0302
}
