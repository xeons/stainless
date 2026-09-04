// Stainless - an experimental systems language.
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

// Opening things the way the user would, and the folders Windows keeps for
// them.
//
// A convenience layer over `Win32.Shell32`. It names shell32 itself with a
// pragma, so a program compiling it needs no `-l`.
module Win32.Shell;

#if WINDOWS

// The library this module needs, so that a program compiling it does not
// have to repeat the name on its own command line.
#pragma comment(lib, "shell32")
#pragma comment(lib, "user32")

import Win32;
import Win32.Shell32;
import Win32.User32;
import Win32.Handles;

/// `ShellExecuteW` returns a fake `HINSTANCE` that is an error code when it is
/// 32 or less. Anything above that means it worked.
public bool Started(HINSTANCE result) { return (nuint)result > ShellExecuteThreshold; }

/// Opens a file, a folder or a URL with whatever the user has associated with
/// it — the same thing double-clicking would do.
public bool Launch(String target) {
    HINSTANCE result = ShellExecuteW(null, "open".ToUtf16().ToPointer(),
                                 target.ToUtf16().ToPointer(), null, null, SwShowNormal);
    return Started(result);
}

/// Opens a folder in Explorer.
public bool Browse(String directory) {
    HINSTANCE result = ShellExecuteW(null, "explore".ToUtf16().ToPointer(),
                                 directory.ToUtf16().ToPointer(), null, null, SwShowNormal);
    return Started(result);
}

/// Runs a program, elevated. Windows shows the consent prompt; a user who
/// refuses is a `false` here and not an error worth explaining.
public bool RunElevated(String program, String arguments) {
    HINSTANCE result = ShellExecuteW(null, "runas".ToUtf16().ToPointer(),
                                 program.ToUtf16().ToPointer(),
                                 arguments.ToUtf16().ToPointer(), null, SwShowNormal);
    return Started(result);
}

/// A well-known folder's path, or an empty string. The `Folder...` constants
/// are in `Win32.Shell32`.
public String FolderPath(int folder) {
    // MAX_PATH, which is what this API writes and does not check against.
    var buffer = new WideBuffer(260u);
    uint result = SHGetFolderPathW(null, folder, null, 0u, buffer.Pointer());
    if (result != 0u) { return ""; }
    return buffer.Text();
}

#endif
