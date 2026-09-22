// SPDX-License-Identifier: 0BSD
//
// The edges of `Standard.Math` and `Standard.Bits` where the obvious code is
// wrong: a power of two past 2^32, the most negative `long` in Euclid, bounds
// given the wrong way round, and the exact value of machine epsilon.
module TextMathEdges;

import Standard.Console;
import Standard.Text;
import Standard.Math;
import Standard.Bits;
import Standard.Limits;

void Wide(String what, ulong value)
{
    Console.WriteLine(what + " " + Text.FromInteger(value));
}

void Signed(String what, long value)
{
    Console.WriteLine(what + " " + Text.FromInteger(value));
}

void Says(String what, bool value)
{
    Console.WriteLine(what + " " + (value ? "yes" : "no"));
}

int Main()
{
    Wide("round-up-5e9", Bits.RoundUpToPowerOfTwo((ulong)5000000000));
    Wide("round-up-2^32+1", Bits.RoundUpToPowerOfTwo((ulong)4294967297));
    Wide("round-up-2^63", Bits.RoundUpToPowerOfTwo((ulong)0x8000000000000000));
    Wide("round-up-past", Bits.RoundUpToPowerOfTwo((ulong)0x8000000000000001));

    long min = Limits.MinLong;
    Signed("gcd-min-6", Math.GreatestCommonDivisor(min, 6));
    Signed("gcd-6-min", Math.GreatestCommonDivisor(6, min));
    Signed("gcd-min-neg-4", Math.GreatestCommonDivisor(min, -4));
    Signed("gcd-min-3", Math.GreatestCommonDivisor(min, 3));
    Signed("gcd-neg", Math.GreatestCommonDivisor(-48, 18));
    Signed("gcd-zero", Math.GreatestCommonDivisor(0, 0));
    Signed("gcd-min-0", Math.GreatestCommonDivisor(min, 0));
    Signed("gcd-min-min", Math.GreatestCommonDivisor(min, min));

    Signed("clamp-int-reversed", (long)Math.Clamp(15, 10, 0));
    Signed("clamp-int-reversed-low", (long)Math.Clamp(-5, 10, 0));
    Signed("clamp-long-reversed", Math.Clamp((long)15, (long)10, (long)0));
    Wide("clamp-nuint-reversed", (ulong)Math.Clamp((nuint)15, (nuint)10, (nuint)0));
    Says("clamp-double-reversed", Math.Clamp(15.0, 10.0, 0.0) == 10.0);
    Signed("clamp-int-inside", (long)Math.Clamp(5, 0, 10));

    Says("epsilon-exact", Math.Epsilon == 1.0 / 4503599627370496.0);
    Says("epsilon-step", 1.0 + Math.Epsilon != 1.0);
    return 0;
}
