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
    int IShape.Sides { get; }                            // SL0793

    // Square does not implement IOther.
    void IOther.Run() { }                                // SL0794

    // IShape has no such member.
    double IShape.Perimeter() => 4.0;                    // SL0794

    // Reached only through the interface, so no word about who may call it.
    public double IShape.Area() => 2.0;                  // SL0795
}

// Two defaults, neither more specific than the other.
public interface IA { String Which() => "A"; }
public interface IB : IA { String IA.Which() => "B"; }
public interface IC : IA { String IA.Which() => "C"; }

public class Undecided : IB, IC { }                      // SL0796

int Main() => 0;
