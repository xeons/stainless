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
/// logo.FillRectangle(Rgba.FromRgb(200, 30, 30), 8, 8, 64, 24);
/// logo.DrawLine(Rgba.Black, 0, 0, logo.Width, logo.Height, 2);
/// logo.Save("out.png", ImageFormat.Png);
/// ```
///
/// **GDI+ on Windows, ImageIO on macOS and libgd elsewhere.** GDI+ and libgd
/// are loaded by name the first time an image is made. That is what lets this
/// live in the standard library at all: a `#pragma comment(lib, "gdiplus")`
/// would put an import in every Stainless binary on Windows including the
/// ones that never make an image, and `-lgd` needs libgd's *development*
/// package where what a machine actually has is the runtime one. So a program
/// that makes no image pays nothing, and a machine with no imaging library
/// answers `ImageError.NoBackend` -- a value to print, rather than a link
/// error. Every Mac has ImageIO, so there it is linked, into the programs that
/// compile this module, and the drawing is done here.
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
import Standard.File;
import Standard.IO;

extern "C"
{
    void* memcpy(void* destination, void* source, nuint count);
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
delegate __stdcall int GdipSetPixelOffsetModeFn(void* graphics, int mode);
delegate __stdcall int GdipCreateImageAttributesFn(void** attributes);
delegate __stdcall int GdipSetImageAttributesWrapModeFn(void* attributes, int wrap,
                                                        uint colour, int clamp);
delegate __stdcall int GdipDisposeImageAttributesFn(void* attributes);
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
/// `PixelOffsetModeHalf`: pixel `i` covers `i` to `i + 1` rather than being
/// centred on `i`, so an integer rectangle covers whole pixels.
const int PixelOffsetHalf = 4;
/// `WrapModeTileFlipXY`, which samples past an image's edge from its mirror
/// rather than from transparency.
const int WrapTileFlipXY = 3;
/// `FillModeAlternate`, the even-odd rule, which is also what libgd's polygon
/// fill does.
const int FillAlternate = 0;
/// `UnitPixel`, for a pen width and for a source rectangle.
const int UnitPixel = 2;
/// `GMEM_MOVEABLE`, which is what a stream over an `HGLOBAL` requires.
const uint GlobalMoveable = 0x0002u;
/// `ImageLockModeRead` and `ImageLockModeWrite`.
const uint LockModeRead = 0x0001u;
const uint LockModeWrite = 0x0002u;

#elif MACOS

// ========================================================== the macOS backend

// Every Mac has all three, so they are linked rather than loaded by name; only
// a program that compiles this module gets them.
#pragma comment(framework, "ImageIO")
#pragma comment(framework, "CoreGraphics")
#pragma comment(framework, "CoreFoundation")

extern "C"
{
    byte* calloc(nuint count, nuint size);
    void free(void* block);

    void* CFDataCreate(void* allocator, byte* bytes, long length);
    void* CFDataCreateMutable(void* allocator, long capacity);
    long CFDataGetLength(void* data);
    byte* CFDataGetBytePtr(void* data);
    void* CFStringCreateWithCString(void* allocator, byte* text, uint encoding);
    void* CFNumberCreate(void* allocator, long type, void* value);
    void* CFDictionaryCreate(void* allocator, void** keys, void** values, long count,
                             void* keyCallBacks, void* valueCallBacks);
    void CFRelease(void* value);

    void* CGImageSourceCreateWithData(void* data, void* options);
    void* CGImageSourceCreateImageAtIndex(void* source, nuint index, void* options);
    void* CGImageDestinationCreateWithData(void* data, void* type, nuint count, void* options);
    void CGImageDestinationAddImage(void* destination, void* image, void* properties);
    byte CGImageDestinationFinalize(void* destination);

    nuint CGImageGetWidth(void* image);
    nuint CGImageGetHeight(void* image);
    nuint CGImageGetBitsPerComponent(void* image);
    nuint CGImageGetBitsPerPixel(void* image);
    nuint CGImageGetBytesPerRow(void* image);
    uint CGImageGetBitmapInfo(void* image);
    void* CGImageGetColorSpace(void* image);
    void* CGImageGetDataProvider(void* image);
    void* CGImageCreate(nuint width, nuint height, nuint bitsPerComponent, nuint bitsPerPixel,
                        nuint bytesPerRow, void* space, uint bitmapInfo, void* provider,
                        void* decode, byte shouldInterpolate, int intent);
    void CGImageRelease(void* image);

    void* CGDataProviderCopyData(void* provider);
    void* CGDataProviderCreateWithData(void* info, void* data, nuint size, void* release);
    void CGDataProviderRelease(void* provider);

    int CGColorSpaceGetModel(void* space);
    nuint CGColorSpaceGetColorTableCount(void* space);
    void CGColorSpaceGetColorTable(void* space, byte* table);
    void* CGColorSpaceGetBaseColorSpace(void* space);
    void* CGColorSpaceCreateDeviceRGB();
    void CGColorSpaceRelease(void* space);

    void* CGBitmapContextCreate(void* data, nuint width, nuint height, nuint bitsPerComponent,
                                nuint bytesPerRow, void* space, uint bitmapInfo);
    void CGContextDrawImage(void* context, ImageRect rect, void* image);
    void CGContextRelease(void* context);
}

extern "C" byte kCFTypeDictionaryKeyCallBacks;
extern "C" byte kCFTypeDictionaryValueCallBacks;
extern "C" void* kCGImageDestinationLossyCompressionQuality;

/// `kCGColorSpaceModelMonochrome`, `...RGB` and `...Indexed`.
const int ModelMonochrome = 0;
const int ModelRgb = 1;
const int ModelIndexed = 5;

/// `CGImageAlphaInfo`: where the alpha is, and whether the colour is
/// multiplied by it.
const uint AlphaNone = 0u;
const uint AlphaPremultipliedLast = 1u;
const uint AlphaPremultipliedFirst = 2u;
const uint AlphaLast = 3u;
const uint AlphaFirst = 4u;
const uint AlphaNoneSkipLast = 5u;
const uint AlphaNoneSkipFirst = 6u;

/// `kCGBitmapByteOrder32Little`.
const uint ByteOrder32Little = 0x2000u;

/// `kCFStringEncodingUTF8` and `kCFNumberDoubleType`.
const uint EncodingUtf8 = 0x08000100u;
const long NumberDouble = 13;

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
delegate void  GdImageCopyFn(void* destination, void* source,
                             int dx, int dy, int sx, int sy, int w, int h);
delegate int   GdImagePaletteToTrueColorFn(void* image);
delegate void* GdImageCreatePaletteFn(int width, int height);
delegate int   GdImageColorAllocateAlphaFn(void* image, int r, int g, int b, int a);
delegate void  GdImageColorTransparentFn(void* image, int index);

extern "C"
{
    void* dlopen(byte* name, int flags);
    void* dlsym(void* library, byte* name);
}

/// `RTLD_LAZY | RTLD_LOCAL`: resolve as called, and do not put libgd's symbols
/// in the global namespace where they could satisfy somebody else's undefined
/// reference.
const int RtldLazyLocal = 0x00001;

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
bool SniffFormat(byte[] data, ImageFormat* found)
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
