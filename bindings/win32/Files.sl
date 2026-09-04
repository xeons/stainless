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

// Files and directories, with paths as text.
//
// A convenience layer over `Win32.Kernel32`, which is where the declarations
// are. Nothing here needs a `-l`.
//
// `Standard.File` and `Standard.Directory` are the portable way to do most of
// this, and are what a program that does not care about Windows should use.
// This exists for the parts that have no portable spelling: the exact share
// mode, the exact disposition, the attributes, and a directory walk that hands
// back one entry at a time.
module Win32.Files;

#if WINDOWS

import Win32;
import Win32.Kernel32;
import Win32.Handles;
import Standard.Collections;

/// Opens or creates a file, taking the path as text.
///
/// Returns `InvalidHandle()` on failure — not null — and the reason is in
/// `Win32.LastError()`. `Win32.IsInvalid` covers both conventions.
public HANDLE Open(String path, uint access, uint shareMode, uint disposition) {
    return CreateFileW(path.ToUtf16().ToPointer(), access, shareMode, null,
                       disposition, FileAttributeNormal, null);
}

/// Opens an existing file for reading, sharing it with other readers.
public HANDLE OpenRead(String path) {
    return Open(path, GenericRead, FileShareRead, OpenExisting);
}

/// Creates a file, or replaces what is there.
public HANDLE Create(String path) {
    return Open(path, GenericWrite, 0u, CreateAlways);
}

/// True when something exists at this path, of any kind.
public bool Exists(String path) {
    return GetFileAttributesW(path.ToUtf16().ToPointer()) != InvalidFileAttributes;
}

/// True when the path names a directory. False when it names a file *and* when
/// there is nothing there, so it is not the negation of a file test.
public bool IsDirectory(String path) {
    uint attributes = GetFileAttributesW(path.ToUtf16().ToPointer());
    if (attributes == InvalidFileAttributes) { return false; }
    return (attributes & FileAttributeDirectory) != 0u;
}

/// The path with `.`, `..` and a relative prefix resolved against the current
/// directory. Windows does this textually; it does not touch the filesystem, so
/// it works for a path that is not there.
public String FullPath(String path) {
    var buffer = new WideBuffer(32768u);
    uint units = GetFullPathNameW(path.ToUtf16().ToPointer(), buffer.Capacity(),
                                  buffer.Pointer(), null);
    if (units == 0u) { return ""; }
    return buffer.Text(units);
}

/// The directory Windows hands out for temporary files, with its trailing
/// separator, which Windows includes and callers routinely forget.
public String TempPath() {
    var buffer = new WideBuffer(32768u);
    uint units = GetTempPathW(buffer.Capacity(), buffer.Pointer());
    if (units == 0u) { return ""; }
    return buffer.Text(units);
}

// ============================================================ directory walk

/// The name a walk found, as text rather than as 260 UTF-16 units.
///
/// `Win32.Kernel32.FindData` is the struct itself, with the fields Windows
/// fills in; these read the parts of it that want converting.
public String NameOf(ref FindData data) {
    return Text.FromNullTerminatedUtf16(&data.FileName[0]);
}

/// The two size halves joined the way the header intends them to be.
public ulong SizeOf(ref FindData data) {
    return ((ulong)data.FileSizeHigh << 32) | (ulong)data.FileSizeLow;
}

public bool IsDirectory(ref FindData data) {
    return (data.Attributes & FileAttributeDirectory) != 0u;
}

/// True for `.` and `..`, which a directory walk always sees first and which
/// almost no caller wants.
public bool IsSelfOrParent(ref FindData data) {
    var name = NameOf(ref data);
    return name == "." || name == "..";
}

/// Begins a directory walk. `pattern` is a path with wildcards — `C:\dir\*` —
/// not a directory. Returns `InvalidHandle()` when nothing matches, with
/// `ErrorFileNotFound`.
public HANDLE FindFirst(String pattern, ref FindData data) {
    return FindFirstFileW(pattern.ToUtf16().ToPointer(), &data);
}

/// The next entry, or false at the end — where `Win32.LastError()` is
/// `ErrorNoMoreFiles` rather than a real failure.
public bool FindNext(HANDLE find, ref FindData data) {
    return Win32.Succeeded(FindNextFileW(find, &data));
}

/// Every name in a directory, without `.` and `..`.
///
/// The whole walk in one call, for the common case where the caller wants a
/// list rather than a cursor. It returns names, not paths.
public List<String> Entries(String directory) {
    var names = new List<String>();
    FindData data;

    HANDLE find = FindFirst(directory + "\\*", ref data);
    if (Win32.IsInvalid(find)) { return names; }

    // FindFirstFileW has already produced the first entry, so this reads
    // before it advances rather than after.
    bool more = true;
    while (more) {
        if (!IsSelfOrParent(ref data)) { names.Add(NameOf(ref data)); }
        more = FindNext(find, ref data);
    }

    FindClose(find);
    return names;
}

#endif
