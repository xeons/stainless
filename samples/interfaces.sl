// SPDX-License-Identifier: 0BSD
module Interfaces;

import Standard.Console;

public interface IShape
{
    double Area { get; }
    String Description { get; }
}

public interface INamed
{
    String Name { get; }
}

public class Circle : IShape, INamed
{
    double _radius;

    public Circle(double r) => _radius = r;
    ~Circle() { Console.WriteLine("  ~Circle"); }

    public double Area => 3.14159265 * _radius * _radius;
    public String Description => "circle of radius " + Text.FromDouble(_radius);
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

    public double Area => _width * _height;
    public String Description =>
        "rectangle " + Text.FromDouble(_width) + "x" + Text.FromDouble(_height);
}

// Dispatch happens through the interface, not the concrete class.
double SumAreas(IShape a, IShape b) => a.Area + b.Area;

void ReportShape(IShape s)
{
    var line = new StringBuilder();
    line.Append("  ");
    line.Append(s.Description);
    line.Append(" -> area ");
    line.AppendDouble(s.Area);
    Console.WriteLine(line.ToText());
}

int Main()
{
    IShape circle = new Circle(2.0);
    IShape box    = new Rectangle(3.0, 4.0);

    ReportShape(circle);
    ReportShape(box);
    Console.WriteLine("total = " + Text.FromDouble(SumAreas(circle, box)));

    // A class may implement several interfaces; each gets its own vtable.
    INamed named = new Circle(1.0);
    Console.WriteLine("named = " + named.Name);

    // StringBuilder makes repeated appending linear instead of quadratic.
    var builder = new StringBuilder();
    for (int i = 0; i < 5; i++)
    {
        builder.AppendInteger(i);
        builder.Append(",");
    }
    Console.WriteLine("built = " + builder.ToText());
    Console.WriteLine("length = " + Text.FromInteger(builder.ByteLength()));
    return 0;
}
