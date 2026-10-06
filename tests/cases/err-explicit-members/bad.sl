// SPDX-License-Identifier: 0BSD
module Bad;

public interface IShape
{
    double Area();
    int Sides { get; }
}

public interface IOther
{
    void Run();
}

public class Square : IShape
{
    public double Area() => 1.0;
    public int Sides => 4;

    // An automatic accessor would need storage named after the property.
    int IShape.Sides { get; }                            // SLC0110

    // Square does not implement IOther.
    void IOther.Run() { }                                // SLC0111

    // IShape has no such member.
    double IShape.Perimeter() => 4.0;                    // SLC0111

    // Reached only through the interface, so no word about who may call it.
    public double IShape.Area() => 2.0;                  // SLC0112
}

// Two defaults, neither more specific than the other.
public interface IA { String Which() => "A"; }
public interface IB : IA { String IA.Which() => "B"; }
public interface IC : IA { String IA.Which() => "C"; }

public class Undecided : IB, IC { }                      // SLC0113

int Main() => 0;
