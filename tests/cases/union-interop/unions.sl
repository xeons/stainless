// SPDX-License-Identifier: 0BSD
//
// A union is what a great many C headers are made of: a value that is one of
// several things, with the choice recorded somewhere else. This checks that
// Stainless and the target's C compiler agree about every byte of one.
module Library.Unions;

public struct Pair {
    public int A;
    public int B;
}

public union Word {
    public int Signed;
    public uint Unsigned;
    public float Real;
}

public union Wide {
    public double D;
    public Pair P;
    public byte B;
}

// The shape a C header actually has: a tag beside the union that says which
// member the union is holding. The union does not record it, and cannot.
public enum Kind : int { AsInt = 0, AsReal = 1 }

public struct Tagged {
    public Kind Which;
    public Word Value;
}

export "C" nuint WordSize() { return sizeof(Word); }
export "C" nuint WideSize() { return sizeof(Wide); }
export "C" nuint TaggedSize() { return sizeof(Tagged); }

// Written on one side, read on the other: the members have to overlap the same
// way in both or these come back wrong.
export "C" uint ReadUnsigned(Word word) { return word.Unsigned; }
export "C" int ReadBits(Word word) { return word.Signed; }
export "C" int ReadPairB(Wide wide) { return wide.P.B; }

export "C" Word MakeReal(float value) {
    Word word;
    word.Real = value;
    return word;
}

export "C" int TaggedInt(Tagged tagged) {
    if (tagged.Which == Kind.AsInt) { return tagged.Value.Signed; }
    return -1;
}
