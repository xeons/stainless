# Standard.Directory

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Directories: making them, removing them, and looking inside.

Listing returns full paths rather than bare names, because a bare name is
almost never what the next line wants. The order is the platform's and is
not sorted; `Sort` is one call away when it matters.

## Contents

**Types** &nbsp; [Entry](#entry-class)

**Functions** &nbsp; [AllFiles](#allfiles-function) &middot; [Create](#create-function) &middot; [CreateAll](#createall-function) &middot; [Delete](#delete-function) &middot; [Directories](#directories-function) &middot; [Entries](#entries-function) &middot; [Exists](#exists-function) &middot; [Files](#files-function)

## Types

### Entry *class*

```
class Entry
```

One entry of a directory: where it is, and whether it is itself a directory.

<sub>[stdlib/Directory.sl:75](../../stdlib/Directory.sl#L75)</sub>

#### Path *property*

```
String Path { get; }
```

The full path, ready to hand back to `File` or `Directory`. Built from
the path that was listed, so a relative listing gives relative entries.

<sub>[stdlib/Directory.sl:78](../../stdlib/Directory.sl#L78)</sub>

#### Name *property*

```
String Name { get; }
```

The last part alone, without any directory in front of it.

<sub>[stdlib/Directory.sl:81](../../stdlib/Directory.sl#L81)</sub>

#### IsDirectory *property*

```
bool IsDirectory { get; }
```

True for a directory, false for anything else -- a regular file, a
symbolic link to one, a device. Only the directory answer is relied on
here, because it is the one that decides whether a walk descends.

<sub>[stdlib/Directory.sl:86](../../stdlib/Directory.sl#L86)</sub>

## Functions

### AllFiles *function*

```
Result<List<String>, IOError> AllFiles(String path)
```

Every file underneath, at any depth.

Written as a worklist rather than a recursion so that a deep tree cannot
run the stack out.

<sub>[stdlib/Directory.sl:150](../../stdlib/Directory.sl#L150)</sub>

### Create *function*

```
IOError Create(String path)
```

Creates one directory. The parent has to exist already; use `CreateAll` when
it might not.

<sub>[stdlib/Directory.sl:50](../../stdlib/Directory.sl#L50)</sub>

### CreateAll *function*

```
IOError CreateAll(String path)
```

Creates the directory and every parent that is missing.

<sub>[stdlib/Directory.sl:55](../../stdlib/Directory.sl#L55)</sub>

### Delete *function*

```
IOError Delete(String path)
```

Removes one empty directory.

<sub>[stdlib/Directory.sl:68](../../stdlib/Directory.sl#L68)</sub>

### Directories *function*

```
Result<List<String>, IOError> Directories(String path)
```

The full paths of the directories directly inside.

<sub>[stdlib/Directory.sl:135](../../stdlib/Directory.sl#L135)</sub>

### Entries *function*

```
Result<List<Entry>, IOError> Entries(String path)
```

Everything directly inside, files and directories both, not recursively.

<sub>[stdlib/Directory.sl:98](../../stdlib/Directory.sl#L98)</sub>

### Exists *function*

```
bool Exists(String path)
```

True when the path names a directory that is there.

<sub>[stdlib/Directory.sl:44](../../stdlib/Directory.sl#L44)</sub>

### Files *function*

```
Result<List<String>, IOError> Files(String path)
```

The full paths of the files directly inside.

<sub>[stdlib/Directory.sl:123](../../stdlib/Directory.sl#L123)</sub>

