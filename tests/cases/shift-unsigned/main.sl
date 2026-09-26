// SPDX-License-Identifier: 0BSD
//
// `>>>` shifts in zeros whatever the operand's sign, where `>>` copies the
// sign bit on a signed one. It promotes, masks its count and overloads as
// the other shifts do, and `>>>` closing three type argument lists at once
// still closes them.
module ShiftUnsigned;

import Standard.Console;
import Standard.Text;
import Standard.Collections;

struct Bits
{
    public uint Value;

    public static Bits operator >>>(Bits bits, int count)
    {
        Bits shifted;
        shifted.Value = bits.Value >>> count;
        return shifted;
    }
}

public void Main()
{
    Console.WriteLine(Text.FromInteger(-16 >>> 28) + " " + Text.FromInteger(-16 >> 28));

    long big = -1L;
    Console.WriteLine(Text.FromInteger(big >>> 60) + " " + Text.FromInteger(big >> 60));

    // An sbyte promotes to int first, as it does for `>>` and as C# has it.
    sbyte small = (sbyte)-128;
    Console.WriteLine(Text.FromInteger(small >>> 4));

    uint top = 1u << 31;
    Console.WriteLine(Text.FromInteger(top >>> 31));

    // The count is taken modulo the width.
    int one = 1;
    Console.WriteLine(Text.FromInteger(-1 >>> (32 + one)));

    int k = -1;
    k >>>= 1;
    Console.WriteLine(Text.FromInteger(k));

    Bits bits;
    bits.Value = 256u;
    Bits shifted = bits >>> 4;
    Console.WriteLine(Text.FromInteger(shifted.Value));

    var nested = new List<List<List<int>>>();
    nested.Add(new List<List<int>>());
    Console.WriteLine(Text.FromInteger((long)nested.Count));
}
