// SPDX-License-Identifier: 0BSD
//
// Main's String[] on a 32-bit target, where an array's header is half the
// size it is on a 64-bit one. Every argument lands in its own element.
module ArgsX86;

import Standard.Console;
import Standard.Text;

int Main(String[] args)
{
    Console.WriteLine("count " + Text.FromInteger((long)args.Length));
    foreach (var one in args)
        Console.WriteLine("  " + one);
    return 0;
}
