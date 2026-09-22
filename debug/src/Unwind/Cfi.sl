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

// DWARF call frame information: `.eh_frame`, which is a bytecode.
//
// **It builds a table nobody stores.** One row per address, one column per
// register, each cell saying where that register's value went -- and the table
// is described by a program that walks addresses forward and edits the row as
// it goes. Reading it means running that program up to the address in question
// and stopping.
//
// Three columns are enough to walk a stack: the **CFA**, which is the caller's
// stack pointer at the call; the return address; and the frame pointer, which
// the next frame's own rules are usually written against.
//
// **`.eh_frame` is not `.debug_frame`**, though the instruction set is one.
// The differences are all in the headers: a CIE is marked by a zero id rather
// than by ones, addresses are written in an encoding the augmentation data
// declares rather than plainly, and the section is loaded into the image, so
// a `pcrel` pointer is relative to where the bytes sit at run time. Getting
// the encoding wrong produces FDEs that cover plausible-looking addresses
// nowhere near the code.
module Debugger;

import Standard.Collections;
import Standard.Text;

// The instructions. The top two bits pick between three groups, which is why
// they are read before the rest of the byte.
const uint CfaAdvanceLoc        = 0x40u;    // high bits 01
const uint CfaOffset            = 0x80u;    // high bits 10
const uint CfaRestore           = 0xC0u;    // high bits 11

const uint CfaNop               = 0x00u;
const uint CfaSetLoc            = 0x01u;
const uint CfaAdvanceLoc1       = 0x02u;
const uint CfaAdvanceLoc2       = 0x03u;
const uint CfaAdvanceLoc4       = 0x04u;
const uint CfaOffsetExtended    = 0x05u;
const uint CfaRestoreExtended   = 0x06u;
const uint CfaUndefined         = 0x07u;
const uint CfaSameValue         = 0x08u;
const uint CfaRegister          = 0x09u;
const uint CfaRememberState     = 0x0Au;
const uint CfaRestoreState      = 0x0Bu;
const uint CfaDefCfa            = 0x0Cu;
const uint CfaDefCfaRegister    = 0x0Du;
const uint CfaDefCfaOffset      = 0x0Eu;
const uint CfaDefCfaExpression  = 0x0Fu;
const uint CfaExpression        = 0x10u;
const uint CfaOffsetExtendedSf  = 0x11u;
const uint CfaDefCfaSf          = 0x12u;
const uint CfaDefCfaOffsetSf    = 0x13u;
const uint CfaValOffset         = 0x14u;
const uint CfaValOffsetSf       = 0x15u;
const uint CfaValExpression     = 0x16u;

// `DW_EH_PE_*`: how an address in `.eh_frame` is written.
const uint PeAbsptr   = 0x00u;
const uint PeUleb128  = 0x01u;
const uint PeUdata2   = 0x02u;
const uint PeUdata4   = 0x03u;
const uint PeUdata8   = 0x04u;
const uint PeSigned   = 0x08u;
const uint PeSleb128  = 0x09u;
const uint PeSdata2   = 0x0Au;
const uint PeSdata4   = 0x0Bu;
const uint PeSdata8   = 0x0Cu;
const uint PePcrel    = 0x10u;
const uint PeTextrel  = 0x20u;
const uint PeDatarel  = 0x30u;
const uint PeFuncrel  = 0x40u;
const uint PeAligned  = 0x50u;
const uint PeIndirect = 0x80u;
const uint PeOmit     = 0xFFu;

/// Where one register's value went, as a row of the table says.
enum CfiRule
{
    /// Nothing said. For a callee-saved register that means it was not
    /// touched; for the return address it means the frame is the last one.
    Unset,
    /// At the CFA plus an offset.
    AtCfaOffset,
    /// In another register.
    InRegister,
    /// Explicitly unchanged.
    Same,
    /// Explicitly nowhere, which for the return address is the end of a stack.
    Undefined,
    /// Described by a DWARF expression, which this engine does not run.
    Expression,
}

/// One row of the table: what the CFA is, and where two registers went.
///
/// Two registers and not sixteen, because two are what a stack walk needs: the
/// return address, and the frame pointer the next frame's CFA is usually
/// written against. A rule naming any other register is carried as far as
/// saying so, and refused.
class CfiRow
{
    /// The register the CFA is measured from, and by how much.
    public ulong CfaRegister;
    public long CfaOffset;
    public bool CfaIsExpression;

    public CfiRule ReturnRule;
    public long ReturnOffset;
    public ulong ReturnRegister;

    public CfiRule FramePointerRule;
    public long FramePointerOffset;
    public ulong FramePointerRegister;

    /// Set when the program named a register this row does not carry, so that
    /// a wrong answer is never given in place of no answer.
    public bool Unreadable;

    public CfiRow()
    {
        CfaRegister = CfiRegisterRsp;
        CfaOffset = 0;
        CfaIsExpression = false;
        ReturnRule = CfiRule.Unset;
        ReturnOffset = 0;
        ReturnRegister = 0u;
        FramePointerRule = CfiRule.Unset;
        FramePointerOffset = 0;
        FramePointerRegister = 0u;
        Unreadable = false;
    }

    public CfiRow Copy()
    {
        var made = new CfiRow();
        made.CfaRegister = CfaRegister;
        made.CfaOffset = CfaOffset;
        made.CfaIsExpression = CfaIsExpression;
        made.ReturnRule = ReturnRule;
        made.ReturnOffset = ReturnOffset;
        made.ReturnRegister = ReturnRegister;
        made.FramePointerRule = FramePointerRule;
        made.FramePointerOffset = FramePointerOffset;
        made.FramePointerRegister = FramePointerRegister;
        made.Unreadable = Unreadable;
        return made;
    }
}

/// A common information entry: what a group of FDEs share.
class Cie
{
    public long CodeAlignment;
    public long DataAlignment;
    public ulong ReturnRegister;

    /// How an FDE writes its addresses.
    public uint PointerEncoding;

    /// Where the shared instructions are, and how far they run.
    public nuint InstructionsAt;
    public nuint InstructionsEnd;

    public Cie()
    {
        CodeAlignment = 1;
        DataAlignment = 1;
        ReturnRegister = CfiReturnAddress;
        PointerEncoding = PeAbsptr;
        InstructionsAt = 0u;
        InstructionsEnd = 0u;
    }
}

/// The caller of a frame, by what `.eh_frame` says about it.
Caller? CallerByCfi(Unwinder table, ITarget target, Registers frame,
                    nuint linked, nuint slide)
{
    var row = RowAt(table, linked);
    if (row == null)
        return null;

    var rules = (CfiRow)row;
    if (rules.Unreadable || rules.CfaIsExpression)
        return null;

    nuint cfa = 0u;
    if (!RegisterOf(rules.CfaRegister, frame, &cfa))
        return null;
    cfa = (nuint)((long)cfa + rules.CfaOffset);

    // The return address. `Undefined` is the outermost frame and is an answer;
    // `Unset` is a frame whose CIE said nothing, which is not.
    if (rules.ReturnRule == CfiRule.Undefined)
        return null;

    nuint returnTo = 0u;
    if (rules.ReturnRule == CfiRule.AtCfaOffset)
    {
        if (!ReadStackWord(target, (nuint)((long)cfa + rules.ReturnOffset),
                           &returnTo))
            return null;
    }
    else if (rules.ReturnRule == CfiRule.InRegister)
    {
        if (!RegisterOf(rules.ReturnRegister, frame, &returnTo))
            return null;
    }
    else
    {
        return null;
    }

    // The caller's frame pointer, which its own CFA rule may be written
    // against. Untouched by this frame is the common case and is right.
    nuint framePointer = frame.FramePointer;
    if (rules.FramePointerRule == CfiRule.AtCfaOffset)
    {
        if (!ReadStackWord(target,
                           (nuint)((long)cfa + rules.FramePointerOffset),
                           &framePointer))
            return null;
    }
    else if (rules.FramePointerRule == CfiRule.InRegister)
    {
        if (!RegisterOf(rules.FramePointerRegister, frame, &framePointer))
            return null;
    }

    // **The CFA is the caller's stack pointer**, by definition: it is the
    // value the stack pointer had at the call site, before `call` pushed
    // anything.
    return new Caller(returnTo, cfa, framePointer);
}

/// One of the three registers this engine carries.
bool RegisterOf(ulong which, Registers frame, nuint* value)
{
    switch (which)
    {
        case CfiRegisterRsp:
            *value = frame.StackPointer;
            return true;
        case CfiRegisterRbp:
            *value = frame.FramePointer;
            return true;
        default:
            return false;
    }
}

/// One entry of `.eh_frame`, as far as naming what it covers.
public class UnwindEntry
{
    /// Where in the section it starts.
    public nuint Offset;

    /// "CIE", or the range an FDE covers.
    public bool IsCie;
    public nuint Begin;
    public nuint Range;

    /// Empty when the entry was read. Otherwise why it was not.
    public String Problem;

    public UnwindEntry(nuint offset, bool isCie, nuint begin, nuint range,
                       String problem)
    {
        Offset = offset;
        IsCie = isCie;
        Begin = begin;
        Range = range;
        Problem = problem;
    }
}

/// Every entry of `.eh_frame`, in the order the section has them.
///
/// For a reader checking this against `llvm-dwarfdump --eh-frame` rather than
/// trusting it. An FDE covering an address no code is at is what a wrong
/// pointer encoding looks like, and nothing else shows it.
public List<UnwindEntry> UnwindEntries(Unwinder table)
{
    var found = new List<UnwindEntry>();

    byte[] data = table.EhFrame;
    nuint sectionAt = table.EhFrameAddress;
    nuint at = 0u;

    while (at + 4u <= data.Length)
    {
        nuint start = at;
        ulong length = LittleEndianAt(data, at, 4u);
        at = at + 4u;

        if (length == 0u)
            break;
        if (length == 0xFFFFFFFFu)
        {
            found.Add(new UnwindEntry(start, false, 0u, 0u,
                                      "64-bit entry, which this does not read"));
            break;
        }

        nuint end = at + (nuint)length;
        if (end > data.Length)
        {
            found.Add(new UnwindEntry(start, false, 0u, 0u, "runs past the section"));
            break;
        }

        if (LittleEndianAt(data, at, 4u) == 0u)
        {
            found.Add(new UnwindEntry(start, true, 0u, 0u, ""));
            at = end;
            continue;
        }

        ulong id = LittleEndianAt(data, at, 4u);
        var cie = ReadCie(data, (at + 4u) - (nuint)id - 4u);
        if (cie == null)
        {
            found.Add(new UnwindEntry(start, false, 0u, 0u, "no CIE"));
            at = end;
            continue;
        }

        nuint after = at + 4u;
        nuint begin = 0u;
        nuint range = 0u;
        if (!ReadEncoded(data, sectionAt, ((Cie)cie).PointerEncoding, &after,
                         &begin)
            || !ReadEncoded(data, sectionAt, ((Cie)cie).PointerEncoding & 0x0Fu,
                            &after, &range))
        {
            found.Add(new UnwindEntry(start, false, 0u, 0u,
                                      "an address this does not decode"));
            at = end;
            continue;
        }

        found.Add(new UnwindEntry(start, false, begin, range, ""));
        at = end;
    }

    return found;
}

/// Runs the table's program up to one address.
///
/// Scans the entries in order. `.eh_frame_hdr` carries a sorted index that
/// would make this a binary search, and is not read: a stack is thirty frames
/// and a program is a few hundred functions, which is a scan nobody notices
/// beside the process reads each frame already costs.
CfiRow? RowAt(Unwinder table, nuint linked)
{
    byte[] data = table.EhFrame;
    nuint sectionAt = table.EhFrameAddress;
    nuint at = 0u;

    while (at + 4u <= data.Length)
    {
        nuint start = at;
        ulong length = LittleEndianAt(data, at, 4u);
        at = at + 4u;

        // A zero length terminates the section. The 64-bit form is not emitted
        // for `.eh_frame` by anything this reads, and is refused rather than
        // read as a short one.
        if (length == 0u)
            break;
        if (length == 0xFFFFFFFFu)
            return null;

        nuint end = at + (nuint)length;
        if (end > data.Length)
            break;

        ulong id = LittleEndianAt(data, at, 4u);
        if (id == 0u)
        {
            // A CIE. Skipped here; an FDE reads the one it points at.
            at = end;
            continue;
        }

        // An FDE. Its `CIE_pointer` counts backwards from its own position.
        nuint ciePointer = (at + 4u) - (nuint)id - 4u;
        var found = ReadCie(data, ciePointer);
        if (found == null)
        {
            at = end;
            continue;
        }
        var cie = (Cie)found;

        nuint after = at + 4u;
        nuint begin = 0u;
        nuint range = 0u;
        if (!ReadEncoded(data, sectionAt, cie.PointerEncoding, &after, &begin)
            || !ReadEncoded(data, sectionAt, cie.PointerEncoding & 0x0Fu,
                            &after, &range))
        {
            at = end;
            continue;
        }

        if (linked < begin || linked >= begin + range)
        {
            at = end;
            continue;
        }

        // The augmentation data, whose length is a LEB when the CIE said "z".
        if (cie.PointerEncoding != PeOmit)
        {
            var reader = new Cursor(data, after);
            ulong augmentation = reader.Leb();
            after = reader.Offset + (nuint)augmentation;
        }

        var row = new CfiRow();
        RunInstructions(data, cie.InstructionsAt, cie.InstructionsEnd, cie,
                        begin, linked, row, true);

        var initial = row.Copy();
        RunInstructions(data, after, end, cie, begin, linked, row, false);
        row.ReturnRegister = row.ReturnRegister;

        // An FDE that never reached the address is still the right FDE: the
        // row as it stands is what the table says there.
        return row;
    }

    return null;
}

/// Reads a CIE's header, or null when it is not one.
Cie? ReadCie(byte[] data, nuint at)
{
    if (at + 9u > data.Length)
        return null;

    ulong length = LittleEndianAt(data, at, 4u);
    if (length == 0u || length == 0xFFFFFFFFu)
        return null;

    nuint end = at + 4u + (nuint)length;
    if (end > data.Length)
        return null;

    if (LittleEndianAt(data, at + 4u, 4u) != 0u)
        return null;

    var made = new Cie();
    var reader = new Cursor(data, at + 8u);

    byte version = reader.U8();
    if (version != (byte)1 && version != (byte)3)
        return null;

    String augmentation = reader.CString();

    made.CodeAlignment = (long)reader.Leb();
    made.DataAlignment = reader.SLeb();

    // Version 1 writes the return register as one byte; later versions as a
    // LEB. Reading the wrong one shifts everything after it.
    made.ReturnRegister = version == (byte)1 ? (ulong)reader.U8() : reader.Leb();

    // `z` opens an augmentation block whose length is a LEB, and the letters
    // after it say what is in it. Without it there is no block at all and no
    // pointer encoding to find -- which is `absptr`, the default.
    if (augmentation.ByteLength() != 0u && augmentation.GetByteAt(0u) == (byte)'z')
    {
        ulong size = reader.Leb();
        nuint blockEnd = reader.Offset + (nuint)size;

        for (nuint i = 1u; i < augmentation.ByteLength(); i++)
        {
            byte letter = augmentation.GetByteAt(i);

            if (letter == (byte)'R')
            {
                made.PointerEncoding = (uint)reader.U8();
                continue;
            }
            if (letter == (byte)'P')
            {
                // A personality routine, written in an encoding of its own.
                uint encoding = (uint)reader.U8();
                nuint ignored = 0u;
                nuint where = reader.Offset;
                if (!ReadEncoded(data, 0u, encoding, &where, &ignored))
                    return null;
                reader = new Cursor(data, where);
                continue;
            }
            if (letter == (byte)'L')
            {
                reader.U8();
                continue;
            }
            if (letter == (byte)'S')
                continue;

            // A letter nothing here knows: the rest of the block cannot be
            // walked, so the encoding is whatever was read before it.
            break;
        }

        made.InstructionsAt = blockEnd;
    }
    else
    {
        made.InstructionsAt = reader.Offset;
    }

    made.InstructionsEnd = end;
    return made;
}

/// Runs a run of instructions, stopping when the program counter passes the
/// address asked about.
///
/// `initial` says these are a CIE's, which never advance and always apply.
void RunInstructions(byte[] data, nuint at, nuint end, Cie cie, nuint begin,
                     nuint wanted, CfiRow row, bool initial)
{
    var reader = new Cursor(data, at);
    nuint where = begin;

    var stack = new List<CfiRow>();

    while (reader.Offset < end && !reader.Overran)
    {
        uint code = (uint)reader.U8();
        uint high = code & 0xC0u;
        uint low = code & 0x3Fu;

        if (high == CfaAdvanceLoc)
        {
            where = where + (nuint)((long)low * cie.CodeAlignment);
            if (!initial && where > wanted)
                return;
            continue;
        }

        if (high == CfaOffset)
        {
            long offset = (long)reader.Leb() * cie.DataAlignment;
            Remember(row, (ulong)low, CfiRule.AtCfaOffset, offset, 0u, cie);
            continue;
        }

        if (high == CfaRestore)
        {
            // Back to what the CIE said, which for everything this reads is
            // nothing at all.
            Remember(row, (ulong)low, CfiRule.Unset, 0, 0u, cie);
            continue;
        }

        switch (low)
        {
            case CfaNop:
                break;

            case CfaSetLoc:
            {
                nuint address = 0u;
                nuint here = reader.Offset;
                if (!ReadEncoded(data, 0u, cie.PointerEncoding & 0x0Fu, &here,
                                 &address))
                {
                    row.Unreadable = true;
                    return;
                }
                reader = new Cursor(data, here);
                where = address;
                if (!initial && where > wanted)
                    return;
                break;
            }

            case CfaAdvanceLoc1:
            {
                where = where + (nuint)((long)reader.U8() * cie.CodeAlignment);
                if (!initial && where > wanted)
                    return;
                break;
            }

            case CfaAdvanceLoc2:
            {
                where = where + (nuint)((long)reader.U16() * cie.CodeAlignment);
                if (!initial && where > wanted)
                    return;
                break;
            }

            case CfaAdvanceLoc4:
            {
                where = where + (nuint)((long)reader.U32() * cie.CodeAlignment);
                if (!initial && where > wanted)
                    return;
                break;
            }

            case CfaOffsetExtended:
            {
                ulong which = reader.Leb();
                long offset = (long)reader.Leb() * cie.DataAlignment;
                Remember(row, which, CfiRule.AtCfaOffset, offset, 0u, cie);
                break;
            }

            case CfaOffsetExtendedSf:
            {
                ulong which = reader.Leb();
                long offset = reader.SLeb() * cie.DataAlignment;
                Remember(row, which, CfiRule.AtCfaOffset, offset, 0u, cie);
                break;
            }

            case CfaRestoreExtended:
                Remember(row, reader.Leb(), CfiRule.Unset, 0, 0u, cie);
                break;

            case CfaUndefined:
                Remember(row, reader.Leb(), CfiRule.Undefined, 0, 0u, cie);
                break;

            case CfaSameValue:
                Remember(row, reader.Leb(), CfiRule.Same, 0, 0u, cie);
                break;

            case CfaRegister:
            {
                ulong which = reader.Leb();
                ulong holding = reader.Leb();
                Remember(row, which, CfiRule.InRegister, 0, holding, cie);
                break;
            }

            case CfaRememberState:
                stack.Add(row.Copy());
                break;

            case CfaRestoreState:
            {
                if (stack.IsEmpty)
                    break;
                var saved = stack[stack.Count - 1u];
                stack.RemoveAt(stack.Count - 1u);
                CopyInto(saved, row);
                break;
            }

            case CfaDefCfa:
            {
                row.CfaRegister = reader.Leb();
                row.CfaOffset = (long)reader.Leb();
                row.CfaIsExpression = false;
                break;
            }

            case CfaDefCfaSf:
            {
                row.CfaRegister = reader.Leb();
                row.CfaOffset = reader.SLeb() * cie.DataAlignment;
                row.CfaIsExpression = false;
                break;
            }

            case CfaDefCfaRegister:
                row.CfaRegister = reader.Leb();
                break;

            case CfaDefCfaOffset:
                row.CfaOffset = (long)reader.Leb();
                break;

            case CfaDefCfaOffsetSf:
                row.CfaOffset = reader.SLeb() * cie.DataAlignment;
                break;

            case CfaDefCfaExpression:
            {
                // A CFA this engine does not compute. Skipped rather than
                // guessed, and the row says so.
                ulong size = reader.Leb();
                reader.Skip((nuint)size);
                row.CfaIsExpression = true;
                break;
            }

            case CfaExpression:
            case CfaValExpression:
            {
                ulong which = reader.Leb();
                ulong size = reader.Leb();
                reader.Skip((nuint)size);
                Remember(row, which, CfiRule.Expression, 0, 0u, cie);
                break;
            }

            case CfaValOffset:
            {
                ulong which = reader.Leb();
                reader.Leb();
                Remember(row, which, CfiRule.Expression, 0, 0u, cie);
                break;
            }

            case CfaValOffsetSf:
            {
                ulong which = reader.Leb();
                reader.SLeb();
                Remember(row, which, CfiRule.Expression, 0, 0u, cie);
                break;
            }

            default:
                // An instruction with no skip rule loses the position, and
                // everything after it is nonsense that still looks like
                // instructions. The row says it cannot be trusted.
                row.Unreadable = true;
                return;
        }
    }
}

/// Files a rule under the column it belongs to, or notes that there is no such
/// column.
///
/// **A register this row does not carry is not ignored.** A rule saying the
/// frame pointer moved into `r12` is a rule this engine cannot follow, and
/// answering as though nothing was said gives a frame pointer that is somebody
/// else's.
void Remember(CfiRow row, ulong which, CfiRule rule, long offset,
              ulong holding, Cie cie)
{
    if (which == cie.ReturnRegister)
    {
        row.ReturnRule = rule;
        row.ReturnOffset = offset;
        row.ReturnRegister = holding;
        if (rule == CfiRule.InRegister && holding != CfiRegisterRsp
            && holding != CfiRegisterRbp)
            row.Unreadable = true;
        return;
    }

    if (which == CfiRegisterRbp)
    {
        row.FramePointerRule = rule;
        row.FramePointerOffset = offset;
        row.FramePointerRegister = holding;
        if (rule == CfiRule.InRegister && holding != CfiRegisterRsp
            && holding != CfiRegisterRbp)
            row.Unreadable = true;
        return;
    }

    // Every other register is one this engine does not carry and does not
    // need: it is not the CFA's base and not the return address.
}

void CopyInto(CfiRow from, CfiRow into)
{
    into.CfaRegister = from.CfaRegister;
    into.CfaOffset = from.CfaOffset;
    into.CfaIsExpression = from.CfaIsExpression;
    into.ReturnRule = from.ReturnRule;
    into.ReturnOffset = from.ReturnOffset;
    into.ReturnRegister = from.ReturnRegister;
    into.FramePointerRule = from.FramePointerRule;
    into.FramePointerOffset = from.FramePointerOffset;
    into.FramePointerRegister = from.FramePointerRegister;
    into.Unreadable = from.Unreadable;
}

/// One address in whichever encoding `DW_EH_PE_*` named.
///
/// `sectionAt` is where the section was linked to sit, which is what a
/// `pcrel` pointer is relative to -- the *address* of the bytes being read,
/// not their offset in the file.
public bool ReadEncodedPointer(byte[] data, nuint sectionAt, uint encoding,
                              nuint* at, nuint* value)
    => ReadEncoded(data, sectionAt, encoding, at, value);

bool ReadEncoded(byte[] data, nuint sectionAt, uint encoding, nuint* at,
                 nuint* value)
{
    if (encoding == PeOmit)
        return false;

    nuint from = *at;
    var reader = new Cursor(data, from);

    ulong raw = 0u;
    uint format = encoding & 0x0Fu;

    switch (format)
    {
        case PeAbsptr:
            raw = reader.U64();
            break;
        case PeUleb128:
            raw = reader.Leb();
            break;
        case PeUdata2:
            raw = (ulong)reader.U16();
            break;
        case PeUdata4:
            raw = (ulong)reader.U32();
            break;
        case PeUdata8:
            raw = reader.U64();
            break;
        case PeSleb128:
            raw = (ulong)reader.SLeb();
            break;
        case PeSdata2:
            raw = (ulong)(long)(short)(ushort)reader.U16();
            break;
        case PeSdata4:
            raw = (ulong)(long)(int)(uint)reader.U32();
            break;
        case PeSdata8:
            raw = reader.U64();
            break;
        default:
            return false;
    }

    if (reader.Overran)
        return false;

    // Relative to where the pointer itself sits, which is the only application
    // this reads: `pcrel` is what lld emits for an FDE's initial location.
    uint application = encoding & 0x70u;
    if (application == PePcrel)
        raw = raw + (ulong)(sectionAt + from);
    else if (application == PeDatarel || application == PeTextrel
             || application == PeFuncrel || application == PeAligned)
        return false;

    // An indirect pointer names a cell in the image holding the real one,
    // which is a read this cannot do from the file alone.
    if ((encoding & PeIndirect) != 0u)
        return false;

    *at = reader.Offset;
    *value = (nuint)raw;
    return true;
}
