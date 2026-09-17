// Bit-fields of a `long` or a `ulong`, and an enum over one, on 32-bit x86.
//
// i386 System V aligns a `long long` to four inside a struct but keeps its
// eight-byte storage unit, and clang places a bit-field in a unit of the
// type's size that starts on a boundary of the type's alignment: the `X : 33`
// after an `int` goes at bit 32, not 64. MSVC keeps eight for both. Each struct
// is filled on both sides and compared byte for byte, and the bytes C wrote are
// read back through Stainless's own field access.
//
// Several of these are narrower than their unit on Linux -- `struct { char c;
// long long x : 3; }` is four bytes holding an eight-byte unit -- so reading or
// writing the whole unit would run off the end of the value. The stores below
// sit in a struct with a sentinel after it, which would show that.
module X86WideBitfields;

import Standard.Console;

struct A { public long X : 3; public int Y : 5; }
struct B { public sbyte C; public long X : 40; }
struct C { public int I; public long X : 33; public sbyte D; }
struct D { public long X : 30; public long Y : 30; public int Z; }
struct E { public byte C; public ulong X : 5; }
struct F { public int P : 20; public long Q : 20; }
struct G { public sbyte C; public long X : 3; }
enum Wide : long { Big = 1 }
struct H { public sbyte C; public Wide W; }

struct Guarded { public G Value; public int Sentinel; }

extern "C" int c_size(int which);
extern "C" void c_fill(int which, byte* into);

void Compare(String name, int which, byte* ours, nuint size)
{
    var theirs = new byte[32];
    c_fill(which, &theirs[0u]);

    String agree = "bytes agree";
    for (nuint i = 0u; i < size; i++)
    {
        if (ours[i] != theirs[i])
            agree = $"byte {i} is {ours[i]} but C wrote {theirs[i]}";
    }

    String sized = (long)size == (long)c_size(which) ? "" : $" but C says {c_size(which)}";
    Console.WriteLine($"{name} {size}{sized}, {agree}");
}

byte* Clear(byte* at, nuint size)
{
    for (nuint i = 0u; i < size; i++)
        at[i] = 0u;
    return at;
}

int Main()
{
    A a; Clear((byte*)&a, sizeof(A)); a.X = -1; a.Y = 9;
    Compare("A", 0, (byte*)&a, sizeof(A));

    B b; Clear((byte*)&b, sizeof(B)); b.C = 1; b.X = 0x123456789;
    Compare("B", 1, (byte*)&b, sizeof(B));

    C c; Clear((byte*)&c, sizeof(C)); c.I = 2; c.X = -0xABCDEF; c.D = 3;
    Compare("C", 2, (byte*)&c, sizeof(C));

    D d; Clear((byte*)&d, sizeof(D)); d.X = 0x1AAAAAAA; d.Y = 0x15555555; d.Z = 4;
    Compare("D", 3, (byte*)&d, sizeof(D));

    E e; Clear((byte*)&e, sizeof(E)); e.C = 5u; e.X = 21u;
    Compare("E", 4, (byte*)&e, sizeof(E));

    F f; Clear((byte*)&f, sizeof(F)); f.P = 0x12345; f.Q = 0x6789A;
    Compare("F", 5, (byte*)&f, sizeof(F));

    Guarded g; Clear((byte*)&g, sizeof(Guarded)); g.Sentinel = 77; g.Value.C = 6; g.Value.X = 3;
    Compare("G", 6, (byte*)&g.Value, sizeof(G));

    H h; Clear((byte*)&h, sizeof(H)); h.C = 7; h.W = Wide.Big;
    Compare("H", 7, (byte*)&h, sizeof(H));

    // Stores that left the sentinel alone, and reads of what C wrote.
    g.Value.X = -2;
    Console.WriteLine($"sentinel {g.Sentinel}, G.X {g.Value.X}");

    C fromC;
    c_fill(2, (byte*)&fromC);
    D fromD;
    c_fill(3, (byte*)&fromD);
    E fromE;
    c_fill(4, (byte*)&fromE);
    Console.WriteLine($"read C {fromC.I} {fromC.X} {fromC.D}");
    Console.WriteLine($"read D {fromD.X} {fromD.Y} {fromD.Z}");
    Console.WriteLine($"read E {fromE.C} {fromE.X}");
    return 0;
}
