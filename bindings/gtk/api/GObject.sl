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

// GObject: reference counting, signals and properties, declared and nothing
// else.
//
// Every GTK widget is a GObject, so this is the file that decides what a
// binding's ownership rules are. Three things a reader coming from Stainless
// should know before the declarations make sense:
//
//   - **GObject is reference counted, and so is Stainless.** They are separate
//     counts on separate objects: a `Gtk.Widget` wrapper holds one reference
//     to the C object, and `sl_release`ing the wrapper is what drops it. The
//     two never see each other's numbers.
//
//   - **A fresh widget's reference is *floating*.** `gtk_window_new` hands
//     back a count of one that nobody owns, on the theory that the container
//     you are about to add it to will claim it. A wrapper that wants to hold
//     the widget itself calls `g_object_ref_sink`, which converts the floating
//     reference into a real one instead of adding a second.
//
//   - **A signal handler outlives the call that connected it**, so anything it
//     needs must outlive it too. `g_signal_connect_data` takes a
//     `GDestroyNotify` for exactly this, and it is where a Stainless object
//     handed over as `user_data` gets its matching release.
//
// The last of those is the whole trick a GTK binding turns on, and it is
// `Gtk.Signals` that turns it.
module Gtk.GObject;

import Gtk.GLib;

#if UNIX

// =================================================================== types

/// `GType`, the runtime type id. A `gsize`, and 0 is invalid.
public using GType = nuint;

/// `GObject*`, `GTypeInstance*` and friends, none of which this binding needs
/// to see inside. Kept as a pointer to bytes so that no layout is claimed.
public using GObjectRef = byte*;

/// `GClosureNotify`: like `GDestroyNotify`, with the closure passed along.
///
/// The second parameter is the `GClosure` being destroyed, which a binding has
/// no use for; what matters is that this runs exactly once, after the last
/// emission, whether the handler was disconnected or the object died.
public delegate void GClosureNotify(gpointer data, gpointer closure);

// ============================================================ the reference

public extern "C" {
    /// Adds a reference. Answers the same pointer, so it composes.
    gpointer g_object_ref(gpointer instance);

    /// Drops one. The object is finalised when the last goes.
    void g_object_unref(gpointer instance);

    /// Takes ownership of a floating reference, or adds a real one if the
    /// reference was not floating.
    ///
    /// **This is what a wrapper calls on a freshly constructed widget.**
    /// `gtk_button_new()` answers with a floating reference; sinking it means
    /// the wrapper owns the widget and `g_object_unref` in the destructor is
    /// balanced. Without it, adding the widget to a container would claim the
    /// float and the wrapper's later unref would be one too many.
    gpointer g_object_ref_sink(gpointer instance);

    /// Whether the reference is still floating, which is worth an assertion
    /// while a binding is being written and nothing afterwards.
    gboolean g_object_is_floating(gpointer instance);
}

// ============================================================== attached data

public extern "C" {
    /// Attaches a pointer to an object under a name, with a notify that runs
    /// when the object dies or the key is replaced.
    ///
    /// This is how a C widget finds its Stainless wrapper: the wrapper stores
    /// itself here, retained, and any callback holding only a `GtkWidget*` can
    /// get back to it. The notify is what releases it.
    void g_object_set_data_full(gpointer instance, gchar* key,
                                gpointer data, GDestroyNotify notify);

    void     g_object_set_data(gpointer instance, gchar* key, gpointer data);
    gpointer g_object_get_data(gpointer instance, gchar* key);
}

// ================================================================ properties

public extern "C" {
    /// Sets one property by name. Variadic, and **every value must be exactly
    /// the property's type**: a `gboolean` property given a Stainless `bool`
    /// would read three bytes of something else.
    ///
    /// The typed setters GTK provides are better wherever one exists; this is
    /// for the properties that have no function of their own.
    void g_object_set(gpointer instance, gchar* property, ...);

    /// Reads properties. Every argument after the name is a *pointer* to
    /// somewhere to put the value, and the list ends with null.
    void g_object_get(gpointer instance, gchar* property, ...);

    /// Freezes and thaws property change notification, so that a run of sets
    /// emits one `notify` rather than one each.
    void g_object_freeze_notify(gpointer instance);
    void g_object_thaw_notify(gpointer instance);
}

// =================================================================== signals

/// `GConnectFlags`. `AFTER` runs the handler after the object's own default
/// handler rather than before it; `SWAPPED` exchanges the instance and the
/// user data, which this binding never wants.
public const gint G_CONNECT_DEFAULT = 0;
public const gint G_CONNECT_AFTER   = 1;
public const gint G_CONNECT_SWAPPED = 2;

// **`g_signal_connect_data` is not declared here**, and the reason is the one
// piece of GObject that a typed language cannot follow.
//
// Its handler parameter is `GCallback`, which is `void (*)(void)`: a function
// pointer of no particular shape, that every caller casts its real handler to
// with the `G_CALLBACK` macro. C is happy because the cast is written out;
// Stainless has no cast between two delegate types, and inventing one would be
// inventing exactly the hole the macro is.
//
// So the declaration lives beside its handler instead. `Gtk.Signals` declares
// it taking a `void (GtkWidget*, gpointer)` and `Gtk.Events` taking a
// `gboolean (GtkWidget*, gpointer, gpointer)`, each in its own module -- the
// same C symbol seen through the two shapes GTK actually emits. A third shape
// would be a third module, and there being only two is why this is worth
// doing rather than working around.

public extern "C" {
    void     g_signal_handler_disconnect(gpointer instance, gulong handler);
    gboolean g_signal_handler_is_connected(gpointer instance, gulong handler);

    /// Stops a handler running for the rest of one emission. What a "before"
    /// handler calls when it has dealt with the event itself.
    void g_signal_stop_emission_by_name(gpointer instance, gchar* signal);

    /// Emits a signal by name. Variadic in its arguments and its result, and
    /// so the one call in this file that a wrapper should think twice about.
    void g_signal_emit_by_name(gpointer instance, gchar* signal, ...);
}

// ===================================================================== types

public extern "C" {
    /// The `GType` of an instance, and its name. Useful for a message that has
    /// to say what it was actually given.
    GType  g_type_from_name(gchar* name);
    gchar* g_type_name(GType type);

    /// Whether `type` is `parent` or descends from it.
    gboolean g_type_is_a(GType type, GType parent);

    /// Initialises the type system. A no-op since GLib 2.36, and left here
    /// because a reader looking for it should find it said so.
    void g_type_init();
}

#endif
