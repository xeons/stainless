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
#pragma comment(lib, "ole32")

import Standard.Com;
import Standard.Text;
import Win32;
import Win32.Com;
import Win32.Ole32;
import Win32.Shell32;
import Win32.ShellCom;
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

// ============================================================ known folders

// The folders Windows keeps for a user, named by GUID.
//
// `SHGetFolderPathW`'s integers (`Win32.Shell32.Folder...`) still work and
// still name the same places, but they stopped being added to: Downloads and
// SavedGames have no number, and never will. These are the current answer.
//
// Each is a function rather than a `static readonly`, because a `--shared`
// build has no entry point to run a static initializer from (SL0380) and these
// modules should compile either way. The cost is one `CLSIDFromString` per
// lookup, against a shell call that is thousands of times dearer.

/// `FOLDERID_Desktop`.
public Guid DesktopId() { return Com.Parse("B4BFCC3A-DB2C-424C-B029-7FE99A87C641"); }
/// `FOLDERID_Documents`.
public Guid DocumentsId() { return Com.Parse("FDD39AD0-238F-46AF-ADB4-6C85480369C7"); }
/// `FOLDERID_Downloads`.
public Guid DownloadsId() { return Com.Parse("374DE290-123F-4565-9164-39C4925E467B"); }
/// `FOLDERID_Pictures`.
public Guid PicturesId() { return Com.Parse("33E28130-4E1E-4676-835A-98395C3BC3BB"); }
/// `FOLDERID_Music`.
public Guid MusicId() { return Com.Parse("4BD8D571-6D19-48D3-BE97-422220080E43"); }
/// `FOLDERID_Videos`.
public Guid VideosId() { return Com.Parse("18989B1D-99B5-455B-841C-AB7C74E4DDFC"); }
/// `FOLDERID_SavedGames`.
public Guid SavedGamesId() { return Com.Parse("4C5C32FF-BB9D-43B0-B5B4-2D72E54EAAA4"); }
/// `FOLDERID_RoamingAppData`.
public Guid RoamingAppDataId() { return Com.Parse("3EB685DB-65F9-4CF6-A03A-E3EF65729F3D"); }
/// `FOLDERID_LocalAppData`.
public Guid LocalAppDataId() { return Com.Parse("F1B32785-6FBA-4FCF-9D55-7B8E7F157091"); }
/// `FOLDERID_ProgramData`.
public Guid ProgramDataId() { return Com.Parse("62AB5D82-FDC1-4DC3-A9DD-070D1D495D97"); }
/// `FOLDERID_Profile`.
public Guid ProfileId() { return Com.Parse("5E6C858F-0E22-4760-9AFE-EA3317B67173"); }
/// `FOLDERID_Windows`.
public Guid WindowsId() { return Com.Parse("F38BF404-1D43-42F2-9305-67DE0B28FC23"); }
/// `FOLDERID_System`.
public Guid SystemId() { return Com.Parse("1AC14E77-02E7-4E5D-B744-2EB1AE5198B7"); }
/// `FOLDERID_ProgramFiles`.
public Guid ProgramFilesId() { return Com.Parse("905E63B6-C1BF-494E-B29C-65B732D3D21A"); }
/// `FOLDERID_Fonts`.
public Guid FontsId() { return Com.Parse("FD228CB7-AE11-4AE3-864C-16F3910AB8FE"); }
/// `FOLDERID_Startup`.
public Guid StartupId() { return Com.Parse("B97D20BB-F46A-4C97-BA10-5E3608430854"); }
/// `FOLDERID_Programs`.
public Guid ProgramsId() { return Com.Parse("A77F5D77-2E2B-44C3-A6A2-ABA601054A51"); }
/// `FOLDERID_Public`.
public Guid PublicId() { return Com.Parse("DFDF76A2-C82A-4D63-906A-5644AC457385"); }

/// The path of a known folder, or why there was not one.
///
/// The folder is named by GUID -- one of the accessors below, or any other
/// `KNOWNFOLDERID`. It fails for a folder that is registered and not created,
/// which is what `KnownFolderCreate` is for, and for a folder that has no path
/// at all.
public Result<String, ComError> KnownFolder(Guid folder) {
    return KnownFolderWith(folder, KnownFolderDefault);
}

/// The same, creating the folder if it is registered and not yet made.
public Result<String, ComError> KnownFolderCreating(Guid folder) {
    return KnownFolderWith(folder, KnownFolderCreate);
}

/// The path of a known folder with `SHGetKnownFolderPath`'s flags spelled out.
public Result<String, ComError> KnownFolderWith(Guid folder, uint flags) {
    char16* path = null;
    int hr = SHGetKnownFolderPath(&folder, flags, null, &path);

    // The string is CoTaskMemAlloc'd and the caller's to free, which TakeString
    // does -- so there is no path through this that leaks it.
    if (Com.Failed(hr)) { return Fail(Com.Classify(hr)); }
    return Ok(Com.TakeString(path));
}

/// The user's desktop.
public Result<String, ComError> Desktop() { return KnownFolder(DesktopId()); }

/// The user's Documents folder.
public Result<String, ComError> Documents() { return KnownFolder(DocumentsId()); }

/// The user's Downloads folder, which has no `SHGetFolderPathW` number and is
/// the usual reason to want this API at all.
public Result<String, ComError> Downloads() { return KnownFolder(DownloadsId()); }

/// The user's Pictures folder.
public Result<String, ComError> Pictures() { return KnownFolder(PicturesId()); }

/// The user's Music folder.
public Result<String, ComError> Music() { return KnownFolder(MusicId()); }

/// The user's Videos folder.
public Result<String, ComError> Videos() { return KnownFolder(VideosId()); }

/// The user's Saved Games folder, which also has no number.
public Result<String, ComError> SavedGames() { return KnownFolder(SavedGamesId()); }

/// Roaming application data: settings that follow the user between machines.
public Result<String, ComError> AppData() { return KnownFolder(RoamingAppDataId()); }

/// Local application data: caches and anything too large to roam.
public Result<String, ComError> LocalAppData() { return KnownFolder(LocalAppDataId()); }

/// Application data shared by every user of the machine.
public Result<String, ComError> ProgramData() { return KnownFolder(ProgramDataId()); }

/// The user's profile directory, the parent of most of the above.
public Result<String, ComError> Profile() { return KnownFolder(ProfileId()); }

/// The Windows directory.
public Result<String, ComError> WindowsFolder() { return KnownFolder(WindowsId()); }

/// The system32 directory.
public Result<String, ComError> System() { return KnownFolder(SystemId()); }

/// The 64-bit Program Files directory.
public Result<String, ComError> ProgramFiles() { return KnownFolder(ProgramFilesId()); }

/// The fonts directory.
public Result<String, ComError> Fonts() { return KnownFolder(FontsId()); }

/// The user's Startup folder, whose contents run at logon.
public Result<String, ComError> Startup() { return KnownFolder(StartupId()); }

/// The user's Start menu Programs folder.
public Result<String, ComError> Programs() { return KnownFolder(ProgramsId()); }

/// The Public profile, shared by every user.
public Result<String, ComError> PublicFolder() { return KnownFolder(PublicId()); }

// ============================================================= shell items

/// The `IShellItem` for a path, or why there was not one.
///
/// This is the door into everything the shell has added since Vista: an item
/// is what `IFileDialog.SetFolder`, `IShellItemArray` and the rest all speak
/// in. The reference is counted by ARC, so nothing here needs releasing.
public Result<IShellItem, ComError> ItemFromPath(String path) {
    byte* raw = null;
    int hr = SHCreateItemFromParsingName(
        path.ToUtf16().ToPointer(), null, iidof(IShellItem), &raw);

    if (Com.Failed(hr)) { return Fail(Com.Classify(hr)); }
    return Ok((IShellItem)raw);
}

/// A shell item's full path, or the empty string for an item that has none --
/// a control panel entry, a device, a search result.
public String PathOf(IShellItem item) {
    char16* name = null;
    if (Com.Failed(item.GetDisplayName(NameFileSystemPath, &name))) { return ""; }
    return Com.TakeString(name);
}

/// A shell item's name as the user sees it, which is not its path: a folder
/// may be localised, and a file may have its extension hidden.
public String NameOf(IShellItem item) {
    char16* name = null;
    if (Com.Failed(item.GetDisplayName(NameNormalDisplay, &name))) { return ""; }
    return Com.TakeString(name);
}

/// Whether a shell item is a folder rather than a file.
public bool IsFolder(IShellItem item) {
    uint attributes = 0u;

    // GetAttributes answers S_FALSE when only some of the asked-for bits are
    // set, which is a success, so the sign is what to test rather than S_OK.
    if (Com.Failed(item.GetAttributes(AttributeFolder, &attributes))) { return false; }
    return (attributes & AttributeFolder) != 0u;
}

/// The item's parent folder, or nothing when it is a root.
public Result<IShellItem, ComError> ParentOf(IShellItem item) {
    byte* raw = null;
    int hr = item.GetParent(&raw);

    if (Com.Failed(hr)) { return Fail(Com.Classify(hr)); }
    return Ok((IShellItem)raw);
}

/// How many items an array holds.
public uint CountOf(IShellItemArray items) {
    uint count = 0u;
    if (Com.Failed(items.GetCount(&count))) { return 0u; }
    return count;
}

/// One item out of an array, or nothing when the index is past the end.
public Result<IShellItem, ComError> ItemAt(IShellItemArray items, uint index) {
    byte* raw = null;
    int hr = items.GetItemAt(index, &raw);

    if (Com.Failed(hr)) { return Fail(Com.Classify(hr)); }
    return Ok((IShellItem)raw);
}

/// Every path in an array, skipping any item that has none.
///
/// What a multi-select open dialog is for, and the shape a program actually
/// wants: a `String[]` rather than a COM enumerator.
public String[] PathsOf(IShellItemArray items) {
    nuint count = (nuint)CountOf(items);
    var paths = new String[count];

    nuint found = 0u;
    for (nuint i = 0u; i < count; i = i + 1u) {
        var got = ItemAt(items, (uint)i);
        if (!got.Ok) { continue; }

        String path = PathOf(got.Value);
        if (path.IsEmpty()) { continue; }

        paths[found] = path;
        found = found + 1u;
    }

    if (found == count) { return paths; }

    // Some items had no path, so the array is longer than what was found.
    var exact = new String[found];
    for (nuint i = 0u; i < found; i = i + 1u) { exact[i] = paths[i]; }
    return exact;
}

#endif
