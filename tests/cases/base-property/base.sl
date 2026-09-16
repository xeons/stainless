// `base.P` is the property this class replaced, not the one it is writing.
//
// A method has always been non-virtual through `base` -- the spec says so, and
// `BindMemberOf` passed the fact along for a call. A property accessor is a
// method too, and did not: an override written the obvious way
//
//     public override bool Flag { get => base.Flag; }
//
// dispatched back through the vtable to itself. Not a crash and not a
// diagnostic: the program hangs, with nothing at all to say about why.
//
// Both halves are checked, because the getter and the setter travel by
// different routes -- one is a `BoundCall`, the other a `BoundPropertyAssignment`.
module BaseProperty;

import Standard.Console;
import Standard.Text;

public class Base
{
    protected int held;
    protected int writes;

    public Base()
    {
        held = 0;
        writes = 0;
    }

    public virtual int Value
    {
        get => held;
        set
        {
            held = value;
            writes = writes + 1;
        }
    }

    public virtual String Name => "base";

    public int Writes => writes;
}

/// Reads and writes through `base`, and adds something of its own around both.
public class Derived : Base
{
    public int Reads { get; private set; }

    public Derived()
    {
        base();
        Reads = 0;
    }

    public override int Value
    {
        get
        {
            Reads = Reads + 1;
            return base.Value;
        }
        set => base.Value = value * 2;
    }

    /// An expression-bodied override, which is the shape that hangs most
    /// readily because it looks like it could not possibly recurse.
    public override String Name => "derived over " + base.Name;
}

/// One more level, to check that `base` means the immediate base rather than
/// the root of the chain.
public class Further : Derived
{
    public Further() => base();

    public override int Value
    {
        get => base.Value + 1;
        set => base.Value = value + 10;
    }
}

int Main()
{
    var d = new Derived();
    d.Value = 21;
    Console.WriteLine("derived stored: " + Standard.Text.FromInteger((long)d.Value));
    Console.WriteLine("derived reads:  " + Standard.Text.FromInteger((long)d.Reads));
    Console.WriteLine("derived writes: " + Standard.Text.FromInteger((long)d.Writes));
    Console.WriteLine("derived name:   " + d.Name);

    var f = new Further();
    f.Value = 1;
    Console.WriteLine("further stored: " + Standard.Text.FromInteger((long)f.Value));

    // And through a base reference, where the override is what must run.
    Base seen = d;
    Console.WriteLine("through a base: " + seen.Name);
    return 0;
}
