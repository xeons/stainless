// SPDX-License-Identifier: 0BSD
module Shapes;

import Standard.Console;

public interface IShape
{
    double Area();
    String Describe();
}

public interface INamed
{
    String Name { get; }
}

public class Circle : IShape, INamed
{
    double _radius;

    public Circle(double r) => _radius = r;
    ~Circle() { Console.WriteLine("~Circle"); }

    public double Area() => 4.0 * _radius * _radius;
    public String Describe() => "circle:" + Text.FromDouble(_radius);
    public String Name => "Circle";
}

public class Rectangle : IShape
{
    double _width;
    double _height;

    public Rectangle(double w, double h)
    {
        _width = w;
        _height = h;
    }

    public double Area() => _width * _height;
    public String Describe() => "rect:" + Text.FromDouble(_width * _height);
}

// The static type here is the interface; both calls dispatch dynamically.
double TotalArea(IShape a, IShape b) => a.Area() + b.Area();

void Report(IShape s)
{
    Console.WriteLine(s.Describe() + " area=" + Text.FromDouble(s.Area()));
}

int Main()
{
    IShape circle = new Circle(2.0);
    IShape box    = new Rectangle(3.0, 4.0);

    Report(circle);
    Report(box);
    Console.WriteLine("total=" + Text.FromDouble(TotalArea(circle, box)));

    // One class, two interfaces, one vtable each.
    INamed named = new Circle(1.0);
    Console.WriteLine("named=" + named.Name);

    // An optional interface reference is still just a pointer.
    IShape? maybe = null;
    Console.WriteLine("null=" + Text.FromBool(maybe == null));

    maybe = circle;
    Console.WriteLine("set=" + Text.FromBool(maybe != null));
    return 0;
}
