// SPDX-License-Identifier: 0BSD
module Bad;

public interface IZero<TSelf>
{
    static abstract TSelf Zero { get; }
    static virtual String Unit => "?";
}

public interface IShape
{
    double Area();
}

// A static member with no body is a requirement, and says so.
public interface IVague
{
    static int Count();                                  // SL0574
}

// An interface's operator is required of implementing types or given to them.
public interface IPlus
{
    static IPlus operator +(IPlus a, IPlus b) => a;      // SL0645
}

// Supplies nothing for the requirement.
public class Empty : IZero<Empty> { }                    // SL0305

public class Counted : IZero<Counted>
{
    public static Counted Zero => new Counted();
}

T Start<T>() where T : IZero<T> => T.Zero;

int Main()
{
    var fine = Start<Counted>();

    // Through the interface itself, which is not one of the types that supply it.
    var wrong = IZero<Counted>.Zero;                     // SL0797
    var also = IZero<Counted>.Unit;                      // SL0797
    return 0;
}
