// SPDX-License-Identifier: 0BSD
module Bad;

public interface IShape { double Area(); }

// A struct is a plain C value and cannot carry a reference count.
public struct Point : IShape {
    public double X;
    public double Area() { return X; }
}

int Main() { return 0; }
