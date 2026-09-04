// Class inheritance, the C# model: single inheritance, virtual/override/
// abstract/sealed, base chaining, protected, and a downcast that checks.
//
// The object model is what makes it cheap. A class reference points at the
// object header and the fields follow it, so with one base the base subobject
// starts where the derived object does: an upcast is the same pointer, and
// `sl_retain` goes on taking the object's own address. Everything here leans on
// that being true, and the field values are how it is checked.
module Inheritance;

import Standard.Console;
import Standard.Text;

public interface INamed {
    String Name();
}

/// The root: abstract, so it cannot be made, and every concrete class below
/// has to answer `Area`.
public abstract class Shape : INamed {
    protected int  sides;
    protected bool closed;

    Shape(int howMany) {
        sides = howMany;
        closed = true;
    }

    public abstract double Area();

    /// Virtual with a body: a derived class may take it or replace it.
    public virtual String Describe() {
        return Name() + " with " + Text.FromInteger(sides) + " sides";
    }

    public virtual String Name() { return "shape"; }

    /// Not virtual, and reads a protected field: the base's own view.
    public int Sides() { return sides; }
}

/// One level down: overrides the abstract method and adds a field of its own,
/// which has to land after the base's.
public class Polygon : Shape {
    protected double width;

    Polygon(int howMany, double w) {
        base(howMany);
        width = w;
    }

    public override double Area() { return width * width; }

    public override String Name() { return "polygon"; }

    /// Reaching the base's implementation, which the vtable would never find.
    public override String Describe() {
        return "a " + base.Describe();
    }
}

/// Two levels down, and sealed: nothing may derive further.
public sealed class Square : Polygon {
    int corners;

    Square(double side) {
        base(4, side);
        corners = 4;
    }

    /// Sealed on an override closes the chain at this class.
    public sealed override String Name() { return "square"; }

    public int Corners() { return corners; }
}

/// A sibling, so the family is a tree rather than a line.
public class Circle : Shape {
    double radius;

    Circle(double r) {
        base(1);
        radius = r;
        closed = true;
    }

    public override double Area() { return 3.0 * radius * radius; }
    public override String Name() { return "circle"; }
}

/// The end of the line for construction: it takes no arguments itself, so
/// anything below it can be built without saying anything.
public class Dot : Shape {
    Dot() {
        base(1);
    }

    public override double Area() { return 0.0; }
    public override String Name() { return "dot"; }
}

/// A class that declares no constructor at all. `new Point()` runs the nearest
/// one up the chain that takes no arguments, which is Dot's.
public class Point : Dot {
}

/// One that declares a constructor but no chain: the same constructor runs,
/// inserted at the head of this one.
public class Pixel : Dot {
    int shade;

    Pixel(int level) {
        shade = level;
    }

    public int Shade() { return shade; }
    public override String Name() { return "pixel"; }
}

/// An abstract property is a pair of abstract accessors, and both dispatch --
/// a setter for the same reason a getter does.
public abstract class Node {
    public abstract int    Weight { get; }
    public abstract String Tag    { get; set; }

    public String Summary() { return Tag + "=" + Text.FromInteger(Weight); }
}

public class Twig : Node {
    String held;

    Twig() { held = "twig"; }

    public override int Weight { get { return 1; } }

    public override String Tag {
        get { return held; }
        set { held = value; }
    }
}

/// `this(...)` runs another of this class's own constructors first. The one it
/// delegates to builds the base, so the base is built once and not twice.
public class Built : Shape {
    public int Steps;

    Built(int howMany, int steps) {
        base(howMany);
        Steps = steps;
    }

    Built(int steps) { this(2, steps); }

    Built() {
        this(5);
        Steps = Steps + 100;
    }

    public override double Area() { return 0.0; }
    public override String Name() { return "built"; }
}

/// Three deep, with a destructor at every level and a reference held at two of
/// them, so what a drop runs and in which order is the whole of what it shows.
public class Held {
    public String Tag;
    Held(String tag) { Tag = tag; }
    ~Held() { Console.WriteLine("    ~Held " + Tag); }
}

public class Root {
    Held mine;
    Root() { mine = new Held("root"); }
    ~Root() { Console.WriteLine("  ~Root"); }
}

public class Middle : Root {
    Held ours;
    Middle() { ours = new Held("middle"); }
    ~Middle() { Console.WriteLine("  ~Middle"); }
}

public class Leaf : Middle {
    ~Leaf() { Console.WriteLine("  ~Leaf"); }
}

/// Virtual properties: the accessors are the methods, so they dispatch like any
/// other pair.
public class Counter {
    protected int held;

    public virtual int Value { get { return held; } }

    Counter(int start) { held = start; }
}

public class Doubling : Counter {
    Doubling(int start) {
        base(start);
    }

    public override int Value { get { return held * 2; } }
}

void Show(Shape shape) {
    Console.WriteLine(shape.Describe()
        + ", area " + Text.FromDouble(shape.Area())
        + ", sides " + Text.FromInteger(shape.Sides()));
}

int Main() {
    // --- dispatch through the base -----------------------------------------
    Shape square = new Square(3.0);
    Shape circle = new Circle(2.0);
    Shape polygon = new Polygon(6, 5.0);

    Show(square);
    Show(circle);
    Show(polygon);

    // --- an interface the base implements and a derived class overrides -----
    INamed named = square;
    Console.WriteLine("through the interface: " + named.Name());

    // --- what the object really is -----------------------------------------
    Console.WriteLine("square is Square: " + Text.FromBool(square is Square));
    Console.WriteLine("square is Polygon: " + Text.FromBool(square is Polygon));
    Console.WriteLine("circle is Polygon: " + Text.FromBool(circle is Polygon));
    Console.WriteLine("circle is INamed: " + Text.FromBool(circle is INamed));

    // --- a downcast, once the question has been asked -----------------------
    if (square is Square) {
        Square back = (Square)square;
        Console.WriteLine("corners: " + Text.FromInteger(back.Corners()));
    }

    // --- fields land after the base's, and both are readable ----------------
    Square direct = new Square(7.0);
    Console.WriteLine("sides " + Text.FromInteger(direct.Sides())
        + ", corners " + Text.FromInteger(direct.Corners())
        + ", area " + Text.FromDouble(direct.Area()));

    // --- a class with no constructor of its own -----------------------------
    Dot dot = new Dot();
    Console.WriteLine("dot sides: " + Text.FromInteger(dot.Sides()));

    Point point = new Point();
    Console.WriteLine("point sides: " + Text.FromInteger(point.Sides())
        + ", name " + point.Name());

    Pixel pixel = new Pixel(9);
    Console.WriteLine("pixel sides: " + Text.FromInteger(pixel.Sides())
        + ", shade " + Text.FromInteger(pixel.Shade())
        + ", name " + pixel.Name());

    // --- virtual properties -------------------------------------------------
    Counter plain = new Counter(21);
    Counter doubling = new Doubling(21);
    Console.WriteLine("counter " + Text.FromInteger(plain.Value)
        + ", doubling " + Text.FromInteger(doubling.Value));

    // --- abstract properties, both halves dispatching -----------------------
    Node node = new Twig();
    Console.WriteLine("node: " + node.Summary());
    node.Tag = "renamed";
    Console.WriteLine("renamed: " + node.Summary());

    // --- this(...) delegation, and the base built exactly once ---------------
    Built once = new Built();
    Console.WriteLine("delegated: sides " + Text.FromInteger(once.Sides())
        + ", steps " + Text.FromInteger(once.Steps)
        + ", name " + once.Name());

    // --- an array of the base, holding three different classes --------------
    Shape[] every = new Shape[3];
    every[0] = square;
    every[1] = circle;
    every[2] = polygon;

    double total = 0.0;
    foreach (Shape one in every) { total = total + one.Area(); }
    Console.WriteLine("total area: " + Text.FromDouble(total));

    // --- destructors chain, derived first ------------------------------------
    //
    // Outside in: a derived destructor may read what its base still holds, and
    // would find it already released the other way round.
    Console.WriteLine("dropping a Leaf:");
    {
        Leaf dropped = new Leaf();
        Console.WriteLine("  made one");
    }

    Console.WriteLine("done");
    return 0;
}
