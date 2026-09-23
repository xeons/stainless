# Standard.Drawing

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Raster images: reading them, drawing on them, and writing them back.

```csharp
var loaded = Image.FromFile("logo.png");
if (!loaded.Ok) { return; }

var logo = loaded.Value;
logo.FillRectangle(Rgba.FromRgb(200, 30, 30), 8, 8, 64, 24);
logo.DrawLine(Rgba.Black, 0, 0, logo.Width, logo.Height, 2);
logo.Save("out.png", ImageFormat.Png);
```

**GDI+ on Windows, libgd everywhere else, and neither is linked.** Both are
loaded by name the first time an image is made. That is what lets this live
in the standard library at all: a `#pragma comment(lib, "gdiplus")` would
put an import in every Stainless binary on Windows including the ones that
never make an image, and `-lgd` needs libgd's *development* package where
what a machine actually has is the runtime one. So a program that makes no
image pays nothing, and a machine with no imaging library answers
`ImageError.NoBackend` -- a value to print, rather than a link error.

**There is no text.** Drawing a string needs a font, and the two backends
disagree about everything to do with one: GDI+ takes a family name and a
device context, libgd wants FreeType and a path to a `.ttf`. That is a
module of its own and saying so is better than half of it.

**Not a canvas for a window.** `Forms.Drawing` is what draws on screen and
is the widget set's business. This is a picture in memory: it is what reads
the PNG that a `Forms.Bitmap` could not, and what a program with no user
interface at all uses to make a chart or a thumbnail.

## Contents

**Types** &nbsp; [Image](#image-class) &middot; [ImageError](#imageerror-enum) &middot; [ImageFormat](#imageformat-enum) &middot; [Imaging](#imaging-class) &middot; [Rgba](#rgba-struct)

## Types

### Image *class*

```
sealed class Image
```

A picture in memory.

**The handle is released by the destructor**, so an image is closed when the
last reference to it goes and there is no `Dispose` to forget. That is worth
stating because the thing being released is a GDI+ or libgd object rather
than memory the language allocated -- ARC counts the `Image`, and the
`Image` owns the picture.

<sub>[stdlib/Drawing/Image.sl:38](../../stdlib/Drawing/Image.sl#L38)</sub>

#### Create *method*

```
static Result<Image, ImageError> Create(int width, int height)
```

An empty picture, every pixel transparent.

**Fails with**

- [ImageError.NoBackend](#nobackend-case) — there is no imaging library on this machine
- [ImageError.OutOfMemory](#outofmemory-case) — the backend would not make a picture that big
- [ImageError.Invalid](#invalid-case) — a width or a height that is not positive

<sub>[stdlib/Drawing/Image.sl:71](../../stdlib/Drawing/Image.sl#L71)</sub>

#### FromBytes *method*

```
static Result<Image, ImageError> FromBytes(byte[] data)
```

A picture decoded from bytes, whatever of the four formats they hold.

**Fails with**

- [ImageError.NoBackend](#nobackend-case) — there is no imaging library on this machine
- [ImageError.Unreadable](#unreadable-case) — the format was recognised and the decoder would not have the bytes
- [ImageError.Unsupported](#unsupported-case) — the first bytes are none of the four, or name a format this backend was built without
- [ImageError.Invalid](#invalid-case) — there are no bytes

**See also** &nbsp; [Image.FromFile](#fromfile-method)

<sub>[stdlib/Drawing/Image.sl:97](../../stdlib/Drawing/Image.sl#L97)</sub>

#### FromFile *method*

```
static Result<Image, ImageError> FromFile(String path)
```

A picture read from a file.

The bytes are read here rather than handed to the decoder, so that a
missing file is `NotFound` on both platforms rather than whatever each
library says about one it could not open.

**Fails with**

- [ImageError.NoBackend](#nobackend-case) — there is no imaging library on this machine
- [ImageError.NotFound](#notfound-case) — there is no file at that path
- [ImageError.Unreadable](#unreadable-case) — the file could not be read, or the decoder would not have it
- [ImageError.Unsupported](#unsupported-case) — the first bytes are none of the four, or name a format this backend was built without
- [ImageError.Invalid](#invalid-case) — the file is empty

**See also** &nbsp; [Image.Save](#save-method)

<sub>[stdlib/Drawing/Image.sl:134](../../stdlib/Drawing/Image.sl#L134)</sub>

#### FromBgra *method*

```
static Result<Image, ImageError> FromBgra(int width, int height, byte[] pixels)
```

A picture made from pixels in `CopyPixels`' order: blue, green, red and
straight alpha, rows top to bottom, `width * 4` bytes to a row.

What a clipboard or a capture hands back. The bytes are copied, so the
array may change afterwards without changing the picture.

**Fails with**

- [ImageError.NoBackend](#nobackend-case) — there is no imaging library on this machine
- [ImageError.OutOfMemory](#outofmemory-case) — the backend would not make a picture that big, or refused the pixels
- [ImageError.Invalid](#invalid-case) — a width or a height that is not positive, or fewer than `width * height * 4` bytes

**See also** &nbsp; [Image.CopyPixels](#copypixels-method)

<sub>[stdlib/Drawing/Image.sl:159](../../stdlib/Drawing/Image.sl#L159)</sub>

#### Width *property*

```
int Width { get; }
```

*No documentation.*

<sub>[stdlib/Drawing/Image.sl:179](../../stdlib/Drawing/Image.sl#L179)</sub>

#### Height *property*

```
int Height { get; }
```

*No documentation.*

<sub>[stdlib/Drawing/Image.sl:180](../../stdlib/Drawing/Image.sl#L180)</sub>

#### IsOpen *property*

```
bool IsOpen { get; }
```

Whether the picture is still open. False only after a destructor has
run, which a program cannot observe on an image it still holds.

<sub>[stdlib/Drawing/Image.sl:184](../../stdlib/Drawing/Image.sl#L184)</sub>

#### GetPixel *method*

```
Rgba GetPixel(int x, int y)
```

The colour at a point, or fully transparent for a point outside.

Answering rather than failing, because the common caller is a loop over
a neighbourhood and a test at every edge is what that loop would
otherwise be made of.

<sub>[stdlib/Drawing/Image.sl:193](../../stdlib/Drawing/Image.sl#L193)</sub>

#### SetPixel *method*

```
void SetPixel(int x, int y, Rgba colour)
```

Writes one pixel, replacing whatever was there rather than blending.

<sub>[stdlib/Drawing/Image.sl:204](../../stdlib/Drawing/Image.sl#L204)</sub>

#### Stride *property*

```
nuint Stride { get; }
```

How many bytes one row of `CopyPixels` occupies: four per pixel, with no
padding between rows.

<sub>[stdlib/Drawing/Image.sl:215](../../stdlib/Drawing/Image.sl#L215)</sub>

#### PixelByteLength *property*

```
nuint PixelByteLength { get; }
```

How many bytes `CopyPixels` writes.

<sub>[stdlib/Drawing/Image.sl:218](../../stdlib/Drawing/Image.sl#L218)</sub>

#### CopyPixels *method*

```
bool CopyPixels(byte[] into)
```

Every pixel, as four bytes each in the order **blue, green, red,
alpha**, rows top to bottom with no padding.

That order rather than red-first because it is what both a Windows DIB
and this module's own `Rgba.Packed` already are: `Packed` is
`0xAARRGGBB`, and its bytes on every machine this compiles for are B, G,
R, A. A reader wanting the other order swaps two bytes per pixel and
knows it is doing so; making this the packed order would have every
reader convert instead.

The alpha is **straight, not premultiplied**. Premultiplying is what a
particular compositor wants rather than what the picture is, so it
belongs to whoever is about to composite.

False when the picture is closed, when there is no backend, when `into`
is shorter than `PixelByteLength`, or when the backend refused.

**See also** &nbsp; [Image.ToBgra](#tobgra-method)

<sub>[stdlib/Drawing/Image.sl:238](../../stdlib/Drawing/Image.sl#L238)</sub>

#### ToBgra *method*

```
byte[] ToBgra()
```

The same bytes in an array of the right size, or an empty one for the
failures `CopyPixels` answers false for.

Empty rather than null for the reason `Encode` gives: an array is a value
here and is never null, and a picture with no pixels is not something
either backend produces.

**See also** &nbsp; [Image.CopyPixels](#copypixels-method)

<sub>[stdlib/Drawing/Image.sl:258](../../stdlib/Drawing/Image.sl#L258)</sub>

#### Clear *method*

```
void Clear(Rgba colour)
```

Fills the whole picture with one colour.

<sub>[stdlib/Drawing/Image.sl:279](../../stdlib/Drawing/Image.sl#L279)</sub>

#### DrawLine *method*

```
void DrawLine(Rgba colour, int x1, int y1, int x2, int y2, int thickness)
```

*No documentation.*

<sub>[stdlib/Drawing/Image.sl:286](../../stdlib/Drawing/Image.sl#L286)</sub>

#### DrawRectangle *method*

```
void DrawRectangle(Rgba colour, int x, int y, int width, int height, int thickness)
```

*No documentation.*

<sub>[stdlib/Drawing/Image.sl:294](../../stdlib/Drawing/Image.sl#L294)</sub>

#### FillRectangle *method*

```
void FillRectangle(Rgba colour, int x, int y, int width, int height)
```

*No documentation.*

<sub>[stdlib/Drawing/Image.sl:300](../../stdlib/Drawing/Image.sl#L300)</sub>

#### DrawEllipse *method*

```
void DrawEllipse(Rgba colour, int x, int y, int width, int height, int thickness)
```

An ellipse inside the rectangle given, which is how every other API here
and in `Forms.Drawing` spells one -- libgd's centre-and-size form is
converted by the backend.

<sub>[stdlib/Drawing/Image.sl:308](../../stdlib/Drawing/Image.sl#L308)</sub>

#### FillEllipse *method*

```
void FillEllipse(Rgba colour, int x, int y, int width, int height)
```

*No documentation.*

<sub>[stdlib/Drawing/Image.sl:314](../../stdlib/Drawing/Image.sl#L314)</sub>

#### DrawPolygon *method*

```
void DrawPolygon(Rgba colour, int[] points, int thickness)
```

A closed shape, from x and y in one flat array: `[x0, y0, x1, y1, ...]`.

**A flat array rather than a `Point[]`**, and that is a deliberate
absence. `Forms.Drawing` declares `Point`, `Size` and `Rectangle`, and a
program that loaded a PNG to put it on a form would have to qualify
every mention of whichever one it meant. Neither library should be the
one that makes the other awkward to import, so this one declares no
geometry at all.

<sub>[stdlib/Drawing/Image.sl:339](../../stdlib/Drawing/Image.sl#L339)</sub>

#### FillPolygon *method*

```
void FillPolygon(Rgba colour, int[] points)
```

*No documentation.*

<sub>[stdlib/Drawing/Image.sl:344](../../stdlib/Drawing/Image.sl#L344)</sub>

#### DrawImage *method*

```
void DrawImage(Image source, int x, int y)
```

Draws another picture on this one, at its own size.

**See also** &nbsp; [Image.DrawImageScaled](#drawimagescaled-method)

<sub>[stdlib/Drawing/Image.sl:362](../../stdlib/Drawing/Image.sl#L362)</sub>

#### DrawImageScaled *method*

```
void DrawImageScaled(Image source, int x, int y, int width, int height, int sourceX, int sourceY, int sourceWidth, int sourceHeight)
```

Draws part of another picture into a rectangle of this one, scaling to
fit. What a thumbnail and a sprite sheet are both made of.

<sub>[stdlib/Drawing/Image.sl:370](../../stdlib/Drawing/Image.sl#L370)</sub>

#### Resize *method*

```
Result<Image, ImageError> Resize(int width, int height)
```

A copy at another size, resampled.

**Fails with**

- [ImageError.NoBackend](#nobackend-case) — there is no imaging library on this machine
- [ImageError.OutOfMemory](#outofmemory-case) — the backend would not make a picture that big
- [ImageError.Invalid](#invalid-case) — a width or a height that is not positive

**See also** &nbsp; [Image.DrawImageScaled](#drawimagescaled-method)

<sub>[stdlib/Drawing/Image.sl:394](../../stdlib/Drawing/Image.sl#L394)</sub>

#### Encode *method*

```
Result<byte[], ImageError> Encode(ImageFormat format, int quality)
```

The encoded bytes, in the format asked for.

`quality` is 0 to 100 and reaches libgd's JPEG encoder; -1 is that
encoder's own default. GDI+ ignores it -- setting it there needs an
`EncoderParameters` laid out by hand for the one format that reads one,
and its default of 75 is the same number libgd uses.

**Fails with**

- [ImageError.NoBackend](#nobackend-case) — there is no imaging library on this machine
- [ImageError.Unsupported](#unsupported-case) — the backend cannot write that format -- a BMP on a libgd built without one -- or the encode failed, which it reports no other way

**See also** &nbsp; [Image.FromBytes](#frombytes-method)

<sub>[stdlib/Drawing/Image.sl:420](../../stdlib/Drawing/Image.sl#L420)</sub>

#### Save *method*

```
ImageError Save(String path, ImageFormat format, int quality)
```

Encodes and writes to a file. `ImageError.None` when it worked.

**Fails with**

- [ImageError.NoBackend](#nobackend-case) — there is no imaging library on this machine
- [ImageError.Unsupported](#unsupported-case) — the backend cannot write that format, or the encode failed
- [ImageError.WriteFailed](#writefailed-case) — the picture encoded and the file would not be written

**See also** &nbsp; [Image.FromFile](#fromfile-method)

<sub>[stdlib/Drawing/Image.sl:444](../../stdlib/Drawing/Image.sl#L444)</sub>

### ImageError *enum*

```
enum ImageError
```

What went wrong.

<sub>[stdlib/Drawing/ImageError.sl:30](../../stdlib/Drawing/ImageError.sl#L30)</sub>

#### None *case*

```
None = 0
```

*No documentation.*

<sub>[stdlib/Drawing/ImageError.sl:32](../../stdlib/Drawing/ImageError.sl#L32)</sub>

#### NoBackend *case*

```
NoBackend = 1
```

There is no imaging library on this machine. On Windows that means
`gdiplus.dll` would not load, which should not happen; on Linux it means
libgd is not installed, which is ordinary and is why this is a value
rather than a failure.

<sub>[stdlib/Drawing/ImageError.sl:38](../../stdlib/Drawing/ImageError.sl#L38)</sub>

#### NotFound *case*

```
NotFound = 2
```

No such file, or a directory along the path is missing.

<sub>[stdlib/Drawing/ImageError.sl:41](../../stdlib/Drawing/ImageError.sl#L41)</sub>

#### Unreadable *case*

```
Unreadable = 3
```

It is there and the decoder would not have it.

<sub>[stdlib/Drawing/ImageError.sl:44](../../stdlib/Drawing/ImageError.sl#L44)</sub>

#### Unsupported *case*

```
Unsupported = 4
```

The format is not one of the four, or is one this build of libgd was
compiled without.

<sub>[stdlib/Drawing/ImageError.sl:48](../../stdlib/Drawing/ImageError.sl#L48)</sub>

#### WriteFailed *case*

```
WriteFailed = 5
```

The encode worked and the write did not.

<sub>[stdlib/Drawing/ImageError.sl:51](../../stdlib/Drawing/ImageError.sl#L51)</sub>

#### OutOfMemory *case*

```
OutOfMemory = 6
```

The allocation failed, which for an image means a size nothing could
hold rather than a machine out of memory.

<sub>[stdlib/Drawing/ImageError.sl:55](../../stdlib/Drawing/ImageError.sl#L55)</sub>

#### Invalid *case*

```
Invalid = 7
```

A size that is not positive, or a call on an image that is already
closed.

<sub>[stdlib/Drawing/ImageError.sl:59](../../stdlib/Drawing/ImageError.sl#L59)</sub>

### ImageFormat *enum*

```
enum ImageFormat
```

The formats both backends read and write.

Four, because four is what GDI+ and libgd agree about. A file is recognised
by its first bytes rather than by its name, so a picture that arrived over a
socket is read the same way as one on disk.

<sub>[stdlib/Drawing/ImageFormat.sl:34](../../stdlib/Drawing/ImageFormat.sl#L34)</sub>

#### Png *case*

```
Png
```

*No documentation.*

<sub>[stdlib/Drawing/ImageFormat.sl:34](../../stdlib/Drawing/ImageFormat.sl#L34)</sub>

#### Jpeg *case*

```
Jpeg
```

*No documentation.*

<sub>[stdlib/Drawing/ImageFormat.sl:34](../../stdlib/Drawing/ImageFormat.sl#L34)</sub>

#### Bmp *case*

```
Bmp
```

*No documentation.*

<sub>[stdlib/Drawing/ImageFormat.sl:34](../../stdlib/Drawing/ImageFormat.sl#L34)</sub>

#### Gif *case*

```
Gif
```

*No documentation.*

<sub>[stdlib/Drawing/ImageFormat.sl:34](../../stdlib/Drawing/ImageFormat.sl#L34)</sub>

### Imaging *class*

```
class Imaging
```

The imaging library, loaded once and shared.

**Public so that a program can ask before it tries.** A tool that writes a
chart wants to say "install libgd" at startup rather than at the end of a
long computation, and `IsAvailable` is how it finds out.

<sub>[stdlib/Drawing/Imaging.sl:34](../../stdlib/Drawing/Imaging.sl#L34)</sub>

#### IsAvailable *property*

```
static bool IsAvailable { get; }
```

Whether there is an imaging library on this machine.

Loads it, so the first call is where the cost is and every `Image` after
it is free.

<sub>[stdlib/Drawing/Imaging.sl:74](../../stdlib/Drawing/Imaging.sl#L74)</sub>

#### BackendName *property*

```
static String BackendName { get; }
```

The name of the library behind it, for a program that reports what it
found. `""` when there is none.

<sub>[stdlib/Drawing/Imaging.sl:78](../../stdlib/Drawing/Imaging.sl#L78)</sub>

### Rgba *struct*

```
struct Rgba
```

A colour, as the eight-bit channels an image actually stores.

**Named for the layout rather than called `Color`**, and deliberately:
`Forms.Drawing` already declares a `Color`, and a program that loaded a PNG
to put it on a form would have to qualify every mention of either. `Rgba`
also says the one thing a caller has to know, which is that the alpha is
eight bits and 255 is opaque.

Packed as `0xAARRGGBB`, which is what GDI+ calls an ARGB and what the
libgd backend converts to and from -- libgd's alpha is seven bits and
inverted, and that is the only place it shows.

<sub>[stdlib/Drawing/Rgba.sl:42](../../stdlib/Drawing/Rgba.sl#L42)</sub>

#### R *field*

```
byte R
```

*No documentation.*

<sub>[stdlib/Drawing/Rgba.sl:44](../../stdlib/Drawing/Rgba.sl#L44)</sub>

#### G *field*

```
byte G
```

*No documentation.*

<sub>[stdlib/Drawing/Rgba.sl:45](../../stdlib/Drawing/Rgba.sl#L45)</sub>

#### B *field*

```
byte B
```

*No documentation.*

<sub>[stdlib/Drawing/Rgba.sl:46](../../stdlib/Drawing/Rgba.sl#L46)</sub>

#### A *field*

```
byte A
```

*No documentation.*

<sub>[stdlib/Drawing/Rgba.sl:47](../../stdlib/Drawing/Rgba.sl#L47)</sub>

#### FromRgb *method*

```
static Rgba FromRgb(byte red, byte green, byte blue)
```

An opaque colour.

**Parameters**

- `red` — 0 to 255
- `green` — 0 to 255
- `blue` — 0 to 255

**See also** &nbsp; [Rgba.FromArgb](#fromargb-method)

<sub>[stdlib/Drawing/Rgba.sl:55](../../stdlib/Drawing/Rgba.sl#L55)</sub>

#### FromArgb *method*

```
static Rgba FromArgb(byte alpha, byte red, byte green, byte blue)
```

A colour with an alpha, where 0 is invisible and 255 is opaque.

**Parameters**

- `alpha` — 0 to 255, and it comes first
- `red` — 0 to 255
- `green` — 0 to 255
- `blue` — 0 to 255

**See also** &nbsp; [Rgba.FromRgb](#fromrgb-method)

<sub>[stdlib/Drawing/Rgba.sl:72](../../stdlib/Drawing/Rgba.sl#L72)</sub>

#### FromPacked *method*

```
static Rgba FromPacked(uint packed)
```

From `0xAARRGGBB`, which is what `Packed` answers and what a colour
written as a hex literal in a program usually is.

**See also** &nbsp; [Rgba.Packed](#packed-property)

<sub>[stdlib/Drawing/Rgba.sl:86](../../stdlib/Drawing/Rgba.sl#L86)</sub>

#### Packed *property*

```
uint Packed { get; }
```

`0xAARRGGBB`.

<sub>[stdlib/Drawing/Rgba.sl:93](../../stdlib/Drawing/Rgba.sl#L93)</sub>

#### IsInvisible *property*

```
bool IsInvisible { get; }
```

Whether anything of this would be drawn at all.

<sub>[stdlib/Drawing/Rgba.sl:97](../../stdlib/Drawing/Rgba.sl#L97)</sub>

#### Equals *method*

```
bool Equals(Rgba other)
```

*No documentation.*

<sub>[stdlib/Drawing/Rgba.sl:99](../../stdlib/Drawing/Rgba.sl#L99)</sub>

#### Transparent *property*

```
static Rgba Transparent { get; }
```

**Properties rather than `static readonly` fields**, which is not a
style choice. A static needs an entry point to be initialized from and a
`--shared` library has none (SL0380) -- and this module is compiled into
every program, including every shared library anybody builds. A property
is a function, so there is nothing to initialize and nothing to go
wrong; the six of them fold to four bytes each.

<sub>[stdlib/Drawing/Rgba.sl:107](../../stdlib/Drawing/Rgba.sl#L107)</sub>

#### Black *property*

```
static Rgba Black { get; }
```

*No documentation.*

<sub>[stdlib/Drawing/Rgba.sl:108](../../stdlib/Drawing/Rgba.sl#L108)</sub>

#### White *property*

```
static Rgba White { get; }
```

*No documentation.*

<sub>[stdlib/Drawing/Rgba.sl:109](../../stdlib/Drawing/Rgba.sl#L109)</sub>

#### Red *property*

```
static Rgba Red { get; }
```

*No documentation.*

<sub>[stdlib/Drawing/Rgba.sl:110](../../stdlib/Drawing/Rgba.sl#L110)</sub>

#### Green *property*

```
static Rgba Green { get; }
```

*No documentation.*

<sub>[stdlib/Drawing/Rgba.sl:111](../../stdlib/Drawing/Rgba.sl#L111)</sub>

#### Blue *property*

```
static Rgba Blue { get; }
```

*No documentation.*

<sub>[stdlib/Drawing/Rgba.sl:112](../../stdlib/Drawing/Rgba.sl#L112)</sub>

