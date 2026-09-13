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

// Cairo: what GTK draws with.
//
// **Not GTK-specific**, which is the useful part. Cairo is its own library
// with its own release schedule, so a paint routine written against this file
// is about drawing rather than about a toolkit version -- and that was true
// back when this binding had a GTK 2 branch, which is why nothing in it had
// one.
//
// Cairo is a stateful painter, not a list of shapes. A call sets the source
// colour, another builds a path, and a third strokes or fills it, at which
// point the path is consumed. Two things follow that catch people out:
//
//   - **`cairo_fill` and `cairo_stroke` clear the path.** Filling *and*
//     outlining one shape means `cairo_fill_preserve` first.
//   - **Colour components are 0.0 to 1.0**, not 0 to 255.
//
// The context a GTK draw handler is given is **borrowed**: it is already
// clipped to the area needing repainting and translated to the widget's
// origin, and it must not be destroyed. One made by `gdk_cairo_create` is
// owned instead, and `cairo_destroy` is what pays for it.
module Gtk.Cairo;

import Gtk.GLib;

#if UNIX

/// `cairo_t*`. Opaque.
public using cairo_t = byte;

/// `cairo_line_cap_t`.
public const gint CAIRO_LINE_CAP_BUTT   = 0;
public const gint CAIRO_LINE_CAP_ROUND  = 1;
public const gint CAIRO_LINE_CAP_SQUARE = 2;

/// `cairo_font_slant_t` and `cairo_font_weight_t`.
public const gint CAIRO_FONT_SLANT_NORMAL = 0;
public const gint CAIRO_FONT_SLANT_ITALIC = 1;
public const gint CAIRO_FONT_WEIGHT_NORMAL = 0;
public const gint CAIRO_FONT_WEIGHT_BOLD   = 1;

/// `cairo_text_extents_t`, filled by `cairo_text_extents`. `Width` and
/// `Height` are the inked area, `XAdvance` how far the pen moves -- which is
/// the one to use for laying text out, because a trailing space has advance
/// and no ink.
public struct cairo_text_extents_t {
    public gdouble XBearing;
    public gdouble YBearing;
    public gdouble Width;
    public gdouble Height;
    public gdouble XAdvance;
    public gdouble YAdvance;
}

public extern "C" {
    // ------------------------------------------------------------- the source

    /// Opaque colour. Components are 0.0 to 1.0.
    void cairo_set_source_rgb(cairo_t* cr, gdouble red, gdouble green, gdouble blue);
    void cairo_set_source_rgba(cairo_t* cr, gdouble red, gdouble green,
                               gdouble blue, gdouble alpha);

    void cairo_set_line_width(cairo_t* cr, gdouble width);
    void cairo_set_line_cap(cairo_t* cr, gint cap);

    // --------------------------------------------------------------- the path

    void cairo_move_to(cairo_t* cr, gdouble x, gdouble y);
    void cairo_line_to(cairo_t* cr, gdouble x, gdouble y);
    void cairo_rectangle(cairo_t* cr, gdouble x, gdouble y, gdouble width, gdouble height);

    /// An arc clockwise from `start` to `stop`, in radians, with zero pointing
    /// right and angles increasing downwards -- because y grows downwards.
    void cairo_arc(cairo_t* cr, gdouble x, gdouble y, gdouble radius,
                   gdouble start, gdouble stop);

    void cairo_curve_to(cairo_t* cr, gdouble x1, gdouble y1, gdouble x2, gdouble y2,
                        gdouble x3, gdouble y3);

    void cairo_close_path(cairo_t* cr);
    void cairo_new_path(cairo_t* cr);

    // ------------------------------------------------------------ the marking

    /// Fills the path and **clears it**.
    void cairo_fill(cairo_t* cr);

    /// Fills and keeps the path, for a shape that is filled and then outlined.
    void cairo_fill_preserve(cairo_t* cr);

    void cairo_stroke(cairo_t* cr);
    void cairo_stroke_preserve(cairo_t* cr);

    /// Paints the source over the whole clip region. What a draw handler calls
    /// first to clear its background.
    void cairo_paint(cairo_t* cr);

    void cairo_clip(cairo_t* cr);
    void cairo_reset_clip(cairo_t* cr);

    // ------------------------------------------------------------------- text

    /// The toy text API, which is what it is called in cairo's own
    /// documentation. Good enough for a label on a chart; Pango is what real
    /// text layout wants.
    void cairo_select_font_face(cairo_t* cr, gchar* family, gint slant, gint weight);
    void cairo_set_font_size(cairo_t* cr, gdouble size);
    void cairo_show_text(cairo_t* cr, gchar* text);
    void cairo_text_extents(cairo_t* cr, gchar* text, cairo_text_extents_t* extents);

    // ------------------------------------------------------------- the matrix

    void cairo_save(cairo_t* cr);
    void cairo_restore(cairo_t* cr);
    void cairo_translate(cairo_t* cr, gdouble x, gdouble y);
    void cairo_scale(cairo_t* cr, gdouble x, gdouble y);
    void cairo_rotate(cairo_t* cr, gdouble radians);

    // ------------------------------------------------------------- ownership

    /// Drops a context the caller owns. **Never** call this on the one a GTK
    /// draw handler was given.
    void cairo_destroy(cairo_t* cr);
}



// ============================================================ what a pen needs

/// `cairo_font_extents_t`: the metrics of a font rather than of a run of text.
/// What a line height is, and the one thing `cairo_text_extents` cannot say --
/// it measures the ink, so "Ag" is taller than "an".
public struct cairo_font_extents_t {
    public double Ascent;
    public double Descent;
    public double Height;
    public double MaxXAdvance;
    public double MaxYAdvance;
}

public extern "C" {
    void cairo_font_extents(cairo_t* cr, cairo_font_extents_t* into);

    /// The dash pattern: `count` lengths in `dashes`, and a `count` of zero is
    /// a solid line. The lengths are in user units, so they scale.
    void cairo_set_dash(cairo_t* cr, gdouble* dashes, gint count, gdouble offset);

    /// Clips to the current path *and* keeps it, which is what pushing a layer
    /// needs -- `cairo_clip` consumes the path and there is then nothing left
    /// to fill.
    void cairo_clip_preserve(cairo_t* cr);

    /// What is left to paint, in user coordinates. A paint handler that only
    /// draws what it has to asks this first.
    void cairo_clip_extents(cairo_t* cr, gdouble* x1, gdouble* y1,
                            gdouble* x2, gdouble* y2);
}

#endif
