// `sizeof`, `alignof` and `offsetof`, against the numbers C computes.
//
// Every expected value in this case was read off `sizeof`/`alignof`/`offsetof`
// in C on this target. They are the three questions a binding has to be able to
// ask about itself, and the reason `offsetof` exists at all is the struct C can
// describe and Stainless cannot: one ending in an inline array.
module LayoutQueries;

import Standard.Console;

public struct Mixed {
    public byte   Flag;
    public double Value;
    public int    Count;
}

public struct Tight {
    public int A;
    public int B;
}

[Packed]
public struct Squeezed {
    public byte   Flag;
    public double Value;
}

[Align(16)]
public struct Wide {
    public int A;
}

public union Word {
    public int   Signed;
    public uint  Unsigned;
    public float Real;
}

public enum Level : byte { Low = 1u, High = 2u }

/// A class is a header followed by its fields, and a class reference points at
/// the header — so an offset counts from there and is what to add to the
/// reference you hold.
public class Holder {
    public int    First;
    public double Second;
}

void Show(String name, nuint value) {
    Console.WriteLine(name + " = " + Text.FromInteger(value));
}

int Main() {
    Show("sizeof(Mixed)", sizeof(Mixed));
    Show("alignof(Mixed)", alignof(Mixed));
    Show("offsetof(Mixed, Flag)", offsetof(Mixed, Flag));
    Show("offsetof(Mixed, Value)", offsetof(Mixed, Value));
    Show("offsetof(Mixed, Count)", offsetof(Mixed, Count));

    Show("alignof(Tight)", alignof(Tight));
    Show("offsetof(Tight, B)", offsetof(Tight, B));

    // [Packed] removes the padding, so the double is not 8-aligned.
    Show("sizeof(Squeezed)", sizeof(Squeezed));
    Show("alignof(Squeezed)", alignof(Squeezed));
    Show("offsetof(Squeezed, Value)", offsetof(Squeezed, Value));

    // [Align] raises the alignment and, with it, the size.
    Show("sizeof(Wide)", sizeof(Wide));
    Show("alignof(Wide)", alignof(Wide));

    // Every member of a union is at zero, which is the whole of what a union is.
    Show("sizeof(Word)", sizeof(Word));
    Show("alignof(Word)", alignof(Word));
    Show("offsetof(Word, Signed)", offsetof(Word, Signed));
    Show("offsetof(Word, Real)", offsetof(Word, Real));

    Show("alignof(byte)", alignof(byte));
    Show("alignof(short)", alignof(short));
    Show("alignof(int)", alignof(int));
    Show("alignof(double)", alignof(double));
    Show("alignof(void*)", alignof(void*));
    Show("alignof(Level)", alignof(Level));

    Show("offsetof(Holder, First)", offsetof(Holder, First));
    Show("offsetof(Holder, Second)", offsetof(Holder, Second));
    return 0;
}
