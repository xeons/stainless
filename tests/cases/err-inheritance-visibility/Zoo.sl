module Zoo;

public class Animal {
    protected int legs;

    Animal() { legs = 4; }

    protected int Legs() { return legs; }

    /// Private to this module. Deriving does not change that.
    int Tag() { return 7; }

    public virtual String Speak() { return "..."; }
}

/// A sealed override in a class that is not itself sealed: the method is closed,
/// the class is not.
public class Quiet : Animal {
    Quiet() { base(); }

    public sealed override String Speak() { return "shh"; }
}
