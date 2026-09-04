// What a `: ...` list refuses, and what only a class may be.
module ErrInheritanceShape;

public interface IThing { int Go(); }

public class Plain {
    public int Value;
}

public sealed class Final {
    public int Value;
}

// A struct is a plain C value, and neither word means anything about one.
public abstract struct Value { public int X; }        // SL0495

// The two say opposite things.
public abstract sealed class Neither { }              // SL0496

// The base comes first, so that no keyword is needed to tell it from an
// interface. Written second it is not a base at all.
public class Backwards : IThing, Plain {              // SL0508
    public int Go() { return 0; }
}

// One base, and one only. With two, a reference to one of them is a different
// address from the object, and reference identity stops being pointer identity.
public class Twice : Plain, Final { }                 // SL0510 (and the sealed one)

// Nothing derives from a sealed class.
public class After : Final { }                        // SL0509

// A cycle has no size and no order to be built in.
public class Left : Right { }                         // SL0511
public class Right : Left { }

public class Itself : Itself { }                      // SL0511

// An interface has no state, so there is nothing for it to inherit.
public interface IExtends : Plain { }                 // SL0512

// The runtime compiled String's layout and its destructor, and neither is
// this compilation's to extend.
public class Longer : String { }                      // SL0513

// The dispatch words, and `protected`, mean nothing where nothing derives.
public struct Flat {
    protected int Guarded;                            // SL0519
    public virtual int Go() { return 0; }             // SL0519
}

public interface ISays {
    virtual int Twice();                              // SL0519
}

public virtual int Free() { return 0; }               // SL0519

int Main() { return 0; }
