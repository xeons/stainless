// SPDX-License-Identifier: 0BSD
//
// `foreach` taking each element apart as it is reached. The element is held
// in a local of the loop's own and taken apart into the names the loop
// declares, so each name is released at the end of its iteration, as a loop
// variable is.
module DeconstructionForeach;

import Standard.Console;
import Standard.Collections;

class Loud
{
    public String Tag;
    public Loud(String tag) => Tag = tag;
    ~Loud() { Console.WriteLine($"  dropped {Tag}"); }
}

record Entry(String Name, int Count);

public int Main()
{
    (int, String)[] numbered = [(1, "one"), (2, "two")];
    foreach (var (number, word) in numbered)
        Console.WriteLine($"a {number} {word}");

    var list = new List<(String, int)>();
    list.Add(("x", 10));
    list.Add(("y", 20));
    foreach ((String key, long value) in list)
        Console.WriteLine($"b {key} {value}");

    foreach ((var key, _) in list)
        Console.WriteLine($"c {key}");

    // Nested, and through a record's generated Deconstruct.
    var nested = new List<(int, Entry)>();
    nested.Add((1, new Entry("apples", 3)));
    nested.Add((2, new Entry("pears", 5)));
    foreach (var (index, (name, count)) in nested)
        Console.WriteLine($"d {index} {name} {count}");

    // A dictionary's pairs, through KeyValuePair's Deconstruct.
    var stock = new Dictionary<String, int>();
    stock.SetValue("bolts", 40);
    int total = 0;
    foreach (var (item, amount) in stock)
    {
        Console.WriteLine($"e {item} {amount}");
        total += amount;
    }
    Console.WriteLine($"e total {total}");

    // `continue` and `break` behave as in any other loop.
    foreach (var (number, word) in numbered)
    {
        if (number == 1)
            continue;
        Console.WriteLine($"f {word}");
        break;
    }

    Console.WriteLine("references:");
    var louds = new List<(Loud, int)>();
    louds.Add((new Loud("first"), 1));
    louds.Add((new Loud("second"), 2));
    foreach (var (loud, at) in louds)
        Console.WriteLine($"  {loud.Tag} {at}");
    louds.Clear();

    Console.WriteLine("done");
    return 0;
}
