# GTK bindings

GTK 3 in two layers, both under `Gtk.`, and the module name says which one you
are looking at:

| Name | What it is |
|---|---|
| `Gtk.GLib`, `Gtk.GObject`, `Gtk.Gdk`, `Gtk.Cairo` | **a library name**: declarations and nothing else, spelled as the headers spell them |
| `Gtk.Api` | **GTK itself**, one call per entry point, across `Gtk.sl` and `GtkControls.sl` |
| `Gtk` | **the wrapper**: a widget class hierarchy, ARC ownership, events that are closures |
| `Gtk.Signals`, `Gtk.Events` | the plumbing that turns a GObject signal into a Stainless call |

These are what `forms/`'s GTK backend is built on, which is why the wrapper is
shaped the way it is: a widget set behind a seam needs absolute placement,
handles it can reach, and one class per widget that the type system checks.

Nothing is generated and nothing is marshalled. A `gchar*` is UTF-8 and
NUL-terminated, which is what a `String` literal already is and what
`Text.FromNullTerminated` reads, so the one thing that usually makes a GUI
binding expensive does not arise here.

## Linking it

```sh
# on a machine with the development packages
stainless run app.sl bindings/gtk \
    -l gtk-3 -l gdk-3 -l gobject-2.0 -l glib-2.0 -l cairo

# on a machine with only the runtime libraries
stainless run app.sl bindings/gtk \
    -l :libgtk-3.so.0 -l :libgdk-3.so.0 -l :libgobject-2.0.so.0 \
    -l :libglib-2.0.so.0 -l :libcairo.so.2
```

### GTK 2 was here and is gone

It was bound beside GTK 3 for a while, behind `-D GTK2`, and `Gtk.Api2` held
the half the two spelled differently. It was removed the day this binding
stopped being something a program merely calls and became the thing `forms/`
is built on: two toolkits behind one seam is two backends to keep honest, and
the second of them is one no current distribution ships and that Lazarus
itself no longer supports.

What survives the removal is the method, and it is the thing to keep doing.
Every declaration here was checked against the library rather than against a
header:

```sh
nm -D --defined-only /usr/lib/x86_64-linux-gnu/libgtk-3.so.0
```

**Do this after adding declarations.** A misfiled call is a link error, and a
link error names one symbol at a time.

**There is no `#pragma comment(lib, ...)` anywhere in these files**, unlike the
Win32 bindings, and the reason is worth knowing. On Windows `user32` is always
`user32`. On Linux the name a linker resolves depends on whether the `-dev`
package is installed: with it, `-l gtk-3` finds the `libgtk-3.so` symlink;
without it, only the versioned `libgtk-3.so.0` exists and the link line wants
`-l :libgtk-3.so.0`. A pragma naming either would be wrong on half the
machines this should work on.

## The raw layer

```
bindings/gtk/api/
  GLib.sl      module Gtk.GLib;     the g* typedefs, memory, GList, GError,
                                    the main loop, timers and idles
  GObject.sl   module Gtk.GObject;  reference counting, attached data,
                                    properties, signal disconnection
  Gdk.sl       module Gtk.Gdk;      event accessors, modifiers, keyvals
  Cairo.sl     module Gtk.Cairo;    drawing, which is its own library
  Gtk.sl       module Gtk.Api;      GTK itself, for a program calling it
  GtkControls.sl module Gtk.Api;    the same module: what a widget set needs --
                                    GtkFixed, tree models, toolbars, choosers
```

## Reading events

`GdkEvent` is a union of thirty-odd structs. A binding that declares them is a
binding that has to get every offset right, so this one **prefers the
accessors**: `gdk_event_get_coords`, `gdk_event_get_state`,
`gdk_event_get_root_coords`, `gdk_event_get_button`, `_keyval`, `_event_type`
and `_click_count` are what the wrapper calls. The result is that **no struct
in the union is declared anywhere here**, so there is no offset to get wrong —
a wrong one is silently wrong data, where a wrong symbol is a link error.

## The wrapper

```
bindings/gtk/
  Signals.sl   module Gtk.Signals;  signals that carry nothing
  Events.sl    module Gtk.Events;   signals that carry a pointer and answer
  Widgets.sl   module Gtk;          the widget classes
  Drawing.sl   module Gtk;          Canvas, Painter, DrawingArea, input
```

**An event is a `closure`** (§2.14.1) — a method and the object it belongs to:

```csharp
button.OnClicked(this.Save);                      // a method bound to an object
button.OnClicked(() => { count.Bump(); });         // or a lambda that captures
```

Both are the same two words. A closure is a *value* and `user_data` is one
pointer, so it is boxed; the box is retained by hand because C is about to hold
the only reference to it, and the matching release is the `GClosureNotify` GTK
runs after the last emission — whether the handler was disconnected or the
widget died holding it. That is the whole ownership story and it is about
twenty lines in `Signals.sl`.

There are **no single-method interfaces** anywhere in this binding. The
adapters that used to sit between a widget's events and the raw dispatchers are
now lambdas that capture the handler, which is what they always were.

**A wrapper owns one reference to its widget.** The constructor sinks the
floating reference GTK hands back and the destructor drops it, so a `Window`
field on a class keeps its window alive exactly as long as the class lives. A
program must keep its wrappers; `Application` holds windows for that reason.

`g_object_ref_sink` is right because every `GtkWidget` is a
`GInitiallyUnowned`. It would be **wrong** for a plain `GObject` such as a
`GtkTextBuffer`, whose reference is not floating and which sinking would
simply add a reference to.

## What is not here

- **Pango.** The one that matters now, and the reason it does is `forms/`: its
  GTK backend draws text with cairo's toy API, so there is no shaping, no
  bidirectional text and no font fallback.
- **GTK 4**, which is a separate backend rather than a third `#if` branch.
  **37 of the 138 calls in the shared file are absent from `libgtk-4.so.1`** —
  measured, not guessed — and they are the load-bearing ones: `gtk_main` and
  `gtk_main_quit`, the whole of `gtk_container_*` and `gtk_box_pack_*`, every
  menu call, `gtk_entry_get_text`, `gtk_dialog_run`, `gtk_widget_destroy`.
  Children are attached with widget-specific calls (`gtk_window_set_child`,
  `gtk_box_append`), the loop is `GtkApplication`, drawing is
  `gtk_drawing_area_set_draw_func`, and input arrives through event
  controllers rather than signals on the widget. Sharing a file with that
  would leave the shared half smaller than the branches.
- **Windows and macOS.** These files say `#if UNIX` and mean it: the `g*`
  typedefs in `GLib.sl` are Linux LP64, and `gulong` is 32 bits on a Windows GTK.

`GtkTreeView` and the model classes *were* the biggest gap and are here now —
`gtk_list_store_set` is variadic and `gtk_list_store_set_value` is not, which
is what `Gtk.GObject`'s `GValue` exists for. So is `GtkFileChooser`: its
constructor is variadic over button-and-response pairs, and passing null for
the first button ends that list so `gtk_dialog_add_button` can add them one at
a time, which is what the variadic tail does anyway.

## Verifying a change

There is no end-to-end test case for these, deliberately: one would fail on any
Linux machine without GTK installed, and the suite is meant to run anywhere.
What to do instead, after touching a declaration:

```sh
# it still builds, which is what catches a symbol that is not there
stainless build samples/gtk/hello.sl bindings/gtk -o /tmp/h3 \
    -l :libgtk-3.so.0 -l :libgdk-3.so.0 -l :libgobject-2.0.so.0 \
    -l :libglib-2.0.so.0 -l :libcairo.so.2
```

The ownership plumbing can be checked without a display at all, because a
`GtkTextBuffer` is a GObject with signals and is not a widget: connect a
handler whose destructor prints, drop the buffer, and watch it release.
Fifty thousand connect-emit-destroy cycles hold steady at 14 MB.

**And run `forms/`'s samples**, which are the real exercise now: between
them they build a hundred and sixteen checks' worth of widgets and drive them.

```sh
stainless build samples/forms/common.sl forms/src bindings/gtk -o /tmp/common     -l :libgtk-3.so.0 -l :libgdk-3.so.0 -l :libgobject-2.0.so.0     -l :libglib-2.0.so.0 -l :libcairo.so.2 -l :libgdk_pixbuf-2.0.so.0
GDK_BACKEND=broadway BROADWAY_DISPLAY=:5 /tmp/common --selftest
```

## A signal's shape has to match the connector's

**`Gtk.Signals` connects handlers that take a sender and user data;
`Gtk.Events` connects handlers that take a sender, one pointer and user data.**
A signal carrying more than that delivers the user data in a register the
handler is not reading, so the boxed closure is read out of whatever was there
instead.

`switch-page` carries a page *and* a page number. `row-activated` carries a
path *and* a column. Connecting either through `ConnectEvent` is a segfault at
the first tab added or the first double click, with thirty frames of GObject in
the backtrace and nothing in it to suggest a capture rule.

**Check the signature before connecting.** Where it does not fit, there is
usually a signal that says the same thing and does -- `notify::page` for the
first, a `button-press-event` with a click count of two for the second.

### Running a window with no screen

**GTK 3 needs nothing installed.** Broadway is a GDK backend that renders to a
browser instead of to X, it ships in `libgtk-3-bin`, and it is a real display
as far as the toolkit is concerned — widgets are allocated, `draw` fires, and
cairo paints:

```sh
broadwayd :5 &
GDK_BACKEND=broadway BROADWAY_DISPLAY=:5 ./YourProgram
```

That is enough to drive a whole widget tree from a timer, emit signals with
`g_signal_emit_by_name`, count paints and quit — which is how this binding, and
the `forms/` backend on top of it, were tested. **Note the socket number:**
`broadwayd :5` reports `broadway6.socket`, and `BROADWAY_DISPLAY=:5` is still
what connects to it.

An `Xvfb` works too, and is what a GTK build without broadway would need:

```sh
Xvfb :9 -screen 0 1024x768x24 &
DISPLAY=:9 ./YourProgram
```
