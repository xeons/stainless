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

module Standard.Directory;

import Standard.Collections;
import Standard.IO;
import Standard.Path;

// ----------------------------------------------------------------- listing

/// One entry of a directory: where it is, and whether it is itself a directory.
public class Entry
{
    /// The full path, ready to hand back to `File` or `Directory`. Built from
    /// the path that was listed, so a relative listing gives relative entries.
    public String Path { get; }

    /// The last part alone, without any directory in front of it.
    public String Name { get; }

    /// True for a directory, false for anything else -- a regular file, a
    /// symbolic link to one, a device. Only the directory answer is relied on
    /// here, because it is the one that decides whether a walk descends.
    public bool IsDirectory { get; }

    /// Builds an entry. Listing is what normally makes these; this is here for
    /// a caller assembling the same shape from somewhere else.
    public Entry(String path, String name, bool isDirectory)
    {
        Path = path;
        Name = name;
        IsDirectory = isDirectory;
    }
}
