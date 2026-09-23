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

module Standard.Process;

import Standard.Collections;

/// Why a program could not be started.
///
/// Only about *starting* it. A program that ran and failed is a `ProcessResult`
/// with a non-zero `ExitCode`, which is an outcome rather than an error --
/// `grep` answering 1 for "no match" is the ordinary case, not a fault.
public enum ProcessError
{
    /// It started.
    None,

    /// No such program, on the PATH or at the path given.
    NotFound,

    /// It exists and this process may not run it.
    Denied,

    /// Out of processes, descriptors or memory.
    NoResource,

    /// It did not start, for a reason none of the above names.
    Failed,
}
