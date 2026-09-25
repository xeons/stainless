// SPDX-License-Identifier: 0BSD
//
// An expression inside a `for parallel` body may hold a value for its own
// length: `?.` holds what it asks about, and a compound assignment whose value
// runs code holds the place it writes. Each belongs to the iteration that
// evaluates it, not to the loop's surroundings.
module ParallelHeld;

import Standard.Console;

threadsafe class Box
{
    public int[] Cells = new int[8];
    public int Size = 3;
}

int Twice(nuint i) => (int)i * 2;

public int Main()
{
    var box = new Box();
    Box? maybe = box;
    var sizes = new int[8];

    for parallel (nuint i = 0u; i < 8u; i++)
    {
        box.Cells[i] += Twice(i);
        sizes[i] = maybe?.Size ?? 0;
    }

    int total = 0;
    for (nuint i = 0u; i < 8u; i++)
        total += box.Cells[i] + sizes[i];
    Console.WriteLine($"{total}");
    return 0;
}
