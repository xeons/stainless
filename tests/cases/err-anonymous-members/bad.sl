// Where a nameless member has no answer.
module ErrAnonymousMembers;

/// Two nameless members at the same depth both offering `Value`. C refuses this
/// too, and for the same reason: there is nothing to choose between them.
public struct Ambiguous
{
    public union  { public int  Value; public float AsFloat; }
    public struct { public long Value; }
}

/// A name that is not in any of them is still just missing.
public struct Plain
{
    public struct { public int Inner; }
}

int Main()
{
    Ambiguous a;
    a.Value = 1;                    // SLN0020

    Plain p;
    p.Missing = 2;                  // SLN0013
    return 0;
}
