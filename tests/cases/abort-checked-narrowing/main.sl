// SPDX-License-Identifier: 0BSD
//
// Inside `checked`, the cast a compound assignment implies is checked as a
// written one is: 250 + 10 is no byte, so this ends the program.
module AbortCheckedNarrowing;

import Standard.Console;

int Main()
{
    byte level = 250;
    checked
    {
        level += 5;
        Console.WriteLine($"level {level}");
        level += 5;
    }
    Console.WriteLine("not reached");
    return 0;
}
