// `zeroable`, and a `where` on a member of a generic type.
//
// A `T` whose zero value is a value of it may be made with `default(T)` and
// `new T[n]`. A member that needs that says so in its own clause, and exists
// only in the instantiations whose arguments meet it: `Box<String>` has no
// `Reset`, and is still a type.
module ConstraintZeroable;

import Standard.Console;

public struct Point
{
    public int X;
    public int Y;
}

public struct Box<T>
{
    public T Value;

    public Box(T value)
    {
        Value = value;
    }

    public void Reset() where T : zeroable
    {
        Value = default(T);
    }

    public T Get() => Value;
}

T ZeroOf<T>() where T : zeroable => default(T);

nuint CountOf<T>(nuint count) where T : unmanaged, zeroable => new T[count].Length;

int Main()
{
    var number = new Box<int>(5);
    number.Reset();
    Console.WriteLine($"{number.Get()}");

    var text = new Box<String>("kept");
    Console.WriteLine(text.Get());

    Point origin = ZeroOf<Point>();
    Console.WriteLine($"{ZeroOf<int>()} {ZeroOf<String?>() == null} {origin.X},{origin.Y}");
    Console.WriteLine($"{CountOf<double>(3u)}");
    return 0;
}
