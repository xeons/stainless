// Stainless - an experimental systems language.
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

// gdi32.dll, declared and nothing else. **Link with `-l gdi32`.**
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

#if WINDOWS

import Win32.User32;

// ================================================================== objects

public extern "C" {
    void* CreatePen(int style, int width, uint colour);
    void* CreateSolidBrush(uint colour);
    void* CreateHatchBrush(int style, uint colour);
    void* CreateFontW(int height, int width, int escapement, int orientation,
                      int weight, uint italic, uint underline, uint strikeOut,
                      uint charSet, uint precision, uint clipPrecision,
                      uint quality, uint pitchAndFamily, ushort* face);
    void* GetStockObject(int index);
    void* SelectObject(void* dc, void* object);
    int   DeleteObject(void* object);
    int   GetObjectW(void* object, int size, void* buffer);
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

public extern "C" {
    int  MoveToEx(void* dc, int x, int y, Point* previous);
    int  LineTo(void* dc, int x, int y);
    int  Rectangle(void* dc, int left, int top, int right, int bottom);
    int  Ellipse(void* dc, int left, int top, int right, int bottom);
    int  RoundRect(void* dc, int left, int top, int right, int bottom,
                   int cornerWidth, int cornerHeight);
    int  Polygon(void* dc, Point* points, int count);
    int  Polyline(void* dc, Point* points, int count);
    int  Arc(void* dc, int left, int top, int right, int bottom,
             int startX, int startY, int endX, int endY);
    uint SetPixel(void* dc, int x, int y, uint colour);
    uint GetPixel(void* dc, int x, int y);
    int  PatBlt(void* dc, int x, int y, int width, int height, uint operation);
    int  BitBlt(void* target, int x, int y, int width, int height,
                void* source, int sourceX, int sourceY, uint operation);
    int  StretchBlt(void* target, int x, int y, int width, int height,
                    void* source, int sourceX, int sourceY,
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

public extern "C" {
    int  TextOutW(void* dc, int x, int y, ushort* text, int length);
    int  GetTextExtentPoint32W(void* dc, ushort* text, int length, Size* size);
    uint SetTextColor(void* dc, uint colour);
    uint GetTextColor(void* dc);
    uint SetBkColor(void* dc, uint colour);
    int  SetBkMode(void* dc, int mode);
    uint SetTextAlign(void* dc, uint align);
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

public extern "C" {
    void* CreateCompatibleDC(void* dc);
    void* CreateCompatibleBitmap(void* dc, int width, int height);
    int   DeleteDC(void* dc);
    int   GetDeviceCaps(void* dc, int index);
    int   SaveDC(void* dc);
    int   RestoreDC(void* dc, int state);
}

public const int DeviceCapsHorizontalPixels = 8;
public const int DeviceCapsVerticalPixels   = 10;
public const int DeviceCapsBitsPerPixel     = 12;
public const int DeviceCapsLogicalPixelsX   = 88;
public const int DeviceCapsLogicalPixelsY   = 90;

#endif
