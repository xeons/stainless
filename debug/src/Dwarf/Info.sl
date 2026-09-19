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

// `.debug_info`: the units, and the entries in them.
//
// **A flat list with parent indices, not a tree of objects.** The entries
// arrive in depth-first order with a null entry closing each run of children,
// so the flat form is what the file already is and the parent link is one
// integer. It also makes the thing a debugger does most -- walk every
// subprogram, or every child of one entry -- a loop over a range rather than a
// recursion, and it makes an entry addressable by the section offset that
// `DW_FORM_ref4` gives, which a tree of objects would need a second index for.
//
// **Strings and addresses are resolved as they are read.** A DWARF 5 unit
// stores most strings as an index into `.debug_str_offsets` and most addresses
// as an index into `.debug_addr`, each biased by a base the unit itself
// declares -- so an attribute's value is meaningless without three other
// sections and the unit's own header. Resolving late would mean every consumer
// carrying that apparatus; resolving here means a caller sees a string and an
// address.
module Debugger;

import Standard.Collections;
import Standard.Text;

/// One attribute of one entry, with its value already resolved.
public class Attribute
{
    public uint At;
    public uint Form;

    /// The numeric value: a constant, an address, a section offset, or the
    /// section-relative offset of another entry for the reference forms.
    public ulong Value;

    /// The text, for the string forms. Empty otherwise.
    public String Text;

    /// The bytes, for `DW_FORM_exprloc` and the block forms -- a location
    /// expression is not a number and pretending it is one loses it.
    public byte[] Block;

    public Attribute(uint at, uint form)
    {
        At = at;
        Form = form;
        Value = 0u;
        Text = "";
        Block = new byte[0u];
    }

    public bool IsText => Text.ByteLength() != 0u;
}

/// One debugging information entry.
public class Die
{
    /// Where this entry starts, counted from the beginning of `.debug_info`.
    /// What a reference form resolves to.
    public nuint Offset;

    public uint Tag;
    public bool HasChildren;

    /// The index of the entry this one hangs under, or -1 for a unit's root.
    public int Parent;

    /// How deep it sits, with a unit root at zero. Kept because printing an
    /// entry tree is the way this reader is checked against `llvm-dwarfdump`,
    /// and recomputing it per line is a walk up the parents.
    public int Depth;

    public List<Attribute> Attributes;

    public Die(nuint offset, uint tag, bool children, int parent, int depth)
    {
        Offset = offset;
        Tag = tag;
        HasChildren = children;
        Parent = parent;
        Depth = depth;
        Attributes = new List<Attribute>();
    }

    public Attribute? Find(uint at)
    {
        for (nuint i = 0u; i < Attributes.Count; i++)
        {
            if (Attributes[i].At == at)
                return Attributes[i];
        }
        return null;
    }

    public String TextOf(uint at)
    {
        var found = Find(at);
        return found == null ? "" : ((Attribute)found).Text;
    }

    public ulong NumberOf(uint at, ulong fallback)
    {
        var found = Find(at);
        return found == null ? fallback : ((Attribute)found).Value;
    }

    public bool Has(uint at) => Find(at) != null;

    /// The name a person would recognise: the source name, falling back to the
    /// linkage name, because a compiler-generated entry may carry only one.
    public String Name
    {
        get
        {
            String plain = TextOf(AtName);
            return plain.ByteLength() != 0u ? plain : TextOf(AtLinkageName);
        }
    }

    /// Where this entry's code begins and ends, when it has any.
    ///
    /// **`DW_AT_high_pc` is a length, not an address**, whenever it is a
    /// constant form rather than an address form -- which is what every
    /// compiler emits now and what this reader has only ever seen. Treating it
    /// as an address gives a function that appears to end near zero, and every
    /// address lookup then misses.
    public bool Range(nuint* low, nuint* high)
    {
        var start = Find(AtLowPc);
        if (start == null)
            return false;
        var end = Find(AtHighPc);
        if (end == null)
            return false;

        nuint from = (nuint)((Attribute)start).Value;
        var span = (Attribute)end;
        nuint to = span.Form == FormAddr
                 ? (nuint)span.Value
                 : from + (nuint)span.Value;

        *low = from;
        *high = to;
        return from != to;
    }
}

/// One compilation unit and everything in it.
public class Unit
{
    /// Where the unit's header starts in `.debug_info`. A `DW_FORM_ref4` is
    /// relative to this.
    public nuint Offset;

    public uint Version;
    public nuint AddressSize;
    public nuint OffsetSize;

    /// The unit's own root entry, and then everything under it in the order the
    /// file had them.
    public List<Die> Dies;

    public Unit(nuint offset)
    {
        Offset = offset;
        Version = 0u;
        AddressSize = 8u;
        OffsetSize = 4u;
        Dies = new List<Die>();
    }

    public Die? Root => Dies.Count != 0u ? Dies[0u] : null;

    public String Name => Dies.Count != 0u ? Dies[0u].Name : "";
    public String CompDir => Dies.Count != 0u ? Dies[0u].TextOf(AtCompDir) : "";

    /// The entry at a section-relative offset, or null.
    public Die? At(nuint offset)
    {
        for (nuint i = 0u; i < Dies.Count; i++)
        {
            if (Dies[i].Offset == offset)
                return Dies[i];
        }
        return null;
    }
}

/// Everything `.debug_info` holds, with the sections it leans on kept beside it.
public class DwarfInfo
{
    public List<Unit> Units;

    byte[] _info;
    byte[] _abbrev;
    byte[] _str;
    byte[] _lineStr;
    byte[] _strOffsets;
    byte[] _addr;

    /// The line-number section, kept for `Lines.sl` rather than used here.
    public byte[] LineSection;

    public DwarfInfo(Image image)
    {
        Units = new List<Unit>();
        _info = image.BytesOf(".debug_info");
        _abbrev = image.BytesOf(".debug_abbrev");
        _str = image.BytesOf(".debug_str");
        _lineStr = image.BytesOf(".debug_line_str");
        _strOffsets = image.BytesOf(".debug_str_offsets");
        _addr = image.BytesOf(".debug_addr");
        LineSection = image.BytesOf(".debug_line");
    }

    public bool IsEmpty => _info.Length == 0u;

    /// Reads every unit. Answers a message when a unit could not be read, which
    /// names the offset so that a person can go and look.
    public String Read()
    {
        nuint at = 0u;
        while (at + 11u < _info.Length)
        {
            nuint next = 0u;
            String bad = ReadUnit(at, &next);
            if (bad.ByteLength() != 0u)
                return bad;
            if (next <= at)
                return "a unit at 0x" + Hexadecimal((ulong)at) + " did not advance";
            at = next;
        }
        return "";
    }

    String ReadUnit(nuint at, nuint* next)
    {
        var reader = new Cursor(_info, at);
        var unit = new Unit(at);

        // A length of 0xffffffff introduces the 64-bit format, where the real
        // length and every section offset in the unit are eight bytes wide.
        ulong length = (ulong)reader.U32();
        unit.OffsetSize = 4u;
        if (length == 0xFFFFFFFFu)
        {
            length = reader.U64();
            unit.OffsetSize = 8u;
        }
        *next = reader.Offset + (nuint)length;

        unit.Version = (uint)reader.U16();

        nuint abbrevAt = 0u;
        if (unit.Version >= 5u)
        {
            // **DWARF 5 reordered this header.** The unit type and the address
            // size come before the abbreviation offset, where DWARF 4 put the
            // offset first. Reading a version 5 unit with the version 4 layout
            // gives an abbreviation offset built from a type byte and half an
            // address size, which finds a table that parses and means nothing.
            reader.U8();                                  // unit_type
            unit.AddressSize = (nuint)reader.U8();
            abbrevAt = (nuint)(unit.OffsetSize == 8u ? reader.U64()
                                                     : (ulong)reader.U32());
        }
        else
        {
            abbrevAt = (nuint)(unit.OffsetSize == 8u ? reader.U64()
                                                     : (ulong)reader.U32());
            unit.AddressSize = (nuint)reader.U8();
        }

        if (unit.AddressSize == 0u || unit.AddressSize > 8u)
            return "a unit at 0x" + Hexadecimal((ulong)at)
                 + " claims an address size of "
                 + Standard.Text.FromInteger((long)unit.AddressSize);

        var abbrevs = AbbrevTable.Read(_abbrev, abbrevAt);

        // The bases a unit's indexed forms are measured from, and a genuine
        // chicken and egg: they are attributes of the root entry, and the root
        // entry's *own* name is a string index that needs them.
        //
        // **Defaulting them and fixing up afterwards does not work**, which is
        // how this was first written and what the second unit of a
        // multi-unit binary immediately exposed. The header-sized defaults --
        // eight, and sixteen for 64-bit DWARF -- are correct only for the unit
        // whose contribution comes first; every later unit's strings resolved
        // against the first one's table and came back with the first one's
        // names. Seventeen units all called `fixture.sl` is what that looks
        // like, and it looks plausible.
        //
        // So the root is read twice: once to find the bases, skipping
        // everything else, and then properly. The first pass is a few dozen
        // bytes and happens once per unit.
        UnitBases bases;
        bases.StrOffsets = unit.OffsetSize == 8u ? 16u : 8u;
        bases.Addr = unit.OffsetSize == 8u ? 16u : 8u;
        PeekBases(_info, reader.Offset, abbrevs, unit, &bases);

        int parent = -1;
        int depth = 0;
        var open = new List<int>();

        while (reader.Offset < *next && !reader.Overran)
        {
            nuint dieAt = reader.Offset;
            ulong code = reader.Leb();

            if (code == 0u)
            {
                // A null entry closes the innermost run of children.
                if (open.Count == 0u)
                    break;
                parent = open[open.Count - 1u];
                open.RemoveAt(open.Count - 1u);
                parent = parent >= 0 && (nuint)parent < unit.Dies.Count
                       ? unit.Dies[(nuint)parent].Parent
                       : -1;
                depth = depth > 0 ? depth - 1 : 0;
                continue;
            }

            var abbrev = abbrevs.Find(code);
            if (abbrev == null)
                return "an entry at 0x" + Hexadecimal((ulong)dieAt)
                     + " uses abbreviation " + Standard.Text.FromInteger((long)code)
                     + ", which its table does not define";

            var shape = (Abbrev)abbrev;
            var die = new Die(dieAt, shape.Tag, shape.HasChildren, parent, depth);

            for (nuint i = 0u; i < shape.Attributes.Count; i++)
            {
                var wanted = shape.Attributes[i];
                var made = ReadAttribute(reader, unit, wanted, &bases);
                if (made == null)
                    return "an entry at 0x" + Hexadecimal((ulong)dieAt)
                         + " uses form 0x" + Hexadecimal((ulong)wanted.Form)
                         + ", which this reader cannot skip";
                die.Attributes.Add((Attribute)made);
            }

            int index = (int)unit.Dies.Count;
            unit.Dies.Add(die);

            if (shape.HasChildren)
            {
                open.Add(index);
                parent = index;
                depth++;
            }
        }

        Units.Add(unit);
        return "";
    }

    /// Finds a unit's `DW_AT_str_offsets_base` and `DW_AT_addr_base` without
    /// resolving anything, so that the root entry's own indexed attributes can
    /// be read with them already in hand.
    ///
    /// Every attribute is stepped over with the same `SkipForm` the real read
    /// uses, so a form this engine cannot handle stops both passes at the same
    /// place rather than only one of them.
    void PeekBases(byte[] section, nuint at, AbbrevTable abbrevs, Unit unit,
                   UnitBases* bases)
    {
        var reader = new Cursor(section, at);
        ulong code = reader.Leb();
        if (code == 0u)
            return;

        var abbrev = abbrevs.Find(code);
        if (abbrev == null)
            return;
        var shape = (Abbrev)abbrev;
        if (shape.Tag != TagCompileUnit)
            return;

        for (nuint i = 0u; i < shape.Attributes.Count; i++)
        {
            var wanted = shape.Attributes[i];

            // Both bases are always `DW_FORM_sec_offset`; anything else with
            // those numbers is not what this is looking for.
            if (wanted.Form == FormSecOffset
                && (wanted.At == AtStrOffsetsBase || wanted.At == AtAddrBase))
            {
                ulong value = ReadOffset(reader, unit.OffsetSize);
                if (wanted.At == AtStrOffsetsBase)
                    bases->StrOffsets = (nuint)value;
                else
                    bases->Addr = (nuint)value;
                continue;
            }

            if (!SkipForm(reader, wanted.Form, unit.AddressSize, unit.OffsetSize))
                return;
        }
    }

    Attribute? ReadAttribute(Cursor reader, Unit unit, AbbrevAttribute wanted,
                             UnitBases* bases)
    {
        var made = new Attribute(wanted.At, wanted.Form);
        uint form = wanted.Form;

        // An indirect form names its real one in the data.
        if (form == FormIndirect)
        {
            form = (uint)reader.Leb();
            if (form == FormIndirect)
                return null;
        }

        nuint offsetSize = unit.OffsetSize;

        switch (form)
        {
            // ------------------------------------------------ no bytes read

            case FormImplicitConst:
                made.Value = (ulong)wanted.Implicit;
                return made;

            case FormFlagPresent:
                made.Value = 1u;
                return made;

            // ------------------------------------------------------ strings

            case FormString:
                made.Text = reader.CString();
                return made;

            case FormStrp:
            {
                nuint offset = (nuint)ReadOffset(reader, offsetSize);
                made.Value = (ulong)offset;
                made.Text = offset < _str.Length ? TextAt(_str, offset) : "";
                return made;
            }

            case FormLineStrp:
            {
                nuint offset = (nuint)ReadOffset(reader, offsetSize);
                made.Value = (ulong)offset;
                made.Text = offset < _lineStr.Length ? TextAt(_lineStr, offset) : "";
                return made;
            }

            // An index into this unit's slice of `.debug_str_offsets`, and from
            // there into `.debug_str`.
            case FormStrx:
            case FormStrx1:
            case FormStrx2:
            case FormStrx3:
            case FormStrx4:
            {
                ulong index = form == FormStrx ? reader.Leb()
                            : ReadFixed(reader, WidthOfStrx(form));
                made.Value = index;
                made.Text = StringAt(index, bases->StrOffsets, offsetSize);
                return made;
            }

            // ---------------------------------------------------- addresses

            case FormAddr:
                made.Value = ReadFixed(reader, unit.AddressSize);
                return made;

            case FormAddrx:
            case FormAddrx1:
            case FormAddrx2:
            case FormAddrx3:
            case FormAddrx4:
            {
                ulong index = form == FormAddrx ? reader.Leb()
                            : ReadFixed(reader, WidthOfAddrx(form));
                made.Value = AddressAt(index, bases->Addr, unit.AddressSize);
                return made;
            }

            // ------------------------------------------------------ numbers

            case FormData1:
            case FormFlag:
                made.Value = (ulong)reader.U8();
                return made;

            case FormData2:
                made.Value = (ulong)reader.U16();
                return made;

            case FormData4:
                made.Value = (ulong)reader.U32();
                return made;

            case FormData8:
                made.Value = reader.U64();
                return made;

            // Sixteen bytes is an MD5 and never a number; kept whole.
            case FormData16:
                made.Block = reader.Take(16u);
                return made;

            case FormUdata:
                made.Value = reader.Leb();
                return made;

            case FormSdata:
                made.Value = (ulong)reader.SLeb();
                return made;

            case FormSecOffset:
                made.Value = ReadOffset(reader, offsetSize);
                return made;

            case FormLoclistx:
            case FormRnglistx:
                made.Value = reader.Leb();
                return made;

            // --------------------------------------------------- references

            // Relative to the unit, and stored absolute -- a consumer that has
            // to remember which unit an offset came from eventually forgets.
            case FormRef1:
            case FormRef2:
            case FormRef4:
            case FormRef8:
            case FormRefUdata:
            {
                ulong relative = form == FormRefUdata ? reader.Leb()
                               : ReadFixed(reader, WidthOfRef(form));
                made.Value = (ulong)unit.Offset + relative;
                return made;
            }

            case FormRefAddr:
            case FormStrpSup:
                made.Value = ReadOffset(reader, offsetSize);
                return made;

            case FormRefSig8:
            case FormRefSup8:
                made.Value = reader.U64();
                return made;

            case FormRefSup4:
                made.Value = (ulong)reader.U32();
                return made;

            // -------------------------------------------------------- blocks

            case FormExprloc:
            case FormBlock:
            {
                nuint size = (nuint)reader.Leb();
                made.Block = reader.Take(size);
                return made;
            }

            case FormBlock1:
            {
                nuint size = (nuint)reader.U8();
                made.Block = reader.Take(size);
                return made;
            }

            case FormBlock2:
            {
                nuint size = (nuint)reader.U16();
                made.Block = reader.Take(size);
                return made;
            }

            case FormBlock4:
            {
                nuint size = (nuint)reader.U32();
                made.Block = reader.Take(size);
                return made;
            }

            // Anything left is a form this reader has no value for but may
            // still be able to step over, which is enough to keep the rest of
            // the unit.
            default:
                if (SkipForm(reader, form, unit.AddressSize, offsetSize))
                    return made;
                return null;
        }
    }

    /// The string at an index, through `.debug_str_offsets` and then
    /// `.debug_str`. Two indirections, either of which can be out of range in a
    /// binary that has been through a linker that did not understand them.
    String StringAt(ulong index, nuint start, nuint offsetSize)
    {
        nuint at = start + (nuint)index * offsetSize;
        if (at + offsetSize > _strOffsets.Length)
            return "";
        var reader = new Cursor(_strOffsets, at);
        nuint offset = (nuint)ReadOffset(reader, offsetSize);
        return offset < _str.Length ? TextAt(_str, offset) : "";
    }

    ulong AddressAt(ulong index, nuint start, nuint addressSize)
    {
        nuint at = start + (nuint)index * addressSize;
        if (at + addressSize > _addr.Length)
            return 0u;
        var reader = new Cursor(_addr, at);
        return ReadFixed(reader, addressSize);
    }
}

/// The offsets a unit's indexed forms are measured from.
///
/// A struct passed by pointer rather than two out-parameters, because they are
/// read together, change together, and are meaningless apart.
struct UnitBases
{
    public nuint StrOffsets;
    public nuint Addr;
}

ulong ReadOffset(Cursor reader, nuint size)
    => size == 8u ? reader.U64() : (ulong)reader.U32();

/// An unsigned number of an arbitrary width from one to eight bytes, which the
/// three-byte forms are the only reason for.
ulong ReadFixed(Cursor reader, nuint size)
{
    ulong answer = 0u;
    for (nuint i = 0u; i < size; i++)
        answer = answer | ((ulong)reader.U8() << (int)(i * 8u));
    return answer;
}

nuint WidthOfStrx(uint form)
{
    switch (form)
    {
        case FormStrx1: return 1u;
        case FormStrx2: return 2u;
        case FormStrx3: return 3u;
        default: return 4u;
    }
}

nuint WidthOfAddrx(uint form)
{
    switch (form)
    {
        case FormAddrx1: return 1u;
        case FormAddrx2: return 2u;
        case FormAddrx3: return 3u;
        default: return 4u;
    }
}

nuint WidthOfRef(uint form)
{
    switch (form)
    {
        case FormRef1: return 1u;
        case FormRef2: return 2u;
        case FormRef4: return 4u;
        default: return 8u;
    }
}
