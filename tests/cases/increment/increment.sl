// SPDX-License-Identifier: 0BSD
//
// `++` and `--`, in both positions and over every kind of place.
//
// They are not lowered to `x = x + 1`, and the difference shows up twice here.
// The postfix form's value is the one from before the write, so `i++` and
// `++i` are different expressions rather than different spellings. And the
// place is worked out exactly once: `cells[Next()]++` calls `Next` one time,
// where an assignment to `cells[Next()] + 1` would have called it twice and
// stepped an element it never read.
module Increment;

import Standard.Console;

class Counter
{
    public int Value { get; set; }
    public Counter() => Value = 0;
}

struct Flags
{
    public uint Low : 4;
    public uint High : 4;
}

static int calls = 0;

/// Counts how often an index expression was evaluated.
int Next()
{
    calls++;
    return 1;
}

public int Main()
{
    // A local, both ways round.
    int i = 5;
    Console.WriteLine($"post   {i++} then {i}");
    Console.WriteLine($"pre    {++i} then {i}");
    Console.WriteLine($"down   {--i} and {i--} then {i}");

    // The loop everybody writes.
    int total = 0;
    for (int n = 0; n < 5; n++)
        total += n;
    Console.WriteLine($"total  {total}");

    // An array element, indexed by something with a side effect.
    var cells = new int[3];
    cells[Next()]++;
    cells[Next()]++;
    Console.WriteLine($"cells  {cells[1]} after {calls} calls");

    // A property, which is a getter and a setter rather than an address.
    var c = new Counter();
    c.Value++;
    ++c.Value;
    Console.WriteLine($"getset {c.Value} post {c.Value++} now {c.Value}");

    // A field, and a bit-field, which is a splice rather than a store.
    Flags flags;
    flags.Low = 7u;
    flags.High = 1u;
    flags.Low++;
    flags.High--;
    Console.WriteLine($"bits   {flags.Low} {flags.High}");

    // Unsigned, where wrapping is the defined behaviour either way.
    byte small = 254;
    small++;
    Console.WriteLine($"byte   {small}");
    small++;
    Console.WriteLine($"wrap   {small}");

    // A double steps by one, not by an integer add.
    double scale = 1.5;
    scale++;
    Console.WriteLine($"double {scale}");

    // A pointer steps by an element, as C's does.
    var numbers = new int[4];
    numbers[0] = 10;
    numbers[1] = 20;
    numbers[2] = 30;

    int* walk = &numbers[0];
    walk++;
    Console.WriteLine($"ptr    {*walk}");
    walk++;
    Console.WriteLine($"ptr    {*walk}");
    walk--;
    Console.WriteLine($"back   {*walk}");

    // The value of an increment is a value like any other.
    int fed = 0;
    Console.WriteLine($"fed    {Twice(fed++)} then {fed}");
    Console.WriteLine($"fed    {Twice(++fed)} then {fed}");

    // An indexer is a property that takes arguments, and the arguments belong
    // to the step as much as the receiver does. This read and wrote a cell
    // nobody had named until the accessors were given their indices: the
    // increment went somewhere else and the value never moved.
    var grid = new Grid(8u);
    grid[4u] = 9;
    grid[4u]++;
    Console.WriteLine($"index  {grid[4u]}");
    grid[4u]--;
    Console.WriteLine($"index  {grid[4u]}");

    // And the index is worked out exactly once, as an array's is.
    grid[Counter.Next()]++;
    Console.WriteLine($"once   {grid[2u]} after {Counter.Calls} call");
    return 0;
}

/// An indexer over an array, so `grid[i]` is a pair of accessor calls rather
/// than an address.
class Grid
{
    int[] _cells;

    public Grid(nuint size) => _cells = new int[size];

    public int this[nuint at]
    {
        get => _cells[at];
        set => _cells[at] = value;
    }
}

/// Counts how many times an index expression was evaluated.
class Counter
{
    public static int Calls = 0;

    public static nuint Next()
    {
        Calls++;
        return 2u;
    }
}

int Twice(int n) => n * 2;
