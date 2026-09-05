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

// The shell's COM interfaces: shell items, and the dialogs built on them.
//
// Declarations and nothing else, spelled as `ShObjIdl.h` spells them. The
// method order *is* the vtable, so nothing here may be reordered or removed
// without changing what every call means -- a method that is not wanted is
// still declared, because slot 7 has to be slot 7. That is why several below
// take `byte*` for an interface this binding does not declare: the parameter
// is never passed, and the slot has to exist.
//
// Every interface extends `IUnknown` whether or not it says so, so a
// declaration's own first method is slot 3.
//
// See §8.5 of the spec for what `com interface` is, and `Win32.Shell` and
// `Win32.Dialogs` for the conveniences over these.
module Win32.ShellCom;

import Standard.Com;
import Win32.Handles;

#if WINDOWS

// ============================================================= shell items

/// A thing in the shell namespace: a file, a folder, a drive, or something
/// with no path at all such as a library or a device.
///
/// The modern replacement for a PIDL, and what every current shell API takes
/// and returns.
[Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe")]
public com interface IShellItem {
    int BindToHandler(byte* bindContext, Guid* handler, Guid* interfaceId, byte** result);
    int GetParent(byte** parent);
    int GetDisplayName(uint kind, char16** name);
    int GetAttributes(uint mask, uint* attributes);
    int Compare(byte* other, uint hint, int* order);
}

/// A shell item that also answers property queries. Declared for its IID and
/// its first three slots; the property methods it adds are not bound.
[Guid("7e9fb0d3-919f-4307-ab2e-9b1860310c93")]
public com interface IShellItem2 : IShellItem {
    int GetPropertyStore(uint flags, Guid* interfaceId, byte** store);
    int GetPropertyStoreWithCreateObject(uint flags, byte* createObject,
                                         Guid* interfaceId, byte** store);
    int GetPropertyStoreForKeys(byte* keys, uint count, uint flags,
                                Guid* interfaceId, byte** store);
    int GetPropertyDescriptionList(byte* keyType, Guid* interfaceId, byte** list);
    int Update(byte* bindContext);
    int GetProperty(byte* key, byte* value);
    int GetCLSID(byte* key, Guid* value);
    int GetFileTime(byte* key, ulong* value);
    int GetInt32(byte* key, int* value);
    int GetString(byte* key, char16** value);
    int GetUInt32(byte* key, uint* value);
    int GetUInt64(byte* key, ulong* value);
    int GetBool(byte* key, int* value);
}

/// Several shell items at once: what an open dialog hands back when more than
/// one file may be chosen.
[Guid("b63ea76d-1f85-456f-a19c-48159efa858b")]
public com interface IShellItemArray {
    int BindToHandler(byte* bindContext, Guid* handler, Guid* interfaceId, byte** result);
    int GetPropertyStore(uint flags, Guid* interfaceId, byte** store);
    int GetPropertyDescriptionList(byte* keyType, Guid* interfaceId, byte** list);
    int GetAttributes(uint options, uint mask, uint* attributes);
    int GetCount(uint* count);
    int GetItemAt(uint index, byte** item);
    int EnumItems(byte** enumerator);
}

/// `IShellItem.GetDisplayName`'s spellings. The name a user reads and the path
/// a program opens are different questions, and this is which one is being
/// asked.
public const uint NameNormalDisplay        = 0x00000000u;
public const uint NameParentRelativeParsing = 0x80018001u;
public const uint NameDesktopAbsoluteParsing = 0x80028000u;
public const uint NameParentRelativeEditing = 0x80031001u;
public const uint NameDesktopAbsoluteEditing = 0x8004c000u;

/// The full path, which is what a program that is going to open the file
/// wants. It fails for an item that has no path -- a control panel entry, a
/// device -- which is the point of it being a separate spelling.
public const uint NameFileSystemPath = 0x80058000u;

public const uint NameUrl                  = 0x80068000u;
public const uint NameParentRelativeForAddressBar = 0x8007c001u;
public const uint NameParentRelative       = 0x80080001u;

/// `IShellItem.GetAttributes` bits, of which these are the ones worth asking.
public const uint AttributeFolder      = 0x20000000u;
public const uint AttributeFileSystem  = 0x40000000u;
public const uint AttributeStream      = 0x00400000u;
public const uint AttributeReadOnly    = 0x00040000u;
public const uint AttributeHidden      = 0x00080000u;
public const uint AttributeLink        = 0x00010000u;

// ============================================================ file dialogs

/// A dialog that takes over its owner window until it is dismissed. The base
/// of every file dialog, and the one method they all share.
[Guid("b4db1657-70d7-485e-8e3e-6fcb5a5c1802")]
public com interface IModalWindow {
    /// Blocks until the user chooses or cancels. Cancelling is not an error
    /// but it is a failure code -- `Win32.Ole32.Cancelled` -- which is why
    /// `Win32.Dialogs` returns an optional rather than a `Result`.
    int Show(HWND owner);
}

/// The Vista-era file dialog: everything `GetOpenFileNameW` did, plus places,
/// libraries, item types and a shell namespace rather than a path.
///
/// This is the base both directions share. `IFileOpenDialog` and
/// `IFileSaveDialog` each add their own methods after it.
[Guid("42f85136-db7e-439c-85f1-e4075d135fc8")]
public com interface IFileDialog : IModalWindow {
    int SetFileTypes(uint count, FilterSpec* types);
    int SetFileTypeIndex(uint index);
    int GetFileTypeIndex(uint* index);
    int Advise(byte* events, uint* cookie);
    int Unadvise(uint cookie);
    int SetOptions(uint options);
    int GetOptions(uint* options);
    int SetDefaultFolder(byte* folder);
    int SetFolder(byte* folder);
    int GetFolder(byte** folder);
    int GetCurrentSelection(byte** item);
    int SetFileName(char16* name);
    int GetFileName(char16** name);
    int SetTitle(char16* title);
    int SetOkButtonLabel(char16* text);
    int SetFileNameLabel(char16* text);
    int GetResult(byte** item);
    int AddPlace(byte* item, int placement);
    int SetDefaultExtension(char16* extension);
    int Close(int result);
    int SetClientGuid(Guid* client);
    int ClearClientData();
    int SetFilter(byte* filter);
}

/// Opening. `GetResults` is the plural of `GetResult` and is what
/// `AllowMultiselect` makes useful.
[Guid("d57c7288-d4ad-4768-be02-9d969532d960")]
public com interface IFileOpenDialog : IFileDialog {
    int GetResults(byte** items);
    int GetSelectedItems(byte** items);
}

/// Saving. The extra methods are about writing back into a file that already
/// exists, which this binding does not use but whose slots must be here.
[Guid("84bccd23-5fde-4cdb-aea4-af64b83d78ab")]
public com interface IFileSaveDialog : IFileDialog {
    int SetSaveAsItem(byte* item);
    int SetProperties(byte* store);
    int SetCollectedProperties(byte* list, int appendDefault);
    int GetProperties(byte** store);
    int ApplyProperties(byte* item, byte* store, HWND owner, byte* sink);
}

/// One entry of a file dialog's type list: what the user reads, and the
/// semicolon-separated patterns it stands for.
///
/// Unlike `OPENFILENAMEW`'s filter this is an array of two pointers rather
/// than one buffer of NUL-separated text, so building it needs no
/// `WideBuffer`.
public struct FilterSpec {
    /// "Text files"
    public char16* Name;
    /// "*.txt;*.log"
    public char16* Pattern;
}

// ------------------------------------------------------- FILEOPENDIALOGOPTIONS

/// Show files that are usually hidden.
public const uint OptionForceShowHidden = 0x10000000u;

/// Choose a folder rather than a file. The reason `IFileDialog` replaced
/// `SHBrowseForFolder`, which was the same dialog with none of the features.
public const uint OptionPickFolders = 0x00000020u;

/// More than one file at a time. Open only.
public const uint OptionAllowMultiselect = 0x00000200u;

/// The file must already exist.
public const uint OptionFileMustExist = 0x00001000u;

/// The folder must already exist.
public const uint OptionPathMustExist = 0x00000800u;

/// Warn before overwriting. Save dialogs set this by default.
public const uint OptionOverwritePrompt = 0x00000002u;

/// Warn if the file is not there. Open dialogs set this by default.
public const uint OptionCreatePrompt = 0x00002000u;

/// Do not add what was chosen to the recent documents list.
public const uint OptionDontAddToRecent = 0x02000000u;

/// Let the user type a name that is not in the list, rather than only pick.
public const uint OptionNoValidate = 0x00000100u;

/// Return the shortcut rather than what it points at.
public const uint OptionNoDereferenceLinks = 0x00100000u;

/// Do not change the process's working directory, which the dialog otherwise
/// does and which is almost never wanted.
public const uint OptionNoChangeDir = 0x00000008u;

/// `IFileDialog.AddPlace`'s two ends of the list.
public const int PlaceBottom = 0;
public const int PlaceTop    = 1;

#endif
