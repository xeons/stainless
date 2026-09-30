// A lambda that writes a variable it captured by value (spec section 2.15).
//
// The capture is a field of the closure, so the write lands there and the
// variable around the lambda keeps its value. A copy the lambda never reads
// again makes the write invisible, and SL0829 says so. A copy it does read
// again is state the closure keeps for itself, and is not reported.
module CapturedWrite;

import Standard.Console;

public closure void Act();
public closure int Next();

public class Box
{
    public int Value;
}

public class Clicks
{
    int _count;

    public int Count => _count;

    // A bare member is copied, so this changes the copy and not the field.
    public Act Lost() => () => _count++;                // SL0829

    // Through `this` the object is captured, and the field is written.
    public Act Kept() => () => this._count++;
}

public struct Point
{
    public int X;

    // A struct's `this` is the value, so the lambda writes a copy of it.
    public Act Move() => () => this.X = 5;              // SL0829
}

bool ParseDigit(String text, out int value)
{
    value = 7;
    return true;
}

public void Main()
{
    int count = 0;
    Act add = () => count++;                            // SL0829
    add();
    add();
    Console.WriteLine($"count {count}");

    int total = 0;
    Act sum = () => { total += 2; };                    // SL0829
    sum();
    Console.WriteLine($"total {total}");

    int parsed = 0;
    Act parse = () => { ParseDigit("7", out parsed); }; // SL0829
    parse();
    Console.WriteLine($"parsed {parsed}");

    // Read again inside the lambda: a counter the closure keeps.
    int n = 0;
    Next next = () => { n++; return n; };
    next();
    next();
    Console.WriteLine($"next {next()} n {n}");

    // The value of the step is the result, so the copy is read.
    int ticket = 10;
    Next take = () => ticket++;
    take();
    Console.WriteLine($"take {take()}");

    // A captured reference names the one object: the write reaches it.
    var box = new Box();
    Act fill = () => box.Value = 3;
    fill();
    Console.WriteLine($"box {box.Value}");

    int[] cells = [0, 0];
    Act mark = () => cells[1] = 4;
    mark();
    Console.WriteLine($"cells {cells[1]}");

    var clicks = new Clicks();
    clicks.Lost()();
    Console.WriteLine($"lost {clicks.Count}");
    clicks.Kept()();
    Console.WriteLine($"kept {clicks.Count}");

    Point point;
    point.X = 1;
    point.Move()();
    Console.WriteLine($"point {point.X}");
}
