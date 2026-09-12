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

// The drawing types: colours, geometry, fonts and the surface controls paint on.
//
// This is the LCL's `graphics.pp` re-cut to C#'s `System.Drawing`, because the
// two describe the same things and C#'s names are the ones a reader of this
// language already has. `TCanvas` is `Graphics`, `clBtnFace` is
// `SystemColors.Control`, and `TFont.Color` is gone -- colour belongs to the
// control that draws, not to the font it draws with, which is the one place
// C#'s arrangement is plainly better than Object Pascal's.
//
// **Geometry is a value, and so is a colour.** `Point`, `Size`, `Rectangle` and
// `Color` are `struct`s: copied by assignment, laid out like the C structs they
// correspond to, and free of reference counting. `Font`, `Pen`, `Brush` and
// `Graphics` are classes, because each owns a platform resource that must be
// released exactly once -- which is what ARC is for.
//
// Nothing here knows what platform it is on. `Graphics` holds an
// `IGraphicsBackend` from `Forms.Platform` and calls through it, so the same
// painting code reaches GDI on Windows and Cairo on GTK.
module Forms.Drawing;

import Standard.Collections;
import Forms.Platform;

// =================================================================== colour

/// A colour, as four bytes.
///
/// **Not the LCL's `TColor`.** That is a 32-bit integer in *BGR* order whose
/// high bit means "this is really a system colour index", so a `TColor` is
/// either a colour or a promise of one and no reader can tell which. Here a
/// `Color` is always four channels that are already resolved, and the system
/// colours live in `SystemColors` where they are looked up when asked for.
/// The BGR packing is a Windows detail, and belongs in the Windows backend.
public struct Color {
    public byte R;
    public byte G;
    public byte B;

    /// 255 is opaque and 0 is invisible. The Win32 backend ignores it outside
    /// the few places GDI understands alpha; it is here because the GTK one
    /// does not, and a type that gains a channel later gains it everywhere.
    public byte A;

    public static Color FromRgb(byte red, byte green, byte blue) {
        Color colour;
        colour.R = red;
        colour.G = green;
        colour.B = blue;
        colour.A = 255;
        return colour;
    }

    public static Color FromArgb(byte alpha, byte red, byte green, byte blue) {
        Color colour = Color.FromRgb(red, green, blue);
        colour.A = alpha;
        return colour;
    }

    /// Whether two colours are the same in every channel.
    ///
    /// A method rather than `==`, because a struct gets no operators unless
    /// they are written and equality on a colour is wanted rarely enough that
    /// the call site reads better spelled out.
    public bool Equals(Color other) {
        return R == other.R && G == other.G && B == other.B && A == other.A;
    }
}

/// The fixed colours, named as C# names them.
public static class Colors {
    public static readonly Color Transparent = Color.FromArgb(0, 0, 0, 0);
    public static readonly Color Black       = Color.FromRgb(0, 0, 0);
    public static readonly Color White       = Color.FromRgb(255, 255, 255);
    public static readonly Color Red         = Color.FromRgb(255, 0, 0);
    public static readonly Color Green       = Color.FromRgb(0, 128, 0);
    public static readonly Color Blue        = Color.FromRgb(0, 0, 255);
    public static readonly Color Yellow      = Color.FromRgb(255, 255, 0);
    public static readonly Color Gray        = Color.FromRgb(128, 128, 128);
    public static readonly Color LightGray   = Color.FromRgb(211, 211, 211);
    public static readonly Color DarkGray    = Color.FromRgb(64, 64, 64);
    public static readonly Color Navy        = Color.FromRgb(0, 0, 128);
    public static readonly Color Maroon      = Color.FromRgb(128, 0, 0);
    public static readonly Color Olive       = Color.FromRgb(128, 128, 0);
    public static readonly Color Purple      = Color.FromRgb(128, 0, 128);
    public static readonly Color Teal        = Color.FromRgb(0, 128, 128);
    public static readonly Color Silver      = Color.FromRgb(192, 192, 192);
}

// ================================================================= geometry

/// A position, in pixels, relative to whatever contains it.
public struct Point {
    public int X;
    public int Y;

    public static Point At(int x, int y) {
        Point point;
        point.X = x;
        point.Y = y;
        return point;
    }

    public static readonly Point Empty = Point.At(0, 0);

    public bool Equals(Point other) { return X == other.X && Y == other.Y; }
}

/// An extent, in pixels. Never negative in practice, though nothing enforces
/// it: a control constrained smaller than its border would otherwise have to
/// report something, and zero is the honest answer.
public struct Size {
    public int Width;
    public int Height;

    public static Size Of(int width, int height) {
        Size size;
        size.Width = width;
        size.Height = height;
        return size;
    }

    public static readonly Size Empty = Size.Of(0, 0);

    public bool IsEmpty => Width <= 0 || Height <= 0;

    public bool Equals(Size other) {
        return Width == other.Width && Height == other.Height;
    }
}

/// A rectangle held as a corner and an extent.
///
/// **Left/Top/Width/Height, not Left/Top/Right/Bottom.** Win32's `RECT` is the
/// second and the LCL's `TRect` follows it, which makes every resize two
/// subtractions and makes "move without resizing" a chance to get one of them
/// wrong. C#'s `Rectangle` is the first, a control's bounds are naturally a
/// position and a size, and the one place the other form is needed -- talking
/// to Win32 -- converts at the boundary where the difference is visible.
public struct Rectangle {
    public int X;
    public int Y;
    public int Width;
    public int Height;

    public static Rectangle Of(int x, int y, int width, int height) {
        Rectangle rectangle;
        rectangle.X = x;
        rectangle.Y = y;
        rectangle.Width = width;
        rectangle.Height = height;
        return rectangle;
    }

    public static Rectangle FromEdges(int left, int top, int right, int bottom) {
        return Rectangle.Of(left, top, right - left, bottom - top);
    }

    public static readonly Rectangle Empty = Rectangle.Of(0, 0, 0, 0);

    public int Left   => X;
    public int Top    => Y;
    public int Right  => X + Width;
    public int Bottom => Y + Height;

    public Point Location => Point.At(X, Y);
    public Size  Extent   => Size.Of(Width, Height);

    public bool IsEmpty => Width <= 0 || Height <= 0;

    /// Whether a point falls inside, with the left and top edges included and
    /// the right and bottom excluded -- the half-open convention every hit test
    /// wants, so two rectangles that share an edge do not both claim it.
    public bool Contains(Point point) {
        return point.X >= X && point.X < X + Width
            && point.Y >= Y && point.Y < Y + Height;
    }

    /// The rectangle shrunk by `amount` on every side, or empty if there is
    /// less than that to shrink.
    public Rectangle Deflate(int amount) {
        return Rectangle.Of(X + amount, Y + amount,
                            Width - amount * 2, Height - amount * 2);
    }

    /// The part both rectangles cover, which may be empty.
    public Rectangle Intersect(Rectangle other) {
        int left   = X > other.X ? X : other.X;
        int top    = Y > other.Y ? Y : other.Y;
        int right  = Right  < other.Right  ? Right  : other.Right;
        int bottom = Bottom < other.Bottom ? Bottom : other.Bottom;
        if (right <= left || bottom <= top) { return Rectangle.Empty; }
        return Rectangle.FromEdges(left, top, right, bottom);
    }

    public bool Equals(Rectangle other) {
        return X == other.X && Y == other.Y
            && Width == other.Width && Height == other.Height;
    }
}

// ===================================================================== font

/// How a font is drawn, beyond its face and size. Bits, so they combine.
[Flags]
public enum FontStyle {
    Regular   = 0,
    Bold      = 1,
    Italic    = 2,
    Underline = 4,
    Strikeout = 8,
}

/// A typeface at a size.
///
/// **Immutable, and that is the difference from `TFont`.** The LCL's font is a
/// `TPersistent` that controls share and mutate, with an `OnChange` that
/// repaints whatever was listening -- so assigning to `Label1.Font.Size` has to
/// reach back through the font to the control. Here a `Font` is a value object
/// with a platform handle: a control that wants a bigger one is given a new
/// `Font`, the control knows its own font changed because it was the one
/// assigned to, and nothing needs a change notification at all.
///
/// The handle is made once, lazily, by the platform, and released when the last
/// reference to the font goes. Sharing one `Font` across a hundred controls
/// therefore costs one platform font, which is what the LCL's sharing was for.
public sealed class Font {
    IFontBackend? backend;

    public String    Family { get; }
    /// In points, as every platform's font dialog states it -- not in pixels,
    /// which would mean something different on each monitor.
    public int       Size   { get; }
    public FontStyle Style  { get; }

    public Font(String family, int size, FontStyle style) {
        Family = family;
        Size = size;
        Style = style;
        backend = null;
    }

    public Font(String family, int size) { this(family, size, FontStyle.Regular); }

    public bool Bold      => Style.HasFlag(FontStyle.Bold);
    public bool Italic    => Style.HasFlag(FontStyle.Italic);
    public bool Underline => Style.HasFlag(FontStyle.Underline);
    public bool Strikeout => Style.HasFlag(FontStyle.Strikeout);

    /// The same font with one thing changed. What a control does when asked to
    /// go bold, since a `Font` cannot be edited in place.
    public Font WithStyle(FontStyle style) { return new Font(Family, Size, style); }
    public Font WithSize(int size)         { return new Font(Family, size, Style); }
    public Font WithFamily(String family)  { return new Font(family, Size, Style); }

    /// The platform's font, made on first use.
    ///
    /// Not public: a control hands a `Font` to `Graphics` and the backend asks
    /// for this. A program that has reached for it wanted `Graphics` instead.
    IFontBackend Backend() {
        var made = backend;
        if (made == null) {
            made = WidgetSet.Current.CreateFont(this);
            backend = made;
        }
        return (IFontBackend)made;
    }

    /// For the backend, which needs the handle it made and cannot see a
    /// module-private method from where it lives.
    public IFontBackend Resource() { return Backend(); }
}

// ============================================================== pen and brush

/// How a line is drawn.
public enum PenStyle { Solid, Dash, Dot, DashDot, None }

/// The outline a `Graphics` draws with.
public sealed class Pen {
    public Color    Color { get; }
    public int      Width { get; }
    public PenStyle Style { get; }

    public Pen(Color colour, int width, PenStyle style) {
        Color = colour;
        Width = width;
        Style = style;
    }

    public Pen(Color colour) { this(colour, 1, PenStyle.Solid); }
}

/// The fill a `Graphics` draws with. Solid only for now; a hatch and a gradient
/// are the two worth adding, and both are a new field here and a new case in
/// each backend rather than a new type.
public sealed class Brush {
    public Color Color { get; }

    public Brush(Color colour) { Color = colour; }
}

// ================================================================= graphics

/// Where text sits inside the rectangle it is drawn in.
public enum HorizontalAlignment { Left, Center, Right }
public enum VerticalAlignment   { Top, Middle, Bottom }

/// How a run of text is laid out. A struct, because it is three small choices
/// that travel together and a class would make every draw call allocate.
public struct TextFormat {
    public HorizontalAlignment Horizontal;
    public VerticalAlignment   Vertical;
    /// Whether a line too long for the rectangle wraps rather than being cut.
    public bool                Wrap;

    public static TextFormat Of(HorizontalAlignment horizontal,
                                VerticalAlignment vertical, bool wrap) {
        TextFormat format;
        format.Horizontal = horizontal;
        format.Vertical = vertical;
        format.Wrap = wrap;
        return format;
    }

    public static readonly TextFormat Default =
        TextFormat.Of(HorizontalAlignment.Left, VerticalAlignment.Top, false);

    public static readonly TextFormat Centered =
        TextFormat.Of(HorizontalAlignment.Center, VerticalAlignment.Middle, false);
}

/// A surface to paint on: the LCL's `TCanvas`, named as C# names it.
///
/// **A `Graphics` is borrowed, never stored.** One arrives in a
/// `PaintEventArgs` and is valid until that handler returns, because what backs
/// it is a device context the platform lent for the duration of one paint. A
/// control that keeps one is keeping a handle the platform has taken back.
/// That is C#'s rule for `Graphics` and the LCL's rule for `TCanvas` during
/// `OnPaint`, arrived at from the same constraint.
///
/// **State is passed, not set.** `TCanvas` carries a current `Pen`, `Brush` and
/// `Font`, so a routine that draws has to save and restore three things or
/// corrupt its caller; every LCL painting bug of the shape "the colour was
/// wrong the second time" is that. Here each call takes what it draws with,
/// which costs one argument and removes the entire class of bug.
public sealed class Graphics {
    IGraphicsBackend backend;

    /// Not public: a `Graphics` is made by the platform when a paint begins.
    public Graphics(IGraphicsBackend surface) { backend = surface; }

    /// Everything inside this is what the control was asked to repaint. Drawing
    /// outside it is not an error and not drawn, so a handler may ignore it
    /// entirely and only a slow one needs to look.
    public Rectangle ClipBounds => backend.ClipBounds();

    /// Narrows drawing to a rectangle and moves the origin to its corner.
    ///
    /// Everything drawn until the matching `PopLayer` is in that rectangle's
    /// own coordinates and clipped to it. What a control drawn inside another
    /// needs, and the reason a `GraphicControl` may draw from (0, 0) without
    /// knowing where on the form it sits.
    public int PushLayer(Rectangle bounds) { return backend.PushLayer(bounds); }

    public void PopLayer(int token) { backend.PopLayer(token); }

    public void DrawLine(Pen pen, int x1, int y1, int x2, int y2) {
        backend.DrawLine(pen, x1, y1, x2, y2);
    }

    public void DrawRectangle(Pen pen, Rectangle bounds) {
        backend.DrawRectangle(pen, bounds);
    }

    public void FillRectangle(Brush brush, Rectangle bounds) {
        backend.FillRectangle(brush, bounds);
    }

    public void DrawEllipse(Pen pen, Rectangle bounds) {
        backend.DrawEllipse(pen, bounds);
    }

    public void FillEllipse(Brush brush, Rectangle bounds) {
        backend.FillEllipse(brush, bounds);
    }

    /// A closed shape. Fewer than three points draws nothing rather than
    /// failing, since a polygon built from a filtered list may legitimately
    /// come out empty.
    public void DrawPolygon(Pen pen, Point[] points) {
        if (points.Length < 3) { return; }
        backend.DrawPolygon(pen, points);
    }

    public void FillPolygon(Brush brush, Point[] points) {
        if (points.Length < 3) { return; }
        backend.FillPolygon(brush, points);
    }

    /// An open run of connected lines.
    public void DrawPolyline(Pen pen, Point[] points) {
        if (points.Length < 2) { return; }
        backend.DrawPolyline(pen, points);
    }

    /// Fills the whole clip with one colour. What a paint handler usually does
    /// first, and the reason `OnPaintBackground` need not exist.
    public void Clear(Color colour) { backend.Clear(colour); }

    /// Draws text at a point, with no wrapping and no alignment.
    public void DrawString(String text, Font font, Color colour, int x, int y) {
        backend.DrawString(text, font, colour, x, y);
    }

    /// Draws text inside a rectangle, aligned and wrapped as the format says.
    public void DrawString(String text, Font font, Color colour,
                           Rectangle bounds, TextFormat format) {
        backend.DrawStringIn(text, font, colour, bounds, format);
    }

    /// Draws a picture with its top-left corner at a point.
    public void DrawBitmap(Bitmap picture, Point at) {
        backend.DrawBitmap(picture.Backend(), at);
    }

    /// Draws it scaled to fill a rectangle.
    public void DrawBitmap(Bitmap picture, Rectangle into) {
        if (into.IsEmpty) { return; }
        backend.DrawBitmapIn(picture.Backend(), into);
    }

    /// How large that text would be. What a control's `PreferredSize` is built
    /// from, and the reason a `Graphics` can be asked for before anything is
    /// drawn on it.
    public Size MeasureString(String text, Font font) {
        return backend.MeasureString(text, font);
    }
}

// ==================================================================== bitmap

/// A picture, loaded once and drawn many times.
///
/// **Read from a file and nothing else, for now.** There is no drawing on to
/// one and no saving from one; what a `Bitmap` is for at this stage is putting
/// icons on a toolbar, in a tree and in a list, which is what `ImageList` takes
/// one for. Which formats can be read is the platform's business -- Windows
/// decodes `.bmp` without a library and nothing else.
public sealed class Bitmap {
    IBitmapBackend backend;

    Bitmap(IBitmapBackend made) { backend = made; }

    /// Reads a picture from disk.
    ///
    /// A `Result` rather than a null, because a missing or unreadable file is
    /// the ordinary case here -- an icon is usually named by a path a program
    /// built, and the error says which one failed.
    public static Result<Bitmap, String> FromFile(String path) {
        var loaded = WidgetSet.Current.LoadBitmap(path);
        if (!loaded.Ok) { return Fail(loaded.Error); }
        return Ok(new Bitmap(loaded.Value));
    }

    public int Width  => backend.Width();
    public int Height => backend.Height();
    public Size Extent => Size.Of(backend.Width(), backend.Height());

    /// The platform's picture, for the things that take one.
    public IBitmapBackend Backend() { return backend; }
}

// =========================================================== system colours

/// The colours the desktop theme chooses, asked of the platform each time.
///
/// The LCL spells these `clBtnFace`, `clWindowText` and so on, hidden inside
/// `TColor`'s high bit; C# gives them a class of their own and resolves them on
/// read, which is also the only way to be right after the user changes theme
/// mid-run. These are properties rather than `static readonly` fields for
/// exactly that reason: a field is read once, before `Main`, and then wrong.
public static class SystemColors {
    public static Color Control          => WidgetSet.Current.SystemColor(SystemColorId.Control);
    public static Color ControlText      => WidgetSet.Current.SystemColor(SystemColorId.ControlText);
    public static Color Window           => WidgetSet.Current.SystemColor(SystemColorId.Window);
    public static Color WindowText       => WidgetSet.Current.SystemColor(SystemColorId.WindowText);
    public static Color Highlight        => WidgetSet.Current.SystemColor(SystemColorId.Highlight);
    public static Color HighlightText    => WidgetSet.Current.SystemColor(SystemColorId.HighlightText);
    public static Color GrayText         => WidgetSet.Current.SystemColor(SystemColorId.GrayText);
    public static Color ControlDark      => WidgetSet.Current.SystemColor(SystemColorId.ControlDark);
    public static Color ControlLight     => WidgetSet.Current.SystemColor(SystemColorId.ControlLight);
}
