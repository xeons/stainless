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

// Drawing into a device context.
//
// A convenience layer over `Win32.Gdi32`. **Link with `-l gdi32`** (and
// `-l user32`, since a device context comes from a window).
//
// GDI's ownership rule is the thing to get right, and nothing here can enforce
// it: every object `Create...` returns must be selected *out* of the device
// context before it is deleted, and a stock object must never be deleted at
// all. The shape that always works is to keep what `SelectObject` gave back and
// put it there again:
//
// ```csharp
// void* pen = CreatePen(PenSolid, 2, Colour(255u, 0u, 0u));
// void* previous = SelectObject(dc, pen);
// // ... draw ...
// SelectObject(dc, previous);
// DeleteObject(pen);
// ```
//
// `OffScreen` below is the one place that pairing is done for you, because
// double buffering is where it is most often got wrong.
module Win32.Drawing;

#if WINDOWS

import Win32;
import Win32.Gdi32;
import Win32.User32;

// =================================================================== colour

/// A `COLORREF` is 0x00BBGGRR — blue in the *high* byte, which is the opposite
/// of the order the components are usually written in.
public uint Colour(byte red, byte green, byte blue) {
    return (uint)red | ((uint)green << 8) | ((uint)blue << 16);
}

public byte Red(uint colour)   { return (byte)(colour & 0xFFu); }
public byte Green(uint colour) { return (byte)((colour >> 8) & 0xFFu); }
public byte Blue(uint colour)  { return (byte)((colour >> 16) & 0xFFu); }

public const uint Black    = 0x000000u;
public const uint White    = 0xFFFFFFu;
public const uint RedInk   = 0x0000FFu;
public const uint GreenInk = 0x008000u;
public const uint BlueInk  = 0xFF0000u;

// ===================================================================== text

/// A font at a given pixel height. Negative heights mean "character height"
/// rather than "cell height", which is what a caller thinking in point sizes
/// wants; this takes the height as written and does not negate it.
public void* CreateFont(String face, int height, int weight, bool italic) {
    return CreateFontW(height, 0, 0, 0, weight, (uint)(italic ? 1 : 0), 0u, 0u,
                       DefaultCharSet, 0u, 0u, ClearTypeQuality, DefaultPitch,
                       face.ToUtf16().ToPointer());
}

/// Draws text at a point, with the current font, colour and alignment.
public bool DrawTextAt(void* dc, int x, int y, String text) {
    var wide = text.ToUtf16();
    return Win32.Succeeded(TextOutW(dc, x, y, wide.ToPointer(), (int)wide.UnitCount()));
}

/// How wide and tall the text would be in the device context's current font.
public Size MeasureText(void* dc, String text) {
    var wide = text.ToUtf16();
    Size size;
    size.Width = 0;
    size.Height = 0;
    GetTextExtentPoint32W(dc, wide.ToPointer(), (int)wide.UnitCount(), &size);
    return size;
}

// ============================================================ double buffer

/// An off-screen device context the same shape as another, with a bitmap
/// already selected into it. Double buffering is this plus one `BitBlt`.
///
/// The caller owns all of it and must call `DestroyOffScreen`, which puts back
/// what was there and then deletes both in the order GDI requires.
public struct OffScreen {
    public void* Dc;
    public void* Bitmap;
    public void* Previous;
}

public OffScreen CreateOffScreen(void* dc, int width, int height) {
    OffScreen buffer;
    buffer.Dc = CreateCompatibleDC(dc);
    buffer.Bitmap = CreateCompatibleBitmap(dc, width, height);
    buffer.Previous = SelectObject(buffer.Dc, buffer.Bitmap);
    return buffer;
}

public void DestroyOffScreen(OffScreen buffer) {
    SelectObject(buffer.Dc, buffer.Previous);
    DeleteObject(buffer.Bitmap);
    DeleteDC(buffer.Dc);
}

/// Fills a rectangle with one colour, creating and destroying the brush.
///
/// Convenient rather than fast: a caller filling many rectangles in the same
/// colour should make one brush and keep it.
public bool Fill(void* dc, Rect* rectangle, uint colour) {
    void* brush = CreateSolidBrush(colour);
    bool filled = Win32.Succeeded(FillRect(dc, rectangle, brush));
    DeleteObject(brush);
    return filled;
}

#endif
