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

// The open and save dialogs, in both generations.
//
// `AskToOpen` and `AskToSave` are `GetOpenFileNameW`, which still works
// everywhere and needs no COM. `ChooseFile` and the rest are `IFileDialog`,
// which is what Windows has actually shown since Vista: the places bar,
// libraries, a shell namespace rather than a path, and folder picking that is
// the same dialog rather than the old tree.
//
// A convenience layer over `Win32.ComDlg32` and `Win32.ShellCom`. It names
// comdlg32, user32 and ole32 itself with a pragma — a dialog needs an owner
// window even when that owner is null — so a program compiling it needs no
// `-l`.
module Win32.Dialogs;

#if WINDOWS

// The library this module needs, so that a program compiling it does not
// have to repeat the name on its own command line.
#pragma comment(lib, "comdlg32")
#pragma comment(lib, "user32")
#pragma comment(lib, "ole32")

import Standard.Com;
import Standard.Text;
import Win32;
import Win32.Com;
import Win32.Ole32;
import Win32.ComDlg32;
import Win32.ShellCom;
import Win32.Shell;
import Win32.Handles;

/// Builds the NUL-separated filter list `OPENFILENAMEW` wants.
///
/// The pairs are label and pattern, alternating, so
/// `["Text files", "*.txt", "All files", "*.*"]` becomes
/// `Text files\0*.txt\0All files\0*.*\0\0`. A Stainless string cannot hold an
/// embedded NUL, so the buffer is filled unit by unit; the caller keeps it
/// alive for as long as the dialog is up.
///
/// `IFileDialog` wants the same pairs in a different shape; `BuildSpecs` is
/// that one, and is simpler because it needs no buffer at all.
public WideBuffer BuildFilter(String[] pairs) {
    // Every entry, its terminator, and the extra terminator that ends the list.
    nuint units = 1u;
    for (nuint i = 0u; i < pairs.Length; i = i + 1u) {
        units = units + pairs[i].ToUtf16().UnitCount() + 1u;
    }

    var buffer = new WideBuffer((uint)units);
    char16* target = buffer.Pointer();

    nuint at = 0u;
    for (nuint i = 0u; i < pairs.Length; i = i + 1u) {
        var wide = pairs[i].ToUtf16();
        char16* source = wide.ToPointer();
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
public String AskToOpen(HWND owner, String title, String[] filterPairs) {
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
public String AskToSave(HWND owner, String title, String[] filterPairs,
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

// ======================================================= the Vista dialogs

/// Why a file dialog produced no path.
public enum DialogError : uint {
    /// The user closed it without choosing. Not a fault, and the usual answer.
    Cancelled = 0u,

    /// The dialog could not be created: COM is not started on this thread, or
    /// the class is not registered.
    NotAvailable = 1u,

    /// It was shown, and something else went wrong reading the result.
    Other = 2u,
}

/// `CLSID_FileOpenDialog`.
public Guid FileOpenDialogId() { return Com.Parse("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7"); }

/// `CLSID_FileSaveDialog`.
public Guid FileSaveDialogId() { return Com.Parse("C0B4E2F3-BA21-4773-8DBA-335EC946EB8B"); }

/// The `FilterSpec` array an `IFileDialog` wants, built from the same
/// label-and-pattern pairs `BuildFilter` takes.
///
/// Simpler than the old filter in every way: an array of two pointers each,
/// rather than one buffer of NUL-separated text with a double NUL at the end.
/// The `Utf16String`s go in `held` because the specs point into them, and the
/// caller keeps that alive for as long as it uses the specs.
public FilterSpec[] BuildSpecs(String[] pairs, Utf16String[] held) {
    nuint count = pairs.Length / 2u;
    var specs = new FilterSpec[count];

    for (nuint i = 0u; i < count; i = i + 1u) {
        held[i * 2u]      = pairs[i * 2u].ToUtf16();
        held[i * 2u + 1u] = pairs[i * 2u + 1u].ToUtf16();

        specs[i].Name    = held[i * 2u].ToPointer();
        specs[i].Pattern = held[i * 2u + 1u].ToPointer();
    }
    return specs;
}

/// Applies the shared settings, and shows the dialog.
///
/// Split out because the open and save paths differ only in which interface
/// they hold and what they read out of it afterwards.
int Prepare(IFileDialog dialog, HWND owner, String title,
            String[] filterPairs, uint options) {
    if (!title.IsEmpty()) { dialog.SetTitle(title.ToUtf16().ToPointer()); }

    uint existing = 0u;
    dialog.GetOptions(&existing);
    dialog.SetOptions(existing | options);

    if (filterPairs.Length >= 2u) {
        var held = new Utf16String[filterPairs.Length];
        var specs = BuildSpecs(filterPairs, held);
        dialog.SetFileTypes((uint)specs.Length, &specs[0]);
    }

    return dialog.Show(owner);
}

/// The chosen item's path, or the reason there was not one.
Result<String, DialogError> Chosen(IFileDialog dialog, int shown) {
    if (Com.WasCancelled(shown)) { return Fail(DialogError.Cancelled); }
    if (Com.Failed(shown))       { return Fail(DialogError.Other); }

    byte* raw = null;
    if (Com.Failed(dialog.GetResult(&raw))) { return Fail(DialogError.Other); }

    // ARC releases the item at the end of this function; the path is a copy.
    IShellItem item = (IShellItem)raw;
    String path = Shell.PathOf(item);

    if (path.IsEmpty()) { return Fail(DialogError.Other); }
    return Ok(path);
}

/// Asks the user for one existing file.
///
/// `filterPairs` is label and pattern, alternating, as `BuildFilter` takes
/// them. An empty array shows everything.
///
/// ```
/// var picked = Dialogs.ChooseFile(null, "Open", ["Text files", "*.txt;*.log"]);
/// if (picked.Ok) { ... }
/// else if (picked.Error == DialogError.Cancelled) { ... }
/// ```
public Result<String, DialogError> ChooseFile(HWND owner, String title,
                                              String[] filterPairs) {
    var made = Com.Create(FileOpenDialogId(), iidof(IFileOpenDialog));
    if (!made.Ok) { return Fail(DialogError.NotAvailable); }

    IFileOpenDialog dialog = (IFileOpenDialog)made.Value;
    int shown = Prepare(dialog, owner, title, filterPairs,
                        OptionFileMustExist | OptionPathMustExist);
    return Chosen(dialog, shown);
}

/// Asks the user for one or more existing files.
public Result<String[], DialogError> ChooseFiles(HWND owner, String title,
                                                 String[] filterPairs) {
    var made = Com.Create(FileOpenDialogId(), iidof(IFileOpenDialog));
    if (!made.Ok) { return Fail(DialogError.NotAvailable); }

    IFileOpenDialog dialog = (IFileOpenDialog)made.Value;
    int shown = Prepare(dialog, owner, title, filterPairs,
                        OptionFileMustExist | OptionPathMustExist |
                        OptionAllowMultiselect);

    if (Com.WasCancelled(shown)) { return Fail(DialogError.Cancelled); }
    if (Com.Failed(shown))       { return Fail(DialogError.Other); }

    byte* raw = null;
    if (Com.Failed(dialog.GetResults(&raw))) { return Fail(DialogError.Other); }

    IShellItemArray items = (IShellItemArray)raw;
    return Ok(Shell.PathsOf(items));
}

/// Asks the user for a folder.
///
/// The same dialog with `PickFolders` set, which is why `SHBrowseForFolder` --
/// a different, worse dialog with none of the places bar -- is not bound.
public Result<String, DialogError> ChooseFolder(HWND owner, String title) {
    var made = Com.Create(FileOpenDialogId(), iidof(IFileOpenDialog));
    if (!made.Ok) { return Fail(DialogError.NotAvailable); }

    IFileOpenDialog dialog = (IFileOpenDialog)made.Value;
    var empty = new String[0u];
    int shown = Prepare(dialog, owner, title, empty,
                        OptionPickFolders | OptionPathMustExist);
    return Chosen(dialog, shown);
}

/// Asks the user where to save, warning before an overwrite.
///
/// `suggestedName` is what the name box starts with, and `defaultExtension` is
/// added when the user types a name without one. Either may be empty.
public Result<String, DialogError> ChooseSaveFile(HWND owner, String title,
                                                  String[] filterPairs,
                                                  String suggestedName,
                                                  String defaultExtension) {
    var made = Com.Create(FileSaveDialogId(), iidof(IFileSaveDialog));
    if (!made.Ok) { return Fail(DialogError.NotAvailable); }

    IFileSaveDialog dialog = (IFileSaveDialog)made.Value;

    if (!suggestedName.IsEmpty()) {
        dialog.SetFileName(suggestedName.ToUtf16().ToPointer());
    }
    if (!defaultExtension.IsEmpty()) {
        dialog.SetDefaultExtension(defaultExtension.ToUtf16().ToPointer());
    }

    int shown = Prepare(dialog, owner, title, filterPairs,
                        OptionOverwritePrompt | OptionPathMustExist);
    return Chosen(dialog, shown);
}

/// Opens a dialog already showing a folder, for the callers that want to start
/// somewhere in particular.
public Result<String, DialogError> ChooseFileIn(HWND owner, String title,
                                                String[] filterPairs,
                                                String startingFolder) {
    var made = Com.Create(FileOpenDialogId(), iidof(IFileOpenDialog));
    if (!made.Ok) { return Fail(DialogError.NotAvailable); }

    IFileOpenDialog dialog = (IFileOpenDialog)made.Value;

    var folder = Shell.ItemFromPath(startingFolder);
    if (folder.Ok) { dialog.SetFolder((byte*)folder.Value); }

    int shown = Prepare(dialog, owner, title, filterPairs,
                        OptionFileMustExist | OptionPathMustExist);
    return Chosen(dialog, shown);
}

#endif
