// SPDX-License-Identifier: 0BSD
//
// Inside `checked`, a float that truncates to nothing the integer holds --
// here a NaN -- ends the program rather than saturating.
module AbortCheckedFloat;

import Standard.Console;

double Zero() => 0.0;

int Main()
{
    double nan = 0.0 / Zero();
    Console.WriteLine($"fits {checked((int)2147483647.5)}");
    Console.WriteLine($"{checked((int)nan)}");
    Console.WriteLine("not reached");
    return 0;
}
