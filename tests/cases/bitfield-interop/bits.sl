// SPDX-License-Identifier: 0BSD
//
// Bit-fields have to agree with the target's C compiler about which bits, not
// just about how many bytes. The consumer writes them from C and reads them
// back through Stainless, and the other way round.
module Library.Bits;

public struct Header {
    public uint Version : 4;
    public uint Kind : 4;
    public uint Length : 24;
}

// Signed fields sign-extend from their own width: three bits holding 7 is -1.
public struct Signed {
    public int Small : 3;
    public int Larger : 5;
}

// A bit-field beside an ordinary one, which closes whatever was being filled.
public struct Mixed {
    public uint Flags : 3;
    public double Weight;
    public uint More : 5;
}

export "C" nuint HeaderSize() { return sizeof(Header); }
export "C" nuint SignedSize() { return sizeof(Signed); }
export "C" nuint MixedSize() { return sizeof(Mixed); }

export "C" uint ReadVersion(Header header) { return header.Version; }
export "C" uint ReadKind(Header header) { return header.Kind; }
export "C" uint ReadLength(Header header) { return header.Length; }

export "C" int ReadSmall(Signed value) { return value.Small; }
export "C" int ReadLarger(Signed value) { return value.Larger; }

export "C" double ReadWeight(Mixed mixed) { return mixed.Weight; }
export "C" uint ReadMore(Mixed mixed) { return mixed.More; }

// Built here, read there.
export "C" Header MakeHeader(uint version, uint kind, uint length) {
    Header header;
    header.Version = version;
    header.Kind = kind;
    header.Length = length;
    return header;
}

// Writing one field must leave its neighbours alone.
export "C" Header BumpKind(Header header) {
    header.Kind = header.Kind + (uint)1;
    return header;
}
