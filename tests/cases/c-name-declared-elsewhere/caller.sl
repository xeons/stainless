// SPDX-License-Identifier: 0BSD
module Caller;

import Standard.Console;

// Declared here and defined in another module, the way a C header and its
// source split a function. Both halves are one symbol.
extern "C" int Twice(int x);
extern "C" void Note(byte* text);

int Main()
{
    Console.WriteLine($"{Twice(21)}");
    Note("declared in one module, defined in another");
    return 0;
}
