// SPDX-License-Identifier: 0BSD
//
// C#'s `MemoryExtensions`, as free functions in `Standard.Collections` that a
// call written on a span reaches.
module SpanExtensions;

import Standard.Console;
import Standard.Collections;
import Standard.Text;

String Show(ReadOnlySpan<int> values)
{
    String text = "[";
    foreach (int v in values)
        text += (text == "[" ? "" : " ") + Text.FromInteger(v);
    return text + "]";
}

String At(Optional<nuint> position) =>
    position is Some found ? Text.FromInteger((int)found.Value) : "none";

String Yes(bool value) => value ? "yes" : "no";

int Main()
{
    int[] numbers = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5];
    Span<int> span = numbers;
    ReadOnlySpan<int> seen = numbers;

    Console.WriteLine("index " + At(span.IndexOf(5)) + " " + At(seen.LastIndexOf(5)) + " " +
        At(span.IndexOf(7)) + " " + At(IndexOf(numbers, 9)));
    Console.WriteLine("runs " + At(seen.IndexOf([1, 5])) + " " + At(seen.LastIndexOf([5, 3])) + " " +
        At(seen.IndexOf([5, 5])) + " " + Text.FromInteger((int)seen.Count([1])) + " " +
        Text.FromInteger((int)seen.Count(5)));
    Console.WriteLine("any " + At(seen.IndexOfAny(9, 4)) + " " + At(seen.IndexOfAny(7, 8, 2)) + " " +
        At(seen.LastIndexOfAny([1, 3])) + " " + At(seen.IndexOfAnyExcept(3)) + " " +
        At(seen.LastIndexOfAnyExcept(5, 3)));
    Console.WriteLine("range " + At(seen.IndexOfAnyInRange(6, 9)) + " " +
        At(seen.IndexOfAnyExceptInRange(1, 5)) + " " + At(seen.LastIndexOfAnyInRange(2, 3)) + " " +
        Yes(seen.ContainsAnyInRange(10, 20)) + " " + Yes(seen.ContainsAnyExceptInRange(0, 9)));
    Console.WriteLine("contains " + Yes(seen.Contains(9)) + " " + Yes(seen.Contains(8)) + " " +
        Yes(seen.ContainsAny(8, 7)) + " " + Yes(seen.ContainsAny([7, 6])) + " " +
        Yes(seen.ContainsAnyExcept([1, 2, 3, 4, 5, 6, 9])));

    int[] same = [3, 1, 4];
    Console.WriteLine("compare " + Yes(seen[0:3].SequenceEqual(same)) + " " +
        Yes(seen.SequenceEqual(same)) + " " + Text.FromInteger(seen[0:3].SequenceCompareTo(same)) + " " +
        Text.FromInteger(seen[0:2].SequenceCompareTo(same)) + " " +
        Text.FromInteger(seen[0:3].SequenceCompareTo([3, 1, 2])) + " " +
        Text.FromInteger((int)seen.CommonPrefixLength([3, 1, 5])));
    Console.WriteLine("ends " + Yes(seen.StartsWith([3, 1])) + " " + Yes(seen.StartsWith(1)) + " " +
        Yes(seen.EndsWith([3, 5])) + " " + Yes(seen.EndsWith(5)));

    int[] padded = [0, 0, 7, 8, 0, 9, 0];
    Console.WriteLine("trim " + Show(Trim(padded, 0)) + " " + Show(padded.TrimStart(0)) + " " +
        Show(padded.TrimEnd([0, 9])));
    Span<int> inside = Trim(new Span<int>(padded), 0);
    inside[0] = 70;
    Console.WriteLine(Show(padded));

    span.Replace(5, 50);
    Console.WriteLine(Show(numbers));
    int[] replaced = new int[4];
    Replace(seen[0:4], replaced, 1, 10);
    Console.WriteLine(Show(replaced));

    span.Reverse();
    Console.WriteLine(Show(numbers));
    span.Sort();
    Console.WriteLine(Show(numbers) + " " + At(seen.BinarySearch(9)) + " " + At(seen.BinarySearch(8)));

    int[] keys = [3, 1, 2];
    String[] names = ["three", "one", "two"];
    Sort(keys, names);
    Console.WriteLine(Show(keys) + " " + names[0] + " " + names[1] + " " + names[2]);
    return 0;
}
