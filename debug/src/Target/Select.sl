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

// Which target this build controls processes through.
//
// The same four-line shape as
// [forms/src/Platform/Select.sl](../../../forms/src/Platform/Select.sl): one
// `#if`, in one place, so that no other file in the engine contains one. A
// branch that is not taken is never lexed, which is why the Windows target can
// name `DEBUG_EVENT` and the Linux build still compiles.
module Debugger;

import Standard.Text;
#if WINDOWS
import Win32;
import Win32.Handles;
import Win32.Kernel32;
#endif

/// The target for this platform, or a reason there is not one yet.
public Result<ITarget, String> MakeTarget()
{
#if WINDOWS
    return Ok((ITarget)new Win32Target());
#else
    // ptrace is 4f. The reading half of this engine -- the containers, the
    // DWARF, the line table -- is complete on both platforms and is what
    // `sldb sections`, `units`, `dies`, `lines`, `line` and `addr` use; only
    // the commands that need a live process are missing here.
    return Fail("controlling a process is not implemented on this platform yet");
#endif
}

/// What the platform calls a trap it was asked for, and one it was not.
///
/// Two numbers rather than two `#if`s scattered through the engine: every
/// platform has both concepts and none agrees on the spelling, so they are
/// named here where the platform is already being chosen.
public uint BreakpointExceptionCode()
{
#if WINDOWS
    return Win32.Kernel32.ExceptionBreakpoint;
#else
    return 5u;                                  // SIGTRAP, for the ptrace half
#endif
}

public uint StepExceptionCode()
{
#if WINDOWS
    return Win32.Kernel32.ExceptionSingleStep;
#else
    // ptrace reports a completed step as SIGTRAP too, and tells the two apart
    // by what was asked for rather than by the number. 4f decides how.
    return 5u;
#endif
}
