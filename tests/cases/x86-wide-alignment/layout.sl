// `long`, `ulong` and `double` inside a struct on 32-bit x86.
//
// The two systems disagree here and neither is wrong: MSVC aligns all three to
// eight, and i386 System V to four, so `struct { int a; long long b; }` is 16
// bytes on Windows and 12 on Linux. The binder took a primitive's size as its
// alignment and so laid out the Windows struct on both, which a Linux consumer
// read four bytes off. Each number is compared against what clang says for the
// same declaration, and the values are read back through C as well.
module X86WideAlignment;

import Standard.Console;

struct IntLong
{
    public int A;
    public long B;
}

struct ByteDouble
{
    public byte A;
    public double B;
    public int C;
}

struct LongByte
{
    public ulong A;
    public byte B;
}

struct Nested
{
    public byte A;
    public IntLong I;
}

extern "C" int c_layout(int which);
extern "C" long c_read_nested(Nested* n);
extern "C" double c_read_by_value(ByteDouble v);

void Check(String what, nuint ours, int which)
{
    int theirs = c_layout(which);
    Console.WriteLine($"{what} {ours}" + ((long)ours == (long)theirs ? "" : $" but C says {theirs}"));
}

int Main()
{
    Check("IntLong size    ", sizeof(IntLong), 0);
    Check("IntLong.B       ", offsetof(IntLong, B), 1);
    Check("IntLong align   ", alignof(IntLong), 2);
    Check("ByteDouble size ", sizeof(ByteDouble), 3);
    Check("ByteDouble.B    ", offsetof(ByteDouble, B), 4);
    Check("ByteDouble.C    ", offsetof(ByteDouble, C), 5);
    Check("LongByte size   ", sizeof(LongByte), 6);
    Check("Nested size     ", sizeof(Nested), 7);
    Check("Nested.I        ", offsetof(Nested, I), 8);

    Nested n;
    n.A = 1u;
    n.I.A = 20;
    n.I.B = 3000000000;
    Console.WriteLine($"read nested      {c_read_nested(&n)}");

    ByteDouble v;
    v.A = 2u;
    v.B = 0.5;
    v.C = 40;
    Console.WriteLine($"read by value    {c_read_by_value(v)}");
    return 0;
}
