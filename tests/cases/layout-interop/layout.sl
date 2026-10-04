// SPDX-License-Identifier: 0BSD
//
// [Packed] and [Align] have to agree with the target's C compiler about every
// byte, and the only way to know that is to ask it. The consumer checks size,
// alignment and every field offset against the generated header.
module Library.Layout;

public struct Plain
{
    public byte Tag;
    public int Value;
    public byte Trailer;
}

// No padding anywhere: what a wire format or an on-disk header looks like.
[Packed]
public struct Wire
{
    public byte Tag;
    public int Value;
    public byte Trailer;
}

// Raised, never lowered: the fields are already 8-aligned and this asks for 16.
[Align(16)]
public struct Wide
{
    public double X;
    public double Y;
}

// Both: nothing padded inside, and the whole of it on a 4-byte boundary.
[Packed]
[Align(4)]
public struct Both
{
    public byte A;
    public int B;
    public byte C;
}

// No field aligned to more than two: what a header inside
// `#pragma pack(push, 2)` lays out, as the Carbon-era ones on macOS are.
[Pack(2)]
public struct Carbon
{
    public short A;
    public int B;
    public double C;
    public byte D;
}

// One field packed, as IOKit's NXEvent packs its 64-bit time: it lands where
// the field before it ended, and the struct asks only what the rest ask.
public struct Event
{
    public int Type;
    [Packed] public long Time;
    public int Flags;
}

export "C" nuint PlainSize() => sizeof(Plain);
export "C" nuint EventSize() => sizeof(Event);
export "C" nuint CarbonSize() => sizeof(Carbon);
export "C" nuint WireSize() => sizeof(Wire);
export "C" nuint WideSize() => sizeof(Wide);
export "C" nuint BothSize() => sizeof(Both);

// Read through a value C built, so the offsets are checked and not just the size.
// Every type is also named in a signature, because the header describes exactly
// what the exported surface mentions and nothing else.
export "C" byte PlainTag(Plain plain) => plain.Tag;
export "C" int BothB(Both both) => both.B;
export "C" int WireValue(Wire wire) => wire.Value;
export "C" byte WireTrailer(Wire wire) => wire.Trailer;
export "C" double WideY(Wide wide) => wide.Y;
export "C" double CarbonC(Carbon carbon) => carbon.C;
export "C" long EventTime(Event value) => value.Time;
