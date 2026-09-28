// SPDX-License-Identifier: 0BSD
module Zeroed;

import Standard.Console;
import Standard.Text;

// A local declared without a value holds its type's zero, whatever the stack
// held before. Each declaration below runs after a call that filled the frame
// with nonzero bytes, and inside a loop that writes it, so a missing store
// shows up as a number that is not zero.

void Scribble()
{
    ulong[32] noise;
    for (nuint i = 0u; i < 32u; i++)
        noise[i] = 0xDEADBEEFCAFEF00Du ^ (ulong)i;
    ulong sum = 0u;
    for (nuint i = 0u; i < 32u; i++)
        sum += noise[i];
    if (sum == 0u)
        Console.WriteLine("unreachable");
}

ulong ReadFresh()
{
    ulong total = 0u;
    for (nuint round = 0u; round < 3u; round++)
    {
        ulong scalar;
        uint[8] words;
        double real;
        byte* pointer;

        total += scalar;
        for (nuint i = 0u; i < 8u; i++)
            total += (ulong)words[i];
        if (real != 0.0 || pointer != null)
            total++;

        scalar = 7u;
        for (nuint i = 0u; i < 8u; i++)
            words[i] = 0xFFFFFFFFu;
        real = 1.5;
    }
    return total;
}

int Main()
{
    Scribble();
    Console.WriteLine("fresh " + Text.FromInteger((long)ReadFresh()));
    return 0;
}
