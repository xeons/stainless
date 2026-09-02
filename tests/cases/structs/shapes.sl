// SPDX-License-Identifier: 0BSD
module Shapes;

extern "C" int printf(byte* format, ...);

public struct Point {
    public double X;
    public double Y;

    public double Length2() { return X * X + Y * Y; }
}

public struct Pair {
    public int A;
    public int B;
}

public struct Mixed {
    public byte Tag;
    public double Value;
    public int Count;
}

double Sum(Point p) { return p.X + p.Y; }
int AddPair(Pair p) { return p.A + p.B; }

Point Make(double x, double y) {
    Point p;
    p.X = x;
    p.Y = y;
    return p;
}

int Main() {
    var p = Make(3.0, 4.0);
    printf("%g %g\n", p.X, p.Y);
    printf("%g\n", p.Length2());
    printf("%g\n", Sum(p));

    Pair q;
    q.A = 20;
    q.B = 22;
    printf("%d\n", AddPair(q));

    // A struct assignment copies the value, it does not alias.
    Pair r = q;
    r.A = 0;
    printf("%d %d\n", q.A, r.A);

    printf("%llu %llu %llu\n", sizeof(Point), sizeof(Pair), sizeof(Mixed));
    return 0;
}
