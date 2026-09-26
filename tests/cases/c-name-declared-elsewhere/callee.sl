// SPDX-License-Identifier: 0BSD
module Callee;

import Standard.Console;

export "C" int Twice(int x) => x * 2;

export "C" void Note(byte* text)
{
    int length = 0;
    while (text[length] != 0)
        length++;
    Console.WriteLine($"{length}");
}
