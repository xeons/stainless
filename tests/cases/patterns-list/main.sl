// SPDX-License-Identifier: 0BSD
//
// List patterns: `[]`, `[first, ..]`, `[.., last]`, `[1, .. var rest]`.
// The length is read once and asked first; each element is then read by its
// index from whichever end it was written against. What `..` names is a
// slice of the same array, not a copy of it.
module PatternsList;

import Standard.Console;
import Standard.Text;
import Standard.Collections;

public class Tracked
{
    public String Name;
    public Tracked(String name) { Name = name; }
    ~Tracked() { Console.WriteLine("~" + Name); }
}

String Shape(int[] items) => items switch
{
    [] => "empty",
    [var only] => "just " + Text.FromInteger(only),
    [1, .., var last] => "one to " + Text.FromInteger(last),
    [var first, _] => "pair from " + Text.FromInteger(first),
    [var first, .. var rest] => Text.FromInteger(first) + " and " +
                                Text.FromInteger((long)rest.Length) + " more",
};

int Sum(Span<int> items) => items switch
{
    [] => 0,
    [var head, .. var tail] => head + Sum(tail),
};

String Ends(List<String> words)
{
    if (words is [var first, .., var last])
        return first + ".." + last;
    return "too short";
}

String Named(Tracked[] people) => people switch
{
    [{ Name: "ann" }, ..] => "ann first",
    [.., var last] => "ends with " + last.Name,
    [] => "nobody",
};

int Main()
{
    Console.WriteLine(Shape([]));
    Console.WriteLine(Shape([9]));
    Console.WriteLine(Shape([1, 2, 3]));
    Console.WriteLine(Shape([4, 5]));
    Console.WriteLine(Shape([4, 5, 6, 7]));

    int[] numbers = [1, 2, 3, 4];
    Console.WriteLine(Text.FromInteger(Sum(numbers[:])));

    // The rest is a view of the array it came from.
    if (numbers is [_, .. var rest])
    {
        rest[0] = 20;
        Console.WriteLine(Text.FromInteger(numbers[1]));
    }

    var words = new List<String>();
    words.Add("alpha");
    Console.WriteLine(Ends(words));
    words.Add("beta");
    words.Add("gamma");
    Console.WriteLine(Ends(words));

    Console.WriteLine(Named([new Tracked("ann"), new Tracked("bo")]));
    Console.WriteLine(Named([new Tracked("cy"), new Tracked("di")]));
    Tracked[] none = [];
    Console.WriteLine(Named(none));

    int[3] inline = [7, 8, 9];
    if (inline is [7, var middle, _])
        Console.WriteLine("middle " + Text.FromInteger(middle));

    return 0;
}
