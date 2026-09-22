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

// GDK: events, keys and the screen, declared and nothing else.
//
// **Read the events through the accessors where there are any.** `GdkEvent` is
// a union of thirty-odd structs and a binding that declares them is a binding
// that has to get every offset right, on every architecture, for a layout the
// headers are free to extend. GDK supplies functions for the fields a program
// actually wants, and this file prefers them:
//
//     gdk_event_get_coords, gdk_event_get_state, gdk_event_get_root_coords
//
// are what `Gtk` calls, along with `gdk_event_get_button`, `_keyval`,
// `_event_type` and `_click_count`, which arrived in GTK 3.2. Between them
// they are every field this binding reads, so no struct in the union is
// declared here at all -- which is the point, because a wrong offset is
// silently wrong data rather than a link error.
//
// The one field that is safe to read from any event is the **type**, which is
// the first member of every struct in the union by construction. `EventType`
// below is that, and nothing else.
module Gtk.Gdk;

import Gtk.GLib;
import Gtk.GObject;

#if UNIX

/// `GdkEvent*`. A union, and opaque here on purpose.
public using GdkEvent = byte;

/// `GdkWindow*`, `GdkScreen*`, `GdkDisplay*`. Opaque.
public using GdkWindow = byte;

// =============================================================== event types

/// `GdkEventType`. The value at offset zero of every event.
public const gint GDK_NOTHING          = -1;
public const gint GDK_DELETE           = 0;
public const gint GDK_DESTROY          = 1;
public const gint GDK_EXPOSE           = 2;
public const gint GDK_MOTION_NOTIFY    = 3;
public const gint GDK_BUTTON_PRESS     = 4;
public const gint GDK_2BUTTON_PRESS    = 5;
public const gint GDK_3BUTTON_PRESS    = 6;
public const gint GDK_BUTTON_RELEASE   = 7;
public const gint GDK_KEY_PRESS        = 8;
public const gint GDK_KEY_RELEASE      = 9;
public const gint GDK_ENTER_NOTIFY     = 10;
public const gint GDK_LEAVE_NOTIFY     = 11;
public const gint GDK_FOCUS_CHANGE     = 12;
public const gint GDK_CONFIGURE        = 13;
public const gint GDK_MAP              = 14;
public const gint GDK_UNMAP            = 15;
public const gint GDK_SCROLL           = 31;

/// `GdkModifierType`, as reported by `gdk_event_get_state`.
///
/// `MOD1` is Alt on every keyboard anyone has. The name is X11's: a modifier
/// is a keycode range, and which key is bound to which range is the user's
/// business, so X refuses to call it Alt and GDK inherited the refusal.
public const guint GDK_SHIFT_MASK   = 1u;
public const guint GDK_LOCK_MASK    = 2u;
public const guint GDK_CONTROL_MASK = 4u;
public const guint GDK_MOD1_MASK    = 8u;
public const guint GDK_BUTTON1_MASK = 256u;
public const guint GDK_BUTTON2_MASK = 512u;
public const guint GDK_BUTTON3_MASK = 1024u;
public const guint GDK_SUPER_MASK   = 67108864u;

/// `GdkEventMask`, for `gtk_widget_add_events`.
///
/// **A `GtkDrawingArea` receives almost nothing by default.** A mouse handler
/// on one that never fires is this, every time.
public const gint GDK_EXPOSURE_MASK        = 2;
public const gint GDK_POINTER_MOTION_MASK  = 4;
public const gint GDK_BUTTON_PRESS_MASK    = 256;
public const gint GDK_BUTTON_RELEASE_MASK  = 512;
public const gint GDK_KEY_PRESS_MASK       = 1024;
public const gint GDK_KEY_RELEASE_MASK     = 2048;
public const gint GDK_ENTER_NOTIFY_MASK    = 4096;
public const gint GDK_LEAVE_NOTIFY_MASK    = 8192;
public const gint GDK_FOCUS_CHANGE_MASK    = 16384;
public const gint GDK_SCROLL_MASK          = 2097152;

/// `GdkScrollDirection`.
public const gint GDK_SCROLL_UP     = 0;
public const gint GDK_SCROLL_DOWN   = 1;
public const gint GDK_SCROLL_LEFT   = 2;
public const gint GDK_SCROLL_RIGHT  = 3;
public const gint GDK_SCROLL_SMOOTH = 4;

// ================================================================== keyvals

/// `GDK_KEY_*`, for the keys a program tests by name rather than by character.
///
/// A printable key's keyval is its Unicode code point for Latin-1 and a
/// 0x01000000-based value above that, so a program handling text should use
/// the `gunichar` from `gdk_keyval_to_unicode` rather than comparing against
/// constants.
public const guint GDK_KEY_BackSpace = 0xff08u;
public const guint GDK_KEY_Tab       = 0xff09u;
public const guint GDK_KEY_Return    = 0xff0du;
public const guint GDK_KEY_Escape    = 0xff1bu;
public const guint GDK_KEY_Delete    = 0xffffu;
public const guint GDK_KEY_Home      = 0xff50u;
public const guint GDK_KEY_Left      = 0xff51u;
public const guint GDK_KEY_Up        = 0xff52u;
public const guint GDK_KEY_Right     = 0xff53u;
public const guint GDK_KEY_Down      = 0xff54u;
public const guint GDK_KEY_Page_Up   = 0xff55u;
public const guint GDK_KEY_Page_Down = 0xff56u;
public const guint GDK_KEY_End       = 0xff57u;
public const guint GDK_KEY_Insert    = 0xff63u;
public const guint GDK_KEY_F1        = 0xffbeu;
public const guint GDK_KEY_F2        = 0xffbfu;
public const guint GDK_KEY_F3        = 0xffc0u;
public const guint GDK_KEY_F4        = 0xffc1u;
public const guint GDK_KEY_F5        = 0xffc2u;
public const guint GDK_KEY_F6        = 0xffc3u;
public const guint GDK_KEY_F7        = 0xffc4u;
public const guint GDK_KEY_F8        = 0xffc5u;
public const guint GDK_KEY_F9        = 0xffc6u;
public const guint GDK_KEY_F10       = 0xffc7u;
public const guint GDK_KEY_F11       = 0xffc8u;
public const guint GDK_KEY_F12       = 0xffc9u;
public const guint GDK_KEY_space     = 0x020u;

// ============================================================== the accessors

public extern "C"
{
    /// The pointer position in the event's own window. False if the event
    /// carries no position, which every key event is.
    gboolean gdk_event_get_coords(GdkEvent* event, gdouble* x, gdouble* y);

    /// The same in root-window coordinates, which is what a popup wants.
    gboolean gdk_event_get_root_coords(GdkEvent* event, gdouble* x, gdouble* y);

    /// The modifier keys held down. False if the event has no state.
    gboolean gdk_event_get_state(GdkEvent* event, guint* state);

    /// The code point a keyval stands for, or 0 for a key that is not a
    /// character. The right way to turn a key press into text.
    guint gdk_keyval_to_unicode(guint keyval);
    guint gdk_unicode_to_keyval(guint codePoint);

    /// The name X11 gives a keyval -- "Return", "a", "F1". **Borrowed.**
    gchar* gdk_keyval_name(guint keyval);

    gpointer gdk_screen_get_default();
    gpointer gdk_display_get_default();
}

// ============================================================== reading events


public extern "C"
{
    /// GTK 3.2 and later, which is every GTK 3 worth running.
    gint     gdk_event_get_event_type(GdkEvent* event);
    gboolean gdk_event_get_button(GdkEvent* event, guint* button);
    gboolean gdk_event_get_keyval(GdkEvent* event, guint* keyval);
    gboolean gdk_event_get_click_count(GdkEvent* event, guint* count);
    gboolean gdk_event_get_scroll_direction(GdkEvent* event, gint* direction);
}


/// The type of any event, which is the one field every struct in the union
/// shares and the only one safe to read without knowing which it is.
///
/// A read of offset zero, in effect, since the type is the first member of
/// every struct in the union by construction. Going through the accessor
/// rather than doing that read keeps the binding honest if GDK ever changes
/// its mind about the layout.
public gint EventType(GdkEvent* event)
{
    return gdk_event_get_event_type(event);
}

// =================================================================== shapes

/// `GdkRectangle`, which is public in the header and is four `int`s. What a
/// monitor's geometry and work area are reported in.
public struct GdkRectangle
{
    public gint X;
    public gint Y;
    public gint Width;
    public gint Height;
}

/// `GdkRGBA`: four components from 0.0 to 1.0, the way cairo wants them
/// rather than the way a byte-per-channel colour is written.
public struct GdkRGBA
{
    public gdouble Red;
    public gdouble Green;
    public gdouble Blue;
    public gdouble Alpha;
}

// ================================================================== windows

public extern "C"
{
    void gdk_window_set_cursor(GdkWindow* window, gpointer cursor);
    void gdk_window_get_origin(GdkWindow* window, gint* x, gint* y);

    /// Raises a window above its siblings.
    ///
    /// GDK rather than GTK because there is no GTK call for it: the container
    /// that gives a child its own window is what stacking applies to, and
    /// `gtk_widget_set_child_visible` and friends say nothing about order.
    void gdk_window_raise(GdkWindow* window);

    /// Where the pointer is, in this window's own coordinates.
    ///
    /// The device has to be named because X11 has had more than one pointer
    /// since XInput2, and the seat is how GTK 3 says "the one this display is
    /// being driven by". `gdk_window_get_pointer` is the one-argument version
    /// and has been deprecated since 3.0.
    gpointer gdk_window_get_device_position(GdkWindow* window, gpointer device,
                                            gint* x, gint* y, guint* mask);
    gpointer gdk_display_get_default_seat(gpointer display);
    gpointer gdk_seat_get_pointer(gpointer seat);

    /// Paints whatever is waiting to be painted, now, rather than when the
    /// frame clock next ticks. The GDK answer to `UpdateWindow`.
    ///
    /// **Deprecated since 3.22 and used anyway**, because nothing replaced it.
    /// A GTK 3 draw is scheduled on the frame clock, so after a
    /// `gtk_widget_queue_draw` there is usually nothing *pending* at all --
    /// `gtk_events_pending` answers zero and a non-blocking pump returns having
    /// painted nothing. The suggested replacement is to stop wanting a
    /// synchronous repaint, which is not available to a seam that has one on
    /// the other side.
    void gdk_window_process_updates(GdkWindow* window, gboolean children);
}

// `gtk_widget_get_window` is the way to one of these, and it is a GTK call
// rather than a GDK one, so it lives in `Gtk.Api` -- which is also what keeps
// this file from having to name a `GtkWidget`.

// ================================================================== cursors

public extern "C"
{
    /// A cursor by CSS name -- `"default"`, `"text"`, `"pointer"`, `"wait"`,
    /// `"crosshair"`, `"ew-resize"`, `"ns-resize"`, `"move"`, `"not-allowed"`.
    ///
    /// Names rather than the `GdkCursorType` enum, which is deprecated and
    /// whose members do not all have a theme behind them. Answers null when
    /// the theme has no such cursor, and a null cursor means "inherit", which
    /// is a reasonable thing for an unknown name to do.
    gpointer gdk_cursor_new_from_name(gpointer display, gchar* name);
}

// ================================================================= monitors

public extern "C"
{
    /// **Borrowed.** Null on a display with no monitor the compositor calls
    /// primary, which is why the backend falls back to monitor 0.
    gpointer gdk_display_get_primary_monitor(gpointer display);
    gpointer gdk_display_get_monitor(gpointer display, gint number);
    gint     gdk_display_get_n_monitors(gpointer display);

    void gdk_monitor_get_geometry(gpointer monitor, GdkRectangle* into);

    /// The part not covered by a panel or a dock. The same as the geometry on
    /// a compositor that does not report one, which is what a window centring
    /// itself should fall back to anyway.
    void gdk_monitor_get_workarea(gpointer monitor, GdkRectangle* into);
}

// ==================================================================== atoms

/// `GdkAtom`: an interned string, compared by address. Opaque, and never
/// freed.
public using GdkAtom = byte*;

public extern "C"
{
    /// The atom for a name. With `onlyIfExists` set, null for a name nothing
    /// has interned yet.
    GdkAtom gdk_atom_intern(gchar* name, gboolean onlyIfExists);

    /// The name, **owned by the caller**: `g_free` it.
    gchar* gdk_atom_name(GdkAtom atom);

    /// Whether the display reports a change of selection owner, which is what
    /// makes `owner-change` fire. X11 with XFixes and Wayland do; Broadway
    /// does not.
    gboolean gdk_display_supports_selection_notification(gpointer display);
}

// ================================================================== pixbufs

/// `GdkPixbuf*`: an image in memory, and a `GObject` rather than a widget --
/// so its reference is **not** floating and `g_object_ref_sink` would be
/// wrong on one.
public using GdkPixbuf = byte;

public extern "C"
{
    /// Null on failure, with `error` filled in. Reads whatever the installed
    /// loaders read, which on any desktop is at least PNG, JPEG and BMP --
    /// the one place this backend does more than the Win32 one, which has
    /// `.bmp` and nothing else.
    GdkPixbuf* gdk_pixbuf_new_from_file(gchar* path, GError** error);

    gint gdk_pixbuf_get_width(GdkPixbuf* pixbuf);
    gint gdk_pixbuf_get_height(GdkPixbuf* pixbuf);

    /// An empty pixbuf that owns its own pixels.
    ///
    /// **This rather than `gdk_pixbuf_new_from_data`**, which does not copy:
    /// that one points at the caller's memory for the pixbuf's whole life, and
    /// handing it the interior of a Stainless array would hand GTK something
    /// ARC is entitled to free first. This allocates, `gdk_pixbuf_get_pixels`
    /// says where, and the copy is the caller's to make.
    ///
    /// `colourspace` is `GDK_COLORSPACE_RGB`, which is 0 and the only one
    /// there has ever been; `bitsPerSample` is 8 and nothing else is
    /// supported.
    GdkPixbuf* gdk_pixbuf_new(gint colourspace, gboolean hasAlpha, gint bitsPerSample,
                              gint width, gint height);

    /// The pixels themselves: red, green, blue and then alpha where there is
    /// one -- not the blue-first order Windows uses.
    byte* gdk_pixbuf_get_pixels(GdkPixbuf* pixbuf);

    /// Bytes from the start of one row to the start of the next, which is
    /// **not** width times four: gdk-pixbuf aligns rows, so a copy that
    /// assumes otherwise shears the picture.
    gint gdk_pixbuf_get_rowstride(GdkPixbuf* pixbuf);

    /// Whether there is a fourth byte per pixel. Non-zero for yes.
    gboolean gdk_pixbuf_get_has_alpha(GdkPixbuf* pixbuf);

    /// Bytes per pixel: 3 without alpha, 4 with.
    gint gdk_pixbuf_get_n_channels(GdkPixbuf* pixbuf);

    /// Bits per channel. 8 for every pixbuf gdk-pixbuf makes.
    gint gdk_pixbuf_get_bits_per_sample(GdkPixbuf* pixbuf);

    /// A new pixbuf at another size. `GDK_INTERP_BILINEAR` is 2.
    GdkPixbuf* gdk_pixbuf_scale_simple(GdkPixbuf* pixbuf, gint width, gint height,
                                       gint interpolation);

    /// The `GType` of a pixbuf, for a tree model column that holds one.
    /// A call rather than a constant, because it is registered at run time.
    GType gdk_pixbuf_get_type();

    /// Makes the pixbuf the source for the next cairo operation, with its
    /// top-left corner at (`x`, `y`). `cairo_paint` then draws it.
    void gdk_cairo_set_source_pixbuf(gpointer cairo, GdkPixbuf* pixbuf,
                                     gdouble x, gdouble y);
}

/// Decoding an image that is already in memory rather than on disk.
///
/// `gdk_pixbuf_new_from_file` is the usual way in and takes a path, which is no
/// use for bytes that came out of the binary's own `.rsrc` section. A loader is
/// the streaming form of the same decoders: feed it the bytes, close it, and
/// ask for the result.
///
/// **Close it before asking.** The pixbuf is not complete until `close` has
/// run, and `close` is also what reports a truncated or unrecognised image.
/// What `get_pixbuf` returns belongs to the loader, so it must be referenced
/// before the loader is dropped.
public using GdkPixbufLoader = byte;

public extern "C"
{
    GdkPixbufLoader* gdk_pixbuf_loader_new();
    gboolean gdk_pixbuf_loader_write(GdkPixbufLoader* loader, byte* bytes,
                                     gsize count, GError** error);
    gboolean gdk_pixbuf_loader_close(GdkPixbufLoader* loader, GError** error);

    /// The decoded image, or null. Owned by the loader until referenced.
    GdkPixbuf* gdk_pixbuf_loader_get_pixbuf(GdkPixbufLoader* loader);
}

public const gint GDK_INTERP_NEAREST  = 0;
public const gint GDK_INTERP_BILINEAR = 2;

#endif
