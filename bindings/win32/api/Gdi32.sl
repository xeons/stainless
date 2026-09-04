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

public extern "C" {
    HPEN    CreatePen(int style, int width, uint colour);
    HBRUSH  CreateSolidBrush(uint colour);
    HBRUSH  CreateHatchBrush(int style, uint colour);
    HFONT   CreateFontW(int height, int width, int escapement, int orientation,
                        int weight, uint italic, uint underline, uint strikeOut,
                        uint charSet, uint precision, uint clipPrecision,
                        uint quality, uint pitchAndFamily, ushort* face);
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

public extern "C" {
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

public extern "C" {
    int  TextOutW(HDC dc, int x, int y, ushort* text, int length);
    int  GetTextExtentPoint32W(HDC dc, ushort* text, int length, Size* size);
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

public extern "C" {
    HDC     CreateCompatibleDC(HDC dc);
    HBITMAP CreateCompatibleBitmap(HDC dc, int width, int height);
    int     DeleteDC(HDC dc);
    int     GetDeviceCaps(HDC dc, int index);
    int     SaveDC(HDC dc);
    int     RestoreDC(HDC dc, int state);
}

public const int DeviceCapsHorizontalPixels = 8;
public const int DeviceCapsVerticalPixels   = 10;
public const int DeviceCapsBitsPerPixel     = 12;
public const int DeviceCapsLogicalPixelsX   = 88;
public const int DeviceCapsLogicalPixelsY   = 90;

#endif
