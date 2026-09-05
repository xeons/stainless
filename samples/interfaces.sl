// SPDX-License-Identifier: 0BSD
module Interfaces;

import Standard.Console;

public interface IShape {
    double Area();
    String Describe();
}

public interface INamed {
    String Name();
}

public class Circle : IShape, INamed {
    double radius;

    public Circle(double r) { radius = r; }
    ~Circle() { Console.WriteLine("  ~Circle"); }

    public double Area() { return 3.14159265 * radius * radius; }
    public String Describe() { return "circle of radius " + Text.FromDouble(radius); }
    public String Name() { return "Circle"; }
}

public class Rectangle : IShape {
    double width;
    double height;

    public Rectangle(double w, double h) { width = w; height = h; }

    public double Area() { return width * height; }
    public String Describe() { return "rectangle " + Text.FromDouble(width) + "x" + Text.FromDouble(height); }
}

// Dispatch happens through the interface, not the concrete class.
double TotalArea(IShape a, IShape b) { return a.Area() + b.Area(); }

void Report(IShape s) {
    var line = new StringBuilder();
    line.Append("  ");
    line.Append(s.Describe());
    line.Append(" -> area ");
    line.AppendDouble(s.Area());
    Console.WriteLine(line.ToText());
}

int Main() {
    IShape circle = new Circle(2.0);
    IShape box    = new Rectangle(3.0, 4.0);

    Report(circle);
    Report(box);
    Console.WriteLine("total = " + Text.FromDouble(TotalArea(circle, box)));

    // A class may implement several interfaces; each gets its own vtable.
    INamed named = new Circle(1.0);
    Console.WriteLine("named = " + named.Name());

    // StringBuilder makes repeated appending linear instead of quadratic.
    var builder = new StringBuilder();
    for (int i = 0; i < 5; i += 1) {
        builder.AppendInteger(i);
        builder.Append(",");
    }
    Console.WriteLine("built = " + builder.ToText());
    Console.WriteLine("length = " + Text.FromInteger(builder.ByteLength()));
    return 0;
}
