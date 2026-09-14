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

**Functions** &nbsp; [DirectoryName](#directoryname-function) &middot; [Extension](#extension-function) &middot; [FileName](#filename-function) &middot; [IsRooted](#isrooted-function) &middot; [Join](#join-function) &middot; [Join](#join-function) &middot; [Split](#split-function) &middot; [WithExtension](#withextension-function) &middot; [WithoutExtension](#withoutextension-function)

**Constants** &nbsp; [AltSeparator](#altseparator-constant) &middot; [Separator](#separator-constant)

## Functions

### DirectoryName *function*

```
String DirectoryName(String path)
```

Everything before the last part, without its trailing separator. A path
with no separator gives the empty string.

<sub>[stdlib/Path.sl:115](../../stdlib/Path.sl#L115)</sub>

### Extension *function*

```
String Extension(String path)
```

The extension, with its dot: `notes.txt` gives `.txt`. No dot in the last
part, or a dot that starts it, gives the empty string.

<sub>[stdlib/Path.sl:126](../../stdlib/Path.sl#L126)</sub>

### FileName *function*

```
String FileName(String path)
```

The last part: `a/b/c.txt` gives `c.txt`.

<sub>[stdlib/Path.sl:108](../../stdlib/Path.sl#L108)</sub>

### IsRooted *function*

```
bool IsRooted(String path)
```

True when the path starts at a root, so that joining it onto another would
be a mistake.

`/x` is rooted everywhere. `\x` and `C:\x` are rooted on Windows and are
ordinary relative names elsewhere, where a colon and a backslash are both
characters a filename may contain.

<sub>[stdlib/Path.sl:159](../../stdlib/Path.sl#L159)</sub>

### Join *function*

```
String Join(String left, String right)
```

Joins two parts with a single separator, whichever way each one ends or
starts. An empty part contributes nothing.

<sub>[stdlib/Path.sl:80](../../stdlib/Path.sl#L80)</sub>

### Join *function*

```
String Join(String first, String second, String third)
```

Three parts joined left to right, with the same rule at each step.

<sub>[stdlib/Path.sl:103](../../stdlib/Path.sl#L103)</sub>

### Split *function*

```
List<String> Split(String path)
```

The parts, with the separators dropped and empty parts skipped.

<sub>[stdlib/Path.sl:175](../../stdlib/Path.sl#L175)</sub>

### WithExtension *function*

```
String WithExtension(String path, String with)
```

The path with a different extension. `with` may be written with or without
its leading dot.

<sub>[stdlib/Path.sl:146](../../stdlib/Path.sl#L146)</sub>

### WithoutExtension *function*

```
String WithoutExtension(String path)
```

The last part with its extension removed.

<sub>[stdlib/Path.sl:138](../../stdlib/Path.sl#L138)</sub>

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

