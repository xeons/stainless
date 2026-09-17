// Every integer type through `Text.FromInteger`, which has a `long`, a `ulong`
// and a `nuint` overload.
//
// Every one of these used to be a compile error but the three that match an
// overload exactly: a `byte` widens to all three parameter types, and a call
// that fit several was ambiguous however much better one of them fitted. The
// better conversion is chosen now, as C# chooses it -- the narrower target
// where one holds the other, and the signed one where neither does.
module IntegerText;

import Standard.Console;

String Show(long n) => "long";
String Show(double d) => "double";

String Pick(byte b) => "byte";
String Pick(int i) => "int";

int Main()
{
    sbyte a = -100;
    byte b = 200;
    short c = -30000;
    ushort d = 60000;
    int e = -2000000000;
    uint f = 4000000000u;
    long g = -9000000000000000000;
    ulong h = 18000000000000000000ul;
    nint i = -7;
    nuint j = 7u;

    Console.WriteLine(Text.FromInteger(a) + " " + Text.FromInteger(b) + " "
                      + Text.FromInteger(c) + " " + Text.FromInteger(d));
    Console.WriteLine(Text.FromInteger(e) + " " + Text.FromInteger(f) + " "
                      + Text.FromInteger(g) + " " + Text.FromInteger(h));
    Console.WriteLine(Text.FromInteger(i) + " " + Text.FromInteger(j) + " "
                      + Text.FromInteger(42));

    Console.WriteLine($"{a} {b} {c} {d} {e} {f} {g} {h} {i} {j}");

    // The same rule away from the standard library: an integer converts to
    // both, and `long` is the one that also converts to the other.
    Console.WriteLine(Show(3) + " " + Show(b) + " " + Show(2.5));

    // An identity beats a widening, and a literal that fits a byte is still
    // an int.
    Console.WriteLine(Pick(b) + " " + Pick(e) + " " + Pick(7));
    return 0;
}
