// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

/// Raster images: reading them, drawing on them, and writing them back.
///
/// ```csharp
/// var loaded = Image.FromFile("logo.png");
/// if (!loaded.Ok) { return; }
///
/// var logo = loaded.Value;
/// logo.FillRectangle(Rgba.Rgb(200, 30, 30), 8, 8, 64, 24);
/// logo.DrawLine(Rgba.Black, 0, 0, logo.Width, logo.Height, 2);
/// logo.Save("out.png", ImageFormat.Png);
/// ```
///
/// **GDI+ on Windows, libgd everywhere else, and neither is linked.** Both are
/// loaded by name the first time an image is made. That is what lets this live
/// in the standard library at all: a `#pragma comment(lib, "gdiplus")` would
/// put an import in every Stainless binary on Windows including the ones that
/// never make an image, and `-lgd` needs libgd's *development* package where
/// what a machine actually has is the runtime one. So a program that makes no
/// image pays nothing, and a machine with no imaging library answers
/// `ImageError.NoBackend` -- a value to print, rather than a link error.
///
/// **There is no text.** Drawing a string needs a font, and the two backends
/// disagree about everything to do with one: GDI+ takes a family name and a
/// device context, libgd wants FreeType and a path to a `.ttf`. That is a
/// module of its own and saying so is better than half of it.
///
/// **Not a canvas for a window.** `Forms.Drawing` is what draws on screen and
/// is the widget set's business. This is a picture in memory: it is what reads
/// the PNG that a `Forms.Bitmap` could not, and what a program with no user
/// interface at all uses to make a chart or a thumbnail.
module Standard.Drawing;

import Standard.Collections;
import Standard.Text;
import Standard.File;
import Standard.IO;
#if WINDOWS
// For `Guid`, which names a GDI+ encoder, and for the `com interface` the
// stream is.
import Standard.Com;
#endif

extern "C"
{
    void* memcpy(void* destination, void* source, nuint count);
}

// ============================================================== the colour

/// A colour, as the eight-bit channels an image actually stores.
///
/// **Named for the layout rather than called `Color`**, and deliberately:
/// `Forms.Drawing` already declares a `Color`, and a program that loaded a PNG
/// to put it on a form would have to qualify every mention of either. `Rgba`
/// also says the one thing a caller has to know, which is that the alpha is
/// eight bits and 255 is opaque.
///
/// Packed as `0xAARRGGBB`, which is what GDI+ calls an ARGB and what the
/// libgd backend converts to and from -- libgd's alpha is seven bits and
/// inverted, and that is the only place it shows.
public struct Rgba
{
    public byte R;
    public byte G;
    public byte B;
    public byte A;

    /// An opaque colour.
    public static Rgba Rgb(byte red, byte green, byte blue)
    {
        Rgba colour;
        colour.R = red;
        colour.G = green;
        colour.B = blue;
        colour.A = (byte)255;
        return colour;
    }

    /// A colour with an alpha, where 0 is invisible and 255 is opaque.
    public static Rgba Argb(byte alpha, byte red, byte green, byte blue)
    {
        Rgba colour;
        colour.R = red;
        colour.G = green;
        colour.B = blue;
        colour.A = alpha;
        return colour;
    }

    /// From `0xAARRGGBB`, which is what `Packed` answers and what a colour
    /// written as a hex literal in a program usually is.
    public static Rgba FromPacked(uint packed)
    {
        return Rgba.Argb((byte)((packed >> 24) & 0xFFu), (byte)((packed >> 16) & 0xFFu),
                         (byte)((packed >> 8) & 0xFFu), (byte)(packed & 0xFFu));
    }

    /// `0xAARRGGBB`.
    public uint Packed =>
        ((uint)A << 24) | ((uint)R << 16) | ((uint)G << 8) | (uint)B;

    /// Whether anything of this would be drawn at all.
    public bool IsInvisible => A == (byte)0;

    public bool Equals(Rgba other) => Packed == other.Packed;

    /// **Properties rather than `static readonly` fields**, which is not a
    /// style choice. A static needs an entry point to be initialized from and a
    /// `--shared` library has none (SL0380) -- and this module is compiled into
    /// every program, including every shared library anybody builds. A property
    /// is a function, so there is nothing to initialize and nothing to go
    /// wrong; the six of them fold to four bytes each.
    public static Rgba Transparent => Rgba.Argb((byte)0, (byte)0, (byte)0, (byte)0);
    public static Rgba Black       => Rgba.Rgb((byte)0, (byte)0, (byte)0);
    public static Rgba White       => Rgba.Rgb((byte)255, (byte)255, (byte)255);
    public static Rgba Red         => Rgba.Rgb((byte)255, (byte)0, (byte)0);
    public static Rgba Green       => Rgba.Rgb((byte)0, (byte)128, (byte)0);
    public static Rgba Blue        => Rgba.Rgb((byte)0, (byte)0, (byte)255);
}

/// The formats both backends read and write.
///
/// Four, because four is what GDI+ and libgd agree about. A file is recognised
/// by its first bytes rather than by its name, so a picture that arrived over a
/// socket is read the same way as one on disk.
public enum ImageFormat { Png, Jpeg, Bmp, Gif }

/// What went wrong.
public enum ImageError
{
    None = 0,

    /// There is no imaging library on this machine. On Windows that means
    /// `gdiplus.dll` would not load, which should not happen; on Linux it means
    /// libgd is not installed, which is ordinary and is why this is a value
    /// rather than a failure.
    NoBackend = 1,

    /// No such file, or a directory along the path is missing.
    NotFound = 2,

    /// It is there and the decoder would not have it.
    Unreadable = 3,

    /// The format is not one of the four, or is one this build of libgd was
    /// compiled without.
    Unsupported = 4,

    /// The encode worked and the write did not.
    WriteFailed = 5,

    /// The allocation failed, which for an image means a size nothing could
    /// hold rather than a machine out of memory.
    OutOfMemory = 6,

    /// A size that is not positive, or a call on an image that is already
    /// closed.
    Invalid = 7,
}

// ======================================================= the Windows backend

#if WINDOWS

/// GDI+'s flat API, declared rather than included.
///
/// Every one is `__stdcall`, which is the same as the default on x64 and is
/// not on x86 -- a `__stdcall` callee removes the arguments, so a 32-bit call
/// through a plain delegate would return to a stack several words adrift. That
/// is the whole reason a delegate may name a convention (§2.14).
///
/// The names are GDI+'s own. A `GpBitmap*`, a `GpGraphics*`, a `GpPen*` and a
/// `GpBrush*` are all `void*` here because nothing in this module reads one.
delegate __stdcall int GdiplusStartupFn(nuint* token, void* input, void* output);
delegate __stdcall int GdipCreateBitmapFromStreamFn(void* stream, void** bitmap);
delegate __stdcall int GdipCreateBitmapFromScan0Fn(int width, int height, int stride,
                                                   int format, byte* scan0, void** bitmap);
delegate __stdcall int GdipDisposeImageFn(void* image);
delegate __stdcall int GdipGetImageWidthFn(void* image, uint* width);
delegate __stdcall int GdipGetImageHeightFn(void* image, uint* height);
delegate __stdcall int GdipBitmapGetPixelFn(void* bitmap, int x, int y, uint* colour);
delegate __stdcall int GdipBitmapSetPixelFn(void* bitmap, int x, int y, uint colour);
delegate __stdcall int GdipGetImageGraphicsContextFn(void* image, void** graphics);
delegate __stdcall int GdipDeleteGraphicsFn(void* graphics);
delegate __stdcall int GdipSetSmoothingModeFn(void* graphics, int mode);
delegate __stdcall int GdipGraphicsClearFn(void* graphics, uint colour);
delegate __stdcall int GdipCreatePen1Fn(uint colour, float width, int unit, void** pen);
delegate __stdcall int GdipDeletePenFn(void* pen);
delegate __stdcall int GdipCreateSolidFillFn(uint colour, void** brush);
delegate __stdcall int GdipDeleteBrushFn(void* brush);
delegate __stdcall int GdipDrawLineIFn(void* graphics, void* pen, int x1, int y1, int x2, int y2);
delegate __stdcall int GdipRectangleIFn(void* graphics, void* tool, int x, int y, int w, int h);
delegate __stdcall int GdipDrawPolygonIFn(void* graphics, void* pen, int* points, int count);
delegate __stdcall int GdipFillPolygonIFn(void* graphics, void* brush, int* points,
                                          int count, int fillMode);
delegate __stdcall int GdipDrawImageRectRectIFn(void* graphics, void* image,
                                                int dx, int dy, int dw, int dh,
                                                int sx, int sy, int sw, int sh,
                                                int unit, void* attributes,
                                                void* callback, void* callbackData);
delegate __stdcall int GdipSaveImageToStreamFn(void* image, void* stream,
                                               Guid* encoder, void* parameters);
delegate __stdcall int GdipBitmapLockBitsFn(void* bitmap, GpRect* area, uint mode,
                                            int format, BitmapData* locked);
delegate __stdcall int GdipBitmapUnlockBitsFn(void* bitmap, BitmapData* locked);

/// The rectangle GDI+ locks, which is `GpRect` and not Windows' own `RECT`:
/// this one is a width and a height where a `RECT` is a second corner.
struct GpRect
{
    int X;
    int Y;
    int Width;
    int Height;
}

/// What `GdipBitmapLockBits` fills in. `Stride` is signed because a bitmap may
/// be stored bottom-up, in which case it is negative and `Scan0` points at the
/// last row -- which is why the copy below walks rows rather than taking the
/// whole block at once.
struct BitmapData
{
    uint Width;
    uint Height;
    int Stride;
    int Format;
    void* Scan0;
    nuint Reserved;
}

delegate __stdcall int CreateStreamOnHGlobalFn(void* memory, int deleteOnRelease,
                                               void** stream);
delegate __stdcall int GetHGlobalFromStreamFn(void* stream, void** memory);

/// **`__stdcall` on the block, not just on the delegates.** Every Win32 entry
/// point is `__stdcall`, which on x86 decorates the symbol as well as deciding
/// who removes the arguments -- `_LoadLibraryA@4`, not `_LoadLibraryA`. This
/// module is compiled into every program on every target, so getting it wrong
/// did not break imaging: it broke the *link* of every 32-bit program in the
/// suite, none of which had heard of this module.
extern "C" __stdcall
{
    void* LoadLibraryA(byte* name);
    void* GetProcAddress(void* library, byte* name);

    void*  GlobalAlloc(uint flags, nuint size);
    void*  GlobalLock(void* memory);
    int    GlobalUnlock(void* memory);
    nuint  GlobalSize(void* memory);
    void*  GlobalFree(void* memory);
}


/// `PixelFormat32bppARGB`: 32 bits per pixel, with alpha, the tenth format
/// GDI+ defines. Spelled out because the header that names it is C++.
const int PixelFormat32bppArgb = 0x0026200A;
/// `SmoothingModeAntiAlias`.
const int SmoothingAntiAlias = 4;
/// `FillModeAlternate`, the even-odd rule, which is also what libgd's polygon
/// fill does.
const int FillAlternate = 0;
/// `UnitPixel`, for a pen width and for a source rectangle.
const int UnitPixel = 2;
/// `GMEM_MOVEABLE`, which is what a stream over an `HGLOBAL` requires.
const uint GlobalMoveable = 0x0002u;
/// `ImageLockModeRead`. Nothing here locks for writing.
const uint LockModeRead = 0x0001u;

/// GDI+, resolved once.
///
/// One object rather than thirty statics: the module holds a single reference
/// to it, so there is one thing to be null before the library is loaded and one
/// thing to test afterwards.
threadsafe sealed class Backend
{
    GdiplusStartupFn _startup;
    GdipCreateBitmapFromStreamFn _fromStream;
    GdipCreateBitmapFromScan0Fn _fromScan0;
    GdipDisposeImageFn _dispose;
    GdipGetImageWidthFn _imageWidth;
    GdipGetImageHeightFn _imageHeight;
    GdipBitmapGetPixelFn _getPixel;
    GdipBitmapSetPixelFn _setPixel;
    GdipGetImageGraphicsContextFn _context;
    GdipDeleteGraphicsFn _deleteGraphics;
    GdipSetSmoothingModeFn _smoothing;
    GdipGraphicsClearFn _clear;
    GdipCreatePen1Fn _makePen;
    GdipDeletePenFn _dropPen;
    GdipCreateSolidFillFn _makeBrush;
    GdipDeleteBrushFn _dropBrush;
    GdipDrawLineIFn _drawLine;
    GdipRectangleIFn _drawRectangle;
    GdipRectangleIFn _fillRectangle;
    GdipRectangleIFn _drawEllipse;
    GdipRectangleIFn _fillEllipse;
    GdipDrawPolygonIFn _drawPolygon;
    GdipFillPolygonIFn _fillPolygon;
    GdipDrawImageRectRectIFn _blit;
    GdipSaveImageToStreamFn _toStream;
    GdipBitmapLockBitsFn _lock;
    GdipBitmapUnlockBitsFn _unlock;
    CreateStreamOnHGlobalFn _makeStream;
    GetHGlobalFromStreamFn _memoryOf;

    /// Whether every symbol resolved and GDI+ started.
    public bool Ready;

    public Backend()
    {
        Ready = false;

        void* gdiplus = LoadLibraryA("gdiplus.dll".ToPointer());
        void* ole = LoadLibraryA("ole32.dll".ToPointer());
        if (gdiplus == null || ole == null)
            return;

        bool complete = true;

        _startup = (GdiplusStartupFn)Find(gdiplus, "GdiplusStartup", &complete);
        _fromStream = (GdipCreateBitmapFromStreamFn)Find(gdiplus, "GdipCreateBitmapFromStream", &complete);
        _fromScan0 = (GdipCreateBitmapFromScan0Fn)Find(gdiplus, "GdipCreateBitmapFromScan0", &complete);
        _dispose = (GdipDisposeImageFn)Find(gdiplus, "GdipDisposeImage", &complete);
        _imageWidth = (GdipGetImageWidthFn)Find(gdiplus, "GdipGetImageWidth", &complete);
        _imageHeight = (GdipGetImageHeightFn)Find(gdiplus, "GdipGetImageHeight", &complete);
        _getPixel = (GdipBitmapGetPixelFn)Find(gdiplus, "GdipBitmapGetPixel", &complete);
        _setPixel = (GdipBitmapSetPixelFn)Find(gdiplus, "GdipBitmapSetPixel", &complete);
        _context = (GdipGetImageGraphicsContextFn)Find(gdiplus, "GdipGetImageGraphicsContext", &complete);
        _deleteGraphics = (GdipDeleteGraphicsFn)Find(gdiplus, "GdipDeleteGraphics", &complete);
        _smoothing = (GdipSetSmoothingModeFn)Find(gdiplus, "GdipSetSmoothingMode", &complete);
        _clear = (GdipGraphicsClearFn)Find(gdiplus, "GdipGraphicsClear", &complete);
        _makePen = (GdipCreatePen1Fn)Find(gdiplus, "GdipCreatePen1", &complete);
        _dropPen = (GdipDeletePenFn)Find(gdiplus, "GdipDeletePen", &complete);
        _makeBrush = (GdipCreateSolidFillFn)Find(gdiplus, "GdipCreateSolidFill", &complete);
        _dropBrush = (GdipDeleteBrushFn)Find(gdiplus, "GdipDeleteBrush", &complete);
        _drawLine = (GdipDrawLineIFn)Find(gdiplus, "GdipDrawLineI", &complete);
        _drawRectangle = (GdipRectangleIFn)Find(gdiplus, "GdipDrawRectangleI", &complete);
        _fillRectangle = (GdipRectangleIFn)Find(gdiplus, "GdipFillRectangleI", &complete);
        _drawEllipse = (GdipRectangleIFn)Find(gdiplus, "GdipDrawEllipseI", &complete);
        _fillEllipse = (GdipRectangleIFn)Find(gdiplus, "GdipFillEllipseI", &complete);
        _drawPolygon = (GdipDrawPolygonIFn)Find(gdiplus, "GdipDrawPolygonI", &complete);
        _fillPolygon = (GdipFillPolygonIFn)Find(gdiplus, "GdipFillPolygonI", &complete);
        _blit = (GdipDrawImageRectRectIFn)Find(gdiplus, "GdipDrawImageRectRectI", &complete);
        _toStream = (GdipSaveImageToStreamFn)Find(gdiplus, "GdipSaveImageToStream", &complete);
        _lock = (GdipBitmapLockBitsFn)Find(gdiplus, "GdipBitmapLockBits", &complete);
        _unlock = (GdipBitmapUnlockBitsFn)Find(gdiplus, "GdipBitmapUnlockBits", &complete);
        _makeStream = (CreateStreamOnHGlobalFn)Find(ole, "CreateStreamOnHGlobal", &complete);
        _memoryOf = (GetHGlobalFromStreamFn)Find(ole, "GetHGlobalFromStream", &complete);

        if (!complete)
            return;

        // `GdiplusStartupInput` is a version, two pointers' worth of options and
        // nothing this module sets. Four words of zero with the version at the
        // front says "version 1, no background thread suppression", which is
        // what every caller wants.
        nuint[] input = new nuint[4u];
        input[0u] = 1u;
        nuint token = 0u;
        if (_startup(&token, (void*)&input[0u], null) != 0)
            return;

        Ready = true;
    }

    /// One symbol, and a running record of whether every one so far was there.
    ///
    /// The flag is passed rather than returned because a missing symbol means
    /// the whole backend is unusable, and twenty-seven separate tests at the
    /// call site would say the same thing twenty-seven times.
    void* Find(void* library, String name, bool* complete)
    {
        void* symbol = GetProcAddress(library, name.ToPointer());
        if (symbol == null)
            *complete = false;
        return symbol;
    }

    // ------------------------------------------------------------- lifetime

    public void* Create(int width, int height)
    {
        void* bitmap = null;
        if (_fromScan0(width, height, 0, PixelFormat32bppArgb, null, &bitmap) != 0)
        {
            return null;
        }
        return bitmap;
    }

    public void* Decode(byte[] data)
    {
        var stream = StreamOver(data);
        if (stream == null)
            return null;

        void* bitmap = null;
        // Released when `stream` goes, which is the end of this function. GDI+
        // keeps a reference of its own to a stream it decoded from, so letting
        // go of this one does not take the pixels with it.
        if (_fromStream((void*)(IUnknown)stream, &bitmap) != 0)
            return null;
        return bitmap;
    }

    public void Destroy(void* image) => _dispose(image);

    public int Width(void* image)
    {
        uint value = 0u;
        _imageWidth(image, &value);
        return (int)value;
    }

    public int Height(void* image)
    {
        uint value = 0u;
        _imageHeight(image, &value);
        return (int)value;
    }

    // --------------------------------------------------------------- pixels

    public uint GetPixel(void* image, int x, int y)
    {
        uint colour = 0u;
        _getPixel(image, x, y, &colour);
        return colour;
    }

    public void SetPixel(void* image, int x, int y, uint colour)
    {
        _setPixel(image, x, y, colour);
    }

    /// Every pixel at once, as four bytes each in the order blue, green, red,
    /// alpha.
    ///
    /// GDI+ stores exactly that -- `PixelFormat32bppARGB` is a little-endian
    /// `0xAARRGGBB`, whose bytes in memory are B, G, R, A -- so a locked row is
    /// copied rather than converted. Row by row rather than in one block,
    /// because `Stride` is signed: a bottom-up bitmap reports a negative one
    /// and points `Scan0` at the last row.
    public bool CopyPixels(void* image, int width, int height, byte* into)
    {
        GpRect area;
        area.X = 0;
        area.Y = 0;
        area.Width = width;
        area.Height = height;

        BitmapData locked;
        if (_lock(image, &area, LockModeRead, PixelFormat32bppArgb, &locked) != 0)
            return false;

        nuint row = (nuint)width * 4u;
        for (int y = 0; y < height; y++)
        {
            byte* source = (byte*)locked.Scan0 + (nint)y * (nint)locked.Stride;
            memcpy((void*)(into + (nuint)y * row), (void*)source, row);
        }

        _unlock(image, &locked);
        return true;
    }

    // -------------------------------------------------------------- drawing

    /// A graphics context over an image, made for one call and thrown away.
    ///
    /// GDI+ would rather one were kept, and keeping one would mean a field that
    /// has to be disposed before the bitmap it belongs to. A context is cheap
    /// and every call that makes one then does real rasterising.
    void* Context(void* image)
    {
        void* graphics = null;
        if (_context(image, &graphics) != 0)
            return null;
        _smoothing(graphics, SmoothingAntiAlias);
        return graphics;
    }

    public void Clear(void* image, uint colour)
    {
        void* graphics = Context(image);
        if (graphics == null)
            return;
        _clear(graphics, colour);
        _deleteGraphics(graphics);
    }

    public void Line(void* image, int x1, int y1, int x2, int y2, uint colour, int thickness)
    {
        void* graphics = Context(image);
        if (graphics == null)
            return;

        void* pen = null;
        if (_makePen(colour, (float)thickness, UnitPixel, &pen) == 0)
        {
            _drawLine(graphics, pen, x1, y1, x2, y2);
            _dropPen(pen);
        }
        _deleteGraphics(graphics);
    }

    /// A rectangle or an ellipse, outlined or filled, which is four calls that
    /// differ only in which GDI+ function they reach.
    public void Shape(void* image, bool ellipse, int x, int y, int width, int height,
                      uint colour, int thickness, bool filled)
    {
        void* graphics = Context(image);
        if (graphics == null)
            return;

        if (filled)
        {
            void* brush = null;
            if (_makeBrush(colour, &brush) == 0)
            {
                if (ellipse)
                {
                    _fillEllipse(graphics, brush, x, y, width, height);
                }
                else
                {
                    _fillRectangle(graphics, brush, x, y, width, height);
                }
                _dropBrush(brush);
            }
        }
        else
        {
            void* pen = null;
            if (_makePen(colour, (float)thickness, UnitPixel, &pen) == 0)
            {
                // A one-pixel pen straddles the edge, so the far row and column
                // of a width-by-height rectangle fall outside it. Both backends
                // want the far edge given as the last pixel.
                if (ellipse)
                {
                    _drawEllipse(graphics, pen, x, y, width - 1, height - 1);
                }
                else
                {
                    _drawRectangle(graphics, pen, x, y, width - 1, height - 1);
                }
                _dropPen(pen);
            }
        }

        _deleteGraphics(graphics);
    }

    public void Polygon(void* image, int[] points, uint colour, int thickness, bool filled)
    {
        void* graphics = Context(image);
        if (graphics == null)
            return;

        int count = (int)(points.Length / 2u);
        if (filled)
        {
            void* brush = null;
            if (_makeBrush(colour, &brush) == 0)
            {
                _fillPolygon(graphics, brush, &points[0u], count, FillAlternate);
                _dropBrush(brush);
            }
        }
        else
        {
            void* pen = null;
            if (_makePen(colour, (float)thickness, UnitPixel, &pen) == 0)
            {
                _drawPolygon(graphics, pen, &points[0u], count);
                _dropPen(pen);
            }
        }

        _deleteGraphics(graphics);
    }

    public void Blit(void* destination, void* source,
                     int dx, int dy, int dw, int dh, int sx, int sy, int sw, int sh)
    {
        void* graphics = Context(destination);
        if (graphics == null)
            return;
        _blit(graphics, source, dx, dy, dw, dh, sx, sy, sw, sh, UnitPixel, null, null, null);
        _deleteGraphics(graphics);
    }

    // -------------------------------------------------------------- codecs

    /// The encoder CLSIDs, written out.
    ///
    /// `GdipGetImageEncoders` answers them at run time, which means a
    /// variable-sized array of `ImageCodecInfo` and a match on a MIME string.
    /// These four have been the same since GDI+ shipped and are documented as
    /// constants; the lookup buys nothing but a failure mode.
    Guid EncoderFor(ImageFormat format)
    {
        // The four differ only in the last byte of the first field, which is
        // why they are built rather than written out four times.
        uint first = 0x557CF406u;                       // PNG
        if (format == ImageFormat.Jpeg)
            first = 0x557CF401u;
        if (format == ImageFormat.Bmp)
            first = 0x557CF400u;
        if (format == ImageFormat.Gif)
            first = 0x557CF402u;

        Guid id;
        id.Data1 = first;
        id.Data2 = (ushort)0x1A04;
        id.Data3 = (ushort)0x11D3;
        id.Data4[0u] = (byte)0x9A;
        id.Data4[1u] = (byte)0x73;
        id.Data4[2u] = (byte)0x00;
        id.Data4[3u] = (byte)0x00;
        id.Data4[4u] = (byte)0xF8;
        id.Data4[5u] = (byte)0x1E;
        id.Data4[6u] = (byte)0xF3;
        id.Data4[7u] = (byte)0x2E;
        return id;
    }

    /// An empty stream, for one about to be written into.
    ///
    /// **`IUnknown` and not a declared `IStream`.** Nothing here calls a stream
    /// method: GDI+ takes the pointer and does the reading itself, so all this
    /// reference is for is the count -- `CreateStreamOnHGlobal` writes a
    /// pointer at one through a `void**`, the cast adopts that count rather
    /// than adding to it (`ConversionKind.ComAdopt`, §8.5), and the release
    /// happens when the reference goes. A `com interface IStream` with no
    /// members is `IUnknown` under another name and the compiler says so
    /// (SL0534); declaring the eleven slots this module never calls would be
    /// inventing a binding to document a shape.
    ///
    /// The `1` is `fDeleteOnRelease`: the memory goes when the stream does,
    /// which is what makes this one thing to keep track of rather than two.
    IUnknown? EmptyStream()
    {
        void* stream = null;
        if (_makeStream(null, 1, &stream) != 0)
            return null;
        return (IUnknown)stream;
    }

    /// A stream over a copy of a buffer.
    IUnknown? StreamOver(byte[] data)
    {
        nuint size = data.Length;
        void* block = GlobalAlloc(GlobalMoveable, size);
        if (block == null)
            return null;

        void* inside = GlobalLock(block);
        if (inside == null)
        {
            GlobalFree(block);
            return null;
        }
        memcpy(inside, (void*)&data[0u], size);
        GlobalUnlock(block);

        void* stream = null;
        if (_makeStream(block, 1, &stream) != 0)
        {
            GlobalFree(block);
            return null;
        }
        return (IUnknown)stream;
    }

    /// The encoded bytes, or an empty array for a failure.
    ///
    /// **Empty rather than null**, because an array is a value in this
    /// language and never null (SL0271). A zero-length encode is not a thing
    /// either backend produces, so the two cannot be confused.
    public byte[] Encode(void* image, ImageFormat format, int quality)
    {
        var nothing = new byte[0u];

        var stream = EmptyStream();
        if (stream == null)
            return nothing;
        void* raw = (void*)(IUnknown)stream;

        var encoder = EncoderFor(format);
        // No encoder parameters, so no quality for a JPEG: GDI+ writes one at
        // its own default of 75. Saying so is better than an `EncoderParameters`
        // this would have to lay out by hand for the one format that reads it,
        // and 75 is the number libgd uses too.
        if (_toStream(image, raw, &encoder, null) != 0)
            return nothing;

        void* block = null;
        if (_memoryOf(raw, &block) != 0 || block == null)
            return nothing;

        nuint size = GlobalSize(block);
        if (size == 0u)
            return nothing;

        void* inside = GlobalLock(block);
        if (inside == null)
            return nothing;

        // **Copied before the stream goes**, because the stream was made with
        // `fDeleteOnRelease` and the memory is freed with it. `stream` is a
        // local, so ARC releases it when this function returns -- after this.
        var data = new byte[size];
        memcpy((void*)&data[0u], inside, size);
        GlobalUnlock(block);
        return data;
    }
}

#else

// ========================================================== the Unix backend

/// libgd, resolved by name.
///
/// `gd.h` is usually not installed -- what a machine has is `libgd.so.3`, the
/// runtime package -- so these are declared from libgd's documented signatures.
/// A `gdImagePtr` is a `void*` because nothing here reads the structure.
///
/// No convention: every one is the platform's own, which is what libgd is
/// compiled with and what a delegate is by default.
delegate void* GdImageCreateTrueColorFn(int width, int height);
delegate void  GdImageDestroyFn(void* image);
delegate void* GdImageCreateFromPtrFn(int size, void* data);
delegate void* GdImageToPtrFn(void* image, int* size);
delegate void* GdImageToPtrQualityFn(void* image, int* size, int quality);
delegate void  GdFreeFn(void* data);
delegate void  GdImageGetClipFn(void* image, int* left, int* top, int* right, int* bottom);
delegate void  GdImageSetPixelFn(void* image, int x, int y, int colour);
delegate int   GdImageGetPixelFn(void* image, int x, int y);
delegate void  GdImageLineFn(void* image, int x1, int y1, int x2, int y2, int colour);
delegate void  GdImageRectFn(void* image, int x1, int y1, int x2, int y2, int colour);
delegate void  GdImageEllipseFn(void* image, int cx, int cy, int w, int h, int colour);
delegate void  GdImagePolygonFn(void* image, int* points, int count, int colour);
delegate void  GdImageSetThicknessFn(void* image, int thickness);
delegate void  GdImageFlagFn(void* image, int on);
delegate void  GdImageCopyResampledFn(void* destination, void* source,
                                      int dx, int dy, int sx, int sy,
                                      int dw, int dh, int sw, int sh);

extern "C"
{
    void* dlopen(byte* name, int flags);
    void* dlsym(void* library, byte* name);
}

/// `RTLD_LAZY | RTLD_LOCAL`: resolve as called, and do not put libgd's symbols
/// in the global namespace where they could satisfy somebody else's undefined
/// reference.
const int RtldLazyLocal = 0x00001;

/// libgd, resolved once.
threadsafe sealed class Backend
{
    GdImageCreateTrueColorFn _createTrueColor;
    GdImageDestroyFn _destroy;
    GdImageCreateFromPtrFn _fromPng;
    GdImageCreateFromPtrFn _fromJpeg;
    GdImageCreateFromPtrFn _fromGif;
    GdImageCreateFromPtrFn _fromBmp;
    GdImageToPtrFn _toPng;
    GdImageToPtrQualityFn _toJpeg;
    GdImageToPtrFn _toGif;
    GdImageToPtrQualityFn _toBmp;
    GdFreeFn _release;
    GdImageGetClipFn _getClip;
    GdImageSetPixelFn _setPixel;
    GdImageGetPixelFn _getPixel;
    GdImageLineFn _line;
    GdImageRectFn _rectangle;
    GdImageRectFn _fillRectangle;
    GdImageEllipseFn _ellipse;
    GdImageEllipseFn _fillEllipse;
    GdImagePolygonFn _polygon;
    GdImagePolygonFn _fillPolygon;
    GdImageSetThicknessFn _thickness;
    GdImageFlagFn _blending;
    GdImageFlagFn _saveAlpha;
    GdImageCopyResampledFn _resample;

    public bool Ready;

    public Backend()
    {
        Ready = false;

        // The versioned runtime library first, which is what a machine with the
        // package installed has; then the development symlink; then the older
        // soname, and the macOS spellings of both.
        void* library = Open("libgd.so.3");
        if (library == null)
            library = Open("libgd.so");
        if (library == null)
            library = Open("libgd.so.2");
        if (library == null)
            library = Open("libgd.3.dylib");
        if (library == null)
            library = Open("libgd.dylib");
        if (library == null)
            return;

        bool complete = true;

        _createTrueColor = (GdImageCreateTrueColorFn)Find(library, "gdImageCreateTrueColor", &complete);
        _destroy = (GdImageDestroyFn)Find(library, "gdImageDestroy", &complete);
        _fromPng = (GdImageCreateFromPtrFn)Find(library, "gdImageCreateFromPngPtr", &complete);
        _fromJpeg = (GdImageCreateFromPtrFn)Find(library, "gdImageCreateFromJpegPtr", &complete);
        _fromGif = (GdImageCreateFromPtrFn)Find(library, "gdImageCreateFromGifPtr", &complete);
        _toPng = (GdImageToPtrFn)Find(library, "gdImagePngPtr", &complete);
        _toJpeg = (GdImageToPtrQualityFn)Find(library, "gdImageJpegPtr", &complete);
        _toGif = (GdImageToPtrFn)Find(library, "gdImageGifPtr", &complete);
        _release = (GdFreeFn)Find(library, "gdFree", &complete);
        _getClip = (GdImageGetClipFn)Find(library, "gdImageGetClip", &complete);
        _setPixel = (GdImageSetPixelFn)Find(library, "gdImageSetPixel", &complete);
        _getPixel = (GdImageGetPixelFn)Find(library, "gdImageGetPixel", &complete);
        _line = (GdImageLineFn)Find(library, "gdImageLine", &complete);
        _rectangle = (GdImageRectFn)Find(library, "gdImageRectangle", &complete);
        _fillRectangle = (GdImageRectFn)Find(library, "gdImageFilledRectangle", &complete);
        _ellipse = (GdImageEllipseFn)Find(library, "gdImageEllipse", &complete);
        _fillEllipse = (GdImageEllipseFn)Find(library, "gdImageFilledEllipse", &complete);
        _polygon = (GdImagePolygonFn)Find(library, "gdImagePolygon", &complete);
        _fillPolygon = (GdImagePolygonFn)Find(library, "gdImageFilledPolygon", &complete);
        _thickness = (GdImageSetThicknessFn)Find(library, "gdImageSetThickness", &complete);
        _blending = (GdImageFlagFn)Find(library, "gdImageAlphaBlending", &complete);
        _saveAlpha = (GdImageFlagFn)Find(library, "gdImageSaveAlpha", &complete);
        _resample = (GdImageCopyResampledFn)Find(library, "gdImageCopyResampled", &complete);

        // BMP arrived in libgd 2.1.1 and a distribution may predate it, so
        // these two are allowed to be missing and the format is refused when
        // they are.
        void* bmpIn = dlsym(library, "gdImageCreateFromBmpPtr".ToPointer());
        void* bmpOut = dlsym(library, "gdImageBmpPtr".ToPointer());
        if (bmpIn != null)
            _fromBmp = (GdImageCreateFromPtrFn)bmpIn;
        if (bmpOut != null)
            _toBmp = (GdImageToPtrQualityFn)bmpOut;

        Ready = complete;
    }

    void* Open(String name) => dlopen(name.ToPointer(), RtldLazyLocal);

    void* Find(void* library, String name, bool* complete)
    {
        void* symbol = dlsym(library, name.ToPointer());
        if (symbol == null)
            *complete = false;
        return symbol;
    }

    /// libgd's alpha is seven bits and inverted: 0 is opaque and 127 is
    /// invisible, where everything above this uses eight bits with 255 opaque.
    /// The halving is lossy one way and exact the other, which is why a round
    /// trip through an image is not quite the byte that went in.
    int ToGd(uint colour)
    {
        uint alpha = (colour >> 24) & 0xFFu;
        uint inverted = (255u - alpha) * 127u / 255u;
        return (int)((inverted << 24) | (colour & 0x00FFFFFFu));
    }

    uint FromGd(int colour)
    {
        uint packed = (uint)colour;
        uint inverted = (packed >> 24) & 0x7Fu;
        uint alpha = 255u - inverted * 255u / 127u;
        return (alpha << 24) | (packed & 0x00FFFFFFu);
    }

    // ------------------------------------------------------------- lifetime

    public void* Create(int width, int height)
    {
        void* image = _createTrueColor(width, height);
        if (image == null)
            return null;

        // A new truecolor image is opaque black, and one made to be drawn on
        // should start empty. Blending off, or the fill would compose with the
        // black rather than replace it.
        _blending(image, 0);
        _fillRectangle(image, 0, 0, width - 1, height - 1, ToGd(0u));
        _blending(image, 1);
        _saveAlpha(image, 1);
        return image;
    }

    public void* Decode(byte[] data)
    {
        int size = (int)data.Length;
        void* raw = (void*)&data[0u];
        void* image = null;

        ImageFormat format = ImageFormat.Png;
        if (!Sniff(data, &format))
            return null;

        if (format == ImageFormat.Png)
            image = _fromPng(size, raw);
        if (format == ImageFormat.Jpeg)
            image = _fromJpeg(size, raw);
        if (format == ImageFormat.Gif)
            image = _fromGif(size, raw);
        if (format == ImageFormat.Bmp && _fromBmp != null)
            image = _fromBmp(size, raw);

        if (image != null)
            _saveAlpha(image, 1);
        return image;
    }

    public void Destroy(void* image) => _destroy(image);

    /// **The size comes from the clipping rectangle and not from `gdImageSX`.**
    /// SX and SY are macros over the structure's fields, so using them would
    /// mean declaring `gdImageStruct` and depending on its layout. A fresh
    /// image's clip is the whole image, which is the same two numbers through a
    /// real function.
    public int Width(void* image)
    {
        int left = 0; int top = 0; int right = 0; int bottom = 0;
        _getClip(image, &left, &top, &right, &bottom);
        return right - left + 1;
    }

    public int Height(void* image)
    {
        int left = 0; int top = 0; int right = 0; int bottom = 0;
        _getClip(image, &left, &top, &right, &bottom);
        return bottom - top + 1;
    }

    // --------------------------------------------------------------- pixels

    public uint GetPixel(void* image, int x, int y) => FromGd(_getPixel(image, x, y));

    public void SetPixel(void* image, int x, int y, uint colour)
    {
        // Replace rather than blend: a caller writing a pixel means that pixel.
        _blending(image, 0);
        _setPixel(image, x, y, ToGd(colour));
        _blending(image, 1);
    }

    /// Every pixel at once, in the same blue, green, red, alpha order the
    /// Windows backend answers.
    ///
    /// **A call per pixel, where GDI+ locks and copies rows.** libgd's true
    /// colour rows are a `int**` inside a structure this module deliberately
    /// does not describe -- reaching into it would mean pinning libgd's layout,
    /// which is the thing `void*` here exists to avoid. `gdImageGetPixel` is a
    /// resolved function pointer and an array index, so an icon costs a
    /// thousand calls and a photograph a million; that is the price of not
    /// knowing the structure, and it is paid once when a picture is handed to
    /// a widget set rather than per frame.
    public bool CopyPixels(void* image, int width, int height, byte* into)
    {
        nuint at = 0u;
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                uint colour = FromGd(_getPixel(image, x, y));
                into[at] = (byte)(colour & 0xFFu);
                into[at + 1u] = (byte)((colour >> 8) & 0xFFu);
                into[at + 2u] = (byte)((colour >> 16) & 0xFFu);
                into[at + 3u] = (byte)((colour >> 24) & 0xFFu);
                at = at + 4u;
            }
        }
        return true;
    }

    // -------------------------------------------------------------- drawing

    public void Clear(void* image, uint colour)
    {
        _blending(image, 0);
        _fillRectangle(image, 0, 0, Width(image) - 1, Height(image) - 1, ToGd(colour));
        _blending(image, 1);
    }

    public void Line(void* image, int x1, int y1, int x2, int y2, uint colour, int width)
    {
        _thickness(image, width < 1 ? 1 : width);
        _line(image, x1, y1, x2, y2, ToGd(colour));
        _thickness(image, 1);
    }

    public void Shape(void* image, bool isEllipse, int x, int y, int width, int height,
                      uint colour, int stroke, bool filled)
    {
        int ink = ToGd(colour);

        if (filled)
        {
            if (isEllipse)
            {
                // libgd's ellipse is a centre and a size, where every other API
                // here gives the bounding box.
                _fillEllipse(image, x + width / 2, y + height / 2, width, height, ink);
            }
            else
            {
                _fillRectangle(image, x, y, x + width - 1, y + height - 1, ink);
            }
            return;
        }

        _thickness(image, stroke < 1 ? 1 : stroke);
        if (isEllipse)
        {
            _ellipse(image, x + width / 2, y + height / 2, width, height, ink);
        }
        else
        {
            _rectangle(image, x, y, x + width - 1, y + height - 1, ink);
        }
        _thickness(image, 1);
    }

    public void Polygon(void* image, int[] points, uint colour, int stroke, bool filled)
    {
        int count = (int)(points.Length / 2u);
        int ink = ToGd(colour);

        if (filled)
        {
            _fillPolygon(image, &points[0u], count, ink);
            return;
        }

        _thickness(image, stroke < 1 ? 1 : stroke);
        _polygon(image, &points[0u], count, ink);
        _thickness(image, 1);
    }

    public void Blit(void* destination, void* source,
                     int dx, int dy, int dw, int dh, int sx, int sy, int sw, int sh)
    {
        // Resampled even when the sizes match, so that the alpha composes the
        // same way it does when they do not. `gdImageCopy` would be faster and
        // would disagree with itself at two different scales.
        _resample(destination, source, dx, dy, sx, sy, dw, dh, sw, sh);
    }

    // -------------------------------------------------------------- codecs

    /// The encoded bytes, or an empty array for a failure. See the note on
    /// the Windows backend's `Encode` for why empty rather than null.
    public byte[] Encode(void* image, ImageFormat format, int quality)
    {
        int size = 0;
        void* raw = null;

        if (format == ImageFormat.Png)
            raw = _toPng(image, &size);
        if (format == ImageFormat.Jpeg)
            raw = _toJpeg(image, &size, quality < 0 ? 75 : quality);
        if (format == ImageFormat.Gif)
            raw = _toGif(image, &size);
        if (format == ImageFormat.Bmp && _toBmp != null)
            raw = _toBmp(image, &size, 0);

        if (raw == null || size <= 0)
            return new byte[0u];

        // Copied out of libgd's allocator into one the caller can hold, because
        // an array is the language's and `gdFree` is libgd's.
        var data = new byte[(nuint)size];
        memcpy((void*)&data[0u], raw, (nuint)size);
        _release(raw);
        return data;
    }
}

#endif

// =============================================================== the module

/// Which format a buffer holds, from its first bytes. False for none this
/// reads, and `found` is untouched then.
///
/// Sniffed rather than taken from the extension, because a caller that read the
/// bytes off a socket has no extension to offer -- and because a `.png` that is
/// really a JPEG is a thing that happens.
///
/// An out pointer rather than an `ImageFormat?`, because an enum is a value and
/// only a class reference may be optional (SL0271).
bool Sniff(byte[] data, ImageFormat* found)
{
    nuint size = data.Length;

    if (size >= 8u && data[0u] == (byte)0x89 && data[1u] == (byte)0x50
                   && data[2u] == (byte)0x4E && data[3u] == (byte)0x47)
    {
        *found = ImageFormat.Png;
        return true;
    }
    if (size >= 3u && data[0u] == (byte)0xFF && data[1u] == (byte)0xD8
                   && data[2u] == (byte)0xFF)
    {
        *found = ImageFormat.Jpeg;
        return true;
    }
    if (size >= 6u && data[0u] == (byte)0x47 && data[1u] == (byte)0x49
                   && data[2u] == (byte)0x46 && data[3u] == (byte)0x38)
    {
        *found = ImageFormat.Gif;
        return true;
    }
    if (size >= 2u && data[0u] == (byte)0x42 && data[1u] == (byte)0x4D)
    {
        *found = ImageFormat.Bmp;
        return true;
    }
    return false;
}

/// The imaging library, loaded once and shared.
///
/// **Public so that a program can ask before it tries.** A tool that writes a
/// chart wants to say "install libgd" at startup rather than at the end of a
/// long computation, and `Available` is how it finds out.
public static class Imaging
{
    static Backend? s_loaded = null;
    static bool s_tried = false;

    /// The backend, loading it if this is the first call, or null when there is
    /// none to load.
    ///
    /// **`Backend` is `threadsafe` because it is frozen, not because it locks.**
    /// Every field is a function pointer written in the constructor and never
    /// again, so there is no content for two threads to race over -- which is
    /// the same ground `String` is admitted on, and the assertion the word is
    /// for (§9.5). A `Backend` is safe for any number of threads to call at
    /// once; the backing libraries are, too.
    ///
    /// **What is not covered is this function's own first call.** Two threads
    /// reaching it together would each load the library and one of the two
    /// objects would be dropped, which leaks a module handle and nothing else.
    /// That is a stated limit rather than an oversight: a lock here would put
    /// `Standard.Threading` underneath a module that otherwise depends on
    /// nothing at all.
    static Backend? Current
    {
        get
        {
            if (s_tried)
                return s_loaded;
            s_tried = true;

            var made = new Backend();
            if (made.Ready)
                s_loaded = made;
            return s_loaded;
        }
    }

    /// Whether there is an imaging library on this machine.
    ///
    /// Loads it, so the first call is where the cost is and every `Image` after
    /// it is free.
    public static bool Available => Current != null;

    /// The name of the library behind it, for a program that reports what it
    /// found. `""` when there is none.
    public static String BackendName
    {
        get
        {
            if (Current == null)
                return "";
#if WINDOWS
            return "GDI+";
#else
            return "libgd";
#endif
        }
    }

    /// The one accessor `Image` uses. Not public: a `Backend` is this
    /// module's own vocabulary and nothing outside could do anything with one.
    static Backend? Use() => Current;
}

// ==================================================================== image

/// A picture in memory.
///
/// **The handle is released by the destructor**, so an image is closed when the
/// last reference to it goes and there is no `Dispose` to forget. That is worth
/// stating because the thing being released is a GDI+ or libgd object rather
/// than memory the language allocated -- ARC counts the `Image`, and the
/// `Image` owns the picture.
public sealed class Image
{
    void* _handle;
    int _wide;
    int _high;

    Image(void* made, int width, int height)
    {
        _handle = made;
        _wide = width;
        _high = height;
    }

    ~Image()
    {
        if (_handle == null)
            return;
        var backend = Imaging.Use();
        if (backend != null)
            ((Backend)backend).Destroy(_handle);
        _handle = null;
    }

    // ------------------------------------------------------------- making one

    /// An empty picture, every pixel transparent.
    public static Result<Image, ImageError> Create(int width, int height)
    {
        if (width <= 0 || height <= 0)
            return Fail(ImageError.Invalid);

        var backend = Imaging.Use();
        if (backend == null)
            return Fail(ImageError.NoBackend);

        void* made = ((Backend)backend).Create(width, height);
        if (made == null)
            return Fail(ImageError.OutOfMemory);
        return Ok(new Image(made, width, height));
    }

    /// A picture decoded from bytes, whatever of the four formats they hold.
    public static Result<Image, ImageError> FromBytes(byte[] data)
    {
        if (data.Length == 0u)
            return Fail(ImageError.Invalid);

        var backend = Imaging.Use();
        if (backend == null)
            return Fail(ImageError.NoBackend);

        ImageFormat format = ImageFormat.Png;
        if (!Sniff(data, &format))
            return Fail(ImageError.Unsupported);

        void* made = ((Backend)backend).Decode(data);
        if (made == null)
            return Fail(ImageError.Unreadable);

        var found = (Backend)backend;
        return Ok(new Image(made, found.Width(made), found.Height(made)));
    }

    /// A picture read from a file.
    ///
    /// The bytes are read here rather than handed to the decoder, so that a
    /// missing file is `NotFound` on both platforms rather than whatever each
    /// library says about one it could not open.
    public static Result<Image, ImageError> FromFile(String path)
    {
        var read = ReadAllBytes(path);
        if (!read.Ok)
        {
            return Fail(read.Error == IOError.NotFound
                        ? ImageError.NotFound : ImageError.Unreadable);
        }
        return FromBytes(read.Value);
    }

    // ------------------------------------------------------------ what it is

    public int Width => _wide;
    public int Height => _high;

    /// Whether the picture is still open. False only after a destructor has
    /// run, which a program cannot observe on an image it still holds.
    public bool IsOpen => _handle != null;

    // ---------------------------------------------------------------- pixels

    /// The colour at a point, or fully transparent for a point outside.
    ///
    /// Answering rather than failing, because the common caller is a loop over
    /// a neighbourhood and a test at every edge is what that loop would
    /// otherwise be made of.
    public Rgba GetPixel(int x, int y)
    {
        if (!Inside(x, y))
            return Rgba.Transparent;
        var backend = Imaging.Use();
        if (backend == null)
            return Rgba.Transparent;
        return Rgba.FromPacked(((Backend)backend).GetPixel(_handle, x, y));
    }

    /// Writes one pixel, replacing whatever was there rather than blending.
    public void SetPixel(int x, int y, Rgba colour)
    {
        if (!Inside(x, y))
            return;
        var backend = Imaging.Use();
        if (backend != null)
            ((Backend)backend).SetPixel(_handle, x, y, colour.Packed);
    }

    /// How many bytes one row of `CopyPixels` occupies: four per pixel, with no
    /// padding between rows.
    public nuint Stride => (nuint)_wide * 4u;

    /// How many bytes `CopyPixels` writes.
    public nuint PixelByteLength => Stride * (nuint)_high;

    /// Every pixel, as four bytes each in the order **blue, green, red,
    /// alpha**, rows top to bottom with no padding.
    ///
    /// That order rather than red-first because it is what both a Windows DIB
    /// and this module's own `Rgba.Packed` already are: `Packed` is
    /// `0xAARRGGBB`, and its bytes on every machine this compiles for are B, G,
    /// R, A. A reader wanting the other order swaps two bytes per pixel and
    /// knows it is doing so; making this the packed order would have every
    /// reader convert instead.
    ///
    /// The alpha is **straight, not premultiplied**. Premultiplying is what a
    /// particular compositor wants rather than what the picture is, so it
    /// belongs to whoever is about to composite.
    ///
    /// False when the picture is closed, when there is no backend, when `into`
    /// is shorter than `PixelByteLength`, or when the backend refused.
    public bool CopyPixels(byte[] into)
    {
        if (_handle == null || into.Length < PixelByteLength)
            return false;

        var backend = Imaging.Use();
        if (backend == null)
            return false;

        return ((Backend)backend).CopyPixels(_handle, _wide, _high, &into[0u]);
    }

    /// The same bytes in an array of the right size, or an empty one for the
    /// failures `CopyPixels` answers false for.
    ///
    /// Empty rather than null for the reason `Encode` gives: an array is a value
    /// here and is never null, and a picture with no pixels is not something
    /// either backend produces.
    public byte[] ToBgra()
    {
        var pixels = new byte[PixelByteLength];
        if (!CopyPixels(pixels))
            return new byte[0u];
        return pixels;
    }

    bool Inside(int x, int y)
    {
        return _handle != null && x >= 0 && y >= 0 && x < _wide && y < _high;
    }

    // --------------------------------------------------------------- drawing
    //
    // Every one of these is clipped by the backend, takes the colour it draws
    // with rather than reading a current one, and answers nothing. The first is
    // the reason there is no bounds checking here; the second is the rule
    // `Forms.Drawing` states at length and this one inherits.

    /// Fills the whole picture with one colour.
    public void Clear(Rgba colour)
    {
        var backend = Imaging.Use();
        if (backend != null && _handle != null)
            ((Backend)backend).Clear(_handle, colour.Packed);
    }

    public void DrawLine(Rgba colour, int x1, int y1, int x2, int y2, int thickness = 1)
    {
        var backend = Imaging.Use();
        if (backend == null || _handle == null)
            return;
        ((Backend)backend).Line(_handle, x1, y1, x2, y2, colour.Packed, thickness);
    }

    public void DrawRectangle(Rgba colour, int x, int y, int width, int height,
                              int thickness = 1)
    {
        Shape(false, colour, x, y, width, height, thickness, false);
    }

    public void FillRectangle(Rgba colour, int x, int y, int width, int height)
    {
        Shape(false, colour, x, y, width, height, 1, true);
    }

    /// An ellipse inside the rectangle given, which is how every other API here
    /// and in `Forms.Drawing` spells one -- libgd's centre-and-size form is
    /// converted by the backend.
    public void DrawEllipse(Rgba colour, int x, int y, int width, int height,
                            int thickness = 1)
    {
        Shape(true, colour, x, y, width, height, thickness, false);
    }

    public void FillEllipse(Rgba colour, int x, int y, int width, int height)
    {
        Shape(true, colour, x, y, width, height, 1, true);
    }

    void Shape(bool ellipse, Rgba colour, int x, int y, int width, int height,
               int thickness, bool filled)
    {
        if (width <= 0 || height <= 0 || _handle == null)
            return;
        var backend = Imaging.Use();
        if (backend == null)
            return;
        ((Backend)backend).Shape(_handle, ellipse, x, y, width, height,
                                 colour.Packed, thickness, filled);
    }

    /// A closed shape, from x and y in one flat array: `[x0, y0, x1, y1, ...]`.
    ///
    /// **A flat array rather than a `Point[]`**, and that is a deliberate
    /// absence. `Forms.Drawing` declares `Point`, `Size` and `Rectangle`, and a
    /// program that loaded a PNG to put it on a form would have to qualify
    /// every mention of whichever one it meant. Neither library should be the
    /// one that makes the other awkward to import, so this one declares no
    /// geometry at all.
    public void DrawPolygon(Rgba colour, int[] points, int thickness = 1)
    {
        Polygon(colour, points, thickness, false);
    }

    public void FillPolygon(Rgba colour, int[] points)
    {
        Polygon(colour, points, 1, true);
    }

    void Polygon(Rgba colour, int[] points, int thickness, bool filled)
    {
        if (points.Length < 6u || points.Length % 2u != 0u || _handle == null)
            return;
        var backend = Imaging.Use();
        if (backend == null)
            return;
        ((Backend)backend).Polygon(_handle, points, colour.Packed, thickness, filled);
    }

    /// Draws another picture on this one, at its own size.
    public void Draw(Image source, int x, int y)
    {
        DrawScaled(source, x, y, source.Width, source.Height,
                   0, 0, source.Width, source.Height);
    }

    /// Draws part of another picture into a rectangle of this one, scaling to
    /// fit. What a thumbnail and a sprite sheet are both made of.
    public void DrawScaled(Image source, int x, int y, int width, int height,
                           int sourceX, int sourceY, int sourceWidth, int sourceHeight)
    {
        if (_handle == null || source._handle == null)
            return;
        if (width <= 0 || height <= 0 || sourceWidth <= 0 || sourceHeight <= 0)
            return;

        var backend = Imaging.Use();
        if (backend == null)
            return;
        ((Backend)backend).Blit(_handle, source._handle, x, y, width, height,
                                sourceX, sourceY, sourceWidth, sourceHeight);
    }

    /// A copy at another size, resampled.
    public Result<Image, ImageError> Resize(int width, int height)
    {
        var made = Create(width, height);
        if (!made.Ok)
            return made;

        made.Value.DrawScaled(this, 0, 0, width, height, 0, 0, _wide, _high);
        return made;
    }

    // ---------------------------------------------------------------- saving

    /// The encoded bytes, in the format asked for.
    ///
    /// `quality` is 0 to 100 and reaches libgd's JPEG encoder; -1 is that
    /// encoder's own default. GDI+ ignores it -- setting it there needs an
    /// `EncoderParameters` laid out by hand for the one format that reads one,
    /// and its default of 75 is the same number libgd uses.
    public Result<byte[], ImageError> Encode(ImageFormat format, int quality = -1)
    {
        if (_handle == null)
            return Fail(ImageError.Invalid);

        var backend = Imaging.Use();
        if (backend == null)
            return Fail(ImageError.NoBackend);

        var data = ((Backend)backend).Encode(_handle, format, quality);
        if (data.Length == 0u)
            return Fail(ImageError.Unsupported);
        return Ok(data);
    }

    /// Encodes and writes to a file. `ImageError.None` when it worked.
    public ImageError Save(String path, ImageFormat format, int quality = -1)
    {
        var data = Encode(format, quality);
        if (!data.Ok)
            return data.Error;

        var written = WriteAllBytes(path, data.Value);
        return written == IOError.None ? ImageError.None : ImageError.WriteFailed;
    }
}
