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

// Painting a widget yourself.
//
// A widget emits `draw` with a `cairo_t*` already clipped to the damaged
// region and translated to its own corner. A program written against a
// `Painter` never sees either: it is handed a `Canvas` and the size to paint,
// which is the whole of what a paint routine needs and none of what a
// toolkit's signal happens to carry.
//
// Cairo is a stateful painter rather than a list of shapes: set a colour,
// build a path, then fill or stroke it, at which point the path is consumed.
// Two consequences catch people out and `Canvas` keeps them visible rather
// than smoothing them over:
//
//   - **`Fill` and `Stroke` clear the path.** Filling *and* outlining one
//     shape is `FillAndKeep` then `Stroke`.
//   - **Colours are 0.0 to 1.0**, not 0 to 255.
//
// **Paint only inside a paint handler.** There is no drawing outside one;
// asking for a repaint is `Redraw`, and GTK decides when.
module Gtk;

import Gtk.GLib;
import Gtk.GObject;
import Gtk.Gdk;
import Gtk.Api;
import Gtk.Cairo;
import Gtk.Events;


#if UNIX

// ==================================================================== canvas

/// Somewhere to paint.
///
/// Wraps a cairo context and **does not own it**: the one a paint handler is
/// given belongs to GTK under version 3, and to `DrawingArea` under version 2,
/// which destroys it when the handler returns. Keeping a `Canvas` past the end
/// of the handler that was given it is a use-after-free.
public class Canvas {
    cairo_t* cr;

    Canvas(cairo_t* context) { cr = context; }

    /// The cairo context, for a call this layer does not wrap. **Borrowed**,
    /// on the terms above.
    public cairo_t* Handle() { return cr; }

    // ------------------------------------------------------------ the source

    /// Components are 0.0 to 1.0.
    public void SetColor(double red, double green, double blue) {
        cairo_set_source_rgb(cr, red, green, blue);
    }

    /// The same with an alpha, 0.0 clear and 1.0 solid.
    public void SetColorAlpha(double red, double green, double blue, double alpha) {
        cairo_set_source_rgba(cr, red, green, blue, alpha);
    }

    /// A colour written the way a stylesheet writes one: 0xRRGGBB.
    public void SetHexColor(int rgb) {
        double red   = (double)((rgb >> 16) & 0xFF) / 255.0;
        double green = (double)((rgb >> 8) & 0xFF) / 255.0;
        double blue  = (double)(rgb & 0xFF) / 255.0;
        cairo_set_source_rgb(cr, red, green, blue);
    }

    public void SetLineWidth(double width) { cairo_set_line_width(cr, width); }

    /// Rounded ends on a stroked line, which is what a chart wants and a box
    /// does not.
    public void SetRoundEnds(bool round) {
        cairo_set_line_cap(cr, round ? CAIRO_LINE_CAP_ROUND : CAIRO_LINE_CAP_BUTT);
    }

    // -------------------------------------------------------------- the path

    public void MoveTo(double x, double y) { cairo_move_to(cr, x, y); }
    public void LineTo(double x, double y) { cairo_line_to(cr, x, y); }

    public void Rectangle(double x, double y, double width, double height) {
        cairo_rectangle(cr, x, y, width, height);
    }

    /// A whole circle. `Arc` is the one that takes angles.
    public void Circle(double x, double y, double radius) {
        cairo_arc(cr, x, y, radius, 0.0, 6.283185307179586);
    }

    /// An arc clockwise from `start` to `stop`, in radians, with zero pointing
    /// right and angles increasing **downwards** -- because y grows downwards.
    public void Arc(double x, double y, double radius, double start, double stop) {
        cairo_arc(cr, x, y, radius, start, stop);
    }

    public void CurveTo(double x1, double y1, double x2, double y2, double x3, double y3) {
        cairo_curve_to(cr, x1, y1, x2, y2, x3, y3);
    }

    public void ClosePath() { cairo_close_path(cr); }
    public void ClearPath() { cairo_new_path(cr); }

    // ----------------------------------------------------------- the marking

    /// Fills the path and **clears it**.
    public void Fill() { cairo_fill(cr); }

    /// Fills and keeps the path, for a shape that is filled and then outlined.
    public void FillAndKeep() { cairo_fill_preserve(cr); }

    public void Stroke() { cairo_stroke(cr); }
    public void StrokeAndKeep() { cairo_stroke_preserve(cr); }

    /// Paints the current colour over everything. What a paint handler calls
    /// first to clear its background.
    public void Clear() { cairo_paint(cr); }

    /// Limits everything after this to the current path.
    public void Clip() { cairo_clip(cr); }

    // ------------------------------------------------------------------ text

    /// Cairo's own documentation calls this the toy text API, and it is: good
    /// enough for a label on a chart, and not what real text layout wants.
    public void SetFont(String family, double size, bool bold) {
        cairo_select_font_face(cr, family.ToPointer(), CAIRO_FONT_SLANT_NORMAL,
            bold ? CAIRO_FONT_WEIGHT_BOLD : CAIRO_FONT_WEIGHT_NORMAL);
        cairo_set_font_size(cr, size);
    }

    /// Draws text with its **baseline** at `y`, not its top. That is the one
    /// thing to remember about drawing text anywhere.
    public void DrawText(String text, double x, double y) {
        cairo_move_to(cr, x, y);
        cairo_show_text(cr, text.ToPointer());
    }

    /// How wide the text will be: the pen advance rather than the inked width,
    /// so a trailing space counts. What centring wants.
    public double TextWidth(String text) {
        cairo_text_extents_t extents;
        cairo_text_extents(cr, text.ToPointer(), &extents);
        return extents.XAdvance;
    }

    // ---------------------------------------------------------- the transform

    /// Saves the colour, line width, font and transform. Paired with
    /// `Restore`, and the way to keep one part of a drawing from leaking
    /// settings into the next.
    public void Save() { cairo_save(cr); }
    public void Restore() { cairo_restore(cr); }

    public void Translate(double x, double y) { cairo_translate(cr, x, y); }
    public void Scale(double x, double y) { cairo_scale(cr, x, y); }
    public void Rotate(double radians) { cairo_rotate(cr, radians); }
}

// =================================================================== painter

/// What a `DrawingArea` calls to paint itself.
///
/// The size is passed rather than asked for, because the two versions ask
/// differently -- `gtk_widget_get_allocated_width` against
/// `gtk_widget_get_allocation` -- and a painter should not have to know which
/// GTK it is running on.
public closure void Painter(Canvas canvas, int width, int height);

/// The adapter from a raw signal to a painter, which is where the whole
/// version difference lives -- and it is eleven lines.
///
/// A function returning a closure rather than a class implementing an
/// interface: the lambda it returns captures the painter, which is exactly
/// what the class's field used to be.
EventHandler PaintAdapter(Painter body) {
    return (sender, carried) => {
            // GTK 3 hands over a context that is already clipped and
            // translated, and owns it.
            var canvas = new Canvas((cairo_t*)carried);
            body(canvas, gtk_widget_get_allocated_width(sender),
                         gtk_widget_get_allocated_height(sender));

        // True: this widget has painted itself and nothing else should.
        return true;
    };
}

// ============================================================== drawing area

/// A widget that draws nothing, so that a program can draw everything.
public class DrawingArea : Widget {
    public DrawingArea() { base(gtk_drawing_area_new()); }

    /// Sets what paints the widget. Connecting a second one replaces nothing
    /// -- GTK runs both, in the order they were connected, and the first to
    /// answer true stops the rest.
    public void OnPaint(Painter painter) {
            ConnectEvent(handle, "draw", PaintAdapter(painter));
    }

    /// Asks to receive mouse and key events.
    ///
    /// **A drawing area gets almost none by default**, which is the reason a
    /// first mouse handler on one never fires. Call this before connecting
    /// anything, and note that keys also need the widget to be able to take
    /// focus.
    public void WantInput() {
        gtk_widget_add_events(handle,
            GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK |
            GDK_POINTER_MOTION_MASK | GDK_KEY_PRESS_MASK | GDK_SCROLL_MASK);
        gtk_widget_set_can_focus(handle, 1);
    }
}

// ==================================================================== input

/// Where the pointer was and what was held down.
public struct Pointer {
    public double X;
    public double Y;

    /// 1 is left, 2 is middle, 3 is right. Zero for a move, which has no
    /// button.
    public int Button;

    public bool Shift;
    public bool Control;
    public bool Alt;
}

/// A key press, as the key and the modifiers.
public struct Key {
    /// A `GDK_KEY_*` value.
    public uint Code;

    /// The character it stands for, or 0 for a key that is not one --
    /// which is what to test for text, rather than comparing `Code`.
    public char32 Character;

    public bool Shift;
    public bool Control;
    public bool Alt;
}

/// What a mouse event runs. True means handled.
public closure bool PointerHandler(Pointer at);

/// What a key event runs. True means handled.
public closure bool KeyHandler(Key key);

EventHandler PointerAdapter(PointerHandler body) {
    return (sender, carried) => {
        GdkEvent* event = (GdkEvent*)carried;

        Pointer at;
        at.X = 0.0;
        at.Y = 0.0;
        gdk_event_get_coords(event, &at.X, &at.Y);

        guint state = 0u;
        gdk_event_get_state(event, &state);
        at.Shift   = (state & GDK_SHIFT_MASK) != 0u;
        at.Control = (state & GDK_CONTROL_MASK) != 0u;
        at.Alt     = (state & GDK_MOD1_MASK) != 0u;

        guint button = 0u;
            gdk_event_get_button(event, &button);
        at.Button = (int)button;

        return body(at);
    };
}

EventHandler KeyAdapter(KeyHandler body) {
    return (sender, carried) => {
        GdkEvent* event = (GdkEvent*)carried;

        guint code = 0u;
            gdk_event_get_keyval(event, &code);

        guint state = 0u;
        gdk_event_get_state(event, &state);

        Key key;
        key.Code = code;
        key.Character = (char32)gdk_keyval_to_unicode(code);
        key.Shift   = (state & GDK_SHIFT_MASK) != 0u;
        key.Control = (state & GDK_CONTROL_MASK) != 0u;
        key.Alt     = (state & GDK_MOD1_MASK) != 0u;

        return body(key);
    };
}

#endif
