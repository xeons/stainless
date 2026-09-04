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

// The open and save dialogs.
//
// A convenience layer over `Win32.ComDlg32`. **Link with `-l comdlg32`** and
// `-l user32`, since a dialog needs an owner window even when that owner is
// null.
module Win32.Dialogs;

#if WINDOWS

import Win32;
import Win32.ComDlg32;

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
