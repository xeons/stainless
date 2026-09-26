// SPDX-License-Identifier: 0BSD
//
// A value that is not a tuple is taken apart by its `Deconstruct`: a method,
// or a free function taking the value first -- uniform call syntax is this
// language's extension method -- with one `out` parameter per name. Which one
// is chosen by how many names there are. A record has one generated, with a
// parameter for each of its own.
module DeconstructMethods;

import Standard.Console;

class Loud
{
    public String Tag;
    public Loud(String tag) => Tag = tag;
    ~Loud() { Console.WriteLine($"  dropped {Tag}"); }
}

class Pair
{
    public Loud Left;
    public Loud Right;

    public Pair(Loud left, Loud right)
    {
        Left = left;
        Right = right;
    }

    // Written with a deconstruction of its own, which writes both outs.
    public void Deconstruct(out Loud left, out Loud right) => (left, right) = (Left, Right);

    public void Deconstruct(out Loud left, out Loud right, out int count)
    {
        (left, right) = (Left, Right);
        count = 2;
    }
}

struct Point
{
    public int X;
    public int Y;

    public Point(int x, int y)
    {
        X = x;
        Y = y;
    }

    public void Deconstruct(out int x, out int y)
    {
        x = X;
        y = Y;
    }
}

struct Range
{
    public int Low;
    public int High;
}

void Deconstruct(Range range, out int low, out int high)
{
    low = range.Low;
    high = range.High;
}

class Holder<T>
{
    public T First;
    public T Second;

    public Holder(T first, T second)
    {
        First = first;
        Second = second;
    }

    public void Deconstruct(out T first, out T second)
    {
        first = First;
        second = Second;
    }
}

record Named(String Label, int Weight);

// One written in the body takes the generated one's place.
record Celsius(double Degrees)
{
    public void Deconstruct(out double fahrenheit) => fahrenheit = Degrees * 9.0 / 5.0 + 32.0;
}

record Spot(int X, int Y);

record Segment(Spot From, Spot To);

Point MakePoint(int x, int y)
{
    Console.WriteLine("made a point");
    return new Point(x, y);
}

public int Main()
{
    var (x, y) = new Point(3, 4);
    Console.WriteLine($"a {x} {y}");

    // A temporary is made once and taken apart.
    (x, y) = MakePoint(5, 6);
    Console.WriteLine($"b {x} {y}");

    Range range;
    range.Low = 1;
    range.High = 9;
    var (low, high) = range;
    Console.WriteLine($"c {low} {high}");

    var (first, second) = new Holder<String>("one", "two");
    Console.WriteLine($"d {first} {second}");

    var (label, weight) = new Named("heavy", 90);
    Console.WriteLine($"e {label} {weight}");

    // Nested: a record whose parts are themselves taken apart.
    var (count, ((fromX, fromY), (toX, _))) = (2, new Segment(new Spot(1, 2), new Spot(3, 4)));
    Console.WriteLine($"f {count} {fromX} {fromY} {toX}");

    var named = new Named("light", 1);
    (label, weight) = named;
    Console.WriteLine($"g {label} {weight} {named == new Named("light", 1)}");

    new Celsius(100.0).Deconstruct(out double fahrenheit);
    Console.WriteLine($"h {fahrenheit}");

    Console.WriteLine("references:");
    {
        var (left, right) = new Pair(new Loud("l"), new Loud("r"));
        Console.WriteLine($"  {left.Tag} {right.Tag}");

        var pair = new Pair(new Loud("kept l"), new Loud("kept r"));
        var (l2, r2, n) = pair;
        Console.WriteLine($"  {l2.Tag} {r2.Tag} {n}");

        (left, _) = pair;
        Console.WriteLine($"  {left.Tag}");
    }

    Console.WriteLine("done");
    return 0;
}
