// SPDX-License-Identifier: 0BSD
//
// A `for parallel` captures every outside variable its body reads, wherever in
// the body the read is: in a switch, in an interpolated string, in a `do`, in a
// lambda made there, or in an array literal.
module ParallelCapturesInside;

import Standard.Console;

public closure int Offset(int x);

int Main()
{
    var slots = new int[8];
    int offset = 100;
    int scale = 3;
    String label = "x";

    for parallel (int i = 0; i < 8; i++)
    {
        switch (i % 2)
        {
            case 0:
                slots[i] = offset;
                break;
            default:
                slots[i] = i;
                break;
        }
    }
    Console.WriteLine($"{slots[0]} {slots[1]} {slots[2]}");

    String[] texts = Array.Repeat("", 4u);
    for parallel (int i = 0; i < 4; i++)
        texts[i] = $"{label}{i * scale}";
    Console.WriteLine($"{texts[0]} {texts[1]} {texts[3]}");

    var counts = new int[4];
    for parallel (int i = 0; i < 4; i++)
    {
        do
        {
            counts[i] = counts[i] + scale;
        }
        while (counts[i] < offset);
    }
    Console.WriteLine($"{counts[0]} {counts[3]}");

    var shifted = new int[4];
    for parallel (int i = 0; i < 4; i++)
    {
        Offset by = (int x) => x + offset;
        shifted[i] = by(i);
    }
    Console.WriteLine($"{shifted[0]} {shifted[3]}");

    var pairs = new int[4];
    for parallel (int i = 0; i < 4; i++)
    {
        int[] pair = [i, scale];
        pairs[i] = pair[0] * pair[1];
    }
    Console.WriteLine($"{pairs[1]} {pairs[3]}");
    return 0;
}
