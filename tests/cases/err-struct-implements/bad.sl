module Bad;

public interface Shape { double Area(); }

// A struct is a plain C value and cannot carry a reference count.
public struct Point : Shape {
    public double X;
    public double Area() { return X; }
}

int Main() { return 0; }
