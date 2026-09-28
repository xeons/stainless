// SPDX-License-Identifier: 0BSD
//
// The members `Span<T>` and `ReadOnlySpan<T>` have as C#'s do, declared in
// the standard library.
module SpanMembers;

import Standard.Console;
import Standard.Text;

public class Trace
{
    public String Name { get; }
    public Trace(String name) => Name = name;
    ~Trace() { Console.WriteLine("~" + Name); }
}

String Show(ReadOnlySpan<int> values)
{
    String text = "[";
    foreach (int v in values)
        text += (text == "[" ? "" : " ") + Text.FromInteger(v);
    return text + "]";
}

String Yes(bool value) => value ? "yes" : "no";

int Main()
{
    int[] numbers = [0, 1, 2, 3, 4, 5, 6, 7];

    var whole = new Span<int>(numbers);
    var part = new Span<int>(numbers, 2u, 3u);
    Console.WriteLine(Show(whole) + " " + Show(part));

    Console.WriteLine(Yes(Span<int>.Empty.IsEmpty) + " " + Yes(part.IsEmpty) + " " +
        Text.FromInteger((int)ReadOnlySpan<int>.Empty.Length));

    part.Fill(9);
    Console.WriteLine(Show(numbers));
    part.Clear();
    Console.WriteLine(Show(numbers));

    // Overlapping copies, both ways.
    for (nuint i = 0u; i < numbers.Length; i++)
        numbers[i] = (int)i;
    whole[0:5].CopyTo(whole[2:]);
    Console.WriteLine(Show(numbers));
    for (nuint i = 0u; i < numbers.Length; i++)
        numbers[i] = (int)i;
    whole[2:].CopyTo(whole);
    Console.WriteLine(Show(numbers));

    int[] small = new int[2];
    Console.WriteLine(Yes(whole.TryCopyTo(small)) + " " + Yes(whole[0:2].TryCopyTo(small)) + " " +
        Show(small));

    Console.WriteLine(Show(whole.Slice(5u)) + " " + Show(whole.Slice(1u, 2u)));

    ReadOnlySpan<int> seen = whole;
    int[] copy = seen.Slice(6u).ToArray();
    copy[0] = 100;
    Console.WriteLine(Show(copy) + " " + Text.FromInteger(numbers[6]));

    nint offset;
    Console.WriteLine(Yes(whole[0:4].Overlaps(whole[3:])) + " " + Yes(whole[0:3].Overlaps(whole[3:])) + " " +
        Yes(whole.Overlaps(copy)));
    if (whole[4:].Overlaps(whole[1:6], out offset))
        Console.WriteLine("offset " + Text.FromInteger((int)offset));

    Console.WriteLine(Yes(whole[1:3] == whole[1:3]) + " " + Yes(whole[1:3] == whole[1:4]) + " " +
        Yes(seen != whole) + " " + Yes(Span<int>.Empty == default(Span<int>)));

    // Written out, the type is the same one.
    Standard.Span<int> named = whole;
    Console.WriteLine(Text.FromInteger((int)named.Length));

    // Clearing releases what the elements held. Only an element with a zero
    // value can be cleared, so these are optional.
    Trace?[] traces = [new Trace("a"), new Trace("b")];
    var held = new Span<Trace?>(traces);
    held.Clear();
    Console.WriteLine("cleared");
    return 0;
}
