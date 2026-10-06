// SPDX-License-Identifier: 0BSD
module Bad;

import Standard.Reflection;

public attribute Label { String Name; int Width; }

int Answer() => 1;

[Reflect]
public class Thing
{
    // Attribute arguments are written into the binary, so they must be constants.
    [Label(Answer())]
    public int Value;

    // SLC0092: a name the attribute does not declare.
    [Label("a", Height = 3)]
    public int Unknown;

    // SLC0093: one field, two values — by name twice, and positionally and then
    // by name.
    [Label("a", Width = 1, Width = 2)]
    public int Twice;
    [Label("a", Name = "b")]
    public int Again;

    // SLC0094: a bare value after a named one, whose field a reader would have
    // to count out.
    [Label(Name = "a", 3)]
    public int Late;

    // SLC0019: more values than there are fields.
    [Label("a", 3, "spare")]
    public int TooMany;
}

int Main() => 0;
