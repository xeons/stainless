// SPDX-License-Identifier: 0BSD
//
// Inside `checked`, negating the most negative int is an overflow: the answer
// is not an int.
module AbortCheckedNegate;

import Standard.Console;

int Main()
{
    int least = -2147483648;
    int one = -1;
    Console.WriteLine($"negated {checked(-one)}");
    Console.WriteLine($"{checked(-least)}");
    Console.WriteLine("not reached");
    return 0;
}
