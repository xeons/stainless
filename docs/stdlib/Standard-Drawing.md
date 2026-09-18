# Standard.Drawing

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Raster images: reading them, drawing on them, and writing them back.

```csharp
var loaded = Image.FromFile("logo.png");
if (!loaded.Ok) { return; }

var logo = loaded.Value;
logo.FillRectangle(Rgba.Rgb(200, 30, 30), 8, 8, 64, 24);
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

<sub>[stdlib/Drawing.sl:1229](../../stdlib/Drawing.sl#L1229)</sub>

#### Create *method*

```
static Result<Image, ImageError> Create(int width, int height)
```

An empty picture, every pixel transparent.

<sub>[stdlib/Drawing.sl:1255](../../stdlib/Drawing.sl#L1255)</sub>

#### FromBytes *method*

```
static Result<Image, ImageError> FromBytes(byte[] data)
```

A picture decoded from bytes, whatever of the four formats they hold.

<sub>[stdlib/Drawing.sl:1271](../../stdlib/Drawing.sl#L1271)</sub>

#### FromFile *method*

```
static Result<Image, ImageError> FromFile(String path)
```

A picture read from a file.

The bytes are read here rather than handed to the decoder, so that a
missing file is `NotFound` on both platforms rather than whatever each
library says about one it could not open.

<sub>[stdlib/Drawing.sl:1297](../../stdlib/Drawing.sl#L1297)</sub>

#### Width *property*

```
int Width { get; }
```

*No documentation.*

<sub>[stdlib/Drawing.sl:1310](../../stdlib/Drawing.sl#L1310)</sub>

#### Height *property*

```
int Height { get; }
```

*No documentation.*

<sub>[stdlib/Drawing.sl:1311](../../stdlib/Drawing.sl#L1311)</sub>

#### IsOpen *property*

```
bool IsOpen { get; }
```

Whether the picture is still open. False only after a destructor has
run, which a program cannot observe on an image it still holds.

<sub>[stdlib/Drawing.sl:1315](../../stdlib/Drawing.sl#L1315)</sub>

#### GetPixel *method*

```
Rgba GetPixel(int x, int y)
```

The colour at a point, or fully transparent for a point outside.

Answering rather than failing, because the common caller is a loop over
a neighbourhood and a test at every edge is what that loop would
otherwise be made of.

<sub>[stdlib/Drawing.sl:1324](../../stdlib/Drawing.sl#L1324)</sub>

#### SetPixel *method*

```
void SetPixel(int x, int y, Rgba colour)
```

Writes one pixel, replacing whatever was there rather than blending.

<sub>[stdlib/Drawing.sl:1335](../../stdlib/Drawing.sl#L1335)</sub>

#### Stride *property*

```
nuint Stride { get; }
```

How many bytes one row of `CopyPixels` occupies: four per pixel, with no
padding between rows.

<sub>[stdlib/Drawing.sl:1346](../../stdlib/Drawing.sl#L1346)</sub>

#### PixelByteLength *property*

```
nuint PixelByteLength { get; }
```

How many bytes `CopyPixels` writes.

<sub>[stdlib/Drawing.sl:1349](../../stdlib/Drawing.sl#L1349)</sub>

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

<sub>[stdlib/Drawing.sl:1367](../../stdlib/Drawing.sl#L1367)</sub>

#### ToBgra *method*

```
byte[] ToBgra()
```

The same bytes in an array of the right size, or an empty one for the
failures `CopyPixels` answers false for.

Empty rather than null for the reason `Encode` gives: an array is a value
here and is never null, and a picture with no pixels is not something
either backend produces.

<sub>[stdlib/Drawing.sl:1385](../../stdlib/Drawing.sl#L1385)</sub>

#### Clear *method*

```
void Clear(Rgba colour)
```

Fills the whole picture with one colour.

<sub>[stdlib/Drawing.sl:1406](../../stdlib/Drawing.sl#L1406)</sub>

#### DrawLine *method*

```
void DrawLine(Rgba colour, int x1, int y1, int x2, int y2, int thickness)
```

*No documentation.*

<sub>[stdlib/Drawing.sl:1413](../../stdlib/Drawing.sl#L1413)</sub>

#### DrawRectangle *method*

```
void DrawRectangle(Rgba colour, int x, int y, int width, int height, int thickness)
```

*No documentation.*

<sub>[stdlib/Drawing.sl:1421](../../stdlib/Drawing.sl#L1421)</sub>

#### FillRectangle *method*

```
void FillRectangle(Rgba colour, int x, int y, int width, int height)
```

*No documentation.*

<sub>[stdlib/Drawing.sl:1427](../../stdlib/Drawing.sl#L1427)</sub>

#### DrawEllipse *method*

```
void DrawEllipse(Rgba colour, int x, int y, int width, int height, int thickness)
```

An ellipse inside the rectangle given, which is how every other API here
and in `Forms.Drawing` spells one -- libgd's centre-and-size form is
converted by the backend.

<sub>[stdlib/Drawing.sl:1435](../../stdlib/Drawing.sl#L1435)</sub>

#### FillEllipse *method*

```
void FillEllipse(Rgba colour, int x, int y, int width, int height)
```

*No documentation.*

<sub>[stdlib/Drawing.sl:1441](../../stdlib/Drawing.sl#L1441)</sub>

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

<sub>[stdlib/Drawing.sl:1466](../../stdlib/Drawing.sl#L1466)</sub>

#### FillPolygon *method*

```
void FillPolygon(Rgba colour, int[] points)
```

*No documentation.*

<sub>[stdlib/Drawing.sl:1471](../../stdlib/Drawing.sl#L1471)</sub>

#### Draw *method*

```
void Draw(Image source, int x, int y)
```

Draws another picture on this one, at its own size.

<sub>[stdlib/Drawing.sl:1487](../../stdlib/Drawing.sl#L1487)</sub>

#### DrawScaled *method*

```
void DrawScaled(Image source, int x, int y, int width, int height, int sourceX, int sourceY, int sourceWidth, int sourceHeight)
```

Draws part of another picture into a rectangle of this one, scaling to
fit. What a thumbnail and a sprite sheet are both made of.

<sub>[stdlib/Drawing.sl:1495](../../stdlib/Drawing.sl#L1495)</sub>

#### Resize *method*

```
Result<Image, ImageError> Resize(int width, int height)
```

A copy at another size, resampled.

<sub>[stdlib/Drawing.sl:1511](../../stdlib/Drawing.sl#L1511)</sub>

#### Encode *method*

```
Result<byte[], ImageError> Encode(ImageFormat format, int quality)
```

The encoded bytes, in the format asked for.

`quality` is 0 to 100 and reaches libgd's JPEG encoder; -1 is that
encoder's own default. GDI+ ignores it -- setting it there needs an
`EncoderParameters` laid out by hand for the one format that reads one,
and its default of 75 is the same number libgd uses.

<sub>[stdlib/Drawing.sl:1529](../../stdlib/Drawing.sl#L1529)</sub>

#### Save *method*

```
ImageError Save(String path, ImageFormat format, int quality)
```

Encodes and writes to a file. `ImageError.None` when it worked.

<sub>[stdlib/Drawing.sl:1545](../../stdlib/Drawing.sl#L1545)</sub>

### ImageError *enum*

```
enum ImageError
```

What went wrong.

<sub>[stdlib/Drawing.sl:150](../../stdlib/Drawing.sl#L150)</sub>

#### None *case*

```
None = 0
```

*No documentation.*

<sub>[stdlib/Drawing.sl:152](../../stdlib/Drawing.sl#L152)</sub>

#### NoBackend *case*

```
NoBackend = 1
```

There is no imaging library on this machine. On Windows that means
`gdiplus.dll` would not load, which should not happen; on Linux it means
libgd is not installed, which is ordinary and is why this is a value
rather than a failure.

<sub>[stdlib/Drawing.sl:158](../../stdlib/Drawing.sl#L158)</sub>

#### NotFound *case*

```
NotFound = 2
```

No such file, or a directory along the path is missing.

<sub>[stdlib/Drawing.sl:161](../../stdlib/Drawing.sl#L161)</sub>

#### Unreadable *case*

```
Unreadable = 3
```

It is there and the decoder would not have it.

<sub>[stdlib/Drawing.sl:164](../../stdlib/Drawing.sl#L164)</sub>

#### Unsupported *case*

```
Unsupported = 4
```

The format is not one of the four, or is one this build of libgd was
compiled without.

<sub>[stdlib/Drawing.sl:168](../../stdlib/Drawing.sl#L168)</sub>

#### WriteFailed *case*

```
WriteFailed = 5
```

The encode worked and the write did not.

<sub>[stdlib/Drawing.sl:171](../../stdlib/Drawing.sl#L171)</sub>

#### OutOfMemory *case*

```
OutOfMemory = 6
```

The allocation failed, which for an image means a size nothing could
hold rather than a machine out of memory.

<sub>[stdlib/Drawing.sl:175](../../stdlib/Drawing.sl#L175)</sub>

#### Invalid *case*

```
Invalid = 7
```

A size that is not positive, or a call on an image that is already
closed.

<sub>[stdlib/Drawing.sl:179](../../stdlib/Drawing.sl#L179)</sub>

### ImageFormat *enum*

```
enum ImageFormat
```

The formats both backends read and write.

Four, because four is what GDI+ and libgd agree about. A file is recognised
by its first bytes rather than by its name, so a picture that arrived over a
socket is read the same way as one on disk.

<sub>[stdlib/Drawing.sl:147](../../stdlib/Drawing.sl#L147)</sub>

#### Png *case*

```
Png
```

*No documentation.*

<sub>[stdlib/Drawing.sl:147](../../stdlib/Drawing.sl#L147)</sub>

#### Jpeg *case*

```
Jpeg
```

*No documentation.*

<sub>[stdlib/Drawing.sl:147](../../stdlib/Drawing.sl#L147)</sub>

#### Bmp *case*

```
Bmp
```

*No documentation.*

<sub>[stdlib/Drawing.sl:147](../../stdlib/Drawing.sl#L147)</sub>

#### Gif *case*

```
Gif
```

*No documentation.*

<sub>[stdlib/Drawing.sl:147](../../stdlib/Drawing.sl#L147)</sub>

### Imaging *class*

```
class Imaging
```

The imaging library, loaded once and shared.

**Public so that a program can ask before it tries.** A tool that writes a
chart wants to say "install libgd" at startup rather than at the end of a
long computation, and `Available` is how it finds out.

<sub>[stdlib/Drawing.sl:1157](../../stdlib/Drawing.sl#L1157)</sub>

#### Available *property*

```
static bool Available { get; }
```

Whether there is an imaging library on this machine.

Loads it, so the first call is where the cost is and every `Image` after
it is free.

<sub>[stdlib/Drawing.sl:1197](../../stdlib/Drawing.sl#L1197)</sub>

#### BackendName *property*

```
static String BackendName { get; }
```

The name of the library behind it, for a program that reports what it
found. `""` when there is none.

<sub>[stdlib/Drawing.sl:1201](../../stdlib/Drawing.sl#L1201)</sub>

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

<sub>[stdlib/Drawing.sl:82](../../stdlib/Drawing.sl#L82)</sub>

#### R *field*

```
byte R
```

*No documentation.*

<sub>[stdlib/Drawing.sl:84](../../stdlib/Drawing.sl#L84)</sub>

#### G *field*

```
byte G
```

*No documentation.*

<sub>[stdlib/Drawing.sl:85](../../stdlib/Drawing.sl#L85)</sub>

#### B *field*

```
byte B
```

*No documentation.*

<sub>[stdlib/Drawing.sl:86](../../stdlib/Drawing.sl#L86)</sub>

#### A *field*

```
byte A
```

*No documentation.*

<sub>[stdlib/Drawing.sl:87](../../stdlib/Drawing.sl#L87)</sub>

#### Rgb *method*

```
static Rgba Rgb(byte red, byte green, byte blue)
```

An opaque colour.

<sub>[stdlib/Drawing.sl:90](../../stdlib/Drawing.sl#L90)</sub>

#### Argb *method*

```
static Rgba Argb(byte alpha, byte red, byte green, byte blue)
```

A colour with an alpha, where 0 is invisible and 255 is opaque.

<sub>[stdlib/Drawing.sl:101](../../stdlib/Drawing.sl#L101)</sub>

#### FromPacked *method*

```
static Rgba FromPacked(uint packed)
```

From `0xAARRGGBB`, which is what `Packed` answers and what a colour
written as a hex literal in a program usually is.

<sub>[stdlib/Drawing.sl:113](../../stdlib/Drawing.sl#L113)</sub>

#### Packed *property*

```
uint Packed { get; }
```

`0xAARRGGBB`.

<sub>[stdlib/Drawing.sl:120](../../stdlib/Drawing.sl#L120)</sub>

#### IsInvisible *property*

```
bool IsInvisible { get; }
```

Whether anything of this would be drawn at all.

<sub>[stdlib/Drawing.sl:124](../../stdlib/Drawing.sl#L124)</sub>

#### Equals *method*

```
bool Equals(Rgba other)
```

*No documentation.*

<sub>[stdlib/Drawing.sl:126](../../stdlib/Drawing.sl#L126)</sub>

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

<sub>[stdlib/Drawing.sl:134](../../stdlib/Drawing.sl#L134)</sub>

#### Black *property*

```
static Rgba Black { get; }
```

*No documentation.*

<sub>[stdlib/Drawing.sl:135](../../stdlib/Drawing.sl#L135)</sub>

#### White *property*

```
static Rgba White { get; }
```

*No documentation.*

<sub>[stdlib/Drawing.sl:136](../../stdlib/Drawing.sl#L136)</sub>

#### Red *property*

```
static Rgba Red { get; }
```

*No documentation.*

<sub>[stdlib/Drawing.sl:137](../../stdlib/Drawing.sl#L137)</sub>

#### Green *property*

```
static Rgba Green { get; }
```

*No documentation.*

<sub>[stdlib/Drawing.sl:138](../../stdlib/Drawing.sl#L138)</sub>

#### Blue *property*

```
static Rgba Blue { get; }
```

*No documentation.*

<sub>[stdlib/Drawing.sl:139](../../stdlib/Drawing.sl#L139)</sub>

