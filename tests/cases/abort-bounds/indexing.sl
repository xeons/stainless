// SPDX-License-Identifier: 0BSD
//
// An out-of-range index stops the program, and says which index and which
// length. The spec states it twice -- §2.11 for an array and §9 for the
// arithmetic C leaves undefined -- and nothing measured it, because until
// `aborts.txt` the harness had no way to run a case that does not return.
module Indexing;

import Standard.Console;
import Standard.Text;

int Main()
{
    var numbers = new int[(nuint)3];
    numbers[0] = 1;

    Console.WriteLine("length " + Text.FromInteger((long)numbers.Length));

    // In range, so that the message below is about the one that is not.
    Console.WriteLine("last " + Text.FromInteger((long)numbers[2]));

    nuint past = 5;
    var lost = numbers[past];

    Console.WriteLine("unreachable");
    return 0;
}
