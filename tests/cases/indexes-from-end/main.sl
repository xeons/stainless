// SPDX-License-Identifier: 0BSD
//
// `^n` counts back from the end: on an array, a slice and an inline array it
// is an index the bounds check measures against the length it already has;
// on a type with `Count` and an integer indexer it is `x[x.Count - n]`, with
// `x` evaluated once. Kept, it is a `Standard.Index`.
module IndexesFromEnd;

import Standard.Console;
import Standard.Text;
import Standard.Collections;

/// Counts, and is indexed by an integer, and says nothing about `Index`.
struct Triple
{
    public int First;
    public int Second;
    public int Third;

    public nuint Length => 3u;

    public int this[int at]
    {
        get
        {
            switch (at)
            {
                case 0: return First;
                case 1: return Second;
                default: return Third;
            }
        }
        set
        {
            switch (at)
            {
                case 0: First = value; break;
                case 1: Second = value; break;
                default: Third = value; break;
            }
        }
    }
}

/// Hands out one list, and counts how often it was asked.
class Holder
{
    public List<String> Items = new List<String>();
    public int Calls = 0;

    public List<String> Fetch()
    {
        Calls++;
        return Items;
    }
}

T Last<T>(T[:] items) => items[^1];

void Show(String label, long value) => Console.WriteLine(label + " " + Text.FromInteger(value));

public void Main()
{
    int[] numbers = [10, 20, 30, 40, 50];
    Show("last", numbers[^1]);
    Show("first", numbers[^5]);

    int back = 2;
    Show("back", numbers[^back]);

    numbers[^2] = 44;
    numbers[^1] += 5;
    numbers[^3]++;
    Show("written", numbers[2] + numbers[3] + numbers[4]);

    int[:] view = numbers[1:];
    Show("slice", view[^1]);

    int[3] inline = [1, 2, 3];
    Show("inline", inline[^1] * 10 + inline[^3]);
    inline[^2] = 7;
    Show("inline written", inline[1]);

    // Kept, then used: the same element, whichever end it names.
    Index last = ^1;
    Index third = 2;
    Show("kept", numbers[last] + numbers[third]);

    bool fromEnd = numbers.Length > 3u;
    Index chosen = new Index(1u, fromEnd);
    Show("chosen", numbers[chosen]);
    Show("value", (long)chosen.Value);
    Show("offset", (long)last.GetOffset(numbers.Length));

    // A type with a count and an integer indexer, as C# has it.
    var names = new List<String>();
    names.Add("ada");
    names.Add("grace");
    names.Add("edsger");
    Console.WriteLine(names[^1] + " " + names[last] + " " + names[^3]);
    names[^1] = "barbara";
    Console.WriteLine(names[2]);

    // Named once: the list is fetched a single time for the write and the count.
    var holder = new Holder();
    holder.Items.Add("one");
    holder.Items.Add("two");
    holder.Fetch()[^1] = "zwei";
    holder.Fetch()[^2] += "!";
    Console.WriteLine(holder.Items[0] + " " + holder.Items[1] + " " + Text.FromInteger(holder.Calls));

    Triple triple;
    triple.First = 1;
    triple.Second = 2;
    triple.Third = 3;
    triple[^1] = 30;
    Show("struct", triple[^1] + triple[^3]);

    List<String>? maybe = names;
    Console.WriteLine(maybe?[^1] ?? "none");
    maybe = null;
    Console.WriteLine(maybe?[^1] ?? "none");

    Show("generic", Last(numbers));
    Console.WriteLine(Last<String>(["x", "y"]));

    Func<int, int> nth = (int k) => numbers[^k];
    Show("closure", nth(1));
}
