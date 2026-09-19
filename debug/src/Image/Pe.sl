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

// The COFF section table, in a file on disk.
//
// **The headers are declared as structs and read by casting, not field by
// field**, because this language has C's layout and there is no reason to
// spell out in code what the format already says declaratively. A
// `Skip(4u) // TimeDateStamp` is a comment that can disagree with its own
// arithmetic; a field called `TimeDateStamp` cannot. The one thing a cast still
// owes the caller is a bounds check, since the input is a file somebody else
// wrote -- `BytesRemainAt` is that, once per header rather than once per field.
//
// The byte cursor next door is for the variable-length half of this job: DWARF
// is LEB128 and abbrev-driven attributes whose widths are decided at run time,
// and no struct describes any of it.
//
// **The whole of the difficulty in the format is eight bytes.** A PE section
// header has room for an eight-character name and every DWARF section is
// called something longer -- `.debug_line` is eleven, and it and
// `.debug_line_str` would both truncate to `.debug_l` and become
// indistinguishable. lld-link writes the long ones into a string table instead
// and leaves `/NNN` in the header, a decimal offset into it.
// `docs/dwarf.md` has the measurement; this is the code that acts on it.
//
// The trap in that, found by reading the bytes rather than a tool's rendering
// of them: **lld writes `NumberOfSymbols` as zero** while still pointing
// `PointerToSymbolTable` at a string table that exists. The table begins where
// the symbols would have ended, so the arithmetic is right either way -- but a
// reader that takes "no symbols" to mean "no string table" and skips the lookup
// finds nothing and silently loses every DWARF section.
module Debugger;

import Standard.Collections;
import Standard.Text;

/// `IMAGE_FILE_HEADER`, which follows the four-byte PE signature.
struct CoffHeader
{
    public ushort Machine;
    public ushort SectionCount;
    public uint   TimeDateStamp;
    public uint   SymbolTable;
    public uint   SymbolCount;
    public ushort OptionalSize;
    public ushort Characteristics;
}

/// The front of `IMAGE_OPTIONAL_HEADER64`, as far as the image base.
///
/// Only as far as it is read: the rest is data directories and sizes a
/// debugger has no use for, and declaring fields nobody reads is how a
/// structure acquires an offset that is wrong and never noticed.
struct PeOptional64
{
    public ushort Magic;
    public byte   MajorLinkerVersion;
    public byte   MinorLinkerVersion;
    public uint   SizeOfCode;
    public uint   SizeOfInitializedData;
    public uint   SizeOfUninitializedData;
    public uint   AddressOfEntryPoint;
    public uint   BaseOfCode;
    public ulong  ImageBase;
}

/// And the 32-bit one, which is not the same structure narrowed: it has a
/// `BaseOfData` that the 64-bit layout does not, so the image base sits in a
/// different place rather than merely a different width.
struct PeOptional32
{
    public ushort Magic;
    public byte   MajorLinkerVersion;
    public byte   MinorLinkerVersion;
    public uint   SizeOfCode;
    public uint   SizeOfInitializedData;
    public uint   SizeOfUninitializedData;
    public uint   AddressOfEntryPoint;
    public uint   BaseOfCode;
    public uint   BaseOfData;
    public uint   ImageBase;
}

/// `IMAGE_SECTION_HEADER`. Forty bytes, and the name is eight raw bytes rather
/// than a string -- it may have no terminator, and it may not be a name at all.
struct PeSectionHeader
{
    public byte[8] Name;
    public uint    VirtualSize;
    public uint    VirtualAddress;
    public uint    SizeOfRawData;
    public uint    PointerToRawData;
    public uint    PointerToRelocations;
    public uint    PointerToLineNumbers;
    public ushort  NumberOfRelocations;
    public ushort  NumberOfLineNumbers;
    public uint    Characteristics;
}

/// `IMAGE_FILE_MACHINE_I386`, the one that decides the pointer width when the
/// optional header is missing or unreadable.
const ushort PeMachineI386 = 0x014Cu;

/// `IMAGE_NT_OPTIONAL_HDR64_MAGIC`, which is what actually says an optional
/// header carries 64-bit addresses -- not the machine, which is a different
/// question with a usually-matching answer.
const ushort PeOptional64Magic = 0x020Bu;

/// One COFF symbol, which is only ever needed for its size: the string table
/// begins where the symbols end.
const nuint PeSymbolSize = 18u;

/// Whether `size` bytes starting at `at` are all inside `data`.
///
/// The second test is not redundant. `at + size` is computed in `nuint` and a
/// corrupt header can name an offset near the top of the range, so the sum
/// wraps and a plain `<= Length` says yes to a read that starts past the end.
bool BytesRemainAt(byte[] data, nuint at, nuint size)
    => at + size >= at && at + size <= data.Length;

Result<Image, String> ReadPe(String path, byte[] data)
{
    var made = new Image(path, ImageKind.Pe);

    // The DOS stub ends with the offset of the real header, at a fixed place
    // that has not moved since 1993.
    if (!BytesRemainAt(data, 0x3Cu, 4u))
        return Fail(path + ": too short to hold a DOS header");
    nuint peAt = (nuint)(*(uint*)&data[0x3Cu]);

    if (!BytesRemainAt(data, peAt, 4u + (nuint)sizeof(CoffHeader)))
        return Fail(path + ": the PE header offset points outside the file");

    var signature = (byte*)&data[peAt];
    if (signature[0] != (byte)0x50 || signature[1] != (byte)0x45
        || signature[2] != 0 || signature[3] != 0)
        return Fail(path + ": no PE signature where the DOS stub said one was");

    var coff = (CoffHeader*)&data[peAt + 4u];
    made.Is64 = coff->Machine != PeMachineI386;

    nuint optionalAt = peAt + 4u + (nuint)sizeof(CoffHeader);
    nuint optionalSize = (nuint)coff->OptionalSize;

    // The optional header is optional in name only for an image; what varies is
    // its length, which the COFF header just gave.
    if (optionalSize >= 2u && BytesRemainAt(data, optionalAt, 2u))
    {
        ushort magic = *(ushort*)&data[optionalAt];
        made.Is64 = magic == PeOptional64Magic;

        if (made.Is64 && BytesRemainAt(data, optionalAt, (nuint)sizeof(PeOptional64)))
        {
            var optional = (PeOptional64*)&data[optionalAt];
            made.PreferredBase = (nuint)optional->ImageBase;
            made.Entry = optional->AddressOfEntryPoint != 0u
                       ? made.PreferredBase + (nuint)optional->AddressOfEntryPoint
                       : 0u;
        }
        else if (!made.Is64 && BytesRemainAt(data, optionalAt, (nuint)sizeof(PeOptional32)))
        {
            var optional = (PeOptional32*)&data[optionalAt];
            made.PreferredBase = (nuint)optional->ImageBase;
            made.Entry = optional->AddressOfEntryPoint != 0u
                       ? made.PreferredBase + (nuint)optional->AddressOfEntryPoint
                       : 0u;
        }
    }

    // Where the long names live. `SymbolCount` is routinely zero in a linked
    // image whose symbols were stripped, and the table is still there.
    nuint strings = coff->SymbolTable != 0u
                  ? (nuint)coff->SymbolTable + (nuint)coff->SymbolCount * PeSymbolSize
                  : 0u;

    nuint at = optionalAt + optionalSize;
    nuint stride = (nuint)sizeof(PeSectionHeader);

    for (nuint i = 0u; i < (nuint)coff->SectionCount; i++)
    {
        if (!BytesRemainAt(data, at + i * stride, stride))
            break;
        var header = (PeSectionHeader*)&data[at + i * stride];

        String name = ResolveSectionName(data, &header->Name[0], strings);

        // **`SizeOfRawData` is rounded up to the file alignment and
        // `VirtualSize` is the truth.** For `.text` the difference is padding
        // nobody executes, but a DWARF section read 476 bytes too long ends in
        // a run of zeros that the reader above it takes seriously: zero is a
        // valid entry in `.debug_addr` and `.debug_str_offsets`, and a unit
        // header of zeros is a unit. Measured against `llvm-objdump -h`, which
        // reports the virtual size -- the two disagreed on every section of the
        // first binary this was pointed at.
        //
        // A virtual size of zero means an object file rather than an image,
        // where the raw size is the only one given.
        nuint rawSize = (nuint)header->SizeOfRawData;
        nuint size = rawSize;
        if (header->VirtualSize != 0u && (nuint)header->VirtualSize < rawSize)
            size = (nuint)header->VirtualSize;

        // A section with no bytes in the file -- `.bss` -- has a raw pointer of
        // zero and is carried with an empty array rather than left out, so that
        // an address inside it still resolves to a name.
        nuint rawAt = (nuint)header->PointerToRawData;
        byte[] bytes = new byte[0u];
        if (rawAt != 0u && size != 0u && BytesRemainAt(data, rawAt, size))
        {
            var body = new Cursor(data, rawAt);
            bytes = body.Take(size);
        }

        made.Add(new Section(name,
                             made.PreferredBase + (nuint)header->VirtualAddress,
                             bytes));
    }

    if (made.Sections.Count == 0u)
        return Fail(path + ": a PE with no sections");
    return Ok(made);
}

/// The eight bytes of a section header's name, resolved.
///
/// Three shapes, and all three occur in one binary this was tested against:
/// a short name with a NUL after it, a name of exactly eight characters with no
/// terminator at all, and `/NNN` pointing into the string table.
String ResolveSectionName(byte[] data, byte* raw, nuint strings)
{
    if (raw[0] == (byte)0x2F && strings != 0u)        // '/'
    {
        // Decimal, and the digits stop at the first non-digit or the eighth
        // byte -- there is no terminator to rely on.
        nuint offset = 0u;
        bool any = false;
        for (nuint i = 1u; i < 8u; i++)
        {
            byte here = raw[i];
            if (here < (byte)0x30 || here > (byte)0x39)
                break;
            offset = offset * 10u + (nuint)(here - (byte)0x30);
            any = true;
        }
        if (any && strings + offset < data.Length)
            return ReadCStringAt(data, strings + offset);
    }

    var made = new StringBuilder();
    for (nuint i = 0u; i < 8u; i++)
    {
        if (raw[i] == 0)
            break;
        made.AppendByte(raw[i]);
    }
    return made.ToText();
}
