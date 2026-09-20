// SPDX-License-Identifier: 0BSD
//
// `Standard.Bits` — counting bits and rotating them.
//
// Every name here is a thin Stainless wrapper over an LLVM intrinsic the
// compiler declares, so what is pinned is the edges rather than the arithmetic:
// zero, which has no highest or lowest set bit; a rotation by nothing and by a
// whole width, which is where the obvious `(v << n) | (v >> (32 - n))` is
// wrong rather than slow; and the two values `RoundUpToPowerOfTwo` cannot
// answer properly.
module BitsCase;

import Standard.Console;
import Standard.Text;
import Standard.Bits;

void Count(String what, int value)
{
    Console.WriteLine(what + " " + Text.FromInteger((long)value));
}

void Wide(String what, ulong value)
{
    Console.WriteLine(what + " " + Text.FromInteger(value));
}

void Says(String what, bool value)
{
    Console.WriteLine(what + " " + (value ? "yes" : "no"));
}

int Main()
{
    // ------------------------------------------------------------- counting

    Count("pop/zero", PopCount(0u));
    Count("pop/full", PopCount(0xFFFFFFFFu));
    Count("pop/half", PopCount(0xAAAAAAAAu));
    Count("pop/zero64", PopCount(0uL));
    Count("pop/full64", PopCount(0xFFFFFFFFFFFFFFFFuL));

    // Zero has no set bit, so the count is the whole width both ways.
    Count("lead/zero", LeadingZeroCount(0u));
    Count("lead/one", LeadingZeroCount(1u));
    Count("lead/top", LeadingZeroCount(0x80000000u));
    Count("lead/zero64", LeadingZeroCount(0uL));
    Count("lead/one64", LeadingZeroCount(1uL));

    Count("trail/zero", TrailingZeroCount(0u));
    Count("trail/one", TrailingZeroCount(1u));
    Count("trail/top", TrailingZeroCount(0x80000000u));
    Count("trail/zero64", TrailingZeroCount(0uL));
    Count("trail/top64", TrailingZeroCount(0x8000000000000000uL));

    // ------------------------------------------------------------- rotating

    // By nothing, and by a whole width: both answer the value unchanged, which
    // a pair of shifts cannot do because shifting by the width is undefined.
    Wide("rot/none", (ulong)RotateLeft(0x12345678u, 0));
    Wide("rot/width", (ulong)RotateLeft(0x12345678u, 32));
    Wide("rot/left", (ulong)RotateLeft(0x12345678u, 4));
    Wide("rot/right", (ulong)RotateRight(0x12345678u, 4));

    // What falls off the top arrives at the bottom, and the other way.
    Wide("rot/wrap", (ulong)RotateLeft(0x80000001u, 1));
    Wide("rot/wrap64", RotateLeft(1uL, 63));
    Wide("rot/right64", RotateRight(1uL, 1));

    // --------------------------------------------------------- powers of two

    Count("log2/zero", Log2(0u));
    Count("log2/one", Log2(1u));
    Count("log2/below", Log2(1023u));
    Count("log2/exact", Log2(1024u));
    Count("log2/64", Log2(0x8000000000000000uL));

    Says("pow2/zero", IsPowerOfTwo(0u));
    Says("pow2/one", IsPowerOfTwo(1u));
    Says("pow2/exact", IsPowerOfTwo(1024u));
    Says("pow2/between", IsPowerOfTwo(1000u));

    Wide("round/zero", (ulong)RoundUpToPowerOfTwo(0u));
    Wide("round/one", (ulong)RoundUpToPowerOfTwo(1u));
    Wide("round/exact", (ulong)RoundUpToPowerOfTwo(1024u));
    Wide("round/above", (ulong)RoundUpToPowerOfTwo(1025u));

    // Past the largest power of two the type holds, the shift wraps and there
    // is no answer to give.
    Wide("round/over", (ulong)RoundUpToPowerOfTwo(0x80000001u));

    return 0;
}
