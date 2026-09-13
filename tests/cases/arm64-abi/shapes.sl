// AAPCS64, one shape per rule. Every signature this produces is pinned in
// ir.txt against what clang writes for the same C, because nothing here can
// run an ARM64 binary -- the IR is the whole of the evidence.
//
// The four rules, in the order the classifier asks them:
//
//   a homogeneous aggregate travels in one SIMD register per member, however
//   big it is -- Quad is thirty-two bytes and crosses in v0-v3;
//   everything else of sixteen bytes or less travels in one or two general
//   registers, sized by the register going out and by the value coming back;
//   a struct of nothing but pointers keeps them as pointers;
//   everything larger is a pointer to a copy the caller made, and that is not
//   'byval', which LLVM would put on the stack instead.
module ArmProbe;

extern "C" int printf(byte* format, ...);

public struct Tri   { public int A; public int B; public int C; }
public struct Trio  { public float A; public float B; public float C; }
public struct Quad  { public double A; public double B; public double C; public double D; }
public struct Big   { public long A; public long B; public sbyte C; }
public struct Twins { public byte* A; public byte* B; }
public struct Small { public sbyte A; public sbyte B; public sbyte C; }

// Twelve bytes: two general registers going out, and the twelve bytes have to
// be copied into sixteen before they are read.
public int sum_tri(Tri v) { return v.A + v.B + v.C; }

// Homogeneous, so registers whatever the size.
public float sum_trio(Trio v) { return v.A + v.B + v.C; }
public double sum_quad(Quad v) { return v.A + v.B + v.C + v.D; }

// Twenty-four bytes and not homogeneous: a pointer to the caller's copy.
public long sum_big(Big v) { return v.A + v.B + (long)v.C; }

// Pointers stay pointers on the way in.
public long count_twins(Twins v) { return (v.A == null ? 0L : 1L) + (v.B == null ? 0L : 1L); }

// Three bytes: an i64 going out and an i24 coming back, which is the one place
// the two directions disagree.
public Small make_small() { Small s; s.A = 1; s.B = 2; s.C = 3; return s; }
public int sum_small(Small v) { return (int)v.A + (int)v.B + (int)v.C; }

public Tri make_tri() { Tri t; t.A = 1; t.B = 2; t.C = 3; return t; }
public Trio make_trio() { Trio t; t.A = 1.0f; t.B = 2.0f; t.C = 3.0f; return t; }
public Quad make_quad() { Quad q; q.A = 1.0; q.B = 2.0; q.C = 3.0; q.D = 4.0; return q; }
public Big make_big() { Big b; b.A = 1; b.B = 2; b.C = 3; return b; }
public Twins make_twins() { Twins t; t.A = null; t.B = null; return t; }

int main()
{
    printf("%d %.1f %.1f %lld %lld %d\n",
           sum_tri(make_tri()),
           (double)sum_trio(make_trio()),
           sum_quad(make_quad()),
           sum_big(make_big()),
           count_twins(make_twins()),
           sum_small(make_small()));
    return 0;
}
