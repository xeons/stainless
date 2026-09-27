// SPDX-License-Identifier: 0BSD
//
// Collection expressions: `[a, ..b, c]` becomes an array, an inline array, a
// slice, a class with `Add`, or one of the list interfaces, as where it is
// going says. A `..` walks anything `foreach` walks, and every element is
// evaluated once, in the order written.
module CollectionExpressions;

import Standard.Console;
import Standard.Text;
import Standard.Collections;

/// Has `Add` and a constructor taking nothing, which is all that is asked.
class Bag
{
    public List<String> Items = new List<String>();

    public void Add(String item) => Items.Add(item);
}

/// Walks down from a number, and cannot say how far beforehand.
class Countdown
{
    int _from;

    public Countdown(int from)
    {
        _from = from;
    }

    public CountdownEnumerator GetEnumerator() => new CountdownEnumerator(_from);
}

class CountdownEnumerator
{
    int _at;

    public CountdownEnumerator(int from)
    {
        _at = from + 1;
    }

    public bool MoveNext()
    {
        _at--;
        return _at > 0;
    }

    public int Current => _at;
}

class Node
{
    public String Name;

    public Node(String name)
    {
        Name = name;
    }
}

/// Records the order it was asked in.
class Trace
{
    public String Seen = "";

    public int Note(int value)
    {
        Seen += Text.FromInteger(value);
        return value;
    }

    public int[] Few(int value)
    {
        Seen += "[" + Text.FromInteger(value) + "]";
        return [value, value];
    }
}

void Show(String label, Span<int> numbers)
{
    var text = label + ":";
    foreach (var n in numbers)
        text += " " + Text.FromInteger(n);
    Console.WriteLine(text);
}

int Sum(Span<int> numbers)
{
    int total = 0;
    foreach (var n in numbers)
        total += n;
    return total;
}

int Sum(IEnumerable<int> numbers) => -1;

T[] Joined<T>(Span<T> left, Span<T> right) => [..left, ..right];

Node[] MakeNodes() => [new Node("a"), new Node("b")];

public void Main()
{
    int[] a = [1, 2, 3];
    int[] b = [7, 8];

    int[] all = [..a, 0, ..b];
    Show("all", all);
    Show("slice of", [..all[1..^1], 99]);

    int[3] inline = [4, 5, 6];
    int[] doubled = [..inline, ..inline];
    Show("inline", doubled);
    int[5] five = [..inline, 1, 2];
    Show("five", [..five]);

    List<int> list = [1, 2, ..a];
    Show("list", [..list]);
    int[] fromEnumerator = [100, ..new Countdown(3), 200];
    Show("walked", fromEnumerator);

    List<int> noList = [];
    int[] noArray = [];
    Console.WriteLine(Text.FromInteger((long)(noList.Count + noArray.Length)));

    Bag bag = ["x", "y", ..["z"]];
    Console.WriteLine(Text.FromInteger((long)bag.Items.Count) + " " + bag.Items[^1]);

    HashSet<int> set = [1, 1, 2, ..a];
    Console.WriteLine(Text.FromInteger((long)set.Count));

    IEnumerable<int> sequence = [3, ..a];
    var seen = "";
    foreach (var n in sequence)
        seen += Text.FromInteger(n);
    Console.WriteLine(seen);
    IReadOnlyList<String> names = ["p", "q"];
    Console.WriteLine(names[1]);

    // With nothing else to go on, the elements and what is spread decide.
    var natural = [..a, 4L];
    Console.WriteLine(Text.FromInteger(natural[3] * 1000000000000L));
    long[] widened = [..a, 5];
    Console.WriteLine(Text.FromInteger(widened[0] + widened[3]));

    // An array is preferred to a type it would have to call Add on.
    Console.WriteLine(Text.FromInteger(Sum([..a, ..b])));
    list.AddRange([5, 6]);
    Console.WriteLine(Text.FromInteger((long)list.Count));

    // Every element once, in the order written, before anything is made.
    var trace = new Trace();
    int[] ordered = [trace.Note(1), ..trace.Few(2), trace.Note(3), ..inline];
    Console.WriteLine(trace.Seen + " " + Text.FromInteger((long)ordered.Length));

    // References are held by the array, however they arrived.
    Node[] nodes = [..MakeNodes(), new Node("c"), ..MakeNodes()[1..]];
    var spelled = "";
    foreach (var node in nodes)
        spelled += node.Name;
    Console.WriteLine(spelled);
    List<Node> kept = [..nodes, ..nodes];
    Console.WriteLine(kept[^1].Name + Text.FromInteger((long)kept.Count));

    Console.WriteLine(Joined<String>(["x", "y"], ["z"])[^1]);
    Show("joined", Joined(a, b));

    int bump = 10;
    Func<int, int[]> make = (int k) => [k, ..a, bump];
    Show("closure", make(5));
}
