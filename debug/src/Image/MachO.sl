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

// The Mach-O load commands, and the dSYM beside an executable.
//
// **The DWARF is not in the executable.** Apple's linker leaves it in the
// object files and `dsymutil` gathers it into `<program>.dSYM`, which the
// compiler runs for every `-g` build. The dSYM is itself a Mach-O holding only
// the `__DWARF` segment, already relocated to the executable's link addresses,
// so its sections are added to the executable's image and nothing else changes.
// `LC_UUID` is what says the two belong together.
//
// **A section name is sixteen bytes**, so `__debug_str_offsets` is written
// `__debug_str_offs`. Names are mapped to the ELF spelling the readers look up.
module Debugger;

import Standard.Collections;
import Standard.File;
import Standard.IO;
import Standard.Path;
import Standard.Text;

/// `mach_header_64`.
struct MachHeader64
{
    public uint Magic;
    public int CpuType;
    public int CpuSubtype;
    public uint FileType;
    public uint CommandCount;
    public uint CommandsSize;
    public uint Flags;
    public uint Reserved;
}

/// `load_command`: the two words every command starts with.
struct MachLoadCommand
{
    public uint Command;
    public uint CommandSize;
}

/// `segment_command_64`. Its `section_64` headers follow it directly.
struct MachSegmentCommand64
{
    public uint Command;
    public uint CommandSize;
    public byte[16] SegmentName;
    public ulong VirtualAddress;
    public ulong VirtualSize;
    public ulong FileOffset;
    public ulong FileSize;
    public int MaximumProtection;
    public int InitialProtection;
    public uint SectionCount;
    public uint Flags;
}

/// `section_64`. Both names are sixteen bytes with no terminator when full.
struct MachSection64
{
    public byte[16] SectionName;
    public byte[16] SegmentName;
    public ulong Address;
    public ulong Size;
    public uint Offset;
    public uint Align;
    public uint RelocationOffset;
    public uint RelocationCount;
    public uint Flags;
    public uint Reserved1;
    public uint Reserved2;
    public uint Reserved3;
}

/// `entry_point_command`, which `LC_MAIN` is.
struct MachEntryPointCommand
{
    public uint Command;
    public uint CommandSize;
    public ulong EntryOffset;
    public ulong StackSize;
}

/// `MH_MAGIC_64`, little-endian.
const uint MachMagic64 = 0xFEEDFACFu;

/// `LC_SEGMENT_64`, `LC_UUID` and `LC_MAIN`.
const uint MachCommandSegment64 = 0x19u;
const uint MachCommandUuid = 0x1Bu;
const uint MachCommandMain = 0x80000028u;

/// The low byte of a section's flags is its type. Three types have no bytes
/// in the file.
const uint MachSectionTypeMask = 0xFFu;
const uint MachSectionZeroFill = 0x01u;
const uint MachSectionGigabyteZeroFill = 0x0Cu;
const uint MachSectionThreadLocalZeroFill = 0x12u;

/// The bytes of `LC_UUID`.
const nuint MachUuidSize = 16u;

Result<Image, String> ReadMachO(String path, byte[] data)
{
    var made = new Image(path, ImageKind.MachO);

    if (!BytesRemainAt(data, 0u, (nuint)sizeof(MachHeader64)))
        return Fail(path + ": the Mach-O header is truncated");
    var header = (MachHeader64*)&data[0u];

    nuint at = (nuint)sizeof(MachHeader64);
    nuint end = at + (nuint)header->CommandsSize;
    if (!BytesRemainAt(data, at, (nuint)header->CommandsSize))
        return Fail(path + ": the Mach-O load commands run past the end of the file");

    bool sawText = false;
    nuint entryOffset = 0u;

    for (uint i = 0u; i < header->CommandCount; i++)
    {
        if (at + (nuint)sizeof(MachLoadCommand) > end)
            break;
        var command = (MachLoadCommand*)&data[at];
        nuint size = (nuint)command->CommandSize;
        if (size < (nuint)sizeof(MachLoadCommand) || at + size > end)
            return Fail(path + ": a Mach-O load command has an impossible size");

        switch (command->Command)
        {
            case MachCommandSegment64:
            {
                if (size < (nuint)sizeof(MachSegmentCommand64))
                    return Fail(path + ": a segment command is truncated");
                var segment = (MachSegmentCommand64*)&data[at];

                // The base a slide is measured from. `__PAGEZERO` sits below it
                // and is never mapped with anything in it.
                if (FixedNameAt(&segment->SegmentName[0], 16u) == "__TEXT")
                {
                    made.PreferredBase = (nuint)segment->VirtualAddress;
                    sawText = true;
                }

                nuint headersAt = at + (nuint)sizeof(MachSegmentCommand64);
                nuint stride = (nuint)sizeof(MachSection64);
                nuint room = size - (nuint)sizeof(MachSegmentCommand64);
                if ((nuint)segment->SectionCount * stride > room)
                    return Fail(path + ": a segment claims more sections than it holds");

                for (uint s = 0u; s < segment->SectionCount; s++)
                {
                    var one = (MachSection64*)&data[headersAt + (nuint)s * stride];
                    made.Add(ReadMachSection(data, one));
                }
                break;
            }

            case MachCommandUuid:
            {
                if (size >= (nuint)sizeof(MachLoadCommand) + MachUuidSize)
                {
                    var body = new Cursor(data, at + (nuint)sizeof(MachLoadCommand));
                    made.Uuid = body.Take(MachUuidSize);
                }
                break;
            }

            case MachCommandMain:
            {
                if (size >= (nuint)sizeof(MachEntryPointCommand))
                    entryOffset = (nuint)((MachEntryPointCommand*)&data[at])->EntryOffset;
                break;
            }
        }

        at += size;
    }

    // `entryoff` is a file offset, and `__TEXT` maps the file from offset zero.
    if (sawText && entryOffset != 0u)
        made.Entry = made.PreferredBase + entryOffset;

    if (made.Sections.Count == 0u)
        return Fail(path + ": a Mach-O with no sections");
    return Ok(made);
}

/// One `section_64`, its name spelled the way the readers look it up.
Section ReadMachSection(byte[] data, MachSection64* header)
{
    String name = MapMachSectionName(FixedNameAt(&header->SectionName[0], 16u));

    nuint size = (nuint)header->Size;
    nuint at = (nuint)header->Offset;
    uint kind = header->Flags & MachSectionTypeMask;
    bool zeroFill = kind == MachSectionZeroFill || kind == MachSectionGigabyteZeroFill
                 || kind == MachSectionThreadLocalZeroFill;

    byte[] bytes = new byte[0u];
    if (!zeroFill && at != 0u && size != 0u && BytesRemainAt(data, at, size))
    {
        var body = new Cursor(data, at);
        bytes = body.Take(size);
    }
    return new Section(name, (nuint)header->Address, bytes);
}

/// `__debug_info` as `.debug_info`, and the one name sixteen bytes cut short.
public String MapMachSectionName(String raw)
{
    if (raw == "__debug_str_offs")
        return ".debug_str_offsets";
    if (raw.ByteLength() > 2u && raw.StartsWith("__"))
        return "." + raw.Substring(2u, raw.ByteLength() - 2u);
    return raw;
}

/// A name of at most `width` bytes, which has no terminator when it is full.
String FixedNameAt(byte* raw, nuint width)
{
    var made = new StringBuilder();
    for (nuint i = 0u; i < width; i++)
    {
        if (raw[i] == 0)
            break;
        made.AppendByte(raw[i]);
    }
    return made.ToText();
}

/// Where `dsymutil` puts the DWARF of the program at `path`.
public String DsymPathFor(String path)
    => path + ".dSYM/Contents/Resources/DWARF/" + Standard.Path.GetFileName(path);

/// Adds the DWARF of the dSYM beside a Mach-O executable, when there is one.
///
/// No dSYM is not an error: the image is a program built without `-g`. A dSYM
/// whose `LC_UUID` differs is, because its lines describe some other build.
Result<Image, String> AttachDsym(Image image)
{
    String companion = DsymPathFor(image.Path);
    if (!Standard.File.Exists(companion))
        return Ok(image);

    var read = Standard.File.ReadAllBytes(companion);
    if (!read.Ok)
        return Fail("cannot read " + companion + ": " + Standard.IO.DescribeIOError(read.Error));

    byte[] data = read.Value;
    if (data.Length < 4u || *(uint*)&data[0u] != MachMagic64)
        return Fail(companion + " is not a 64-bit Mach-O");

    var parsed = ReadMachO(companion, data);
    if (!parsed.Ok)
        return Fail(parsed.Error);

    var dsym = parsed.Value;
    if (!AreSameUuid(image.Uuid, dsym.Uuid))
        return Fail(companion + " is from another build of " + image.Path
                    + " (their LC_UUIDs differ); rebuild with -g");

    var sections = dsym.Sections;
    for (nuint i = 0u; i < sections.Count; i++)
    {
        if (sections[i].Name.StartsWith(".debug_"))
            image.Add(sections[i]);
    }
    return Ok(image);
}

/// Whether two `LC_UUID`s are present and equal.
public bool AreSameUuid(byte[] left, byte[] right)
{
    if (left.Length != MachUuidSize || right.Length != MachUuidSize)
        return false;
    for (nuint i = 0u; i < MachUuidSize; i++)
    {
        if (left[i] != right[i])
            return false;
    }
    return true;
}
