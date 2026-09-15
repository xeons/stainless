# Standard.File

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Whole-file operations.

A module is a scope, so this is what C# spells as a static class: `File.Exists`
is a module-qualified call, and `import Standard.File;` is what makes the
short name reach it. Streams live in Standard.IO; this module is for the
cases where the whole file is the unit of work.

## Contents

**Functions** &nbsp; [AppendText](#appendtext-function) &middot; [Copy](#copy-function) &middot; [Delete](#delete-function) &middot; [Exists](#exists-function) &middot; [Modified](#modified-function) &middot; [ReadAllBytes](#readallbytes-function) &middot; [ReadAllLines](#readalllines-function) &middot; [ReadAllText](#readalltext-function) &middot; [Rename](#rename-function) &middot; [Size](#size-function) &middot; [WriteAllBytes](#writeallbytes-function) &middot; [WriteAllLines](#writealllines-function) &middot; [WriteAllText](#writealltext-function)

## Functions

### AppendText *function*

```
IOError AppendText(String path, String text)
```

Adds `text` to the end, creating the file if it is not there.

<sub>[stdlib/File.sl:171](../../stdlib/File.sl#L171)</sub>

### Copy *function*

```
IOError Copy(String from, String to)
```

Copies a file. Reads it whole, so this is for ordinary files rather than
for something that will not fit in memory.

<sub>[stdlib/File.sl:187](../../stdlib/File.sl#L187)</sub>

### Delete *function*

```
IOError Delete(String path)
```

Removes the file. `IOError.None` on success.

<sub>[stdlib/File.sl:57](../../stdlib/File.sl#L57)</sub>

### Exists *function*

```
bool Exists(String path)
```

True when the path names a file that is there. A directory is not a file,
so this is false for one.

<sub>[stdlib/File.sl:45](../../stdlib/File.sl#L45)</sub>

### Modified *function*

```
long Modified(String path)
```

When it was last written, in seconds since the epoch, or -1.

<sub>[stdlib/File.sl:54](../../stdlib/File.sl#L54)</sub>

### ReadAllBytes *function*

```
Result<byte[], IOError> ReadAllBytes(String path)
```

The whole file as bytes.

<sub>[stdlib/File.sl:72](../../stdlib/File.sl#L72)</sub>

### ReadAllLines *function*

```
Result<List<String>, IOError> ReadAllLines(String path)
```

The file's lines, with either line ending accepted and a trailing newline
producing no final empty line.

<sub>[stdlib/File.sl:113](../../stdlib/File.sl#L113)</sub>

### ReadAllText *function*

```
Result<String, IOError> ReadAllText(String path)
```

The whole file as text, read as UTF-8.

<sub>[stdlib/File.sl:102](../../stdlib/File.sl#L102)</sub>

### Rename *function*

```
IOError Rename(String from, String to)
```

Moves or renames. Whether it replaces an existing destination is the
platform's decision, not this one's.

<sub>[stdlib/File.sl:61](../../stdlib/File.sl#L61)</sub>

### Size *function*

```
long Size(String path)
```

The size in bytes, or -1 when there is nothing there.

<sub>[stdlib/File.sl:51](../../stdlib/File.sl#L51)</sub>

### WriteAllBytes *function*

```
IOError WriteAllBytes(String path, byte[] data)
```

Replaces the file with `data`, creating it if needed.

<sub>[stdlib/File.sl:121](../../stdlib/File.sl#L121)</sub>

### WriteAllLines *function*

```
IOError WriteAllLines(String path, IReadOnlyList<String> lines)
```

Writes the lines, each followed by a newline.

<sub>[stdlib/File.sl:151](../../stdlib/File.sl#L151)</sub>

### WriteAllText *function*

```
IOError WriteAllText(String path, String text)
```

Replaces the file with `text`, written as UTF-8.

<sub>[stdlib/File.sl:136](../../stdlib/File.sl#L136)</sub>

