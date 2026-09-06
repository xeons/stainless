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
// exist in both GTK 2 and GTK 3, and are what `Gtk` calls. Four more --
// `gdk_event_get_button`, `_keyval`, `_event_type` and `_click_count` -- were
// added in GTK 3.2 and are **not** in GTK 2, so they sit behind the `#if` and
// the GTK 2 side reads two structs instead. Those two are declared below with
// their offsets spelled out, because a wrong one there is silently wrong data
// rather than a link error.
//
// The one field that is safe to read from any event is the **type**, which is
// the first member of every struct in the union by construction. `EventType`
// below is that, and nothing else.
module Gtk.Gdk;

import Gtk.GLib;

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

public extern "C" {
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

#if !GTK2

public extern "C" {
    /// GTK 3.2 and later. The GTK 2 branch reads the struct instead.
    gint     gdk_event_get_event_type(GdkEvent* event);
    gboolean gdk_event_get_button(GdkEvent* event, guint* button);
    gboolean gdk_event_get_keyval(GdkEvent* event, guint* keyval);
    gboolean gdk_event_get_click_count(GdkEvent* event, guint* count);
    gboolean gdk_event_get_scroll_direction(GdkEvent* event, gint* direction);
}

#else

// GTK 2 has none of those, so the two structs a program actually reads are
// declared here. **The offsets are the point of these declarations**, so they
// are written out: every event begins with the same four members, and the
// interesting fields follow at fixed places on a 64-bit build.
//
//     0   GdkEventType   type          (an enum, so four bytes)
//     4                  -- padding to the pointer's alignment
//     8   GdkWindow*     window
//     16  gint8          send_event
//     20  guint32        time
//
// Nothing below reads `window` or `send_event`; they are present so that the
// members after them land where C puts them.

/// `GdkEventButton`, as far as the fields worth reading.
public struct GdkEventButton {
    public gint    Type;
    public gint    Padding;
    public GdkWindow* Window;
    public sbyte   SendEvent;
    public byte[3] SendEventPadding;
    public guint32 Time;

    /// Where the pointer was, relative to the event's window.
    public gdouble X;
    public gdouble Y;

    public gdouble* Axes;
    public guint    State;

    /// 1 is left, 2 is middle, 3 is right.
    public guint    Button;
}

/// `GdkEventKey`, as far as the fields worth reading.
public struct GdkEventKey {
    public gint    Type;
    public gint    Padding;
    public GdkWindow* Window;
    public sbyte   SendEvent;
    public byte[3] SendEventPadding;
    public guint32 Time;

    public guint   State;

    /// The `GDK_KEY_*` value.
    public guint   Keyval;
}

#endif

/// The type of any event, which is the one field every struct in the union
/// shares and the only one safe to read without knowing which it is.
///
/// GTK 3 has a function for it and GTK 2 does not, so this is where the two
/// meet. It is a read of offset zero either way -- the accessor does the same
/// thing -- and going through the function under GTK 3 keeps the binding
/// honest if GDK ever changes its mind about the layout.
public gint EventType(GdkEvent* event) {
    #if !GTK2
        return gdk_event_get_event_type(event);
    #else
        return *(gint*)event;
    #endif
}

#endif
