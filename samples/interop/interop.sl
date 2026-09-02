module Interop;

// Ordinary C declarations. No binding layer, no marshalling, no header.
extern "C" {
    int  printf(byte* format, ...);
    void c_drive();
    void c_report(byte* label, Point p);
}

extern "C" Point c_make_point(double x, double y);

public struct Point {
    public double X;
    public double Y;
}

public struct Pair {
    public int A;
    public int B;
}

// Callable from C under these exact names.
export "C" Point sl_scale(Point p, double factor) {
    Point result;
    result.X = p.X * factor;
    result.Y = p.Y * factor;
    return result;
}

export "C" int sl_add_pair(Pair p) {
    return p.A + p.B;
}

export "C" double sl_hypot_sq(double x, double y) {
    return x * x + y * y;
}

int Main() {
    printf("Stainless -> C:\n");
    var p = c_make_point(3.0, 4.0);
    c_report("built in C, read in Stainless", p);
    printf("  [SL] p.X + p.Y = %g\n", p.X + p.Y);

    printf("C -> Stainless:\n");
    c_drive();
    return 0;
}
