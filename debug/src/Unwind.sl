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

// Where a frame's caller is, read from what the linker already wrote down.
//
// Every binary this compiler produces carries it: `.eh_frame` on ELF,
// `.pdata` and its `UNWIND_INFO` on PE. Neither is debug information -- both
// are there so that an exception can be thrown through a frame, which is why
// they cover the C runtime and the system's own libraries as well, and why
// they survive `-O2` where a frame pointer does not.
//
// **The two formats answer the same question in opposite directions.** DWARF
// CFI is a bytecode that builds a table: run it to the address in question and
// read off where each register went. Windows lists the prologue's own
// operations in reverse and asks a reader to undo them. So there are two
// readers and one seam, and the seam is a `Frame`: a program counter, a stack
// pointer and a frame pointer, in and out.
//
// **What is deliberately not here.** A CFA rule that is a DWARF expression
// (`DW_CFA_def_cfa_expression`), and a rule that names a callee-saved register
// this engine does not carry. Both are refused rather than guessed, and the
// walk falls back to the frame pointer -- which is right wherever there is
// one, and says so rather than producing a chain that climbs into the heap.
module Debugger;

import Standard.Collections;
import Standard.Text;

/// The x86-64 register numbers DWARF uses, which are not the instruction
/// encoding's.
const ulong CfiRegisterRsp = 7u;
const ulong CfiRegisterRbp = 6u;

/// Where the return address lives, as far as DWARF's table is concerned: a
/// register number past the real ones.
const ulong CfiReturnAddress = 16u;

/// What one frame's unwind information said.
public class Caller
{
    public nuint Pc;
    public nuint StackPointer;
    public nuint FramePointer;

    public Caller(nuint pc, nuint stackPointer, nuint framePointer)
    {
        Pc = pc;
        StackPointer = stackPointer;
        FramePointer = framePointer;
    }
}

/// Everything a binary says about unwinding, read once.
///
/// Built from the image alone, so it costs nothing at a stop and can be
/// exercised on a machine that could not run the binary.
public class Unwinder
{
    Image _image;

    /// `.eh_frame`, and where it was linked to sit -- a pointer encoding may be
    /// relative to its own address, so the section's address is part of
    /// reading it.
    byte[] _ehFrame;
    nuint _ehFrameAddress;

    /// `.pdata`, an array of three-word records sorted by address.
    byte[] _pdata;
    nuint _pdataAddress;

    /// One past the last byte any section reaches.
    nuint _top;

    public Unwinder(Image image)
    {
        _image = image;

        var eh = image.Find(".eh_frame");
        _ehFrame = eh == null ? new byte[0u] : ((Section)eh).Data;
        _ehFrameAddress = eh == null ? 0u : ((Section)eh).Address;

        var pdata = image.Find(".pdata");
        _pdata = pdata == null ? new byte[0u] : ((Section)pdata).Data;
        _pdataAddress = pdata == null ? 0u : ((Section)pdata).Address;

        _top = image.PreferredBase;
        var sections = image.Sections;
        for (nuint i = 0u; i < sections.Count; i++)
        {
            nuint end = sections[i].Address + sections[i].Size;
            if (end > _top)
                _top = end;
        }
    }

    /// Whether this binary describes its frames at all.
    public bool IsEmpty => _ehFrame.Length == 0u && _pdata.Length == 0u;

    /// Which of the two this image carries, for a reader that wants to say.
    public String Format
    {
        get
        {
            if (_ehFrame.Length != 0u)
                return ".eh_frame";
            if (_pdata.Length != 0u)
                return ".pdata";
            return "none";
        }
    }

    public Image Image => _image;

    /// The caller of the frame these registers describe, or null.
    ///
    /// `slide` is where the loader put the image against where it was linked,
    /// so that everything below can work in link-time addresses -- which is
    /// what both formats are written in.
    ///
    /// Null means this engine cannot answer, never that there is no caller. A
    /// caller that treats it as the end of the stack is a caller that loses
    /// every frame above a function described in a way this does not read.
    public Caller? CallerOf(ITarget target, Registers frame, nuint slide)
    {
        nuint linked = frame.Pc - slide;

        if (_pdata.Length != 0u)
            return CallerByXdata(this, target, frame, linked, slide);

        if (_ehFrame.Length != 0u)
            return CallerByCfi(this, target, frame, linked, slide);

        return null;
    }

    /// Whether a link-time address is inside this image at all.
    ///
    /// The whole span, not only the sections: the headers sit below the first
    /// of them and are just as much not-code. An address in a shared library
    /// or in the system's own code is outside, which is the distinction the
    /// walk needs.
    public bool InImage(nuint linked)
        => linked >= _image.PreferredBase && linked < _top;

    /// Whether this image's unwind information covers an address.
    ///
    /// **Everything in the image that is really code is covered**, because
    /// that is what these sections are for: an exception has to be thrown
    /// through every frame. So an address inside the image that this does not
    /// describe is not a return address -- it is whatever a frame-pointer
    /// chain wandered into.
    public bool Describes(nuint linked)
    {
        if (_pdata.Length != 0u)
            return FunctionCovering(this, linked) != null;
        if (_ehFrame.Length != 0u)
            return RowAt(this, linked) != null;
        return false;
    }

    /// The bytes of whichever section covers a link-time address, and where in
    /// them that address falls.
    ///
    /// Both formats point at other parts of the image by address rather than by
    /// file offset -- an `UNWIND_INFO` lives wherever the linker put it, which
    /// for lld is inside `.rdata`.
    public bool BytesAt(nuint address, byte[]* into, nuint* offset)
    {
        var sections = _image.Sections;
        for (nuint i = 0u; i < sections.Count; i++)
        {
            var one = sections[i];
            if (!one.Covers(address))
                continue;
            *into = one.Data;
            *offset = address - one.Address;
            return true;
        }
        return false;
    }

    public byte[] EhFrame => _ehFrame;
    public nuint EhFrameAddress => _ehFrameAddress;
    public byte[] Pdata => _pdata;
    public nuint PdataAddress => _pdataAddress;
}

/// One word out of a stopped process.
bool ReadStackWord(ITarget target, nuint at, nuint* into)
{
    byte[] cell = new byte[8];
    if (!target.ReadMemory(at, cell, 8u))
        return false;
    *into = (nuint)LittleEndianWord(cell);
    return true;
}
