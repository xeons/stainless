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
public struct Color
{
    public byte R;
    public byte G;
    public byte B;

    /// 255 is opaque and 0 is invisible. The Win32 backend ignores it outside
    /// the few places GDI understands alpha; it is here because the GTK one
    /// does not, and a type that gains a channel later gains it everywhere.
    public byte A;

    public static Color FromRgb(byte red, byte green, byte blue)
    {
        Color color;
        color.R = red;
        color.G = green;
        color.B = blue;
        color.A = 255;
        return color;
    }

    public static Color FromArgb(byte alpha, byte red, byte green, byte blue)
    {
        Color color = Color.FromRgb(red, green, blue);
        color.A = alpha;
        return color;
    }

    /// Whether two colours are the same in every channel.
    ///
    /// A method rather than `==`, because a struct gets no operators unless
    /// they are written and equality on a colour is wanted rarely enough that
    /// the call site reads better spelled out.
    public bool Equals(Color other)
    {
        return R == other.R && G == other.G && B == other.B && A == other.A;
    }
}

/// The fixed colours, named as C# names them.
public static class Colors
{
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
public struct Point
{
    public int X;
    public int Y;

    public static Point FromXY(int x, int y)
    {
        Point point;
        point.X = x;
        point.Y = y;
        return point;
    }

    public static readonly Point Empty = Point.FromXY(0, 0);

    public bool Equals(Point other) => X == other.X && Y == other.Y;
}

/// An extent, in pixels. Never negative in practice, though nothing enforces
/// it: a control constrained smaller than its border would otherwise have to
/// report something, and zero is the honest answer.
public struct Size
{
    public int Width;
    public int Height;

    public static Size FromDimensions(int width, int height)
    {
        Size size;
        size.Width = width;
        size.Height = height;
        return size;
    }

    public static readonly Size Empty = Size.FromDimensions(0, 0);

    public bool IsEmpty => Width <= 0 || Height <= 0;

    public bool Equals(Size other)
    {
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
public struct Rectangle
{
    public int X;
    public int Y;
    public int Width;
    public int Height;

    public static Rectangle FromBounds(int x, int y, int width, int height)
    {
        Rectangle rectangle;
        rectangle.X = x;
        rectangle.Y = y;
        rectangle.Width = width;
        rectangle.Height = height;
        return rectangle;
    }

    public static Rectangle FromEdges(int left, int top, int right, int bottom)
    {
        return Rectangle.FromBounds(left, top, right - left, bottom - top);
    }

    public static readonly Rectangle Empty = Rectangle.FromBounds(0, 0, 0, 0);

    public int Left   => X;
    public int Top    => Y;
    public int Right  => X + Width;
    public int Bottom => Y + Height;

    public Point Location => Point.FromXY(X, Y);
    public Size Extent   => Size.FromDimensions(Width, Height);

    public bool IsEmpty => Width <= 0 || Height <= 0;

    /// Whether a point falls inside, with the left and top edges included and
    /// the right and bottom excluded -- the half-open convention every hit test
    /// wants, so two rectangles that share an edge do not both claim it.
    public bool Contains(Point point)
    {
        return point.X >= X && point.X < X + Width
            && point.Y >= Y && point.Y < Y + Height;
    }

    /// The rectangle shrunk by `amount` on every side, or empty if there is
    /// less than that to shrink.
    public Rectangle DeflateBy(int amount)
    {
        int width = Width - amount * 2;
        int height = Height - amount * 2;
        return Rectangle.FromBounds(X + amount, Y + amount,
                            width < 0 ? 0 : width, height < 0 ? 0 : height);
    }

    /// The part both rectangles cover, which may be empty.
    public Rectangle Intersect(Rectangle other)
    {
        int left   = X > other.X ? X : other.X;
        int top    = Y > other.Y ? Y : other.Y;
        int right  = Right  < other.Right  ? Right  : other.Right;
        int bottom = Bottom < other.Bottom ? Bottom : other.Bottom;
        if (right <= left || bottom <= top)
            return Rectangle.Empty;
        return Rectangle.FromEdges(left, top, right, bottom);
    }

    public bool Equals(Rectangle other)
    {
        return X == other.X && Y == other.Y
            && Width == other.Width && Height == other.Height;
    }
}

// ===================================================================== font

/// How a font is drawn, beyond its face and size. Bits, so they combine.
[Flags]
public enum FontStyle
{
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
public sealed class Font
{
    IFontBackend? _backend;

    public String    Family { get; }
    /// In points, as every platform's font dialog states it -- not in pixels,
    /// which would mean something different on each monitor.
    public int       Size   { get; }
    public FontStyle Style  { get; }

    public Font(String family, int size, FontStyle style)
    {
        Family = family;
        Size = size;
        Style = style;
        _backend = null;
    }

    public Font(String family, int size) => this(family, size, FontStyle.Regular);

    public bool Bold      => Style.HasFlag(FontStyle.Bold);
    public bool Italic    => Style.HasFlag(FontStyle.Italic);
    public bool Underline => Style.HasFlag(FontStyle.Underline);
    public bool Strikeout => Style.HasFlag(FontStyle.Strikeout);

    /// The same font with one thing changed. What a control does when asked to
    /// go bold, since a `Font` cannot be edited in place.
    public Font WithStyle(FontStyle style) => new Font(Family, Size, style);
    public Font WithSize(int size) => new Font(Family, size, Style);
    public Font WithFamily(String family) => new Font(family, Size, Style);

    /// The platform's font, made on first use.
    ///
    /// For the backend: a control hands a `Font` to `Graphics` and the backend
    /// asks for this. A program that has reached for it wanted `Graphics`.
    public IFontBackend Resource
    {
        get
        {
            var made = _backend;
            if (made == null)
            {
                made = WidgetSet.Current.CreateFont(this);
                _backend = made;
            }
            return (IFontBackend)made;
        }
    }
}

// ============================================================== pen and brush

/// How a line is drawn.
public enum PenStyle { Solid, Dash, Dot, DashDot, None }

/// The outline a `Graphics` draws with.
public sealed class Pen
{
    public Color    Color { get; }
    public int      Width { get; }
    public PenStyle Style { get; }

    public Pen(Color color, int width, PenStyle style)
    {
        Color = color;
        Width = width;
        Style = style;
    }

    public Pen(Color color) => this(color, 1, PenStyle.Solid);
}

/// How a `Brush` fills: one colour, or two with a ramp between them.
///
/// A hatch is the other one worth having and is not here. It would be a third
/// case rather than a fourth type, exactly as these two are.
public enum BrushStyle
{
    /// `Color` everywhere, and `EndColor` ignored.
    Solid,
    /// `Color` at the top, `EndColor` at the bottom.
    VerticalGradient,
    /// `Color` at the left, `EndColor` at the right.
    HorizontalGradient,
}

/// The fill a `Graphics` draws with.
///
/// **A field rather than a type per kind**, which is what the note that used
/// to be here asked for: a gradient brush that was its own class would mean
/// every `FillRectangle` in every backend testing which it had been handed,
/// and a `Brush` parameter that could no longer be passed on unexamined.
///
/// `EndColor` is `Color` for a solid one, so a backend's gradient path and its
/// solid path can be the same code where that is convenient and the answer is
/// right either way.
public sealed class Brush
{
    public Color Color { get; }

    /// The colour the ramp reaches. The same as `Color` unless this is a
    /// gradient.
    public Color EndColor { get; }

    public BrushStyle Style { get; }

    public Brush(Color color)
    {
        Color = color;
        EndColor = color;
        Style = BrushStyle.Solid;
    }

    /// A ramp from one colour to another, down or across.
    ///
    /// ```
    /// var gutter = new Brush(SystemColors.Control, SystemColors.Window,
    ///                        BrushStyle.HorizontalGradient);
    /// ```
    public Brush(Color from, Color to, BrushStyle style)
    {
        Color = from;
        EndColor = to;
        Style = style;
    }

    /// Whether this asks for a ramp at all, which is the question every
    /// backend asks first.
    public bool IsGradient => Style != BrushStyle.Solid;
}

// ================================================================= graphics

/// Where text sits inside the rectangle it is drawn in.
public enum HorizontalAlignment { Left, Center, Right }
public enum VerticalAlignment   { Top, Middle, Bottom }

/// How a run of text is laid out. A struct, because it is three small choices
/// that travel together and a class would make every draw call allocate.
public struct TextFormat
{
    public HorizontalAlignment Horizontal;
    public VerticalAlignment Vertical;
    /// Whether a line too long for the rectangle wraps rather than being cut.
    public bool Wrap;

    public static TextFormat FromAlignment(HorizontalAlignment horizontal,
                                VerticalAlignment vertical, bool wrap)
    {
        TextFormat format;
        format.Horizontal = horizontal;
        format.Vertical = vertical;
        format.Wrap = wrap;
        return format;
    }

    public static readonly TextFormat Default =
        TextFormat.FromAlignment(HorizontalAlignment.Left, VerticalAlignment.Top, false);

    public static readonly TextFormat Centered =
        TextFormat.FromAlignment(HorizontalAlignment.Center, VerticalAlignment.Middle, false);
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
public sealed class Graphics
{
    IGraphicsBackend _backend;

    /// Not public: a `Graphics` is made by the platform when a paint begins.
    public Graphics(IGraphicsBackend surface) => _backend = surface;

    /// Everything inside this is what the control was asked to repaint. Drawing
    /// outside it is not an error and not drawn, so a handler may ignore it
    /// entirely and only a slow one needs to look.
    public Rectangle ClipBounds => _backend.ClipBounds;

    /// Narrows drawing to a rectangle and moves the origin to its corner.
    ///
    /// Everything drawn until the matching `PopLayer` is in that rectangle's
    /// own coordinates and clipped to it. What a control drawn inside another
    /// needs, and the reason a `GraphicControl` may draw from (0, 0) without
    /// knowing where on the form it sits.
    public int PushLayer(Rectangle bounds) => _backend.PushLayer(bounds);

    public void PopLayer(int token) => _backend.PopLayer(token);

    public void DrawLine(Pen pen, int x1, int y1, int x2, int y2)
    {
        _backend.DrawLine(pen, x1, y1, x2, y2);
    }

    public void DrawRectangle(Pen pen, Rectangle bounds)
    {
        _backend.DrawRectangle(pen, bounds);
    }

    public void FillRectangle(Brush brush, Rectangle bounds)
    {
        _backend.FillRectangle(brush, bounds);
    }

    public void DrawEllipse(Pen pen, Rectangle bounds)
    {
        _backend.DrawEllipse(pen, bounds);
    }

    public void FillEllipse(Brush brush, Rectangle bounds)
    {
        _backend.FillEllipse(brush, bounds);
    }

    /// A closed shape. Fewer than three points draws nothing rather than
    /// failing, since a polygon built from a filtered list may legitimately
    /// come out empty.
    public void DrawPolygon(Pen pen, Point[] points)
    {
        if (points.Length < 3)
            return;
        _backend.DrawPolygon(pen, points);
    }

    public void FillPolygon(Brush brush, Point[] points)
    {
        if (points.Length < 3)
            return;
        _backend.FillPolygon(brush, points);
    }

    /// An open run of connected lines.
    public void DrawPolyline(Pen pen, Point[] points)
    {
        if (points.Length < 2)
            return;
        _backend.DrawPolyline(pen, points);
    }

    /// Fills the whole clip with one colour. What a paint handler usually does
    /// first, and the reason `OnPaintBackground` need not exist.
    public void Clear(Color color) => _backend.Clear(color);

    /// Draws text at a point, with no wrapping and no alignment.
    public void DrawString(String text, Font font, Color color, int x, int y)
    {
        _backend.DrawString(text, font, color, x, y);
    }

    /// Draws text inside a rectangle, aligned and wrapped as the format says.
    public void DrawString(String text, Font font, Color color,
                           Rectangle bounds, TextFormat format)
    {
        _backend.DrawStringIn(text, font, color, bounds, format);
    }

    /// Draws a picture with its top-left corner at a point.
    public void DrawBitmap(Bitmap picture, Point at)
    {
        _backend.DrawBitmap(picture.Backend, at);
    }

    /// Draws a picture faded into its background: `opacity` percent of it,
    /// and the rest whatever was already there.
    ///
    /// What a disabled icon is. 100 is `DrawBitmap` and takes that path, so a
    /// caller working out its own opacity does not have to special-case the
    /// ordinary one.
    public void DrawBitmap(Bitmap picture, Point at, int opacity)
    {
        if (opacity >= 100)
        {
            _backend.DrawBitmap(picture.Backend, at);
            return;
        }
        if (opacity <= 0)
            return;
        _backend.DrawBitmapFaded(picture.Backend, at, opacity);
    }

    /// Draws it scaled to fill a rectangle.
    public void DrawBitmap(Bitmap picture, Rectangle into)
    {
        if (into.IsEmpty)
            return;
        _backend.DrawBitmapIn(picture.Backend, into);
    }

    /// How large that text would be. What a control's `PreferredSize` is built
    /// from, and the reason a `Graphics` can be asked for before anything is
    /// drawn on it.
    public Size MeasureString(String text, Font font)
    {
        return _backend.MeasureString(text, font);
    }
}

// ==================================================================== bitmap

/// A picture, loaded once and drawn many times.
///
/// **PNG, JPEG, BMP and GIF, on both backends.** Which formats can be read used
/// to be the platform's business, and that meant `.bmp` and nothing else on
/// Windows, because `LoadImageW` is the whole of what Windows decodes without a
/// library. `Standard.Drawing` decodes all four everywhere -- GDI+ on Windows,
/// libgd elsewhere -- so a `Bitmap` is now one of its images handed to the
/// widget set, and the platform's own loader is the fallback rather than the
/// rule.
///
/// The two libraries stay apart otherwise, and deliberately:
/// `Standard.Drawing` is a picture in memory that knows nothing about windows,
/// and this is a picture the *toolkit* holds -- an `HBITMAP`, a `GdkPixbuf` --
/// which is the only kind a control can draw. `FromImage` is the one crossing,
/// and it copies: what a widget set holds afterwards owes nothing to the image
/// it came from.
///
/// There is still no drawing on to one and no saving from one. Draw on a
/// `Standard.Drawing.Image` and bring the result across.
public sealed class Bitmap
{
    IBitmapBackend _backend;

    Bitmap(IBitmapBackend made) => _backend = made;

    /// Reads a picture from disk.
    ///
    /// A `Result` rather than a null, because a missing or unreadable file is
    /// the ordinary case here -- an icon is usually named by a path a program
    /// built, and the error says which one failed.
    public static Result<Bitmap, String> FromFile(String path)
    {
        // The decoder first, because it reads four formats where the widget
        // set reads one -- and the widget set second, because a machine with
        // no imaging library still has whatever its own toolkit can decode.
        if (Standard.Drawing.Imaging.Available)
        {
            var read = Standard.Drawing.Image.FromFile(path);
            if (read.Ok)
                return FromImage(read.Value);

            // A file that is genuinely missing is worth saying so about
            // directly; anything else may still be something the platform
            // knows and this does not, so it falls through.
            if (read.Error == Standard.Drawing.ImageError.NotFound)
                return Fail("could not read '" + path + "': there is no such file");
        }

        var loaded = WidgetSet.Current.LoadBitmap(path);
        if (!loaded.Ok)
            return Fail(loaded.Error);
        return Ok(new Bitmap(loaded.Value));
    }

    /// A picture the program decoded, drew or generated, handed to the widget
    /// set.
    ///
    /// This is the crossing between the two drawing libraries, and it is a
    /// copy: the pixels are read out of `picture` once and given to the
    /// toolkit, so the two are independent afterwards and drawing on the image
    /// again does not change the bitmap.
    public static Result<Bitmap, String> FromImage(Standard.Drawing.Image picture)
    {
        if (!picture.IsOpen)
            return Fail("that picture has been closed");

        var pixels = picture.ToBgra();
        if (pixels.Length == 0u)
            return Fail("could not read the picture's pixels");
        return FromPixels(picture.Width, picture.Height, pixels);
    }

    /// A picture from pixels the program already has, in `CopyPixels`' order:
    /// blue, green, red and straight alpha, rows top to bottom, `width * 4`
    /// bytes to a row.
    ///
    /// The one way in that needs no imaging library, which is what a picture
    /// pasted from the clipboard arrives through.
    public static Result<Bitmap, String> FromPixels(int width, int height, byte[] pixels)
    {
        var made = WidgetSet.Current.CreateBitmap(width, height, pixels);
        if (!made.Ok)
            return Fail(made.Error);
        return Ok(new Bitmap(made.Value));
    }

    /// Reads a picture the program is carrying inside itself, by the numeric
    /// id its resource script gave it.
    ///
    /// This is the one that cannot go wrong at the customer's machine. A path
    /// is a promise about a file that has to still be there, spelled the same
    /// way, beside a binary that may have been moved; a resource id is checked
    /// when the program is *built* and travels in the executable. For a
    /// toolbar's icons -- which are part of the program rather than part of its
    /// data -- that is the difference between a missing button and no failure
    /// mode at all.
    ///
    /// **Windows only.** The `Result` is the honest way to say so: on a GTK
    /// build this fails with a message explaining that an ELF binary has no
    /// resource section, rather than the method not existing and the program
    /// failing to compile on one of the two platforms.
    public static Result<Bitmap, String> FromResource(int id)
    {
        var loaded = WidgetSet.Current.LoadBitmapResource(id);
        if (!loaded.Ok)
            return Fail(loaded.Error);
        return Ok(new Bitmap(loaded.Value));
    }

    public int Width  => _backend.Width;
    public int Height => _backend.Height;
    public Size Extent => Size.FromDimensions(_backend.Width, _backend.Height);

    /// The platform's picture, for the things that take one.
    public IBitmapBackend Backend => _backend;
}

// =========================================================== system colours

/// The colours the desktop theme chooses, asked of the platform each time.
///
/// The LCL spells these `clBtnFace`, `clWindowText` and so on, hidden inside
/// `TColor`'s high bit; C# gives them a class of their own and resolves them on
/// read, which is also the only way to be right after the user changes theme
/// mid-run. These are properties rather than `static readonly` fields for
/// exactly that reason: a field is read once, before `Main`, and then wrong.
public static class SystemColors
{
    public static Color Control          => WidgetSet.Current.GetSystemColor(SystemColorId.Control);
    public static Color ControlText      => WidgetSet.Current.GetSystemColor(SystemColorId.ControlText);
    public static Color Window           => WidgetSet.Current.GetSystemColor(SystemColorId.Window);
    public static Color WindowText       => WidgetSet.Current.GetSystemColor(SystemColorId.WindowText);
    public static Color Highlight        => WidgetSet.Current.GetSystemColor(SystemColorId.Highlight);
    public static Color HighlightText    => WidgetSet.Current.GetSystemColor(SystemColorId.HighlightText);
    public static Color GrayText         => WidgetSet.Current.GetSystemColor(SystemColorId.GrayText);
    public static Color ControlDark      => WidgetSet.Current.GetSystemColor(SystemColorId.ControlDark);
    public static Color ControlLight     => WidgetSet.Current.GetSystemColor(SystemColorId.ControlLight);
}
