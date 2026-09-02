// SPDX-License-Identifier: 0BSD
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

// An enum crosses as its underlying integer, and the header restates the
// constants so C can name them.
public enum Unit : int { Metres, Feet }

export "C" double Convert(double value, Unit unit) {
    if (unit == Unit.Feet) { return value * 3.28084; }
    return value;
}

// A delegate crosses as a plain C function pointer, so C can pass one in.
public delegate int Adjust(int value);

export "C" int ApplyTwice(Adjust f, int value) { return f(f(value)); }

// Visible to other Stainless modules, absent from the export table.
public int Helper() { return 1; }

// Module-private.
int Secret() { return 2; }
