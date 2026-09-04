// SPDX-License-Identifier: 0BSD
//
// [Packed] and [Align] have to agree with the target's C compiler about every
// byte, and the only way to know that is to ask it. The consumer checks size,
// alignment and every field offset against the generated header.
module Library.Layout;

public struct Plain {
    public byte Tag;
    public int Value;
    public byte Trailer;
}

// No padding anywhere: what a wire format or an on-disk header looks like.
[Packed]
public struct Wire {
    public byte Tag;
    public int Value;
    public byte Trailer;
}

// Raised, never lowered: the fields are already 8-aligned and this asks for 16.
[Align(16)]
public struct Wide {
    public double X;
    public double Y;
}

// Both: nothing padded inside, and the whole of it on a 4-byte boundary.
[Packed]
[Align(4)]
public struct Both {
    public byte A;
    public int B;
    public byte C;
}

export "C" nuint PlainSize() { return sizeof(Plain); }
export "C" nuint WireSize() { return sizeof(Wire); }
export "C" nuint WideSize() { return sizeof(Wide); }
export "C" nuint BothSize() { return sizeof(Both); }

// Read through a value C built, so the offsets are checked and not just the size.
// Every type is also named in a signature, because the header describes exactly
// what the exported surface mentions and nothing else.
export "C" byte PlainTag(Plain plain) { return plain.Tag; }
export "C" int BothB(Both both) { return both.B; }
export "C" int WireValue(Wire wire) { return wire.Value; }
export "C" byte WireTrailer(Wire wire) { return wire.Trailer; }
export "C" double WideY(Wide wide) { return wide.Y; }
