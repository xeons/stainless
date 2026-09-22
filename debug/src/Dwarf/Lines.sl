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

// `.debug_line`: which address belongs to which line, and back.
//
// **It is a bytecode, not a table.** A line table would be enormous -- one row
// per machine instruction that begins a statement, for every function in the
// program -- so DWARF ships a program that *builds* the table instead, in a
// machine with six registers and an opcode that advances two of them at once.
// Running it is the only way to read it, and that is why this file is an
// interpreter rather than a parser.
//
// The rows it produces are what a debugger actually wants twice over: a
// breakpoint on `fixture.sl:38` is a search for a row, and reporting where a
// stopped process is is a search for the row before its address.
//
// **DWARF 5 rewrote the file table and this is the part that bites.** Version 4
// and earlier list the directories and file names as runs of NUL-terminated
// strings; version 5 replaces both with a described table -- a format list of
// (content type, form) pairs, then that many entries in that shape. It also
// renumbered them: version 5 counts files from zero and entry zero is the
// primary source file, where version 4 counted from one and kept the primary
// file outside the list. A reader that gets the numbering wrong reports every
// line against the file before the right one, which looks like an off-by-one in
// something else entirely.
module Debugger;

import Standard.Collections;
import Standard.Text;

// The standard opcodes, which is the half of the instruction set that has
// names. Anything at or above `opcode_base` is a special opcode and means
// several things at once.
const uint LnsCopy             = 1u;
const uint LnsAdvancePc        = 2u;
const uint LnsAdvanceLine      = 3u;
const uint LnsSetFile          = 4u;
const uint LnsSetColumn        = 5u;
const uint LnsNegateStmt       = 6u;
const uint LnsSetBasicBlock    = 7u;
const uint LnsConstAddPc       = 8u;
const uint LnsFixedAdvancePc   = 9u;
const uint LnsSetPrologueEnd   = 10u;
const uint LnsSetEpilogueBegin = 11u;
const uint LnsSetIsa           = 12u;

// The extended opcodes, which arrive behind a zero byte and a length.
const uint LneEndSequence      = 1u;
const uint LneSetAddress       = 2u;
const uint LneDefineFile       = 3u;
const uint LneSetDiscriminator = 4u;

// What a column of the version 5 file table holds.
const uint LnctPath           = 1u;
const uint LnctDirectoryIndex = 2u;
const uint LnctTimestamp      = 3u;
const uint LnctSize           = 4u;
const uint LnctMd5            = 5u;

/// One row of the table the program builds: an address, and what source it
/// came from.
public class LineRow
{
    public nuint Address;
    public nuint File;
    public uint Line;
    public uint Column;

    /// Whether this address is a place a breakpoint belongs. A statement may
    /// compile to several rows and only some are marked.
    public bool IsStmt;

    /// The first address *after* a run of code. Its line means nothing, and a
    /// lookup that treats it as a row covering what follows reports the wrong
    /// function for every address in the gap.
    public bool EndSequence;

    public bool PrologueEnd;
    public bool EpilogueBegin;

    public LineRow(nuint address, nuint file, uint line, uint column,
                   bool isStmt, bool endSequence, bool prologueEnd,
                   bool epilogueBegin)
    {
        Address = address;
        File = file;
        Line = line;
        Column = column;
        IsStmt = isStmt;
        EndSequence = endSequence;
        PrologueEnd = prologueEnd;
        EpilogueBegin = epilogueBegin;
    }
}

/// One unit's line table: the files it names, and the rows the program built.
public class LineTable
{
    /// The file names, in the unit's own numbering -- so `Files[row.File]` is
    /// always right and the version difference is settled when the table is
    /// read rather than at every use.
    public List<String> Files;

    public List<LineRow> Rows;

    public uint Version;

    public LineTable()
    {
        Files = new List<String>();
        Rows = new List<LineRow>();
        Version = 0u;
    }

    public String FileName(nuint index)
        => index < Files.Count ? Files[index] : "";

    /// The row covering an address, or null.
    ///
    /// **A sequence's last row ends it and covers nothing.** Rows come in runs,
    /// each finishing with an `end_sequence` whose address is one past the last
    /// instruction; an address at or beyond that belongs to no row in the run.
    /// Ignoring that reports the previous function for every address in a gap
    /// between sequences, which is exactly the sort of answer that looks
    /// plausible enough to act on.
    public LineRow? RowCovering(nuint address)
    {
        LineRow? best = null;
        for (nuint i = 0u; i + 1u < Rows.Count; i++)
        {
            var here = Rows[i];
            if (here.EndSequence)
                continue;
            var next = Rows[i + 1u];
            if (address >= here.Address && address < next.Address)
            {
                // Later rows win: several can share an address, and the last
                // one written is the state the program ended in.
                best = here;
            }
        }
        return best;
    }

    /// The lowest address that begins a statement on `line` or the first line
    /// after it that has any code, in the file at `file`.
    ///
    /// **The line actually chosen is answered too**, because a breakpoint on a
    /// blank line or a declaration binds somewhere else and a marker that does
    /// not move is the one that wastes an afternoon. Visual Studio moves it;
    /// so should this.
    public bool AddressForLine(nuint file, uint line, nuint* address, uint* chosen)
    {
        bool found = false;
        uint bestLine = 0u;
        nuint bestAddress = 0u;

        for (nuint i = 0u; i < Rows.Count; i++)
        {
            var row = Rows[i];
            if (row.EndSequence || !row.IsStmt || row.File != file)
                continue;
            if (row.Line < line)
                continue;

            if (!found || row.Line < bestLine
                || (row.Line == bestLine && row.Address < bestAddress))
            {
                found = true;
                bestLine = row.Line;
                bestAddress = row.Address;
            }
        }

        if (!found)
            return false;
        *address = bestAddress;
        *chosen = bestLine;
        return true;
    }
}

/// The six registers the line program moves, plus the flags it resets after
/// every row.
struct LineMachine
{
    public nuint Address;
    public nuint File;
    public uint Line;
    public uint Column;
    public bool IsStmt;
    public bool PrologueEnd;
    public bool EpilogueBegin;
    public nuint OperationIndex;
}

/// Runs the line program a unit points at.
///
/// `at` is the unit's `DW_AT_stmt_list`. Answers an empty table when there is
/// nothing there, which is what a unit compiled without line information has
/// and is not an error.
public LineTable ReadLineTable(byte[] section, nuint at, byte[] lineStr,
                               byte[] str)
{
    var made = new LineTable();
    if (at + 4u >= section.Length)
        return made;

    var reader = new Cursor(section, at);

    nuint offsetSize = 4u;
    ulong length = (ulong)reader.U32();
    if (length == 0xFFFFFFFFu)
    {
        length = reader.U64();
        offsetSize = 8u;
    }
    nuint end = reader.Offset + (nuint)length;

    made.Version = (uint)reader.U16();
    if (made.Version >= 5u)
    {
        reader.U8();                                  // address_size
        reader.U8();                                  // segment_selector_size
    }

    // Everything from here to the first opcode is the header, and its length is
    // given rather than implied -- which is what lets a producer add fields a
    // reader has never heard of.
    nuint headerLength = (nuint)(offsetSize == 8u ? reader.U64()
                                                  : (ulong)reader.U32());
    nuint program = reader.Offset + headerLength;

    nuint minimumLength = (nuint)reader.U8();
    nuint operationsPerInstruction = 1u;
    if (made.Version >= 4u)
        operationsPerInstruction = (nuint)reader.U8();
    if (operationsPerInstruction == 0u)
        operationsPerInstruction = 1u;

    bool defaultIsStmt = reader.U8() != 0;
    int lineBase = (int)(sbyte)reader.U8();
    uint lineRange = (uint)reader.U8();
    uint opcodeBase = (uint)reader.U8();
    if (lineRange == 0u)
        lineRange = 1u;

    // How many operands each standard opcode takes. Read and kept because an
    // opcode this reader does not know can still be stepped over if its operand
    // count is known -- the line program's version of a skip rule.
    var standardLengths = new List<nuint>();
    for (uint i = 1u; i < opcodeBase; i++)
        standardLengths.Add((nuint)reader.U8());

    if (made.Version >= 5u)
        ReadFileTableV5(reader, made, lineStr, str, offsetSize);
    else
        ReadFileTableV4(reader, made);

    // --------------------------------------------------------- the program

    reader.Seek(program);

    LineMachine state;
    ResetLineMachine(&state, defaultIsStmt, made.Version);

    while (reader.Offset < end && !reader.Overran)
    {
        uint opcode = (uint)reader.U8();

        if (opcode >= opcodeBase)
        {
            // A special opcode advances the address and the line together, and
            // emits a row. This is most of a real line program by volume.
            uint adjusted = opcode - opcodeBase;
            nuint advance = (nuint)(adjusted / lineRange);
            AdvanceLineAddress(&state, advance, minimumLength,
                               operationsPerInstruction);
            state.Line = (uint)((int)state.Line + lineBase
                                + (int)(adjusted % lineRange));
            AppendLineRow(made, &state, false);
            continue;
        }

        if (opcode == 0u)
        {
            // An extended opcode: a length, then a sub-opcode, then operands.
            // The length is what makes an unknown one survivable.
            nuint size = (nuint)reader.Leb();
            nuint after = reader.Offset + size;
            if (size == 0u)
                continue;

            uint sub = (uint)reader.U8();
            switch (sub)
            {
                case LneEndSequence:
                    AppendLineRow(made, &state, true);
                    ResetLineMachine(&state, defaultIsStmt, made.Version);
                    break;

                case LneSetAddress:
                    state.Address = (nuint)ReadFixedWidth(reader, size - 1u);
                    state.OperationIndex = 0u;
                    break;

                default:
                    break;                  // define_file, discriminator, ours
            }

            reader.Seek(after);
            continue;
        }

        switch (opcode)
        {
            case LnsCopy:
                AppendLineRow(made, &state, false);
                break;

            case LnsAdvancePc:
                AdvanceLineAddress(&state, (nuint)reader.Leb(), minimumLength,
                                   operationsPerInstruction);
                break;

            case LnsAdvanceLine:
                state.Line = (uint)((long)state.Line + reader.SLeb());
                break;

            case LnsSetFile:
                state.File = (nuint)reader.Leb();
                break;

            case LnsSetColumn:
                state.Column = (uint)reader.Leb();
                break;

            case LnsNegateStmt:
                state.IsStmt = !state.IsStmt;
                break;

            case LnsSetBasicBlock:
                break;

            case LnsConstAddPc:
            {
                // The address advance of special opcode 255, and nothing else
                // -- a cheap way to move a long way without a LEB128.
                uint adjusted = 255u - opcodeBase;
                AdvanceLineAddress(&state, (nuint)(adjusted / lineRange),
                                   minimumLength, operationsPerInstruction);
                break;
            }

            case LnsFixedAdvancePc:
                // **A plain uhalf, not a LEB128**, and the only operand in the
                // whole instruction set that is. Reading it as a LEB128 is a
                // desynchronisation that lasts for the rest of the sequence.
                state.Address = state.Address + (nuint)reader.U16();
                state.OperationIndex = 0u;
                break;

            case LnsSetPrologueEnd:
                state.PrologueEnd = true;
                break;

            case LnsSetEpilogueBegin:
                state.EpilogueBegin = true;
                break;

            case LnsSetIsa:
                reader.Leb();
                break;

            default:
            {
                // A standard opcode this reader does not know, stepped over by
                // the operand count the header gave.
                nuint operands = opcode - 1u < standardLengths.Count
                               ? standardLengths[opcode - 1u] : 0u;
                for (nuint i = 0u; i < operands; i++)
                    reader.Leb();
                break;
            }
        }
    }

    return made;
}

void ResetLineMachine(LineMachine* state, bool defaultIsStmt, uint version)
{
    state->Address = 0u;
    // Version 5 numbers files from zero and puts the primary source file
    // there; earlier versions number from one. The starting value follows.
    state->File = 1u;
    state->Line = 1u;
    state->Column = 0u;
    state->IsStmt = defaultIsStmt;
    state->PrologueEnd = false;
    state->EpilogueBegin = false;
    state->OperationIndex = 0u;
}

/// The address advance shared by the special opcodes, `advance_pc` and
/// `const_add_pc`.
///
/// The operation index only matters on a VLIW target, where one instruction
/// holds several operations -- `maximum_operations_per_instruction` is one on
/// everything this compiler targets, which makes this a multiply. It is written
/// out because the day it is not one, a reader that assumed so is wrong
/// everywhere and obviously nowhere.
void AdvanceLineAddress(LineMachine* state, nuint advance, nuint minimumLength,
                        nuint operationsPerInstruction)
{
    nuint total = state->OperationIndex + advance;
    state->Address = state->Address
                   + minimumLength * (total / operationsPerInstruction);
    state->OperationIndex = total % operationsPerInstruction;
}

void AppendLineRow(LineTable table, LineMachine* state, bool endSequence)
{
    table.Rows.Add(new LineRow(state->Address, state->File, state->Line,
                               state->Column, state->IsStmt, endSequence,
                               state->PrologueEnd, state->EpilogueBegin));

    // These three last exactly one row, which is what makes them describe an
    // address rather than a stretch of code.
    state->PrologueEnd = false;
    state->EpilogueBegin = false;
}

/// The version 5 file table: a described format, then entries in it.
void ReadFileTableV5(Cursor reader, LineTable table, byte[] lineStr,
                     byte[] str, nuint offsetSize)
{
    // Directories first, then files, both in the same shape.
    var directories = new List<String>();
    ReadEntryListV5(reader, directories, null, lineStr, str, offsetSize);

    var names = new List<String>();
    var parents = new List<nuint>();
    ReadEntryListV5(reader, names, parents, lineStr, str, offsetSize);

    for (nuint i = 0u; i < names.Count; i++)
    {
        String name = names[i];
        nuint parent = i < parents.Count ? parents[i] : 0u;

        // An absolute name is its own answer; a relative one hangs off its
        // directory. Both separators are treated as one, because a Windows
        // build writes `C:\dir\obj\stdlib/Text.sl` -- backslashes from the
        // directory and a forward slash from what the compiler joined on.
        if (IsAbsolutePath(name) || parent >= directories.Count)
        {
            table.Files.Add(name);
            continue;
        }
        table.Files.Add(JoinPath(directories[parent], name));
    }
}

/// One of the version 5 tables: a format description, a count, then the
/// entries.
///
/// `parents` is filled with each entry's directory index when it is given,
/// and left alone when the caller passed null -- which the directory table
/// does, having no parents of its own.
void ReadEntryListV5(Cursor reader, List<String> into, List<nuint>? parents,
                     byte[] lineStr, byte[] str, nuint offsetSize)
{
    nuint columns = (nuint)reader.U8();
    var kinds = new List<uint>();
    var forms = new List<uint>();
    for (nuint i = 0u; i < columns; i++)
    {
        kinds.Add((uint)reader.Leb());
        forms.Add((uint)reader.Leb());
    }

    nuint count = (nuint)reader.Leb();
    for (nuint i = 0u; i < count; i++)
    {
        String name = "";
        nuint parent = 0u;

        for (nuint c = 0u; c < columns; c++)
        {
            uint kind = kinds[c];
            uint form = forms[c];

            if (kind == LnctPath)
            {
                name = ReadLineString(reader, form, lineStr, str, offsetSize);
                continue;
            }
            if (kind == LnctDirectoryIndex)
            {
                parent = (nuint)ReadLineNumber(reader, form, offsetSize);
                continue;
            }

            // A timestamp, a size, an MD5, or a column a later standard added:
            // stepped over by the same rule the entry reader uses.
            SkipForm(reader, form, 8u, offsetSize);
        }

        into.Add(name);
        if (parents != null)
            ((List<nuint>)parents).Add(parent);
    }
}

/// The version 4 file table: two runs of NUL-terminated strings, each ended by
/// an empty one.
void ReadFileTableV4(Cursor reader, LineTable table)
{
    var directories = new List<String>();
    // Index zero is the compilation directory, which is not in the list.
    directories.Add("");
    while (!reader.Overran)
    {
        String one = reader.CString();
        if (one.ByteLength() == 0u)
            break;
        directories.Add(one);
    }

    // Numbering starts at one, so index zero is a placeholder that no row
    // names -- keeping it makes `Files[row.File]` right without a subtraction
    // that would then have to be undone for version 5.
    table.Files.Add("");
    while (!reader.Overran)
    {
        String name = reader.CString();
        if (name.ByteLength() == 0u)
            break;
        nuint parent = (nuint)reader.Leb();
        reader.Leb();                                 // modification time
        reader.Leb();                                 // length

        if (IsAbsolutePath(name) || parent >= directories.Count
            || directories[parent].ByteLength() == 0u)
        {
            table.Files.Add(name);
            continue;
        }
        table.Files.Add(JoinPath(directories[parent], name));
    }
}

String ReadLineString(Cursor reader, uint form, byte[] lineStr, byte[] str,
                      nuint offsetSize)
{
    switch (form)
    {
        case FormString:
            return reader.CString();

        case FormLineStrp:
        {
            nuint offset = (nuint)ReadSectionOffset(reader, offsetSize);
            return offset < lineStr.Length ? ReadCStringAt(lineStr, offset) : "";
        }

        case FormStrp:
        {
            nuint offset = (nuint)ReadSectionOffset(reader, offsetSize);
            return offset < str.Length ? ReadCStringAt(str, offset) : "";
        }

        default:
            SkipForm(reader, form, 8u, offsetSize);
            return "";
    }
}

ulong ReadLineNumber(Cursor reader, uint form, nuint offsetSize)
{
    switch (form)
    {
        case FormData1: return (ulong)reader.U8();
        case FormData2: return (ulong)reader.U16();
        case FormData4: return (ulong)reader.U32();
        case FormData8: return reader.U64();
        case FormUdata: return reader.Leb();
        default:
            SkipForm(reader, form, 8u, offsetSize);
            return 0u;
    }
}

/// Whether a path names a place without needing a directory in front of it.
///
/// Both shapes, because a line table written on Windows and read on Linux is
/// an ordinary thing for a cross-compiler to produce.
bool IsAbsolutePath(String path)
{
    nuint length = path.ByteLength();
    if (length == 0u)
        return false;
    byte first = path.GetByteAt(0u);
    if (first == (byte)47 || first == (byte)92)       // '/' or '\'
        return true;
    // A drive letter, a colon, and a separator.
    if (length >= 3u && path.GetByteAt(1u) == (byte)58)  // ':'
    {
        byte third = path.GetByteAt(2u);
        return third == (byte)47 || third == (byte)92;
    }
    return false;
}

String JoinPath(String directory, String name)
{
    nuint length = directory.ByteLength();
    if (length == 0u)
        return name;
    byte last = directory.GetByteAt(length - 1u);
    if (last == (byte)47 || last == (byte)92)
        return directory + name;
    return directory + "/" + name;
}
