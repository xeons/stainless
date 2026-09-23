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

/// Directories: making them, removing them, and looking inside.
///
/// Listing returns full paths rather than bare names, because a bare name is
/// almost never what the next line wants. The order is the platform's and is
/// not sorted; `Sort` is one call away when it matters.
module Standard.Directory;

import Standard.Collections;
import Standard.IO;
import Standard.Path;

extern "C"
{
    bool  sl_path_exists(byte* path);
    bool  sl_path_is_directory(byte* path);
    int   sl_directory_create(byte* path);
    int   sl_directory_delete(byte* path);
    byte* sl_directory_open(byte* path);
    byte* sl_directory_next(byte* handle, bool* isDirectory);
    void  sl_directory_close(byte* handle);
}

/// True when the path names a directory that is there.
public bool Exists(String path)
{
    return sl_path_exists(path.ToPointer()) && sl_path_is_directory(path.ToPointer());
}

/// Creates one directory. The parent has to exist already; use `CreateDirectoryTree` when
/// it might not.
///
/// @failure IOError.NotFound       a directory along the path is missing
/// @failure IOError.AccessDenied   the parent refuses it
/// @failure IOError.AlreadyExists  something is there under that name
/// @failure IOError.NotADirectory  a file along the path was used as a directory
/// @failure IOError.Unknown        the platform reported something with no case
///                                 of its own -- a full disk among them
/// @see Directory.CreateDirectoryTree
public IOError CreateDirectory(String path)
{
    return (IOError)sl_directory_create(path.ToPointer());
}

/// Creates the directory and every parent that is missing.
///
/// A trailing separator is allowed, and a directory that appears while this
/// runs -- made by another process, say -- is success rather than a failure.
///
/// @failure IOError.AccessDenied   a directory along the way refuses it
/// @failure IOError.AlreadyExists  a file is there under one of the names
/// @failure IOError.NotADirectory  a file along the path was used as a directory
/// @failure IOError.Unknown        the platform reported something with no case
///                                 of its own -- a full disk among them
/// @see Directory.CreateDirectory
public IOError CreateDirectoryTree(String path)
{
    // `a/b/` names `a/b`. Stop at a root, which is its own directory name.
    while (Path.GetFileName(path).ByteLength() == 0)
    {
        var trimmed = Path.GetDirectoryName(path);
        if (trimmed.ByteLength() == 0 || trimmed.ByteLength() >= path.ByteLength())
            break;
        path = trimmed;
    }

    if (Exists(path))
        return IOError.None;

    var parent = Path.GetDirectoryName(path);
    if (parent.ByteLength() > 0 && !Exists(parent))
    {
        var failed = CreateDirectoryTree(parent);
        if (failed != IOError.None)
            return failed;
    }

    var made = CreateDirectory(path);
    if (made == IOError.AlreadyExists && Exists(path))
        return IOError.None;
    return made;
}

/// Removes one empty directory.
///
/// @failure IOError.NotFound       there is nothing at that path
/// @failure IOError.AccessDenied   the directory or its parent refuses it
/// @failure IOError.NotADirectory  the path names a file; `File.Delete` removes
///                                 one of those
/// @failure IOError.Invalid        the last part of the path is `.`
/// @failure IOError.Unknown        the platform reported something with no case
///                                 of its own -- a directory that is not empty
///                                 among them
public IOError Delete(String path)
{
    return (IOError)sl_directory_delete(path.ToPointer());
}

/// Everything directly inside, files and directories both, not recursively.
///
/// @failure IOError.NotFound      there is no directory at that path
/// @failure IOError.AccessDenied  it is there and cannot be listed
/// @see Directory.GetFiles
/// @seealso Directory.GetDirectories
public Result<List<Entry>, IOError> GetEntries(String path)
{
    var found = new List<Entry>();

    var cursor = sl_directory_open(path.ToPointer());
    if (cursor == null)
    {
        var why = Exists(path) ? IOError.AccessDenied : IOError.NotFound;
        return Fail(why);
    }

    bool isDirectory = false;
    var raw = sl_directory_next(cursor, &isDirectory);

    while (raw != null)
    {
        // The name lives in the cursor and is replaced on the next step, so it
        // is copied into a String here rather than held on to.
        var name = Text.FromNullTerminated(raw);
        found.Add(new Entry(Path.Join(path, name), name, isDirectory));
        raw = sl_directory_next(cursor, &isDirectory);
    }

    sl_directory_close(cursor);
    return Ok(found);
}

/// The full paths of the files directly inside.
///
/// @failure IOError.NotFound      there is no directory at that path
/// @failure IOError.AccessDenied  it is there and cannot be listed
/// @see Directory.GetDirectories
/// @seealso Directory.GetAllFiles
public Result<List<String>, IOError> GetFiles(String path)
{
    var all = GetEntries(path);
    if (!all.Ok)
        return Fail(all.Error);

    var paths = new List<String>();
    foreach (var entry in all.Value)
    {
        if (!entry.IsDirectory)
            paths.Add(entry.Path);
    }
    return Ok(paths);
}

/// The full paths of the directories directly inside.
///
/// @failure IOError.NotFound      there is no directory at that path
/// @failure IOError.AccessDenied  it is there and cannot be listed
/// @see Directory.GetFiles
public Result<List<String>, IOError> GetDirectories(String path)
{
    var all = GetEntries(path);
    if (!all.Ok)
        return Fail(all.Error);

    var paths = new List<String>();
    foreach (var entry in all.Value)
    {
        if (entry.IsDirectory)
            paths.Add(entry.Path);
    }
    return Ok(paths);
}

/// Every file underneath, at any depth.
///
/// Written as a worklist rather than a recursion so that a deep tree cannot
/// run the stack out.
///
/// @failure IOError.NotFound      there is no directory at that path
/// @failure IOError.AccessDenied  the directory, or one underneath it, cannot
///                                be listed
/// @see Directory.GetFiles
public Result<List<String>, IOError> GetAllFiles(String path)
{
    var paths = new List<String>();

    var pending = new Queue<String>();
    pending.Enqueue(path);

    while (!pending.IsEmpty)
    {
        var here = pending.Dequeue();
        var listed = GetEntries(here);
        if (!listed.Ok)
            return Fail(listed.Error);

        foreach (var entry in listed.Value)
        {
            if (entry.IsDirectory)
            {
                pending.Enqueue(entry.Path);
            }
            else
            {
                paths.Add(entry.Path);
            }
        }
    }

    return Ok(paths);
}
