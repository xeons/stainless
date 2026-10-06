// What `base`, `new` and `is` refuse.
module ErrBaseUse;

public interface IThing { int Go(); }

public abstract class Shape
{
    protected int sides;

    Shape(int howMany) => sides = howMany;

    public abstract double Area();
}

public class Circle : Shape
{
    Circle() => base(1);

    public override double Area() => 1.0;

    public int Sides() => sides;
}

/// Nothing to do with Circle, so no object is ever both.
public class Unrelated
{
    public int Value;
}

public class Rooted
{
    // A class deriving from nothing has no base to name.
    public int Ask() => base.Missing; // SLC0054
}

public class Elsewhere : Shape
{
    Elsewhere() => base(2);

    public override double Area() => 0.0;

    public double Twice()
    {
        // `base` is where to look a name up, not a value in its own right.
        var held = base;                              // SLC0054
        return 0.0;
    }

    public double Late()
    {
        // The base is built before this class's body runs, so a chain anywhere
        // but the head would be reading fields nothing had set.
        base(3);                                      // SLC0055
        return 0.0;
    }
}

public class Wrongly : Shape
{
    Wrongly()
    {
        sides = 1;
        base(1);                                      // SLC0055
    }

    public override double Area() => 0.0;
}

/// Shape takes an argument, and this says nothing about which one.
public class Unsaid : Shape // SLC0056
{
    public override double Area() => 0.0;
}

/// Constructors that delegate to each other and so never build anything.
public class Ring
{
    Ring(int a) => this(); // SLC0058
    Ring() => this(1);
}

public class Selfish
{
    Selfish(int a) => this(a); // SLC0058
}

public class Misplaced
{
    int _held;

    Misplaced(int a) => _held = a;

    Misplaced()
    {
        _held = 0;
        this(1);                                      // SLC0055
    }
}

/// Nothing above it declares a constructor, so there is none to chain to.
public class Bare { }

public class OnBare : Bare
{
    OnBare() => base();                               // SLC0089
}

int Main()
{
    // An abstract class exists to be derived from; there is no such object.
    Shape none = new Shape(1);                        // SLC0053

    Circle circle = new Circle();

    // No object is both, so the question has an answer already.
    bool never = circle is Unrelated;                 // SLF0020

    // A number is known exactly where it is written.
    bool number = 3 is Circle;                        // SLF0020

    // Upwards the type already says so.
    bool always = circle is Shape;                    // SLC0058, a warning

    return always ? 1 : 0;
}
