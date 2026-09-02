// SPDX-License-Identifier: 0BSD
module Shapes;

extern "C" int printf(byte* format, ...);

public struct Point {
    public double X;
    public double Y;

    public double LengthSquared() { return X * X + Y * Y; }
}

public struct Pair {
    public int A;
    public int B;
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
    printf("p          = (%g, %g)\n", p.X, p.Y);
    printf("lengthSq   = %g\n", p.LengthSquared());
    printf("Sum(p)     = %g\n", Sum(p));

    Pair q;
    q.A = 20;
    q.B = 22;
    printf("AddPair(q) = %d\n", AddPair(q));

    printf("sizeof(Point)=%llu sizeof(Pair)=%llu\n", sizeof(Point), sizeof(Pair));
    return 0;
}
