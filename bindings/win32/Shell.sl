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

// shell32 and comdlg32: opening things the way the user would, and the file
// dialogs.
//
// **Link with `-l shell32 -l comdlg32`** — and `-l user32`, since a dialog
// needs an owner window even when that owner is null.
module Win32.Shell;

#if WINDOWS

import Win32;

// ============================================================ ShellExecuteW

public extern "C" {
    void* ShellExecuteW(void* owner, ushort* verb, ushort* file,
                        ushort* parameters, ushort* directory, int show);
    uint  SHGetFolderPathW(void* owner, int folder, void* token, uint flags, ushort* path);
}

/// `ShellExecuteW` returns a fake `HINSTANCE` that is an error code when it is
/// 32 or less. Anything above that means it worked.
public bool Started(void* result) { return (nuint)result > 32u; }

/// Opens a file, a folder or a URL with whatever the user has associated with
/// it — the same thing double-clicking would do.
public bool Open(String target) {
    void* result = ShellExecuteW(null, "open".ToUtf16().ToPointer(),
                                 target.ToUtf16().ToPointer(), null, null, 1);
    return Started(result);
}

/// Opens a folder in Explorer.
public bool Browse(String directory) {
    void* result = ShellExecuteW(null, "explore".ToUtf16().ToPointer(),
                                 directory.ToUtf16().ToPointer(), null, null, 1);
    return Started(result);
}

/// Runs a program, elevated. Windows shows the consent prompt; a user who
/// refuses is a `false` here and not an error worth explaining.
public bool RunElevated(String program, String arguments) {
    void* result = ShellExecuteW(null, "runas".ToUtf16().ToPointer(),
                                 program.ToUtf16().ToPointer(),
                                 arguments.ToUtf16().ToPointer(), null, 1);
    return Started(result);
}

/// `SHGetFolderPathW`'s well-known folders. The modern API is
/// `SHGetKnownFolderPath`, which takes a GUID by pointer and returns memory to
/// free with `CoTaskMemFree`; these integers still work and need neither.
public const int FolderDesktop      = 0x0000;
public const int FolderPrograms     = 0x0002;
public const int FolderPersonal     = 0x0005;   // Documents
public const int FolderFavorites    = 0x0006;
public const int FolderStartup      = 0x0007;
public const int FolderRecent       = 0x0008;
public const int FolderAppData      = 0x001A;   // Roaming
public const int FolderLocalAppData = 0x001C;
public const int FolderCommonAppData = 0x0023;
public const int FolderWindows      = 0x0024;
public const int FolderSystem       = 0x0025;
public const int FolderProgramFiles = 0x0026;
public const int FolderProfile      = 0x0028;

/// Create the folder if it is not there yet.
public const int FolderCreate = 0x8000;

/// A well-known folder's path, or an empty string.
public String FolderPath(int folder) {
    // MAX_PATH, which is what this API writes and does not check against.
    var buffer = new WideBuffer(260u);
    uint result = SHGetFolderPathW(null, folder, null, 0u, buffer.Pointer());
    if (result != 0u) { return ""; }
    return buffer.Text();
}

// ============================================================== file dialogs

/// `OPENFILENAMEW`. `sizeof` is 152, and `Size` must be set to it.
///
/// `File` points at a buffer the dialog *writes into*, so it must be writable
/// and big enough — `AskToOpen` below supplies one. `Filter` is stranger: it is
/// a list of NUL-separated pairs ending in a double NUL, which no Stainless
/// string can hold, so `BuildFilter` assembles one.
public struct OpenFileName {
    public uint  Size;
    public void* Owner;
    public void* Instance;
    public ushort* Filter;
    public ushort* CustomFilter;
    public uint  CustomFilterMax;
    public uint  FilterIndex;
    public ushort* File;
    public uint  FileMax;
    public ushort* FileTitle;
    public uint  FileTitleMax;
    public ushort* InitialDirectory;
    public ushort* Title;
    public uint  Flags;
    public ushort FileOffset;
    public ushort ExtensionOffset;
    public ushort* DefaultExtension;
    public long  CustomData;
    public void* Hook;
    public ushort* TemplateName;
    public void* Reserved1;
    public uint  Reserved2;
    public uint  FlagsEx;
}

public const uint OfnReadOnly         = 0x00000001u;
public const uint OfnOverwritePrompt  = 0x00000002u;
public const uint OfnHideReadOnly     = 0x00000004u;
public const uint OfnNoChangeDir      = 0x00000008u;
public const uint OfnAllowMultiSelect = 0x00000200u;
public const uint OfnPathMustExist    = 0x00000800u;
public const uint OfnFileMustExist    = 0x00001000u;
public const uint OfnCreatePrompt     = 0x00002000u;
public const uint OfnNoDereferenceLinks = 0x00100000u;
public const uint OfnExplorer         = 0x00080000u;

public extern "C" {
    int  GetOpenFileNameW(OpenFileName* dialog);
    int  GetSaveFileNameW(OpenFileName* dialog);
    uint CommDlgExtendedError();
}

/// Builds the NUL-separated filter list `OPENFILENAMEW` wants.
///
/// The pairs are label and pattern, alternating, so
/// `["Text files", "*.txt", "All files", "*.*"]` becomes
/// `Text files\0*.txt\0All files\0*.*\0\0`. A Stainless string cannot hold an
/// embedded NUL, so the buffer is filled unit by unit; the caller keeps it
/// alive for as long as the dialog is up.
public WideBuffer BuildFilter(String[] pairs) {
    // Every entry, its terminator, and the extra terminator that ends the list.
    nuint units = 1u;
    for (nuint i = 0u; i < pairs.Length; i = i + 1u) {
        units = units + pairs[i].ToUtf16().UnitCount() + 1u;
    }

    var buffer = new WideBuffer((uint)units);
    ushort* target = buffer.Pointer();

    nuint at = 0u;
    for (nuint i = 0u; i < pairs.Length; i = i + 1u) {
        var wide = pairs[i].ToUtf16();
        ushort* source = wide.ToPointer();
        for (nuint j = 0u; j < wide.UnitCount(); j = j + 1u) {
            target[at] = source[j];
            at = at + 1u;
        }
        target[at] = 0u;
        at = at + 1u;
    }
    target[at] = 0u;
    return buffer;
}

/// An `OPENFILENAMEW` with its size set and everything else zeroed.
public OpenFileName NewOpenFileName() {
    OpenFileName dialog;
    dialog.Size = (uint)sizeof(OpenFileName);
    dialog.Owner = null;
    dialog.Instance = null;
    dialog.Filter = null;
    dialog.CustomFilter = null;
    dialog.CustomFilterMax = 0u;
    dialog.FilterIndex = 0u;
    dialog.File = null;
    dialog.FileMax = 0u;
    dialog.FileTitle = null;
    dialog.FileTitleMax = 0u;
    dialog.InitialDirectory = null;
    dialog.Title = null;
    dialog.Flags = 0u;
    dialog.FileOffset = 0u;
    dialog.ExtensionOffset = 0u;
    dialog.DefaultExtension = null;
    dialog.CustomData = 0;
    dialog.Hook = null;
    dialog.TemplateName = null;
    dialog.Reserved1 = null;
    dialog.Reserved2 = 0u;
    dialog.FlagsEx = 0u;
    return dialog;
}

/// Shows the open dialog and returns the chosen path, or an empty string if
/// the user cancelled.
public String AskToOpen(void* owner, String title, String[] filterPairs) {
    var filter = BuildFilter(filterPairs);
    var chosen = new WideBuffer(32768u);

    var dialog = NewOpenFileName();
    dialog.Owner = owner;
    dialog.Filter = filter.Pointer();
    dialog.FilterIndex = 1u;
    dialog.File = chosen.Pointer();
    dialog.FileMax = chosen.Capacity();
    dialog.Title = title.ToUtf16().ToPointer();
    dialog.Flags = OfnExplorer | OfnFileMustExist | OfnPathMustExist | OfnHideReadOnly;

    if (!Win32.Succeeded(GetOpenFileNameW(&dialog))) { return ""; }
    return chosen.Text();
}

/// Shows the save dialog and returns the chosen path, or an empty string.
public String AskToSave(void* owner, String title, String[] filterPairs,
                        String defaultExtension) {
    var filter = BuildFilter(filterPairs);
    var chosen = new WideBuffer(32768u);

    var dialog = NewOpenFileName();
    dialog.Owner = owner;
    dialog.Filter = filter.Pointer();
    dialog.FilterIndex = 1u;
    dialog.File = chosen.Pointer();
    dialog.FileMax = chosen.Capacity();
    dialog.Title = title.ToUtf16().ToPointer();
    dialog.DefaultExtension = defaultExtension.ToUtf16().ToPointer();
    dialog.Flags = OfnExplorer | OfnOverwritePrompt | OfnPathMustExist | OfnHideReadOnly;

    if (!Win32.Succeeded(GetSaveFileNameW(&dialog))) { return ""; }
    return chosen.Text();
}

#endif
