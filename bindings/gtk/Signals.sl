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

// How a GTK signal reaches a Stainless object: the signals that carry nothing.
//
// This is the whole of the binding's cleverness, and it is worth reading once
// because everything in `Gtk` rests on it.
//
// **The problem.** A `delegate` is a bare C function pointer: it captures
// nothing, which is exactly what makes it callable by C with no thunk, and
// exactly what stops it being a handler for *this* button. GTK's answer is the
// one every C library gives -- a `gpointer user_data` alongside the callback --
// so the object goes through that.
//
// **The three moves.**
//
//   1. A handler is an ordinary Stainless object implementing `IHandler`. A
//      lambda becomes one, because a lambda takes its type from what it is
//      assigned to and an interface with one method is something it may become
//      (§2.15).
//
//   2. It is **retained by hand** on the way out, because C is about to hold
//      the only reference to it and the compiler cannot see that. The matching
//      release is the `GClosureNotify` that `g_signal_connect_data` takes,
//      which GTK runs after the last emission -- whether the handler was
//      disconnected or the widget died holding it.
//
//   3. It comes back as a `gpointer` and is cast to the interface. Nothing
//      checks that cast, which is why the dispatcher below is paired with
//      exactly one connect function: the only pointer that ever reaches
//      `Dispatch` is one `ConnectPlain` put there.
//
// **Why `g_signal_connect_data` is declared here and not in `Gtk.GObject`.**
// Its handler parameter is `GCallback`, `void (*)(void)`, which every C caller
// casts its real handler to. Stainless has no cast between delegate types, so
// the declaration is written with the handler shape it is used at -- this
// module for `void (GtkWidget*, gpointer)` and `Gtk.Events` for the shape that
// carries an event and answers. The same C function, declared twice, in the
// two shapes GTK actually emits.
module Gtk.Signals;

import Gtk.GLib;
import Gtk.GObject;
import Gtk.Api;

#if UNIX

/// The shape of a signal that carries nothing: `clicked`, `activate`,
/// `changed`, `destroy`, `toggled`, `value-changed`.
public delegate void PlainCallback(GtkWidget* sender, gpointer data);

extern "C" {
    void sl_retain(gpointer pointer);
    void sl_release(gpointer pointer);

    gulong g_signal_connect_data(gpointer instance, gchar* signal, PlainCallback handler,
                                 gpointer data, GClosureNotify notify, gint flags);
}

/// What a signal that carries nothing calls.
public interface IHandler {
    void Handle(GtkWidget* sender);
}

/// The C entry point. **One per signal shape, not one per handler**: a
/// module-level function, so its address is a plain C function pointer and
/// there is no thunk anywhere in this file.
void Dispatch(GtkWidget* sender, gpointer data) {
    var handler = (IHandler)data;
    handler.Handle(sender);
}

/// The release half of every connection here.
///
/// GTK calls this once, after the last emission. That it runs on a widget's
/// destruction as well as on an explicit disconnect is what makes the whole
/// arrangement leak-free without a line of bookkeeping in `Gtk`.
void Forget(gpointer data, gpointer closure) {
    sl_release(data);
}

/// Connects a handler to a signal that carries nothing.
///
/// Answers the handler id, which `Disconnect` takes and almost nothing needs:
/// a handler normally lives exactly as long as the widget it is on.
public gulong ConnectPlain(GtkWidget* instance, String signal, IHandler handler) {
    sl_retain((gpointer)handler);

    return g_signal_connect_data(instance, signal.ToPointer(),
        Dispatch, (gpointer)handler, Forget, G_CONNECT_DEFAULT);
}

/// Drops a connection early. The handler's release happens in `Forget`,
/// exactly as it would have on the widget's destruction.
public void Disconnect(GtkWidget* instance, gulong handler) {
    g_signal_handler_disconnect(instance, handler);
}

#endif
