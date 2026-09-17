// SPDX-License-Identifier: 0BSD
//
// Where an attribute may not be written, and how its arguments may not be
// named. Both are the parser's answers, which is why they are a case of their
// own: a file with a parse error never reaches the binder, so these could not
// share a case with the rules the binder holds.
module Bad;

public attribute Label { String Name; }

// SL0727: ':' names a parameter at a call; an attribute's field is set with
// '=', because an attribute is a value rather than a call.
[Label(Name: "colon")]
public class Named { }

// SL0728: a declaration nothing reads an attribute back from. Dropping one
// silently is the worse answer — '[Embed]' decides what a static holds, and a
// declaration that ignored it would compile to one that does not have it.
[Label("alias")]
using Bytes = byte[];

[Label("delegate")]
public delegate int Answer();

[Label("const")]
const int Size = 1;

[Label("extern")]
extern "C" int errno;

[Label("function")]
int Free() => 0;

public class Holder
{
    [Label("constructor")]
    Holder() { }

    [Label("destructor")]
    ~Holder() { }

    [Label("method")]
    public int Method() => 0;

    [Label("operator")]
    public static Holder operator +(Holder left, Holder right) => left;

    [Label("initializer")]
    static Holder() { }
}

int Main() => 0;
