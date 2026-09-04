// SPDX-License-Identifier: 0BSD
module Interop;

extern "C" {
    int  printf(byte* format, ...);
    void c_drive();
}

// Declared before the struct it mentions, on purpose.
extern "C" Point c_make_point(double x, double y);

public struct Point {
    public double X;
    public double Y;
}

public struct Pair {
    public int A;
    public int B;
}

export "C" Point sl_scale(Point p, double factor) {
    Point result;
    result.X = p.X * factor;
    result.Y = p.Y * factor;
    return result;
}

export "C" int sl_add_pair(Pair p) {
    return p.A + p.B;
}

int Main() {
    var p = c_make_point(3.0, 4.0);
    printf("sl:point=%g,%g\n", p.X, p.Y);
    c_drive();
    return 0;
}
