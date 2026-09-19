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

// The seam between the engine and the operating system it stops a process
// through.
//
// Designed the way [forms/src/Platform.sl](../../forms/src/Platform.sl)
// designs its widget-set seam: one interface, an implementation per platform,
// and neither naming a type from the other. Nothing above this line knows what
// a `DEBUG_EVENT` or a `ptrace` request is, and nothing below it knows what
// DWARF is.
//
// **What came back is a variant, not a pile of out-parameters.** A debug event
// is a genuine choice between eight different shapes -- a stop carries a thread
// and an address, an exit carries a code, output carries text -- and the
// alternative is a structure whose fields are meaningful in combinations a
// reader has to learn. This is what variants are for.
//
// **One thread owns the session.** Windows requires `WaitForDebugEvent` and
// `ContinueDebugEvent` on the thread that created the debuggee, and `ptrace`
// requires every request from the thread that attached. That is not two
// platform quirks that happen to agree; it is the same rule, and it means the
// engine is single-threaded by construction rather than by choice.
module Debugger;

import Standard.Collections;
import Standard.Text;

/// The registers a debugger reads before it reads anything else.
///
/// Three, not sixteen, and deliberately named for what they mean rather than
/// what they are called on one architecture: `Pc` is `Rip` on x86-64 and `PC`
/// on ARM64, and a stack walk written against the general names ports.
public struct Registers
{
    public nuint Pc;
    public nuint StackPointer;
    public nuint FramePointer;
}

/// What the operating system reported.
public variant DebugEvent
{
    /// The process exists and its image is at this address. The first event of
    /// every session, and where the slide comes from.
    Started(nuint imageBase, uint thread);

    /// It stopped. `code` is the platform's exception number, and
    /// `firstChance` is false when the program's own handlers have already
    /// declined it -- which makes it the last word before the process dies.
    Stopped(uint thread, nuint address, uint code, bool firstChance);

    ThreadCreated(uint thread);
    ThreadExited(uint thread);

    /// A library was mapped. Its own debug information, if anyone wants it,
    /// begins here.
    ModuleLoaded(nuint at);

    /// The program called something like `OutputDebugString`.
    Output(String text);

    Exited(int code);

    /// The wait timed out. Not an error, and not the end of anything.
    Nothing;
}

/// A process this debugger controls.
///
/// Every method here must be called from the one thread that launched the
/// target; see the note at the top of the file.
public interface ITarget
{
    /// Starts the program stopped at its own first instruction, in the sense
    /// that nothing of it has run that the debugger did not allow.
    ///
    /// **Not suspended**, which is the obvious way and the wrong one: a
    /// debuggee stops of its own accord at the loader's breakpoint, and a
    /// process created suspended has to be resumed by hand at a moment that is
    /// hard to pick correctly.
    Result<bool, String> Launch(String path, String arguments);

    /// The next event, or `Nothing` if none arrived in time.
    DebugEvent Wait(uint milliseconds);

    /// Lets the program continue from the event just reported.
    ///
    /// `handled` says whether the debugger dealt with an exception. False
    /// hands it back to the program, which is what must happen for a fault
    /// that is genuinely the program's -- swallowing those turns a crash into
    /// an infinite loop of the same crash.
    void Resume(bool handled);

    bool ReadMemory(nuint address, byte[] into, nuint count);
    bool WriteMemory(nuint address, byte[] from, nuint count);

    bool ReadRegisters(uint thread, Registers* into);
    bool WriteRegisters(uint thread, Registers* from);

    /// Asks for exactly one instruction on the next resume.
    ///
    /// **An intent, not a register.** Windows spells it as the trap flag in a
    /// thread's `EFlags`; ptrace spells it as `PTRACE_SINGLESTEP`, a different
    /// *request* rather than a different state. Carrying it as "step next
    /// time" is the only shape both can implement.
    bool SetSingleStep(uint thread, bool on);

    /// Kills it. Safe to call when it has already gone.
    void Terminate();

    /// Where the loader put the image, which is zero until `Started`.
    nuint ImageBase { get; }

    bool IsRunning { get; }
}
