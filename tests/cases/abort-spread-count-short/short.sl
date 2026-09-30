// SPDX-License-Identifier: 0BSD
//
// A spread's `Count` sizes the array a collection expression makes. One that
// promises more than it yields would leave elements nothing wrote, and a
// `String` read from one would be a null, so the program stops first.
module AbortSpreadCountShort;

import Standard.Console;
import Standard.Collections;

class Promise : IEnumerable<String>
{
    public nuint Count { get; }

    public Promise(nuint count)
    {
        Count = count;
    }

    public IEnumerator<String> GetEnumerator()
    {
        var held = new List<String>();
        held.Add("one");
        return held.GetEnumerator();
    }
}

int Main()
{
    String[] kept = [..new Promise(1u)];
    Console.WriteLine($"kept {kept.Length} {kept[0]}");
    String[] shortfall = ["first", ..new Promise(3u)];
    Console.WriteLine($"never {shortfall[2]}");
    return 0;
}
