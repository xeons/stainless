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

<sub>[stdlib/File.sl:205](../../stdlib/File.sl#L205)</sub>

### Copy *function*

```
IOError Copy(String from, String to)
```

Copies a file. Reads it whole, so this is for ordinary files rather than
for something that will not fit in memory.

<sub>[stdlib/File.sl:221](../../stdlib/File.sl#L221)</sub>

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

**The reported size is a hint, not a promise.** A `/proc` or `/sys` file
reports zero and then hands over kilobytes when read; a file another process
is appending to reports less than it will give. So the size opens the array
and reading to the end decides where it stops -- which is what "all bytes"
has to mean for this to be usable on Linux at all. Trusting the size gave
every `/proc/<pid>/maps` back as empty, which is a debugger that cannot find
where a program was loaded.

<sub>[stdlib/File.sl:87](../../stdlib/File.sl#L87)</sub>

### ReadAllLines *function*

```
Result<List<String>, IOError> ReadAllLines(String path)
```

The file's lines, with either line ending accepted and a trailing newline
producing no final empty line.

<sub>[stdlib/File.sl:147](../../stdlib/File.sl#L147)</sub>

### ReadAllText *function*

```
Result<String, IOError> ReadAllText(String path)
```

The whole file as text, read as UTF-8.

<sub>[stdlib/File.sl:136](../../stdlib/File.sl#L136)</sub>

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

<sub>[stdlib/File.sl:155](../../stdlib/File.sl#L155)</sub>

### WriteAllLines *function*

```
IOError WriteAllLines(String path, IReadOnlyList<String> lines)
```

Writes the lines, each followed by a newline.

<sub>[stdlib/File.sl:185](../../stdlib/File.sl#L185)</sub>

### WriteAllText *function*

```
IOError WriteAllText(String path, String text)
```

Replaces the file with `text`, written as UTF-8.

<sub>[stdlib/File.sl:170](../../stdlib/File.sl#L170)</sub>

