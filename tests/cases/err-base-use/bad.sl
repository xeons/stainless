// What `base`, `new` and `is` refuse.
module ErrBaseUse;

public interface IThing { int Go(); }

public abstract class Shape {
    protected int sides;

    Shape(int howMany) { sides = howMany; }

    public abstract double Area();
}

public class Circle : Shape {
    Circle() { base(1); }

    public override double Area() { return 1.0; }

    public int Sides() { return sides; }
}

/// Nothing to do with Circle, so no object is ever both.
public class Unrelated {
    public int Value;
}

public class Rooted {
    // A class deriving from nothing has no base to name.
    public int Ask() { return base.Missing; }         // SL0515
}

public class Elsewhere : Shape {
    Elsewhere() { base(2); }

    public override double Area() { return 0.0; }

    public double Twice() {
        // `base` is where to look a name up, not a value in its own right.
        var held = base;                              // SL0515
        return 0.0;
    }

    public double Late() {
        // The base is built before this class's body runs, so a chain anywhere
        // but the head would be reading fields nothing had set.
        base(3);                                      // SL0516
        return 0.0;
    }
}

public class Wrongly : Shape {
    Wrongly() {
        sides = 1;
        base(1);                                      // SL0516
    }

    public override double Area() { return 0.0; }
}

/// Shape takes an argument, and this says nothing about which one.
public class Unsaid : Shape {                         // SL0517
    public override double Area() { return 0.0; }
}

int Main() {
    // An abstract class exists to be derived from; there is no such object.
    Shape none = new Shape(1);                        // SL0514

    Circle circle = new Circle();

    // No object is both, so the question has an answer already.
    bool never = circle is Unrelated;                 // SL0518

    // A number is known exactly where it is written.
    bool number = 3 is Circle;                        // SL0518

    // Upwards the type already says so.
    bool always = circle is Shape;                    // SL0521, a warning

    return always ? 1 : 0;
}
