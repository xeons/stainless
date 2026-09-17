// Integers as text on a target where a pointer is four bytes.
//
// `Text.FromInteger` of a `nuint` was declared as taking a `nuint` and bound
// to the runtime's `unsigned long long` entry point. On x86 the caller pushed
// four bytes and the runtime read eight, so `$"{n}"` of 5 printed a nineteen-
// digit number whose low half was 5. A `ulong`, meanwhile, could not be
// interpolated at all there, because the only unsigned conversion took a
// `nuint` and a `ulong` does not narrow into one implicitly.
module X86IntegerText;

import Standard.Console;

int Main()
{
    nuint n = 5u;
    nint s = -6;
    uint u = 4000000000u;
    ulong big = 18446744073709551615ul;
    long negative = -9000000000;
    byte b = 200;

    Console.WriteLine($"{n} {s} {u} {big} {negative} {b}");
    Console.WriteLine(Text.FromInteger(n) + " " + Text.FromInteger(s) + " "
                      + Text.FromInteger(big) + " " + Text.FromInteger(negative));

    // Two in a row, which is where the stray high half came from: whatever the
    // caller had pushed next.
    nuint length = 12u;
    nuint index = 3u;
    Console.WriteLine($"{index} of {length}");

    // Every integer type by overload, which here is where `nuint` is narrower
    // than `long` and so widens to all three of `FromInteger`'s parameters.
    sbyte a = -100;
    short c = -30000;
    ushort d = 60000;
    int e = -2000000000;
    Console.WriteLine(Text.FromInteger(a) + " " + Text.FromInteger(b) + " "
                      + Text.FromInteger(c) + " " + Text.FromInteger(d) + " "
                      + Text.FromInteger(e) + " " + Text.FromInteger(u) + " "
                      + Text.FromInteger(42));
    return 0;
}
