# GTK bindings

GTK 2 and GTK 3 in two layers, both under `Gtk.`, and the module name says
which one you are looking at:

| Name | What it is |
|---|---|
| `Gtk.GLib`, `Gtk.GObject`, `Gtk.Gdk`, `Gtk.Cairo` | **a library name**: declarations and nothing else, spelled as the headers spell them |
| `Gtk.Api`, `Gtk.Api2`, `Gtk.Api3` | **GTK itself**, split into the half both versions share and the two halves they do not |
| `Gtk` | **the wrapper**: a widget class hierarchy, ARC ownership, events that are closures |
| `Gtk.Signals`, `Gtk.Events` | the plumbing that turns a GObject signal into a Stainless call |

Nothing is generated and nothing is marshalled. A `gchar*` is UTF-8 and
NUL-terminated, which is what a `String` literal already is and what
`Text.FromNullTerminated` reads, so the one thing that usually makes a GUI
binding expensive does not arise here.

## Choosing a version

**GTK 3 unless you ask for GTK 2.** The two cannot be linked into one program
— they export overlapping symbols from libraries that disagree about the
objects behind them — so the choice is a build flag:

```sh
# GTK 3, on a machine with the development packages
stainless run app.sl bindings/gtk \
    -l gtk-3 -l gdk-3 -l gobject-2.0 -l glib-2.0 -l cairo

# GTK 3, on a machine with only the runtime libraries
stainless run app.sl bindings/gtk \
    -l :libgtk-3.so.0 -l :libgdk-3.so.0 -l :libgobject-2.0.so.0 \
    -l :libglib-2.0.so.0 -l :libcairo.so.2

# GTK 2
stainless run app.sl bindings/gtk -D GTK2 \
    -l :libgtk-x11-2.0.so.0 -l :libgdk-x11-2.0.so.0 \
    -l :libgobject-2.0.so.0 -l :libglib-2.0.so.0 -l :libcairo.so.2
```

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
  Cairo.sl     module Gtk.Cairo;    drawing — the same under both versions
  Gtk.sl       module Gtk.Api;      everything GTK 2 and GTK 3 spell alike
  Gtk3.sl      module Gtk.Api3;     GtkGrid, orientation, CSS, margins
  Gtk2.sl      module Gtk.Api2;     GtkTable, hbox/vbox, GtkMisc, allocation
```

The split between the last three is smaller than a reader expects. Windows,
buttons, labels, entries, containers, menus, notebooks, dialogs and text views
are all in the shared file; **layout and styling are where the versions part
company**, plus a handful of calls GTK 3 added that look shared and are not.

Those were found by asking the libraries rather than by reading:

```sh
nm -D --defined-only /usr/lib/x86_64-linux-gnu/libgtk-3.so.0
nm -D --defined-only /usr/lib/x86_64-linux-gnu/libgtk-x11-2.0.so.0
```

and checking every declared symbol against both. It caught nine calls filed as
shared that GTK 2 does not have, and one — `gtk_entry_set_editable` — that GTK
3 removed. **Do this after adding declarations.** A misfiled call is a link
error on the version that lacks it, and a link error names one symbol at a
time.

## Reading events

`GdkEvent` is a union of thirty-odd structs. A binding that declares them is a
binding that has to get every offset right, so this one **prefers the
accessors**: `gdk_event_get_coords`, `gdk_event_get_state` and
`gdk_event_get_root_coords` exist in both versions and are what the wrapper
calls. `gdk_event_get_button`, `_keyval`, `_event_type` and `_click_count`
arrived in GTK 3.2 and are not in GTK 2, so the GTK 2 side reads two structs
whose offsets are written out in `Gdk.sl`. Those two are the only hand-computed
layouts in the whole binding.

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
button.OnClicked(() => { count = count + 1; });   // or a lambda that captures
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

- **`GtkTreeView` and the model classes.** The biggest remaining gap, and the
  one a real application hits first. `GtkListStore` is variadic in a way that
  needs `GValue` to bind properly.
- **`GtkFileChooser`.** `gtk_file_chooser_dialog_new` is variadic over a
  NULL-terminated list of button-and-response pairs.
- **Pango**, so text is cairo's toy API: fine for a label on a chart, not for
  laying out a paragraph.
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
  typedefs below are Linux LP64, and `gulong` is 32 bits on a Windows GTK.

## Verifying a change

There is no end-to-end test case for these, deliberately: one would fail on any
Linux machine without GTK installed, and the suite is meant to run anywhere.
What to do instead, after touching a declaration:

```sh
# both versions still build, which is what catches a misfiled symbol
stainless build samples/gtk/hello.sl bindings/gtk -o /tmp/h3 -l :libgtk-3.so.0 ...
stainless build samples/gtk/hello.sl bindings/gtk -D GTK2 -o /tmp/h2 -l :libgtk-x11-2.0.so.0 ...
```

The ownership plumbing can be checked without a display at all, because a
`GtkTextBuffer` is a GObject with signals and is not a widget: connect a
handler whose destructor prints, drop the buffer, and watch it release.
Fifty thousand connect-emit-destroy cycles hold steady at 14 MB.

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
`g_signal_emit_by_name`, count paints and quit — which is how this binding was
tested. **Note the socket number:** `broadwayd :5` reports
`broadway6.socket`, and `BROADWAY_DISPLAY=:5` is still what connects to it.

**GTK 2 has no broadway** — `libgdk-x11-2.0` contains not one mention of it, so
GTK 2 is X11 or nothing. Testing that side headlessly needs an X server:

```sh
sudo apt install xvfb
Xvfb :9 -screen 0 1024x768x24 &
DISPLAY=:9 ./YourProgram
```
