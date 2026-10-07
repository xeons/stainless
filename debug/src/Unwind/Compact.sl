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

// `__unwind_info`, Apple's compact unwind table.
//
// Apple's linker turns each function's CFI into one 32-bit encoding and
// leaves `__eh_frame` only for what an encoding cannot say. A Mac executable
// from this compiler carries no `__eh_frame` at all.
//
// The table is two levels. The first is an index of pages by function offset.
// A page is "regular", a run of (offset, encoding) pairs, or "compressed",
// where each entry packs a 24-bit offset from the page's base and an 8-bit
// index into the common encodings, then the page's own. Offsets are from the
// image base, which is the Mach header.
//
// A function in FRAME mode is answered from its frame record, the same two
// loads the frame-pointer walk makes. That is wrong for the few instructions
// of a prologue or epilogue, where the record is not yet or no longer there.
module Debugger;

import Standard.Collections;
import Standard.Text;

/// `UNWIND_SECOND_LEVEL_REGULAR` and `UNWIND_SECOND_LEVEL_COMPRESSED`.
const uint CompactPageRegular = 2u;
const uint CompactPageCompressed = 3u;

/// The bits of an encoding that say how the rest is read.
public const uint CompactUnwindModeMask = 0x0F000000u;

/// The size of the section header, and of one first-level index entry.
const nuint CompactHeaderSize = 28u;
const nuint CompactIndexEntrySize = 12u;

/// One function's line in the table.
public class CompactEntry
{
    /// Where the function starts, as an offset from the image base.
    public nuint FunctionOffset;
    public uint Encoding;

    public CompactEntry(nuint functionOffset, uint encoding)
    {
        FunctionOffset = functionOffset;
        Encoding = encoding;
    }
}

/// Every second-level entry, in address order.
///
/// Consecutive functions with one encoding share an entry, so this is not one
/// line per function. `llvm-objdump --macho --unwind-info` lists the same.
public List<CompactEntry> ReadCompactEntries(byte[] info)
{
    var made = new List<CompactEntry>();
    if (info.Length < CompactHeaderSize || LittleEndianAt(info, 0u, 4u) != 1u)
        return made;

    nuint indexAt = (nuint)LittleEndianAt(info, 20u, 4u);
    nuint indexCount = (nuint)LittleEndianAt(info, 24u, 4u);

    // The last index entry is a sentinel marking the end of the text.
    for (nuint i = 0u; i + 1u < indexCount; i++)
    {
        nuint at = indexAt + i * CompactIndexEntrySize;
        if (!BytesRemainAt(info, at, CompactIndexEntrySize))
            break;
        nuint base2 = (nuint)LittleEndianAt(info, at, 4u);
        nuint page = (nuint)LittleEndianAt(info, at + 4u, 4u);
        if (page != 0u)
            AddCompactPage(info, page, base2, made);
    }
    return made;
}

/// The entries of one second-level page.
void AddCompactPage(byte[] info, nuint page, nuint base2, List<CompactEntry> into)
{
    if (!BytesRemainAt(info, page, 8u))
        return;

    uint kind = (uint)LittleEndianAt(info, page, 4u);
    nuint entriesAt = page + (nuint)LittleEndianAt(info, page + 4u, 2u);
    nuint count = (nuint)LittleEndianAt(info, page + 6u, 2u);

    switch (kind)
    {
        case CompactPageRegular:
            for (nuint i = 0u; i < count; i++)
            {
                nuint at = entriesAt + i * 8u;
                if (!BytesRemainAt(info, at, 8u))
                    return;
                into.Add(new CompactEntry((nuint)LittleEndianAt(info, at, 4u),
                                          (uint)LittleEndianAt(info, at + 4u, 4u)));
            }
            return;

        case CompactPageCompressed:
        {
            if (!BytesRemainAt(info, page, 12u))
                return;
            nuint ownAt = page + (nuint)LittleEndianAt(info, page + 8u, 2u);
            nuint ownCount = (nuint)LittleEndianAt(info, page + 10u, 2u);
            nuint commonAt = (nuint)LittleEndianAt(info, 4u, 4u);
            nuint commonCount = (nuint)LittleEndianAt(info, 8u, 4u);

            for (nuint i = 0u; i < count; i++)
            {
                nuint at = entriesAt + i * 4u;
                if (!BytesRemainAt(info, at, 4u))
                    return;
                uint packed = (uint)LittleEndianAt(info, at, 4u);
                nuint which = (nuint)(packed >> 24);

                nuint encodingAt = which < commonCount
                                 ? commonAt + which * 4u
                                 : ownAt + (which - commonCount) * 4u;
                if (which >= commonCount + ownCount || !BytesRemainAt(info, encodingAt, 4u))
                    return;

                into.Add(new CompactEntry(base2 + (nuint)(packed & 0x00FFFFFFu),
                                          (uint)LittleEndianAt(info, encodingAt, 4u)));
            }
            return;
        }

        default:
            return;
    }
}

/// The encoding covering a link-time address, or false when the table has
/// none or says zero, which is "nothing is known about this function".
public bool FindCompactEncoding(Unwinder table, nuint linked, uint* encoding)
{
    if (linked < table.Image.PreferredBase)
        return false;
    nuint offset = linked - table.Image.PreferredBase;

    var entries = table.CompactEntries;
    if (entries.Count == 0u || offset < entries[0u].FunctionOffset
        || offset >= table.CompactEnd)
        return false;

    // The last entry that starts at or before the address.
    nuint low = 0u;
    nuint high = entries.Count;
    while (high - low > 1u)
    {
        nuint middle = low + (high - low) / 2u;
        if (entries[middle].FunctionOffset <= offset)
            low = middle;
        else
            high = middle;
    }

    *encoding = entries[low].Encoding;
    return *encoding != 0u;
}

/// Where the first-level index says the described text ends, as an offset
/// from the image base.
public nuint ReadCompactEnd(byte[] info)
{
    if (info.Length < CompactHeaderSize)
        return 0u;
    nuint indexAt = (nuint)LittleEndianAt(info, 20u, 4u);
    nuint indexCount = (nuint)LittleEndianAt(info, 24u, 4u);
    if (indexCount == 0u)
        return 0u;
    nuint last = indexAt + (indexCount - 1u) * CompactIndexEntrySize;
    if (!BytesRemainAt(info, last, 4u))
        return 0u;
    return (nuint)LittleEndianAt(info, last, 4u);
}

/// The caller of a frame, by what `__unwind_info` says about it.
Caller? CallerByCompact(Unwinder table, ITarget target, Registers frame,
                        nuint linked, nuint slide)
{
    uint encoding = 0u;
    if (!FindCompactEncoding(table, linked, &encoding))
        return null;

    switch (encoding & CompactUnwindModeMask)
    {
        case CompactUnwindModeFrame:
        {
            nuint framePointer = frame.FramePointer;
            nuint returnTo = 0u;
            nuint callerFrame = 0u;
            if (framePointer == 0u
                || !ReadStackWord(target, framePointer + 8u, &returnTo)
                || !ReadStackWord(target, framePointer, &callerFrame))
                return null;
            return new Caller(returnTo, framePointer + 16u, callerFrame);
        }

        case CompactUnwindModeFrameless:
        {
            // The return address never left the link register, so this
            // answers for frame zero and refuses above it.
            nuint returnTo = 0u;
            if (!ReadDwarfRegister(frame, DwarfRegisterLink, &returnTo))
                return null;
            nuint size = (nuint)((encoding >> 12) & 0xFFFu) * 16u;
            return new Caller(returnTo, frame.StackPointer + size, frame.FramePointer);
        }

        case CompactUnwindModeDwarf:
            return CallerByCfi(table, target, frame, linked, slide);

        default:
            return null;
    }
}
