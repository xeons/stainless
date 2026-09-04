// SPDX-License-Identifier: 0BSD
//
// The same six declarations under both C ABIs. They do not agree, and that is
// the point: 'Mixed' and 'Straddle' come out at different sizes, because
// Microsoft opens a new storage unit when the declared type's size changes and
// Itanium packs straight across. Every number here was read off clang built for
// the matching target.
module Bits;

import Standard.Console;

public struct Flags    { public uint Kind : 3; public uint Level : 5; public uint Rest : 24; }
public struct Mixed    { public int A : 1; public byte B : 1; }
public struct Signed   { public int S : 3; public int T : 5; }
public struct Split    { public int A : 30; public int B : 4; }
public struct Straddle { public int A : 3; public short B : 4; }
public struct WithPlain { public int A : 3; public double D; public int B : 5; }

int Main() {
    Console.WriteLine(
        Text.FromInteger((int)sizeof(Flags)) + " " +
        Text.FromInteger((int)sizeof(Mixed)) + " " +
        Text.FromInteger((int)sizeof(Signed)) + " " +
        Text.FromInteger((int)sizeof(Split)) + " " +
        Text.FromInteger((int)sizeof(Straddle)) + " " +
        Text.FromInteger((int)sizeof(WithPlain)));

    // Reading and writing has to work whichever way they were laid out.
    Flags f;
    f.Kind = 5;
    f.Level = 17;
    f.Rest = 1000000;
    f.Level = f.Level - (uint)1;
    Console.WriteLine(Text.FromInteger((int)f.Kind) + " " +
                      Text.FromInteger((int)f.Level) + " " +
                      Text.FromInteger((int)f.Rest));

    Signed s;
    s.S = 7;
    s.T = -3;
    Console.WriteLine(Text.FromInteger(s.S) + " " + Text.FromInteger(s.T));
    return 0;
}
