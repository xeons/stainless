// The shapes where a classifier is most likely to disagree with C: sizes that
// are not a register, structs of floats, and a struct returned by value.
module AbiProbe2;

extern "C" int printf(byte* format, ...);

public struct Three  { public byte A; public byte B; public byte C; }
public struct Twelve { public int A; public int B; public int C; }
public struct Twins  { public float X; public float Y; }
public struct Pair   { public double X; public double Y; }
public struct One    { public byte A; }

extern "C" int    sum_three(Three v);
extern "C" int    sum_twelve(Twelve v);
extern "C" double sum_twins(Twins v);
extern "C" double sum_pair(Pair v);
extern "C" int    sum_one(One v);

extern "C" Three  make_three(byte a);
extern "C" Twelve make_twelve(int a);
extern "C" Twins  make_twins(float a);
extern "C" Pair   make_pair(double a);
extern "C" One    make_one(byte a);

extern "C" int between(int a, Three b, int c, Twelve d, int e);

int Main()
{
    Three three;  three.A = 1; three.B = 2; three.C = 3;
    Twelve twelve; twelve.A = 10; twelve.B = 20; twelve.C = 30;
    Twins twins;  twins.X = 1.5f; twins.Y = 2.5f;
    Pair pair;    pair.X = 1.25; pair.Y = 2.75;
    One one;      one.A = 9;

    printf("sum_three  = %d    (want 6)\n", sum_three(three));
    printf("sum_twelve = %d   (want 60)\n", sum_twelve(twelve));
    printf("sum_twins  = %.2f (want 4.00)\n", sum_twins(twins));
    printf("sum_pair   = %.2f (want 4.00)\n", sum_pair(pair));
    printf("sum_one    = %d    (want 9)\n", sum_one(one));

    var t = make_three(4);
    printf("make_three = %d %d %d (want 4 5 6)\n", (int)t.A, (int)t.B, (int)t.C);

    var w = make_twelve(7);
    printf("make_twelve= %d %d %d (want 7 8 9)\n", w.A, w.B, w.C);

    var tw = make_twins(1.5f);
    printf("make_twins = %.2f %.2f (want 1.50 2.50)\n", (double)tw.X, (double)tw.Y);

    var p = make_pair(1.25);
    printf("make_pair  = %.2f %.2f (want 1.25 2.25)\n", p.X, p.Y);

    var o = make_one(5);
    printf("make_one   = %d    (want 5)\n", (int)o.A);

    printf("between    = %d   (want 71)\n", between(1, three, 2, twelve, 2));
    return 0;
}
