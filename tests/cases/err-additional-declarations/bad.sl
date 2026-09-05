// What a second declaration of a type may not do.
//
// A type may be declared more than once inside its own module, the way a module
// may span files. The first declaration settles what the type *is*; a later one
// may add behaviour and nothing else. That is narrower than C#'s `partial`, and
// deliberately: the reason the rule exists is `String`, whose layout belongs to
// the runtime, and a rule that let a later declaration change a layout would be
// a rule that let one change String's.
module Bad;

public class Shape {
    public int Sides;
}

// Fine: another declaration, adding a method.
public class Shape {
    public int Corners() { return Sides; }
}

// Not fine: the layout belongs to the declaration that has the fields.
public class Shape {
    public int Extra;                           // SL0552
}

// Not fine: pass 5 builds the dispatch tables from the first declaration, so a
// base list arriving later would arrive after they were built.
public interface IDrawable { void Draw(); }

public class Shape : IDrawable {                // SL0551
    public void Draw() { }
}

// Not fine: every declaration has to agree about what it is.
public struct Shape {                           // SL0550
    public int Wrong() { return 0; }
}

int Main() { return 0; }
