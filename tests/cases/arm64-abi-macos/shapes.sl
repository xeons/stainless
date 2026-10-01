// DarwinPCS, Apple's AAPCS64, one shape per rule. Every signature this
// produces is pinned in ir.txt against what clang writes for shapes.c, because
// nothing here runs a Mac binary -- the IR is the whole of the evidence.
//
// The structs travel as they do on every ARM64 system; arm64-abi says how.
// What Darwin adds is three rules:
//
//   a narrow integer is widened to 32 bits by whoever produces it, the caller
//   an argument and the callee a result, and the other side reads the whole
//   register -- so every declaration, definition and call says signext or
//   zeroext, and one that forgot hands over garbage in the upper bits;
//   an empty struct is left out of the parameters and returned as nothing;
//   a variadic argument goes on the stack, which the back end does from the
//   triple and the IR does not show.
module ArmMacProbe;

public struct Tri   { public int A; public int B; public int C; }
public struct Trio  { public float A; public float B; public float C; }
public struct Quad  { public double A; public double B; public double C; public double D; }
public struct Big   { public long A; public long B; public sbyte C; }
public struct Twins { public byte* A; public byte* B; }
public struct Small { public sbyte A; public sbyte B; public sbyte C; }
public struct Empty { }

extern "C" int sum_tri(Tri v);
extern "C" float sum_trio(Trio v);
extern "C" double sum_quad(Quad v);
extern "C" long sum_big(Big v);
extern "C" long count_twins(Twins v);
extern "C" int sum_small(Small v);

extern "C" Small make_small();
extern "C" Tri make_tri();
extern "C" Trio make_trio();
extern "C" Big make_big();
extern "C" Twins make_twins();

// Narrow integers, each widened as C widens it. char is C's char, which is
// signed here; char16 is C's char16_t, an unsigned short.
extern "C" sbyte take_sbyte(sbyte v);
extern "C" byte take_byte(byte v);
extern "C" short take_short(short v);
extern "C" ushort take_ushort(ushort v);
extern "C" bool take_bool(bool v);
extern "C" char take_char(char v);
extern "C" char16 take_char16(char16 v);
extern "C" int take_int(int v);

// An empty struct takes no register: b arrives in w1, not w2.
extern "C" int skip_empty(int a, Empty e, int b);
extern "C" Empty make_empty();

extern "C" int report(byte* format, ...);

// The same rules on the definitions a C caller reaches.
export "C" short widen_byte(byte v) => (short)v;
export "C" bool is_negative(sbyte v) => v < 0;
export "C" int between(int a, Empty e, int b) => b - a;

// And through a pointer, where nothing but the type says how to call.
public delegate ushort Narrowed(sbyte v);

public ushort twice(sbyte v) => (ushort)(v * 2);

int main()
{
    Empty e;
    Narrowed through = twice;

    int total = sum_tri(make_tri()) + (int)sum_trio(make_trio()) + sum_small(make_small())
        + (int)sum_big(make_big()) + (int)count_twins(make_twins());

    Quad q;
    q.A = 1.0;
    q.B = 2.0;
    q.C = 3.0;
    q.D = 4.0;
    total += (int)sum_quad(q);

    total += take_sbyte(-1) + take_byte(200) + take_short(-2) + take_ushort(60000)
        + (take_bool(true) ? 1 : 0) + take_char('a') + take_char16('b') + take_int(3);

    total += skip_empty(1, e, 2) + between(1, make_empty(), 2) + widen_byte(7)
        + (is_negative(-3) ? 1 : 0) + through(-4);

    // Variadic: the promotions are C's, so char, bool and sbyte cross as int
    // and float as double. The structs cross as they would if named, and the
    // empty one not at all.
    report("%d", make_trio(), make_small(), make_big(), 'c', 1.5f, true, (sbyte)-5, e, total);
    return 0;
}
