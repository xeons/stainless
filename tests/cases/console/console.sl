// SPDX-License-Identifier: 0BSD
//
// `Standard.Console` — the three that write and the one that flushes.
//
// `ReadLine`, `ReadToEnd` and `IsInputAtEnd` are pinned by `environment`, which has
// the stdin to feed them. What is here is the other half: that `Write` adds
// nothing, that `WriteLine` adds a newline, and that `WriteError` writes a
// whole line to stderr rather than to stdout. The harness compares stdout and
// then stderr, so the last line below arriving last is the assertion.
module ConsoleCase;

import Standard.Console;

int Main()
{
    // Three calls, one line: Write adds nothing of its own.
    Console.Write("a");
    Console.Write("b");
    Console.WriteLine("c");

    Console.Flush();

    Console.WriteLine("second");

    // Its newline is not optional, so this is a line and not a fragment.
    Console.WriteError("on stderr");
    return 0;
}
