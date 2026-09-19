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

// gdi32.dll, declared and nothing else.
//
// Declarations cost nothing, so this module needs no library on its own; a
// program that *calls* one of them wants `-l gdi32`, or `Win32.Drawing`, which
// names it with a pragma.
//
// It imports `Win32.User32` for `POINT` and `SIZE`, which are windef.h types
// declared there.
//
// GDI's ownership rule is the thing to get right, and no binding can enforce
// it: every object `Create...` returns must be selected *out* of the device
// context before it is deleted, because a selected object cannot be deleted and
// the leak is silent. A stock object from `GetStockObject` must never be
// deleted at all.
module Win32.Gdi32;

import Win32.Handles;

#if WINDOWS

import Win32.User32;

// ================================================================== objects

public extern "C"
{
    HPEN    CreatePen(int style, int width, uint colour);
    HBRUSH  CreateSolidBrush(uint colour);
    HBRUSH  CreateHatchBrush(int style, uint colour);
    HFONT   CreateFontW(int height, int width, int escapement, int orientation,
                        int weight, uint italic, uint underline, uint strikeOut,
                        uint charSet, uint precision, uint clipPrecision,
                        uint quality, uint pitchAndFamily, char16* face);
    HGDIOBJ GetStockObject(int index);
    HGDIOBJ SelectObject(HDC dc, HGDIOBJ object);
    int     DeleteObject(HGDIOBJ object);
    int     GetObjectW(HGDIOBJ object, int size, void* buffer);
}

public const int PenSolid       = 0;
public const int PenDash        = 1;
public const int PenDot         = 2;
public const int PenDashDot     = 3;
public const int PenDashDotDot  = 4;
public const int PenNull        = 5;
public const int PenInsideFrame = 6;

public const int HatchHorizontal       = 0;
public const int HatchVertical         = 1;
public const int HatchForwardDiagonal  = 2;
public const int HatchBackwardDiagonal = 3;
public const int HatchCross            = 4;
public const int HatchDiagonalCross    = 5;

/// `GetStockObject` indices. A stock object is owned by the system and must
/// **not** be passed to `DeleteObject`.
public const int WhiteBrush     = 0;
public const int LightGrayBrush = 1;
public const int GrayBrush      = 2;
public const int DarkGrayBrush  = 3;
public const int BlackBrush     = 4;
public const int NullBrush      = 5;
public const int WhitePen       = 6;
public const int BlackPen       = 7;
public const int NullPen        = 8;
public const int SystemFont     = 13;
public const int DefaultGuiFont = 17;

/// `CreateFontW`'s weight.
public const int FontThin     = 100;
public const int FontLight    = 300;
public const int FontNormal   = 400;
public const int FontSemiBold = 600;
public const int FontBold     = 700;
public const int FontHeavy    = 900;

public const uint DefaultCharSet   = 1u;
public const uint DefaultQuality   = 0u;
public const uint ClearTypeQuality = 5u;
public const uint DefaultPitch     = 0u;

// ================================================================== drawing

public extern "C"
{
    int  MoveToEx(HDC dc, int x, int y, Point* previous);
    int  LineTo(HDC dc, int x, int y);
    int  Rectangle(HDC dc, int left, int top, int right, int bottom);
    int  Ellipse(HDC dc, int left, int top, int right, int bottom);
    int  RoundRect(HDC dc, int left, int top, int right, int bottom,
                   int cornerWidth, int cornerHeight);
    int  Polygon(HDC dc, Point* points, int count);
    int  Polyline(HDC dc, Point* points, int count);
    int  Arc(HDC dc, int left, int top, int right, int bottom,
             int startX, int startY, int endX, int endY);
    uint SetPixel(HDC dc, int x, int y, uint colour);
    uint GetPixel(HDC dc, int x, int y);
    int  PatBlt(HDC dc, int x, int y, int width, int height, uint operation);
    int  BitBlt(HDC target, int x, int y, int width, int height,
                HDC source, int sourceX, int sourceY, uint operation);
    int  StretchBlt(HDC target, int x, int y, int width, int height,
                    HDC source, int sourceX, int sourceY,
                    int sourceWidth, int sourceHeight, uint operation);
}

/// Raster operations, for `BitBlt` and friends.
public const uint SrcCopy    = 0x00CC0020u;
public const uint SrcPaint   = 0x00EE0086u;
public const uint SrcAnd     = 0x008800C6u;
public const uint SrcInvert  = 0x00660046u;
public const uint NotSrcCopy = 0x00330008u;
public const uint Blackness  = 0x00000042u;
public const uint Whiteness  = 0x00FF0062u;
public const uint PatCopy    = 0x00F00021u;

// ===================================================================== text

public extern "C"
{
    int  TextOutW(HDC dc, int x, int y, char16* text, int length);
    int  GetTextExtentPoint32W(HDC dc, char16* text, int length, Size* size);
    uint SetTextColor(HDC dc, uint colour);
    uint GetTextColor(HDC dc);
    uint SetBkColor(HDC dc, uint colour);
    int  SetBkMode(HDC dc, int mode);
    uint SetTextAlign(HDC dc, uint align);
}

/// `SetBkMode`. `Transparent` is what a caller drawing text over a picture
/// almost always means.
public const int TransparentBackground = 1;
public const int OpaqueBackground      = 2;

public const uint TextAlignLeft     = 0u;
public const uint TextAlignRight    = 2u;
public const uint TextAlignCenter   = 6u;
public const uint TextAlignTop      = 0u;
public const uint TextAlignBottom   = 8u;
public const uint TextAlignBaseline = 24u;

// ================================================================== bitmaps

public extern "C"
{
    HDC     CreateCompatibleDC(HDC dc);
    HBITMAP CreateCompatibleBitmap(HDC dc, int width, int height);
    int     DeleteDC(HDC dc);
    int     GetDeviceCaps(HDC dc, int index);
    int     SaveDC(HDC dc);
    int     RestoreDC(HDC dc, int state);
}

/// A device-independent bitmap's description.
///
/// `Height` is signed and the sign is the whole point: a positive one means
/// the rows are stored bottom-up, which is the DIB's own ancient convention,
/// and a negative one means top-down, which is how every decoder in the world
/// hands pixels over. Writing the negative is what turns a copy into a
/// straight `memcpy` rather than a loop that walks one of the two backwards.
public struct BitmapInfoHeader
{
    public uint Size;
    public int  Width;
    public int  Height;
    public ushort Planes;
    public ushort BitCount;
    public uint Compression;
    public uint ImageByteLength;
    public int  PixelsPerMeterX;
    public int  PixelsPerMeterY;
    public uint ColoursUsed;
    public uint ColoursImportant;
}

/// A header and its palette. At 32 bits a pixel there is no palette, so this
/// is the header and one unused entry -- which is what `BITMAPINFO` is in the
/// header too, and why passing a bare `BitmapInfoHeader*` is the usual way
/// this is called.
public struct BitmapInfo
{
    public BitmapInfoHeader Header;
    public uint FirstColour;
}

public extern "C"
{
    /// Makes a DIB and hands back a pointer to the pixels it owns.
    ///
    /// The bits belong to the bitmap: they are valid until `DeleteObject`, and
    /// must not be freed. `GdiFlush` is required before reading back anything
    /// GDI drew into them, and is not required for writing them before the
    /// bitmap is first used, which is what a decoder does.
    HBITMAP CreateDIBSection(HDC dc, BitmapInfo* info, uint usage,
                             void** bits, void* section, uint offset);
    int GdiFlush();
}

/// How two pictures are combined, for `GdiAlphaBlend`.
///
/// `SourceConstantAlpha` is a whole-picture opacity applied on top of whatever
/// the per-pixel alpha says; 255 means "use the pixels' own". `AlphaFormat` is
/// `AC_SRC_ALPHA` when the source has a per-pixel alpha channel and zero when
/// it does not, and getting that wrong is invisible in one direction and total
/// in the other: claiming an alpha channel a bitmap has not got reads whatever
/// is in the fourth byte, which for a `.bmp` is zero, which is transparent.
public struct BlendFunction
{
    public byte Operation;
    public byte Flags;
    public byte SourceConstantAlpha;
    public byte AlphaFormat;
}

public extern "C"
{
    /// `AlphaBlend`, under the name gdi32 exports it by.
    ///
    /// **`GdiAlphaBlend` rather than `AlphaBlend`**, which is the same function:
    /// the documented name lives in `msimg32.dll`, whose entire content is
    /// forwarders, and gdi32 has exported this one since Windows 2000. Naming
    /// it here means nothing has to link a second library for a picture with
    /// transparency in it.
    ///
    /// **The source must be premultiplied** -- each colour already scaled by
    /// its own alpha. Given straight colour it lightens every partly
    /// transparent pixel, which reads as a halo round every icon rather than
    /// as an obvious failure.
    int GdiAlphaBlend(HDC destination, int x, int y, int width, int height,
                      HDC source, int sourceX, int sourceY,
                      int sourceWidth, int sourceHeight, BlendFunction blend);
}

/// `AC_SRC_OVER`, the only blend operation there is.
public const byte BlendSourceOver = 0;

// ---------------------------------------------------------------- gradients

/// `TRIVERTEX`: one corner of a gradient, with its colour and where it is.
///
/// **The channels are sixteen bits and the high byte is the one that shows.**
/// A `COLOR16` runs 0 to 65535, so an ordinary 8-bit channel goes in shifted
/// up by eight. Passing it unshifted gives a ramp between two almost-black
/// corners, which reads as the call having failed rather than as a scale being
/// wrong by a factor of 257.
public struct TriVertex
{
    public int X;
    public int Y;
    public ushort Red;
    public ushort Green;
    public ushort Blue;
    public ushort Alpha;
}

/// `GRADIENT_RECT`: which two of the vertices are one rectangle's corners.
public struct GradientRect
{
    public uint UpperLeft;
    public uint LowerRight;
}

/// `GRADIENT_FILL_RECT_H` and `_V`: across, and down.
public const uint GradientFillRectH = 0u;
public const uint GradientFillRectV = 1u;

public extern "C"
{
    /// `GradientFill`, under the name gdi32 exports it by -- the same
    /// arrangement `GdiAlphaBlend` above explains, and for the same reason:
    /// the documented name is in `msimg32.dll`, which is forwarders and
    /// nothing else.
    ///
    /// `meshes` is an array of `GradientRect` for the two rectangle modes and
    /// of triangles for the third, which is why it is untyped here.
    int GdiGradientFill(HDC target, TriVertex* vertices, uint vertexCount,
                        void* meshes, uint meshCount, uint mode);
}
/// `AC_SRC_ALPHA`: the source carries a per-pixel alpha channel.
public const byte BlendSourceAlpha = 1;

/// `BI_RGB`: no compression. At 32 bits a pixel the bytes of each are blue,
/// green, red and then one GDI itself ignores -- which is what makes a
/// straight alpha channel something a caller has to composite rather than
/// something `BitBlt` honours.
public const uint BitmapCompressionRgb = 0u;

/// `DIB_RGB_COLORS`, as against palette indices.
public const uint DibRgbColours = 0u;

public const int DeviceCapsHorizontalPixels = 8;
public const int DeviceCapsVerticalPixels   = 10;
public const int DeviceCapsBitsPerPixel     = 12;
public const int DeviceCapsLogicalPixelsX   = 88;
public const int DeviceCapsLogicalPixelsY   = 90;

// ========================================================= origin and clipping
//
// What a control drawn inside another needs: everything it draws moved to its
// own corner, and nothing it draws allowed outside it. `SaveDC` and `RestoreDC`
// above are what put both back in one call.

public extern "C"
{
    /// Moves the origin all drawing is measured from. The previous origin is
    /// written to `previous`, which may be null.
    int SetViewportOrgEx(HDC dc, int x, int y, Point* previous);
    int GetViewportOrgEx(HDC dc, Point* origin);
    /// Moves it by a delta rather than to a place, which is what nesting wants.
    int OffsetViewportOrgEx(HDC dc, int dx, int dy, Point* previous);

    /// Narrows the clip to the part of it inside this rectangle. Only ever
    /// narrows: there is no call that widens one, which is what `SaveDC` and
    /// `RestoreDC` are for.
    int IntersectClipRect(HDC dc, int left, int top, int right, int bottom);
    int ExcludeClipRect(HDC dc, int left, int top, int right, int bottom);
    /// The smallest rectangle holding the whole clip.
    int GetClipBox(HDC dc, Rect* bounds);
}

/// What `GetClipBox` answers.
public const int ClipError       = 0;
public const int ClipEmpty       = 1;
public const int ClipSimple      = 2;
public const int ClipComplex     = 3;

#endif
