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

// GDI behind `Graphics`, and a font that is made once.
//
// **Every GDI object this creates, it deletes.** A device context holds one pen
// and one brush at a time and hands back what was there; leaking either is the
// classic GDI failure, and it does not announce itself -- a program simply runs
// out of handles some minutes later. So each drawing call here selects, draws,
// selects the old object back, and deletes what it made. That is three extra
// calls per primitive and it is the only arrangement that cannot leak.
//
// A cache keyed by colour and width would remove most of them, and is the
// obvious next step; it is not here because a cache that is wrong leaks in a way
// that is much harder to find than the thing it replaced.
module Forms.Platform.Win32;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;
import Win32;
import Win32.Handles;
import Win32.Kernel32;
import Win32.User32;
import Win32.Gdi32;

#if WINDOWS

// ===================================================================== font

/// A `HFONT`, made once for a `Font` and deleted when the last reference to it
/// goes.
public class FontBackend : IFontBackend {
    HFONT font;

    public FontBackend(Font wanted) {
        // A negative height is a *character* height rather than a cell height,
        // which is what a point size means and what every font dialog reports.
        // The 72 is points per inch and `DeviceCapsLogicalPixelsY` is the screen's real DPI,
        // so this is the one line that makes a 10pt font 10pt on any monitor.
        HDC screen = GetDC(null);
        int dpi = GetDeviceCaps(screen, DeviceCapsLogicalPixelsY);
        ReleaseDC(null, screen);
        if (dpi <= 0) { dpi = 96; }

        int height = -(wanted.Size * dpi / 72);
        int weight = wanted.Bold ? FontBold : FontNormal;

        font = CreateFontW(height, 0, 0, 0, weight,
                           (uint)(wanted.Italic ? 1 : 0),
                           (uint)(wanted.Underline ? 1 : 0),
                           (uint)(wanted.Strikeout ? 1 : 0),
                           DefaultCharSet, 0u, 0u, ClearTypeQuality, DefaultPitch,
                           wanted.Family.ToUtf16().ToPointer());
    }

    ~FontBackend() {
        if (font != null) {
            DeleteObject((HGDIOBJ)(void*)font);
            font = null;
        }
    }

    public nuint Handle() { return (nuint)(void*)font; }

    /// The font as GDI wants it, for the drawing code in this module.
    public HFONT Native() { return font; }
}

// ================================================================= graphics

/// `IGraphicsBackend` over a device context.
///
/// **It does not own the context.** One of these is made around the `HDC` a
/// `WM_PAINT` lent, and is thrown away when the paint ends; releasing the
/// context is the caller's business, because the caller is what called
/// `BeginPaint` and is the only thing that can call the matching `EndPaint`.
public class GraphicsBackend : IGraphicsBackend {
    HDC   dc;
    FRect clip;

    public GraphicsBackend(HDC context, FRect clipped) {
        dc = context;
        clip = clipped;
    }

    public FRect ClipBounds() { return clip; }

    public void Clear(Color colour) {
        Rect whole = ToRect(clip);
        HBRUSH brush = CreateSolidBrush(ToColorRef(colour));
        FillRect(dc, &whole, brush);
        DeleteObject((HGDIOBJ)(void*)brush);
    }

    /// Selects a pen made for this call, runs the body, and puts back what was
    /// there. Every outline call goes through here so that none of them can
    /// forget the second half.
    HPEN UsePen(Pen pen) {
        int style = PenStyleOf(pen.Style);
        HPEN made = CreatePen(style, pen.Width, ToColorRef(pen.Color));
        SelectObject(dc, (HGDIOBJ)(void*)made);
        return made;
    }

    void DropPen(HPEN made) {
        SelectObject(dc, GetStockObject(BlackPen));
        DeleteObject((HGDIOBJ)(void*)made);
    }

    HBRUSH UseBrush(Brush brush) {
        HBRUSH made = CreateSolidBrush(ToColorRef(brush.Color));
        SelectObject(dc, (HGDIOBJ)(void*)made);
        return made;
    }

    void DropBrush(HBRUSH made) {
        SelectObject(dc, GetStockObject(WhiteBrush));
        DeleteObject((HGDIOBJ)(void*)made);
    }

    int PenStyleOf(PenStyle style) {
        if (style == PenStyle.Dash)    { return PenDash; }
        if (style == PenStyle.Dot)     { return PenDot; }
        if (style == PenStyle.DashDot) { return PenDashDot; }
        if (style == PenStyle.None)    { return PenNull; }
        return PenSolid;
    }

    public void DrawLine(Pen pen, int x1, int y1, int x2, int y2) {
        HPEN made = UsePen(pen);
        MoveToEx(dc, x1, y1, null);
        LineTo(dc, x2, y2);
        DropPen(made);
    }

    public void DrawRectangle(Pen pen, FRect bounds) {
        HPEN made = UsePen(pen);
        // A hollow brush, so `Rectangle` outlines rather than filling: GDI's
        // shape calls always do both, and this is how "outline only" is said.
        HGDIOBJ wasBrush = SelectObject(dc, GetStockObject(NullBrush));
        Rectangle(dc, bounds.Left, bounds.Top, bounds.Right, bounds.Bottom);
        SelectObject(dc, wasBrush);
        DropPen(made);
    }

    public void FillRectangle(Brush brush, FRect bounds) {
        Rect r = ToRect(bounds);
        HBRUSH made = CreateSolidBrush(ToColorRef(brush.Color));
        FillRect(dc, &r, made);
        DeleteObject((HGDIOBJ)(void*)made);
    }

    public void DrawEllipse(Pen pen, FRect bounds) {
        HPEN made = UsePen(pen);
        HGDIOBJ wasBrush = SelectObject(dc, GetStockObject(NullBrush));
        Ellipse(dc, bounds.Left, bounds.Top, bounds.Right, bounds.Bottom);
        SelectObject(dc, wasBrush);
        DropPen(made);
    }

    public void FillEllipse(Brush brush, FRect bounds) {
        HBRUSH made = UseBrush(brush);
        HPEN pen = CreatePen(PenSolid, 1, ToColorRef(brush.Color));
        HGDIOBJ wasPen = SelectObject(dc, (HGDIOBJ)(void*)pen);
        Ellipse(dc, bounds.Left, bounds.Top, bounds.Right, bounds.Bottom);
        SelectObject(dc, wasPen);
        DeleteObject((HGDIOBJ)(void*)pen);
        DropBrush(made);
    }

    /// Copies the points into the shape GDI wants. Two structures called
    /// `Point` that differ only in which module declared them, so the copy is
    /// a loop rather than a cast.
    Win32.User32.Point[] Native(FPoint[] points) {
        var native = new Win32.User32.Point[points.Length];
        for (nuint i = 0u; i < points.Length; i += 1u) {
            Win32.User32.Point one;
            one.X = points[i].X;
            one.Y = points[i].Y;
            native[i] = one;
        }
        return native;
    }

    public void DrawPolygon(Pen pen, FPoint[] points) {
        var native = Native(points);
        HPEN made = UsePen(pen);
        HGDIOBJ wasBrush = SelectObject(dc, GetStockObject(NullBrush));
        Polygon(dc, &native[0u], (int)points.Length);
        SelectObject(dc, wasBrush);
        DropPen(made);
    }

    public void FillPolygon(Brush brush, FPoint[] points) {
        var native = Native(points);
        HBRUSH made = UseBrush(brush);
        Polygon(dc, &native[0u], (int)points.Length);
        DropBrush(made);
    }

    public void DrawPolyline(Pen pen, FPoint[] points) {
        var native = Native(points);
        HPEN made = UsePen(pen);
        Polyline(dc, &native[0u], (int)points.Length);
        DropPen(made);
    }

    public void DrawString(String text, Font font, Color colour, int x, int y) {
        var wide = text.ToUtf16();
        HGDIOBJ wasFont = SelectObject(dc, (HGDIOBJ)(nuint)font.Resource().Handle());
        uint wasColour = SetTextColor(dc, ToColorRef(colour));
        int wasMode = SetBkMode(dc, TransparentBackground);
        TextOutW(dc, x, y, wide.ToPointer(), (int)wide.UnitCount());
        SetBkMode(dc, wasMode);
        SetTextColor(dc, wasColour);
        SelectObject(dc, wasFont);
    }

    public void DrawStringIn(String text, Font font, Color colour,
                             FRect bounds, TextFormat format) {
        var wide = text.ToUtf16();
        Rect r = ToRect(bounds);

        uint flags = 0u;
        if (format.Horizontal == HorizontalAlignment.Center) { flags = flags | DtCenter; }
        else if (format.Horizontal == HorizontalAlignment.Right) { flags = flags | DtRight; }

        if (format.Wrap) {
            flags = flags | DtWordBreak;
        } else {
            flags = flags | DtSingleLine;
            // Vertical centring is a single-line-only feature of DrawText, so
            // it can only be asked for here.
            if (format.Vertical == VerticalAlignment.Middle) { flags = flags | DtVerticalCenter; }
            else if (format.Vertical == VerticalAlignment.Bottom) { flags = flags | DtBottom; }
        }

        HGDIOBJ wasFont = SelectObject(dc, (HGDIOBJ)(nuint)font.Resource().Handle());
        uint wasColour = SetTextColor(dc, ToColorRef(colour));
        int wasMode = SetBkMode(dc, TransparentBackground);
        DrawTextW(dc, wide.ToPointer(), (int)wide.UnitCount(), &r, flags);
        SetBkMode(dc, wasMode);
        SetTextColor(dc, wasColour);
        SelectObject(dc, wasFont);
    }

    public FSize MeasureString(String text, Font font) {
        var wide = text.ToUtf16();
        HGDIOBJ wasFont = SelectObject(dc, (HGDIOBJ)(nuint)font.Resource().Handle());
        Win32.User32.Size measured;
        GetTextExtentPoint32W(dc, wide.ToPointer(), (int)wide.UnitCount(), &measured);
        SelectObject(dc, wasFont);
        return Extent(measured.Width, measured.Height);
    }
}

/// Measures text without a window to measure it in.
///
/// A control asked for its preferred size before it is on screen still has to
/// answer, and the screen's own device context is what every Windows program
/// uses for that. Released immediately, because a screen DC comes from a pool
/// of five and a program that keeps them stops being able to draw.
public FSize MeasureWithFont(String text, Font font) {
    HDC screen = GetDC(null);
    var surface = new GraphicsBackend(screen, Area(0, 0, 0, 0));
    var measured = surface.MeasureString(text, font);
    ReleaseDC(null, screen);
    return measured;
}

#endif
