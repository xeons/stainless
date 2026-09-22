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

// Drawing: cairo behind `IGraphicsBackend`, and pictures behind the other two.
//
// **cairo is a painter, GDI is a bag of objects**, and the difference shows up
// in what each backend has to keep. The Win32 one owns a pen, a brush and a
// font, creates and selects and deletes them, and caches nothing -- every
// drawing call makes two GDI objects and destroys them. Here a `Pen` is two
// calls before the stroke and there is nothing to own, so this file has no
// destructor in it at all.
//
// **Three things cairo does differently, and each is one line here:**
//
//   - **Coordinates are on the line, not beside it.** A one-pixel stroke
//     centred on an integer coordinate lands half on each side and is drawn
//     grey twice. Every outline below is offset by half a pixel, which is the
//     standard cairo answer and the reason a rectangle looks crisp.
//   - **Filling consumes the path.** Outlining a filled shape means
//     `cairo_fill_preserve` and then a stroke, in that order.
//   - **Text is drawn from its baseline.** Every other API in this project
//     draws from the top-left, so the ascent is added on the way in.
//
// **The text here is cairo's toy API**, which is what the GTK bindings say
// they have and is a real limit: no Pango means no shaping, no bidirectional
// text and no font fallback, so a label in Arabic is drawn wrong. It is
// stated in the README rather than discovered.
module Forms.Platform.Gtk;

import Standard.Collections;
import Standard.Text;
import Forms.Drawing;
import Forms.Platform;
#if UNIX
import Gtk.GLib;
import Gtk.GObject;
import Gtk.Gdk;
import Gtk.Api;
import Gtk.Cairo;

// ==================================================================== font

/// The platform's font, which on GTK is a name rather than a handle.
///
/// **There is no object to make.** CSS takes a family and a size as text, and
/// cairo's toy API takes the same three things at the point of drawing, so
/// nothing is allocated and `Handle` has nothing to answer with. Zero, and the
/// comment is here so that a reader who went looking for the handle finds out
/// why there is not one rather than assuming a bug.
public class GtkFontBackend : IFontBackend
{
    public String Name { get; }
    public Font   Of   { get; }

    public GtkFontBackend(Font font)
    {
        Of = font;
        Name = PangoName(font);
    }

    public nuint Handle => 0u;
}

/// Sets cairo's font from one of ours. The slant and the weight are cairo's
/// own two-value enums, which is the whole of what the toy API supports --
/// no semibold, and no underline or strikeout, which are drawn as lines.
void SelectFont(gpointer cairo, Font font)
{
    cairo_select_font_face(cairo, font.Family.ToPointer(),
                           font.Italic ? CAIRO_FONT_SLANT_ITALIC
                                       : CAIRO_FONT_SLANT_NORMAL,
                           font.Bold ? CAIRO_FONT_WEIGHT_BOLD
                                     : CAIRO_FONT_WEIGHT_NORMAL);

    // Points to pixels at the 96 DPI GTK reports for an unscaled display.
    // The same arithmetic the Win32 backend does against the real DC, and the
    // reason both are wrong on a scaled screen -- which is the DPI item in
    // the roadmap rather than something to paper over here.
    cairo_set_font_size(cairo, (double)font.Size * 96.0 / 72.0);
}

// ================================================================ pictures

/// A picture, which on GTK is a `GdkPixbuf`.
///
/// **This reads more formats than the Win32 backend does**, and not because
/// anything here is cleverer: `gdk-pixbuf` has loaders for PNG, JPEG, GIF and
/// the rest, where `LoadImageW` reads `.bmp` and nothing else. The seam says
/// what the format may be is the backend's business, which is exactly the
/// right thing for it to say.
public class GtkBitmapBackend : IBitmapBackend
{
    gpointer _pixbuf;

    public GtkBitmapBackend(gpointer image) => _pixbuf = image;

    /// A pixbuf is a plain `GObject` and its reference is **not** floating, so
    /// this is a reference added rather than a float claimed -- `ref_sink`
    /// would be wrong here and right on a widget.
    ~GtkBitmapBackend()
    {
        if (_pixbuf != null)
        {
            g_object_unref(_pixbuf);
            _pixbuf = null;
        }
    }

    public int Width => gdk_pixbuf_get_width((GdkPixbuf*)_pixbuf);
    public int Height => gdk_pixbuf_get_height((GdkPixbuf*)_pixbuf);

    public nuint Handle => (nuint)_pixbuf;

    /// What the pixbuf itself says, which is the honest answer and not one
    /// this backend has to act on: cairo composites a pixbuf correctly whether
    /// or not it has an alpha channel, so nothing here branches on this. It is
    /// the Win32 side that must choose between two different blits, and the
    /// seam asks both the same question rather than having one of them carry a
    /// property only the other means anything by.
    public bool HasAlpha => gdk_pixbuf_get_has_alpha((GdkPixbuf*)_pixbuf) != 0;

    /// The pixbuf itself, for the image list and the toolbar, which need the
    /// object rather than a number.
    public gpointer Pixbuf => _pixbuf;
}

/// Same-sized pictures, indexed by number.
///
/// **A list rather than one wide bitmap**, which is what an `HIMAGELIST` is.
/// GTK has no image list at all -- a toolbar takes a widget per button and a
/// tree takes a pixbuf per row -- so the seam's idea of one is kept here and
/// scaling happens on the way in, which is what makes every entry the size the
/// list says it is.
public class GtkImageListBackend : IImageListBackend
{
    List<gpointer> _pictures;
    FSize _extent;

    public GtkImageListBackend(FSize imageSize)
    {
        _pictures = new List<gpointer>();
        _extent = imageSize;
    }

    ~GtkImageListBackend()
    {
        for (nuint i = 0u; i < _pictures.Count; i++)
            g_object_unref(_pictures[i]);
        _pictures.Clear();
    }

    public int Add(IBitmapBackend picture)
    {
        var source = ((GtkBitmapBackend)picture).Pixbuf;
        gpointer scaled = source;

        // Scaled only when it has to be, and the copy is owned either way --
        // so an entry is unreffed once in the destructor whichever branch it
        // came from.
        if (gdk_pixbuf_get_width((GdkPixbuf*)source) != _extent.Width ||
            gdk_pixbuf_get_height((GdkPixbuf*)source) != _extent.Height)
        {
            scaled = gdk_pixbuf_scale_simple((GdkPixbuf*)source, _extent.Width,
                                             _extent.Height, GDK_INTERP_BILINEAR);
        }
        else
        {
            g_object_ref(source);
        }

        _pictures.Add(scaled);
        return (int)_pictures.Count - 1;
    }

    public int Count => (int)_pictures.Count;
    public FSize ImageSize => _extent;

    /// **Borrowed.** A list has no handle of its own -- there is no such GTK
    /// object -- so this answers the address of the list itself, which is
    /// enough for a program comparing two lists and no use for anything else.
    public nuint Handle => 0u;

    /// One picture, for a toolbar button or a tree row. Null for an index
    /// nothing was added at, which is what a control passing -1 means.
    public gpointer Pixbuf(int index)
    {
        if (index < 0 || (nuint)index >= _pictures.Count)
            return null;
        return _pictures[(nuint)index];
    }
}

// ================================================================ graphics

/// A cairo context behind `IGraphicsBackend`.
///
/// **Borrowed, always.** The context comes from a `draw` handler, is already
/// clipped to the damaged region and translated to the widget's corner, and
/// must not be destroyed. Nothing here makes one, which is why there is no
/// destructor.
public class GtkGraphicsBackend : IGraphicsBackend
{
    gpointer _cairo;

    public GtkGraphicsBackend(gpointer context) => _cairo = context;

    // ------------------------------------------------------------- layers

    /// Clips to a rectangle and moves the origin to its corner.
    ///
    /// `cairo_save` and `cairo_restore` are a stack, so the token is not
    /// needed to know what to undo -- it is checked rather than used, which is
    /// what keeps an unbalanced push from quietly restoring somebody else's
    /// state.
    int _depth;

    public int PushLayer(Rectangle bounds)
    {
        cairo_save(_cairo);
        cairo_rectangle(_cairo, (double)bounds.X, (double)bounds.Y,
                        (double)bounds.Width, (double)bounds.Height);
        cairo_clip(_cairo);
        cairo_translate(_cairo, (double)bounds.X, (double)bounds.Y);
        _depth = _depth + 1;
        return _depth;
    }

    public void PopLayer(int token)
    {
        if (token != _depth)
            return;
        cairo_restore(_cairo);
        _depth = _depth - 1;
    }

    public Rectangle ClipBounds
    {
        get
        {
            gdouble x1 = 0.0;
            gdouble y1 = 0.0;
            gdouble x2 = 0.0;
            gdouble y2 = 0.0;
            cairo_clip_extents(_cairo, &x1, &y1, &x2, &y2);
            return Area((int)x1, (int)y1, (int)(x2 - x1), (int)(y2 - y1));
        }
    }

    // -------------------------------------------------------------- paint

    void Source(Color colour)
    {
        cairo_set_source_rgb(_cairo, (double)(int)colour.R / 255.0,
                                    (double)(int)colour.G / 255.0,
                                    (double)(int)colour.B / 255.0);
    }

    /// Everything a pen decides, before the stroke that uses it.
    ///
    /// **Half a pixel.** A cairo line is centred on its path, so a one-pixel
    /// stroke along an integer coordinate covers half of each neighbouring
    /// pixel and is drawn as two grey ones. Offsetting the path by half puts
    /// it between pixels, where a one-pixel line lands on exactly one. Only
    /// odd widths need it, which is what the test is.
    double Ready(Pen pen)
    {
        Source(pen.Color);
        cairo_set_line_width(_cairo, (double)pen.Width);

        // A dash pattern in user units. The lengths are the ones GDI uses for
        // the same three styles, so a program drawing a dashed border gets the
        // same picture on both backends.
        if (pen.Style == PenStyle.Dash)
        {
            double[2] pattern = [6.0, 3.0];
            cairo_set_dash(_cairo, &pattern[0u], 2, 0.0);
        }
        else if (pen.Style == PenStyle.Dot)
        {
            double[2] pattern = [1.0, 3.0];
            cairo_set_dash(_cairo, &pattern[0u], 2, 0.0);
        }
        else if (pen.Style == PenStyle.DashDot)
        {
            double[4] pattern = [6.0, 3.0, 1.0, 3.0];
            cairo_set_dash(_cairo, &pattern[0u], 4, 0.0);
        }
        else
        {
            cairo_set_dash(_cairo, null, 0, 0.0);
        }

        return (pen.Width % 2) == 1 ? 0.5 : 0.0;
    }

    public void Clear(Color colour)
    {
        Source(colour);
        cairo_paint(_cairo);
    }

    public void DrawLine(Pen pen, int x1, int y1, int x2, int y2)
    {
        if (pen.Style == PenStyle.None)
            return;
        double half = Ready(pen);
        cairo_new_path(_cairo);
        cairo_move_to(_cairo, (double)x1 + half, (double)y1 + half);
        cairo_line_to(_cairo, (double)x2 + half, (double)y2 + half);
        cairo_stroke(_cairo);
    }

    /// **Inside the rectangle, as GDI draws it.** `Rectangle(l, t, r, b)` puts
    /// its outline on the columns `l` and `r - 1`, so a 10 by 10 rectangle
    /// covers 10 by 10 pixels. The path runs through the centres of the edge
    /// pixels, which is one less than the size apart.
    public void DrawRectangle(Pen pen, Rectangle bounds)
    {
        if (pen.Style == PenStyle.None || bounds.Width <= 0 || bounds.Height <= 0)
            return;
        double half = Ready(pen);
        cairo_new_path(_cairo);
        cairo_rectangle(_cairo, (double)bounds.X + half, (double)bounds.Y + half,
                        (double)(bounds.Width - 1), (double)(bounds.Height - 1));
        cairo_stroke(_cairo);
    }

    public void FillRectangle(Brush brush, Rectangle bounds)
    {
        cairo_pattern_t* ramp = null;

        if (brush.IsGradient)
        {
            ramp = RampOver(brush, bounds);
            cairo_set_source(_cairo, ramp);
        }
        else
        {
            Source(brush.Color);
        }

        cairo_new_path(_cairo);
        cairo_rectangle(_cairo, (double)bounds.X, (double)bounds.Y,
                        (double)bounds.Width, (double)bounds.Height);
        cairo_fill(_cairo);

        // After the fill, not before: `cairo_set_source` takes a reference of
        // its own, but the source is what the fill just read and destroying it
        // first would be destroying it while it was in use.
        if (ramp != null)
            cairo_pattern_destroy(ramp);
    }

    /// A linear pattern spanning the rectangle, down or across.
    cairo_pattern_t* RampOver(Brush brush, Rectangle bounds)
    {
        double left = (double)bounds.X;
        double top = (double)bounds.Y;
        double right = (double)(bounds.X + bounds.Width);
        double bottom = (double)(bounds.Y + bounds.Height);

        var ramp = brush.Style == BrushStyle.HorizontalGradient
                 ? cairo_pattern_create_linear(left, top, right, top)
                 : cairo_pattern_create_linear(left, top, left, bottom);

        AddStop(ramp, 0.0, brush.Color);
        AddStop(ramp, 1.0, brush.EndColor);
        return ramp;
    }

    /// One end of the ramp. Cairo takes components as 0 to 1, which is the
    /// thing this file's header warns about.
    static void AddStop(cairo_pattern_t* ramp, double at, Color colour)
    {
        cairo_pattern_add_color_stop_rgb(ramp, at,
                                         (double)colour.R / 255.0,
                                         (double)colour.G / 255.0,
                                         (double)colour.B / 255.0);
    }

    /// An ellipse is a scaled circle, which is the only way cairo draws one.
    /// The save and restore are what keep the scaling from reaching the line
    /// width, which would otherwise be squashed along with the shape.
    ///
    /// False, with no path, for a rectangle with no area. A scale by zero
    /// leaves cairo in `CAIRO_STATUS_INVALID_MATRIX`, which is sticky: every
    /// call after it in the same paint is ignored, so one empty shape would
    /// blank the rest of the control.
    bool Ellipse(Rectangle bounds)
    {
        cairo_new_path(_cairo);
        if (bounds.Width <= 0 || bounds.Height <= 0)
            return false;
        cairo_save(_cairo);
        cairo_translate(_cairo, (double)bounds.X + (double)bounds.Width / 2.0,
                               (double)bounds.Y + (double)bounds.Height / 2.0);
        cairo_scale(_cairo, (double)bounds.Width / 2.0, (double)bounds.Height / 2.0);
        cairo_arc(_cairo, 0.0, 0.0, 1.0, 0.0, 6.283185307179586);
        cairo_restore(_cairo);
        return true;
    }

    public void DrawEllipse(Pen pen, Rectangle bounds)
    {
        if (pen.Style == PenStyle.None)
            return;
        Ready(pen);
        if (Ellipse(bounds))
            cairo_stroke(_cairo);
    }

    public void FillEllipse(Brush brush, Rectangle bounds)
    {
        Source(brush.Color);
        if (Ellipse(bounds))
            cairo_fill(_cairo);
    }

    void Path(Point[] points, double half, bool close)
    {
        cairo_new_path(_cairo);
        if (points.Length == 0u)
            return;

        cairo_move_to(_cairo, (double)points[0u].X + half, (double)points[0u].Y + half);
        for (nuint i = 1u; i < points.Length; i++)
        {
            cairo_line_to(_cairo, (double)points[i].X + half, (double)points[i].Y + half);
        }
        if (close)
            cairo_close_path(_cairo);
    }

    public void DrawPolygon(Pen pen, Point[] points)
    {
        if (pen.Style == PenStyle.None)
            return;
        double half = Ready(pen);
        Path(points, half, true);
        cairo_stroke(_cairo);
    }

    public void FillPolygon(Brush brush, Point[] points)
    {
        Source(brush.Color);
        Path(points, 0.0, true);
        cairo_fill(_cairo);
    }

    public void DrawPolyline(Pen pen, Point[] points)
    {
        if (pen.Style == PenStyle.None)
            return;
        double half = Ready(pen);
        Path(points, half, false);
        cairo_stroke(_cairo);
    }

    // --------------------------------------------------------------- text

    /// Draws from the top-left, which is what every other API in this project
    /// means by a text position -- so the ascent is added to reach the
    /// baseline cairo draws from.
    public void DrawString(String text, Font font, Color colour, int x, int y)
    {
        if (text.IsEmpty)
            return;
        SelectFont(_cairo, font);
        Source(colour);

        cairo_font_extents_t metrics;
        cairo_font_extents(_cairo, &metrics);

        cairo_move_to(_cairo, (double)x, (double)y + metrics.Ascent);
        cairo_show_text(_cairo, text.ToPointer());
        Decorate(text, font, x, y, metrics);
    }

    public void DrawStringIn(String text, Font font, Color colour,
                             Rectangle bounds, TextFormat format)
    {
        if (text.IsEmpty)
            return;
        SelectFont(_cairo, font);
        Source(colour);

        cairo_font_extents_t metrics;
        cairo_font_extents(_cairo, &metrics);
        var extent = MeasureString(text, font);

        int x = bounds.X;
        if (format.Horizontal == HorizontalAlignment.Center)
        {
            x = bounds.X + (bounds.Width - extent.Width) / 2;
        }
        else if (format.Horizontal == HorizontalAlignment.Right)
        {
            x = bounds.X + bounds.Width - extent.Width;
        }

        int y = bounds.Y;
        if (format.Vertical == VerticalAlignment.Middle)
        {
            y = bounds.Y + (bounds.Height - extent.Height) / 2;
        }
        else if (format.Vertical == VerticalAlignment.Bottom)
        {
            y = bounds.Y + bounds.Height - extent.Height;
        }

        // Clipped to the rectangle, which is what makes this different from
        // placing the text by hand: a caption longer than its box stops at
        // the edge rather than running over whatever is beside it.
        cairo_save(_cairo);
        cairo_new_path(_cairo);
        cairo_rectangle(_cairo, (double)bounds.X, (double)bounds.Y,
                        (double)bounds.Width, (double)bounds.Height);
        cairo_clip(_cairo);

        cairo_move_to(_cairo, (double)x, (double)y + metrics.Ascent);
        cairo_show_text(_cairo, text.ToPointer());
        Decorate(text, font, x, y, metrics);
        cairo_restore(_cairo);
    }

    /// Underline and strikeout, which cairo's toy text API does not draw: they
    /// are lines, and their positions are the ones every toolkit uses -- just
    /// under the baseline, and a third of the ascent above it.
    void Decorate(String text, Font font, int x, int y, cairo_font_extents_t metrics)
    {
        if (!font.Underline && !font.Strikeout)
            return;

        var extent = MeasureString(text, font);
        cairo_set_line_width(_cairo, 1.0);
        cairo_set_dash(_cairo, null, 0, 0.0);

        if (font.Underline)
        {
            double at = (double)y + metrics.Ascent + 1.5;
            cairo_new_path(_cairo);
            cairo_move_to(_cairo, (double)x, at);
            cairo_line_to(_cairo, (double)(x + extent.Width), at);
            cairo_stroke(_cairo);
        }
        if (font.Strikeout)
        {
            double at = (double)y + metrics.Ascent - metrics.Ascent / 3.0;
            cairo_new_path(_cairo);
            cairo_move_to(_cairo, (double)x, at);
            cairo_line_to(_cairo, (double)(x + extent.Width), at);
            cairo_stroke(_cairo);
        }
    }

    /// The advance width and the *font's* height, not the ink's.
    ///
    /// `cairo_text_extents` measures the marks the glyphs make, so "an" comes
    /// out shorter than "Ag" and a row of labels would not line up. The width
    /// is the advance -- where the next glyph would start, which is what
    /// laying text out needs -- and the height is the font's line height.
    public FSize MeasureString(String text, Font font)
    {
        SelectFont(_cairo, font);

        cairo_font_extents_t metrics;
        cairo_font_extents(_cairo, &metrics);
        if (text.IsEmpty)
            return Extent(0, (int)metrics.Height);

        cairo_text_extents_t ink;
        cairo_text_extents(_cairo, text.ToPointer(), &ink);
        return Extent((int)(ink.XAdvance + 0.5), (int)(metrics.Height + 0.5));
    }

    // ------------------------------------------------------------ pictures

    public void DrawBitmap(IBitmapBackend picture, Point at)
    {
        var pixbuf = ((GtkBitmapBackend)picture).Pixbuf;
        cairo_save(_cairo);
        gdk_cairo_set_source_pixbuf(_cairo, (GdkPixbuf*)pixbuf,
                                    (double)at.X, (double)at.Y);
        cairo_paint(_cairo);
        cairo_restore(_cairo);
    }

    public void DrawBitmapFaded(IBitmapBackend picture, Point at, int opacity)
    {
        var pixbuf = ((GtkBitmapBackend)picture).Pixbuf;
        cairo_save(_cairo);
        gdk_cairo_set_source_pixbuf(_cairo, (GdkPixbuf*)pixbuf,
                                    (double)at.X, (double)at.Y);
        cairo_paint_with_alpha(_cairo, (double)opacity / 100.0);
        cairo_restore(_cairo);
    }

    /// Scaled into a rectangle. The scaling is cairo's rather than
    /// `gdk_pixbuf_scale_simple`'s, because this happens per frame and a
    /// resampled copy per frame would be the expensive way round.
    public void DrawBitmapIn(IBitmapBackend picture, Rectangle into)
    {
        var pixbuf = (GdkPixbuf*)((GtkBitmapBackend)picture).Pixbuf;
        int width = gdk_pixbuf_get_width(pixbuf);
        int height = gdk_pixbuf_get_height(pixbuf);
        // Nothing to draw into, and a scale by zero would stop the context:
        // see `Ellipse`.
        if (width <= 0 || height <= 0 || into.Width <= 0 || into.Height <= 0)
            return;

        cairo_save(_cairo);
        cairo_new_path(_cairo);
        cairo_rectangle(_cairo, (double)into.X, (double)into.Y,
                        (double)into.Width, (double)into.Height);
        cairo_clip(_cairo);

        cairo_translate(_cairo, (double)into.X, (double)into.Y);
        cairo_scale(_cairo, (double)into.Width / (double)width,
                           (double)into.Height / (double)height);
        gdk_cairo_set_source_pixbuf(_cairo, pixbuf, 0.0, 0.0);
        cairo_paint(_cairo);
        cairo_restore(_cairo);
    }
}

#endif
