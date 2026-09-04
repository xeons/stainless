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

// The registry, as values that cannot be read before they are checked.
//
// A convenience layer over `Win32.AdvApi32`. It names advapi32 itself with a
// pragma, so a program compiling it needs no `-l`.
//
// Every `Reg...` function returns its error code rather than setting
// `GetLastError`, so this is the one part of Win32 whose failures were already
// values. Turning them into a `Result` costs nothing and makes reading one
// impossible until it has been checked.
module Win32.Registry;

#if WINDOWS

// The library this module needs, so that a program compiling it does not
// have to repeat the name on its own command line.
#pragma comment(lib, "advapi32")

import Win32;
import Win32.AdvApi32;
import Win32.Handles;

/// Why a registry operation did not produce a value.
public enum RegistryError : uint {
    None         = 0u,
    NotFound     = 2u,
    AccessDenied = 5u,
    MoreData     = 234u,
    NoMoreItems  = 259u,

    /// Something the enumeration above does not name, including a value that
    /// is there but is not the kind that was asked for. `Win32.Describe` will
    /// say what the raw code meant.
    Other        = 0xFFFFFFFFu,
}

/// A code from a `Reg...` call as one of the errors above.
public RegistryError Classify(int code) {
    if (code == 0)   { return RegistryError.None; }
    if (code == 2)   { return RegistryError.NotFound; }
    if (code == 5)   { return RegistryError.AccessDenied; }
    if (code == 234) { return RegistryError.MoreData; }
    if (code == 259) { return RegistryError.NoMoreItems; }
    return RegistryError.Other;
}

// ==================================================================== keys

/// Opens a key, or fails.
///
/// The handle must be closed with `Close`. `root` is one of `Win32.AdvApi32`'s
/// predefined keys, and `path` is relative to it:
/// `Open(LocalMachine(), "SOFTWARE\\...", KeyRead)`.
public Result<HKEY, RegistryError> Open(HKEY root, String path, uint access) {
    HKEY key = null;
    int code = RegOpenKeyExW(root, path.ToUtf16().ToPointer(), 0u, access, &key);
    if (code != 0) { return Fail(Classify(code)); }
    return Ok(key);
}

/// Opens a key for reading, which is what most callers want.
public Result<HKEY, RegistryError> OpenRead(HKEY root, String path) {
    return Open(root, path, KeyRead);
}

/// Opens a key, creating it and every missing parent if it is not there.
public Result<HKEY, RegistryError> Create(HKEY root, String path, uint access) {
    HKEY key = null;
    uint disposition = 0u;
    int code = RegCreateKeyExW(root, path.ToUtf16().ToPointer(), 0u, null, 0u,
                               access, null, &key, &disposition);
    if (code != 0) { return Fail(Classify(code)); }
    return Ok(key);
}

public bool Close(HKEY key) { return RegCloseKey(key) == 0; }

// ================================================================== reading

/// A string value, or why there was not one.
///
/// `REG_SZ` and `REG_EXPAND_SZ` both read as strings; an expandable one is
/// returned with its `%VARIABLES%` still in it, and `Win32.Environment.Expand`
/// is what fills them in.
public Result<String, RegistryError> ReadString(HKEY key, String name) {
    var buffer = new ByteBuffer(8192u);
    uint size = buffer.Capacity();
    uint kind = 0u;

    int code = RegQueryValueExW(key, name.ToUtf16().ToPointer(), null, &kind,
                                buffer.Pointer(), &size);
    if (code != 0) { return Fail(Classify(code)); }
    if (kind != KindString && kind != KindExpandString) {
        return Fail(RegistryError.Other);
    }

    return Ok(buffer.AsText());
}

/// A `REG_DWORD`.
public Result<uint, RegistryError> ReadUInt(HKEY key, String name) {
    var buffer = new ByteBuffer(8u);
    uint size = 4u;
    uint kind = 0u;

    int code = RegQueryValueExW(key, name.ToUtf16().ToPointer(), null, &kind,
                                buffer.Pointer(), &size);
    if (code != 0) { return Fail(Classify(code)); }
    if (kind != KindUInt) { return Fail(RegistryError.Other); }

    return Ok(buffer.AsUInt());
}

/// A `REG_QWORD`.
public Result<ulong, RegistryError> ReadULong(HKEY key, String name) {
    var buffer = new ByteBuffer(16u);
    uint size = 8u;
    uint kind = 0u;

    int code = RegQueryValueExW(key, name.ToUtf16().ToPointer(), null, &kind,
                                buffer.Pointer(), &size);
    if (code != 0) { return Fail(Classify(code)); }
    if (kind != KindULong) { return Fail(RegistryError.Other); }

    return Ok(buffer.AsULong());
}

// ================================================================== writing

/// Writes a `REG_SZ`. The size Windows wants includes the terminator, in bytes.
public RegistryError WriteString(HKEY key, String name, String value) {
    var wide = value.ToUtf16();
    uint bytes = (uint)((wide.UnitCount() + 1u) * 2u);
    int code = RegSetValueExW(key, name.ToUtf16().ToPointer(), 0u, KindString,
                              (byte*)wide.ToPointer(), bytes);
    return Classify(code);
}

/// Writes a `REG_DWORD`.
public RegistryError WriteUInt(HKEY key, String name, uint value) {
    uint stored = value;
    int code = RegSetValueExW(key, name.ToUtf16().ToPointer(), 0u, KindUInt,
                              (byte*)&stored, 4u);
    return Classify(code);
}

/// Removes a value from a key.
public RegistryError DeleteValue(HKEY key, String name) {
    return Classify(RegDeleteValueW(key, name.ToUtf16().ToPointer()));
}

// ============================================================== enumeration

/// The name of the `index`th subkey, or an empty string past the end.
///
/// A registry key name is at most 255 characters, which is why the buffer is
/// that size and no thought is given to it being too small.
public String SubKey(HKEY key, uint index) {
    var buffer = new WideBuffer(256u);
    uint size = (uint)(buffer.Capacity() + 1u);

    int code = RegEnumKeyExW(key, index, buffer.Pointer(), &size,
                             null, null, null, null);
    if (code != 0) { return ""; }
    return buffer.Text(size);
}

/// The name of the `index`th value, or an empty string past the end.
public String ValueName(HKEY key, uint index) {
    var buffer = new WideBuffer(16384u);
    uint size = (uint)(buffer.Capacity() + 1u);

    int code = RegEnumValueW(key, index, buffer.Pointer(), &size,
                             null, null, null, null);
    if (code != 0) { return ""; }
    return buffer.Text(size);
}

/// How many subkeys and how many values a key has, so an enumeration knows
/// where to stop.
public struct KeyCounts {
    public uint SubKeys;
    public uint Values;
}

public KeyCounts Counts(HKEY key) {
    KeyCounts counts;
    counts.SubKeys = 0u;
    counts.Values = 0u;
    RegQueryInfoKeyW(key, null, null, null, &counts.SubKeys, null, null,
                     &counts.Values, null, null, null, null);
    return counts;
}

#endif
