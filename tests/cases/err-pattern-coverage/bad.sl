// SPDX-License-Identifier: 0BSD
//
// A switch expression that does not cover every value, and an arm nothing
// reaches because the ones before it already match all it does.
module Bad;

public enum Color { Red, Green, Blue }

[Flags]
public enum Access { Read = 1, Write = 2 }

public variant Shape
{
    Circle(double Radius);
    Rect(double Width, double Height);
    Empty;
}

// SL0620: a member of the enum is left out.
String Paint(Color color) => color switch
{
    Color.Red => "red",
    Color.Green => "green",
};

// SL0620: a [Flags] enum's members are not all its values.
String Allowed(Access access) => access switch
{
    Access.Read => "read",
    Access.Write => "write",
};

// SL0620: false is left out.
String Yes(bool flag) => flag switch
{
    true => "yes",
};

// SL0620: only the big circles are covered.
String Size(Shape shape) => shape switch
{
    Circle(> 1.0) => "big",
    Rect => "rect",
    Empty => "empty",
};

// SL0620: inside a tuple, (false, false) is left out.
String Pair(bool a, bool b) => (a, b) switch
{
    (true, _) => "first",
    (_, true) => "second",
};

// SL0621: every case is already covered.
String Covered(Shape shape) => shape switch
{
    Circle => "circle",
    Rect => "rect",
    Empty => "empty",
    _ => "other",
};

// SL0621: (true, true) is part of (true, _).
String Subsumed((bool, bool) pair) => pair switch
{
    (true, _) => "first",
    (true, true) => "both",
    _ => "neither",
};

// SL0436: a statement over a variant that leaves part of a case out.
String Statement(Shape shape)
{
    switch (shape)
    {
        case Circle(> 1.0): return "big";
        case Rect: return "rect";
        case Empty: return "empty";
    }
    return "small";
}

public int Main() => 0;
