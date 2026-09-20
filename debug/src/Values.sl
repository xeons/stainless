// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// A location and a type make a value.
//
// **Four things here are about this language rather than about DWARF**, and
// each is measured against `docs/abi.md` rather than assumed:
//
//   - **A class body includes its 24-byte `__header`**, so the field offsets
//     DWARF gives are already right and need no adjustment. The header is also
//     worth *reading*: `type` at +16 is an `SlTypeInfo*` whose `name` is at +16
//     of that, which is how a variable declared as a base class can show what
//     it actually is -- `Shape (Circle)` -- with no `[Reflect]` anywhere,
//     because every object carries the header whether or not it carries field
//     tables. And `strong` at +0 being zero means the object is dead, which
//     turns a stale weak reference from a lie into `(dead)`.
//
//   - **An array and a `String` are described as far as their length and no
//     further.** DWARF can only express an array whose bound it knows
//     statically, so the elements are left out rather than described wrongly.
//     `length` sits at offset 24 and the elements begin at **32**, not 24 --
//     the length is a word of its own.
//
//   - **A variant's tag cannot be mapped to a case.** The cases are numbered in
//     declaration order, but DWARF gets a member only for the ones that carry a
//     payload, so the k-th member is not tag k. Printing `tag = 2` and the
//     names it might be is the honest limit until the compiler emits an
//     enumeration for it.
//
//   - **Every local is in the function's scope**, because no `DILexicalBlock`
//     is emitted. A variable declared inside a loop is visible from the
//     function's first line, holding whatever its stack slot happened to
//     contain.
module Debugger;

import Standard.Collections;
import Standard.Text;

// The DWARF expression operations a local's location actually uses at -O0.
const uint OpAddr         = 0x03u;
const uint OpFbreg        = 0x91u;
const uint OpReg0         = 0x50u;
const uint OpReg31        = 0x6Fu;
const uint OpBreg0        = 0x70u;
const uint OpBreg31       = 0x8Fu;
const uint OpCallFrameCfa = 0x9Cu;

/// DWARF's numbering of the x86-64 registers, which is not the instruction
/// encoding's: 6 is RBP and 7 is RSP.
const ulong DwarfRegisterFramePointer = 6u;
const ulong DwarfRegisterStackPointer = 7u;

// `DW_ATE_*`: what a base type's bytes mean.
const ulong EncodingBoolean       = 0x02u;
const ulong EncodingFloat         = 0x04u;
const ulong EncodingSigned        = 0x05u;
const ulong EncodingSignedChar    = 0x06u;
const ulong EncodingUnsigned      = 0x07u;
const ulong EncodingUnsignedChar  = 0x08u;

/// Where the object header's fields are. `docs/abi.md` §2.3.
const nuint HeaderStrongOffset = 0u;
const nuint HeaderTypeOffset   = 16u;
const nuint HeaderSize         = 24u;

/// And `SlTypeInfo`: size, destroy, name.
const nuint TypeInfoNameOffset = 16u;

/// An array or a `String`: the length after the header, the elements after
/// that.
const nuint LengthOffset   = 24u;
const nuint ElementsOffset = 32u;

/// Reads one variable and says what it holds.
///
/// `frame` is the frame it lives in, which supplies the frame base every
/// `DW_OP_fbreg` is relative to.
public String ReadValue(Engine engine, ITarget target, Unit unit, Die variable,
                        Die owner, Registers frame)
{
    nuint at = 0u;
    if (!LocationOf(engine, unit, variable, owner, frame, &at))
        return "<no location>";

    var described = DescribeType(unit, variable);
    return FormatAt(engine, target, unit, described, at);
}

/// Where a variable lives, by running its location expression.
///
/// Only the operations a `-g -O0` build actually produces are implemented, and
/// anything else answers false rather than a plausible address -- a local read
/// from the wrong place is worse than one that says it could not be found.
bool LocationOf(Engine engine, Unit unit, Die variable, Die owner,
                Registers frame, nuint* address)
{
    var location = variable.Find(AtLocation);
    if (location == null)
        return false;
    byte[] program = ((Attribute)location).Block;
    if (program.Length == 0u)
        return false;

    var reader = new Cursor(program);
    uint operation = (uint)reader.U8();

    switch (operation)
    {
        case OpAddr:
        {
            // A static, whose address is link-time and so has to be slid.
            nuint linked = (nuint)ReadFixedWidth(reader, unit.AddressSize);
            *address = engine.ToRuntime(linked);
            return true;
        }

        case OpFbreg:
        {
            long offset = reader.SLeb();
            nuint frameBase = 0u;
            if (!FrameBaseOf(owner, frame, &frameBase))
                return false;
            *address = (nuint)((long)frameBase + offset);
            return true;
        }

        default:
            if (operation >= OpBreg0 && operation <= OpBreg31)
            {
                ulong which = (ulong)(operation - OpBreg0);
                long offset = reader.SLeb();
                nuint holding = 0u;
                if (!RegisterValue(frame, which, &holding))
                    return false;
                *address = (nuint)((long)holding + offset);
                return true;
            }
            return false;
    }
}

/// What `DW_AT_fbreg` is relative to, from the function's own
/// `DW_AT_frame_base`.
///
/// **Under `-g` this is `DW_OP_reg6 RBP`**, because the compiler emits
/// `"frame-pointer"="all"` there; see `docs/dwarf.md`. `DW_OP_call_frame_cfa`
/// is what the C runtime's own units use and is answered from the frame
/// pointer as well, which is right wherever there is one: the canonical frame
/// address on x86-64 is the frame pointer plus sixteen -- the saved pointer and
/// the return address.
bool FrameBaseOf(Die owner, Registers frame, nuint* base2)
{
    var found = owner.Find(AtFrameBase);
    if (found == null)
    {
        *base2 = frame.FramePointer;
        return frame.FramePointer != 0u;
    }

    byte[] program = ((Attribute)found).Block;
    if (program.Length == 0u)
        return false;

    var reader = new Cursor(program);
    uint operation = (uint)reader.U8();

    if (operation == OpCallFrameCfa)
    {
        *base2 = frame.FramePointer + 16u;
        return frame.FramePointer != 0u;
    }

    if (operation >= OpReg0 && operation <= OpReg31)
        return RegisterValue(frame, (ulong)(operation - OpReg0), base2);

    if (operation >= OpBreg0 && operation <= OpBreg31)
    {
        ulong which = (ulong)(operation - OpBreg0);
        long offset = reader.SLeb();
        nuint holding = 0u;
        if (!RegisterValue(frame, which, &holding))
            return false;
        *base2 = (nuint)((long)holding + offset);
        return true;
    }

    return false;
}

/// One of the three registers this engine carries. Anything else is refused
/// rather than guessed -- see `Registers`, which explains why there are three.
bool RegisterValue(Registers frame, ulong which, nuint* value)
{
    switch (which)
    {
        case DwarfRegisterFramePointer:
            *value = frame.FramePointer;
            return true;
        case DwarfRegisterStackPointer:
            *value = frame.StackPointer;
            return true;
        default:
            return false;
    }
}

/// What a variable's type is, with the wrappers taken off.
public class DescribedType
{
    public uint Tag;
    public String Name;
    public nuint Size;
    public ulong Encoding;

    /// The entry itself, for a caller that wants its members.
    public Die? Definition;

    public DescribedType()
    {
        Tag = 0u;
        Name = "?";
        Size = 0u;
        Encoding = 0u;
        Definition = null;
    }
}

/// Resolves a variable's `DW_AT_type`, stepping through the qualifiers.
///
/// `typedef`, `const` and `volatile` describe how a type may be used rather
/// than what its bytes are, so reading a value steps straight through them --
/// while the *name* kept is the first one seen, which is what the program
/// called it.
public DescribedType DescribeType(Unit unit, Die carrier)
{
    var answer = new DescribedType();

    var reference = carrier.Find(AtType);
    if (reference == null)
        return answer;

    nuint at = (nuint)((Attribute)reference).Value;
    String outermost = "";

    // A bound on the walk: a type graph with a cycle in it is a corrupt one,
    // and following it for ever is worse than saying so.
    for (int step = 0; step < 32; step++)
    {
        var found = unit.At(at);
        if (found == null)
            return answer;

        var die = (Die)found;
        String named = die.TextOf(AtName);
        if (outermost.ByteLength() == 0u && named.ByteLength() != 0u)
            outermost = named;

        if (die.Tag == TagTypedef || die.Tag == TagConstType
            || die.Tag == TagVolatileType)
        {
            var inner = die.Find(AtType);
            if (inner == null)
                break;
            at = (nuint)((Attribute)inner).Value;
            continue;
        }

        answer.Tag = die.Tag;
        answer.Name = named.ByteLength() != 0u ? named : outermost;
        answer.Size = (nuint)die.NumberOf(AtByteSize, 0u);
        answer.Encoding = die.NumberOf(AtEncoding, 0u);
        answer.Definition = die;

        // **A class reference is a pointer, and the pointer has no name.**
        // Every reference in this language is described as a
        // `DW_TAG_pointer_type` whose target is the class or array -- so the
        // name a program would recognise belongs to what is pointed at, and
        // taking the pointer's own leaves the type column empty and the
        // `String` and array cases below unable to recognise themselves.
        if (die.Tag == TagPointerType && answer.Name.ByteLength() == 0u)
            answer.Name = PointeeName(unit, die);

        // DWARF spells `void*` as a pointer with no target type at all, which
        // leaves nothing to name it after.
        if (die.Tag == TagPointerType && answer.Name.ByteLength() == 0u)
            answer.Name = "void*";

        // **A pointer's width is usually not written down.** LLVM leaves
        // `DW_AT_byte_size` off a pointer whose width is the unit's address
        // size, which is every pointer this compiler emits, so the unit is
        // what answers when the entry does not.
        if (answer.Size == 0u && die.Tag == TagPointerType)
            answer.Size = unit.AddressSize;

        return answer;
    }

    answer.Name = outermost.ByteLength() != 0u ? outermost : "?";
    return answer;
}

/// What a `DW_AT_type` points at, with the qualifiers stepped through.
///
/// The entry rather than a description of it, for a caller that wants the
/// members of what it found -- which `DescribedType` carries only for the
/// outermost entry.
Die? TypeEntryOf(Unit unit, Die carrier)
{
    var reference = carrier.Find(AtType);
    if (reference == null)
        return null;

    nuint at = (nuint)((Attribute)reference).Value;

    // Bounded for the same reason the walk in `DescribeType` is: a cycle here
    // is a corrupt file, and following it for ever is worse than saying so.
    for (int step = 0; step < 32; step++)
    {
        var found = unit.At(at);
        if (found == null)
            return null;

        var die = (Die)found;
        if (die.Tag != TagTypedef && die.Tag != TagConstType
            && die.Tag != TagVolatileType)
            return die;

        var inner = die.Find(AtType);
        if (inner == null)
            return null;
        at = (nuint)((Attribute)inner).Value;
    }
    return null;
}

/// Whether a pointer is a reference to an object rather than a raw address.
///
/// By the `__header` member, which the compiler emits on a class body, an
/// array body and the two text classes and on nothing else (docs/abi.md §2).
/// A `Point*` and a `void*` point at memory with no header in front of it, and
/// reading one as an object answers a strong count that is somebody's field.
bool PointsAtAnObject(Unit unit, DescribedType pointer)
{
    var definition = pointer.Definition;
    if (definition == null)
        return false;

    var pointee = TypeEntryOf(unit, (Die)definition);
    if (pointee == null)
        return false;

    var body = (Die)pointee;
    if (body.Tag != TagStructureType && body.Tag != TagClassType)
        return false;

    var members = ChildrenOf(unit, body);
    return !members.IsEmpty && members[0u].Name == "__header";
}

/// What a pointer points at, by name.
String PointeeName(Unit unit, Die pointer)
{
    var reference = pointer.Find(AtType);
    if (reference == null)
        return "";

    nuint at = (nuint)((Attribute)reference).Value;
    for (int step = 0; step < 32; step++)
    {
        var found = unit.At(at);
        if (found == null)
            return "";
        var die = (Die)found;

        String named = die.TextOf(AtName);
        if (named.ByteLength() != 0u)
            return named;

        var inner = die.Find(AtType);
        if (inner == null)
            return "";
        at = (nuint)((Attribute)inner).Value;
    }
    return "";
}

/// Reads and formats a value of a described type at an address.
public String FormatAt(Engine engine, ITarget target, Unit unit,
                       DescribedType described, nuint at)
    => FormatValueAt(engine, target, unit, described, at, 0);

/// How far a value may be printed into. A struct inside a struct is shown, and
/// one inside that is `{...}`: the third level is rarely what was asked for and
/// always what makes a line too long to read.
const int WatchDepthLimit = 2;

/// How many members of one aggregate are shown before the rest are `...`.
const nuint MembersShown = 12u;

String FormatValueAt(Engine engine, ITarget target, Unit unit,
                     DescribedType described, nuint at, int depth)
{
    switch (described.Tag)
    {
        case TagBaseType:
            return FormatBaseType(target, described, at);

        case TagPointerType:
        {
            nuint pointer = 0u;
            if (!ReadWord(target, at, &pointer))
                return "<unreadable>";
            if (pointer == 0u)
                return "null";
            if (!PointsAtAnObject(unit, described))
                return "0x" + FormatHexadecimal((ulong)pointer);
            return FormatObject(target, described, pointer);
        }

        case TagEnumerationType:
            return FormatEnumeration(target, unit, described, at);

        case TagStructureType:
        case TagClassType:
            // A value of class type is reached through a pointer everywhere in
            // this language, so an aggregate here is a `struct` laid out in
            // place -- or a variant, which is a struct with a tag.
            return FormatStructure(engine, target, unit, described, at, depth);

        default:
        {
            if (described.Size != 0u && described.Size <= 8u)
                return FormatBaseType(target, described, at);
            return "<" + described.Name + ">";
        }
    }
}

/// A struct laid out in place, member by member -- or the live case, when the
/// struct is a variant.
String FormatStructure(Engine engine, ITarget target, Unit unit,
                       DescribedType described, nuint at, int depth)
{
    var definition = described.Definition;
    if (definition == null)
        return described.Name + " at 0x" + FormatHexadecimal((ulong)at);

    if (depth >= WatchDepthLimit)
        return "{...}";

    var members = ChildrenOf(unit, (Die)definition);

    var live = LiveCaseOf(target, unit, members, at);
    if (live != null)
        return FormatCase(engine, target, unit, members, (VariantCase)live, at,
                          depth);

    return FormatMembers(engine, target, unit, members, at, depth, "");
}

/// Which case of a variant is in the storage, by name.
public class VariantCase
{
    public String Name;

    public VariantCase(String name)
    {
        Name = name;
    }
}

/// The live case of a variant, or null when this is an ordinary struct.
///
/// A variant is a struct whose first member is called `tag` and is typed as an
/// enumeration -- which is how the compiler describes one, and how the k-th
/// member stops being mistaken for tag k: DWARF gets a member only for a case
/// that carries a payload.
VariantCase? LiveCaseOf(ITarget target, Unit unit, List<Die> members, nuint at)
{
    if (members.IsEmpty)
        return null;

    var first = members[0u];
    if (first.Tag != TagMember || first.Name != "tag")
        return null;

    var numbering = TypeEntryOf(unit, first);
    if (numbering == null || ((Die)numbering).Tag != TagEnumerationType)
        return null;

    var counted = (Die)numbering;
    nuint size = (nuint)counted.NumberOf(AtByteSize, 1u);
    ulong raw = 0u;
    if (!ReadNumber(target, at + (nuint)first.NumberOf(AtDataMemberLoc, 0u),
                    size, &raw))
        return null;

    var cases = ChildrenOf(unit, counted);
    for (nuint i = 0u; i < cases.Count; i++)
    {
        if (cases[i].Tag == TagEnumerator
            && cases[i].NumberOf(AtConstValue, 0u) == raw)
            return new VariantCase(cases[i].Name);
    }

    // A tag no case claims is a variant that was never assigned, or storage
    // being read as something it is not. Naming the number is the honest
    // answer to both.
    return new VariantCase("tag " + Standard.Text.FromInteger((long)raw));
}

/// The live case, and its payload if it has one.
String FormatCase(Engine engine, ITarget target, Unit unit, List<Die> members,
                  VariantCase live, nuint at, int depth)
{
    for (nuint i = 1u; i < members.Count; i++)
    {
        var one = members[i];
        if (one.Tag != TagMember || one.Name != live.Name)
            continue;

        var described = DescribeType(unit, one);
        nuint where = at + (nuint)one.NumberOf(AtDataMemberLoc, 0u);
        return live.Name + " "
             + FormatValueAt(engine, target, unit, described, where, depth);
    }

    // No member of that name: the case carries nothing, which is most of them.
    return live.Name;
}

/// `{ X = 1, Y = 2 }`, for however many members are worth showing.
String FormatMembers(Engine engine, ITarget target, Unit unit,
                     List<Die> members, nuint at, int depth, String skip)
{
    var made = new StringBuilder();
    made.Append("{ ");

    nuint shown = 0u;
    for (nuint i = 0u; i < members.Count; i++)
    {
        var one = members[i];
        if (one.Tag != TagMember || one.Name == skip)
            continue;

        if (shown == MembersShown)
        {
            made.Append(", ...");
            break;
        }
        if (shown != 0u)
            made.Append(", ");
        shown++;

        made.Append(one.Name);
        made.Append(" = ");
        made.Append(FormatMember(engine, target, unit, one, at, depth));
    }

    if (shown == 0u)
        return "{ }";

    made.Append(" }");
    return made.ToText();
}

/// One member of an aggregate, at its own offset.
String FormatMember(Engine engine, ITarget target, Unit unit, Die member,
                    nuint at, int depth)
{
    var described = DescribeType(unit, member);

    ulong bits = 0u;
    if (ReadBitField(target, member, described, at, &bits))
    {
        return IsSignedEncoding(described.Encoding)
             ? Standard.Text.FromInteger(SignExtendedFrom(bits, BitsOf(member)))
             : Standard.Text.FromInteger((long)bits);
    }

    nuint where = at + (nuint)member.NumberOf(AtDataMemberLoc, 0u);
    return FormatValueAt(engine, target, unit, described, where, depth + 1);
}

/// A run of bits inside the word it shares, when that is what a member is.
///
/// Answers false for an ordinary member, which is most of them. A bit field is
/// `DW_AT_bit_size` bits beginning `DW_AT_data_bit_offset` bits into the
/// structure -- an absolute offset, so nothing here needs the member's byte
/// offset, which a bit field does not carry.
public bool ReadBitField(ITarget target, Die member, DescribedType described,
                         nuint at, ulong* value)
{
    nuint width = BitsOf(member);
    if (width == 0u || width > 64u)
        return false;

    nuint start = (nuint)member.NumberOf(AtDataBitOffset, 0u);

    // The eight bytes the field begins in. A field the compiler emits never
    // straddles the unit it was given, so eight from there always hold it.
    nuint word = (start / 64u) * 8u;
    nuint shift = start - word * 8u;
    if (shift + width > 64u)
        return false;

    ulong raw = 0u;
    if (!ReadNumber(target, at + word, 8u, &raw))
        return false;

    ulong mask = width == 64u ? ~0u : (1u << (int)width) - 1u;
    *value = (raw >> (int)shift) & mask;
    return true;
}

/// How many bits a member is, or zero when it is a whole one.
public nuint BitsOf(Die member) => (nuint)member.NumberOf(AtBitSize, 0u);

/// Sign-extends a value read in `width` bits.
long SignExtendedFrom(ulong raw, nuint width)
{
    if (width >= 64u)
        return (long)raw;
    int spare = (int)(64u - width);
    return ((long)(raw << spare)) >> spare;
}

/// Whether a base type's bytes are a signed number.
public bool IsSignedEncoding(ulong encoding)
    => encoding == EncodingSigned || encoding == EncodingSignedChar;

String FormatBaseType(ITarget target, DescribedType described, nuint at)
{
    nuint size = described.Size != 0u ? described.Size : 8u;
    if (size > 8u)
        size = 8u;

    ulong raw = 0u;
    if (!ReadNumber(target, at, size, &raw))
        return "<unreadable>";

    switch (described.Encoding)
    {
        case EncodingBoolean:
            return raw != 0u ? "true" : "false";

        case EncodingSigned:
        case EncodingSignedChar:
            return Standard.Text.FromInteger(SignExtended(raw, size));

        case EncodingFloat:
            return FormatFloat(raw, size);

        default:
            return Standard.Text.FromInteger((long)raw);
    }
}

/// Sign-extends a value read in `size` bytes.
///
/// Without it a negative `int` read into eight bytes is four billion.
long SignExtended(ulong raw, nuint size) => SignExtendedFrom(raw, size * 8u);

/// The bits of an IEEE value, as the number they are.
///
/// The bytes are read as an integer and reinterpreted, which is the only way
/// round: a `double` cannot be loaded out of a `byte[]` without going through
/// something the size of one.
String FormatFloat(ulong raw, nuint size)
{
    if (size == 4u)
    {
        uint narrow = (uint)raw;
        return Standard.Text.FromDouble((double)(*(float*)&narrow));
    }
    return Standard.Text.FromDouble(*(double*)&raw);
}

/// Up to eight bytes out of the target, little-endian.
bool ReadNumber(ITarget target, nuint at, nuint size, ulong* value)
{
    if (size == 0u || size > 8u)
        return false;

    byte[] bytes = new byte[8];
    if (!target.ReadMemory(at, bytes, size))
        return false;

    ulong raw = 0u;
    for (nuint i = 0u; i < size; i++)
        raw = raw | ((ulong)bytes[i] << (int)(i * 8u));

    *value = raw;
    return true;
}

String FormatEnumeration(ITarget target, Unit unit, DescribedType described,
                         nuint at)
{
    nuint size = described.Size != 0u ? described.Size : 4u;
    ulong raw = 0u;
    if (!ReadNumber(target, at, size, &raw))
        return "<unreadable>";

    var definition = described.Definition;
    if (definition != null)
    {
        var children = ChildrenOf(unit, (Die)definition);
        for (nuint i = 0u; i < children.Count; i++)
        {
            var one = children[i];
            if (one.Tag == TagEnumerator && one.NumberOf(AtConstValue, 0u) == raw)
                return one.Name + " (" + Standard.Text.FromInteger((long)raw) + ")";
        }
    }
    return Standard.Text.FromInteger((long)raw);
}

/// A reference, read through its object header.
String FormatObject(ITarget target, DescribedType described, nuint pointer)
{
    String declared = described.Name;

    // Strip the pointer's own spelling: DWARF describes a class reference as a
    // pointer to the class, and the name carried here is the pointee's.
    nuint strong = 0u;
    nuint typeInfo = 0u;
    if (!ReadWord(target, pointer + HeaderStrongOffset, &strong)
        || !ReadWord(target, pointer + HeaderTypeOffset, &typeInfo))
        return declared + " at 0x" + FormatHexadecimal((ulong)pointer);

    // A `String` or an array: length at 24, elements at 32.
    //
    // The name is the qualified one -- `Standard.Text.String`, not `String` --
    // because that is what the program called the type and what DWARF carries.
    bool isString = IsStringNamed(declared);
    if (isString || EndsWithBrackets(declared))
    {
        nuint length = 0u;
        if (ReadWord(target, pointer + LengthOffset, &length))
        {
            if (isString)
                return FormatString(target, pointer, length);
            // The type has already been named by the caller, so this says the
            // one thing DWARF could not: how long it actually is.
            return Standard.Text.FromInteger((long)length) + " elements at 0x"
                 + FormatHexadecimal((ulong)(pointer + ElementsOffset));
        }
    }

    String runtime = TypeNameOf(target, typeInfo);

    var made = new StringBuilder();
    made.Append(declared);
    if (runtime.ByteLength() != 0u && runtime != declared)
    {
        made.Append(" (");
        made.Append(runtime);
        made.Append(")");
    }
    made.Append(" at 0x");
    made.Append(FormatHexadecimal((ulong)pointer));

    // **A strong count of zero is a dead object.** A weak reference keeps the
    // header readable after the object has gone, so a pointer that still looks
    // fine may name something nothing owns -- which `docs/abi.md` warns reads
    // as a live object to anything that does not check.
    if (strong == 0u)
        made.Append(" (dead)");
    return made.ToText();
}

/// The `name` of an `SlTypeInfo`, which is what lets a base-class variable show
/// its real type without any reflection metadata.
String TypeNameOf(ITarget target, nuint typeInfo)
{
    if (typeInfo == 0u)
        return "";
    nuint namePointer = 0u;
    if (!ReadWord(target, typeInfo + TypeInfoNameOffset, &namePointer))
        return "";
    return ReadCString(target, namePointer, 128u);
}

String FormatString(ITarget target, nuint pointer, nuint length)
{
    if (length > 256u)
        length = 256u;
    byte[] bytes = new byte[length + 1u];
    if (length != 0u && !target.ReadMemory(pointer + ElementsOffset, bytes, length))
        return "<unreadable string>";

    var made = new StringBuilder();
    made.AppendByte((byte)34);
    for (nuint i = 0u; i < length; i++)
    {
        byte here = bytes[i];
        made.AppendByte(here < (byte)32 ? (byte)46 : here);
    }
    made.AppendByte((byte)34);
    return made.ToText();
}

String ReadCString(ITarget target, nuint at, nuint most)
{
    var made = new StringBuilder();
    byte[] one = new byte[1];
    for (nuint i = 0u; i < most; i++)
    {
        if (!target.ReadMemory(at + i, one, 1u))
            break;
        if (one[0u] == 0)
            break;
        made.AppendByte(one[0u]);
    }
    return made.ToText();
}

bool ReadWord(ITarget target, nuint at, nuint* into)
{
    byte[] cell = new byte[8];
    if (!target.ReadMemory(at, cell, 8u))
        return false;
    *into = (nuint)LittleEndianWord(cell);
    return true;
}

/// Whether a type name is the standard library's `String`.
///
/// By its qualified name and by the bare one, because a program may name it
/// either way and the debugger should recognise both.
bool IsStringNamed(String name)
    => name == "String" || name == "Standard.Text.String";

bool EndsWithBrackets(String name)
{
    nuint length = name.ByteLength();
    return length >= 2u && name.ByteAt(length - 2u) == (byte)91
        && name.ByteAt(length - 1u) == (byte)93;
}

/// Every parameter and local in scope at an address, in declaration order.
///
/// The subprogram's own children, then the children of each `DW_TAG_lexical_block`
/// whose code covers the address. A block that does not cover it declares
/// nothing that exists yet.
///
/// **A block whose range cannot be read is entered anyway.** At `-O2` a block
/// may be described by `DW_AT_ranges` rather than a low and a high address, and
/// showing a variable that might not be in scope is a smaller fault than hiding
/// one that is.
public List<Die> VariablesInScopeAt(Unit unit, Die owner, nuint linked)
{
    var found = new List<Die>();
    GatherVariables(found, unit, owner, linked, 0);
    return found;
}

void GatherVariables(List<Die> into, Unit unit, Die owner, nuint linked,
                     int depth)
{
    // A tree this deep is a corrupt file rather than a nested block.
    if (depth > 32)
        return;

    var children = ChildrenOf(unit, owner);
    for (nuint i = 0u; i < children.Count; i++)
    {
        var one = children[i];

        if (one.Tag == TagFormalParameter || one.Tag == TagVariable)
        {
            into.Add(one);
            continue;
        }

        if (one.Tag != TagLexicalBlock)
            continue;

        nuint from = 0u;
        nuint to = 0u;
        if (one.Range(&from, &to) && (linked < from || linked >= to))
            continue;

        GatherVariables(into, unit, one, linked, depth + 1);
    }
}

/// The entries directly under one, in the order the file had them.
///
/// The flat list with parent indices is what makes this a scan rather than a
/// recursion: a child is any later entry whose parent is this one, and the run
/// ends when something shallower appears.
public List<Die> ChildrenOf(Unit unit, Die parent)
{
    var found = new List<Die>();

    int index = -1;
    for (nuint i = 0u; i < unit.Dies.Count; i++)
    {
        if (unit.Dies[i].Offset == parent.Offset)
        {
            index = (int)i;
            break;
        }
    }
    if (index < 0)
        return found;

    for (nuint i = (nuint)index + 1u; i < unit.Dies.Count; i++)
    {
        var die = unit.Dies[i];
        if (die.Depth <= parent.Depth)
            break;
        if (die.Parent == index)
            found.Add(die);
    }
    return found;
}
