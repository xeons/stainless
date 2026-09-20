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
//   sldb watch <binary> f:n e  what an expression is worth there
//   sldb when <binary> f:n c    stop at a line only when c holds
//   sldb unwind <binary> f:n    the stack both ways, for comparing them
//   sldb cfi <binary>           what the unwind information covers
//   sldb threads <binary> f:n   every thread, and where each of them is
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

    // ------------------------------------------------ watch expressions
    //
    // The grammar, which needs no process, no binary and no frame -- which is
    // why parsing is its own pass. A watch that is refused is refused the same
    // way here as it is in the box it was typed into.
    var plain = ParseWatch("a");
    ok = ReportCheck(ok, "a bare name is an expression",
                     plain.Problem.IsEmpty && plain.Root == "a"
                     && plain.Steps.IsEmpty && plain.Stars == 0);

    var chain = ParseWatch("a.b.c");
    ok = ReportCheck(ok, "a chain of fields is one step each",
                     chain.Problem.IsEmpty && chain.Steps.Count == 2u
                     && chain.Steps[0u].IsField && chain.Steps[0u].Field == "b"
                     && chain.Steps[1u].Field == "c");

    var constant = ParseWatch("a[3]");
    var index = constant.Steps.IsEmpty ? null : constant.Steps[0u].Index;
    ok = ReportCheck(ok, "an index is an expression of its own",
                     constant.Problem.IsEmpty && constant.Steps.Count == 1u
                     && !constant.Steps[0u].IsField
                     && index != null && ((WatchExpression)index).IsLiteral
                     && ((WatchExpression)index).Literal == 3u);

    var variable = ParseWatch("a[i]");
    var inner = variable.Steps.IsEmpty ? null : variable.Steps[0u].Index;
    ok = ReportCheck(ok, "and so an index may be a variable",
                     variable.Problem.IsEmpty && inner != null
                     && ((WatchExpression)inner).Root == "i");

    var followed = ParseWatch("**p");
    ok = ReportCheck(ok, "stars are counted rather than nested",
                     followed.Problem.IsEmpty && followed.Stars == 2
                     && followed.Root == "p");

    var hex = ParseWatch("0x2A");
    ok = ReportCheck(ok, "a number may be written in hexadecimal",
                     hex.Problem.IsEmpty && hex.IsLiteral && hex.Literal == 42u);

    // **Every refusal names what was wrong**, because a watch is typed by a
    // person and "invalid expression" tells them nothing about which half.
    ok = ReportCheck(ok, "an empty expression is refused",
                     !ParseWatch("").Problem.IsEmpty);
    ok = ReportCheck(ok, "a '.' with no field after it is refused",
                     !ParseWatch("a.").Problem.IsEmpty);
    ok = ReportCheck(ok, "a '[' with no ']' is refused",
                     !ParseWatch("a[3").Problem.IsEmpty);
    ok = ReportCheck(ok, "two expressions in a row are refused",
                     !ParseWatch("a b").Problem.IsEmpty);

    // A byte that means nothing here is carried into the message, which is
    // the whole reason the scanner keeps it rather than dropping it.
    ok = ReportCheck(ok, "and a stray byte is named in the refusal",
                     ParseWatch("a $ b").Problem.Contains("$"));

    // An arithmetic expression is not a small expression, and saying so is
    // better than half-evaluating one.
    ok = ReportCheck(ok, "arithmetic is not part of the promise",
                     !ParseWatch("a + 1").Problem.IsEmpty);

    // One comparison, which is what a conditional breakpoint is.
    var asked = ParseWatch("count >= 3");
    ok = ReportCheck(ok, "a comparison is an expression with a right side",
                     asked.Problem.IsEmpty && asked.IsCondition
                     && asked.Root == "count" && asked.Against != null
                     && ((WatchExpression)asked.Against).IsLiteral
                     && ((WatchExpression)asked.Against).Literal == 3u);

    ok = ReportCheck(ok, "and a plain expression is not a condition",
                     !ParseWatch("count").IsCondition);

    ok = ReportCheck(ok, "both sides may be expressions",
                     ParseWatch("a.b[1] != *p").Problem.IsEmpty);

    // A chain is the beginning of a language, and the promise is smaller.
    ok = ReportCheck(ok, "a chain of comparisons is refused",
                     !ParseWatch("a < b < c").Problem.IsEmpty);

    // `=` is what somebody meant to type as `==`, and saying which is the
    // whole reason the scanner keeps the byte.
    ok = ReportCheck(ok, "a single '=' is named as the mistake it is",
                     ParseWatch("a = 1").Problem.Contains("=="));

    // --------------------------------------------------- unwind information
    //
    // The two readers, against tables written by hand. Neither needs a binary
    // or a process, which is the half of an unwinder that can be checked that
    // way -- what it does with a real stack is `sldb unwind`, which walks the
    // same stack twice and prints both.

    // **A `.pdata` record is found by binary search**, and the search is the
    // part with an off-by-one in it: three functions, and every address in
    // each of them, plus the gaps between.
    byte[] pdata = [
        0x00, 0x10, 0x00, 0x00, 0x20, 0x10, 0x00, 0x00, 0x00, 0x20, 0x00, 0x00,
        0x30, 0x10, 0x00, 0x00, 0x40, 0x10, 0x00, 0x00, 0x08, 0x20, 0x00, 0x00,
        0x50, 0x10, 0x00, 0x00, 0x60, 0x10, 0x00, 0x00, 0x10, 0x20, 0x00, 0x00,
    ];

    ok = ReportCheck(ok, "the first byte of a function is in it",
                     RuntimeFunctionIndexAt(pdata, 0x1000u) == 0);
    ok = ReportCheck(ok, "and the last",
                     RuntimeFunctionIndexAt(pdata, 0x101Fu) == 0);
    ok = ReportCheck(ok, "the byte one past it is not",
                     RuntimeFunctionIndexAt(pdata, 0x1020u) < 0);
    ok = ReportCheck(ok, "the one in the middle is found",
                     RuntimeFunctionIndexAt(pdata, 0x1035u) == 1);
    ok = ReportCheck(ok, "and the last one",
                     RuntimeFunctionIndexAt(pdata, 0x105Fu) == 2);
    ok = ReportCheck(ok, "below the first is nothing",
                     RuntimeFunctionIndexAt(pdata, 0x0FFFu) < 0);
    ok = ReportCheck(ok, "past the last is nothing",
                     RuntimeFunctionIndexAt(pdata, 0x2000u) < 0);

    // **Every unwind code has a length**, and a reader that gets one wrong
    // reads the next code from the middle of this one -- which still produces
    // codes, and they are nonsense that looks like a prologue.
    ok = ReportCheck(ok, "an alloc-large in units is two slots",
                     UnwindCodeSlots(1u, 0u) == 2u);
    ok = ReportCheck(ok, "and in bytes is three",
                     UnwindCodeSlots(1u, 1u) == 3u);
    ok = ReportCheck(ok, "a push is one",
                     UnwindCodeSlots(0u, 5u) == 1u);
    ok = ReportCheck(ok, "saving a register is two",
                     UnwindCodeSlots(4u, 3u) == 2u);
    ok = ReportCheck(ok, "and saving it far is three",
                     UnwindCodeSlots(5u, 3u) == 3u);

    // The CFI pointer encodings, which are where an `.eh_frame` reader goes
    // wrong quietly: the entries still parse and the ranges they claim are
    // plausible and somewhere else.
    byte[] encoded = [0x08, 0x00, 0x00, 0x00, 0xF8, 0xFF, 0xFF, 0xFF];

    nuint place = 0u;
    nuint value = 0u;
    ok = ReportCheck(ok, "an sdata4 pcrel pointer is relative to itself",
                     ReadEncodedPointer(encoded, 0x2000u, 0x1Bu, &place, &value)
                     && value == 0x2008u && place == 4u);

    place = 4u;
    ok = ReportCheck(ok, "and a negative one goes backwards",
                     ReadEncodedPointer(encoded, 0x2000u, 0x1Bu, &place, &value)
                     && value == 0x1FFCu);

    place = 0u;
    ok = ReportCheck(ok, "a udata4 with no application is itself",
                     ReadEncodedPointer(encoded, 0x2000u, 0x03u, &place, &value)
                     && value == 8u);

    place = 0u;
    ok = ReportCheck(ok, "an omitted pointer is refused",
                     !ReadEncodedPointer(encoded, 0u, 0xFFu, &place, &value));

    place = 0u;
    ok = ReportCheck(ok, "and so is an indirect one, which needs the process",
                     !ReadEncodedPointer(encoded, 0u, 0x9Bu, &place, &value));

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
            if (!IsTheSameSourceFile(table.Files[f], wantedFile))
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
        if (!FindAddressOfWhere(tables, where, &at, &chosen))
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

    // Where the loader actually put it, which on a position-independent
    // executable is never where it was linked -- and is the one number that
    // makes every breakpoint land.
    if (!engine.SlideKnown)
        Console.WriteLine("note: the image base was never learned,"
                          + " so no breakpoint is planted");
    else if (engine.Slide != 0u)
        Console.WriteLine("image slid by 0x"
                          + FormatHexadecimal((ulong)engine.Slide));

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
///
/// The splitting is this tool's, because `file:line` is a thing a command line
/// says and not a thing a debugger knows about; the lookup itself is
/// `Debugger.FindLineAddress`, shared with the window so that the two cannot
/// disagree about which file a path names.
bool FindAddressOfWhere(List<LineTable> tables, String where, nuint* address,
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
    return FindLineAddress(tables, file, line, address, chosen);
}

/// Runs to a breakpoint and then does something there.
///
/// The three commands below differ only in what that something is, so the
/// launching, the breakpoint and the reporting are written once.
int RunToBreakpointThen(String path, String where, String what, int times,
                        String[] watches, String condition)
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
    if (!FindAddressOfWhere(tables, where, &at, &chosen))
    {
        Console.WriteLine("sldb: no code for " + where);
        return 1;
    }
    var planted = engine.Add(at, where);

    if (condition.ByteLength() != 0u)
    {
        String bad2 = engine.Condition(planted, condition);
        if (bad2.ByteLength() != 0u)
        {
            Console.WriteLine("sldb: " + condition + ": " + bad2);
            return 1;
        }
    }

    // Before the program starts, because a watch is a property of the session
    // rather than of a stop -- and because a refusal here names the expression
    // that was wrong rather than appearing as a row in a pane.
    for (nuint i = 0u; i < watches.Length; i++)
    {
        String problem = engine.AddWatch(watches[i]);
        if (problem.ByteLength() != 0u)
        {
            Console.WriteLine("sldb: " + watches[i] + ": " + problem);
            return 1;
        }
    }

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

    // A condition that could not be answered still stops, and says so: a
    // breakpoint silently skipped is the stop somebody waited three minutes
    // for, gone.
    if (planted.ConditionProblem.ByteLength() != 0u)
        Console.WriteLine("      condition: " + planted.ConditionProblem);

    // **Through a snapshot, which is the point rather than a convenience.**
    // The IDE cannot ask the engine anything -- the one thread allowed to read
    // the process is busy -- so what a window shows is whatever `TakeSnapshot`
    // put in a snapshot. Printing from the same object is what makes these
    // commands a test of what the window will show, instead of a second route
    // to the same data that can quietly diverge from it.
    if (what == "stack" || what == "locals" || what == "snapshot"
        || what == "watch" || what == "when" || what == "threads")
    {
        var taken = TakeSnapshot(engine, target, stop);
        switch (what)
        {
            case "stack":
                PrintFrames(taken);
                break;

            case "locals":
                PrintValues(taken);
                break;

            case "watch":
                PrintWatches(taken);
                break;

            case "when":
                PrintValues(taken);
                break;

            case "threads":
                PrintThreads(taken);
                break;

            default:
                PrintWholeSnapshot(taken);
                break;
        }
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

/// What the unwind information says it covers.
///
/// Diffable against `llvm-dwarfdump --eh-frame` and `llvm-readobj
/// --unwind`, which is the only thing that catches a pointer encoding read
/// wrongly: the entries still parse, and the ranges they claim are plausible
/// and somewhere else.
int PrintUnwindTable(String path)
{
    var read = Debugger.Image.FromFile(path);
    if (!read.Ok)
    {
        Console.WriteLine("sldb: " + read.Error);
        return 1;
    }

    var table = new Unwinder(read.Value);
    Console.WriteLine(read.Value.Path);
    Console.WriteLine("  format  " + table.Format);

    if (table.IsEmpty)
    {
        Console.WriteLine("  nothing describes this binary's frames");
        return 1;
    }

    if (table.Format == ".pdata")
    {
        nuint count = table.Pdata.Length / 12u;
        Console.WriteLine("  " + FormatNumber(count) + " function(s)");
        Console.WriteLine("");
        for (nuint i = 0u; i < count; i++)
        {
            nuint at = i * 12u;
            Console.WriteLine("  0x" + FormatHexPadded(
                                  (nuint)LittleEndianAt(table.Pdata, at, 4u), 8)
                              + "  0x" + FormatHexPadded(
                                  (nuint)LittleEndianAt(table.Pdata, at + 4u, 4u), 8)
                              + "  info 0x" + FormatHexPadded(
                                  (nuint)LittleEndianAt(table.Pdata, at + 8u, 4u), 8));
        }
        return 0;
    }

    var entries = UnwindEntries(table);
    nuint fdes = 0u;
    for (nuint i = 0u; i < entries.Count; i++)
    {
        if (!entries[i].IsCie)
            fdes++;
    }

    Console.WriteLine("  " + FormatNumber(entries.Count) + " entries, "
                      + FormatNumber(fdes) + " of them FDEs");
    Console.WriteLine("");

    for (nuint i = 0u; i < entries.Count; i++)
    {
        var one = entries[i];
        if (one.IsCie)
        {
            Console.WriteLine("  0x" + FormatHexPadded(one.Offset, 6) + "  CIE");
            continue;
        }
        if (one.Problem.ByteLength() != 0u)
        {
            Console.WriteLine("  0x" + FormatHexPadded(one.Offset, 6)
                              + "  FDE  -- " + one.Problem);
            continue;
        }
        Console.WriteLine("  0x" + FormatHexPadded(one.Offset, 6)
                          + "  FDE  0x" + FormatHexPadded(one.Begin, 12)
                          + " .. 0x" + FormatHexPadded(one.Begin + one.Range, 12));
    }
    return 0;
}

/// The stack walked with the unwind information and again without it.
///
/// **What proves the unwinder is a difference, not an assertion.** The frame
/// pointer walk is right wherever there is a frame pointer, so on a `-g -O0`
/// binary the two agree all the way down and that is the answer: nothing was
/// broken. Where they part is where the unwind information was worth reading.
int PrintBothWalks(String path, String where)
{
    var made = MakeTarget();
    if (!made.Ok)
    {
        Console.WriteLine("sldb: " + made.Error);
        return 1;
    }

    var read = Debugger.Image.FromFile(path);
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
    var target = made.Value;
    var engine = new Engine(target, image, info, tables);

    nuint at = 0u;
    uint chosen = 0u;
    if (!FindAddressOfWhere(tables, where, &at, &chosen))
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
    Console.WriteLine("unwind   " + engine.Unwinder.Format);
    Console.WriteLine("");

    Console.WriteLine("with the unwind information");
    PrintWalk(engine, WalkStack(target, stop.Thread, engine.Unwinder,
                                engine.Slide));

    Console.WriteLine("");
    Console.WriteLine("frame pointer only");
    PrintWalk(engine, WalkStack(target, stop.Thread, null, engine.Slide));

    engine.Terminate();
    return 0;
}

void PrintWalk(Engine engine, List<Frame> frames)
{
    var table = engine.Unwinder;
    for (nuint i = 0u; i < frames.Count; i++)
    {
        var frame = frames[i];
        String named = engine.FunctionAt(i == 0u ? frame.Pc : frame.Pc - 1u);
        nuint linked = engine.ToLinked(frame.Pc);

        Console.WriteLine("  #" + FormatNumber(i) + "  "
                          + PadRight(named.ByteLength() != 0u ? named : "??", 20)
                          + "0x" + FormatHexPadded(frame.Pc, 12)
                          + (table.InImage(linked)
                             ? "  +0x" + FormatHexadecimal((ulong)linked) : "")
                          + (frame.Unwound ? "" : "   (frame pointer)"));
    }
}

/// The locals a snapshot holds, one to a line.
void PrintValues(Snapshot taken)
{
    if (taken.Locals.IsEmpty)
    {
        Console.WriteLine("  (none)");
        return;
    }

    for (nuint i = 0u; i < taken.Locals.Count; i++)
    {
        var one = taken.Locals[i];
        Console.WriteLine("  " + PadRight(one.Name, 12)
                          + PadRight(one.TypeName, 24) + one.Value
                          + (one.IsParameter ? "   (parameter)" : ""));
    }
}

/// The watches a snapshot holds, one to a line.
///
/// A watch that could not be read is a line too, marked so that a value and a
/// refusal cannot be mistaken for each other in a column of text.
void PrintWatches(Snapshot taken)
{
    if (taken.Watches.IsEmpty)
    {
        Console.WriteLine("  (none)");
        return;
    }

    for (nuint i = 0u; i < taken.Watches.Count; i++)
    {
        var one = taken.Watches[i];
        Console.WriteLine("  " + PadRight(one.Expression, 20)
                          + PadRight(one.TypeName, 24)
                          + (one.Ok ? one.Value : "-- " + one.Value));
    }
}

/// The threads a snapshot holds, one to a line.
///
/// A thread the platform lists and will not let a debugger read says so rather
/// than being left out: a program with four threads has four, and a pane that
/// showed one would be answering a different question.
void PrintThreads(Snapshot taken)
{
    if (taken.Threads.IsEmpty)
    {
        Console.WriteLine("  (none)");
        return;
    }

    for (nuint i = 0u; i < taken.Threads.Count; i++)
    {
        var one = taken.Threads[i];
        String where = !one.CanRead
                     ? "(not traced)"
                     : FormatWhere(one.File, one.Line, one.HasSource, one.Pc);

        Console.WriteLine("  " + (one.IsCurrent ? "> " : "  ")
                          + PadRight(FormatNumber((nuint)one.Id), 10)
                          + PadRight(one.Function.ByteLength() != 0u
                                     ? one.Function : "??", 24)
                          + where);
    }
}

/// The call stack a snapshot holds.
void PrintFrames(Snapshot taken)
{
    for (nuint i = 0u; i < taken.Frames.Count; i++)
    {
        var frame = taken.Frames[i];
        Console.WriteLine("  #" + FormatNumber(i) + "  "
                          + PadRight(frame.Function.ByteLength() != 0u
                                     ? frame.Function : "??", 24)
                          + FormatWhere(frame.File, frame.Line, frame.HasSource,
                                        frame.Pc));
    }
}

/// Everything in a snapshot, which is everything a window is given.
///
/// Its own command rather than a debugging aid: what this prints is exactly
/// the surface the IDE's panes are built on, so a field that grows here and is
/// never printed is a field no headless test covers.
void PrintWholeSnapshot(Snapshot taken)
{
    Console.WriteLine("state    " + StateName(taken.State));
    Console.WriteLine("stop     " + KindName(taken.Kind));
    Console.WriteLine("where    " + FormatWhere(taken.File, taken.Line,
                                                taken.HasSource, taken.Address));
    Console.WriteLine("function " + (taken.Function.ByteLength() != 0u
                                     ? taken.Function : "??"));
    if (taken.Note.ByteLength() != 0u)
        Console.WriteLine("note     " + taken.Note);

    Console.WriteLine("frames");
    PrintFrames(taken);
    Console.WriteLine("locals");
    PrintValues(taken);
    Console.WriteLine("watches");
    PrintWatches(taken);
    Console.WriteLine("threads");
    PrintThreads(taken);
}

/// A file and a line, or the address when there is no line.
String FormatWhere(String file, uint line, bool known, nuint address)
{
    if (known)
        return file + ":" + Standard.Text.FromInteger((long)line);
    return "0x" + FormatHexadecimal((ulong)address) + " (no line)";
}

String StateName(RunState state)
{
    switch (state)
    {
        case RunState.Idle: return "idle";
        case RunState.Running: return "running";
        case RunState.Stopped: return "stopped";
        default: return "ended";
    }
}

String KindName(StopKind kind)
{
    switch (kind)
    {
        case StopKind.Breakpoint: return "breakpoint";
        case StopKind.Step: return "step";
        case StopKind.Fault: return "fault";
        case StopKind.Exited: return "exited";
        case StopKind.Paused: return "paused";
        default: return "not running";
    }
}

/// The arguments from `from` onwards, as their own array.
String[] ArgumentsFrom(String[] args, nuint from)
{
    String[] rest = new String[args.Length - from];
    for (nuint i = from; i < args.Length; i++)
        rest[i - from] = args[i];
    return rest;
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
    Console.WriteLine("  sldb watch <binary> f:n e  what an expression is worth");
    Console.WriteLine("  sldb when <binary> f:n c   stop there only when c holds");
    Console.WriteLine("  sldb unwind <binary> f:n   the stack both ways");
    Console.WriteLine("  sldb cfi <binary>          what the unwind info covers");
    Console.WriteLine("  sldb threads <binary> f:n  every thread, and where it is");
    Console.WriteLine("  sldb snapshot <binary> f:n everything a window is given");
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

    String[] none = new String[0];

    if (args[0u] == "stack" && args.Length >= 3u)
        return RunToBreakpointThen(args[1u], args[2u], "stack", 0, none, "");

    if (args[0u] == "locals" && args.Length >= 3u)
        return RunToBreakpointThen(args[1u], args[2u], "locals", 0, none, "");

    if (args[0u] == "threads" && args.Length >= 3u)
        return RunToBreakpointThen(args[1u], args[2u], "threads", 0, none, "");

    if (args[0u] == "watch" && args.Length >= 4u)
        return RunToBreakpointThen(args[1u], args[2u], "watch", 0,
                                   ArgumentsFrom(args, 3u), "");

    if (args[0u] == "cfi" && args.Length >= 2u)
        return PrintUnwindTable(args[1u]);

    if (args[0u] == "unwind" && args.Length >= 3u)
        return PrintBothWalks(args[1u], args[2u]);

    if (args[0u] == "when" && args.Length >= 4u)
        return RunToBreakpointThen(args[1u], args[2u], "when", 0, none,
                                   args[3u]);

    if (args[0u] == "snapshot" && args.Length >= 3u)
        return RunToBreakpointThen(args[1u], args[2u], "snapshot", 0,
                                   args.Length >= 4u ? ArgumentsFrom(args, 3u)
                                                     : none, "");

    if ((args[0u] == "step" || args[0u] == "next") && args.Length >= 3u)
    {
        int times = args.Length >= 4u ? (int)ParseNumber(args[3u]) : 1;
        return RunToBreakpointThen(args[1u], args[2u], args[0u], times, none, "");
    }

    return PrintUsage();
}
