# Standard.Resources

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

What a program carries inside itself, on every platform.

A `.rc` listed among a build's sources is compiled by `llvm-rc` and folded
into the binary, and this reads it back:

```csharp
import Standard.Resources;

String ready = Resources.GetText(201u);
byte[] icon  = Resources.GetBytes(ResourceType.Bitmap, 101);
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
so `GetPointer` hands back memory that is already there and stays valid as long
as the program runs. It must not be written through. `GetBytes` copies, which
is what anything outliving the call wants.

## Contents

**Types** &nbsp; [ResourceType](#resourcetype-enum)

**Functions** &nbsp; [Exists](#exists-function) &middot; [Exists](#exists-function) &middot; [GetBitmapFile](#getbitmapfile-function) &middot; [GetBytes](#getbytes-function) &middot; [GetBytes](#getbytes-function) &middot; [GetPointer](#getpointer-function) &middot; [GetSize](#getsize-function) &middot; [GetText](#gettext-function)

**Constants** &nbsp; [ManifestId](#manifestid-constant)

## Types

### ResourceType *enum*

```
enum ResourceType
```

The `RT_` numbers, which mean what they mean in `winuser.h` because that is
what the resource compiler writes.

An enum rather than fourteen constants at module level, because `Icon`,
`Menu`, `Dialog` and `Version` are words an importer has other uses for.

<sub>[stdlib/Resources/ResourceType.sl:33](../../stdlib/Resources/ResourceType.sl#L33)</sub>

#### Cursor *case*

```
Cursor = 1
```

`RT_CURSOR`.

<sub>[stdlib/Resources/ResourceType.sl:36](../../stdlib/Resources/ResourceType.sl#L36)</sub>

#### Bitmap *case*

```
Bitmap = 2
```

`RT_BITMAP`, without the file header; `GetBitmapFile` puts one back.

<sub>[stdlib/Resources/ResourceType.sl:39](../../stdlib/Resources/ResourceType.sl#L39)</sub>

#### Icon *case*

```
Icon = 3
```

`RT_ICON`.

<sub>[stdlib/Resources/ResourceType.sl:42](../../stdlib/Resources/ResourceType.sl#L42)</sub>

#### Menu *case*

```
Menu = 4
```

`RT_MENU`.

<sub>[stdlib/Resources/ResourceType.sl:45](../../stdlib/Resources/ResourceType.sl#L45)</sub>

#### Dialog *case*

```
Dialog = 5
```

`RT_DIALOG`.

<sub>[stdlib/Resources/ResourceType.sl:48](../../stdlib/Resources/ResourceType.sl#L48)</sub>

#### StringTable *case*

```
StringTable = 6
```

`RT_STRING`; `GetText` reads one entry out of a block of sixteen.

<sub>[stdlib/Resources/ResourceType.sl:51](../../stdlib/Resources/ResourceType.sl#L51)</sub>

#### Accelerator *case*

```
Accelerator = 9
```

`RT_ACCELERATOR`.

<sub>[stdlib/Resources/ResourceType.sl:54](../../stdlib/Resources/ResourceType.sl#L54)</sub>

#### RcData *case*

```
RcData = 10
```

`RT_RCDATA`, which is bytes and nothing else, and so the one that
travels to every platform unchanged.

<sub>[stdlib/Resources/ResourceType.sl:58](../../stdlib/Resources/ResourceType.sl#L58)</sub>

#### MessageTable *case*

```
MessageTable = 11
```

`RT_MESSAGETABLE`.

<sub>[stdlib/Resources/ResourceType.sl:61](../../stdlib/Resources/ResourceType.sl#L61)</sub>

#### GroupCursor *case*

```
GroupCursor = 12
```

`RT_GROUP_CURSOR`.

<sub>[stdlib/Resources/ResourceType.sl:64](../../stdlib/Resources/ResourceType.sl#L64)</sub>

#### GroupIcon *case*

```
GroupIcon = 14
```

`RT_GROUP_ICON`.

<sub>[stdlib/Resources/ResourceType.sl:67](../../stdlib/Resources/ResourceType.sl#L67)</sub>

#### Version *case*

```
Version = 16
```

`RT_VERSION`.

<sub>[stdlib/Resources/ResourceType.sl:70](../../stdlib/Resources/ResourceType.sl#L70)</sub>

#### Html *case*

```
Html = 23
```

`RT_HTML`.

<sub>[stdlib/Resources/ResourceType.sl:73](../../stdlib/Resources/ResourceType.sl#L73)</sub>

#### Manifest *case*

```
Manifest = 24
```

`RT_MANIFEST`, read by the loader rather than by the program.

<sub>[stdlib/Resources/ResourceType.sl:76](../../stdlib/Resources/ResourceType.sl#L76)</sub>

## Functions

### Exists *function*

```
bool Exists(ResourceType type, int id)
```

Whether a resource of this type and number is there.

**Parameters**

- `type` — which `RT_` kind it was filed as
- `id` — the number the script filed the resource under

<sub>[stdlib/Resources/Resources.sl:296](../../stdlib/Resources/Resources.sl#L296)</sub>

### Exists *function*

```
bool Exists(String type, String name)
```

Whether one named by text, of a type named by text, is there.

**Parameters**

- `type` — the type name the script invented
- `name` — the resource name, matched without regard to ASCII case

<sub>[stdlib/Resources/Resources.sl:303](../../stdlib/Resources/Resources.sl#L303)</sub>

### GetBitmapFile *function*

```
byte[] GetBitmapFile(int id)
```

A `RT_BITMAP` as a whole `.bmp` file.

**The resource is not a file.** The resource compiler strips the 14-byte
`BITMAPFILEHEADER`, because Windows never wants it -- `LoadImageW` is handed
the `BITMAPINFOHEADER` onwards and knows what to do. Anything else that
decodes an image expects a whole file, so this puts the header back.

The pixel offset is not guesswork: the DIB header says how long it is, and
the palette between it and the pixels is `biClrUsed` entries of four bytes,
or the full `2^depth` when that field is zero and the depth is 8 or fewer.
A 40-byte header with `BI_BITFIELDS` is followed by its three colour masks
first; the 12-byte `BITMAPCOREHEADER` has no `biClrUsed`, and its palette
entries are three bytes each.

Empty when there is no such bitmap.

<sub>[stdlib/Resources/Resources.sl:433](../../stdlib/Resources/Resources.sl#L433)</sub>

### GetBytes *function*

```
byte[] GetBytes(ResourceType type, int id)
```

A resource's bytes, copied into an array this program owns.

Empty when there is no such resource, which is also what an empty resource
gives -- ask `Exists` where the difference matters.

**Parameters**

- `type` — an `RT_` number
- `id` — the number the script filed the resource under

**See also** &nbsp; [Resources.Exists](#exists-function)

<sub>[stdlib/Resources/Resources.sl:342](../../stdlib/Resources/Resources.sl#L342)</sub>

### GetBytes *function*

```
byte[] GetBytes(String type, String name)
```

The same, for a resource named by text.

**Parameters**

- `type` — the type name the script invented
- `name` — the resource name, matched without regard to ASCII case

**See also** &nbsp; [Resources.Exists](#exists-function)

<sub>[stdlib/Resources/Resources.sl:354](../../stdlib/Resources/Resources.sl#L354)</sub>

### GetPointer *function*

```
byte* GetPointer(ResourceType type, int id, uint* byteCount)
```

A pointer straight at a resource's bytes, without copying them.

The memory belongs to the loaded image: read-only, never freed, and valid
for as long as the program runs. `GetBytes` is the one to use for anything that
outlives the call.

**Parameters**

- `type` — an `RT_` number
- `id` — the number the script filed the resource under
- `byteCount` — where the size is written, or null to skip it

**See also** &nbsp; [Resources.GetBytes](#getbytes-function)

<sub>[stdlib/Resources/Resources.sl:329](../../stdlib/Resources/Resources.sl#L329)</sub>

### GetSize *function*

```
uint GetSize(ResourceType type, int id)
```

How many bytes a resource holds, or zero when there is none.

**Parameters**

- `type` — an `RT_` number
- `id` — the number the script filed the resource under

<sub>[stdlib/Resources/Resources.sl:312](../../stdlib/Resources/Resources.sl#L312)</sub>

### GetText *function*

```
String GetText(uint id)
```

One string from a string table, by the number the script gave it.

**A string is not a resource of its own.** The resource compiler files them
sixteen to a block: the block's name is `id / 16 + 1`, and inside it each of
the sixteen slots is a 16-bit length followed by that many UTF-16 units,
with a length of zero meaning nothing is filed at that slot. `LoadStringW`
does this arithmetic on Windows; it is written out here so that both
platforms answer identically and so that Windows needs no user32.

Empty for a number with no string, which is what `LoadStringW` answers too.

<sub>[stdlib/Resources/Resources.sl:384](../../stdlib/Resources/Resources.sl#L384)</sub>

## Constants

### ManifestId *constant*

```
const int ManifestId = 1
```

`CREATEPROCESS_MANIFEST_RESOURCE_ID`: the name an executable's own manifest
is filed under.

<sub>[stdlib/Resources/Resources.sl:59](../../stdlib/Resources/Resources.sl#L59)</sub>

