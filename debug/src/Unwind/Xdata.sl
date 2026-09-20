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

// Windows x64 unwinding: `.pdata` says which function, `UNWIND_INFO` says what
// its prologue did.
//
// **It is a list of operations to undo, not a table to look up.** The codes
// are stored with the *last* prologue operation first, each tagged with how far
// into the prologue it had happened by. So a reader walks them in order,
// applies every one whose offset is at or below where the program counter is,
// and arrives at the stack pointer the function was entered with. The return
// address is the word there, because `call` pushed it and nothing below is
// still outstanding.
//
// **A frame that has not finished its prologue is the case that needs the
// offsets.** A stop one instruction into a function has not pushed anything
// yet, and undoing a push that never happened moves the stack pointer eight
// bytes into somebody else's frame -- which reads a return address that is
// whatever was there.
//
// Reference: the x64 exception handling documentation, and `RtlVirtualUnwind`,
// which is what does this for real. This is the subset the compiler and the C
// runtime emit; anything else is refused rather than guessed.
module Debugger;

import Standard.Collections;
import Standard.Text;

/// `UNWIND_INFO.Flags`.
const uint UnwindFlagChainInfo = 0x4u;

/// The operations, in the low nibble of a code's second byte.
const uint UwopPushNonVolatile = 0u;
const uint UwopAllocLarge      = 1u;
const uint UwopAllocSmall      = 2u;
const uint UwopSetFramePointer = 3u;
const uint UwopSaveNonVolatile = 4u;
const uint UwopSaveNonVolatileFar = 5u;
const uint UwopEpilogue        = 6u;
const uint UwopSpare           = 7u;
const uint UwopSaveXmm128      = 8u;
const uint UwopSaveXmm128Far   = 9u;
const uint UwopPushMachineFrame = 10u;

/// The instruction encoding's number for RBP, which is what an unwind code
/// carries -- not DWARF's.
const uint MachineRegisterRbp = 5u;

/// How deep a chain of `UNW_FLAG_CHAININFO` may go before it is a cycle.
const int MostChainedRecords = 8;

/// One `RUNTIME_FUNCTION`: three addresses, relative to the image base.
class RuntimeFunction
{
    public nuint Begin;
    public nuint End;
    public nuint Info;

    public RuntimeFunction(nuint begin, nuint end, nuint info)
    {
        Begin = begin;
        End = end;
        Info = info;
    }
}

/// The caller of a frame, by what its prologue did.
Caller? CallerByXdata(Unwinder table, ITarget target, Registers frame,
                      nuint linked, nuint slide)
{
    var found = FunctionCovering(table, linked);
    if (found == null)
        return null;

    nuint stack = frame.StackPointer;
    nuint framePointer = frame.FramePointer;

    if (!UndoPrologue(table, target, (RuntimeFunction)found, linked, slide,
                      &stack, &framePointer, 0))
        return null;

    // Whatever the prologue did, `call` pushed the return address and it is
    // still where it was put.
    nuint returnTo = 0u;
    if (!ReadStackWord(target, stack, &returnTo))
        return null;

    return new Caller(returnTo, stack + 8u, framePointer);
}

/// Which `RUNTIME_FUNCTION` covers a link-time address.
///
/// `.pdata` is sorted, so this is a binary search -- which matters: a stack of
/// thirty frames through a program with four hundred functions is thirty scans
/// otherwise, at every stop.
RuntimeFunction? FunctionCovering(Unwinder table, nuint linked)
{
    int found = RuntimeFunctionIndexAt(table.Pdata,
                                       linked - table.Image.PreferredBase);
    return found < 0 ? null : RuntimeFunctionAt(table.Pdata, (nuint)found);
}

/// Which record of a `.pdata` covers an image-relative address, by index, or
/// -1.
///
/// The search on its own, for a test that has a table and no binary. The
/// off-by-one lives here rather than in the reading: a record covers its first
/// byte and not the one past its last.
public int RuntimeFunctionIndexAt(byte[] pdata, nuint rva)
{
    nuint count = pdata.Length / 12u;
    nuint low = 0u;
    nuint high = count;

    while (low < high)
    {
        nuint middle = low + (high - low) / 2u;
        var one = RuntimeFunctionAt(pdata, middle);

        if (rva < one.Begin)
        {
            high = middle;
            continue;
        }
        if (rva >= one.End)
        {
            low = middle + 1u;
            continue;
        }
        return (int)middle;
    }
    return -1;
}

/// How many two-byte slots an unwind code occupies, for a test that has no
/// binary. `SlotsOf` by another name, and the name a caller outside can use.
public nuint UnwindCodeSlots(uint operation, uint operand)
    => SlotsOf(operation, operand);

RuntimeFunction RuntimeFunctionAt(byte[] pdata, nuint index)
{
    nuint at = index * 12u;
    return new RuntimeFunction((nuint)LittleEndianAt(pdata, at, 4u),
                               (nuint)LittleEndianAt(pdata, at + 4u, 4u),
                               (nuint)LittleEndianAt(pdata, at + 8u, 4u));
}

/// Runs a function's unwind codes backwards over the stack pointer.
///
/// `stack` goes in as the stack pointer at the stop and comes out as the one
/// the function was entered with; `framePointer` is corrected when the
/// prologue saved the caller's.
bool UndoPrologue(Unwinder table, ITarget target, RuntimeFunction where,
                  nuint linked, nuint slide, nuint* stack,
                  nuint* framePointer, int depth)
{
    if (depth > MostChainedRecords)
        return false;

    byte[] xdata = new byte[0u];
    nuint at = 0u;
    if (!table.BytesAt(table.Image.PreferredBase + where.Info, &xdata, &at))
        return false;
    if (at + 4u > xdata.Length)
        return false;

    uint first = (uint)xdata[at];
    uint version = first & 7u;
    uint flags = (first >> 3) & 0x1Fu;
    if (version != 1u)
        return false;

    nuint prologueSize = (nuint)xdata[at + 1u];
    nuint codeCount = (nuint)xdata[at + 2u];
    uint frameRegister = (uint)xdata[at + 3u] & 0xFu;
    uint frameOffset = ((uint)xdata[at + 3u] >> 4) & 0xFu;

    nuint codes = at + 4u;
    if (codes + codeCount * 2u > xdata.Length)
        return false;

    // How far into the prologue the program counter is. Past its end, every
    // operation has happened.
    nuint rva = linked - table.Image.PreferredBase;
    nuint into = rva - where.Begin;
    if (into > prologueSize)
        into = prologueSize;

    // **The frame register first, because it undoes everything after it.** If
    // the prologue has already run `lea rbp, [rsp + n]`, the stack pointer at
    // this instant may be anywhere -- a `sub rsp` inside the body, an aligned
    // call -- and the only fixed point is the frame register.
    if (frameRegister == MachineRegisterRbp && FramePointerSet(xdata, codes,
                                                               codeCount, into))
        *stack = *framePointer - (nuint)(frameOffset * 16u);

    nuint index = 0u;
    while (index < codeCount)
    {
        nuint entry = codes + index * 2u;
        nuint offset = (nuint)xdata[entry];
        uint operation = (uint)xdata[entry + 1u] & 0xFu;
        uint operand = ((uint)xdata[entry + 1u] >> 4) & 0xFu;

        nuint slots = SlotsOf(operation, operand);
        if (slots == 0u && operation != UwopPushNonVolatile
            && operation != UwopAllocSmall && operation != UwopAllocLarge
            && operation != UwopSetFramePointer
            && operation != UwopSaveNonVolatile
            && operation != UwopSaveNonVolatileFar
            && operation != UwopSaveXmm128 && operation != UwopSaveXmm128Far
            && operation != UwopPushMachineFrame && operation != UwopEpilogue
            && operation != UwopSpare)
            return false;

        // An operation the program counter has not reached has not happened,
        // so there is nothing of it to undo.
        if (offset > into)
        {
            index = index + slots;
            continue;
        }

        switch (operation)
        {
            case UwopPushNonVolatile:
            {
                if (operand == MachineRegisterRbp
                    && !ReadStackWord(target, *stack, framePointer))
                    return false;
                *stack = *stack + 8u;
                break;
            }

            case UwopAllocLarge:
            {
                // Two shapes, told apart by the operand: one extra code
                // holding the size in eight-byte units, or two holding it in
                // bytes.
                if (operand == 0u)
                {
                    if (index + 1u >= codeCount)
                        return false;
                    *stack = *stack
                           + (nuint)(LittleEndianAt(xdata, codes + (index + 1u) * 2u, 2u) * 8u);
                }
                else
                {
                    if (index + 2u >= codeCount)
                        return false;
                    *stack = *stack
                           + (nuint)LittleEndianAt(xdata, codes + (index + 1u) * 2u, 4u);
                }
                break;
            }

            case UwopAllocSmall:
                *stack = *stack + (nuint)((operand + 1u) * 8u);
                break;

            case UwopPushMachineFrame:
                // The processor pushed a trap frame: five words, or six with
                // an error code. Above it is the interrupted code's own stack,
                // which this engine does not follow.
                return false;

            default:
                // Everything else -- setting the frame register, saving a
                // register or an XMM register into the frame, an epilogue
                // marker -- leaves the stack pointer where it was.
                break;
        }

        index = index + slots;
    }

    // A chained record describes the rest of the prologue in the function this
    // one was split out of. The `RUNTIME_FUNCTION` follows the codes, aligned
    // to a word.
    if ((flags & UnwindFlagChainInfo) != 0u)
    {
        nuint after = codes + ((codeCount + 1u) & ~1u) * 2u;
        if (after + 12u > xdata.Length)
            return false;

        var primary = new RuntimeFunction(
            (nuint)LittleEndianAt(xdata, after, 4u),
            (nuint)LittleEndianAt(xdata, after + 4u, 4u),
            (nuint)LittleEndianAt(xdata, after + 8u, 4u));

        // Past the primary's prologue entirely: every one of its operations
        // has happened by the time a chained fragment is running.
        nuint asIf = table.Image.PreferredBase + primary.End - 1u;
        return UndoPrologue(table, target, primary, asIf, slide, stack,
                            framePointer, depth + 1);
    }

    return true;
}

/// Whether the prologue has reached its `UWOP_SET_FPREG` by `into`.
bool FramePointerSet(byte[] xdata, nuint codes, nuint codeCount, nuint into)
{
    nuint index = 0u;
    while (index < codeCount)
    {
        nuint entry = codes + index * 2u;
        uint operation = (uint)xdata[entry + 1u] & 0xFu;
        uint operand = ((uint)xdata[entry + 1u] >> 4) & 0xFu;

        if (operation == UwopSetFramePointer && (nuint)xdata[entry] <= into)
            return true;

        index = index + SlotsOf(operation, operand);
    }
    return false;
}

/// How many two-byte slots one operation occupies, itself included.
nuint SlotsOf(uint operation, uint operand)
{
    switch (operation)
    {
        case UwopAllocLarge:
            return operand == 0u ? 2u : 3u;
        case UwopSaveNonVolatile:
        case UwopSaveXmm128:
            return 2u;
        case UwopSaveNonVolatileFar:
        case UwopSaveXmm128Far:
            return 3u;
        case UwopPushMachineFrame:
            return 1u;
        default:
            return 1u;
    }
}

/// Up to eight bytes of a buffer as a little-endian number. Answers zero past
/// the end, which is what every reader here does with a truncated file.
public ulong LittleEndianAt(byte[] data, nuint at, nuint size)
{
    ulong answer = 0u;
    for (nuint i = 0u; i < size; i++)
    {
        if (at + i >= data.Length)
            break;
        answer = answer | ((ulong)data[at + i] << (int)(i * 8u));
    }
    return answer;
}
