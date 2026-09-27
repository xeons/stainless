// SPDX-License-Identifier: 0BSD
//
// `params`: a call may give the last parameter's elements one by one. A
// `T[]` is gathered into a new array; a `Span<T>` into an array in the caller's
// frame, which costs no allocation.
module Params;

import Standard.Console;
import Standard.Text;

int Sum(params int[] values)
{
    int total = 0;
    foreach (int value in values)
        total += value;
    return total;
}

int SumSlice(params Span<int> values)
{
    int total = 0;
    foreach (int value in values)
        total += value;
    return total;
}

String Join(String separator, params Span<String> parts)
{
    var joined = "";
    for (nuint i = 0; i < parts.Length; i++)
    {
        if (i > 0)
            joined = joined + separator;
        joined = joined + parts[i];
    }
    return joined;
}

// The declared form is preferred where both fit.
String Which(int value) => "one int";
String Which(params int[] values) => "params of " + Text.FromInteger((long)values.Length);

T First<T>(params T[] items) => items[0];
nuint Count<T>(params Span<T> items) => items.Length;

String Labelled(String label = "none", params int[] values) =>
    label + ":" + Text.FromInteger(Sum(values));

int Note(int value)
{
    Console.WriteLine("evaluated " + Text.FromInteger(value));
    return value;
}

String Ordered(int a, int b, params Span<int> rest) =>
    Text.FromInteger(a) + "," + Text.FromInteger(b) + "+" + Text.FromInteger((long)rest.Length);

public struct Named
{
    public String Name;
    public int Rank;
}

Named Make(String name, int rank)
{
    Named made;
    made.Name = name;
    made.Rank = rank;
    return made;
}

String Describe(params Span<Named> all)
{
    var text = "";
    foreach (Named one in all)
        text = text + one.Name + Text.FromInteger(one.Rank);
    return text;
}

class Bag
{
    int _total;

    public Bag(params int[] values)
    {
        foreach (int value in values)
            _total += value;
    }

    public int Total => _total;

    public void Add(params Span<int> values)
    {
        foreach (int value in values)
            _total += value;
    }
}

// What the callee hands back lives as long as the statement, which is as
// long as the frame's array does.
Span<int> Echo(params Span<int> values) => values;

nuint Lengths(params Span<Span<int>> parts)
{
    nuint total = 0;
    foreach (Span<int> part in parts)
        total += part.Length;
    return total;
}

// Reached as `values.Plus(1, 2)`: the receiver is the first argument.
int Plus(int[] values, params int[] more) => Sum(values) + Sum(more);

int Main()
{
    Console.WriteLine(Text.FromInteger(Sum(1, 2, 3)));
    Console.WriteLine(Text.FromInteger(Sum()));

    int[] array = [4, 5, 6];
    Console.WriteLine(Text.FromInteger(Sum(array)));
    Console.WriteLine(Text.FromInteger(Sum([7, 8])));

    Console.WriteLine(Text.FromInteger(SumSlice(7, 8, 9)));
    Console.WriteLine(Text.FromInteger(SumSlice()));
    Console.WriteLine(Text.FromInteger(SumSlice(array)));
    Console.WriteLine(Text.FromInteger(SumSlice(array[1:])));

    Console.WriteLine(Join(", ", "a", "b" + "b", "c"));
    Console.WriteLine(Join("-"));

    Console.WriteLine(Which(1));
    Console.WriteLine(Which(1, 2));
    Console.WriteLine(Which());
    Console.WriteLine(Which(array));

    Console.WriteLine(Text.FromInteger(First(10, 20)));
    Console.WriteLine(First("x", "y"));
    Console.WriteLine(Text.FromInteger(First(array)));
    Console.WriteLine(Text.FromInteger((long)Count("p", "q", "r")));
    Console.WriteLine(Text.FromInteger((long)Count(1.5, 2.5)));

    Console.WriteLine(Labelled());
    Console.WriteLine(Labelled("some", 1, 2));
    Console.WriteLine(Labelled(label: "named"));
    Console.WriteLine(Labelled(values: array));

    // Evaluated as written, the gathered ones included.
    Console.WriteLine(Ordered(Note(1), Note(2), Note(3), Note(4)));
    Console.WriteLine(Ordered(b: Note(20), a: Note(10)));

    Console.WriteLine(Describe(Make("ada", 1), Make("bo" + "b", 2)));

    var bag = new Bag(1, 2, 3, 4);
    bag.Add(5, 6);
    bag.Add();
    Console.WriteLine(Text.FromInteger(bag.Total));

    Console.WriteLine(Text.FromInteger(array.Plus(1, 2)));

    Console.WriteLine(Text.FromInteger(SumSlice(Echo(1, 2, 3))));
    Console.WriteLine(Text.FromInteger((long)Lengths(Echo(1, 2), Echo(3), Echo())));

    // The frame's array is the same slot every time round.
    for (int i = 0; i < 3; i++)
        Console.WriteLine(Text.FromInteger(SumSlice(i, i, i)));

    // A worker outlives the statement that spawned it, so its elements are
    // on the heap.
    int spawned = 0;
    parallel
    {
        spawned = spawn SumSlice(100, 200);
    }
    Console.WriteLine(Text.FromInteger(spawned));
    return 0;
}
