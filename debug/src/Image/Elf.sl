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

// The ELF section and program headers.
//
// Easier than the PE in the one respect that matters: a section name is an
// offset into a string section from the start, so there is no eight-byte limit
// and no special case.
//
// **Both tables are read, and they answer different questions.** The section
// headers say what a region is called, and only the names make `.debug_info`
// findable; the program headers say what the loader maps, and only those give
// the address a runtime slide is measured from. Reading one and guessing the
// other is a mistake that costs nothing until a live process exists -- see
// `LowestLoadAddress`, which is where it was made.
//
// A stripped binary can have its section headers removed entirely and still
// run perfectly, so a missing section table is "nothing to debug with" rather
// than "corrupt".
//
// **Six structs rather than one reader with a width flag.** The 32- and 64-bit
// layouts are not the same shape at two sizes: a program header puts its flags
// second in the 64-bit form and second-to-last in the 32-bit one, so a reader
// that widened its fields and kept its order would be silently wrong about
// every segment on one of the two. Written out, the difference is visible; as
// a conditional skip it was a comment nobody would have checked.
module Debugger;

import Standard.Collections;
import Standard.Text;

struct Elf64Header
{
    public byte[16] Ident;
    public ushort   Type;
    public ushort   Machine;
    public uint     Version;
    public ulong    Entry;
    public ulong    ProgramHeaders;
    public ulong    SectionHeaders;
    public uint     Flags;
    public ushort   HeaderSize;
    public ushort   ProgramHeaderSize;
    public ushort   ProgramHeaderCount;
    public ushort   SectionHeaderSize;
    public ushort   SectionHeaderCount;
    public ushort   NameSectionIndex;
}

struct Elf32Header
{
    public byte[16] Ident;
    public ushort   Type;
    public ushort   Machine;
    public uint     Version;
    public uint     Entry;
    public uint     ProgramHeaders;
    public uint     SectionHeaders;
    public uint     Flags;
    public ushort   HeaderSize;
    public ushort   ProgramHeaderSize;
    public ushort   ProgramHeaderCount;
    public ushort   SectionHeaderSize;
    public ushort   SectionHeaderCount;
    public ushort   NameSectionIndex;
}

struct Elf64SectionHeader
{
    public uint  Name;
    public uint  Type;
    public ulong Flags;
    public ulong Address;
    public ulong Offset;
    public ulong Size;
    public uint  Link;
    public uint  Info;
    public ulong AddressAlign;
    public ulong EntrySize;
}

struct Elf32SectionHeader
{
    public uint Name;
    public uint Type;
    public uint Flags;
    public uint Address;
    public uint Offset;
    public uint Size;
    public uint Link;
    public uint Info;
    public uint AddressAlign;
    public uint EntrySize;
}

/// The 64-bit segment header. **`Flags` is the second field here.**
struct Elf64ProgramHeader
{
    public uint  Type;
    public uint  Flags;
    public ulong Offset;
    public ulong VirtualAddress;
    public ulong PhysicalAddress;
    public ulong FileSize;
    public ulong MemorySize;
    public ulong Align;
}

/// And the 32-bit one, where **`Flags` is second to last**. This is the whole
/// reason there are two of these rather than one with wider fields.
struct Elf32ProgramHeader
{
    public uint Type;
    public uint Offset;
    public uint VirtualAddress;
    public uint PhysicalAddress;
    public uint FileSize;
    public uint MemorySize;
    public uint Flags;
    public uint Align;
}

const byte ElfClass32 = 1;
const byte ElfClass64 = 2;

/// `SHT_NOBITS`: a section that occupies memory and no file. `.bss`.
const uint ShtNoBits = 8u;

/// `PT_LOAD`: a segment the loader maps. The only kind that decides where the
/// image goes.
const uint PtLoad = 1u;

Result<Image, String> ReadElf(String path, byte[] data)
{
    var made = new Image(path, ImageKind.Elf);

    if (data.Length < 16u)
        return Fail(path + ": too short to hold an ELF identifier");

    made.Is64 = data[4u] == ElfClass64;
    if (data[4u] != ElfClass32 && data[4u] != ElfClass64)
        return Fail(path + ": the ELF class byte is neither 32- nor 64-bit");

    // The two headers are read into the same locals, so everything below this
    // is written once.
    nuint segmentsAt = 0u;
    nuint sectionsAt = 0u;
    nuint segmentSize = 0u;
    nuint segmentCount = 0u;
    nuint headerSize = 0u;
    nuint sectionCount = 0u;
    nuint nameSection = 0u;

    if (made.Is64)
    {
        if (!BytesRemainAt(data, 0u, (nuint)sizeof(Elf64Header)))
            return Fail(path + ": the ELF header is truncated");
        var header = (Elf64Header*)&data[0u];
        made.Entry = (nuint)header->Entry;
        segmentsAt = (nuint)header->ProgramHeaders;
        sectionsAt = (nuint)header->SectionHeaders;
        segmentSize = (nuint)header->ProgramHeaderSize;
        segmentCount = (nuint)header->ProgramHeaderCount;
        headerSize = (nuint)header->SectionHeaderSize;
        sectionCount = (nuint)header->SectionHeaderCount;
        nameSection = (nuint)header->NameSectionIndex;
    }
    else
    {
        if (!BytesRemainAt(data, 0u, (nuint)sizeof(Elf32Header)))
            return Fail(path + ": the ELF header is truncated");
        var header = (Elf32Header*)&data[0u];
        made.Entry = (nuint)header->Entry;
        segmentsAt = (nuint)header->ProgramHeaders;
        sectionsAt = (nuint)header->SectionHeaders;
        segmentSize = (nuint)header->ProgramHeaderSize;
        segmentCount = (nuint)header->ProgramHeaderCount;
        headerSize = (nuint)header->SectionHeaderSize;
        sectionCount = (nuint)header->SectionHeaderCount;
        nameSection = (nuint)header->NameSectionIndex;
    }

    if (sectionsAt == 0u || sectionCount == 0u)
        return Fail(path + ": no section headers -- the binary has been stripped");
    if (headerSize == 0u)
        headerSize = made.Is64 ? (nuint)sizeof(Elf64SectionHeader)
                               : (nuint)sizeof(Elf32SectionHeader);

    // The names live in a section of their own, which has to be located before
    // any other section can be given one.
    byte[] names = new byte[0u];
    if (nameSection < sectionCount)
    {
        nuint at = 0u;
        nuint size = 0u;
        if (FindSectionSpan(data, made.Is64, sectionsAt + nameSection * headerSize,
                        &at, &size) && BytesRemainAt(data, at, size))
        {
            var body = new Cursor(data, at);
            names = body.Take(size);
        }
    }

    for (nuint i = 0u; i < sectionCount; i++)
    {
        nuint headerAt = sectionsAt + i * headerSize;
        nuint nameAt = 0u;
        uint kind = 0u;
        nuint address = 0u;
        nuint at = 0u;
        nuint size = 0u;

        if (made.Is64)
        {
            if (!BytesRemainAt(data, headerAt, (nuint)sizeof(Elf64SectionHeader)))
                break;
            var header = (Elf64SectionHeader*)&data[headerAt];
            nameAt = (nuint)header->Name;
            kind = header->Type;
            address = (nuint)header->Address;
            at = (nuint)header->Offset;
            size = (nuint)header->Size;
        }
        else
        {
            if (!BytesRemainAt(data, headerAt, (nuint)sizeof(Elf32SectionHeader)))
                break;
            var header = (Elf32SectionHeader*)&data[headerAt];
            nameAt = (nuint)header->Name;
            kind = header->Type;
            address = (nuint)header->Address;
            at = (nuint)header->Offset;
            size = (nuint)header->Size;
        }

        String name = nameAt < names.Length ? ReadCStringAt(names, nameAt) : "";

        byte[] bytes = new byte[0u];
        if (kind != ShtNoBits && size != 0u && BytesRemainAt(data, at, size))
        {
            var body = new Cursor(data, at);
            bytes = body.Take(size);
        }

        made.Add(new Section(name, address, bytes));
    }

    made.PreferredBase = LowestLoadAddress(data, made.Is64, segmentsAt, segmentSize,
                                  segmentCount);

    if (made.Sections.Count == 0u)
        return Fail(path + ": an ELF whose section headers read as empty");
    return Ok(made);
}

/// Where one section header's bytes are, for the one lookup that happens before
/// the loop that would otherwise have done it.
bool FindSectionSpan(byte[] data, bool is64, nuint headerAt, nuint* at, nuint* size)
{
    if (is64)
    {
        if (!BytesRemainAt(data, headerAt, (nuint)sizeof(Elf64SectionHeader)))
            return false;
        var header = (Elf64SectionHeader*)&data[headerAt];
        *at = (nuint)header->Offset;
        *size = (nuint)header->Size;
        return true;
    }

    if (!BytesRemainAt(data, headerAt, (nuint)sizeof(Elf32SectionHeader)))
        return false;
    var header = (Elf32SectionHeader*)&data[headerAt];
    *at = (nuint)header->Offset;
    *size = (nuint)header->Size;
    return true;
}

/// The lowest virtual address the loader is asked to map, which is what a
/// runtime slide is measured against.
///
/// **From the program headers, not from the sections**, and the difference is
/// not academic. The lowest *section* address in a position-independent
/// executable is wherever `.note.gnu.build-id` landed -- 0x350 in the binary
/// this was first tested against -- while the first `PT_LOAD` starts at zero
/// and zero is what the loader adds its slide to. Taking the section address
/// would put every translated address out by exactly that much, and only once
/// a live process existed to notice.
///
/// Zero when there are no program headers at all, which is what a relocatable
/// object has: nothing is loaded, so nothing slides.
nuint LowestLoadAddress(byte[] data, bool is64, nuint at, nuint size, nuint count)
{
    if (at == 0u || count == 0u)
        return 0u;
    if (size == 0u)
        size = is64 ? (nuint)sizeof(Elf64ProgramHeader)
                    : (nuint)sizeof(Elf32ProgramHeader);

    nuint lowest = 0u;
    bool any = false;

    for (nuint i = 0u; i < count; i++)
    {
        nuint headerAt = at + i * size;
        uint kind = 0u;
        nuint address = 0u;

        if (is64)
        {
            if (!BytesRemainAt(data, headerAt, (nuint)sizeof(Elf64ProgramHeader)))
                break;
            var header = (Elf64ProgramHeader*)&data[headerAt];
            kind = header->Type;
            address = (nuint)header->VirtualAddress;
        }
        else
        {
            if (!BytesRemainAt(data, headerAt, (nuint)sizeof(Elf32ProgramHeader)))
                break;
            var header = (Elf32ProgramHeader*)&data[headerAt];
            kind = header->Type;
            address = (nuint)header->VirtualAddress;
        }

        if (kind != PtLoad)
            continue;
        if (!any || address < lowest)
        {
            lowest = address;
            any = true;
        }
    }
    return any ? lowest : 0u;
}
