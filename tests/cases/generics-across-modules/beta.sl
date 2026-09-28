// SPDX-License-Identifier: 0BSD
//
// Two modules each declare a `Point`, of different layouts, and each makes the
// same generic types of its own: a list, a tuple, a slice, a lambda's type, a
// generic closure and a generic function, and a list of pointers. Each is its
// own instantiation, with its own symbols, however alike the two print.
module Beta;

import Standard.Collections;
import Standard.Console;
import Alpha;

public struct Point
{
    public long X;
    public String Name;
}

public int Main()
{
    Point p;
    p.X = 40;
    p.Name = "beta";

    var list = new List<Point>();
    list.Add(p);

    (Point, int) pair = (p, 2);
    Span<Point> slice = [p];
    var measure = (Point q) => q.X + 2;
    Func<Point, String> fn = q => q.Name;
    List<Point*> addresses = new List<Point*>();
    addresses.Add(&p);

    Console.WriteLine($"alpha {SumAlpha()}");
    Console.WriteLine($"list  {list[0].X} {list[0].Name}");
    Console.WriteLine($"tuple {pair.Item1.Name} {pair.Item2}");
    Console.WriteLine($"slice {slice[0].Name}");
    Console.WriteLine($"fn    {measure(p)} {fn(p)} {Same(p).Name}");
    Console.WriteLine($"ptr   {addresses[0]->Name}");

    // The other module's, by its qualified name, beside this one's.
    var theirs = new List<Alpha.Point>();
    Alpha.Point a;
    a.X = 5;
    a.Y = 6;
    theirs.Add(a);
    Console.WriteLine($"both  {theirs[0].X + theirs[0].Y} {list.Count}");
    return 0;
}
