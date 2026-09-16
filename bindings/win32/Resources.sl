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

// What a program carries inside itself.
//
// A Windows executable has a section the loader indexes by *type* and *name*,
// and a `.rc` file listed among a build's sources is what puts things there:
//
// ```
// stainless build src app.rc -l user32
// ```
//
// ```
// // app.rc
// 101 BITMAP  "toolbar.bmp"
// 1   ICON    "app.ico"
// 1   24      "app.manifest"        // 24 is RT_MANIFEST
//
// STRINGTABLE BEGIN
//     201 "Ready"
//     202 "Saving..."
// END
// ```
//
// ```csharp
// import Win32.Resources;
//
// String ready = Resources.Text(201u);
// byte[] blob  = Resources.Bytes(Resources.Id(301), RtRcData());
// ```
//
// **This is a Windows idea and has no counterpart elsewhere.** ELF has no
// resource section at all; the nearest thing, GLib's GResource, is a
// name-to-bytes lookup that a library reads rather than something the loader
// knows about. The difference matters most for the three types that are not
// data but *description* -- `RT_MENU`, `RT_DIALOG` and `RT_ACCELERATOR` are a
// declarative UI format that Windows itself interprets, and nothing on another
// system reads them. A build for a target with no resource section leaves the
// script out and says so (SL0700).
//
// ## Names
//
// A resource is identified by a string or by a small integer, and Windows
// passes both through the same `char16*` parameter: an integer is cast to a
// pointer and recognised by being below 65536. That is `MAKEINTRESOURCE`, and
// `Id` below is it. Everything here takes a `char16*` name for that reason, so
// a custom string type and an integer id go to the same call.
//
// ## Lifetime
//
// Nothing here has to be freed. A resource lives in the mapped image, so the
// bytes `Pointer` hands back are valid for as long as the module is loaded and
// must never be written through. `Bytes` copies out of them, which is the safe
// thing and the reason it exists.
module Win32.Resources;

#if WINDOWS

// user32 for the loaders; kernel32 comes with the C runtime already.
#pragma comment(lib, "user32")

import Win32;
import Win32.Kernel32;
import Win32.User32;
import Win32.Handles;
import Win32.Version;
import Standard.Collections;

// ------------------------------------------------------------------- names

/// `MAKEINTRESOURCE`: an integer id as the name a resource API wants.
///
/// Windows reserves the bottom 64K of the pointer range for this, so an id
/// above 65535 is not representable and is the one thing a resource script
/// must not use. The cast is what the C macro does, nothing more.
public char16* Id(int id) => (char16*)(nuint)(uint)id;

/// True when a name is an integer id rather than a string, which is what a
/// callback from `EnumResourceNamesW` has to ask before reading it.
public bool IsId(char16* name) => (nuint)name < 65536u;

/// The integer behind such a name. Meaningless unless `IsId` said so.
public int IdOf(char16* name) => (int)(uint)(nuint)name;

/// A resource name as text, whichever of the two it is: `#101` for an integer
/// id, and the string itself otherwise.
///
/// The `#` spelling is the one a resource script uses for the same thing, so
/// what this prints can be pasted back into an `.rc`.
public String NameOf(char16* name)
{
    if (IsId(name))
        return $"#{IdOf(name)}";
    return Text.FromNullTerminatedUtf16(name);
}

// ----------------------------------------------------------------- modules

/// This program's own module, which is what every call here defaults to.
///
/// `GetModuleHandleW(null)` is the running executable rather than whichever
/// DLL this code was compiled into -- the two differ only for a library, which
/// is why `In` below exists.
public HMODULE Self() => GetModuleHandleW(null);

/// Opens another binary to read its resources and nothing else.
///
/// `LOAD_LIBRARY_AS_DATAFILE` maps the file without running any code in it: no
/// `DllMain`, no imports resolved, no chance of executing something. It is the
/// only safe way to read resources out of a file this program did not build,
/// and it is how an icon is pulled from an arbitrary `.exe`.
///
/// Null on failure; `Win32.LastErrorMessage` says why. What this returns must
/// be passed to `CloseModule` when it is done with.
public HMODULE OpenForResources(String path)
{
    return LoadLibraryExW(path.ToUtf16().ToPointer(), null, LoadLibraryAsDataFile);
}

/// Closes what `OpenForResources` opened.
public void CloseModule(HMODULE library)
{
    if (library != null)
        FreeLibrary(library);
}

// -------------------------------------------------------------- raw access

/// Whether a resource of this type and name is there at all.
public bool Exists(char16* name, char16* type) => Has(Self(), name, type);

/// The same, in another module.
public bool Has(HMODULE library, char16* name, char16* type)
{
    return FindResourceW(library, name, type) != null;
}

/// How many bytes a resource holds, or zero when there is no such resource.
public uint Size(char16* name, char16* type) => SizeIn(Self(), name, type);

/// The same, in another module.
public uint SizeIn(HMODULE library, char16* name, char16* type)
{
    HANDLE found = FindResourceW(library, name, type);
    if (found == null)
        return 0u;
    return SizeofResource(library, found);
}

/// A pointer straight at the resource's bytes, without copying them.
///
/// This is the fast path and the sharp one: the memory belongs to the mapped
/// image, so it is read-only, it must not be freed, and it stays valid exactly
/// as long as the module does. For anything that outlives the call, use
/// `Bytes`.
///
/// Null when there is no such resource. `size` is set either way.
public byte* Pointer(char16* name, char16* type, uint* size)
{
    return PointerIn(Self(), name, type, size);
}

/// The same, in another module.
public byte* PointerIn(HMODULE library, char16* name, char16* type, uint* size)
{
    if (size != null)
        *size = 0u;

    HANDLE found = FindResourceW(library, name, type);
    if (found == null)
        return null;

    HANDLE loaded = LoadResource(library, found);
    if (loaded == null)
        return null;

    void* at = LockResource(loaded);
    if (at == null)
        return null;

    if (size != null)
        *size = SizeofResource(library, found);
    return (byte*)at;
}

/// A resource's bytes, copied out into an array this program owns.
///
/// Empty when there is no such resource, which is the same answer an empty
/// resource gives -- ask `Exists` first where the difference matters.
public byte[] Bytes(char16* name, char16* type) => BytesIn(Self(), name, type);

/// The same, in another module.
public byte[] BytesIn(HMODULE library, char16* name, char16* type)
{
    uint size = 0u;
    byte* at = PointerIn(library, name, type, &size);
    if (at == null || size == 0u)
        return new byte[0];

    var copy = new byte[(nuint)size];
    for (int i = 0; i < (int)size; i = i + 1)
        copy[i] = at[i];
    return copy;
}

// ----------------------------------------------------------------- strings

/// One string from an `RT_STRING` table.
///
/// A string table is stored in blocks of sixteen and is not addressed the way
/// every other resource is, which is why this takes a plain id rather than a
/// name: `LoadStringW` works out which block holds it.
///
/// An id with no string is an empty string. Windows caps a table entry at
/// 4096 characters, so nothing is truncated here that was not truncated by
/// `rc` first.
public String Text(uint id) => TextIn(Self(), id);

/// The same, from another module.
public String TextIn(HMODULE library, uint id)
{
    var buffer = new WideBuffer(4096u);
    int units = LoadStringW((HINSTANCE)library, id, buffer.Pointer(), (int)buffer.Capacity);
    if (units <= 0)
        return "";
    return buffer.Text((uint)units);
}

// ------------------------------------------------------------------ images

/// An icon from an `RT_GROUP_ICON`, at the size the system wants for a window.
///
/// `LoadImageW` rather than `LoadIconW`, because an icon resource holds
/// several sizes and this is the call that picks one. `LrDefaultSize` takes
/// what `SM_CXICON` says, which is the large one; `IconSmall` takes the size
/// that goes in a title bar.
///
/// Null when there is no such icon. Shared, so there is nothing to destroy.
public HICON Icon(char16* name)
{
    return (HICON)LoadImageW((HINSTANCE)Self(), name, ImageIcon, 0, 0,
                             LrDefaultSize | LrShared);
}

/// The small icon, for a title bar and the task switcher.
public HICON IconSmall(char16* name)
{
    return (HICON)LoadImageW((HINSTANCE)Self(), name, ImageIcon,
                             GetSystemMetrics(SmSmallIconWidth),
                             GetSystemMetrics(SmSmallIconHeight),
                             LrShared);
}

/// A cursor from an `RT_GROUP_CURSOR`. Null when there is none.
public HCURSOR Cursor(char16* name)
{
    return (HCURSOR)LoadImageW((HINSTANCE)Self(), name, ImageCursor, 0, 0,
                               LrDefaultSize | LrShared);
}

/// A bitmap from an `RT_BITMAP`, at the size it was compiled at.
///
/// Not shared: what this returns is owned by the caller and wants
/// `DeleteObject` when it is finished with. `LrShared` is deliberately not
/// used here, because a bitmap is the one of these three that a program
/// usually goes on to select into a device context and modify around.
public HBITMAP Bitmap(char16* name)
{
    return (HBITMAP)LoadImageW((HINSTANCE)Self(), name, ImageBitmap, 0, 0, LrDefaultColor);
}

// -------------------------------------------------- menus and accelerators

/// A menu built from an `RT_MENU` template.
///
/// Null when there is no such menu. What this returns is owned by the caller
/// until `SetMenu` attaches it to a window, after which the window destroys it.
public HMENU Menu(char16* name)
{
    return LoadMenuW((HINSTANCE)Self(), name);
}

/// An accelerator table from an `RT_ACCELERATOR` resource.
///
/// A table is shared and never destroyed, so this can be called as often as is
/// convenient. It is only half of what accelerators need: the message loop has
/// to call `TranslateAcceleratorW` before dispatching, and *not* dispatch a
/// message the table took.
public HACCEL Accelerators(char16* name)
{
    return LoadAcceleratorsW((HINSTANCE)Self(), name);
}

// ----------------------------------------------------------------- version

/// A four-part version number, as `RT_VERSION` stores one.
public struct FileVersion
{
    public ushort Major;
    public ushort Minor;
    public ushort Build;
    public ushort Revision;

    /// The usual `1.2.3.4` spelling.
    public String Text() => $"{Major}.{Minor}.{Build}.{Revision}";
}

/// The version a binary reports, read from its `RT_VERSION` resource.
///
/// **Reads a file, not a loaded module**, because that is all `version.dll`
/// offers: `Own()` below is how a program asks about itself.
///
/// All zeroes when the file has no version resource, which is the ordinary
/// case for anything not built by a Windows toolchain that was told to add
/// one -- a Stainless binary has none unless its `.rc` says `VERSIONINFO`.
public FileVersion VersionOf(String path)
{
    FileVersion answer;
    answer.Major = 0u; answer.Minor = 0u; answer.Build = 0u; answer.Revision = 0u;

    var wide = path.ToUtf16();
    uint ignored = 0u;
    uint size = GetFileVersionInfoSizeW(wide.ToPointer(), &ignored);
    if (size == 0u)
        return answer;

    // The block has to outlive every query against it: `VerQueryValueW` hands
    // back a pointer into it rather than a copy. `buffer` living to the end of
    // this function is what makes that safe, and why the numbers are read out
    // before returning rather than the pointer being handed on.
    var buffer = new ByteBuffer(size);
    if (Failed(GetFileVersionInfoW(wide.ToPointer(), 0u, size, (void*)buffer.Pointer())))
    {
        return answer;
    }

    void* found = null;
    uint length = 0u;
    if (Failed(VerQueryValueW((void*)buffer.Pointer(), "\\".ToUtf16().ToPointer(),
                              &found, &length)))
    {
        return answer;
    }
    if (found == null || length < (uint)sizeof(FixedFileInfo))
        return answer;

    FixedFileInfo* fixed = (FixedFileInfo*)found;
    if (fixed->Signature != FixedFileInfoSignature)
        return answer;

    // Four 16-bit parts in two 32-bit words, most significant half first.
    answer.Major    = (ushort)(fixed->FileVersionMs >> 16);
    answer.Minor    = (ushort)(fixed->FileVersionMs & 0xFFFFu);
    answer.Build    = (ushort)(fixed->FileVersionLs >> 16);
    answer.Revision = (ushort)(fixed->FileVersionLs & 0xFFFFu);
    return answer;
}

/// This program's own version, which means finding its own path first.
public FileVersion Version()
{
    var buffer = new WideBuffer(32768u);
    uint units = GetModuleFileNameW(null, buffer.Pointer(), buffer.Capacity);
    if (units == 0u)
    {
        FileVersion none;
        none.Major = 0u; none.Minor = 0u; none.Build = 0u; none.Revision = 0u;
        return none;
    }
    return VersionOf(buffer.Text(units));
}

// ------------------------------------------------------------ enumeration

/// Every resource name of one type, as text.
///
/// For asking what a binary actually contains rather than assuming: a resource
/// editor, a build that verifies its own icons made it in, or a program
/// reading another file's resources through `OpenForResources`.
///
/// An integer id comes back in the `#101` spelling `NameOf` uses.
public String[] Names(char16* type) => NamesIn(Self(), type);

/// The same, in another module.
public String[] NamesIn(HMODULE library, char16* type)
{
    var found = new List<String>();

    // The callback cannot capture, being a plain C function pointer, so the
    // list travels through the `lParam` Windows passes along untouched. That
    // is what the parameter has always been for.
    EnumResourceNamesW(library, type, CollectName, (nint)(void*)found);

    return found.ToArray();
}

/// Every resource *type* a module carries, as text.
public String[] Types() => TypesIn(Self());

/// The same, in another module.
public String[] TypesIn(HMODULE library)
{
    var found = new List<String>();
    EnumResourceTypesW(library, CollectType, (nint)(void*)found);
    return found.ToArray();
}

int CollectName(HMODULE library, char16* type, char16* name, nint parameter)
{
    var into = (List<String>)(void*)parameter;
    into.Add(NameOf(name));
    return 1;
}

int CollectType(HMODULE library, char16* type, nint parameter)
{
    var into = (List<String>)(void*)parameter;
    into.Add(NameOf(type));
    return 1;
}

#endif
