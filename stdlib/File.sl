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

// Whole-file operations.
//
// A module is a scope, so this is what C# spells as a static class: `File.Exists`
// is a module-qualified call, and `import Standard.File;` is what makes the
// short name reach it. Streams live in Standard.IO; this module is for the
// cases where the whole file is the unit of work.
module Standard.File;

import Standard.Collections;
import Standard.IO;

extern "C" {
    bool sl_path_exists(byte* path);
    bool sl_path_is_directory(byte* path);
    long sl_path_size(byte* path);
    long sl_path_modified(byte* path);
    int  sl_file_delete(byte* path);
    int  sl_file_rename(byte* from, byte* to);
}

/// True when the path names a file that is there. A directory is not a file,
/// so this is false for one.
public bool Exists(String path) {
    return sl_path_exists(path.ToPointer()) && !sl_path_is_directory(path.ToPointer());
}

/// The size in bytes, or -1 when there is nothing there.
public long Size(String path) { return sl_path_size(path.ToPointer()); }

/// When it was last written, in seconds since the epoch, or -1.
public long Modified(String path) { return sl_path_modified(path.ToPointer()); }

/// Removes the file. `IOError.None` on success.
public IOError Delete(String path) { return (IOError)sl_file_delete(path.ToPointer()); }

/// Moves or renames. Whether it replaces an existing destination is the
/// platform's decision, not this one's.
public IOError Rename(String from, String to) {
    return (IOError)sl_file_rename(from.ToPointer(), to.ToPointer());
}

// ------------------------------------------------------------------ opening

/// Opens a file. The stream always exists; `IsOpen()` says whether it holds
/// one, and `Error()` says why not.
public FileStream Open(String path, FileMode mode, FileAccess access) {
    return new FileStream(path, mode, access);
}

public FileStream OpenRead(String path) {
    return new FileStream(path, FileMode.Open, FileAccess.Read);
}

/// Creates the file, or replaces what is there.
public FileStream Create(String path) {
    return new FileStream(path, FileMode.Create, FileAccess.Write);
}

/// Opens for writing at the end, creating the file if it is not there.
public FileStream OpenAppend(String path) {
    return new FileStream(path, FileMode.Append, FileAccess.Write);
}

// ------------------------------------------------------------------ reading

/// The whole file as bytes.
public Result<byte[], IOError> ReadAllBytes(String path) {
    var file = OpenRead(path);
    if (!file.IsOpen()) { return Fail(file.Error()); }

    long size = file.Length();
    if (size < 0) {
        file.Close();
        return Fail(IOError.Unknown);
    }

    var data = new byte[(nuint)size];
    nuint got = file.Read(data, 0, (nuint)size);
    var failure = file.Error();
    file.Close();

    if (failure != IOError.None) { return Fail(failure); }

    // A short read is not an error, but the array has to match what arrived.
    if (got == (nuint)size) { return Ok(data); }

    var exact = new byte[got];
    for (nuint i = 0; i < got; i = i + 1) { exact[i] = data[i]; }
    return Ok(exact);
}

/// The whole file as text, read as UTF-8.
public Result<String, IOError> ReadAllText(String path) {
    var raw = ReadAllBytes(path);
    if (!raw.Ok) { return Fail(raw.Error); }
    if (raw.Value.Length == 0) { return Ok(""); }

    return Ok(Text.FromBytes(&raw.Value[0], raw.Value.Length));
}

/// The file's lines, with either line ending accepted and a trailing newline
/// producing no final empty line.
public Result<List<String>, IOError> ReadAllLines(String path) {
    var text = ReadAllText(path);
    if (!text.Ok) { return Fail(text.Error); }

    return Ok(IO.SplitLines(text.Value));
}

// ------------------------------------------------------------------ writing

/// Replaces the file with `data`, creating it if needed.
public IOError WriteAllBytes(String path, byte[] data) {
    var file = Create(path);
    if (!file.IsOpen()) { return file.Error(); }

    file.Write(data, 0, data.Length);
    var failure = file.Error();
    file.Close();
    return failure;
}

/// Replaces the file with `text`, written as UTF-8.
public IOError WriteAllText(String path, String text) {
    var file = Create(path);
    if (!file.IsOpen()) { return file.Error(); }

    file.WriteText(text);
    var failure = file.Error();
    file.Close();
    return failure;
}

/// Writes the lines, each followed by a newline.
public IOError WriteAllLines(String path, IReadOnlyList<String> lines) {
    var file = Create(path);
    if (!file.IsOpen()) { return file.Error(); }

    for (nuint i = 0; i < lines.Count(); i = i + 1) {
        file.WriteText(lines.At(i));
        file.WriteText("\n");
    }

    var failure = file.Error();
    file.Close();
    return failure;
}

/// Adds `text` to the end, creating the file if it is not there.
public IOError AppendText(String path, String text) {
    var file = OpenAppend(path);
    if (!file.IsOpen()) { return file.Error(); }

    file.WriteText(text);
    var failure = file.Error();
    file.Close();
    return failure;
}

/// Copies a file. Reads it whole, so this is for ordinary files rather than
/// for something that will not fit in memory.
public IOError Copy(String from, String to) {
    var data = ReadAllBytes(from);
    if (!data.Ok) { return data.Error; }
    return WriteAllBytes(to, data.Value);
}
