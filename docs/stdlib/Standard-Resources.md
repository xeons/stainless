# Standard.Resources

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

What a program carries inside itself, on every platform.

A `.rc` listed among a build's sources is compiled by `llvm-rc` and folded
into the binary, and this reads it back:

```csharp
import Standard.Resources;

String ready = Resources.Text(201u);
byte[] icon  = Resources.Bytes(Resources.Bitmap, 101);
```

**The same answers on both platforms, by two different routes.** A PE has a
resource directory and the loader indexes it, so a Windows build asks
`FindResourceW` and gets a pointer into the mapped image. ELF has no such
section, so the compiler puts the compiled `.res` in ordinary constant data
and this walks it. Both were checked against each other on the same script,
entry by entry, which is the only reason the claim is worth making.

**What travels and what does not.** Bytes travel: `RT_RCDATA`, `RT_BITMAP`,
`RT_STRING`, `RT_HTML` and a type a script invents are all readable
anywhere. What does not travel is the part where the *operating system*
reads the resource on the program's behalf -- an `RT_MANIFEST` selects
comctl32 version 6, an `RT_GROUP_ICON` becomes the window's icon, and an
`RT_DIALOG` becomes a window full of controls, none of which anything
outside Windows does. Those are readable here as bytes and mean nothing.

**Nothing is freed.** A resource lives in the loaded image on both routes,
so `Pointer` hands back memory that is already there and stays valid as long
as the program runs. It must not be written through. `Bytes` copies, which
is what anything outliving the call wants.

## Contents

**Functions** &nbsp; [BitmapFile](#bitmapfile-function) &middot; [Bytes](#bytes-function) &middot; [Bytes](#bytes-function) &middot; [Exists](#exists-function) &middot; [Exists](#exists-function) &middot; [Pointer](#pointer-function) &middot; [Size](#size-function) &middot; [Text](#text-function)

**Constants** &nbsp; [Accelerator](#accelerator-constant) &middot; [Bitmap](#bitmap-constant) &middot; [Cursor](#cursor-constant) &middot; [Dialog](#dialog-constant) &middot; [GroupCursor](#groupcursor-constant) &middot; [GroupIcon](#groupicon-constant) &middot; [Html](#html-constant) &middot; [Icon](#icon-constant) &middot; [Manifest](#manifest-constant) &middot; [ManifestId](#manifestid-constant) &middot; [Menu](#menu-constant) &middot; [MessageTable](#messagetable-constant) &middot; [RcData](#rcdata-constant) &middot; [StringTable](#stringtable-constant) &middot; [Version](#version-constant)

## Functions

### BitmapFile *function*

```
byte[] BitmapFile(int id)
```

A `RT_BITMAP` as a whole `.bmp` file.

**The resource is not a file.** The resource compiler strips the 14-byte
`BITMAPFILEHEADER`, because Windows never wants it -- `LoadImageW` is handed
the `BITMAPINFOHEADER` onwards and knows what to do. Anything else that
decodes an image expects a whole file, so this puts the header back.

The pixel offset is not guesswork: the DIB header says how long it is, and
the palette between it and the pixels is `biClrUsed` entries of four bytes,
or the full `2^depth` when that field is zero and the depth is 8 or fewer.

Empty when there is no such bitmap.

<sub>[stdlib/Resources.sl:376](../../stdlib/Resources.sl#L376)</sub>

### Bytes *function*

```
byte[] Bytes(int type, int id)
```

A resource's bytes, copied into an array this program owns.

Empty when there is no such resource, which is also what an empty resource
gives -- ask `Exists` where the difference matters.

<sub>[stdlib/Resources.sl:303](../../stdlib/Resources.sl#L303)</sub>

### Bytes *function*

```
byte[] Bytes(String type, String name)
```

The same, for a resource named by text.

<sub>[stdlib/Resources.sl:310](../../stdlib/Resources.sl#L310)</sub>

### Exists *function*

```
bool Exists(int type, int id)
```

Whether a resource of this type and number is there.

<sub>[stdlib/Resources.sl:276](../../stdlib/Resources.sl#L276)</sub>

### Exists *function*

```
bool Exists(String type, String name)
```

Whether one named by text, of a type named by text, is there.

<sub>[stdlib/Resources.sl:279](../../stdlib/Resources.sl#L279)</sub>

### Pointer *function*

```
byte* Pointer(int type, int id, uint* byteCount)
```

A pointer straight at a resource's bytes, without copying them.

The memory belongs to the loaded image: read-only, never freed, and valid
for as long as the program runs. `Bytes` is the one to use for anything that
outlives the call.

<sub>[stdlib/Resources.sl:295](../../stdlib/Resources.sl#L295)</sub>

### Size *function*

```
uint Size(int type, int id)
```

How many bytes a resource holds, or zero when there is none.

<sub>[stdlib/Resources.sl:284](../../stdlib/Resources.sl#L284)</sub>

### Text *function*

```
String Text(uint id)
```

One string from a string table, by the number the script gave it.

**A string is not a resource of its own.** The resource compiler files them
sixteen to a block: the block's name is `id / 16 + 1`, and inside it each of
the sixteen slots is a 16-bit length followed by that many UTF-16 units,
with a length of zero meaning nothing is filed at that slot. `LoadStringW`
does this arithmetic on Windows; it is written out here so that both
platforms answer identically and so that Windows needs no user32.

Empty for a number with no string, which is what `LoadStringW` answers too.

<sub>[stdlib/Resources.sl:336](../../stdlib/Resources.sl#L336)</sub>

## Constants

### Accelerator *constant*

```
const int Accelerator = 9
```

*No documentation.*

<sub>[stdlib/Resources.sl:67](../../stdlib/Resources.sl#L67)</sub>

### Bitmap *constant*

```
const int Bitmap = 2
```

*No documentation.*

<sub>[stdlib/Resources.sl:62](../../stdlib/Resources.sl#L62)</sub>

### Cursor *constant*

```
const int Cursor = 1
```

The `RT_` numbers, which mean what they mean in `winuser.h` because that is
what the resource compiler writes.

<sub>[stdlib/Resources.sl:61](../../stdlib/Resources.sl#L61)</sub>

### Dialog *constant*

```
const int Dialog = 5
```

*No documentation.*

<sub>[stdlib/Resources.sl:65](../../stdlib/Resources.sl#L65)</sub>

### GroupCursor *constant*

```
const int GroupCursor = 12
```

*No documentation.*

<sub>[stdlib/Resources.sl:70](../../stdlib/Resources.sl#L70)</sub>

### GroupIcon *constant*

```
const int GroupIcon = 14
```

*No documentation.*

<sub>[stdlib/Resources.sl:71](../../stdlib/Resources.sl#L71)</sub>

### Html *constant*

```
const int Html = 23
```

*No documentation.*

<sub>[stdlib/Resources.sl:73](../../stdlib/Resources.sl#L73)</sub>

### Icon *constant*

```
const int Icon = 3
```

*No documentation.*

<sub>[stdlib/Resources.sl:63](../../stdlib/Resources.sl#L63)</sub>

### Manifest *constant*

```
const int Manifest = 24
```

*No documentation.*

<sub>[stdlib/Resources.sl:74](../../stdlib/Resources.sl#L74)</sub>

### ManifestId *constant*

```
const int ManifestId = 1
```

`CREATEPROCESS_MANIFEST_RESOURCE_ID`: the name an executable's own manifest
is filed under.

<sub>[stdlib/Resources.sl:78](../../stdlib/Resources.sl#L78)</sub>

### Menu *constant*

```
const int Menu = 4
```

*No documentation.*

<sub>[stdlib/Resources.sl:64](../../stdlib/Resources.sl#L64)</sub>

### MessageTable *constant*

```
const int MessageTable = 11
```

*No documentation.*

<sub>[stdlib/Resources.sl:69](../../stdlib/Resources.sl#L69)</sub>

### RcData *constant*

```
const int RcData = 10
```

*No documentation.*

<sub>[stdlib/Resources.sl:68](../../stdlib/Resources.sl#L68)</sub>

### StringTable *constant*

```
const int StringTable = 6
```

*No documentation.*

<sub>[stdlib/Resources.sl:66](../../stdlib/Resources.sl#L66)</sub>

### Version *constant*

```
const int Version = 16
```

*No documentation.*

<sub>[stdlib/Resources.sl:72](../../stdlib/Resources.sl#L72)</sub>

