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

// advapi32: the registry.
//
// **Link with `-l advapi32`.**
//
// The registry is the one part of Win32 that does not use `GetLastError`: every
// `Reg...` function *returns* its error code, and returns `ErrorSuccess` when it
// worked. The bindings pass that through unchanged, and the wrappers on top
// return a `Result` so a caller cannot read a value that was never read.
module Win32.Registry;

#if WINDOWS

import Win32;

public extern "C" {
    int RegOpenKeyExW(void* key, ushort* path, uint options, uint access, void** result);
    int RegCreateKeyExW(void* key, ushort* path, uint reserved, ushort* windowClass,
                        uint options, uint access, void* security,
                        void** result, uint* disposition);
    int RegCloseKey(void* key);
    int RegQueryValueExW(void* key, ushort* name, uint* reserved, uint* kind,
                         byte* data, uint* size);
    int RegSetValueExW(void* key, ushort* name, uint reserved, uint kind,
                       byte* data, uint size);
    int RegDeleteValueW(void* key, ushort* name);
    int RegDeleteKeyW(void* key, ushort* path);
    int RegEnumKeyExW(void* key, uint index, ushort* name, uint* nameSize,
                      uint* reserved, ushort* windowClass, uint* classSize,
                      void* lastWrite);
    int RegEnumValueW(void* key, uint index, ushort* name, uint* nameSize,
                      uint* reserved, uint* kind, byte* data, uint* dataSize);
    int RegQueryInfoKeyW(void* key, ushort* windowClass, uint* classSize,
                         uint* reserved, uint* subkeys, uint* maxSubkeyLength,
                         uint* maxClassLength, uint* values, uint* maxValueNameLength,
                         uint* maxValueLength, uint* securityDescriptor,
                         void* lastWrite);
    int RegFlushKey(void* key);
}

// ================================================================= the roots

/// The predefined keys. They are pointer-shaped constants rather than handles
/// anything opened, so they are never closed.
public void* ClassesRoot()  { return (void*)(nuint)0x80000000u; }
public void* CurrentUser()  { return (void*)(nuint)0x80000001u; }
public void* LocalMachine() { return (void*)(nuint)0x80000002u; }
public void* Users()        { return (void*)(nuint)0x80000003u; }
public void* CurrentConfig() { return (void*)(nuint)0x80000005u; }

// =================================================================== access

public const uint KeyQueryValue       = 0x0001u;
public const uint KeySetValue         = 0x0002u;
public const uint KeyCreateSubKey     = 0x0004u;
public const uint KeyEnumerateSubKeys = 0x0008u;
public const uint KeyNotify           = 0x0010u;
public const uint KeyCreateLink       = 0x0020u;

/// `KEY_READ` and `KEY_WRITE`, which are the two a program normally wants.
public const uint KeyRead      = 0x20019u;
public const uint KeyWrite     = 0x20006u;
public const uint KeyAllAccess = 0xF003Fu;

/// Which view of the registry to use on a 64-bit system, where a 32-bit program
/// is redirected into `Wow6432Node` unless it says otherwise.
public const uint KeyWow6464Key = 0x0100u;
public const uint KeyWow6432Key = 0x0200u;

// ==================================================================== kinds

public const uint KindNone         = 0u;
public const uint KindString       = 1u;    // REG_SZ
public const uint KindExpandString = 2u;    // REG_EXPAND_SZ
public const uint KindBinary       = 3u;
public const uint KindUInt         = 4u;    // REG_DWORD
public const uint KindMultiString  = 7u;
public const uint KindULong        = 11u;   // REG_QWORD

// ============================================================== the wrappers

/// Why a registry read did not produce a value.
public enum RegistryError : uint {
    None        = 0u,
    NotFound    = 2u,
    AccessDenied = 5u,
    MoreData    = 234u,
    NoMoreItems = 259u,

    /// Something the enumeration above does not name; the code itself is in
    /// `Win32.Describe` territory rather than this one's.
    Other       = 0xFFFFFFFFu,
}

RegistryError Classify(int code) {
    if (code == 0)   { return RegistryError.None; }
    if (code == 2)   { return RegistryError.NotFound; }
    if (code == 5)   { return RegistryError.AccessDenied; }
    if (code == 234) { return RegistryError.MoreData; }
    if (code == 259) { return RegistryError.NoMoreItems; }
    return RegistryError.Other;
}

/// Opens a key for reading, or fails.
///
/// The handle must be closed with `Close`. `root` is one of the predefined
/// keys, and `path` is relative to it: `Open(LocalMachine(), "SOFTWARE\\...")`.
public Result<void*, RegistryError> Open(void* root, String path, uint access) {
    void* key = null;
    int code = RegOpenKeyExW(root, path.ToUtf16().ToPointer(), 0u, access, &key);
    if (code != 0) { return Fail(Classify(code)); }
    return Ok(key);
}

/// Opens a key for reading, which is what most callers want.
public Result<void*, RegistryError> OpenRead(void* root, String path) {
    return Open(root, path, KeyRead);
}

/// Opens a key, creating it and every missing parent if it is not there.
public Result<void*, RegistryError> Create(void* root, String path, uint access) {
    void* key = null;
    uint disposition = 0u;
    int code = RegCreateKeyExW(root, path.ToUtf16().ToPointer(), 0u, null, 0u,
                               access, null, &key, &disposition);
    if (code != 0) { return Fail(Classify(code)); }
    return Ok(key);
}

public bool Close(void* key) { return RegCloseKey(key) == 0; }

/// A string value, or why there was not one.
///
/// `REG_SZ` and `REG_EXPAND_SZ` both read as strings; an expandable one is
/// returned with its `%VARIABLES%` still in it, and `Win32.Kernel.Expand` is
/// what fills them in.
public Result<String, RegistryError> ReadString(void* key, String name) {
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
public Result<uint, RegistryError> ReadUInt(void* key, String name) {
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
public Result<ulong, RegistryError> ReadULong(void* key, String name) {
    var buffer = new ByteBuffer(16u);
    uint size = 8u;
    uint kind = 0u;

    int code = RegQueryValueExW(key, name.ToUtf16().ToPointer(), null, &kind,
                                buffer.Pointer(), &size);
    if (code != 0) { return Fail(Classify(code)); }
    if (kind != KindULong) { return Fail(RegistryError.Other); }

    return Ok(buffer.AsULong());
}

/// Writes a `REG_SZ`. The size Windows wants includes the terminator, in bytes.
public RegistryError WriteString(void* key, String name, String value) {
    var wide = value.ToUtf16();
    uint bytes = (uint)((wide.UnitCount() + 1u) * 2u);
    int code = RegSetValueExW(key, name.ToUtf16().ToPointer(), 0u, KindString,
                              (byte*)wide.ToPointer(), bytes);
    return Classify(code);
}

/// Writes a `REG_DWORD`.
public RegistryError WriteUInt(void* key, String name, uint value) {
    uint stored = value;
    int code = RegSetValueExW(key, name.ToUtf16().ToPointer(), 0u, KindUInt,
                              (byte*)&stored, 4u);
    return Classify(code);
}

/// Removes a value from a key.
public RegistryError DeleteValue(void* key, String name) {
    return Classify(RegDeleteValueW(key, name.ToUtf16().ToPointer()));
}

/// The name of the `index`th subkey, or an empty string past the end.
///
/// A registry key name is at most 255 characters, which is why the buffer is
/// that size and no thought is given to it being too small.
public String SubKey(void* key, uint index) {
    var buffer = new WideBuffer(256u);
    uint size = (uint)(buffer.Capacity() + 1u);

    int code = RegEnumKeyExW(key, index, buffer.Pointer(), &size,
                             null, null, null, null);
    if (code != 0) { return ""; }
    return buffer.Text(size);
}

/// The name of the `index`th value, or an empty string past the end.
public String ValueName(void* key, uint index) {
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

public KeyCounts Counts(void* key) {
    KeyCounts counts;
    counts.SubKeys = 0u;
    counts.Values = 0u;
    RegQueryInfoKeyW(key, null, null, null, &counts.SubKeys, null, null,
                     &counts.Values, null, null, null, null);
    return counts;
}

#endif
