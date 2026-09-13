/* The C side: whatever clang does for this target is the answer. */

typedef struct { unsigned char A, B, C; } Three;
typedef struct { int A, B, C; }           Twelve;
typedef struct { float X, Y; }            Twins;
typedef struct { double X, Y; }           Pair;
typedef struct { unsigned char A; }       One;

int    sum_three(Three v)   { return v.A + v.B + v.C; }
int    sum_twelve(Twelve v) { return v.A + v.B + v.C; }
double sum_twins(Twins v)   { return (double)v.X + (double)v.Y; }
double sum_pair(Pair v)     { return v.X + v.Y; }
int    sum_one(One v)       { return v.A; }

Three  make_three(unsigned char a) { Three v; v.A = a; v.B = a + 1; v.C = a + 2; return v; }
Twelve make_twelve(int a)          { Twelve v; v.A = a; v.B = a + 1; v.C = a + 2; return v; }
Twins  make_twins(float a)         { Twins v; v.X = a; v.Y = a + 1.0f; return v; }
Pair   make_pair(double a)         { Pair v; v.X = a; v.Y = a + 1.0; return v; }
One    make_one(unsigned char a)   { One v; v.A = a; return v; }

int between(int a, Three b, int c, Twelve d, int e)
{
    return a + b.A + b.B + b.C + c + d.A + d.B + d.C + e;
}
