// SPDX-License-Identifier: 0BSD
//
// A tuple written out converts to another tuple type element by element, as
// C# converts one. So an element that takes its type from where it is going
// -- `null`, `default`, `Ok(x)`, `new(...)` -- may be written in one, provided
// the tuple is going somewhere that says what that is.
module TupleLiterals;

import Standard.Console;

enum Oops { Bad }

struct Point
{
    public int X;
    public int Y;

    public Point(int x, int y)
    {
        X = x;
        Y = y;
    }
}

(String?, int) Pick(bool some) => some ? ("some", 1) : (null, 0);

String Describe((Result<int, Oops>, String) pair)
{
    switch (pair.Item1)
    {
        case Ok ok: return $"{ok.Value} {pair.Item2}";
        default: return $"failed {pair.Item2}";
    }
}

public int Main()
{
    (String?, int) nothing = (null, 1);
    Console.WriteLine($"a {nothing.Item1 ?? "none"} {nothing.Item2}");

    (long, double) widened = (1, 2);
    Console.WriteLine($"b {widened.Item1} {widened.Item2}");

    (Point, int) made = (new(3, 4), default);
    Console.WriteLine($"c {made.Item1.X} {made.Item1.Y} {made.Item2}");

    var first = Pick(true);
    var second = Pick(false);
    Console.WriteLine($"d {first.Item1 ?? "none"} {second.Item1 ?? "none"}");

    Console.WriteLine($"e {Describe((Ok(5), "five"))} {Describe((Fail(Oops.Bad), "none"))}");

    // Nested, and through a cast.
    var cast = ((String?, (int, String?)))("outer", (1, null));
    Console.WriteLine($"f {cast.Item1 ?? "-"} {cast.Item2.Item1} {cast.Item2.Item2 ?? "-"}");
    return 0;
}
