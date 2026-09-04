// SPDX-License-Identifier: 0BSD
module Bad;

import Standard.Reflection;

// A class lays its fields out behind a header the compiler owns.
public class Object {
    public int A : 3;
    public Object() { A = 0; }
}

// Wider than what it is some of.
public struct TooWide { public byte B : 9; }

// Zero is C's storage-unit closer, which is not written yet.
public struct Zero { public int Z : 0; }

// Not something that has bits to take.
public struct NotInteger { public double D : 3; }

// Packed and bit-fields mean different things to different C compilers.
[Packed]
public struct PackedBits { public int A : 3; public int B : 5; }

// Reflection describes a field by its byte offset.
[Reflect]
public struct Reflected { public int A : 3; }

public struct Flags { public int A : 3; public int B : 5; }
void Takes(ref int n) { }

int Main() {
    Flags f;
    f.A = 1;
    Takes(ref f.A);         // a bit-field has no address
    return 0;
}
