// SPDX-License-Identifier: 0BSD
//
// `a..b` over an array or a slice is the slice `a[a:b]` is: a view, not a
// copy, with either end counted from where it says. Kept, it is a
// `Standard.Range`. A type with a count and `Slice(start, length)` answers
// with what that method makes, and a list pattern's `.. var rest` asks it too.
module Ranges;

import Standard.Console;
import Standard.Text;
import Standard.Collections;

/// Counts, and slices by start and length, as C# asks of a type.
class Word
{
    String[:] _letters;

    public Word(String[:] letters)
    {
        _letters = letters;
    }

    public nuint Length => _letters.Length;

    public String this[nuint at] => _letters[at];

    public Word Slice(nuint start, nuint length) => new Word(_letters[start:start + length]);

    public String Spelled()
    {
        var text = "";
        foreach (var letter in _letters)
            text += letter;
        return text;
    }
}

String Joined(int[:] numbers)
{
    var text = "";
    foreach (var n in numbers)
        text += text.IsEmpty ? Text.FromInteger(n) : " " + Text.FromInteger(n);
    return text;
}

int[] Numbers() => [1, 2, 3, 4, 5, 6];

int[] Announced(int[] numbers)
{
    Console.WriteLine("sliced");
    return numbers;
}

Range Announced(Range range)
{
    Console.WriteLine("range");
    return range;
}

public void Main()
{
    int[] numbers = Numbers();
    Console.WriteLine(Joined(numbers[1..4]));
    Console.WriteLine(Joined(numbers[..2]));
    Console.WriteLine(Joined(numbers[^2..]));
    Console.WriteLine(Joined(numbers[1..^1]));
    Console.WriteLine(Joined(numbers[..]));
    Console.WriteLine(Joined(numbers[^4..^2]));
    Console.WriteLine(Joined(numbers[2:^2]));

    // A view: writing through it writes the array.
    int[:] middle = numbers[1..^1];
    middle[0] = 20;
    middle[^1] = 50;
    Console.WriteLine(Joined(numbers));

    // Narrowing a slice narrows it again.
    Console.WriteLine(Joined(middle[1..^1]));

    int from = 1;
    int to = 3;
    Console.WriteLine(Joined(numbers[from..to]));
    Console.WriteLine(Joined(Numbers()[^to..^from]));

    // Kept as values.
    Range inner = 1..^1;
    Range all = ..;
    Range tail = 4..;
    Console.WriteLine(Joined(numbers[inner]) + " | " + Joined(numbers[all]) + " | " + Joined(numbers[tail]));
    Console.WriteLine(Text.FromInteger((long)inner.Start.Value) + " " +
        Text.FromBool(inner.End.IsFromEnd));

    Index start = 2;
    Index end = ^1;
    Console.WriteLine(Joined(numbers[start..end]));

    var (offset, length) = inner.GetOffsetAndLength(numbers.Length);
    Console.WriteLine(Text.FromInteger((long)offset) + " " + Text.FromInteger((long)length));

    // A list slices by its own Slice, which copies.
    var list = new List<String>();
    list.Add("a");
    list.Add("b");
    list.Add("c");
    list.Add("d");
    List<String> some = list[1..^1];
    Console.WriteLine(Text.FromInteger((long)some.Count) + " " + some[0] + some[1]);
    Console.WriteLine(list[inner][^1]);

    var word = new Word(["s", "t", "a", "i", "n"]);
    Console.WriteLine(word[1..^1].Spelled() + " " + word[^2..].Spelled());

    if (word is [var first, .. var rest])
        Console.WriteLine(first + " then " + rest.Spelled());

    foreach (var n in numbers[^3..])
        Console.WriteLine(Text.FromInteger(n));

    // What is sliced is evaluated before the range, as it is written.
    Console.WriteLine(Joined(Announced(numbers)[Announced(1..3)]));
}
