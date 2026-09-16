// SPDX-License-Identifier: 0BSD
module Widths;

extern "C" int printf(byte* format, ...);

// What a literal is, and what it becomes.
//
// A literal adopts what can hold it, and a minus in front of one does not take
// that away: `-100` fits an sbyte as plainly as `200` fits a byte. A float
// literal is spelled with an `f`, as in C#, and is a float from the lexer
// onwards rather than a rounded double. And the type a literal starts out as
// is the narrowest of int, uint, long and ulong that holds it, which is what
// keeps a value past an int from being cut to 32 bits on its way to something
// wider.

const float Tenth = 0.1;        // a double literal suits a float constant
const float Negative = -2.5f;
const double Widened = 1.5f;    // and a float literal suits a double one
const sbyte Floor = -128;

String Show(sbyte v) => "sbyte";
String Show(int v) => "int";
String Pick(short v) => "short";
String Pick(long v) => "long";

int Main()
{
    sbyte c = -100;
    short s = -30000;
    sbyte floor = -128;
    short shortFloor = -32768;
    int intFloor = -2147483648;
    long big = -9000000000000000000;
    byte zero = -0;
    printf("%d %d %d %d %d %lld %d\n", c, s, floor, shortFloor, intFloor, big, zero);

    float f = 1.5f;
    float g = (float)0.1;
    double d = g;
    float h = f * 2.0f + g;
    float negated = -1.25f;
    float exponent = 2.5e3f;
    printf("%.3f %.3f %.3f %.3f %.3f %.1f\n", f, g, d, h, negated, exponent);
    printf("%.3f %.3f %.3f %d\n", Tenth, Negative, Widened, Floor);

    // Past an int, and still the number that was written. Each of these came
    // out as its own low 32 bits before the literal carried a type of its own.
    long wide = 9223372036854775807;
    ulong top = 18446744073709551615;
    nuint size = 5000000000;
    double asDouble = 5000000000;
    float asFloat = 5000000000;
    printf("%lld %llu %llu %.1f %.1f\n", wide, top, (ulong)size, asDouble, asFloat);

    // A mask written the way a C header writes it. The literal is wider than
    // an int, so the operation widens rather than the literal being cut.
    int flags = -65536;
    var masked = flags & 0xFFFF0000;
    printf("%lld\n", (long)masked);

    // An exact match still wins, and a literal that fits only one overload
    // picks it.
    printf("%s %s\n", Show(-5).ToPointer(), Pick(-40000).ToPointer());
    return 0;
}
