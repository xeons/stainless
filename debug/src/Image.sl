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

// An executable on disk, reduced to the two things a debugger wants from one:
// where its sections are and what is in them.
//
// **From the file, never from the target's memory.** The DWARF is read off
// disk, which is what `fpdebug` does and what lets every one of these readers
// be tested with no process in existence -- the whole of the reading half of
// this engine runs on a build machine that could not launch the binary if it
// tried. The only thing the live process is needed for is the *slide*: where
// the loader actually put the image, against where it was linked to go.
//
// There is no `IImage` interface and no pair of implementations, which is a
// departure from how `forms/` does this. The reason is that a container is not
// a seam a program stands on -- nothing here is ever asked to be polymorphic
// over PE and ELF, because both are read once, at the start, into the same
// three fields. A function that sniffs the magic and fills a class is the whole
// of what two interfaces would have bought.
module Debugger;

import Standard.Collections;
import Standard.File;
import Standard.IO;
import Standard.Text;

/// One section: what it is called, where it was linked to live, and its bytes.
public class Section
{
    public String Name;

    /// The address this section was linked at, which for a PE includes the
    /// preferred image base and for an ELF is whatever the linker chose -- a
    /// non-relocatable one gets a real address and a PIE gets an offset from
    /// zero. Either way, the runtime address is this plus the image's slide.
    public nuint Address;

    /// Its contents. Empty for a section with no bytes in the file, `.bss`
    /// being the one everybody meets.
    public byte[] Data;

    public Section(String name, nuint address, byte[] data)
    {
        Name = name;
        Address = address;
        Data = data;
    }

    public nuint Size => Data.Length;

    /// Whether an address falls inside this section, as it was linked.
    public bool Covers(nuint address)
        => address >= Address && address < Address + Data.Length;
}

/// What kind of container it turned out to be. Worth reporting rather than
/// hiding, because "this is an ELF" is a useful thing for a tool to print when
/// somebody points it at the wrong file.
public enum ImageKind { Unknown, Pe, Elf }

public class Image
{
    public String Path;
    public ImageKind Kind;

    /// Whether addresses in this image are 64 bits. Every target this compiler
    /// has is little-endian, but not all of them are 64-bit -- the 32-bit x86
    /// cases in `tests/cases` are real -- so this one does have to be carried.
    public bool Is64;

    /// Where the image asked to be loaded. A PE says so outright; an ELF's is
    /// the lowest address of its loadable sections, which is zero for a PIE.
    /// Subtracting this from a runtime address gives the offset a section
    /// address can be compared against.
    public nuint PreferredBase;

    /// The entry point, as linked.
    public nuint Entry;

    List<Section> _sections;

    public Image(String path, ImageKind kind)
    {
        Path = path;
        Kind = kind;
        Is64 = true;
        PreferredBase = 0u;
        Entry = 0u;
        _sections = new List<Section>();
    }

    public List<Section> Sections => _sections;

    public void Add(Section section) => _sections.Add(section);

    /// The section of that name, or null. Names are compared exactly: a PE's
    /// DWARF sections carry the same names an ELF's do, which is the whole
    /// reason one DWARF reader can sit over both containers.
    public Section? Find(String name)
    {
        for (nuint i = 0u; i < _sections.Count; i++)
        {
            if (_sections[i].Name == name)
                return _sections[i];
        }
        return null;
    }

    /// The bytes of a section, or an empty array when there is none.
    ///
    /// **An absent DWARF section is not an error**, which is why this does not
    /// answer a `Result`. A binary with no `.debug_loclists` is an ordinary
    /// binary that happened not to need one, and every reader of an optional
    /// section would otherwise have to say so at every call.
    public byte[] BytesOf(String name)
    {
        var found = Find(name);
        if (found == null)
            return new byte[0u];
        return ((Section)found).Data;
    }

    /// Whether this image carries DWARF at all.
    public bool HasDwarf => Find(".debug_info") != null;

    /// Reads an executable, deciding what it is from its first bytes.
    ///
    /// The error says what was wrong in words a person can act on, because the
    /// usual cause of one is a path that points at the wrong thing.
    public static Result<Image, String> FromFile(String path)
    {
        var read = Standard.File.ReadAllBytes(path);
        if (!read.Ok)
            return Fail("cannot read " + path + ": "
                    + Standard.IO.Describe(read.Error));

        byte[] data = read.Value;
        if (data.Length < 4u)
            return Fail(path + " is too short to be an executable");

        // "MZ" then, much further in, "PE\0\0"; or "\x7fELF" outright.
        if (data[0u] == (byte)0x4D && data[1u] == (byte)0x5A)
            return ReadPe(path, data);
        if (data[0u] == (byte)0x7F && data[1u] == (byte)0x45
            && data[2u] == (byte)0x4C && data[3u] == (byte)0x46)
            return ReadElf(path, data);

        return Fail(path + " is neither a PE nor an ELF");
    }
}

/// Whether every header structure is the size its format says it is, and the
/// first one that is not.
///
/// **This is the test the 32-bit readers would otherwise not have.** Laying a
/// struct over bytes from a file is only as good as the declaration, and a
/// mistyped field or a padding byte nobody expected shifts everything after it
/// silently -- the reader does not fail, it reports plausible nonsense. Every
/// one of these numbers is fixed by the PE or ELF specification and by nothing
/// about this machine, so the check needs no binary, runs on both platforms,
/// and covers the 32-bit layouts that no binary in this tree exercises yet.
///
/// Answers "" when they are all right, because a name and a number is what a
/// caller wants to print and a bool is not.
public String HeaderSizeProblem()
{
    String bad = Wrong("CoffHeader", (nuint)sizeof(CoffHeader), 20u);
    if (!bad.IsEmpty) return bad;

    bad = Wrong("PeOptional64", (nuint)sizeof(PeOptional64), 32u);
    if (!bad.IsEmpty) return bad;

    bad = Wrong("PeOptional32", (nuint)sizeof(PeOptional32), 32u);
    if (!bad.IsEmpty) return bad;

    bad = Wrong("PeSectionHeader", (nuint)sizeof(PeSectionHeader), 40u);
    if (!bad.IsEmpty) return bad;

    bad = Wrong("Elf64Header", (nuint)sizeof(Elf64Header), 64u);
    if (!bad.IsEmpty) return bad;

    bad = Wrong("Elf32Header", (nuint)sizeof(Elf32Header), 52u);
    if (!bad.IsEmpty) return bad;

    bad = Wrong("Elf64SectionHeader", (nuint)sizeof(Elf64SectionHeader), 64u);
    if (!bad.IsEmpty) return bad;

    bad = Wrong("Elf32SectionHeader", (nuint)sizeof(Elf32SectionHeader), 40u);
    if (!bad.IsEmpty) return bad;

    bad = Wrong("Elf64ProgramHeader", (nuint)sizeof(Elf64ProgramHeader), 56u);
    if (!bad.IsEmpty) return bad;

    return Wrong("Elf32ProgramHeader", (nuint)sizeof(Elf32ProgramHeader), 32u);
}

String Wrong(String name, nuint got, nuint wanted)
{
    if (got == wanted)
        return "";
    return name + " is " + Standard.Text.FromInteger((long)got)
         + " bytes, and the format says " + Standard.Text.FromInteger((long)wanted);
}
