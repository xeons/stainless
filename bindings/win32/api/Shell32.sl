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

// shell32.dll.
//
// Declarations cost nothing, so this module needs no library on its own; a
// program that *calls* one of them wants `-l shell32`, or `Win32.Shell`, which
// names it with a pragma.
//
// The flat entry points, and the two that take a GUID: `SHGetKnownFolderPath`
// and `SHCreateItemFromParsingName` are the doors to everything the shell has
// added since Vista. The interfaces they lead to are in `Win32.ShellCom`.
module Win32.Shell32;

import Standard.Com;
import Win32.Handles;

#if WINDOWS

public extern "C" {
    HINSTANCE ShellExecuteW(HWND owner, char16* verb, char16* file,
                            char16* parameters, char16* directory, int show);
    uint      SHGetFolderPathW(HWND owner, int folder, HANDLE token, uint flags, char16* path);
    uint      DragQueryFileW(HDROP drop, uint index, char16* buffer, uint size);
    void      DragFinish(HDROP drop);
    void      DragAcceptFiles(HWND window, int accept);

    // Since Vista. The path comes back in memory the caller frees with
    // `CoTaskMemFree`, and the folder is named by GUID rather than by the
    // small integers below -- which is what lets a folder be added without
    // renumbering anything.
    int       SHGetKnownFolderPath(Guid* folder, uint flags, HANDLE token,
                                   char16** path);

    // A path, as the `IShellItem` every modern shell API takes.
    int       SHCreateItemFromParsingName(char16* path, byte* bindContext,
                                          Guid* interfaceId, byte** item);

    // The item for a known folder, without going through its path -- which is
    // the only way to name one that has no path.
    int       SHCreateItemInKnownFolder(Guid* folder, uint flags, char16* name,
                                        Guid* interfaceId, byte** item);

    // The shell's own allocator for a `PIDL`, and the one call that frees the
    // results of the older namespace functions.
    void      ILFree(byte* list);
}

/// `SHGetKnownFolderPath` flags.

/// The default: the path as it is now, and a failure if the folder does not
/// exist.
public const uint KnownFolderDefault = 0x00000000u;

/// Create the folder if it is registered but not yet made.
public const uint KnownFolderCreate = 0x00008000u;

/// The path even if the folder is not there, which is what a program that is
/// about to create it wants.
public const uint KnownFolderDontVerify = 0x00004000u;

/// `ShellExecuteW` returns a fake `HINSTANCE` that is an error code when it is
/// 32 or less. Anything above that means it worked.
public const nuint ShellExecuteThreshold = 32u;

/// `SHGetFolderPathW`'s well-known folders. The modern API is
/// `SHGetKnownFolderPath`, which takes a GUID by pointer and returns memory to
/// free with `CoTaskMemFree`; these integers still work and need neither.
public const int FolderDesktop       = 0x0000;
public const int FolderPrograms      = 0x0002;
public const int FolderPersonal      = 0x0005;   // Documents
public const int FolderFavorites     = 0x0006;
public const int FolderStartup       = 0x0007;
public const int FolderRecent        = 0x0008;
public const int FolderAppData       = 0x001A;   // Roaming
public const int FolderLocalAppData  = 0x001C;
public const int FolderCommonAppData = 0x0023;
public const int FolderWindows       = 0x0024;
public const int FolderSystem        = 0x0025;
public const int FolderProgramFiles  = 0x0026;
public const int FolderProfile       = 0x0028;

/// Create the folder if it is not there yet.
public const int FolderCreate = 0x8000;

#endif
