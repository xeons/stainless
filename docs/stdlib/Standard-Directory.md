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

<sub>[stdlib/Directory.sl:98](../../stdlib/Directory.sl#L98)</sub>

#### Path *property*

```
String Path { get; }
```

The full path, ready to hand back to `File` or `Directory`. Built from
the path that was listed, so a relative listing gives relative entries.

<sub>[stdlib/Directory.sl:102](../../stdlib/Directory.sl#L102)</sub>

#### Name *property*

```
String Name { get; }
```

The last part alone, without any directory in front of it.

<sub>[stdlib/Directory.sl:105](../../stdlib/Directory.sl#L105)</sub>

#### IsDirectory *property*

```
bool IsDirectory { get; }
```

True for a directory, false for anything else -- a regular file, a
symbolic link to one, a device. Only the directory answer is relied on
here, because it is the one that decides whether a walk descends.

<sub>[stdlib/Directory.sl:110](../../stdlib/Directory.sl#L110)</sub>

## Functions

### CreateDirectory *function*

```
IOError CreateDirectory(String path)
```

Creates one directory. The parent has to exist already; use `CreateDirectoryTree` when
it might not.

<sub>[stdlib/Directory.sl:52](../../stdlib/Directory.sl#L52)</sub>

### CreateDirectoryTree *function*

```
IOError CreateDirectoryTree(String path)
```

Creates the directory and every parent that is missing.

A trailing separator is allowed, and a directory that appears while this
runs -- made by another process, say -- is success rather than a failure.

<sub>[stdlib/Directory.sl:61](../../stdlib/Directory.sl#L61)</sub>

### Delete *function*

```
IOError Delete(String path)
```

Removes one empty directory.

<sub>[stdlib/Directory.sl:90](../../stdlib/Directory.sl#L90)</sub>

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

<sub>[stdlib/Directory.sl:186](../../stdlib/Directory.sl#L186)</sub>

### GetDirectories *function*

```
Result<List<String>, IOError> GetDirectories(String path)
```

The full paths of the directories directly inside.

<sub>[stdlib/Directory.sl:167](../../stdlib/Directory.sl#L167)</sub>

### GetEntries *function*

```
Result<List<Entry>, IOError> GetEntries(String path)
```

Everything directly inside, files and directories both, not recursively.

<sub>[stdlib/Directory.sl:123](../../stdlib/Directory.sl#L123)</sub>

### GetFiles *function*

```
Result<List<String>, IOError> GetFiles(String path)
```

The full paths of the files directly inside.

<sub>[stdlib/Directory.sl:151](../../stdlib/Directory.sl#L151)</sub>

