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

module Standard.IO;

import Standard.Collections;

// ------------------------------------------------------------------ errors

/// Why an operation did not work. `None` is success.
///
/// These are the distinctions a program can act on, not the platform's whole
/// error list: the values are the same on every platform, which `errno` is not.
public enum IOError
{
    /// Nothing went wrong.
    None = 0,

    /// No such file, or a directory along the path is missing.
    NotFound = 1,

    /// It is there and this process may not touch it that way.
    AccessDenied = 2,

    /// Creating something that is already there.
    AlreadyExists = 3,

    /// A path used a file as though it were a directory.
    NotADirectory = 4,

    /// A directory was given where a file was wanted.
    IsADirectory = 5,

    /// The request made no sense -- a count past the end of a buffer, a
    /// negative seek, a mode the operation cannot take.
    Invalid = 6,

    /// The end of the file. A read that returns zero is the usual way this is
    /// seen, so this value is rarer than it looks.
    EndOfFile = 7,

    /// The stream was closed before the call.
    Closed = 8,

    /// The platform said something this enum has no name for.
    Unknown = 9,
}
