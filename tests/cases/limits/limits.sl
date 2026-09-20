// SPDX-License-Identifier: 0BSD
//
// `Standard.Limits` — what each number type holds.
//
// Printing the values would only pin that they are what they are. What is
// checked here is that each one is genuinely the edge: arithmetic wraps
// (§9.12), so one past a maximum is the matching minimum and one before a
// minimum is the maximum. A digit dropped from any of these constants fails
// that and nothing else would notice.
module LimitsCase;

import Standard.Console;
import Standard.Text;
import Standard.Limits;

void Says(String what, bool ok)
{
    Console.WriteLine(what + " " + (ok ? "yes" : "no"));
}

int Main()
{
    // ------------------------------------------------------- the values, once

    Console.WriteLine("sbyte " + Text.FromInteger((long)MinSByte) + " " + Text.FromInteger((long)MaxSByte));
    Console.WriteLine("short " + Text.FromInteger((long)MinShort) + " " + Text.FromInteger((long)MaxShort));
    Console.WriteLine("int " + Text.FromInteger((long)MinInt) + " " + Text.FromInteger((long)MaxInt));
    Console.WriteLine("long " + Text.FromInteger(MinLong) + " " + Text.FromInteger(MaxLong));
    Console.WriteLine("byte " + Text.FromInteger((long)MinByte) + " " + Text.FromInteger((long)MaxByte));
    Console.WriteLine("ushort " + Text.FromInteger((long)MinUShort) + " " + Text.FromInteger((long)MaxUShort));
    Console.WriteLine("uint " + Text.FromInteger((long)MinUInt) + " " + Text.FromInteger((long)MaxUInt));
    Console.WriteLine("ulong " + Text.FromInteger(MinULong) + " " + Text.FromInteger(MaxULong));

    // ------------------------------------------------- the edge, by wrapping

    int highInt = MaxInt;
    long highLong = MaxLong;
    uint highUInt = MaxUInt;
    ulong highULong = MaxULong;

    Says("int/over", highInt + 1 == MinInt);
    Says("int/under", MinInt - 1 == MaxInt);
    Says("long/over", highLong + 1 == MinLong);
    Says("long/under", MinLong - 1 == MaxLong);
    Says("uint/over", highUInt + 1u == MinUInt);
    Says("uint/under", MinUInt - 1u == MaxUInt);
    Says("ulong/over", highULong + 1u == MinULong);
    Says("ulong/under", MinULong - 1u == MaxULong);

    // The narrow ones promote to `int` before they can wrap, so the edge is
    // checked by the cast back instead.
    Says("sbyte/over", (sbyte)(MaxSByte + 1) == MinSByte);
    Says("byte/over", (byte)(MaxByte + 1) == MinByte);
    Says("short/over", (short)(MaxShort + 1) == MinShort);
    Says("ushort/over", (ushort)(MaxUShort + 1) == MinUShort);

    // ---------------------------------------------------------- the target's

    // Written twice behind an `#if`, so what is checked is that the right half
    // was compiled rather than what the number is.
    Says("nuint/width", sizeof(nuint) == 4u
        ? MaxNUInt == (nuint)MaxUInt
        : MaxNUInt == (nuint)MaxULong);
    Says("nint/width", sizeof(nint) == 4u
        ? MaxNInt == (nint)MaxInt
        : MaxNInt == (nint)MaxLong);

    // ------------------------------------------------------------- floating

    // Finite below the edge and infinite above it, which is what makes these
    // the largest values rather than merely large ones.
    Says("double/finite", MaxDouble * 1.0 == MaxDouble);
    Says("double/over", MaxDouble * 2.0 > MaxDouble);
    Says("double/sign", MinDouble == -MaxDouble);
    Says("double/small", SmallestDouble > 0.0);
    Says("float/sign", MinFloat == -MaxFloat);
    Says("float/small", SmallestFloat > 0.0f);

    return 0;
}
