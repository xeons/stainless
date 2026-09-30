// SPDX-License-Identifier: 0BSD
//
// A spread that yields more than its `Count` runs off the end of the array
// made for it, and the index check stops it there.
module AbortSpreadCountLong;

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
        held.Add("two");
        return held.GetEnumerator();
    }
}

int Main()
{
    String[] kept = [..new Promise(2u)];
    Console.WriteLine($"kept {kept.Length} {kept[1]}");
    String[] overrun = ["first", ..new Promise(1u)];
    Console.WriteLine($"never {overrun[1]}");
    return 0;
}
