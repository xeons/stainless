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

// The other signal shape: one that carries something and answers.
//
// `Gtk.Signals` has the whole explanation; this is the same machinery for
// handlers of the form
//
//     gboolean handler(GtkWidget *widget, gpointer carried, gpointer user_data)
//
// which is a separate module for one reason: `g_signal_connect_data` takes its
// handler as a `GCallback`, C casts every real handler to that, and Stainless
// has no cast between delegate types. So the function is declared once per
// shape, and a shape gets a module.
//
// **Two different signals share this one shape**, which is the piece of luck
// that keeps the count at two:
//
//   - **The input events.** `delete-event`, `button-press-event`,
//     `key-press-event` and the rest carry a `GdkEvent*`.
//   - **Drawing.** GTK 3's `draw` carries a `cairo_t*` and GTK 2's
//     `expose-event` a `GdkEventExpose*`. Both are pointers, both answer
//     `gboolean`, and both are therefore this.
//
// So `carried` is deliberately a bare `gpointer` rather than a `GdkEvent*`:
// what it points at depends on the signal, and the caller of `ConnectEvent` is
// the one that knows.
//
// **The answer means handled.** True stops the signal reaching anything else,
// including the widget's own default handler. Returning true from
// `delete-event` is what keeps a window open; returning true from a draw
// handler is what stops GTK drawing over what you just painted.
module Gtk.Events;

import Gtk.GLib;
import Gtk.GObject;
import Gtk.Api;

#if UNIX

/// What such a signal runs. `carried` is whatever the signal carries -- a
/// `GdkEvent*` for input, a `cairo_t*` for `draw`.
public closure bool EventHandler(GtkWidget* sender, gpointer carried);

/// The shape of the C callback GTK will make.
public delegate gboolean EventCallback(GtkWidget* sender, gpointer carried, gpointer data);

extern "C" {
    void sl_retain(gpointer pointer);
    void sl_release(gpointer pointer);

    gulong g_signal_connect_data(gpointer instance, gchar* signal, EventCallback handler,
                                 gpointer data, GClosureNotify notify, gint flags);
}

/// A closure with an address; see `Gtk.Signals.Boxed`.
class Boxed {
    public EventHandler Body;
    public Boxed(EventHandler body) { Body = body; }
}

gboolean Dispatch(GtkWidget* sender, gpointer carried, gpointer data) {
    var boxed = (Boxed)data;
    return boxed.Body(sender, carried) ? 1 : 0;
}

void Forget(gpointer data, gpointer closure) {
    sl_release(data);
}

/// Connects a handler to a signal that carries a pointer and wants an answer.
public gulong ConnectEvent(GtkWidget* instance, String signal, EventHandler handler) {
    var boxed = new Boxed(handler);
    sl_retain((gpointer)boxed);

    return g_signal_connect_data(instance, signal.ToPointer(),
        Dispatch, (gpointer)boxed, Forget, G_CONNECT_DEFAULT);
}

#endif
