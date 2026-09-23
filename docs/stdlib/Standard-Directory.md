# Standard.Directory

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Directories: making them, removing them, and looking inside.

Listing returns full paths rather than bare names, because a bare name is
almost never what the next line wants. The order is the platform's and is
not sorted; `Sort` is one call away when it matters.

## Contents

**Types** &nbsp; [Entry](#entry-class)

**Functions** &nbsp; [CreateDirectory](#createdirectory-function) &middot; [CreateDirectoryTree](#createdirectorytree-function) &middot; [Delete](#delete-function) &middot; [Exists](#exists-function) &middot; [GetAllFiles](#getallfiles-function) &middot; [GetDirectories](#getdirectories-function) &middot; [GetEntries](#getentries-function) &middot; [GetFiles](#getfiles-function)

## Types

### Entry *class*

```
class Entry
```

One entry of a directory: where it is, and whether it is itself a directory.

<sub>[stdlib/Directory.sl:122](../../stdlib/Directory.sl#L122)</sub>

#### Path *property*

```
String Path { get; }
```

The full path, ready to hand back to `File` or `Directory`. Built from
the path that was listed, so a relative listing gives relative entries.

<sub>[stdlib/Directory.sl:126](../../stdlib/Directory.sl#L126)</sub>

#### Name *property*

```
String Name { get; }
```

The last part alone, without any directory in front of it.

<sub>[stdlib/Directory.sl:129](../../stdlib/Directory.sl#L129)</sub>

#### IsDirectory *property*

```
bool IsDirectory { get; }
```

True for a directory, false for anything else -- a regular file, a
symbolic link to one, a device. Only the directory answer is relied on
here, because it is the one that decides whether a walk descends.

<sub>[stdlib/Directory.sl:134](../../stdlib/Directory.sl#L134)</sub>

## Functions

### CreateDirectory *function*

```
IOError CreateDirectory(String path)
```

Creates one directory. The parent has to exist already; use `CreateDirectoryTree` when
it might not.

**Fails with**

- [IOError.NotFound](Standard-IO.md#notfound-case) — a directory along the path is missing
- [IOError.AccessDenied](Standard-IO.md#accessdenied-case) — the parent refuses it
- [IOError.AlreadyExists](Standard-IO.md#alreadyexists-case) — something is there under that name
- [IOError.NotADirectory](Standard-IO.md#notadirectory-case) — a file along the path was used as a directory
- [IOError.Unknown](Standard-IO.md#unknown-case) — the platform reported something with no case of its own -- a full disk among them

**See also** &nbsp; [Directory.CreateDirectoryTree](#createdirectorytree-function)

<sub>[stdlib/Directory.sl:60](../../stdlib/Directory.sl#L60)</sub>

### CreateDirectoryTree *function*

```
IOError CreateDirectoryTree(String path)
```

Creates the directory and every parent that is missing.

A trailing separator is allowed, and a directory that appears while this
runs -- made by another process, say -- is success rather than a failure.

**Fails with**

- [IOError.AccessDenied](Standard-IO.md#accessdenied-case) — a directory along the way refuses it
- [IOError.AlreadyExists](Standard-IO.md#alreadyexists-case) — a file is there under one of the names
- [IOError.NotADirectory](Standard-IO.md#notadirectory-case) — a file along the path was used as a directory
- [IOError.Unknown](Standard-IO.md#unknown-case) — the platform reported something with no case of its own -- a full disk among them

**See also** &nbsp; [Directory.CreateDirectory](#createdirectory-function)

<sub>[stdlib/Directory.sl:76](../../stdlib/Directory.sl#L76)</sub>

### Delete *function*

```
IOError Delete(String path)
```

Removes one empty directory.

**Fails with**

- [IOError.NotFound](Standard-IO.md#notfound-case) — there is nothing at that path
- [IOError.AccessDenied](Standard-IO.md#accessdenied-case) — the directory or its parent refuses it
- [IOError.NotADirectory](Standard-IO.md#notadirectory-case) — the path names a file; `File.Delete` removes one of those
- [IOError.Invalid](Standard-IO.md#invalid-case) — the last part of the path is `.`
- [IOError.Unknown](Standard-IO.md#unknown-case) — the platform reported something with no case of its own -- a directory that is not empty among them

<sub>[stdlib/Directory.sl:114](../../stdlib/Directory.sl#L114)</sub>

### Exists *function*

```
bool Exists(String path)
```

True when the path names a directory that is there.

<sub>[stdlib/Directory.sl:45](../../stdlib/Directory.sl#L45)</sub>

### GetAllFiles *function*

```
Result<List<String>, IOError> GetAllFiles(String path)
```

Every file underneath, at any depth.

Written as a worklist rather than a recursion so that a deep tree cannot
run the stack out.

**Fails with**

- [IOError.NotFound](Standard-IO.md#notfound-case) — there is no directory at that path
- [IOError.AccessDenied](Standard-IO.md#accessdenied-case) — the directory, or one underneath it, cannot be listed

**See also** &nbsp; [Directory.GetFiles](#getfiles-function)

<sub>[stdlib/Directory.sl:229](../../stdlib/Directory.sl#L229)</sub>

### GetDirectories *function*

```
Result<List<String>, IOError> GetDirectories(String path)
```

The full paths of the directories directly inside.

**Fails with**

- [IOError.NotFound](Standard-IO.md#notfound-case) — there is no directory at that path
- [IOError.AccessDenied](Standard-IO.md#accessdenied-case) — it is there and cannot be listed

**See also** &nbsp; [Directory.GetFiles](#getfiles-function)

<sub>[stdlib/Directory.sl:205](../../stdlib/Directory.sl#L205)</sub>

### GetEntries *function*

```
Result<List<Entry>, IOError> GetEntries(String path)
```

Everything directly inside, files and directories both, not recursively.

**Fails with**

- [IOError.NotFound](Standard-IO.md#notfound-case) — there is no directory at that path
- [IOError.AccessDenied](Standard-IO.md#accessdenied-case) — it is there and cannot be listed

**See also** &nbsp; [Directory.GetFiles](#getfiles-function) &middot; [Directory.GetDirectories](#getdirectories-function)

<sub>[stdlib/Directory.sl:152](../../stdlib/Directory.sl#L152)</sub>

### GetFiles *function*

```
Result<List<String>, IOError> GetFiles(String path)
```

The full paths of the files directly inside.

**Fails with**

- [IOError.NotFound](Standard-IO.md#notfound-case) — there is no directory at that path
- [IOError.AccessDenied](Standard-IO.md#accessdenied-case) — it is there and cannot be listed

**See also** &nbsp; [Directory.GetDirectories](#getdirectories-function) &middot; [Directory.GetAllFiles](#getallfiles-function)

<sub>[stdlib/Directory.sl:185](../../stdlib/Directory.sl#L185)</sub>

