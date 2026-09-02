// SPDX-License-Identifier: 0BSD
module Shapes;

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
    ~Circle() { Console.WriteLine("~Circle"); }

    public double Area() { return 4.0 * radius * radius; }
    public String Describe() { return "circle:" + Text.FromDouble(radius); }
    public String Name() { return "Circle"; }
}

public class Rectangle : IShape {
    double width;
    double height;

    public Rectangle(double w, double h) { width = w; height = h; }

    public double Area() { return width * height; }
    public String Describe() { return "rect:" + Text.FromDouble(width * height); }
}

// The static type here is the interface; both calls dispatch dynamically.
double TotalArea(IShape a, IShape b) { return a.Area() + b.Area(); }

void Report(IShape s) {
    Console.WriteLine(s.Describe() + " area=" + Text.FromDouble(s.Area()));
}

int Main() {
    IShape circle = new Circle(2.0);
    IShape box    = new Rectangle(3.0, 4.0);

    Report(circle);
    Report(box);
    Console.WriteLine("total=" + Text.FromDouble(TotalArea(circle, box)));

    // One class, two interfaces, one vtable each.
    INamed named = new Circle(1.0);
    Console.WriteLine("named=" + named.Name());

    // An optional interface reference is still just a pointer.
    IShape? maybe = null;
    Console.WriteLine("null=" + Text.FromBool(maybe == null));

    maybe = circle;
    Console.WriteLine("set=" + Text.FromBool(maybe != null));
    return 0;
}
