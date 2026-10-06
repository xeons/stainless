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
    static int Count();                                  // SLC0070
}

// An interface's operator is required of implementing types or given to them.
public interface IPlus
{
    static IPlus operator +(IPlus a, IPlus b) => a;      // SLC0091
}

// Supplies nothing for the requirement.
public class Empty : IZero<Empty> { }                    // SLC0013

public class Counted : IZero<Counted>
{
    public static Counted Zero => new Counted();
}

T Start<T>() where T : IZero<T> => T.Zero;

int Main()
{
    var fine = Start<Counted>();

    // Through the interface itself, which is not one of the types that supply it.
    var wrong = IZero<Counted>.Zero;                     // SLG0020
    var also = IZero<Counted>.Unit;                      // SLG0020
    return 0;
}
