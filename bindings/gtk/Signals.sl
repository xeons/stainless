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

// How a GTK signal reaches a Stainless handler: the signals that carry nothing.
//
// **The problem.** A `delegate` is a bare C function pointer, which is exactly
// what makes it callable by C with no thunk and exactly what stops it being a
// handler for *this* button. GTK's answer is the one every C library gives -- a
// `gpointer user_data` beside the callback -- and Stainless's answer to what
// goes in it is a `closure` (§2.14.1): a method and the object it belongs to.
//
// **The three moves.**
//
//   1. The handler is a closure. A bound method and a capturing lambda are both
//      one, and both are two words: a function and a receiver.
//
//   2. A closure is a value, and `user_data` is one pointer, so it is **boxed**
//      -- put in a small object whose address C can hold. That object is
//      retained by hand, because C is about to hold the only reference to it.
//
//   3. The matching release is the `GClosureNotify` that
//      `g_signal_connect_data` takes, which GTK runs after the last emission --
//      whether the handler was disconnected or the widget died holding it. That
//      is what makes the whole arrangement leak-free with no bookkeeping
//      anywhere else.
//
// **Why `g_signal_connect_data` is declared here and not in `Gtk.GObject`.**
// Its handler parameter is `GCallback`, `void (*)(void)`, which every C caller
// casts its real handler to. Stainless has no cast between delegate types, so
// the declaration is written with the shape it is used at -- this module for
// `void (GtkWidget*, gpointer)` and `Gtk.Events` for the shape that carries
// something and answers. The same C function, declared twice, in the two shapes
// GTK actually emits.
module Gtk.Signals;

import Gtk.GLib;
import Gtk.GObject;
import Gtk.Api;

#if UNIX

/// What a signal that carries nothing runs: `clicked`, `activate`, `changed`,
/// `destroy`, `toggled`, `value-changed`.
///
/// A closure, so `button.OnClicked(this.Save)` and
/// `button.OnClicked(() => { count = count + 1; })` are both handlers and both
/// keep whatever they need alive.
public closure void Handler();

/// The shape of the C callback GTK will make.
public delegate void PlainCallback(GtkWidget* sender, gpointer data);

extern "C"
{
    void sl_retain(gpointer pointer);
    void sl_release(gpointer pointer);

    gulong g_signal_connect_data(gpointer instance, gchar* signal, PlainCallback handler,
                                 gpointer data, GClosureNotify notify, gint flags);
}

/// A closure with an address, since `user_data` is one pointer and a closure is
/// two words. The one allocation a subscription costs.
class Boxed
{
    public Handler Body;
    public Boxed(Handler body) => Body = body;
}

/// The C entry point. **One per signal shape, not one per handler**: a
/// module-level function, so its address is a plain C function pointer and
/// there is no thunk anywhere in this file.
void Dispatch(GtkWidget* sender, gpointer data)
{
    var boxed = (Boxed)data;
    boxed.Body();
}

/// The release half of every connection here.
void Forget(gpointer data, gpointer closure)
{
    sl_release(data);
}

/// Connects a handler to a signal that carries nothing.
///
/// Answers the handler id, which `Disconnect` takes and almost nothing needs:
/// a handler normally lives exactly as long as the widget it is on.
public gulong ConnectPlain(GtkWidget* instance, String signal, Handler handler)
{
    var boxed = new Boxed(handler);
    sl_retain((gpointer)boxed);

    return g_signal_connect_data(instance, signal.ToPointer(),
        Dispatch, (gpointer)boxed, Forget, G_CONNECT_DEFAULT);
}

/// Drops a connection early. The release happens in `Forget`, exactly as it
/// would have on the widget's destruction.
public void Disconnect(GtkWidget* instance, gulong handler)
{
    g_signal_handler_disconnect(instance, handler);
}

#endif
