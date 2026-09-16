// SPDX-License-Identifier: 0BSD
//
// The arithmetic C leaves undefined and C# defines. Stainless follows C# where
// there is a sensible answer, and traps where there is not.
module Edges;

import Standard.Console;

// A struct with no fields still occupies a byte, so a struct containing one
// lays out the same way the emitted LLVM type does.
struct Marker { }
struct Tagged
{
    public Marker mark;
    public int value;
}

int Forty() => 40;
long Seventy() => 70;
int Four() => 4;

int Main()
{
    // The count is reduced modulo the width, as in C#, rather than left
    // undefined as in C.
    Console.WriteLine(Text.FromInteger(1 << Forty()));       // 1 << 8
    Console.WriteLine(Text.FromInteger(1 << Seventy()));     // count of a wider type
    long one = 1;
    Console.WriteLine(Text.FromInteger(one << Seventy()));   // 1L << 6
    Console.WriteLine(Text.FromInteger(-16 >> 2));
    Console.WriteLine(Text.FromInteger(1 << 30));

    // Division by a divisor that is not zero is untouched.
    Console.WriteLine(Text.FromInteger(100 / Four()));
    Console.WriteLine(Text.FromInteger(100 % Four()));

    // An empty struct is one byte, so `value` is not at offset 0 and a copy
    // moves the whole thing.
    Tagged first;
    first.value = 42;
    Tagged second = first;
    Console.WriteLine(Text.FromInteger(second.value));
    Console.WriteLine(Text.FromInteger((int)sizeof(Marker)));
    Console.WriteLine(Text.FromInteger((int)sizeof(Tagged)));

    // A negated literal is as wide as the value it holds. Every integer
    // literal starts out an `int` and adopts a wider type where it is used,
    // and a minus is in between: the width has to be chosen for the operation,
    // or the value truncates to 32 bits and widens back with nothing to say.
    long floor = -9223372036854775808;
    long wide = -9000000000000000000;
    long past = -4000000000;
    int smallest = -2147483648;     // still an int, as in C#
    Console.WriteLine(Text.FromInteger(floor));
    Console.WriteLine(Text.FromInteger(wide));
    Console.WriteLine(Text.FromInteger(past));
    Console.WriteLine(Text.FromInteger((long)smallest));

    // And an unsigned value past 2^63 writes as itself rather than as the
    // negative number the same bits spell.
    ulong huge = 18000000000000000000u;
    Console.WriteLine(Text.FromInteger(huge));

    return 0;
}
