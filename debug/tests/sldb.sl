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
//   sldb lines <binary>        the line table, row by row
//   sldb line <binary> f:n     what address a source line begins at
//   sldb addr <binary> 0xNNN   what source line an address came from
//   sldb run <binary> [f:n]    run it, stopping at a line
//   sldb stack <binary> f:n    the call stack where it stops
//   sldb step <binary> f:n [k] step k lines from there, into calls
//   sldb next <binary> f:n [k] the same, over them
//   sldb locals <binary> f:n   the parameters and locals in scope there
//   sldb --selftest            the checks that need no binary
module Sldb;

import Standard.Collections;
import Standard.Console;
import Standard.Env;
import Standard.Text;
import Debugger;

/// FormatHexadecimal, with a fixed width, because a column of addresses that do not
/// line up is a column nobody reads.
String FormatHexPadded(nuint value, int digits)
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

String FormatNumber(nuint value) => Standard.Text.FromInteger((long)value);

/// Pads on the right, for a column of names.
String PadRight(String text, nuint width)
{
    var made = new StringBuilder();
    made.Append(text);
    for (nuint i = text.ByteLength(); i < width; i++)
        made.AppendByte((byte)32);
    return made.ToText();
}

int PrintSections(String path)
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
    Console.WriteLine("  base      0x" + FormatHexPadded(image.PreferredBase, 16));
    Console.WriteLine("  entry     0x" + FormatHexPadded(image.Entry, 16));
    Console.WriteLine("  dwarf     " + (image.HasDwarf ? "yes" : "no"));
    Console.WriteLine("");
    Console.WriteLine("  " + PadRight("name", 20) + PadRight("address", 20) + "size");

    var sections = image.Sections;
    for (nuint i = 0u; i < sections.Count; i++)
    {
        var section = sections[i];
        Console.WriteLine("  " + PadRight(section.Name, 20)
                          + PadRight("0x" + FormatHexPadded(section.Address, 16), 20)
                          + FormatNumber(section.Size));
    }
    return 0;
}

// ------------------------------------------------------------------ self test

/// Reports one check and carries the verdict along, which is how the Forms
/// samples do it: a module-level flag is refused (SL0575 territory -- only
/// `const` lives at module scope), and threading it reads better than a class
/// that exists to hold one bool.
bool ReportCheck(bool sofar, String what, bool ok)
{
    Console.WriteLine((ok ? "  ok   " : "  FAIL ") + what);
    return sofar && ok;
}

/// The parts that need no binary on disk: the number reading everything else
/// is built out of.
int RunSelfTest()
{
    // LEB128, unsigned. 0xE5 0x8E 0x26 is the canonical 624485 from the DWARF
    // standard's own worked example, which is why it is the one used here.
    bool ok = true;

    byte[] example = [0xE5, 0x8E, 0x26];
    var one = new Cursor(example);
    ok = ReportCheck(ok, "an unsigned LEB128 reads the standard's own example",
               one.Leb() == 624485u);

    // And signed: 0xC0 0xBB 0x78 is -123456, the matching example.
    byte[] negative = [0xC0, 0xBB, 0x78];
    var two = new Cursor(negative);
    ok = ReportCheck(ok, "a signed LEB128 reads its example too", two.SLeb() == -123456);

    // A single byte with the sign bit set is negative, which is the case a
    // reader that forgets to smear the sign gets wrong and nothing notices
    // until an fbreg offset points the wrong way up the stack.
    byte[] minusOne = [0x7F];
    var three = new Cursor(minusOne);
    ok = ReportCheck(ok, "a one-byte signed LEB128 is sign-extended", three.SLeb() == -1);

    byte[] plus63 = [0x3F];
    var four = new Cursor(plus63);
    ok = ReportCheck(ok, "and a positive one is not", four.SLeb() == 63);

    // Little-endian, which everything in both containers is.
    byte[] word = [0x78, 0x56, 0x34, 0x12, 0, 0, 0, 0];
    var five = new Cursor(word);
    ok = ReportCheck(ok, "a u32 is little-endian", five.U32() == 0x12345678u);

    byte[] wide = [1, 0, 0, 0, 0, 0, 0, 0x80];
    var six = new Cursor(wide);
    ok = ReportCheck(ok, "a u64 uses its top byte", six.U64() == 0x8000000000000001u);

    // **Running off the end answers rather than aborts**, which is the whole
    // contract: the input is a file somebody else wrote.
    byte[] tooShort = [1, 2];
    var seven = new Cursor(tooShort);
    seven.U32();
    ok = ReportCheck(ok, "a read past the end is refused, not fatal", seven.Overran);

    byte[] terminated = [0x41, 0x42, 0, 0x43];
    var eight = new Cursor(terminated);
    ok = ReportCheck(ok, "a C string stops at its NUL", eight.CString() == "AB");
    ok = ReportCheck(ok, "and leaves the cursor after it", eight.Offset == 3u);

    // An unterminated string is still answered, because the bytes are probably
    // the name that was meant.
    byte[] unterminated = [0x41, 0x42];
    var nine = new Cursor(unterminated);
    ok = ReportCheck(ok, "an unterminated string is answered anyway", nine.CString() == "AB");
    ok = ReportCheck(ok, "and says it ran over", nine.Overran);

    // A run of continuation bytes must stop rather than walk the file.
    byte[] endless = [0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,
                      0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80];
    var ten = new Cursor(endless);
    ten.Leb();
    ok = ReportCheck(ok, "a LEB128 that never ends stops at ten bytes", ten.Offset == 10u);

    // ------------------------------------------------- the line-table lookups
    //
    // Diffing the whole table against `llvm-dwarfdump` proves the *rows*, and
    // says nothing about the two searches over them -- which is where the
    // subtlety is. Two sequences with a gap between them is the shape that
    // catches it.
    var table = new LineTable();
    table.Files.Add("one.sl");
    //                          addr    file line col stmt  end    pro    epi
    table.Rows.Add(new LineRow(0x1000u, 0u, 10u, 1u, true,  false, false, false));
    table.Rows.Add(new LineRow(0x1010u, 0u, 11u, 1u, true,  false, false, false));
    table.Rows.Add(new LineRow(0x1020u, 0u, 11u, 1u, false, true,  false, false));
    table.Rows.Add(new LineRow(0x2000u, 0u, 20u, 1u, true,  false, false, false));
    table.Rows.Add(new LineRow(0x2010u, 0u, 20u, 1u, false, true,  false, false));

    var first = table.RowCovering(0x1000u);
    ok = ReportCheck(ok, "an address at a row's start is that row",
                     first != null && ((LineRow)first).Line == 10u);

    var middle = table.RowCovering(0x1015u);
    ok = ReportCheck(ok, "an address inside a row belongs to it",
                     middle != null && ((LineRow)middle).Line == 11u);

    // **The end of a sequence covers nothing.** Its address is one past the
    // last instruction, so treating it as a row that reaches the next sequence
    // reports the previous function for every address in the gap -- an answer
    // plausible enough to act on.
    ok = ReportCheck(ok, "the address a sequence ends at belongs to no row",
                     table.RowCovering(0x1020u) == null);
    ok = ReportCheck(ok, "and neither does the gap after it",
                     table.RowCovering(0x1500u) == null);

    var second = table.RowCovering(0x2000u);
    ok = ReportCheck(ok, "the next sequence starts cleanly",
                     second != null && ((LineRow)second).Line == 20u);

    nuint found = 0u;
    uint chosen = 0u;
    ok = ReportCheck(ok, "a line with code gives its own address",
                     table.AddressForLine(0u, 11u, &found, &chosen)
                     && found == 0x1010u && chosen == 11u);

    // A line with no code binds forward, and the caller is told where to.
    ok = ReportCheck(ok, "a line with none moves to the next that has some",
                     table.AddressForLine(0u, 12u, &found, &chosen)
                     && found == 0x2000u && chosen == 20u);

    ok = ReportCheck(ok, "and past the last line there is nothing",
                     !table.AddressForLine(0u, 99u, &found, &chosen));

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
                              + FormatHexadecimal((ulong)forms[i]));
            everyForm = false;
        }
    }
    ok = ReportCheck(ok, "every form this engine names can also be skipped", everyForm);

    // And the other half of the contract: a form it does not know is *refused*,
    // not skipped by zero bytes. Answering true there would keep the reader
    // running over an entry it has already lost.
    byte[] spare = [0, 0, 0, 0, 0, 0, 0, 0];
    var unknown = new Cursor(spare);
    ok = ReportCheck(ok, "a form it has never heard of is refused rather than guessed",
               !SkipForm(unknown, 0x7Fu, 8u, 4u));

    // The header structures, against the sizes their formats fix. Cheap, and
    // the only cover the 32-bit layouts have until a 32-bit binary is built
    // here -- the box this is developed on has no multilib.
    String sizes = HeaderSizeProblem();
    ok = ReportCheck(ok, "every header struct is the size its format says",
               sizes.IsEmpty);
    if (!sizes.IsEmpty)
        Console.WriteLine("       " + sizes);

    Console.WriteLine(ok ? "all checks passed" : "FAILED");
    return ok ? 0 : 1;
}

/// Reads the binary and its DWARF, or prints why not.
DwarfInfo? LoadDwarfOrComplain(String path)
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

int PrintUnits(String path)
{
    var info = LoadDwarfOrComplain(path);
    if (info == null)
        return 1;

    var units = ((DwarfInfo)info).Units;
    Console.WriteLine(FormatNumber(units.Count) + " unit(s)");
    for (nuint i = 0u; i < units.Count; i++)
    {
        var unit = units[i];
        Console.WriteLine("");
        Console.WriteLine("  0x" + FormatHexadecimal((ulong)unit.Offset) + "  "
                          + unit.Name);
        Console.WriteLine("    version " + FormatNumber((nuint)unit.Version)
                          + ", " + FormatNumber(unit.AddressSize) + "-byte addresses, "
                          + FormatNumber(unit.Dies.Count) + " entries");
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
int PrintDies(String path, String only)
{
    var info = LoadDwarfOrComplain(path);
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
            line.Append(FormatHexadecimal((ulong)die.Offset));
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
                text.Append(FormatAttributeValue(one));
                Console.WriteLine(text.ToText());
            }
        }
    }
    return 0;
}

/// One attribute's value, in the shape `llvm-dwarfdump` prints it so the two
/// can be compared without translating.
String FormatAttributeValue(Attribute one)
{
    if (one.IsText)
        return "(\"" + one.Text + "\")";
    if (one.Block.Length != 0u)
        return "(<0x" + FormatHexadecimal((ulong)one.Block.Length) + "> bytes)";
    return "(0x" + FormatHexadecimal(one.Value) + ")";
}

/// Every unit's line table, read once.
///
/// A unit points at its table with `DW_AT_stmt_list`, and several units can
/// point at the same one, so this is per unit rather than per section.
List<LineTable> ReadEveryLineTable(DwarfInfo info)
{
    var made = new List<LineTable>();
    for (nuint i = 0u; i < info.Units.Count; i++)
    {
        var root = info.Units[i].Root;
        if (root == null || !((Die)root).Has(AtStmtList))
        {
            made.Add(new LineTable());
            continue;
        }
        nuint at = (nuint)((Die)root).NumberOf(AtStmtList, 0u);
        made.Add(ReadLineTable(info.LineSection, at, info.LineStrSection,
                               info.StrSection));
    }
    return made;
}

int PrintLines(String path)
{
    var info = LoadDwarfOrComplain(path);
    if (info == null)
        return 1;

    var held = (DwarfInfo)info;
    var tables = ReadEveryLineTable(held);
    for (nuint u = 0u; u < tables.Count; u++)
    {
        var table = tables[u];
        if (table.Rows.Count == 0u)
            continue;

        Console.WriteLine("");
        Console.WriteLine(held.Units[u].Name + "  ("
                          + FormatNumber(table.Rows.Count) + " rows, "
                          + FormatNumber(table.Files.Count) + " files)");

        for (nuint i = 0u; i < table.Rows.Count; i++)
        {
            var row = table.Rows[i];
            var line = new StringBuilder();
            line.Append("  0x");
            line.Append(FormatHexPadded(row.Address, 16));
            line.Append(" ");
            line.Append(PadRight(FormatNumber((nuint)row.Line), 7));
            line.Append(PadRight(FormatNumber((nuint)row.Column), 7));
            line.Append(PadRight(FormatNumber(row.File), 7));
            if (row.IsStmt)        line.Append(" is_stmt");
            if (row.PrologueEnd)   line.Append(" prologue_end");
            if (row.EpilogueBegin) line.Append(" epilogue_begin");
            if (row.EndSequence)   line.Append(" end_sequence");
            Console.WriteLine(line.ToText());
        }
    }
    return 0;
}

/// `file:line` to an address -- what planting a breakpoint is.
int PrintAddressOfLine(String path, String where)
{
    nuint colon = 0u;
    bool found = false;
    for (nuint i = where.ByteLength(); i > 0u; i--)
    {
        if (where.ByteAt(i - 1u) == (byte)58)         // ':'
        {
            colon = i - 1u;
            found = true;
            break;
        }
    }
    if (!found)
    {
        Console.WriteLine("sldb: expected file:line, got " + where);
        return 2;
    }

    String wantedFile = where.Substring(0u, colon);
    uint wantedLine = (uint)ParseNumber(where.Substring(colon + 1u,
                                        where.ByteLength() - colon - 1u));

    var info = LoadDwarfOrComplain(path);
    if (info == null)
        return 1;

    var held = (DwarfInfo)info;
    var tables = ReadEveryLineTable(held);

    for (nuint u = 0u; u < tables.Count; u++)
    {
        var table = tables[u];
        for (nuint f = 0u; f < table.Files.Count; f++)
        {
            if (!PathEndsWith(table.Files[f], wantedFile))
                continue;

            nuint address = 0u;
            uint chosen = 0u;
            if (!table.AddressForLine(f, wantedLine, &address, &chosen))
                continue;

            Console.WriteLine("0x" + FormatHexadecimal((ulong)address)
                              + "  " + table.Files[f] + ":"
                              + FormatNumber((nuint)chosen));

            // **Say so when the breakpoint moved.** A line with no code binds
            // to the next one that has some, and a marker that silently sits
            // where it was asked for is the one that wastes an afternoon.
            if (chosen != wantedLine)
                Console.WriteLine("      (line " + FormatNumber((nuint)wantedLine)
                                  + " has no code; moved to "
                                  + FormatNumber((nuint)chosen) + ")");
            return 0;
        }
    }

    Console.WriteLine("sldb: no code for " + where);
    return 1;
}

/// An address back to a source line -- what reporting a stop is.
int PrintLineOfAddress(String path, String text)
{
    nuint address = (nuint)ParseNumber(text);

    var info = LoadDwarfOrComplain(path);
    if (info == null)
        return 1;

    var held = (DwarfInfo)info;
    var tables = ReadEveryLineTable(held);

    for (nuint u = 0u; u < tables.Count; u++)
    {
        var row = tables[u].RowCovering(address);
        if (row == null)
            continue;

        var here = (LineRow)row;
        Console.WriteLine(tables[u].FileName(here.File) + ":"
                          + FormatNumber((nuint)here.Line)
                          + "  (0x" + FormatHexadecimal((ulong)here.Address)
                          + (here.IsStmt ? ", a statement)" : ")"));

        // The function it fell in, which is what a person actually wanted.
        var unit = held.Units[u];
        for (nuint i = 0u; i < unit.Dies.Count; i++)
        {
            var die = unit.Dies[i];
            if (die.Tag != TagSubprogram)
                continue;
            nuint low = 0u;
            nuint high = 0u;
            if (die.Range(&low, &high) && address >= low && address < high)
            {
                Console.WriteLine("      in " + die.Name + " at +"
                                  + FormatNumber(address - low));
                break;
            }
        }
        return 0;
    }

    Console.WriteLine("sldb: no line covers 0x" + FormatHexadecimal((ulong)address));
    return 1;
}

/// Decimal, or hexadecimal behind an `0x`.
ulong ParseNumber(String text)
{
    nuint length = text.ByteLength();
    nuint at = 0u;
    ulong radix = 10u;

    if (length >= 2u && text.ByteAt(0u) == (byte)48
        && (text.ByteAt(1u) == (byte)120 || text.ByteAt(1u) == (byte)88))
    {
        at = 2u;
        radix = 16u;
    }

    ulong answer = 0u;
    for (nuint i = at; i < length; i++)
    {
        byte here = text.ByteAt(i);
        ulong digit = 16u;
        if (here >= (byte)48 && here <= (byte)57)
            digit = (ulong)(here - (byte)48);
        else if (here >= (byte)97 && here <= (byte)102)
            digit = (ulong)(here - (byte)97) + 10u;
        else if (here >= (byte)65 && here <= (byte)70)
            digit = (ulong)(here - (byte)65) + 10u;
        if (digit >= radix)
            break;
        answer = answer * radix + digit;
    }
    return answer;
}

/// Whether a full path ends with the piece a person typed.
///
/// A debugger is told `fixture.sl`, not
/// `/home/brandon/spike/fixture.sl`, so matching is on the tail at a separator
/// boundary -- and both separators count, because a line table written by a
/// Windows cross-compiler mixes them inside one string.
bool PathEndsWith(String full, String tail)
{
    nuint a = full.ByteLength();
    nuint b = tail.ByteLength();
    if (b == 0u || b > a)
        return false;

    for (nuint i = 0u; i < b; i++)
    {
        byte left = full.ByteAt(a - b + i);
        byte right = tail.ByteAt(i);
        if (left == (byte)92) left = (byte)47;
        if (right == (byte)92) right = (byte)47;
        if (left != right)
            return false;
    }

    if (b == a)
        return true;
    byte before = full.ByteAt(a - b - 1u);
    return before == (byte)47 || before == (byte)92;
}

/// Runs the program, stopping at a line if one was named.
///
/// The whole reading half meets the process here: an address comes from the
/// line table, a breakpoint goes in at it, and where the process stops is
/// turned back into a file and a line.
int RunProgram(String path, String where)
{
    var made = MakeTarget();
    if (!made.Ok)
    {
        Console.WriteLine("sldb: " + made.Error);
        return 1;
    }

    var read = Image.FromFile(path);
    if (!read.Ok)
    {
        Console.WriteLine("sldb: " + read.Error);
        return 1;
    }

    var image = read.Value;
    var info = new DwarfInfo(image);
    String bad = info.Read();
    if (bad.ByteLength() != 0u)
    {
        Console.WriteLine("sldb: " + bad);
        return 1;
    }

    var tables = ReadEveryLineTable(info);
    var engine = new Engine(made.Value, image, info, tables);

    // Running without DWARF works and reports addresses rather than lines,
    // which is a fair thing to do and a confusing thing to be given without
    // warning -- a default `-g` build on Windows writes CodeView to a .pdb and
    // carries no DWARF at all.
    if (info.IsEmpty)
        Console.WriteLine("note: no DWARF here, so stops are addresses only"
                          + " (see docs/dwarf.md)");

    if (where.ByteLength() != 0u)
    {
        nuint at = 0u;
        uint chosen = 0u;
        if (!FindLineAddress(tables, where, &at, &chosen))
        {
            Console.WriteLine("sldb: no code for " + where);
            return 1;
        }
        engine.Add(at, where);
        Console.WriteLine("breakpoint at 0x" + FormatHexadecimal((ulong)at)
                          + "  " + where
                          + (chosen != 0u ? "" : ""));
    }

    var started = engine.Start(path, "");
    if (!started.Ok)
    {
        Console.WriteLine("sldb: " + started.Error);
        return 1;
    }

    var stop = started.Value;
    while (true)
    {
        switch (stop.Kind)
        {
            case StopKind.Breakpoint:
            {
                Console.WriteLine("stopped at " + engine.Describe(stop.Address));
                String inside = engine.FunctionAt(stop.Address);
                if (inside.ByteLength() != 0u)
                    Console.WriteLine("      in " + inside);
                break;
            }

            case StopKind.Fault:
            {
                Console.WriteLine("fault 0x" + FormatHexadecimal((ulong)stop.Code)
                                  + " at " + engine.Describe(stop.Address));
                engine.Terminate();
                return 1;
            }

            case StopKind.Exited:
            {
                Console.WriteLine("exited with "
                                  + Standard.Text.FromInteger((long)stop.ExitCode));
                return 0;
            }

            default:
                break;
        }

        stop = engine.Continue();
    }
}

/// The address a `file:line` names, in link-time terms.
bool FindLineAddress(List<LineTable> tables, String where, nuint* address,
                     uint* chosen)
{
    nuint colon = 0u;
    bool split = false;
    for (nuint i = where.ByteLength(); i > 0u; i--)
    {
        if (where.ByteAt(i - 1u) == (byte)58)
        {
            colon = i - 1u;
            split = true;
            break;
        }
    }
    if (!split)
        return false;

    String file = where.Substring(0u, colon);
    uint line = (uint)ParseNumber(where.Substring(colon + 1u,
                                  where.ByteLength() - colon - 1u));

    for (nuint u = 0u; u < tables.Count; u++)
    {
        for (nuint f = 0u; f < tables[u].Files.Count; f++)
        {
            if (!PathEndsWith(tables[u].Files[f], file))
                continue;
            if (tables[u].AddressForLine(f, line, address, chosen))
                return true;
        }
    }
    return false;
}

/// Runs to a breakpoint and then does something there.
///
/// The three commands below differ only in what that something is, so the
/// launching, the breakpoint and the reporting are written once.
int RunToBreakpointThen(String path, String where, String what, int times)
{
    var made = MakeTarget();
    if (!made.Ok)
    {
        Console.WriteLine("sldb: " + made.Error);
        return 1;
    }

    var read = Image.FromFile(path);
    if (!read.Ok)
    {
        Console.WriteLine("sldb: " + read.Error);
        return 1;
    }

    var image = read.Value;
    var info = new DwarfInfo(image);
    String bad = info.Read();
    if (bad.ByteLength() != 0u)
    {
        Console.WriteLine("sldb: " + bad);
        return 1;
    }

    var tables = ReadEveryLineTable(info);
    var engine = new Engine(made.Value, image, info, tables);
    var target = made.Value;

    nuint at = 0u;
    uint chosen = 0u;
    if (!FindLineAddress(tables, where, &at, &chosen))
    {
        Console.WriteLine("sldb: no code for " + where);
        return 1;
    }
    engine.Add(at, where);

    var started = engine.Start(path, "");
    if (!started.Ok)
    {
        Console.WriteLine("sldb: " + started.Error);
        return 1;
    }

    var stop = started.Value;
    if (stop.Kind != StopKind.Breakpoint)
    {
        Console.WriteLine("sldb: never reached " + where);
        engine.Terminate();
        return 1;
    }

    Console.WriteLine("stopped at " + engine.Describe(stop.Address));

    if (what == "stack")
    {
        PrintCallStack(target, engine, stop.Thread);
        engine.Terminate();
        return 0;
    }

    if (what == "locals")
    {
        PrintLocals(target, engine, stop.Thread, stop.Address);
        engine.Terminate();
        return 0;
    }

    for (int i = 0; i < times; i++)
    {
        var moved = what == "next" ? engine.StepOver(stop.Thread)
                                   : engine.StepIn(stop.Thread);
        if (moved.Kind == StopKind.Exited)
        {
            Console.WriteLine("exited with "
                              + Standard.Text.FromInteger((long)moved.ExitCode));
            return 0;
        }
        if (moved.Kind == StopKind.Fault)
        {
            Console.WriteLine("fault 0x" + FormatHexadecimal((ulong)moved.Code));
            engine.Terminate();
            return 1;
        }
        Console.WriteLine("  -> " + engine.Describe(moved.Address)
                          + "   " + engine.FunctionAt(moved.Address));
        stop = moved;
    }

    engine.Terminate();
    return 0;
}

/// Every parameter and local of the function stopped in.
///
/// **All of them, including ones not yet reached**, because the compiler emits
/// no lexical blocks: a variable declared inside a loop belongs to the
/// function's scope as far as DWARF is concerned, so it is in this list from
/// the function's first line holding whatever its stack slot contained. Saying
/// so is better than filtering by `DW_AT_decl_line`, which would be the
/// debugger guessing at something the compiler knows and could emit.
void PrintLocals(ITarget target, Engine engine, uint thread, nuint pc)
{
    var found = engine.SubprogramAt(pc);
    if (found == null)
    {
        Console.WriteLine("  (no function here)");
        return;
    }

    var where = (Subprogram)found;
    Registers frame;
    frame.Pc = 0u;
    frame.StackPointer = 0u;
    frame.FramePointer = 0u;
    if (!target.ReadRegisters(thread, &frame))
    {
        Console.WriteLine("  (registers unreadable)");
        return;
    }

    var children = ChildrenOf(where.InUnit, where.Die);
    bool any = false;
    for (nuint i = 0u; i < children.Count; i++)
    {
        var one = children[i];
        if (one.Tag != TagFormalParameter && one.Tag != TagVariable)
            continue;

        var described = DescribeType(where.InUnit, one);
        String value = ReadValue(engine, target, where.InUnit, one,
                                 where.Die, frame);
        Console.WriteLine("  " + PadRight(one.Name, 12)
                          + PadRight(described.Name, 24) + value
                          + (one.Tag == TagFormalParameter ? "   (parameter)" : ""));
        any = true;
    }
    if (!any)
        Console.WriteLine("  (none)");
}

void PrintCallStack(ITarget target, Engine engine, uint thread)
{
    var frames = WalkStack(target, thread);
    for (nuint i = 0u; i < frames.Count; i++)
    {
        var frame = frames[i];
        String name = engine.FunctionAt(frame.Pc);

        // **Every frame above the first is a return address**, which is the
        // instruction *after* the call. Asked about that address directly, the
        // line table answers the line the call returns to -- which is usually
        // the same line and occasionally the next one. Stepping back one byte
        // asks about the call itself.
        nuint asking = i == 0u ? frame.Pc : frame.Pc - 1u;

        Console.WriteLine("  #" + FormatNumber(i) + "  "
                          + PadRight(name.ByteLength() != 0u ? name : "??", 24)
                          + engine.Describe(asking));
    }
}

int PrintUsage()
{
    Console.WriteLine("sldb -- the Stainless debugger");
    Console.WriteLine("");
    Console.WriteLine("  sldb sections <binary>     what the container holds");
    Console.WriteLine("  sldb units <binary>        the compilation units");
    Console.WriteLine("  sldb dies <binary> [name]  the entry tree");
    Console.WriteLine("  sldb lines <binary>        the line table, row by row");
    Console.WriteLine("  sldb line <binary> f:n     what address a line begins at");
    Console.WriteLine("  sldb addr <binary> 0xNNN   what line an address came from");
    Console.WriteLine("  sldb run <binary> [f:n]    run it, stopping at a line");
    Console.WriteLine("  sldb stack <binary> f:n    the call stack where it stops");
    Console.WriteLine("  sldb step <binary> f:n [k] step k lines, into calls");
    Console.WriteLine("  sldb next <binary> f:n [k] the same, over them");
    Console.WriteLine("  sldb locals <binary> f:n   the variables in scope there");
    Console.WriteLine("  sldb --selftest            the checks that need no binary");
    return 2;
}

int Main()
{
    var args = Standard.Env.Arguments();
    if (args.Length == 0u)
        return PrintUsage();

    if (args[0u] == "--selftest")
        return RunSelfTest();

    if (args[0u] == "sections" && args.Length >= 2u)
        return PrintSections(args[1u]);

    if (args[0u] == "units" && args.Length >= 2u)
        return PrintUnits(args[1u]);

    if (args[0u] == "dies" && args.Length >= 2u)
        return PrintDies(args[1u], args.Length >= 3u ? args[2u] : "");

    if (args[0u] == "lines" && args.Length >= 2u)
        return PrintLines(args[1u]);

    if (args[0u] == "line" && args.Length >= 3u)
        return PrintAddressOfLine(args[1u], args[2u]);

    if (args[0u] == "addr" && args.Length >= 3u)
        return PrintLineOfAddress(args[1u], args[2u]);

    if (args[0u] == "run" && args.Length >= 2u)
        return RunProgram(args[1u], args.Length >= 3u ? args[2u] : "");

    if (args[0u] == "stack" && args.Length >= 3u)
        return RunToBreakpointThen(args[1u], args[2u], "stack", 0);

    if (args[0u] == "locals" && args.Length >= 3u)
        return RunToBreakpointThen(args[1u], args[2u], "locals", 0);

    if ((args[0u] == "step" || args[0u] == "next") && args.Length >= 3u)
    {
        int times = args.Length >= 4u ? (int)ParseNumber(args[3u]) : 1;
        return RunToBreakpointThen(args[1u], args[2u], args[0u], times);
    }

    return PrintUsage();
}
