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

// What differs between the processors this engine debugs.
//
// The debugger and its debuggee are built for one architecture, so this is
// decided when the debugger is compiled. Like `Select.sl`, it is the one file
// that tests for it.
//
// Two differences matter. A trap is one byte on x86-64 and one four-byte
// instruction on arm64. And `call` pushes its return address, while `bl` puts
// it in the link register and leaves the stack alone.
module Debugger;

#if ARM64

/// DWARF's numbers for the registers `Registers` carries: x29, the stack
/// pointer, and x30.
public const ulong DwarfRegisterFramePointer = 29u;
public const ulong DwarfRegisterStackPointer = 31u;
public const ulong DwarfRegisterLink = 30u;

/// The CFI column the return address is described in, which on arm64 is the
/// link register itself.
public const ulong DwarfReturnAddressColumn = 30u;

/// `brk #0`, little-endian.
public byte[] MakeTrapInstruction() => [0x00, 0x00, 0x20, 0xD4];

/// Where a function just entered will return to: the link register.
public bool ReadReturnAddressAtEntry(ITarget target, Registers frame, nuint* into)
{
    *into = StripPointerSignature(frame.LinkRegister);
    return frame.LinkRegister != 0u;
}

/// Whether the instruction just stepped was a call.
///
/// `bl` and `blr` write the address after themselves into x30, and nothing
/// else an instruction does leaves it pointing there.
public bool WasCallTaken(Registers lineStart, Registers before, Registers after)
    => after.LinkRegister == before.Pc + 4u && after.StackPointer <= lineStart.StackPointer;

/// A code address with any pointer-authentication signature cleared.
///
/// An arm64 process calls into the system's arm64e libraries, which sign the
/// return addresses they save. A user address has at most 47 bits.
public nuint StripPointerSignature(nuint address) => address & 0x00007FFFFFFFFFFFu;

/// `UNWIND_ARM64_MODE_FRAME`, `_FRAMELESS` and `_DWARF`.
public const uint CompactUnwindModeFrame = 0x04000000u;
public const uint CompactUnwindModeFrameless = 0x02000000u;
public const uint CompactUnwindModeDwarf = 0x03000000u;

#else

/// DWARF's numbers for the x86-64 registers `Registers` carries: RBP and RSP.
/// They are not the instruction encoding's. There is no link register.
public const ulong DwarfRegisterFramePointer = 6u;
public const ulong DwarfRegisterStackPointer = 7u;
public const ulong DwarfRegisterLink = 0xFFFFu;

/// The CFI column the return address is described in: one past the real
/// registers.
public const ulong DwarfReturnAddressColumn = 16u;

/// `int3`. One byte, so it never overwrites the instruction after the one it
/// replaces.
public byte[] MakeTrapInstruction() => [0xCC];

/// Where a function just entered will return to: the word `call` pushed.
public bool ReadReturnAddressAtEntry(ITarget target, Registers frame, nuint* into)
    => ReadStackWord(target, frame.StackPointer, into);

/// Whether the instruction just stepped was a call: the stack went below
/// where the line began. The callee's own prologue cannot do that before its
/// first instruction has run.
public bool WasCallTaken(Registers lineStart, Registers before, Registers after)
    => after.StackPointer < lineStart.StackPointer;

/// A code address as it is. x86-64 signs nothing.
public nuint StripPointerSignature(nuint address) => address;

/// `UNWIND_X86_64_MODE_RBP_FRAME` and `_DWARF`. Its frameless modes keep the
/// stack size in the function's own instructions, which are not read here,
/// so that constant is one no encoding masks to.
public const uint CompactUnwindModeFrame = 0x01000000u;
public const uint CompactUnwindModeFrameless = 0x10000000u;
public const uint CompactUnwindModeDwarf = 0x04000000u;

#endif

/// A register named by its DWARF number, if it is one `Registers` carries.
///
/// Anything else is refused rather than guessed. A link register of zero is
/// refused too: above frame zero it is not known.
public bool ReadDwarfRegister(Registers frame, ulong which, nuint* value)
{
    switch (which)
    {
        case DwarfRegisterFramePointer:
            *value = frame.FramePointer;
            return true;
        case DwarfRegisterStackPointer:
            *value = frame.StackPointer;
            return true;
        case DwarfRegisterLink:
            *value = frame.LinkRegister;
            return frame.LinkRegister != 0u;
        default:
            return false;
    }
}

/// Whether `ReadDwarfRegister` can answer for a register.
public bool IsCarriedDwarfRegister(ulong which)
    => which == DwarfRegisterFramePointer || which == DwarfRegisterStackPointer
       || which == DwarfRegisterLink;
