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

// Directories: making them, removing them, and looking inside.
//
// Listing returns full paths rather than bare names, because a bare name is
// almost never what the next line wants. The order is the platform's and is
// not sorted; `Sort` is one call away when it matters.
module Standard.Directory;

import Standard.Collections;
import Standard.IO;
import Standard.Path;

extern "C" {
    bool  sl_path_exists(byte* path);
    bool  sl_path_is_directory(byte* path);
    int   sl_directory_create(byte* path);
    int   sl_directory_delete(byte* path);
    byte* sl_directory_open(byte* path);
    byte* sl_directory_next(byte* handle, bool* isDirectory);
    void  sl_directory_close(byte* handle);
}

/// True when the path names a directory that is there.
public bool Exists(String path) {
    return sl_path_exists(path.ToPointer()) && sl_path_is_directory(path.ToPointer());
}

/// Creates one directory. The parent has to exist already; use `CreateAll` when
/// it might not.
public IOError Create(String path) {
    return (IOError)sl_directory_create(path.ToPointer());
}

/// Creates the directory and every parent that is missing.
public IOError CreateAll(String path) {
    if (Exists(path)) { return IOError.None; }

    var parent = Path.DirectoryName(path);
    if (parent.ByteLength() > 0 && !Exists(parent)) {
        var failed = CreateAll(parent);
        if (failed != IOError.None) { return failed; }
    }

    return Create(path);
}

/// Removes one empty directory.
public IOError Delete(String path) {
    return (IOError)sl_directory_delete(path.ToPointer());
}

// ----------------------------------------------------------------- listing

/// One entry of a directory: where it is, and whether it is itself a directory.
public class Entry {
    public String Path { get; }
    public String Name { get; }
    public bool IsDirectory { get; }

    public Entry(String path, String name, bool isDirectory) {
        Path = path;
        Name = name;
        IsDirectory = isDirectory;
    }
}

/// Everything directly inside, files and directories both, not recursively.
public Result<List<Entry>> Entries(String path) {
    var found = new List<Entry>();

    var cursor = sl_directory_open(path.ToPointer());
    if (cursor == null) {
        var why = Exists(path) ? IOError.AccessDenied : IOError.NotFound;
        return new Result<List<Entry>>(false, found, why);
    }

    bool isDirectory = false;
    var raw = sl_directory_next(cursor, &isDirectory);

    while (raw != null) {
        // The name lives in the cursor and is replaced on the next step, so it
        // is copied into a String here rather than held on to.
        var name = Text.FromNullTerminated(raw);
        found.Add(new Entry(Path.Join(path, name), name, isDirectory));
        raw = sl_directory_next(cursor, &isDirectory);
    }

    sl_directory_close(cursor);
    return new Result<List<Entry>>(true, found, IOError.None);
}

/// The full paths of the files directly inside.
public Result<List<String>> Files(String path) {
    var all = Entries(path);
    if (!all.Ok) { return new Result<List<String>>(false, new List<String>(), all.Error); }

    var paths = new List<String>();
    foreach (var entry in all.Value) {
        if (!entry.IsDirectory) { paths.Add(entry.Path); }
    }
    return new Result<List<String>>(true, paths, IOError.None);
}

/// The full paths of the directories directly inside.
public Result<List<String>> Directories(String path) {
    var all = Entries(path);
    if (!all.Ok) { return new Result<List<String>>(false, new List<String>(), all.Error); }

    var paths = new List<String>();
    foreach (var entry in all.Value) {
        if (entry.IsDirectory) { paths.Add(entry.Path); }
    }
    return new Result<List<String>>(true, paths, IOError.None);
}

/// Every file underneath, at any depth.
///
/// Written as a worklist rather than a recursion so that a deep tree cannot
/// run the stack out.
public Result<List<String>> AllFiles(String path) {
    var paths = new List<String>();

    var pending = new Queue<String>();
    pending.Enqueue(path);

    while (!pending.IsEmpty()) {
        var here = pending.Dequeue();
        var listed = Entries(here);
        if (!listed.Ok) { return new Result<List<String>>(false, paths, listed.Error); }

        foreach (var entry in listed.Value) {
            if (entry.IsDirectory) { pending.Enqueue(entry.Path); }
            else { paths.Add(entry.Path); }
        }
    }

    return new Result<List<String>>(true, paths, IOError.None);
}
