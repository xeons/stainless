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

module Standard.Media.Audio;

import Standard.Text;
import Standard.Collections;
import Standard.File;
import Standard.IO;

/// Why a sound did not happen.
public enum AudioError
{
    /// There is no audio library on this machine: no winmm, or no
    /// libasound. `Audio.IsAvailable` is how to ask before trying.
    NoBackend,

    /// The format is not one this module handles, or not one the device
    /// would take.
    Format,

    /// There is no sound device, or the one there is refused to open.
    Device,

    /// Something else has the device and will not share it.
    Busy,

    /// The player or recorder has been closed.
    Closed,

    /// The file was not a WAV, or was one this module does not read.
    Malformed,

    /// The file could not be read or written; `Standard.IO` has the detail.
    IO,
}
