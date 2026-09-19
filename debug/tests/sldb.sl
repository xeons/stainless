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

// The console debugger, which for now only reads.
//
// **This exists so the engine can be tested without a window**, which is the
// lesson `forms/` paid for twice: a self test that drives a GUI proves the
// model and nothing else. Everything the IDE will eventually show comes from
// here first, and every question this answers is one a scripted test can ask.
//
//   sldb sections <binary>     what the container holds
//   sldb units <binary>        the compilation units, and what each covers
//   sldb dies <binary> [name]  the entry tree, for diffing against dwarfdump
//   sldb --selftest            the checks that need no binary
module Sldb;

import Standard.Collections;
import Standard.Console;
import Standard.Env;
import Standard.Text;
import Debugger;

/// Hexadecimal, with a fixed width, because a column of addresses that do not
/// line up is a column nobody reads.
String Hex(nuint value, int digits)
{
    var made = new StringBuilder();
    for (int shift = (digits - 1) * 4; shift >= 0; shift = shift - 4)
    {
        nuint nibble = (value >> shift) & 0xFu;
        byte here = nibble < 10u
                  ? (byte)((nuint)48 + nibble)
                  : (byte)((nuint)97 + nibble - 10u);
        made.AppendByte(here);
    }
    return made.ToText();
}

String Number(nuint value) => Standard.Text.FromInteger((long)value);

/// Pads on the right, for a column of names.
String Wide(String text, nuint width)
{
    var made = new StringBuilder();
    made.Append(text);
    for (nuint i = text.ByteLength(); i < width; i++)
        made.AppendByte((byte)32);
    return made.ToText();
}

int Sections(String path)
{
    var read = Image.FromFile(path);
    if (!read.Ok)
    {
        Console.WriteLine("sldb: " + read.Error);
        return 1;
    }

    var image = read.Value;
    Console.WriteLine(image.Path);
    Console.WriteLine("  format    " + (image.Kind == ImageKind.Pe ? "PE" : "ELF")
                      + (image.Is64 ? " 64-bit" : " 32-bit"));
    Console.WriteLine("  base      0x" + Hex(image.PreferredBase, 16));
    Console.WriteLine("  entry     0x" + Hex(image.Entry, 16));
    Console.WriteLine("  dwarf     " + (image.HasDwarf ? "yes" : "no"));
    Console.WriteLine("");
    Console.WriteLine("  " + Wide("name", 20) + Wide("address", 20) + "size");

    var sections = image.Sections;
    for (nuint i = 0u; i < sections.Count; i++)
    {
        var section = sections[i];
        Console.WriteLine("  " + Wide(section.Name, 20)
                          + Wide("0x" + Hex(section.Address, 16), 20)
                          + Number(section.Size));
    }
    return 0;
}

// ------------------------------------------------------------------ self test

/// Reports one check and carries the verdict along, which is how the Forms
/// samples do it: a module-level flag is refused (SL0575 territory -- only
/// `const` lives at module scope), and threading it reads better than a class
/// that exists to hold one bool.
bool Check(bool sofar, String what, bool ok)
{
    Console.WriteLine((ok ? "  ok   " : "  FAIL ") + what);
    return sofar && ok;
}

/// The parts that need no binary on disk: the number reading everything else
/// is built out of.
int SelfTest()
{
    // LEB128, unsigned. 0xE5 0x8E 0x26 is the canonical 624485 from the DWARF
    // standard's own worked example, which is why it is the one used here.
    bool ok = true;

    byte[] example = [0xE5, 0x8E, 0x26];
    var one = new Cursor(example);
    ok = Check(ok, "an unsigned LEB128 reads the standard's own example",
               one.Leb() == 624485u);

    // And signed: 0xC0 0xBB 0x78 is -123456, the matching example.
    byte[] negative = [0xC0, 0xBB, 0x78];
    var two = new Cursor(negative);
    ok = Check(ok, "a signed LEB128 reads its example too", two.SLeb() == -123456);

    // A single byte with the sign bit set is negative, which is the case a
    // reader that forgets to smear the sign gets wrong and nothing notices
    // until an fbreg offset points the wrong way up the stack.
    byte[] minusOne = [0x7F];
    var three = new Cursor(minusOne);
    ok = Check(ok, "a one-byte signed LEB128 is sign-extended", three.SLeb() == -1);

    byte[] plus63 = [0x3F];
    var four = new Cursor(plus63);
    ok = Check(ok, "and a positive one is not", four.SLeb() == 63);

    // Little-endian, which everything in both containers is.
    byte[] word = [0x78, 0x56, 0x34, 0x12, 0, 0, 0, 0];
    var five = new Cursor(word);
    ok = Check(ok, "a u32 is little-endian", five.U32() == 0x12345678u);

    byte[] wide = [1, 0, 0, 0, 0, 0, 0, 0x80];
    var six = new Cursor(wide);
    ok = Check(ok, "a u64 uses its top byte", six.U64() == 0x8000000000000001u);

    // **Running off the end answers rather than aborts**, which is the whole
    // contract: the input is a file somebody else wrote.
    byte[] tooShort = [1, 2];
    var seven = new Cursor(tooShort);
    seven.U32();
    ok = Check(ok, "a read past the end is refused, not fatal", seven.Overran);

    byte[] terminated = [0x41, 0x42, 0, 0x43];
    var eight = new Cursor(terminated);
    ok = Check(ok, "a C string stops at its NUL", eight.CString() == "AB");
    ok = Check(ok, "and leaves the cursor after it", eight.Offset == 3u);

    // An unterminated string is still answered, because the bytes are probably
    // the name that was meant.
    byte[] unterminated = [0x41, 0x42];
    var nine = new Cursor(unterminated);
    ok = Check(ok, "an unterminated string is answered anyway", nine.CString() == "AB");
    ok = Check(ok, "and says it ran over", nine.Overran);

    // A run of continuation bytes must stop rather than walk the file.
    byte[] endless = [0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,
                      0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80];
    var ten = new Cursor(endless);
    ten.Leb();
    ok = Check(ok, "a LEB128 that never ends stops at ten bytes", ten.Offset == 10u);

    // **Every named form must be a skippable form.** A form this engine can
    // name but not step over is one that loses its place in the entry stream
    // and keeps producing entries that look right -- so the constants are
    // checked against the function rather than believed beside it.
    uint[] forms = KnownForms();
    bool everyForm = true;
    for (nuint i = 0u; i < forms.Length; i++)
    {
        // Zeros make every length-prefixed form empty and every LEB zero,
        // which is the shortest legal encoding of each. `DW_FORM_indirect`
        // names its real form in the data, so it gets one that is not zero.
        byte[] room = [0x0B, 0, 0, 0, 0, 0, 0, 0,
                       0, 0, 0, 0, 0, 0, 0, 0,
                       0, 0, 0, 0, 0, 0, 0, 0];
        var over = new Cursor(room);
        if (!SkipForm(over, forms[i], 8u, 4u))
        {
            Console.WriteLine("       no skip rule for form 0x"
                              + Hexadecimal((ulong)forms[i]));
            everyForm = false;
        }
    }
    ok = Check(ok, "every form this engine names can also be skipped", everyForm);

    // And the other half of the contract: a form it does not know is *refused*,
    // not skipped by zero bytes. Answering true there would keep the reader
    // running over an entry it has already lost.
    byte[] spare = [0, 0, 0, 0, 0, 0, 0, 0];
    var unknown = new Cursor(spare);
    ok = Check(ok, "a form it has never heard of is refused rather than guessed",
               !SkipForm(unknown, 0x7Fu, 8u, 4u));

    // The header structures, against the sizes their formats fix. Cheap, and
    // the only cover the 32-bit layouts have until a 32-bit binary is built
    // here -- the box this is developed on has no multilib.
    String sizes = HeaderSizeProblem();
    ok = Check(ok, "every header struct is the size its format says",
               sizes.IsEmpty);
    if (!sizes.IsEmpty)
        Console.WriteLine("       " + sizes);

    Console.WriteLine(ok ? "all checks passed" : "FAILED");
    return ok ? 0 : 1;
}

/// Reads the binary and its DWARF, or prints why not.
DwarfInfo? Load(String path)
{
    var read = Image.FromFile(path);
    if (!read.Ok)
    {
        Console.WriteLine("sldb: " + read.Error);
        return null;
    }

    var info = new DwarfInfo(read.Value);
    if (info.IsEmpty)
    {
        Console.WriteLine("sldb: " + path + " carries no DWARF");
        Console.WriteLine("      on Windows a -g build writes CodeView to a .pdb;");
        Console.WriteLine("      see docs/dwarf.md for how to force DWARF instead");
        return null;
    }

    String bad = info.Read();
    if (bad.ByteLength() != 0u)
    {
        Console.WriteLine("sldb: " + bad);
        return null;
    }
    return info;
}

int Units(String path)
{
    var info = Load(path);
    if (info == null)
        return 1;

    var units = ((DwarfInfo)info).Units;
    Console.WriteLine(Number(units.Count) + " unit(s)");
    for (nuint i = 0u; i < units.Count; i++)
    {
        var unit = units[i];
        Console.WriteLine("");
        Console.WriteLine("  0x" + Hexadecimal((ulong)unit.Offset) + "  "
                          + unit.Name);
        Console.WriteLine("    version " + Number((nuint)unit.Version)
                          + ", " + Number(unit.AddressSize) + "-byte addresses, "
                          + Number(unit.Dies.Count) + " entries");
        var root = unit.Root;
        if (root != null)
        {
            String dir = ((Die)root).TextOf(AtCompDir);
            if (dir.ByteLength() != 0u)
                Console.WriteLine("    " + dir);
        }
    }
    return 0;
}

/// The entry tree, indented, in the order the file has it.
///
/// **Shaped so it can be diffed against `llvm-dwarfdump --debug-info`**, which
/// is the only way this reader was ever going to be trusted: the offsets and
/// the tag names are the tool's, so a disagreement shows up as a line rather
/// than as a feeling.
int Dies(String path, String only)
{
    var info = Load(path);
    if (info == null)
        return 1;

    var units = ((DwarfInfo)info).Units;
    for (nuint u = 0u; u < units.Count; u++)
    {
        var unit = units[u];
        for (nuint i = 0u; i < unit.Dies.Count; i++)
        {
            var die = unit.Dies[i];
            if (only.ByteLength() != 0u && die.Name != only)
                continue;

            var line = new StringBuilder();
            line.Append("0x");
            line.Append(Hexadecimal((ulong)die.Offset));
            line.Append(": ");
            for (int pad = 0; pad < die.Depth; pad++)
                line.Append("  ");
            line.Append(TagName(die.Tag));
            Console.WriteLine(line.ToText());

            for (nuint a = 0u; a < die.Attributes.Count; a++)
            {
                var one = die.Attributes[a];
                var text = new StringBuilder();
                text.Append("      ");
                for (int pad = 0; pad < die.Depth; pad++)
                    text.Append("  ");
                text.Append(AttributeName(one.At));
                text.Append("\t");
                text.Append(Describe(one));
                Console.WriteLine(text.ToText());
            }
        }
    }
    return 0;
}

/// One attribute's value, in the shape `llvm-dwarfdump` prints it so the two
/// can be compared without translating.
String Describe(Attribute one)
{
    if (one.IsText)
        return "(\"" + one.Text + "\")";
    if (one.Block.Length != 0u)
        return "(<0x" + Hexadecimal((ulong)one.Block.Length) + "> bytes)";
    return "(0x" + Hexadecimal(one.Value) + ")";
}

int Usage()
{
    Console.WriteLine("sldb -- the Stainless debugger");
    Console.WriteLine("");
    Console.WriteLine("  sldb sections <binary>     what the container holds");
    Console.WriteLine("  sldb units <binary>        the compilation units");
    Console.WriteLine("  sldb dies <binary> [name]  the entry tree");
    Console.WriteLine("  sldb --selftest            the checks that need no binary");
    return 2;
}

int Main()
{
    var args = Standard.Env.Arguments();
    if (args.Length == 0u)
        return Usage();

    if (args[0u] == "--selftest")
        return SelfTest();

    if (args[0u] == "sections" && args.Length >= 2u)
        return Sections(args[1u]);

    if (args[0u] == "units" && args.Length >= 2u)
        return Units(args[1u]);

    if (args[0u] == "dies" && args.Length >= 2u)
        return Dies(args[1u], args.Length >= 3u ? args[2u] : "");

    return Usage();
}
