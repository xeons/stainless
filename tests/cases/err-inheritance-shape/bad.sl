// What a `: ...` list refuses, and what only a class may be.
module ErrInheritanceShape;

public interface IThing { int Go(); }

public class Plain
{
    public int Value;
}

public sealed class Final
{
    public int Value;
}

// A struct is a plain C value, and neither word means anything about one.
public abstract struct Value { public int X; }        // SLC0036

// The two say opposite things.
public abstract sealed class Neither { }              // SLC0047

// The base comes first, so that no keyword is needed to tell it from an
// interface. Written second it is not a base at all.
public class Backwards : IThing, Plain // SLC0048
{
    public int Go() => 0;
}

// One base, and one only. With two, a reference to one of them is a different
// address from the object, and reference identity stops being pointer identity.
public class Twice : Plain, Final { }                 // SLC0050 (and the sealed one)

// Nothing derives from a sealed class.
public class After : Final { }                        // SLC0049

// A cycle has no size and no order to be built in.
public class Left : Right { }                         // SLC0051
public class Right : Left { }

public class Itself : Itself { }                      // SLC0051

// An interface has no state, so there is nothing for it to inherit.
public interface IExtends : Plain { }                 // SLC0011

// The runtime compiled String's layout and its destructor, and neither is
// this compilation's to extend.
public class Longer : String { }                      // SLC0052

// The dispatch words, and `protected`, mean nothing where nothing derives.
public struct Flat
{
    protected int Guarded;                            // SLC0057
    public virtual int Go() => 0; // SLC0057
}

public interface ISays
{
    virtual int Twice();                              // SLC0057
}

public virtual int Free() => 0; // SLC0057

int Main() => 0;
