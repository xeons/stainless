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

// Walking the stack, which under `-g` is two loads per frame.
//
// **This is only possible because the compiler emits a frame pointer.** It does
// that under `-g` and nowhere else -- `"frame-pointer"="all"`, one attribute
// group, added because LLVM omits the frame pointer at every optimisation
// level unless asked, `-O0` included. Without it `DW_AT_frame_base` describes
// RSP, which is correct and describes a frame nothing can unwind.
//
// With it every function begins `push rbp; mov rbp, rsp`, so the frame pointer
// register points at a cell holding the caller's frame pointer, with the return
// address in the next cell up:
//
//     [rbp]      the caller's rbp
//     [rbp + 8]  the address to return to
//
// which is the whole algorithm.
//
// **What this is not.** It is not an unwinder. At `-O2` there is no frame
// pointer and this answers one frame; through the C runtime, which the
// toolchain builds with its own flags, it answers whatever those flags left
// behind. The real thing reads `.eh_frame` on ELF and `.pdata` on PE -- both of
// which are already in every binary this compiler produces, measured in
// `docs/dwarf.md` -- and is deliberately later work. A two-load walk that is
// right at `-O0` is what a debugger needs first and is worth having on its own.
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

    /// How far up the stack this is, with the stopped function at zero.
    public int Depth;

    public Frame(nuint pc, nuint framePointer, int depth)
    {
        Pc = pc;
        FramePointer = framePointer;
        Depth = depth;
    }
}

/// How many frames to believe before deciding the chain is nonsense.
///
/// A stack that has been corrupted, or one walked out of a function with no
/// frame pointer, produces a chain that can be arbitrarily long and is
/// arbitrarily wrong. Stopping is better than printing a thousand frames.
const int MostFrames = 128;

/// Walks the frame-pointer chain from a stopped thread.
///
/// Answers at least one frame whenever the registers can be read at all -- the
/// stopped address is a frame whether or not anything above it can be
/// recovered.
public List<Frame> WalkStack(ITarget target, uint thread)
{
    var frames = new List<Frame>();

    Registers registers;
    registers.Pc = 0u;
    registers.StackPointer = 0u;
    registers.FramePointer = 0u;
    if (!target.ReadRegisters(thread, &registers))
        return frames;

    frames.Add(new Frame(registers.Pc, registers.FramePointer, 0));

    nuint framePointer = registers.FramePointer;
    for (int depth = 1; depth < MostFrames; depth++)
    {
        if (framePointer == 0u)
            break;

        byte[] cell = new byte[8];

        // The return address first, because a frame whose caller cannot be
        // read is still worth reporting if its return address can.
        if (!target.ReadMemory(framePointer + 8u, cell, 8u))
            break;
        nuint returnTo = (nuint)LittleEndianWord(cell);

        if (!target.ReadMemory(framePointer, cell, 8u))
            break;
        nuint callerFrame = (nuint)LittleEndianWord(cell);

        // **The chain must climb.** The stack grows downwards, so a caller's
        // frame pointer is always at a higher address than its callee's. A
        // value that does not climb is not a frame -- it is whatever happened
        // to be in the register of a function that never set one up, and
        // following it walks in circles or off into the heap.
        if (callerFrame != 0u && callerFrame <= framePointer)
            break;

        // A return address of zero is the bottom: the runtime's entry stub sets
        // one up so that exactly this loop stops.
        if (returnTo == 0u)
            break;

        frames.Add(new Frame(returnTo, callerFrame, depth));
        framePointer = callerFrame;
    }

    return frames;
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
