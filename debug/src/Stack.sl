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

// Walking the stack: the unwind information first, the frame pointer after.
//
// **`Unwind.sl` is what makes this right anywhere but `-O0`.** `.eh_frame` on
// ELF and `.pdata` on PE describe every frame in the binary, the C runtime and
// the system's libraries included, because they exist so an exception can be
// thrown through one. They survive `-O2`, where there is no frame pointer at
// all.
//
// **The frame pointer walk is still here, and is not a historical remnant.**
// Unwind information can run out: a frame with no entry covering it, a CFA
// described by an expression, a rule naming a register this engine does not
// carry. Where that happens the two-load walk is what there is, and under `-g`
// it is exactly right -- the compiler emits `"frame-pointer"="all"`, so every
// function begins `push rbp; mov rbp, rsp` and
//
//     [rbp]      the caller's rbp
//     [rbp + 8]  the address to return to
//
// is the whole of it. A frame recovered either way is a frame; one recovered
// by neither ends the walk.
module Debugger;

import Standard.Collections;
import Standard.Text;

/// One frame of a call stack.
public class Frame
{
    /// Where this frame is executing. For frame zero that is the program
    /// counter; for every frame above it, the address *returned to*.
    public nuint Pc;

    public nuint FramePointer;

    /// The stack pointer this frame was entered with. Zero when the walk got
    /// here by the frame pointer, which says nothing about it.
    public nuint StackPointer;

    /// How far up the stack this is, with the stopped function at zero.
    public int Depth;

    /// Whether the unwind information answered for this frame, or the frame
    /// pointer did. Worth reporting: a walk that fell back has stopped being
    /// certain, and everything above it is a guess that happens to be right
    /// most of the time.
    public bool Unwound;

    public Frame(nuint pc, nuint framePointer, int depth)
    {
        Pc = pc;
        FramePointer = framePointer;
        StackPointer = 0u;
        Depth = depth;
        Unwound = false;
    }
}

/// How many frames to believe before deciding the chain is nonsense.
///
/// A stack that has been corrupted, or one walked out of a function with no
/// frame pointer, produces a chain that can be arbitrarily long and is
/// arbitrarily wrong. Stopping is better than printing a thousand frames.
const int MostFrames = 128;

/// Walks a stopped thread's stack.
///
/// Answers at least one frame whenever the registers can be read at all -- the
/// stopped address is a frame whether or not anything above it can be
/// recovered.
///
/// `table` may be null, which is a walk with nothing but the frame pointer.
public List<Frame> WalkStack(ITarget target, uint thread, Unwinder? table,
                             nuint slide)
{
    var frames = new List<Frame>();

    Registers registers;
    registers.Pc = 0u;
    registers.StackPointer = 0u;
    registers.FramePointer = 0u;
    if (!target.ReadRegisters(thread, &registers))
        return frames;

    var here = new Frame(registers.Pc, registers.FramePointer, 0);
    here.StackPointer = registers.StackPointer;
    here.Unwound = true;
    frames.Add(here);

    for (int depth = 1; depth < MostFrames; depth++)
    {
        var next = StepOutOfFrame(target, table, registers, slide);
        if (next == null)
            break;

        var caller = (Frame)next;
        caller.Depth = depth;

        // **The chain must climb.** The stack grows downwards, so a caller's
        // stack is always at a higher address than its callee's. A value that
        // does not climb is not a frame -- it is whatever a function that set
        // nothing up left in the register -- and following it walks in circles
        // or off into the heap.
        if (caller.StackPointer != 0u
            && caller.StackPointer <= registers.StackPointer)
            break;

        // A return address of zero is the bottom: the runtime's entry stub
        // sets one up so that exactly this loop stops.
        if (caller.Pc == 0u)
            break;

        frames.Add(caller);

        registers.Pc = caller.Pc;
        registers.StackPointer = caller.StackPointer;
        registers.FramePointer = caller.FramePointer;
    }

    return frames;
}

/// One frame out, by whatever can answer.
///
/// The unwind information is asked first because it is right wherever it
/// exists. The frame-pointer walk is the fallback rather than the other way
/// round: it is right only where a frame pointer was set up, and it cannot
/// tell that it was not.
Frame? StepOutOfFrame(ITarget target, Unwinder? table, Registers registers,
                      nuint slide)
{
    if (table != null)
    {
        var found = ((Unwinder)table).CallerOf(target, registers, slide);
        if (found != null)
        {
            var caller = (Caller)found;
            var made = new Frame(caller.Pc, caller.FramePointer, 0);
            made.StackPointer = caller.StackPointer;
            made.Unwound = true;
            return made;
        }
    }

    nuint framePointer = registers.FramePointer;
    if (framePointer == 0u)
        return null;

    byte[] cell = new byte[8];

    // The return address first, because a frame whose caller cannot be read is
    // still worth reporting if its return address can.
    if (!target.ReadMemory(framePointer + 8u, cell, 8u))
        return null;
    nuint returnTo = (nuint)LittleEndianWord(cell);

    if (!target.ReadMemory(framePointer, cell, 8u))
        return null;
    nuint callerFrame = (nuint)LittleEndianWord(cell);

    if (callerFrame != 0u && callerFrame <= framePointer)
        return null;

    // **A guess that lands in our own code is not a guess worth keeping.**
    // Everything in the image that is really code is covered by its unwind
    // information -- that is what the section is for -- so an address inside
    // the image that nothing describes is not a return address. It is where a
    // frame-pointer chain wandered after leaving a frame that never had one,
    // and following it produces frames that look like ours and are not.
    if (table != null)
    {
        var known = (Unwinder)table;
        nuint linked = returnTo - slide;
        if (!known.IsEmpty && known.InImage(linked) && !known.Describes(linked))
            return null;
    }

    var walked = new Frame(returnTo, callerFrame, 0);

    // The cell above the saved frame pointer holds the return address, so the
    // caller's stack pointer is the one after it.
    walked.StackPointer = framePointer + 16u;
    return walked;
}

/// Eight bytes as a little-endian number.
///
/// Every target this compiler has is little-endian; see `Bytes.sl`, which makes
/// the same decision for the same reason.
ulong LittleEndianWord(byte[] cell)
{
    ulong answer = 0u;
    for (nuint i = 0u; i < 8u; i++)
        answer = answer | ((ulong)cell[i] << (int)(i * 8u));
    return answer;
}
