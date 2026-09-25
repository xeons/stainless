// What a second declaration of a type may not do.
//
// A class may take fields from any of its declarations and its base list from
// any one. A struct takes both from its first, because its layout is C's.
module Bad;

public interface IDrawable { void Draw(); }
public interface ISized { int Size(); }

public class Shape : IDrawable
{
    public int Sides;
    public void Draw() { }
}

// Fine: another declaration, adding a method and a field.
public class Shape
{
    public int Corners;
    public int Count() => Sides + Corners;
}

// Not fine: the first declaration already said what it derives from.
public class Shape : ISized // SL0551
{
    public int Size() => Sides;
}

public struct Point
{
    public int X;
}

// Not fine: a struct's layout belongs to the declaration that has the fields.
public struct Point
{
    public int Y;                               // SL0552
}

// Not fine: nor does a struct take a base list from a later declaration.
public struct Point : IDrawable // SL0551
{
    public void Draw() { }
}

// Not fine: every declaration has to agree about what it is.
public struct Shape // SL0550
{
    public int Wrong() => 0;
}

int Main() => 0;
