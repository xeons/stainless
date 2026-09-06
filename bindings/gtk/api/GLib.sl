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

// GLib: the C runtime GTK is built on, declared and nothing else.
//
// This is a raw binding. Entry points and types keep the names the headers
// give them, so anything found in the GLib reference is here under the same
// spelling, and the conveniences are `Gtk` on top.
//
// **The type aliases are the whole of the ABI story.** GLib's `g*` typedefs
// exist so that one header can serve several platforms; on Linux x86-64 they
// are what the aliases below say, and the bindings are written in the aliases
// rather than in the underlying types so that a port has one place to change.
// Two are worth reading twice:
//
//   - **`gpointer` is `byte*`**, because `byte*` is the language's `void*`
//     (§2.5) and any pointer converts to it implicitly.
//   - **`gulong` is 64 bits here.** It is `unsigned long`, and Linux is LP64.
//     A Windows build of GLib would make it 32, which is one of the reasons
//     this file says `#if UNIX` and means it.
//
// **A `gchar*` is UTF-8 and NUL-terminated**, which is exactly what
// `Text.FromNullTerminated` reads and what a `String` literal already is. That
// is the one piece of luck in this whole binding: no marshalling anywhere.
module Gtk.GLib;

#if UNIX

// ================================================================== the types

/// `gboolean`, which is a `gint` and not a C99 `bool`: 0 or 1, four bytes.
public using gboolean = int;

/// `gpointer` and `gconstpointer`. `byte*` is the language's `void*`.
public using gpointer = byte*;

/// `gchar*`: UTF-8, NUL-terminated. `Text.FromNullTerminated` reads one.
public using gchar = byte;

public using gint = int;
public using guint = uint;
public using gint8 = sbyte;
public using guint8 = byte;
public using gint16 = short;
public using guint16 = ushort;
public using gint32 = int;
public using guint32 = uint;
public using gint64 = long;
public using guint64 = ulong;
public using gfloat = float;
public using gdouble = double;

/// `gsize` and `gssize`, which are `size_t` and its signed twin.
public using gsize = nuint;
public using gssize = nint;

/// `gulong`. **64 bits on Linux**, and the type a signal handler id has.
public using gulong = ulong;
public using glong = long;

/// `GQuark`, an interned string as an integer.
public using GQuark = uint;

// ============================================================== the callbacks

/// `GDestroyNotify`: what GLib calls when it drops a piece of user data.
///
/// This is the hook a binding needs and the reason the ownership works out.
/// A Stainless object handed to C as `gpointer` must be retained by hand,
/// because C is then holding the only reference to it; this is where the
/// matching release goes.
public delegate void GDestroyNotify(gpointer data);

/// `GSourceFunc`: returns true to stay registered, false to be removed.
public delegate gboolean GSourceFunc(gpointer data);

/// `GFunc`, for `g_list_foreach`.
public delegate void GFunc(gpointer item, gpointer data);

/// `GCompareFunc`: negative, zero or positive, as `strcmp` is.
public delegate gint GCompareFunc(gpointer left, gpointer right);

// =================================================================== memory

public extern "C" {
    /// Allocates, and aborts rather than returning null.
    gpointer g_malloc(gsize bytes);

    /// The same, zeroed.
    gpointer g_malloc0(gsize bytes);

    gpointer g_realloc(gpointer block, gsize bytes);

    /// Frees a block GLib allocated. **Not** `free`: GLib may not be using the
    /// C allocator, and a string a GTK getter says the caller owns has to come
    /// back here.
    void g_free(gpointer block);

    /// A copy of a NUL-terminated string, owned by the caller. Free it with
    /// `g_free`.
    gchar* g_strdup(gchar* text);
}

// ================================================================== the list

/// `GList`, the doubly-linked list GTK returns collections in.
///
/// Walked rather than indexed: `Data` is the element, `Next` is null at the
/// end. Most GTK getters that answer with one say the caller owns the list but
/// not its elements, which is `g_list_free` and not `g_list_free_full`.
public struct GList {
    public gpointer Data;
    public GList*   Next;
    public GList*   Prev;
}

/// `GSList`, the singly-linked one. Same story with no `Prev`.
public struct GSList {
    public gpointer Data;
    public GSList*  Next;
}

public extern "C" {
    guint    g_list_length(GList* list);
    gpointer g_list_nth_data(GList* list, guint index);
    void     g_list_free(GList* list);
    void     g_list_free_full(GList* list, GDestroyNotify free);
    void     g_list_foreach(GList* list, GFunc each, gpointer data);

    guint    g_slist_length(GSList* list);
    void     g_slist_free(GSList* list);
}

// ================================================================== GError

/// `GError`. The out-parameter half of every GLib call that can fail.
///
/// A call takes a `GError**`. On success it leaves it null; on failure it
/// allocates one, and the caller frees it with `g_error_free`. Passing null
/// for the whole thing says "I do not want to know", which is legal and
/// usually wrong.
public struct GError {
    public GQuark Domain;
    public gint   Code;
    public gchar* Message;
}

public extern "C" {
    void g_error_free(GError* error);
    void g_clear_error(GError** error);
}

// =============================================================== main loop

/// `GMainContext` and `GMainLoop`, which are what `gtk_main` runs underneath.
///
/// A program with a GUI does not need these -- `gtk_main` is the loop -- but
/// a timer or an idle callback is registered here, and a headless program that
/// wants GLib's event loop without a display can run one directly.
public extern "C" {
    gpointer g_main_loop_new(gpointer context, gboolean isRunning);
    void     g_main_loop_run(gpointer loop);
    void     g_main_loop_quit(gpointer loop);
    void     g_main_loop_unref(gpointer loop);
    gboolean g_main_loop_is_running(gpointer loop);

    gpointer g_main_context_default();
    gboolean g_main_context_iteration(gpointer context, gboolean mayBlock);
    gboolean g_main_context_pending(gpointer context);
}

/// `G_PRIORITY_*`. Lower runs first; the default is 0 and idle is 200.
public const gint G_PRIORITY_HIGH         = -100;
public const gint G_PRIORITY_DEFAULT      = 0;
public const gint G_PRIORITY_HIGH_IDLE    = 100;
public const gint G_PRIORITY_DEFAULT_IDLE = 200;
public const gint G_PRIORITY_LOW          = 300;

public extern "C" {
    /// Runs `function` when nothing else is pending, and again while it
    /// answers true. The `_full` form is the one worth using: it takes the
    /// `GDestroyNotify` that undoes a retain.
    guint g_idle_add_full(gint priority, GSourceFunc function,
                          gpointer data, GDestroyNotify notify);

    /// The same, every `interval` milliseconds.
    guint g_timeout_add_full(gint priority, guint interval, GSourceFunc function,
                             gpointer data, GDestroyNotify notify);

    /// The same, on a whole-second boundary. Cheaper for anything that only
    /// has to look right rather than be exact, because it lets the kernel wake
    /// several timers at once.
    guint g_timeout_add_seconds_full(gint priority, guint interval, GSourceFunc function,
                                     gpointer data, GDestroyNotify notify);

    gboolean g_source_remove(guint tag);
}

#endif
