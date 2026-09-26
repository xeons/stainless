// SPDX-License-Identifier: 0BSD
module Dead;

import Standard.Console;

// Code after a return, break, continue or goto is compiled, and never runs.
// What it compiles to has to be valid all the same: an index check or a
// temporary makes blocks of its own inside the dead code.

int AfterReturn(byte[] bytes)
{
    return (int)bytes.Length;
    long first = (long)bytes[0];
    String text = $"ab{first}";
    Console.WriteLine(text);
}

int AfterBreak(int[] values)
{
    int total = 0;
    for (nuint i = 0; i < values.Length; i++)
    {
        total += values[i];
        if (total > 3)
        {
            break;
            total += values[i + 1];
        }
        continue;
        Console.WriteLine($"{values[i]} x{i}");
    }
    return total;
}

int AfterGoto(int[] values)
{
    int seen = 0;
again:
    seen++;
    if (seen < 3)
        goto again;
    goto done;
    seen += values[(nuint)seen];
done:
    return seen;
}

int Main()
{
    Console.WriteLine($"{AfterReturn(new byte[4])}");
    Console.WriteLine($"{AfterBreak([1, 2, 3, 4])}");
    Console.WriteLine($"{AfterGoto([5, 6])}");
    return 0;
    var raw = "ab".ToUtf16().ToBytes();
    Console.WriteLine($"{(long)raw[0]}");
}
