# Standard.Path

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Taking paths apart and putting them together.

Purely textual: nothing here touches a disk, and none of it asks whether the
path exists.

**What counts as a separator is the platform's business, not a preference.**
Windows accepts both `\` and `/` everywhere, so both are read apart there and
a path from a config file or a URL works either way. Linux and macOS accept
only `/` -- and a backslash there is not a separator being generously
allowed, it is an ordinary character that a filename may contain. Treating
`report\2026.csv` as two parts on Linux is not lenient, it is wrong.

So the questions this module answers have different answers on different
platforms, and it says which rather than picking one.

## Contents

**Functions** &nbsp; [ChangeExtension](#changeextension-function) &middot; [GetDirectoryName](#getdirectoryname-function) &middot; [GetExtension](#getextension-function) &middot; [GetFileName](#getfilename-function) &middot; [GetFileNameWithoutExtension](#getfilenamewithoutextension-function) &middot; [IsPathRooted](#ispathrooted-function) &middot; [IsSamePath](#issamepath-function) &middot; [Join](#join-function) &middot; [Join](#join-function) &middot; [SplitPath](#splitpath-function)

**Constants** &nbsp; [AltSeparator](#altseparator-constant) &middot; [Separator](#separator-constant)

## Functions

### ChangeExtension *function*

```
String ChangeExtension(String path, String with)
```

The path with a different extension. `with` may be written with or without
its leading dot. Nothing before the last part is touched.

<sub>[stdlib/Path.sl:194](../../stdlib/Path.sl#L194)</sub>

### GetDirectoryName *function*

```
String GetDirectoryName(String path)
```

Everything before the last part, without its trailing separator. A path
with no separator gives the empty string.

A root keeps its separator, because without it the answer names somewhere
else: `/foo` gives `/`, and on Windows `C:\foo` gives `C:\`, where `C:`
alone would be that drive's current directory.

<sub>[stdlib/Path.sl:132](../../stdlib/Path.sl#L132)</sub>

### GetExtension *function*

```
String GetExtension(String path)
```

The extension, with its dot: `notes.txt` gives `.txt`. No dot in the last
part, a dot that starts it, or a dot that ends it gives the empty string.

<sub>[stdlib/Path.sl:175](../../stdlib/Path.sl#L175)</sub>

### GetFileName *function*

```
String GetFileName(String path)
```

The last part: `a/b/c.txt` gives `c.txt`.

<sub>[stdlib/Path.sl:120](../../stdlib/Path.sl#L120)</sub>

### GetFileNameWithoutExtension *function*

```
String GetFileNameWithoutExtension(String path)
```

The last part with its extension removed. A trailing dot goes with it.

<sub>[stdlib/Path.sl:186](../../stdlib/Path.sl#L186)</sub>

### IsPathRooted *function*

```
bool IsPathRooted(String path)
```

True when the path starts at a root, so that joining it onto another would
be a mistake.

`/x` is rooted everywhere. `\x` and `C:\x` are rooted on Windows and are
ordinary relative names elsewhere, where a colon and a backslash are both
characters a filename may contain.

<sub>[stdlib/Path.sl:210](../../stdlib/Path.sl#L210)</sub>

### IsSamePath *function*

```
bool IsSamePath(String left, String right)
```

Whether two paths name the same file, as text.

It settles the two differences the platform itself creates: Windows accepts
`/` and `\` interchangeably and matches names without regard to case,
Linux does neither. A compiler joining a directory to a file name writes
`C:\src\obj/Text.sl`, one separator from each half, and `==` says that is
a different file from `C:\src\obj\Text.sl`.

Nothing is opened, followed or resolved. A caller that needs `..` or a
relative path resolved MUST do that first.

Only ASCII letters are case-folded. Windows folds more, with a table that
has changed between releases, so two paths differing only in the case of a
non-ASCII letter are reported as different.

<sub>[stdlib/Path.sl:242](../../stdlib/Path.sl#L242)</sub>

### Join *function*

```
String Join(String left, String right)
```

Joins two parts with a single separator, whichever way each one ends or
starts. An empty part contributes nothing.

<sub>[stdlib/Path.sl:85](../../stdlib/Path.sl#L85)</sub>

### Join *function*

```
String Join(String first, String second, String third)
```

Three parts joined left to right, with the same rule at each step.

<sub>[stdlib/Path.sl:114](../../stdlib/Path.sl#L114)</sub>

### SplitPath *function*

```
List<String> SplitPath(String path)
```

The parts, with the separators dropped and empty parts skipped.

<sub>[stdlib/Path.sl:280](../../stdlib/Path.sl#L280)</sub>

## Constants

### AltSeparator *constant*

```
const char AltSeparator = 47
```

The other one, accepted everywhere a separator is looked for.

<sub>[stdlib/Path.sl:46](../../stdlib/Path.sl#L46)</sub>

### Separator *constant*

```
const char Separator = 92
```

What `Join` writes between two parts.

<sub>[stdlib/Path.sl:43](../../stdlib/Path.sl#L43)</sub>

