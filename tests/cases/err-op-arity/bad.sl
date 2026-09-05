// SPDX-License-Identifier: 0BSD
module Bad;

// `~` takes one operand and `*` takes two; neither takes what it likes.
public struct Mask {
    public uint Bits;
    public static Mask operator ~(Mask a, Mask b) { return a; }
}

int Main() { return 0; }
