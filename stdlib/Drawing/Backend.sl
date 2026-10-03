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

module Standard.Drawing;

import Standard.Text;

#if WINDOWS
// For `Guid`, which names a GDI+ encoder, and for the `com interface` the
// stream is.
import Standard.Com;
#endif

#if WINDOWS

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
    GdipSetPixelOffsetModeFn _pixelOffset;
    GdipCreateImageAttributesFn _makeAttributes;
    GdipSetImageAttributesWrapModeFn _wrapAttributes;
    GdipDisposeImageAttributesFn _dropAttributes;
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

        _startup = (GdiplusStartupFn)FindSymbol(gdiplus, "GdiplusStartup", &complete);
        _fromStream = (GdipCreateBitmapFromStreamFn)FindSymbol(gdiplus, "GdipCreateBitmapFromStream", &complete);
        _fromScan0 = (GdipCreateBitmapFromScan0Fn)FindSymbol(gdiplus, "GdipCreateBitmapFromScan0", &complete);
        _dispose = (GdipDisposeImageFn)FindSymbol(gdiplus, "GdipDisposeImage", &complete);
        _imageWidth = (GdipGetImageWidthFn)FindSymbol(gdiplus, "GdipGetImageWidth", &complete);
        _imageHeight = (GdipGetImageHeightFn)FindSymbol(gdiplus, "GdipGetImageHeight", &complete);
        _getPixel = (GdipBitmapGetPixelFn)FindSymbol(gdiplus, "GdipBitmapGetPixel", &complete);
        _setPixel = (GdipBitmapSetPixelFn)FindSymbol(gdiplus, "GdipBitmapSetPixel", &complete);
        _context = (GdipGetImageGraphicsContextFn)FindSymbol(gdiplus, "GdipGetImageGraphicsContext", &complete);
        _deleteGraphics = (GdipDeleteGraphicsFn)FindSymbol(gdiplus, "GdipDeleteGraphics", &complete);
        _smoothing = (GdipSetSmoothingModeFn)FindSymbol(gdiplus, "GdipSetSmoothingMode", &complete);
        _pixelOffset = (GdipSetPixelOffsetModeFn)FindSymbol(gdiplus, "GdipSetPixelOffsetMode", &complete);
        _makeAttributes = (GdipCreateImageAttributesFn)FindSymbol(gdiplus, "GdipCreateImageAttributes", &complete);
        _wrapAttributes = (GdipSetImageAttributesWrapModeFn)FindSymbol(gdiplus, "GdipSetImageAttributesWrapMode", &complete);
        _dropAttributes = (GdipDisposeImageAttributesFn)FindSymbol(gdiplus, "GdipDisposeImageAttributes", &complete);
        _clear = (GdipGraphicsClearFn)FindSymbol(gdiplus, "GdipGraphicsClear", &complete);
        _makePen = (GdipCreatePen1Fn)FindSymbol(gdiplus, "GdipCreatePen1", &complete);
        _dropPen = (GdipDeletePenFn)FindSymbol(gdiplus, "GdipDeletePen", &complete);
        _makeBrush = (GdipCreateSolidFillFn)FindSymbol(gdiplus, "GdipCreateSolidFill", &complete);
        _dropBrush = (GdipDeleteBrushFn)FindSymbol(gdiplus, "GdipDeleteBrush", &complete);
        _drawLine = (GdipDrawLineIFn)FindSymbol(gdiplus, "GdipDrawLineI", &complete);
        _drawRectangle = (GdipRectangleIFn)FindSymbol(gdiplus, "GdipDrawRectangleI", &complete);
        _fillRectangle = (GdipRectangleIFn)FindSymbol(gdiplus, "GdipFillRectangleI", &complete);
        _drawEllipse = (GdipRectangleIFn)FindSymbol(gdiplus, "GdipDrawEllipseI", &complete);
        _fillEllipse = (GdipRectangleIFn)FindSymbol(gdiplus, "GdipFillEllipseI", &complete);
        _drawPolygon = (GdipDrawPolygonIFn)FindSymbol(gdiplus, "GdipDrawPolygonI", &complete);
        _fillPolygon = (GdipFillPolygonIFn)FindSymbol(gdiplus, "GdipFillPolygonI", &complete);
        _blit = (GdipDrawImageRectRectIFn)FindSymbol(gdiplus, "GdipDrawImageRectRectI", &complete);
        _toStream = (GdipSaveImageToStreamFn)FindSymbol(gdiplus, "GdipSaveImageToStream", &complete);
        _lock = (GdipBitmapLockBitsFn)FindSymbol(gdiplus, "GdipBitmapLockBits", &complete);
        _unlock = (GdipBitmapUnlockBitsFn)FindSymbol(gdiplus, "GdipBitmapUnlockBits", &complete);
        _makeStream = (CreateStreamOnHGlobalFn)FindSymbol(ole, "CreateStreamOnHGlobal", &complete);
        _memoryOf = (GetHGlobalFromStreamFn)FindSymbol(ole, "GetHGlobalFromStream", &complete);

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
    void* FindSymbol(void* library, String name, bool* complete)
    {
        void* symbol = GetProcAddress(library, name.ToPointer());
        if (symbol == null)
            *complete = false;
        return symbol;
    }

    // ------------------------------------------------------------- lifetime

    public void* CreateImage(int width, int height)
    {
        void* bitmap = null;
        if (_fromScan0(width, height, 0, PixelFormat32bppArgb, null, &bitmap) != 0)
        {
            return null;
        }
        return bitmap;
    }

    public void* DecodeImage(byte[] data)
    {
        var stream = CreateStreamOver(data);
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

    /// Whether GDI+ decodes the format at all, which it does for all four.
    public bool CanDecode(ImageFormat format) => true;

    public void DestroyImage(void* image) => _dispose(image);

    public int GetWidth(void* image)
    {
        uint value = 0u;
        _imageWidth(image, &value);
        return (int)value;
    }

    public int GetHeight(void* image)
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

    /// The reverse of `CopyPixels`: every pixel at once, from the same order.
    public bool WritePixels(void* image, int width, int height, byte* from)
    {
        GpRect area;
        area.X = 0;
        area.Y = 0;
        area.Width = width;
        area.Height = height;

        BitmapData locked;
        if (_lock(image, &area, LockModeWrite, PixelFormat32bppArgb, &locked) != 0)
            return false;

        nuint row = (nuint)width * 4u;
        for (int y = 0; y < height; y++)
        {
            byte* target = (byte*)locked.Scan0 + (nint)y * (nint)locked.Stride;
            memcpy((void*)target, (void*)(from + (nuint)y * row), row);
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
    ///
    /// **`areas` is for fills and copies, and is false for outlines.** GDI+
    /// centres a pixel on its integer coordinate by default, so a filled
    /// rectangle's edges fall half across the pixels either side of it. An
    /// outline wants exactly that, because a one-pixel pen on an integer
    /// coordinate then covers one pixel; a fill wants pixel `i` to be the square
    /// from `i` to `i + 1`, which is what libgd fills.
    void* CreateGraphics(void* image, bool areas)
    {
        void* graphics = null;
        if (_context(image, &graphics) != 0)
            return null;
        _smoothing(graphics, SmoothingAntiAlias);
        if (areas)
            _pixelOffset(graphics, PixelOffsetHalf);
        return graphics;
    }

    public void ClearImage(void* image, uint colour)
    {
        void* graphics = CreateGraphics(image, true);
        if (graphics == null)
            return;
        _clear(graphics, colour);
        _deleteGraphics(graphics);
    }

    public void DrawLine(void* image, int x1, int y1, int x2, int y2, uint colour, int thickness)
    {
        void* graphics = CreateGraphics(image, false);
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
    public void DrawShape(void* image, bool ellipse, int x, int y, int width, int height,
                      uint colour, int thickness, bool filled)
    {
        void* graphics = CreateGraphics(image, filled);
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

    public void DrawPolygon(void* image, int[] points, uint colour, int thickness, bool filled)
    {
        void* graphics = CreateGraphics(image, filled);
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

    public void BlitImage(void* destination, void* source,
                     int dx, int dy, int dw, int dh, int sx, int sy, int sw, int sh)
    {
        void* graphics = CreateGraphics(destination, true);
        if (graphics == null)
            return;

        // Scaling samples past the source's last row and column, and GDI+
        // reads transparency there unless told to mirror the edge instead.
        void* attributes = null;
        if (_makeAttributes(&attributes) == 0)
            _wrapAttributes(attributes, WrapTileFlipXY, 0u, 0);

        _blit(graphics, source, dx, dy, dw, dh, sx, sy, sw, sh, UnitPixel, attributes,
              null, null);

        if (attributes != null)
            _dropAttributes(attributes);
        _deleteGraphics(graphics);
    }

    // -------------------------------------------------------------- codecs

    /// The encoder CLSIDs, written out.
    ///
    /// `GdipGetImageEncoders` answers them at run time, which means a
    /// variable-sized array of `ImageCodecInfo` and a match on a MIME string.
    /// These four have been the same since GDI+ shipped and are documented as
    /// constants; the lookup buys nothing but a failure mode.
    Guid FindEncoder(ImageFormat format)
    {
        // The four differ only in the last byte of the first field, which is
        // why they are built rather than written out four times.
        uint first = format switch
        {
            ImageFormat.Jpeg => 0x557CF401u,
            ImageFormat.Bmp => 0x557CF400u,
            ImageFormat.Gif => 0x557CF402u,
            _ => 0x557CF406u,                           // PNG
        };

        return new Guid(first, (ushort)0x1A04, (ushort)0x11D3,
            (byte)0x9A, (byte)0x73, (byte)0x00, (byte)0x00, (byte)0xF8, (byte)0x1E, (byte)0xF3, (byte)0x2E);
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
    IUnknown? CreateEmptyStream()
    {
        void* stream = null;
        if (_makeStream(null, 1, &stream) != 0)
            return null;
        return (IUnknown)stream;
    }

    /// A stream over a copy of a buffer.
    IUnknown? CreateStreamOver(byte[] data)
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
    public byte[] EncodeImage(void* image, ImageFormat format, int quality)
    {
        var nothing = new byte[0u];

        var stream = CreateEmptyStream();
        if (stream == null)
            return nothing;
        void* raw = (void*)(IUnknown)stream;

        var encoder = FindEncoder(format);
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

#elif MACOS

/// ImageIO to read and write a picture, and drawing done here on a buffer this
/// module owns.
///
/// **The drawing is not CoreGraphics'.** CoreGraphics antialiases, keeps
/// premultiplied alpha and has its own idea of which pixels a one-pixel edge
/// touches; the module's promises -- a fill covers exactly the pixels it was
/// given, a written pixel reads back -- are what GDI+ and libgd keep, and a
/// rasteriser of a hundred lines keeps them too. Each shape is marked in a
/// coverage mask and composed once, so a translucent shape does not darken
/// where its strokes overlap.
///
/// **Pixels are read as stored.** A decoded picture's bytes are copied out of
/// its data provider, so no colour is converted on the way in or out and a
/// grey of 128 reads as 128; only a layout this does not know is drawn
/// through CoreGraphics instead.
threadsafe sealed class Backend
{
    /// Linked, so always there.
    public bool Ready;

    public Backend()
    {
        Ready = true;
    }

    // ------------------------------------------------------------- lifetime

    public void* CreateImage(int width, int height)
    {
        var canvas = (Canvas*)calloc(1u, sizeof(Canvas));
        if (canvas == null)
            return null;

        (*canvas).Pixels = (uint*)calloc((nuint)width * (nuint)height, 4u);
        if ((*canvas).Pixels == null)
        {
            free((void*)canvas);
            return null;
        }

        (*canvas).Width = width;
        (*canvas).Height = height;
        return (void*)canvas;
    }

    public void DestroyImage(void* image)
    {
        var canvas = (Canvas*)image;
        free((void*)(*canvas).Pixels);
        free(image);
    }

    public int GetWidth(void* image) => (*(Canvas*)image).Width;

    public int GetHeight(void* image) => (*(Canvas*)image).Height;

    // --------------------------------------------------------------- pixels

    public uint GetPixel(void* image, int x, int y)
    {
        var canvas = (Canvas*)image;
        if (x < 0 || y < 0 || x >= (*canvas).Width || y >= (*canvas).Height)
            return 0u;
        return (*canvas).Pixels[(nuint)y * (nuint)(*canvas).Width + (nuint)x];
    }

    /// Replaced rather than blended: a caller writing a pixel means that pixel.
    public void SetPixel(void* image, int x, int y, uint colour)
    {
        var canvas = (Canvas*)image;
        if (x < 0 || y < 0 || x >= (*canvas).Width || y >= (*canvas).Height)
            return;
        (*canvas).Pixels[(nuint)y * (nuint)(*canvas).Width + (nuint)x] = colour;
    }

    /// Blue, green, red, alpha: the order the other backends answer.
    public bool CopyPixels(void* image, int width, int height, byte* into)
    {
        var canvas = (Canvas*)image;
        nuint count = (nuint)width * (nuint)height;
        for (nuint i = 0u; i < count; i++)
        {
            uint colour = (*canvas).Pixels[i];
            into[i * 4u] = (byte)(colour & 0xFFu);
            into[i * 4u + 1u] = (byte)((colour >> 8) & 0xFFu);
            into[i * 4u + 2u] = (byte)((colour >> 16) & 0xFFu);
            into[i * 4u + 3u] = (byte)(colour >> 24);
        }
        return true;
    }

    public bool WritePixels(void* image, int width, int height, byte* from)
    {
        var canvas = (Canvas*)image;
        nuint count = (nuint)width * (nuint)height;
        for (nuint i = 0u; i < count; i++)
            (*canvas).Pixels[i] = (uint)from[i * 4u] | ((uint)from[i * 4u + 1u] << 8)
                                  | ((uint)from[i * 4u + 2u] << 16) | ((uint)from[i * 4u + 3u] << 24);
        return true;
    }

    // -------------------------------------------------------------- drawing

    public void ClearImage(void* image, uint colour)
    {
        var canvas = (Canvas*)image;
        nuint count = (nuint)(*canvas).Width * (nuint)(*canvas).Height;
        for (nuint i = 0u; i < count; i++)
            (*canvas).Pixels[i] = colour;
    }

    public void DrawLine(void* image, int x1, int y1, int x2, int y2, uint colour, int width)
    {
        var canvas = (Canvas*)image;
        byte* mask = NewMask(canvas);
        if (mask == null)
            return;
        MarkLine(canvas, mask, x1, y1, x2, y2, width < 1 ? 1 : width);
        ApplyMask(canvas, mask, colour);
    }

    /// The bounding box `x, y, width, height`, as everywhere else here. An
    /// ellipse is centred on the box's middle pixel, or a pixel short of the
    /// middle when the size is even, and spans the size less one: so an odd
    /// one reaches every side and an even one stops a pixel short of one,
    /// which is where libgd puts it.
    public void DrawShape(void* image, bool isEllipse, int x, int y, int width, int height,
                          uint colour, int stroke, bool filled)
    {
        var canvas = (Canvas*)image;
        byte* mask = NewMask(canvas);
        if (mask == null)
            return;

        int thickness = stroke < 1 ? 1 : stroke;
        if (!isEllipse)
        {
            if (filled)
            {
                MarkBox(canvas, mask, x, y, width, height);
            }
            else
            {
                int right = x + width - 1;
                int bottom = y + height - 1;
                MarkLine(canvas, mask, x, y, right, y, thickness);
                MarkLine(canvas, mask, right, y, right, bottom, thickness);
                MarkLine(canvas, mask, right, bottom, x, bottom, thickness);
                MarkLine(canvas, mask, x, bottom, x, y, thickness);
            }
        }
        else
        {
            double cx = (double)(x + width / 2);
            double cy = (double)(y + height / 2);
            double rx = (double)(width - 1) / 2.0;
            double ry = (double)(height - 1) / 2.0;
            for (int py = y; py < y + height; py++)
            {
                for (int px = x; px < x + width; px++)
                {
                    bool inside = InsideEllipse(px, py, cx, cy, rx, ry);
                    if (inside && (filled ||
                                   !InsideEllipse(px, py, cx, cy, rx - (double)thickness,
                                                  ry - (double)thickness)))
                        MarkPixel(canvas, mask, px, py);
                }
            }
        }

        ApplyMask(canvas, mask, colour);
    }

    public void DrawPolygon(void* image, int[] points, uint colour, int stroke, bool filled)
    {
        var canvas = (Canvas*)image;
        int count = (int)(points.Length / 2u);
        if (count < 3)
            return;

        byte* mask = NewMask(canvas);
        if (mask == null)
            return;

        if (filled)
        {
            MarkPolygon(canvas, mask, points, count);
        }
        else
        {
            int thickness = stroke < 1 ? 1 : stroke;
            for (int i = 0; i < count; i++)
            {
                int j = (i + 1) % count;
                MarkLine(canvas, mask, points[(nuint)(2 * i)], points[(nuint)(2 * i + 1)],
                         points[(nuint)(2 * j)], points[(nuint)(2 * j + 1)], thickness);
            }
        }
        ApplyMask(canvas, mask, colour);
    }

    /// `source`'s rectangle drawn into `destination`'s and composed over it.
    /// The same size is a copy; another is sampled between the four nearest
    /// pixels, with each edge pixel taken from the source's edge rather than
    /// blended with what lies past it.
    public void BlitImage(void* destination, void* source,
                          int dx, int dy, int dw, int dh, int sx, int sy, int sw, int sh)
    {
        var target = (Canvas*)destination;
        var from = (Canvas*)source;
        bool same = dw == sw && dh == sh;

        for (int j = 0; j < dh; j++)
        {
            int ty = dy + j;
            if (ty < 0 || ty >= (*target).Height)
                continue;
            for (int i = 0; i < dw; i++)
            {
                int tx = dx + i;
                if (tx < 0 || tx >= (*target).Width)
                    continue;

                uint colour = same
                    ? GetPixel(source, sx + i, sy + j)
                    : SamplePixel(from, sx, sy, sw, sh,
                                  (double)sx + ((double)i + 0.5) * (double)sw / (double)dw - 0.5,
                                  (double)sy + ((double)j + 0.5) * (double)sh / (double)dh - 0.5);

                nuint at = (nuint)ty * (nuint)(*target).Width + (nuint)tx;
                (*target).Pixels[at] = BlendColour((*target).Pixels[at], colour);
            }
        }
    }

    // -------------------------------------------------------------- codecs

    /// ImageIO reads all four, whichever its version.
    public bool CanDecode(ImageFormat format) => true;

    public void* DecodeImage(byte[] data)
    {
        void* bytes = CFDataCreate(null, &data[0u], (long)data.Length);
        if (bytes == null)
            return null;

        void* source = CGImageSourceCreateWithData(bytes, null);
        CFRelease(bytes);
        if (source == null)
            return null;

        void* decoded = CGImageSourceCreateImageAtIndex(source, 0u, null);
        CFRelease(source);
        if (decoded == null)
            return null;

        int width = (int)CGImageGetWidth(decoded);
        int height = (int)CGImageGetHeight(decoded);
        void* image = width > 0 && height > 0 ? CreateImage(width, height) : null;
        if (image != null && !CopyStored(decoded, (Canvas*)image) && !CopyDrawn(decoded, (Canvas*)image))
        {
            DestroyImage(image);
            image = null;
        }

        CGImageRelease(decoded);
        return image;
    }

    /// The encoded bytes, or an empty array for a failure, as the other
    /// backends answer.
    public byte[] EncodeImage(void* image, ImageFormat format, int quality)
    {
        var canvas = (Canvas*)image;
        nuint width = (nuint)(*canvas).Width;
        nuint height = (nuint)(*canvas).Height;

        // Red, green, blue, alpha, unmultiplied: what CGImageCreate takes as
        // `kCGImageAlphaLast`.
        byte* rgba = calloc(width * height, 4u);
        if (rgba == null)
            return new byte[0u];
        for (nuint i = 0u; i < width * height; i++)
        {
            uint colour = (*canvas).Pixels[i];
            rgba[i * 4u] = (byte)((colour >> 16) & 0xFFu);
            rgba[i * 4u + 1u] = (byte)((colour >> 8) & 0xFFu);
            rgba[i * 4u + 2u] = (byte)(colour & 0xFFu);
            rgba[i * 4u + 3u] = (byte)(colour >> 24);
        }

        byte[] result = new byte[0u];
        void* provider = CGDataProviderCreateWithData(null, (void*)rgba, width * height * 4u, null);
        void* space = CGColorSpaceCreateDeviceRGB();
        void* picture = provider != null && space != null
            ? CGImageCreate(width, height, 8u, 32u, width * 4u, space, AlphaLast, provider, null, 0, 0)
            : null;

        if (picture != null)
        {
            void* type = CFStringCreateWithCString(null, TypeIdentifier(format).ToPointer(), EncodingUtf8);
            void* output = CFDataCreateMutable(null, 0);
            void* destination = type != null && output != null
                ? CGImageDestinationCreateWithData(output, type, 1u, null)
                : null;

            if (destination != null)
            {
                void* properties = null;
                if (format == ImageFormat.Jpeg)
                {
                    double fraction = (double)(quality < 0 ? 75 : quality) / 100.0;
                    void* number = CFNumberCreate(null, NumberDouble, (void*)&fraction);
                    void* key = kCGImageDestinationLossyCompressionQuality;
                    properties = CFDictionaryCreate(null, &key, &number, 1,
                                                    (void*)&kCFTypeDictionaryKeyCallBacks,
                                                    (void*)&kCFTypeDictionaryValueCallBacks);
                    CFRelease(number);
                }

                CGImageDestinationAddImage(destination, picture, properties);
                if (CGImageDestinationFinalize(destination) != 0)
                {
                    long length = CFDataGetLength(output);
                    result = new byte[(nuint)length];
                    if (length > 0)
                        memcpy((void*)&result[0u], (void*)CFDataGetBytePtr(output), (nuint)length);
                }

                if (properties != null)
                    CFRelease(properties);
                CFRelease(destination);
            }

            if (output != null)
                CFRelease(output);
            if (type != null)
                CFRelease(type);
            CGImageRelease(picture);
        }

        if (space != null)
            CGColorSpaceRelease(space);
        if (provider != null)
            CGDataProviderRelease(provider);
        free((void*)rgba);
        return result;
    }

    static String TypeIdentifier(ImageFormat format) => format switch
    {
        ImageFormat.Jpeg => "public.jpeg",
        ImageFormat.Gif => "com.compuserve.gif",
        ImageFormat.Bmp => "com.microsoft.bmp",
        _ => "public.png",
    };

    /// A decoded picture's own bytes, for an 8-bit grey, indexed or RGB layout;
    /// false for any other, which `CopyDrawn` takes instead.
    bool CopyStored(void* decoded, Canvas* canvas)
    {
        if (CGImageGetBitsPerComponent(decoded) != 8u)
            return false;

        void* space = CGImageGetColorSpace(decoded);
        int model = space != null ? CGColorSpaceGetModel(space) : -1;
        nuint bits = CGImageGetBitsPerPixel(decoded);
        uint info = CGImageGetBitmapInfo(decoded);
        uint alpha = info & 0x1Fu;
        bool little = (info & 0x7000u) == ByteOrder32Little;

        // Which byte of a pixel is red, green, blue and alpha; -1 for none.
        int red = -1; int green = -1; int blue = -1; int opacity = -1;
        byte[] table = new byte[0u];

        if (model == ModelIndexed && bits == 8u)
        {
            void* basis = CGColorSpaceGetBaseColorSpace(space);
            if (basis == null || CGColorSpaceGetModel(basis) != ModelRgb)
                return false;
            nuint entries = CGColorSpaceGetColorTableCount(space);
            table = new byte[entries * 3u + 3u];
            CGColorSpaceGetColorTable(space, &table[0u]);
        }
        else if (model == ModelMonochrome && bits == 8u && alpha == AlphaNone)
        {
            red = 0; green = 0; blue = 0;
        }
        else if (model == ModelMonochrome && bits == 16u)
        {
            bool first = alpha == AlphaFirst || alpha == AlphaPremultipliedFirst;
            red = first ? 1 : 0; green = red; blue = red;
            opacity = first ? 0 : 1;
        }
        else if (model == ModelRgb && bits == 24u && alpha == AlphaNone)
        {
            red = 0; green = 1; blue = 2;
        }
        else if (model == ModelRgb && bits == 32u)
        {
            bool first = alpha == AlphaFirst || alpha == AlphaPremultipliedFirst ||
                         alpha == AlphaNoneSkipFirst;
            int start = first ? 1 : 0;
            red = start; green = start + 1; blue = start + 2;
            if (alpha != AlphaNoneSkipFirst && alpha != AlphaNoneSkipLast && alpha != AlphaNone)
                opacity = first ? 0 : 3;
            if (little)
            {
                red = 3 - red; green = 3 - green; blue = 3 - blue;
                if (opacity >= 0)
                    opacity = 3 - opacity;
            }
        }
        else
        {
            return false;
        }

        void* provider = CGImageGetDataProvider(decoded);
        void* copied = provider != null ? CGDataProviderCopyData(provider) : null;
        if (copied == null)
            return false;

        byte* stored = CFDataGetBytePtr(copied);
        nuint row = CGImageGetBytesPerRow(decoded);
        nuint step = bits / 8u;
        bool premultiplied = alpha == AlphaPremultipliedFirst || alpha == AlphaPremultipliedLast;
        int width = (*canvas).Width;

        for (int y = 0; y < (*canvas).Height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                byte* pixel = stored + (nuint)y * row + (nuint)x * step;
                uint r; uint g; uint b; uint a = 255u;
                if (red < 0)
                {
                    nuint entry = (nuint)pixel[0] * 3u;
                    r = (uint)table[entry]; g = (uint)table[entry + 1u]; b = (uint)table[entry + 2u];
                }
                else
                {
                    r = (uint)pixel[red]; g = (uint)pixel[green]; b = (uint)pixel[blue];
                    if (opacity >= 0)
                        a = (uint)pixel[opacity];
                }

                if (premultiplied && a != 0u && a != 255u)
                {
                    r = (r * 255u + a / 2u) / a; if (r > 255u) r = 255u;
                    g = (g * 255u + a / 2u) / a; if (g > 255u) g = 255u;
                    b = (b * 255u + a / 2u) / a; if (b > 255u) b = 255u;
                }

                (*canvas).Pixels[(nuint)y * (nuint)width + (nuint)x] = (a << 24) | (r << 16) | (g << 8) | b;
            }
        }

        CFRelease(copied);
        return true;
    }

    /// Any other layout, drawn into an RGBA context by CoreGraphics and read
    /// back. The colour is converted on the way, which is what a 16-bit or a
    /// CMYK picture needs anyway.
    bool CopyDrawn(void* decoded, Canvas* canvas)
    {
        nuint width = (nuint)(*canvas).Width;
        nuint height = (nuint)(*canvas).Height;
        byte* rgba = calloc(width * height, 4u);
        void* space = CGColorSpaceCreateDeviceRGB();
        void* context = rgba != null && space != null
            ? CGBitmapContextCreate((void*)rgba, width, height, 8u, width * 4u, space, AlphaPremultipliedLast)
            : null;

        bool drawn = context != null;
        if (drawn)
        {
            ImageRect whole;
            whole.X = 0.0;
            whole.Y = 0.0;
            whole.Width = (double)width;
            whole.Height = (double)height;
            CGContextDrawImage(context, whole, decoded);

            for (nuint i = 0u; i < width * height; i++)
            {
                uint r = (uint)rgba[i * 4u]; uint g = (uint)rgba[i * 4u + 1u];
                uint b = (uint)rgba[i * 4u + 2u]; uint a = (uint)rgba[i * 4u + 3u];
                if (a != 0u && a != 255u)
                {
                    r = (r * 255u + a / 2u) / a; if (r > 255u) r = 255u;
                    g = (g * 255u + a / 2u) / a; if (g > 255u) g = 255u;
                    b = (b * 255u + a / 2u) / a; if (b > 255u) b = 255u;
                }
                (*canvas).Pixels[i] = (a << 24) | (r << 16) | (g << 8) | b;
            }
            CGContextRelease(context);
        }

        if (space != null)
            CGColorSpaceRelease(space);
        if (rgba != null)
            free((void*)rgba);
        return drawn;
    }

    // ----------------------------------------------------------- rasterising

    /// A mask the size of the picture, one byte a pixel, all clear; null when
    /// it cannot be had.
    static byte* NewMask(Canvas* canvas) =>
        calloc((nuint)(*canvas).Width * (nuint)(*canvas).Height, 1u);

    static void MarkPixel(Canvas* canvas, byte* mask, int x, int y)
    {
        if (x < 0 || y < 0 || x >= (*canvas).Width || y >= (*canvas).Height)
            return;
        mask[(nuint)y * (nuint)(*canvas).Width + (nuint)x] = 1;
    }

    static void MarkBox(Canvas* canvas, byte* mask, int x, int y, int width, int height)
    {
        for (int py = y; py < y + height; py++)
            for (int px = x; px < x + width; px++)
                MarkPixel(canvas, mask, px, py);
    }

    /// Bresenham's line, each point a square `thickness` across centred on it.
    static void MarkLine(Canvas* canvas, byte* mask, int x1, int y1, int x2, int y2, int thickness)
    {
        int dx = x2 > x1 ? x2 - x1 : x1 - x2;
        int dy = y2 > y1 ? y1 - y2 : y2 - y1;
        int stepX = x1 < x2 ? 1 : -1;
        int stepY = y1 < y2 ? 1 : -1;
        int error = dx + dy;
        int back = (thickness - 1) / 2;
        int x = x1;
        int y = y1;

        while (true)
        {
            MarkBox(canvas, mask, x - back, y - back, thickness, thickness);
            if (x == x2 && y == y2)
                break;
            int twice = 2 * error;
            if (twice >= dy)
            {
                error += dy;
                x += stepX;
            }
            if (twice <= dx)
            {
                error += dx;
                y += stepY;
            }
        }
    }

    /// A pixel is inside when its centre is, by the even-odd rule.
    static void MarkPolygon(Canvas* canvas, byte* mask, int[] points, int count)
    {
        var crossings = new double[(nuint)count];
        for (int py = 0; py < (*canvas).Height; py++)
        {
            double centre = (double)py + 0.5;
            int found = 0;
            for (int i = 0; i < count; i++)
            {
                int j = (i + 1) % count;
                double ax = (double)points[(nuint)(2 * i)];
                double ay = (double)points[(nuint)(2 * i + 1)] + 0.5;
                double bx = (double)points[(nuint)(2 * j)];
                double by = (double)points[(nuint)(2 * j + 1)] + 0.5;
                if ((ay <= centre && by > centre) || (by <= centre && ay > centre))
                {
                    crossings[(nuint)found] = ax + (centre - ay) * (bx - ax) / (by - ay);
                    found++;
                }
            }

            for (int i = 1; i < found; i++)
            {
                double held = crossings[(nuint)i];
                int k = i - 1;
                while (k >= 0 && crossings[(nuint)k] > held)
                {
                    crossings[(nuint)(k + 1)] = crossings[(nuint)k];
                    k--;
                }
                crossings[(nuint)(k + 1)] = held;
            }

            for (int i = 0; i + 1 < found; i += 2)
            {
                int from = (int)Ceiling(crossings[(nuint)i]);
                int to = (int)Floor(crossings[(nuint)(i + 1)]);
                for (int px = from; px <= to; px++)
                    MarkPixel(canvas, mask, px, py);
            }
        }
    }

    static double Floor(double value)
    {
        double whole = (double)(long)value;
        return whole > value ? whole - 1.0 : whole;
    }

    static double Ceiling(double value)
    {
        double whole = (double)(long)value;
        return whole < value ? whole + 1.0 : whole;
    }

    static bool InsideEllipse(int px, int py, double cx, double cy, double rx, double ry)
    {
        if (rx < 0.0 || ry < 0.0)
            return false;
        double ox = (double)px - cx;
        double oy = (double)py - cy;
        if (rx == 0.0 || ry == 0.0)
            return (rx == 0.0 ? ox == 0.0 : ox * ox <= rx * rx) &&
                   (ry == 0.0 ? oy == 0.0 : oy * oy <= ry * ry);
        return ox * ox / (rx * rx) + oy * oy / (ry * ry) <= 1.0 + 1e-9;
    }

    /// Every marked pixel composed with `colour`, and the mask freed.
    static void ApplyMask(Canvas* canvas, byte* mask, uint colour)
    {
        nuint count = (nuint)(*canvas).Width * (nuint)(*canvas).Height;
        for (nuint i = 0u; i < count; i++)
            if (mask[i] != 0)
                (*canvas).Pixels[i] = BlendColour((*canvas).Pixels[i], colour);
        free((void*)mask);
    }

    /// `over` composed over `under`, neither premultiplied.
    static uint BlendColour(uint under, uint over)
    {
        uint sa = over >> 24;
        if (sa == 255u)
            return over;
        if (sa == 0u)
            return under;

        uint da = under >> 24;
        uint kept = da * (255u - sa);
        uint oa = sa + (kept + 127u) / 255u;
        if (oa == 0u)
            return 0u;

        uint whole = oa * 255u;
        uint r = (((over >> 16) & 0xFFu) * sa * 255u + ((under >> 16) & 0xFFu) * kept + whole / 2u) / whole;
        uint g = (((over >> 8) & 0xFFu) * sa * 255u + ((under >> 8) & 0xFFu) * kept + whole / 2u) / whole;
        uint b = ((over & 0xFFu) * sa * 255u + (under & 0xFFu) * kept + whole / 2u) / whole;
        return (oa << 24) | (r << 16) | (g << 8) | b;
    }

    /// The colour at a point between pixels, from the four nearest, with the
    /// point held inside the source rectangle so an edge takes the edge.
    static uint SamplePixel(Canvas* source, int sx, int sy, int sw, int sh, double x, double y)
    {
        double left = (double)sx;
        double top = (double)sy;
        double right = (double)(sx + sw - 1);
        double bottom = (double)(sy + sh - 1);
        if (x < left) x = left;
        if (x > right) x = right;
        if (y < top) y = top;
        if (y > bottom) y = bottom;

        int x0 = (int)Floor(x);
        int y0 = (int)Floor(y);
        int x1 = x0 + 1 > sx + sw - 1 ? x0 : x0 + 1;
        int y1 = y0 + 1 > sy + sh - 1 ? y0 : y0 + 1;
        double fx = x - (double)x0;
        double fy = y - (double)y0;

        // Premultiplied while they are mixed, so a transparent neighbour does
        // not darken the edge.
        double a = 0.0; double r = 0.0; double g = 0.0; double b = 0.0;
        for (int k = 0; k < 4; k++)
        {
            int px = (k & 1) == 0 ? x0 : x1;
            int py = (k & 2) == 0 ? y0 : y1;
            double weight = ((k & 1) == 0 ? 1.0 - fx : fx) * ((k & 2) == 0 ? 1.0 - fy : fy);
            uint colour = 0u;
            if (px >= 0 && py >= 0 && px < (*source).Width && py < (*source).Height)
                colour = (*source).Pixels[(nuint)py * (nuint)(*source).Width + (nuint)px];
            double alpha = (double)(colour >> 24) * weight;
            a += alpha;
            r += (double)((colour >> 16) & 0xFFu) * alpha;
            g += (double)((colour >> 8) & 0xFFu) * alpha;
            b += (double)(colour & 0xFFu) * alpha;
        }

        if (a <= 0.0)
            return 0u;
        uint oa = (uint)(a + 0.5);
        if (oa > 255u) oa = 255u;
        uint mixedRed = (uint)(r / a + 0.5);
        uint mixedGreen = (uint)(g / a + 0.5);
        uint mixedBlue = (uint)(b / a + 0.5);
        if (mixedRed > 255u) mixedRed = 255u;
        if (mixedGreen > 255u) mixedGreen = 255u;
        if (mixedBlue > 255u) mixedBlue = 255u;
        return (oa << 24) | (mixedRed << 16) | (mixedGreen << 8) | mixedBlue;
    }
}

#else

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
    GdImageCopyFn _copy;
    GdImagePaletteToTrueColorFn _toTrueColor;
    GdImageCreatePaletteFn _createPalette;
    GdImageColorAllocateAlphaFn _allocateColour;
    GdImageColorTransparentFn _transparent;

    public bool Ready;

    public Backend()
    {
        Ready = false;

        // The versioned runtime library first, which is what a machine with the
        // package installed has; then the development symlink; then the older
        // soname.
        void* library = OpenLibrary("libgd.so.3");
        if (library == null)
            library = OpenLibrary("libgd.so");
        if (library == null)
            library = OpenLibrary("libgd.so.2");
        if (library == null)
            return;

        bool complete = true;

        _createTrueColor = (GdImageCreateTrueColorFn)FindSymbol(library, "gdImageCreateTrueColor", &complete);
        _destroy = (GdImageDestroyFn)FindSymbol(library, "gdImageDestroy", &complete);
        _fromPng = (GdImageCreateFromPtrFn)FindSymbol(library, "gdImageCreateFromPngPtr", &complete);
        _fromJpeg = (GdImageCreateFromPtrFn)FindSymbol(library, "gdImageCreateFromJpegPtr", &complete);
        _fromGif = (GdImageCreateFromPtrFn)FindSymbol(library, "gdImageCreateFromGifPtr", &complete);
        _toPng = (GdImageToPtrFn)FindSymbol(library, "gdImagePngPtr", &complete);
        _toJpeg = (GdImageToPtrQualityFn)FindSymbol(library, "gdImageJpegPtr", &complete);
        _toGif = (GdImageToPtrFn)FindSymbol(library, "gdImageGifPtr", &complete);
        _release = (GdFreeFn)FindSymbol(library, "gdFree", &complete);
        _getClip = (GdImageGetClipFn)FindSymbol(library, "gdImageGetClip", &complete);
        _setPixel = (GdImageSetPixelFn)FindSymbol(library, "gdImageSetPixel", &complete);
        _getPixel = (GdImageGetPixelFn)FindSymbol(library, "gdImageGetPixel", &complete);
        _line = (GdImageLineFn)FindSymbol(library, "gdImageLine", &complete);
        _rectangle = (GdImageRectFn)FindSymbol(library, "gdImageRectangle", &complete);
        _fillRectangle = (GdImageRectFn)FindSymbol(library, "gdImageFilledRectangle", &complete);
        _ellipse = (GdImageEllipseFn)FindSymbol(library, "gdImageEllipse", &complete);
        _fillEllipse = (GdImageEllipseFn)FindSymbol(library, "gdImageFilledEllipse", &complete);
        _polygon = (GdImagePolygonFn)FindSymbol(library, "gdImagePolygon", &complete);
        _fillPolygon = (GdImagePolygonFn)FindSymbol(library, "gdImageFilledPolygon", &complete);
        _thickness = (GdImageSetThicknessFn)FindSymbol(library, "gdImageSetThickness", &complete);
        _blending = (GdImageFlagFn)FindSymbol(library, "gdImageAlphaBlending", &complete);
        _saveAlpha = (GdImageFlagFn)FindSymbol(library, "gdImageSaveAlpha", &complete);
        _resample = (GdImageCopyResampledFn)FindSymbol(library, "gdImageCopyResampled", &complete);
        _copy = (GdImageCopyFn)FindSymbol(library, "gdImageCopy", &complete);
        _createPalette = (GdImageCreatePaletteFn)FindSymbol(library, "gdImageCreate", &complete);
        _allocateColour = (GdImageColorAllocateAlphaFn)FindSymbol(library, "gdImageColorAllocateAlpha", &complete);
        _transparent = (GdImageColorTransparentFn)FindSymbol(library, "gdImageColorTransparent", &complete);

        // 2.1.0 and later. Without it every decoded image is copied onto a
        // true colour one instead, which costs a second image for the length
        // of the copy.
        void* toTrueColor = dlsym(library, "gdImagePaletteToTrueColor".ToPointer());
        if (toTrueColor != null)
            _toTrueColor = (GdImagePaletteToTrueColorFn)toTrueColor;

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

    void* OpenLibrary(String name) => dlopen(name.ToPointer(), RtldLazyLocal);

    void* FindSymbol(void* library, String name, bool* complete)
    {
        void* symbol = dlsym(library, name.ToPointer());
        if (symbol == null)
            *complete = false;
        return symbol;
    }

    /// libgd's alpha is seven bits and inverted: 0 is opaque and 127 is
    /// invisible, where everything above this uses eight bits with 255 opaque.
    ///
    /// So only half the alphas survive a trip through an image. Both
    /// directions round to nearest, which makes a value that has been through
    /// once come back unchanged every time after; rounding down both ways
    /// drifted further from the original on every trip.
    int ToGd(uint colour)
    {
        uint alpha = (colour >> 24) & 0xFFu;
        uint inverted = ((255u - alpha) * 127u + 127u) / 255u;
        return (int)((inverted << 24) | (colour & 0x00FFFFFFu));
    }

    uint FromGd(int colour)
    {
        uint packed = (uint)colour;
        uint inverted = (packed >> 24) & 0x7Fu;
        uint alpha = 255u - (inverted * 255u + 63u) / 127u;
        return (alpha << 24) | (packed & 0x00FFFFFFu);
    }

    // ------------------------------------------------------------- lifetime

    public void* CreateImage(int width, int height)
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

    public void* DecodeImage(byte[] data)
    {
        int size = (int)data.Length;
        void* raw = (void*)&data[0u];
        void* image = null;

        ImageFormat format = ImageFormat.Png;
        if (!SniffFormat(data, &format))
            return null;

        if (format == ImageFormat.Png)
            image = _fromPng(size, raw);
        if (format == ImageFormat.Jpeg)
            image = _fromJpeg(size, raw);
        if (format == ImageFormat.Gif)
            image = _fromGif(size, raw);
        if (format == ImageFormat.Bmp && _fromBmp != null)
            image = _fromBmp(size, raw);

        if (image == null)
            return null;
        return ConvertToTrueColor(image);
    }

    /// Whether this libgd decodes the format at all.
    public bool CanDecode(ImageFormat format) => format != ImageFormat.Bmp || _fromBmp != null;

    /// A decoded image as true colour, which is what everything else here
    /// assumes.
    ///
    /// A GIF, a palette PNG and a grey PNG decode to palette images, whose
    /// pixels are indices: `gdImageGetPixel` answers the index, and a drawing
    /// call stores the low byte of a colour as one. The image is taken, and
    /// the one answered may be another.
    void* ConvertToTrueColor(void* image)
    {
        if (_toTrueColor != null)
        {
            if (_toTrueColor(image) == 0)
            {
                _destroy(image);
                return null;
            }
            _blending(image, 1);
            _saveAlpha(image, 1);
            return image;
        }

        // `gdImageCopy` converts a palette entry, and its alpha, to the colour
        // it stands for. It skips the transparent index, which leaves the
        // transparent pixel `CreateImage` put there.
        int width = GetWidth(image);
        int height = GetHeight(image);
        void* copy = CreateImage(width, height);
        if (copy != null)
        {
            _blending(copy, 0);
            _copy(copy, image, 0, 0, 0, 0, width, height);
            _blending(copy, 1);
        }
        _destroy(image);
        return copy;
    }

    public void DestroyImage(void* image) => _destroy(image);

    /// **The size comes from the clipping rectangle and not from `gdImageSX`.**
    /// SX and SY are macros over the structure's fields, so using them would
    /// mean declaring `gdImageStruct` and depending on its layout. A fresh
    /// image's clip is the whole image, which is the same two numbers through a
    /// real function.
    public int GetWidth(void* image)
    {
        int left = 0; int top = 0; int right = 0; int bottom = 0;
        _getClip(image, &left, &top, &right, &bottom);
        return right - left + 1;
    }

    public int GetHeight(void* image)
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
                at += 4u;
            }
        }
        return true;
    }

    /// The reverse of `CopyPixels`, a call per pixel for the reason given there.
    public bool WritePixels(void* image, int width, int height, byte* from)
    {
        // Replace rather than blend, as `SetPixel` does.
        _blending(image, 0);
        nuint at = 0u;
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                uint colour = (uint)from[at] | ((uint)from[at + 1u] << 8)
                            | ((uint)from[at + 2u] << 16) | ((uint)from[at + 3u] << 24);
                _setPixel(image, x, y, ToGd(colour));
                at += 4u;
            }
        }
        _blending(image, 1);
        return true;
    }

    // -------------------------------------------------------------- drawing

    public void ClearImage(void* image, uint colour)
    {
        _blending(image, 0);
        _fillRectangle(image, 0, 0, GetWidth(image) - 1, GetHeight(image) - 1, ToGd(colour));
        _blending(image, 1);
    }

    public void DrawLine(void* image, int x1, int y1, int x2, int y2, uint colour, int width)
    {
        _thickness(image, width < 1 ? 1 : width);
        _line(image, x1, y1, x2, y2, ToGd(colour));
        _thickness(image, 1);
    }

    /// libgd's ellipse is a centre and a size, where every other API here gives
    /// the bounding box. It spans the centre plus and minus half the size
    /// given, which is one pixel more than the size, so it is given one less:
    /// an odd width then fills its rectangle, and an even one, which has no
    /// middle pixel to centre on, stops a pixel short of one side.
    public void DrawShape(void* image, bool isEllipse, int x, int y, int width, int height,
                      uint colour, int stroke, bool filled)
    {
        int ink = ToGd(colour);

        if (filled)
        {
            if (isEllipse)
            {
                _fillEllipse(image, x + width / 2, y + height / 2, width - 1, height - 1, ink);
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
            _ellipse(image, x + width / 2, y + height / 2, width - 1, height - 1, ink);
        }
        else
        {
            _rectangle(image, x, y, x + width - 1, y + height - 1, ink);
        }
        _thickness(image, 1);
    }

    public void DrawPolygon(void* image, int[] points, uint colour, int stroke, bool filled)
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

    public void BlitImage(void* destination, void* source,
                     int dx, int dy, int dw, int dh, int sx, int sy, int sw, int sh)
    {
        // Resampled even when the sizes match, so that the alpha composes the
        // same way it does when they do not. `gdImageCopy` would be faster and
        // would disagree with itself at two different scales.
        _resample(destination, source, dx, dy, sx, sy, dw, dh, sw, sh);
    }

    // -------------------------------------------------------------- codecs

    /// A palette copy of a picture with at most 256 colours, each kept exactly,
    /// or null when it has more or has a pixel neither opaque nor invisible.
    ///
    /// libgd quantizes a truecolor picture to write a GIF, and 2.3.3 as Ubuntu
    /// 24.04 ships it moves even a two-colour picture's red to 252, 2, 4.
    /// Null leaves that quantizing to libgd, which is all a GIF can do then.
    void* ExactPalette(void* image)
    {
        int width = GetWidth(image);
        int height = GetHeight(image);
        var colours = new int[256u];
        int count = 0;
        int invisible = -1;

        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                int colour = _getPixel(image, x, y);
                int alpha = (colour >> 24) & 0x7F;
                if (alpha == 127)
                {
                    invisible = 0;
                    continue;
                }
                if (alpha != 0)
                    return null;
                if (IndexOfColour(colours, count, colour) >= 0)
                    continue;
                if (count == 256 || count == 255 && invisible >= 0)
                    return null;
                colours[(nuint)count] = colour;
                count++;
            }
        }

        void* palette = _createPalette(width, height);
        if (palette == null)
            return null;

        for (int at = 0; at < count; at++)
        {
            int colour = colours[(nuint)at];
            _allocateColour(palette, (colour >> 16) & 0xFF, (colour >> 8) & 0xFF, colour & 0xFF, 0);
        }
        if (invisible >= 0)
        {
            invisible = _allocateColour(palette, 0, 0, 0, 127);
            _transparent(palette, invisible);
        }

        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                int colour = _getPixel(image, x, y);
                int index = ((colour >> 24) & 0x7F) == 127 ? invisible : IndexOfColour(colours, count, colour);
                _setPixel(palette, x, y, index);
            }
        }
        return palette;
    }

    static int IndexOfColour(int[] colours, int count, int colour)
    {
        for (int at = 0; at < count; at++)
        {
            if (colours[(nuint)at] == colour)
                return at;
        }
        return -1;
    }

    /// The encoded bytes, or an empty array for a failure. See the note on
    /// the Windows backend's `EncodeImage` for why empty rather than null.
    public byte[] EncodeImage(void* image, ImageFormat format, int quality)
    {
        int size = 0;
        void* raw = null;

        if (format == ImageFormat.Png)
            raw = _toPng(image, &size);
        if (format == ImageFormat.Jpeg)
            raw = _toJpeg(image, &size, quality < 0 ? 75 : quality);
        if (format == ImageFormat.Gif)
        {
            void* exact = ExactPalette(image);
            raw = _toGif(exact != null ? exact : image, &size);
            if (exact != null)
                _destroy(exact);
        }
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
