// SPDX-License-Identifier: 0BSD
module Bad;

// Not a power of two.
[Align(3)]
public struct Odd { public int A; }

// More than a page.
[Align(8192)]
public struct TooWide { public double X; }

// Neither applies to a class.
[Packed]
public class Object { public int A; public Object() { A = 0; } }

[Align(8)]
public class Aligned { public int A; public Aligned() { A = 0; } }

// Nor to a variant, whose payload area is not a field the source arranged.
[Packed]
public variant Choice { One(int N); Two; }

// [Pack] takes a power of two, says nothing beside [Packed], and lays out a
// struct or a union alone.
[Pack(3)]
public struct OddPack { public int A; }

[Packed]
[Pack(2)]
public struct TwicePacked { public int A; }

[Pack(2)]
public class PackedClass { public int A; public PackedClass() { A = 0; } }

// [Packed] on one field: a struct's or a union's, and not a bit-field.
public class PackedFieldOwner
{
    [Packed] public long Time;
    public PackedFieldOwner() { Time = 0; }
}

public struct PackedBits
{
    [Packed] public uint Flags : 3;
}

int Main() => 0;
