# Standard.File

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Whole-file operations.

A module is a scope, so this is what C# spells as a static class: `File.Exists`
is a module-qualified call, and `import Standard.File;` is what makes the
short name reach it. Streams live in Standard.IO; this module is for the
cases where the whole file is the unit of work.

## Contents

**Functions** &nbsp; [AppendAllText](#appendalltext-function) &middot; [Copy](#copy-function) &middot; [Delete](#delete-function) &middot; [Exists](#exists-function) &middot; [GetLastWriteTime](#getlastwritetime-function) &middot; [GetSize](#getsize-function) &middot; [Move](#move-function) &middot; [ReadAllBytes](#readallbytes-function) &middot; [ReadAllLines](#readalllines-function) &middot; [ReadAllText](#readalltext-function) &middot; [WriteAllBytes](#writeallbytes-function) &middot; [WriteAllLines](#writealllines-function) &middot; [WriteAllText](#writealltext-function)

## Functions

### AppendAllText *function*

```
IOError AppendAllText(String path, String text)
```

Adds `text` to the end, creating the file if it is not there.

**Fails with**

- [IOError.AccessDenied](Standard-IO.md#accessdenied-case) -- the path or its directory refuses it
- [IOError.IsADirectory](Standard-IO.md#isadirectory-case) -- the path names a directory
- [IOError.Unknown](Standard-IO.md#unknown-case) -- the write or the close failed for a reason with no case of its own, a full disk among them

<sub>[stdlib/File.sl:292](../../stdlib/File.sl#L292)</sub>

### Copy *function*

```
IOError Copy(String from, String to)
```

Copies a file. Reads it whole, so this is for ordinary files rather than
for something that will not fit in memory.

**Parameters**

- `from` -- the file to read, which must be there
- `to` -- the file to replace or create

**Fails with**

- [IOError.NotFound](Standard-IO.md#notfound-case) -- `from` is not there
- [IOError.AccessDenied](Standard-IO.md#accessdenied-case) -- either path refuses it
- [IOError.IsADirectory](Standard-IO.md#isadirectory-case) -- either path names a directory
- [IOError.Unknown](Standard-IO.md#unknown-case) -- the read or the write failed for a reason with no case of its own

<sub>[stdlib/File.sl:313](../../stdlib/File.sl#L313)</sub>

### Delete *function*

```
IOError Delete(String path)
```

Removes the file. `IOError.None` on success.

**Fails with**

- [IOError.NotFound](Standard-IO.md#notfound-case) -- there is nothing at that path
- [IOError.AccessDenied](Standard-IO.md#accessdenied-case) -- the file or its directory refuses it
- [IOError.IsADirectory](Standard-IO.md#isadirectory-case) -- the path names a directory; use `Directory`
- [IOError.Invalid](Standard-IO.md#invalid-case) -- the path holds a NUL

<sub>[stdlib/File.sl:71](../../stdlib/File.sl#L71)</sub>

### Exists *function*

```
bool Exists(String path)
```

True when the path names a file that is there. A directory is not a file,
so this is false for one.

<sub>[stdlib/File.sl:49](../../stdlib/File.sl#L49)</sub>

### GetLastWriteTime *function*

```
long GetLastWriteTime(String path)
```

When it was last written, in seconds since the epoch, or -1.

<sub>[stdlib/File.sl:60](../../stdlib/File.sl#L60)</sub>

### GetSize *function*

```
long GetSize(String path)
```

The size in bytes, or -1 when there is nothing there.

<sub>[stdlib/File.sl:57](../../stdlib/File.sl#L57)</sub>

### Move *function*

```
IOError Move(String from, String to)
```

Moves or renames. Whether it replaces an existing destination is the
platform's decision, not this one's.

**Parameters**

- `from` -- the file to move, which must be there
- `to` -- where it is to end up, directories and all

**Fails with**

- [IOError.NotFound](Standard-IO.md#notfound-case) -- `from` is not there
- [IOError.AccessDenied](Standard-IO.md#accessdenied-case) -- either path refuses it
- [IOError.AlreadyExists](Standard-IO.md#alreadyexists-case) -- `to` is taken and this platform will not replace it
- [IOError.Invalid](Standard-IO.md#invalid-case) -- either path holds a NUL

<sub>[stdlib/File.sl:88](../../stdlib/File.sl#L88)</sub>

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

**Fails with**

- [IOError.NotFound](Standard-IO.md#notfound-case) -- there is no file at that path
- [IOError.AccessDenied](Standard-IO.md#accessdenied-case) -- the file refuses to be read
- [IOError.IsADirectory](Standard-IO.md#isadirectory-case) -- the path names a directory
- [IOError.Unknown](Standard-IO.md#unknown-case) -- the file is there and its length could not be had, or the platform reported something with no case of its own -- a full disk among them

**See also** &nbsp; [File.ReadAllText](#readalltext-function)

<sub>[stdlib/File.sl:125](../../stdlib/File.sl#L125)</sub>

### ReadAllLines *function*

```
Result<List<String>, IOError> ReadAllLines(String path)
```

The file's lines, with either line ending accepted and a trailing newline
producing no final empty line.

**Fails with**

- [IOError.NotFound](Standard-IO.md#notfound-case) -- there is no file at that path
- [IOError.AccessDenied](Standard-IO.md#accessdenied-case) -- the file refuses to be read
- [IOError.IsADirectory](Standard-IO.md#isadirectory-case) -- the path names a directory
- [IOError.Unknown](Standard-IO.md#unknown-case) -- the platform reported something with no case of its own

**See also** &nbsp; [File.WriteAllLines](#writealllines-function)

<sub>[stdlib/File.sl:201](../../stdlib/File.sl#L201)</sub>

### ReadAllText *function*

```
Result<String, IOError> ReadAllText(String path)
```

The whole file as text, read as UTF-8. A byte order mark at the start is
dropped: it says how the text is stored and is not part of it.

**Fails with**

- [IOError.NotFound](Standard-IO.md#notfound-case) -- there is no file at that path
- [IOError.AccessDenied](Standard-IO.md#accessdenied-case) -- the file refuses to be read
- [IOError.IsADirectory](Standard-IO.md#isadirectory-case) -- the path names a directory
- [IOError.Unknown](Standard-IO.md#unknown-case) -- the platform reported something with no case of its own

**See also** &nbsp; [File.WriteAllText](#writealltext-function)

<sub>[stdlib/File.sl:179](../../stdlib/File.sl#L179)</sub>

### WriteAllBytes *function*

```
IOError WriteAllBytes(String path, byte[] data)
```

Replaces the file with `data`, creating it if needed.

**Fails with**

- [IOError.AccessDenied](Standard-IO.md#accessdenied-case) -- the path or its directory refuses it
- [IOError.IsADirectory](Standard-IO.md#isadirectory-case) -- the path names a directory
- [IOError.Unknown](Standard-IO.md#unknown-case) -- the write or the close failed for a reason with no case of its own, a full disk among them

<sub>[stdlib/File.sl:227](../../stdlib/File.sl#L227)</sub>

### WriteAllLines *function*

```
IOError WriteAllLines(String path, IReadOnlyList<String> lines)
```

Writes the lines, each followed by a newline. Stops at the first write that
fails.

**Fails with**

- [IOError.AccessDenied](Standard-IO.md#accessdenied-case) -- the path or its directory refuses it
- [IOError.IsADirectory](Standard-IO.md#isadirectory-case) -- the path names a directory
- [IOError.Unknown](Standard-IO.md#unknown-case) -- a write or the close failed for a reason with no case of its own, a full disk among them

<sub>[stdlib/File.sl:265](../../stdlib/File.sl#L265)</sub>

### WriteAllText *function*

```
IOError WriteAllText(String path, String text)
```

Replaces the file with `text`, written as UTF-8.

**Fails with**

- [IOError.AccessDenied](Standard-IO.md#accessdenied-case) -- the path or its directory refuses it
- [IOError.IsADirectory](Standard-IO.md#isadirectory-case) -- the path names a directory
- [IOError.Unknown](Standard-IO.md#unknown-case) -- the write or the close failed for a reason with no case of its own, a full disk among them

**See also** &nbsp; [File.ReadAllText](#readalltext-function)

<sub>[stdlib/File.sl:246](../../stdlib/File.sl#L246)</sub>

