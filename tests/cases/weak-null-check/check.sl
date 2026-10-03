// A weak reference compared with null is asked whether its object is alive:
// a dead one compares equal to null, though its slot still holds where the
// object was.
module WeakNullCheck;

import Standard.Console;

public class Thing { }

int Main()
{
    weak Thing? loose;
    var other = new Thing();
    {
        var thing = new Thing();
        loose = thing;
        Console.WriteLine($"held: {loose is null} {loose == null} {loose != null} {loose == thing}");
    }
    Console.WriteLine($"gone: {loose is null} {loose == null} {loose != null} {loose is not null}");
    Console.WriteLine($"not another: {loose == other}");
    return 0;
}
