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
#if WINDOWS
import Win32;
import Win32.Handles;
import Win32.Kernel32;
import Win32.User32;
import Win32.Gdi32;

// ===================================================================== font

/// A `HFONT`, made once for a `Font` and deleted when the last reference to it
/// goes.
public class FontBackend : IFontBackend
{
    HFONT _font;

    public FontBackend(Font wanted)
    {
        // A negative height is a *character* height rather than a cell height,
        // which is what a point size means and what every font dialog reports.
        // The 72 is points per inch and `DeviceCapsLogicalPixelsY` is the screen's real DPI,
        // so this is the one line that makes a 10pt font 10pt on any monitor.
        HDC screen = GetDC(null);
        int dpi = GetDeviceCaps(screen, DeviceCapsLogicalPixelsY);
        ReleaseDC(null, screen);
        if (dpi <= 0)
            dpi = 96;

        int height = -(wanted.Size * dpi / 72);
        int weight = wanted.Bold ? FontBold : FontNormal;

        _font = CreateFontW(height, 0, 0, 0, weight,
                           (uint)(wanted.Italic ? 1 : 0),
                           (uint)(wanted.Underline ? 1 : 0),
                           (uint)(wanted.Strikeout ? 1 : 0),
                           DefaultCharSet, 0u, 0u, ClearTypeQuality, DefaultPitch,
                           wanted.Family.ToUtf16().ToPointer());
    }

    ~FontBackend()
    {
        if (_font != null)
        {
            DeleteObject((HGDIOBJ)(void*)_font);
            _font = null;
        }
    }

    public nuint Handle => (nuint)(void*)_font;

    /// The font as GDI wants it, for the drawing code in this module.
    public HFONT Native => _font;
}

// ================================================================= graphics

/// `IGraphicsBackend` over a device context.
///
/// **It does not own the context.** One of these is made around the `HDC` a
/// `WM_PAINT` lent, and is thrown away when the paint ends; releasing the
/// context is the caller's business, because the caller is what called
/// `BeginPaint` and is the only thing that can call the matching `EndPaint`.
public class GraphicsBackend : IGraphicsBackend
{
    HDC _dc;
    FRect _clip;

    public GraphicsBackend(HDC context, FRect clipped)
    {
        _dc = context;
        _clip = clipped;
    }

    public FRect ClipBounds => _clip;

    /// `SaveDC` answers a token that puts back the clip *and* the origin
    /// together, which is exactly the pair this changes -- so there is nothing
    /// to restore by hand and no way to restore one and forget the other.
    public int PushLayer(FRect bounds)
    {
        int token = SaveDC(_dc);
        IntersectClipRect(_dc, bounds.Left, bounds.Top, bounds.Right, bounds.Bottom);
        OffsetViewportOrgEx(_dc, bounds.X, bounds.Y, null);
        return token;
    }

    public void PopLayer(int token) => RestoreDC(_dc, token);

    public void Clear(Color colour)
    {
        Rect whole = ToRect(_clip);
        HBRUSH brush = CreateSolidBrush(ToColorRef(colour));
        FillRect(_dc, &whole, brush);
        DeleteObject((HGDIOBJ)(void*)brush);
    }

    /// Selects a pen made for this call, runs the body, and puts back what was
    /// there. Every outline call goes through here so that none of them can
    /// forget the second half.
    HPEN UsePen(Pen pen)
    {
        int style = PenStyleOf(pen.Style);
        HPEN made = CreatePen(style, pen.Width, ToColorRef(pen.Color));
        SelectObject(_dc, (HGDIOBJ)(void*)made);
        return made;
    }

    void DropPen(HPEN made)
    {
        SelectObject(_dc, GetStockObject(BlackPen));
        DeleteObject((HGDIOBJ)(void*)made);
    }

    HBRUSH UseBrush(Brush brush)
    {
        HBRUSH made = CreateSolidBrush(ToColorRef(brush.Color));
        SelectObject(_dc, (HGDIOBJ)(void*)made);
        return made;
    }

    void DropBrush(HBRUSH made)
    {
        SelectObject(_dc, GetStockObject(WhiteBrush));
        DeleteObject((HGDIOBJ)(void*)made);
    }

    int PenStyleOf(PenStyle style)
    {
        if (style == PenStyle.Dash)
            return PenDash;
        if (style == PenStyle.Dot)
            return PenDot;
        if (style == PenStyle.DashDot)
            return PenDashDot;
        if (style == PenStyle.None)
            return PenNull;
        return PenSolid;
    }

    public void DrawLine(Pen pen, int x1, int y1, int x2, int y2)
    {
        HPEN made = UsePen(pen);
        MoveToEx(_dc, x1, y1, null);
        LineTo(_dc, x2, y2);
        DropPen(made);
    }

    public void DrawRectangle(Pen pen, FRect bounds)
    {
        HPEN made = UsePen(pen);
        // A hollow brush, so `Rectangle` outlines rather than filling: GDI's
        // shape calls always do both, and this is how "outline only" is said.
        HGDIOBJ wasBrush = SelectObject(_dc, GetStockObject(NullBrush));
        Rectangle(_dc, bounds.Left, bounds.Top, bounds.Right, bounds.Bottom);
        SelectObject(_dc, wasBrush);
        DropPen(made);
    }

    public void FillRectangle(Brush brush, FRect bounds)
    {
        if (brush.IsGradient)
        {
            FillGradient(brush, bounds);
            return;
        }

        Rect r = ToRect(bounds);
        HBRUSH made = CreateSolidBrush(ToColorRef(brush.Color));
        FillRect(_dc, &r, made);
        DeleteObject((HGDIOBJ)(void*)made);
    }

    /// A two-corner ramp, across or down.
    ///
    /// `GdiGradientFill` wants the two opposite corners as vertices and a mesh
    /// naming them, which for one rectangle is two of each -- more ceremony
    /// than the call deserves, and the reason this is not written inline.
    void FillGradient(Brush brush, FRect bounds)
    {
        TriVertex[2] corners;
        corners[0u] = Corner(bounds.Left, bounds.Top, brush.Color);
        corners[1u] = Corner(bounds.Right, bounds.Bottom, brush.EndColor);

        GradientRect mesh;
        mesh.UpperLeft = 0u;
        mesh.LowerRight = 1u;

        uint mode = brush.Style == BrushStyle.HorizontalGradient
                  ? GradientFillRectH
                  : GradientFillRectV;

        GdiGradientFill(_dc, &corners[0u], 2u, (void*)&mesh, 1u, mode);
    }

    /// One corner, with an 8-bit colour widened to the sixteen bits a
    /// `TRIVERTEX` holds -- see the note where it is declared.
    static TriVertex Corner(int x, int y, Color colour)
    {
        TriVertex made;
        made.X = x;
        made.Y = y;
        made.Red   = (ushort)((uint)colour.R << 8);
        made.Green = (ushort)((uint)colour.G << 8);
        made.Blue  = (ushort)((uint)colour.B << 8);
        made.Alpha = (ushort)0;
        return made;
    }

    public void DrawEllipse(Pen pen, FRect bounds)
    {
        HPEN made = UsePen(pen);
        HGDIOBJ wasBrush = SelectObject(_dc, GetStockObject(NullBrush));
        Ellipse(_dc, bounds.Left, bounds.Top, bounds.Right, bounds.Bottom);
        SelectObject(_dc, wasBrush);
        DropPen(made);
    }

    public void FillEllipse(Brush brush, FRect bounds)
    {
        HBRUSH made = UseBrush(brush);
        HPEN pen = CreatePen(PenSolid, 1, ToColorRef(brush.Color));
        HGDIOBJ wasPen = SelectObject(_dc, (HGDIOBJ)(void*)pen);
        Ellipse(_dc, bounds.Left, bounds.Top, bounds.Right, bounds.Bottom);
        SelectObject(_dc, wasPen);
        DeleteObject((HGDIOBJ)(void*)pen);
        DropBrush(made);
    }

    /// Copies the points into the shape GDI wants. Two structures called
    /// `Point` that differ only in which module declared them, so the copy is
    /// a loop rather than a cast.
    Win32.User32.Point[] Native(FPoint[] points)
    {
        var native = new Win32.User32.Point[points.Length];
        for (nuint i = 0u; i < points.Length; i++)
        {
            Win32.User32.Point one;
            one.X = points[i].X;
            one.Y = points[i].Y;
            native[i] = one;
        }
        return native;
    }

    public void DrawPolygon(Pen pen, FPoint[] points)
    {
        var native = Native(points);
        HPEN made = UsePen(pen);
        HGDIOBJ wasBrush = SelectObject(_dc, GetStockObject(NullBrush));
        Polygon(_dc, &native[0u], (int)points.Length);
        SelectObject(_dc, wasBrush);
        DropPen(made);
    }

    public void FillPolygon(Brush brush, FPoint[] points)
    {
        var native = Native(points);
        HBRUSH made = UseBrush(brush);
        Polygon(_dc, &native[0u], (int)points.Length);
        DropBrush(made);
    }

    public void DrawPolyline(Pen pen, FPoint[] points)
    {
        var native = Native(points);
        HPEN made = UsePen(pen);
        Polyline(_dc, &native[0u], (int)points.Length);
        DropPen(made);
    }

    public void DrawString(String text, Font font, Color colour, int x, int y)
    {
        var wide = text.ToUtf16();
        HGDIOBJ wasFont = SelectObject(_dc, (HGDIOBJ)(nuint)font.Resource.Handle);
        uint wasColour = SetTextColor(_dc, ToColorRef(colour));
        int wasMode = SetBkMode(_dc, TransparentBackground);
        TextOutW(_dc, x, y, wide.ToPointer(), (int)wide.UnitCount());
        SetBkMode(_dc, wasMode);
        SetTextColor(_dc, wasColour);
        SelectObject(_dc, wasFont);
    }

    public void DrawStringIn(String text, Font font, Color colour,
                             FRect bounds, TextFormat format)
    {
        var wide = text.ToUtf16();
        Rect r = ToRect(bounds);

        uint flags = 0u;
        if (format.Horizontal == HorizontalAlignment.Center)
        {
            flags = flags | DtCenter;
        }
        else if (format.Horizontal == HorizontalAlignment.Right)
        {
            flags = flags | DtRight;
        }

        if (format.Wrap)
        {
            flags = flags | DtWordBreak;
        }
        else
        {
            flags = flags | DtSingleLine;
            // Vertical centring is a single-line-only feature of DrawText, so
            // it can only be asked for here.
            if (format.Vertical == VerticalAlignment.Middle)
            {
                flags = flags | DtVerticalCenter;
            }
            else if (format.Vertical == VerticalAlignment.Bottom)
            {
                flags = flags | DtBottom;
            }
        }

        HGDIOBJ wasFont = SelectObject(_dc, (HGDIOBJ)(nuint)font.Resource.Handle);
        uint wasColour = SetTextColor(_dc, ToColorRef(colour));
        int wasMode = SetBkMode(_dc, TransparentBackground);
        DrawTextW(_dc, wide.ToPointer(), (int)wide.UnitCount(), &r, flags);
        SetBkMode(_dc, wasMode);
        SetTextColor(_dc, wasColour);
        SelectObject(_dc, wasFont);
    }

    /// Draws a bitmap through a memory device context, which is the only way
    /// GDI will copy one: a bitmap is not something a `HDC` can be told to
    /// draw, it is something selected into a second `HDC` and blitted from.
    public void DrawBitmap(IBitmapBackend picture, FPoint at)
    {
        Blit(picture, Area(at.X, at.Y, picture.Width, picture.Height), false);
    }

    public void DrawBitmapIn(IBitmapBackend picture, FRect into)
    {
        Blit(picture, into, true);
    }

    void Blit(IBitmapBackend picture, FRect into, bool scaled)
    {
        HBITMAP bitmap = (HBITMAP)(void*)picture.Handle;
        if (bitmap == null)
            return;

        HDC memory = CreateCompatibleDC(_dc);
        if (memory == null)
            return;
        HGDIOBJ was = SelectObject(memory, (HGDIOBJ)(void*)bitmap);

        if (picture.HasAlpha)
        {
            // `GdiAlphaBlend` scales as well as blends, so there is no
            // stretched-versus-not branch here: the destination rectangle is
            // the source rectangle when nothing is scaling.
            BlendFunction blend;
            blend.Operation = BlendSourceOver;
            blend.Flags = 0;
            blend.SourceConstantAlpha = 255;
            blend.AlphaFormat = BlendSourceAlpha;

            GdiAlphaBlend(_dc, into.X, into.Y, into.Width, into.Height,
                          memory, 0, 0, picture.Width, picture.Height, blend);
        }
        else if (scaled)
        {
            StretchBlt(_dc, into.X, into.Y, into.Width, into.Height,
                       memory, 0, 0, picture.Width, picture.Height, SrcCopy);
        }
        else
        {
            BitBlt(_dc, into.X, into.Y, into.Width, into.Height, memory, 0, 0, SrcCopy);
        }

        SelectObject(memory, was);
        DeleteDC(memory);
    }

    public FSize MeasureString(String text, Font font)
    {
        var wide = text.ToUtf16();
        HGDIOBJ wasFont = SelectObject(_dc, (HGDIOBJ)(nuint)font.Resource.Handle);
        Win32.User32.Size measured;
        GetTextExtentPoint32W(_dc, wide.ToPointer(), (int)wide.UnitCount(), &measured);
        SelectObject(_dc, wasFont);
        return Extent(measured.Width, measured.Height);
    }
}

/// Measures text without a window to measure it in.
///
/// A control asked for its preferred size before it is on screen still has to
/// answer, and the screen's own device context is what every Windows program
/// uses for that. Released immediately, because a screen DC comes from a pool
/// of five and a program that keeps them stops being able to draw.
public FSize MeasureWithFont(String text, Font font)
{
    HDC screen = GetDC(null);
    var surface = new GraphicsBackend(screen, Area(0, 0, 0, 0));
    var measured = surface.MeasureString(text, font);
    ReleaseDC(null, screen);
    return measured;
}

#endif
