// SPDX-License-Identifier: 0BSD
//
// `ReadOnlySpan<T>` is the view a function takes when it only reads. An array
// and a `Span<T>` both convert to one, and cutting one keeps it read-only.
module Spans;

import Standard.Console;
import Standard.Collections;
import Standard.Text;

public class Trace
{
    public String Name { get; }
    public Trace(String name) => Name = name;
    ~Trace() { Console.WriteLine("~" + Name); }
}

int Sum(ReadOnlySpan<int> values)
{
    int total = 0;
    foreach (int v in values)
        total += v;
    return total;
}

nuint Count<T>(params ReadOnlySpan<T> items) => items.Length;

T Last<T>(ReadOnlySpan<T> items) => items[^1];

String Shape(ReadOnlySpan<int> values) => values switch
{
    [] => "empty",
    [var only] => "one: " + Text.FromInteger(only),
    [var first, .. var rest] => $"{first} then {rest.Length} more",
};

// A fresh span, handed to a parameter that only reads it.
Span<Trace> Made()
{
    var traces = new Trace[3];
    traces[0] = new Trace("a");
    traces[1] = new Trace("b");
    traces[2] = new Trace("c");
    return traces[1:];
}

String Names(ReadOnlySpan<Trace> traces)
{
    String text = "";
    foreach (var t in traces)
        text += t.Name;
    return text;
}

int Main()
{
    int[] numbers = [1, 2, 3, 4, 5, 6];
    Span<int> middle = numbers[1:5];

    Console.WriteLine(Text.FromInteger(Sum(numbers)));
    Console.WriteLine(Text.FromInteger(Sum(middle)));

    // A read-only view of a span still sees a write made through the span.
    ReadOnlySpan<int> seen = middle;
    middle[0] = 20;
    Console.WriteLine(Text.FromInteger(seen[0]));

    // Cutting a read-only span gives another one.
    ReadOnlySpan<int> inner = seen[1:3];
    Console.WriteLine(Text.FromInteger(Sum(inner)));

    Console.WriteLine(Shape(numbers[0:0]));
    Console.WriteLine(Shape(numbers[2:3]));
    Console.WriteLine(Shape(seen));

    Console.WriteLine(Text.FromInteger((int)Count(1, 2, 3)));
    Console.WriteLine(Text.FromInteger(Last(middle)));
    Console.WriteLine(Text.FromInteger((int)BinarySearch(numbers, 4).GetValue()));
    Console.WriteLine(Text.FromInteger(Where(seen, n => n % 2 == 0).Count));

    ReadOnlySpan<byte> greeting = "hi"u8;
    Console.WriteLine(Text.FromInteger(greeting[0]));

    Console.WriteLine(Names(Made()));
    return 0;
}
