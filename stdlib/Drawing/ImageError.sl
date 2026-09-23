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

module Standard.Drawing;

import Standard.Collections;
import Standard.Text;
import Standard.File;
import Standard.IO;

/// What went wrong.
public enum ImageError
{
    None = 0,

    /// There is no imaging library on this machine. On Windows that means
    /// `gdiplus.dll` would not load, which should not happen; on Linux it means
    /// libgd is not installed, which is ordinary and is why this is a value
    /// rather than a failure.
    NoBackend = 1,

    /// No such file, or a directory along the path is missing.
    NotFound = 2,

    /// It is there and the decoder would not have it.
    Unreadable = 3,

    /// The format is not one of the four, or is one this build of libgd was
    /// compiled without.
    Unsupported = 4,

    /// The encode worked and the write did not.
    WriteFailed = 5,

    /// The allocation failed, which for an image means a size nothing could
    /// hold rather than a machine out of memory.
    OutOfMemory = 6,

    /// A size that is not positive, or a call on an image that is already
    /// closed.
    Invalid = 7,
}
