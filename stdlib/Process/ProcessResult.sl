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

/// What a finished program left behind.
public struct ProcessResult
{
    /// Zero by convention means success; 128 + N means a signal killed it,
    /// which is what a shell reports too.
    public int ExitCode;

    /// Everything it wrote to its output, as one String.
    public String StandardOutput;

    /// And to its error stream, kept separate so that a program which prints
    /// progress there does not corrupt what was being captured.
    public String StandardError;

    /// The usual question, spelled once.
    public bool Succeeded => ExitCode == 0;
}
