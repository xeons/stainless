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

// An opaque type and an alias over a pointer to it: C's own idiom for a handle,
// and the header says exactly that. The type is never laid out on either side,
// so what crosses is a pointer and nothing else.
public struct Slot__;
public using Slot = Slot__*;

public using Count = nuint;

export "C" Slot SlotAt(int* storage, int index) {
    return (Slot)(&storage[index]);
}

export "C" int SlotRead(Slot slot) { return *((int*)slot); }

export "C" Count Measure(byte* text) {
    Count n = (Count)0;
    while (text[n] != (byte)0) { n = n + (Count)1; }
    return n;
}

// Visible to other Stainless modules, absent from the export table.
public int Helper() { return 1; }

// Module-private.
int Secret() { return 2; }
