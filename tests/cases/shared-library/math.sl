module Library.Math;

public struct Point {
    public double X;
    public double Y;
}

public struct Pair {
    public int A;
    public int B;
}

export "C" int Add(int a, int b) { return a + b; }

export "C" Point Scale(Point p, double by) {
    Point result;
    result.X = p.X * by;
    result.Y = p.Y * by;
    return result;
}

export "C" int SumPair(Pair p) { return p.A + p.B; }

// Visible to other Stainless modules, absent from the export table.
public int Helper() { return 1; }

// Module-private.
int Secret() { return 2; }
