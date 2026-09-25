// SPDX-License-Identifier: 0BSD
//
// Assignment evaluates as C#'s does: the place first, left to right, then the
// value, then the store. A compound assignment works its place out once and
// names it twice, so `a[i++] += 10` steps `i` a single time and adds to the
// element it read. Every call below logs, so the order is what is printed.
module AssignmentOrder;

import Standard.Console;
import Standard.Collections;

class Holder
{
    public int F;
    public int P { get; set; }
    public String Name = "";
    public String? Label { get; set; }
    public int[] Cells = new int[2];
}

class Grid
{
    int[] _cells = new int[4];

    public int this[int at]
    {
        get => _cells[at];
        set => _cells[at] = value;
    }
}

struct Wallet
{
    public int _count;
    public int Count { get => _count; set => _count = value; }
}

struct Flags
{
    public uint Low : 4;
    public uint High : 4;
}

struct Money
{
    public long Cents;

    public static Money operator +(Money a, Money b)
    {
        Money sum;
        sum.Cents = a.Cents + b.Cents;
        return sum;
    }
}

// Replaces what an assignment is storing into while it is storing into it.
// C# writes the object it had already reached, and so does this; the one
// replaced is kept alive until the statement ends rather than freed under
// the store.
class Owner
{
    public Holder _holder = new Holder();
    public int[] _items = new int[2];

    public int Replace()
    {
        _holder = new Holder();
        _items = new int[2];
        return 5;
    }

    public String Run()
    {
        _holder.F = Replace();
        _items[0] = Replace();
        _holder.F += Replace();
        _items[1] += Replace();
        _holder.P += Replace();
        return $"{_holder.F} {_items[0]} {_items[1]} {_holder.P}";
    }
}

// A generic container, where the element type is only known per instance.
class Box<T>
{
    T[] _cells;

    public Box(nuint size) => _cells = new T[size];

    public T this[int at]
    {
        get => _cells[at];
        set => _cells[at] = value;
    }
}

struct Point
{
    public int X;
    public int Y;
}

class Shape
{
    public Point Origin;
}

struct Row
{
    public int[4] Values;
}

public closure void Bump();

Holder Get(Holder holder, String why)
{
    Console.WriteLine($"get {why}");
    return holder;
}

Holder Make(String why)
{
    Console.WriteLine($"make {why}");
    return new Holder();
}

int Log(String what, int value)
{
    Console.WriteLine(what);
    return value;
}

String Word(String what)
{
    Console.WriteLine($"word {what}");
    return what;
}

public int Main()
{
    var held = new Holder();

    // The place is worked out once.
    int[] a = new int[4];
    int i = 0;
    a[i++] += 10;
    Console.WriteLine($"a {a[0]} {a[1]} i {i}");

    Get(held, "field").F += 5;
    Console.WriteLine($"F {held.F}");

    var grid = new Grid();
    grid[Log("index", 1)] += 7;
    grid[Log("index", 1)] *= 3;
    Console.WriteLine($"grid {grid[1]}");

    Make("temporary").F += 1;
    Get(held, "property").P += 3;
    Get(held, "property").P++;
    Console.WriteLine($"P {held.P}");

    // The place comes before the value.
    int[] b = new int[4];
    int k = 0;
    b[k++] = k;
    int j = 0;
    b[j + 2] = j = 3;
    Console.WriteLine($"b {b[0]} {b[2]}");
    Get(held, "receiver").F = Log("value", 9);
    Get(held, "receiver").P = Log("value", 11);
    grid[Log("index", 2)] = Log("value", 4);
    Console.WriteLine($"F {held.F} P {held.P} grid {grid[2]}");

    // The value sees what the place did, and the old value is read first.
    int x = 1;
    x += x++ + 10;
    Console.WriteLine($"x {x}");

    // A String appended through a receiver that is called once.
    Get(held, "name").Name += Word("a");
    Get(held, "name").Name += Word("b");
    Console.WriteLine($"name {held.Name}");

    // `??=` asks once and stores only when there was nothing.
    String?[] names = new String?[2];
    names[Log("slot", 0)] ??= Word("first");
    names[Log("slot", 0)] ??= Word("second");
    Get(held, "label").Label ??= Word("label");
    Get(held, "label").Label ??= Word("again");
    Console.WriteLine($"names {names[0] ?? "-"} label {held.Label ?? "-"}");

    // A bit-field, spliced into the unit it shares.
    Flags flags;
    flags.Low = 3u;
    flags.High = 1u;
    flags.Low += (uint)Log("bits", 2);
    Console.WriteLine($"flags {flags.Low} {flags.High}");

    // A declared operator, over an element.
    var purse = new Money[2];
    Money coin;
    coin.Cents = 7;
    purse[Log("purse", 1)] += coin;
    purse[Log("purse", 1)] += coin;
    Console.WriteLine($"purse {purse[1].Cents}");

    // A struct's property on an array element: the element is storage.
    var wallets = new Wallet[2];
    wallets[Log("wallet", 1)].Count = 4;
    wallets[Log("wallet", 1)].Count += 3;
    wallets[1].Count++;
    Console.WriteLine($"wallet {wallets[1].Count}");

    // Through a container's indexer, to an object and to a number.
    var holders = new List<Holder>();
    holders.Add(new Holder());
    holders[(nuint)Log("list", 0)].F += 9;
    holders[(nuint)Log("list", 0)].Cells[Log("cell", 1)] += 2;
    var numbers = new List<int>();
    numbers.Add(1);
    numbers[(nuint)Log("numbers", 0)] += 10;
    numbers[(nuint)Log("numbers", 0)] *= 2;
    Console.WriteLine($"list {holders[0u].F} {holders[0u].Cells[1]} numbers {numbers[0u]}");

    // Inside a lambda, which holds its own copy of the array reference.
    var total = new int[1];
    Bump bump = () => total[Log("lambda", 0)] += 5;
    bump();
    bump();
    Console.WriteLine($"lambda {total[0]}");

    // An assignment is a value: the one stored.
    int[] c = new int[2];
    int n = 0;
    int got = c[n++] += 4;
    Console.WriteLine($"value {got} {c[0]} {n}");

    // A generic indexer, and a struct field inside an object.
    var box = new Box<long>(2u);
    box[Log("box", 1)] += 6L;
    box[Log("box", 1)] -= (long)Log("step", 2);
    var shapes = new Shape[1];
    shapes[0] = new Shape();
    shapes[Log("shape", 0)].Origin.X += Log("dx", 5);
    shapes[Log("shape", 0)].Origin.Y = Log("dy", 6);
    Console.WriteLine($"box {box[1]} shape {shapes[0].Origin.X} {shapes[0].Origin.Y}");

    // An inline array inside an element, and a pointer.
    var rows = new Row[2];
    rows[Log("row", 1)].Values[Log("column", 2)] += Log("add", 5);
    int* at = &rows[1].Values[0];
    at[Log("pointer", 2)] *= 3;
    Console.WriteLine($"row {rows[1].Values[2]}");

    Console.WriteLine($"owner {new Owner().Run()}");
    return 0;
}
