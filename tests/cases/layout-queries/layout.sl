// `sizeof`, `alignof` and `offsetof`, against the numbers C computes.
//
// Every expected value in this case was read off `sizeof`/`alignof`/`offsetof`
// in C on this target. They are the three questions a binding has to be able to
// ask about itself, and the reason `offsetof` exists at all is the struct C can
// describe and Stainless cannot: one ending in an inline array.
module LayoutQueries;

import Standard.Console;

public struct Mixed
{
    public byte Flag;
    public double Value;
    public int Count;
}

public struct Tight
{
    public int A;
    public int B;
}

[Packed]
public struct Squeezed
{
    public byte Flag;
    public double Value;
}

[Align(16)]
public struct Wide
{
    public int A;
}

public union Word
{
    public int Signed;
    public uint Unsigned;
    public float Real;
}

public enum Level : byte { Low = 1u, High = 2u }

/// A class is a header followed by its fields, and a class reference points at
/// the header — so an offset counts from there and is what to add to the
/// reference you hold.
public class Holder
{
    public int First;
    public double Second;
}

void Show(String name, nuint value)
{
    Console.WriteLine(name + " = " + Text.FromInteger(value));
}

int Main()
{
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

    // What `sizeof` says has to be what the generated code does, which is a
    // separate claim: LLVM has no way to be told a type's alignment, so an
    // over-aligned struct's stride is the emitter's to get right and this
    // line is what checks that it did.
    var many = new Wide[3];
    many[0u].A = 10;
    many[1u].A = 20;
    byte* first = (byte*)&many[0u];
    byte* second = (byte*)&many[1u];
    Show("stride of Wide[]", (nuint)second - (nuint)first);

    // And a struct holding one has to put it where `offsetof` says, which is
    // the same claim one level up. The same goes for a struct of bit-fields,
    // whose storage is bytes and whose alignment is therefore not its own.
    Show("sizeof(Nesting)", sizeof(Nesting));
    Show("offsetof(Nesting, Middle)", offsetof(Nesting, Middle));
    Show("offsetof(Nesting, Last)", offsetof(Nesting, Last));

    Nesting nested;
    nested.First = 1u;
    nested.Middle.A = 7;
    nested.Last = 9u;

    // Read back through the offsets rather than through the fields, so that
    // the two accounts have to agree rather than merely being consistent.
    byte* raw = (byte*)&nested;
    Show("Middle, at its offset",
         (nuint)*(int*)(raw + offsetof(Nesting, Middle)));
    Show("Last, at its offset", (nuint)*(raw + offsetof(Nesting, Last)));

    Show("sizeof(Bits)", sizeof(Bits));
    Show("offsetof(Bits, Flags)", offsetof(Bits, Flags));
    Show("offsetof(Bits, After)", offsetof(Bits, After));
    return 0;
}

/// A struct holding an over-aligned one, which is where the two accounts of a
/// layout meet.
public struct Nesting
{
    public byte First;
    public Wide Middle;
    public byte Last;
}

public struct Packed3 { public uint A : 3; public uint B : 5; public uint C : 24; }

/// And one holding a struct of bit-fields, whose storage is bytes.
public struct Bits
{
    public byte Lead;
    public Packed3 Flags;
    public byte After;
}
