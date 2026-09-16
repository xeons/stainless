// SPDX-License-Identifier: 0BSD
module Bad;

public class Packet
{
    public const nuint HeaderSize = 20u;

    // Two declarations of one name inside a type are one name declared twice,
    // whichever kinds they are.
    public const nuint HeaderSize = 24u;
}

public class Frame
{
    public const int Width = 8;
    public static readonly int Width = 8;
}

int Main() => 0;
