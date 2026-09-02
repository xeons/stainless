module Shapes;

import Standard.Console;

public interface Shape {
    double Area();
    String Describe();
}

public interface Named {
    String Name();
}

public class Circle : Shape, Named {
    double radius;

    public Circle(double r) { radius = r; }
    ~Circle() { Console.WriteLine("~Circle"); }

    public double Area() { return 4.0 * radius * radius; }
    public String Describe() { return "circle:" + Text.FromDouble(radius); }
    public String Name() { return "Circle"; }
}

public class Rectangle : Shape {
    double width;
    double height;

    public Rectangle(double w, double h) { width = w; height = h; }

    public double Area() { return width * height; }
    public String Describe() { return "rect:" + Text.FromDouble(width * height); }
}

// The static type here is the interface; both calls dispatch dynamically.
double TotalArea(Shape a, Shape b) { return a.Area() + b.Area(); }

void Report(Shape s) {
    Console.WriteLine(s.Describe() + " area=" + Text.FromDouble(s.Area()));
}

int Main() {
    Shape circle = new Circle(2.0);
    Shape box    = new Rectangle(3.0, 4.0);

    Report(circle);
    Report(box);
    Console.WriteLine("total=" + Text.FromDouble(TotalArea(circle, box)));

    // One class, two interfaces, one vtable each.
    Named named = new Circle(1.0);
    Console.WriteLine("named=" + named.Name());

    // An optional interface reference is still just a pointer.
    Shape? maybe = null;
    Console.WriteLine("null=" + Text.FromBool(maybe == null));

    maybe = circle;
    Console.WriteLine("set=" + Text.FromBool(maybe != null));
    return 0;
}
