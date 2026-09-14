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

// GTK 3, as a raw binding: entry points and constants under the names the
// headers give them.
//
// **This was two files and a `#if`.** GTK 2 was bound beside GTK 3 until the
// day the toolkit stopped being something a program here merely called and
// became something `forms/` is built on. Two toolkits behind one seam is two
// backends to keep honest, and the second of them is one no current
// distribution ships and that Lazarus itself has stopped supporting -- so the
// split went, `Gtk.Api2` with it, and `Gtk.Api3` folded in here. What is left
// of that work is the method: every declaration below was checked against
// `nm -D --defined-only libgtk-3.so.0`, which is the only way to be sure of a
// hand-written binding.
//
// **There is no `#pragma comment(lib, ...)` here, and that is deliberate.** On
// Windows a library has one name and `user32` is always `user32`. On Linux the
// name a linker resolves depends on whether the development package is
// installed: with it, `-l gtk-3` finds `libgtk-3.so`; without it, only the
// versioned `libgtk-3.so.0` exists and the link line wants `-l :libgtk-3.so.0`
// instead. Naming one of those in a pragma would make this file wrong on half
// the machines it should work on, so the choice is left where it belongs:
//
//     # GTK 3, on a machine with the development packages
//     stainless run app.sl bindings/gtk \
//         -l gtk-3 -l gdk-3 -l gobject-2.0 -l glib-2.0 -l cairo
//
//     # GTK 3, on a machine with only the runtime
//     stainless run app.sl bindings/gtk \
//         -l :libgtk-3.so.0 -l :libgdk-3.so.0 -l :libgobject-2.0.so.0 \
//         -l :libglib-2.0.so.0 -l :libcairo.so.2
//
// There is no version flag any more. GTK 4 would be a separate backend
// rather than a third branch -- 37 of the calls below are absent from
// `libgtk-4.so.1`, and they are the load-bearing ones -- so a `#if` would
// not have served it either.
//
// **Every widget pointer is a `GtkWidget*`.** GTK's C API is written in terms
// of `GtkWindow*`, `GtkButton*` and so on, but the casts between them are the
// `GTK_WINDOW()` macros, which are checked casts that a C compiler cannot see
// through either. Since a binding cannot reproduce the check, it does not
// pretend to: one pointer type, and the wrapper classes in `Gtk` are where the
// distinction is kept -- by a class hierarchy, which does check.
module Gtk.Api;

import Gtk.GLib;
import Gtk.GObject;

#if UNIX

// =================================================================== handles

/// `GtkWidget`, and every other GTK instance. Opaque: a binding never reads
/// one, it only passes it back.
public using GtkWidget = byte;

/// `GtkTextIter`, which is the one GTK struct a caller has to allocate itself.
///
/// Its contents are private -- fourteen `dummy` members in the header -- but
/// its *size* is public, because callers put one on the stack. Eighty bytes on
/// a 64-bit build, which is what the fourteen members come to, and it is
/// declared as bytes because nothing here should be tempted to read them.
public struct GtkTextIter {
    public byte[80] Private;
}

// ==================================================================== enums

/// `GtkWindowType`.
public const gint GTK_WINDOW_TOPLEVEL = 0;
public const gint GTK_WINDOW_POPUP    = 1;

/// `GtkWindowPosition`.
public const gint GTK_WIN_POS_NONE             = 0;
public const gint GTK_WIN_POS_CENTER           = 1;
public const gint GTK_WIN_POS_MOUSE            = 2;
public const gint GTK_WIN_POS_CENTER_ALWAYS    = 3;
public const gint GTK_WIN_POS_CENTER_ON_PARENT = 4;

/// `GtkOrientation`, taken at construction by a box, a separator, a paned
/// and a scale alike -- one call each, rather than one per direction.
public const gint GTK_ORIENTATION_HORIZONTAL = 0;
public const gint GTK_ORIENTATION_VERTICAL   = 1;

/// `GtkPolicyType`, for a scrolled window's bars.
public const gint GTK_POLICY_ALWAYS    = 0;
public const gint GTK_POLICY_AUTOMATIC = 1;
public const gint GTK_POLICY_NEVER     = 2;

/// `GtkMessageType`.
public const gint GTK_MESSAGE_INFO     = 0;
public const gint GTK_MESSAGE_WARNING  = 1;
public const gint GTK_MESSAGE_QUESTION = 2;
public const gint GTK_MESSAGE_ERROR    = 3;
public const gint GTK_MESSAGE_OTHER    = 4;

/// `GtkButtonsType`.
public const gint GTK_BUTTONS_NONE      = 0;
public const gint GTK_BUTTONS_OK        = 1;
public const gint GTK_BUTTONS_CLOSE     = 2;
public const gint GTK_BUTTONS_CANCEL    = 3;
public const gint GTK_BUTTONS_YES_NO    = 4;
public const gint GTK_BUTTONS_OK_CANCEL = 5;

/// `GtkDialogFlags`, which are a bit set.
public const gint GTK_DIALOG_MODAL               = 1;
public const gint GTK_DIALOG_DESTROY_WITH_PARENT = 2;

/// `GtkResponseType`. All negative, because a positive response id belongs to
/// the application: `gtk_dialog_add_button` takes any `gint` the caller likes,
/// and these are the ones GTK reserves for itself.
public const gint GTK_RESPONSE_NONE         = -1;
public const gint GTK_RESPONSE_REJECT       = -2;
public const gint GTK_RESPONSE_ACCEPT       = -3;
public const gint GTK_RESPONSE_DELETE_EVENT = -4;
public const gint GTK_RESPONSE_OK           = -5;
public const gint GTK_RESPONSE_CANCEL       = -6;
public const gint GTK_RESPONSE_CLOSE        = -7;
public const gint GTK_RESPONSE_YES          = -8;
public const gint GTK_RESPONSE_NO           = -9;
public const gint GTK_RESPONSE_APPLY        = -10;
public const gint GTK_RESPONSE_HELP         = -11;

/// `GtkJustification`.
public const gint GTK_JUSTIFY_LEFT   = 0;
public const gint GTK_JUSTIFY_RIGHT  = 1;
public const gint GTK_JUSTIFY_CENTER = 2;
public const gint GTK_JUSTIFY_FILL   = 3;

// ============================================================ start and stop

public extern "C" {
    /// Starts GTK, **ending the program** if there is no display. `argc` and
    /// `argv` may both be null, which says the toolkit gets no command line of
    /// its own to parse.
    void gtk_init(gint* argc, gchar*** argv);

    /// The same, answering false instead of ending the program.
    ///
    /// This is the one to call. A program that cannot open a display has
    /// something to say about it, and a toolkit that exits before `Main` gets
    /// a chance is not a good citizen of a language with no exceptions.
    gboolean gtk_init_check(gint* argc, gchar*** argv);

    /// Runs the main loop until `gtk_main_quit`.
    void gtk_main();

    /// Ends the innermost `gtk_main`. Nested loops are what a modal dialog is,
    /// so this is a stack rather than a switch.
    void gtk_main_quit();

    /// Handles one pending event, or blocks for one. Answers true if the loop
    /// should stop.
    gboolean gtk_main_iteration();
    gboolean gtk_main_iteration_do(gboolean blocking);

    /// Whether anything is waiting. The pair of calls that lets a long
    /// computation keep the window painting without a thread.
    gboolean gtk_events_pending();

    /// Null when the running GTK is at least the version asked for, and a
    /// message saying why not otherwise. **Borrowed.**
    ///
    /// A version test that reads as a sentence rather than as three
    /// comparisons against `gtk_get_major_version` and its two relatives,
    /// which are below and are what a program wants when it needs the numbers
    /// themselves rather than a verdict.
    gchar* gtk_check_version(guint major, guint minor, guint micro);
}

// ==================================================================== widget

public extern "C" {
    void gtk_widget_show(GtkWidget* widget);

    /// Shows the widget and everything inside it. What a window wants once,
    /// after it has been filled.
    void gtk_widget_show_all(GtkWidget* widget);

    void gtk_widget_hide(GtkWidget* widget);

    /// Destroys the widget and its children, breaking it out of its container.
    ///
    /// A widget's C reference count is not the whole story: a destroyed widget
    /// may still be allocated, because something is holding a reference, but
    /// it is no longer usable for anything. This is what closing a window does
    /// to everything in it.
    void gtk_widget_destroy(GtkWidget* widget);

    void     gtk_widget_set_sensitive(GtkWidget* widget, gboolean sensitive);
    gboolean gtk_widget_get_sensitive(GtkWidget* widget);
    void     gtk_widget_set_visible(GtkWidget* widget, gboolean visible);
    gboolean gtk_widget_get_visible(GtkWidget* widget);

    /// The smallest the widget will be laid out at. -1 for either means "ask
    /// the widget", which is the default.
    void gtk_widget_set_size_request(GtkWidget* widget, gint width, gint height);

    void gtk_widget_grab_focus(GtkWidget* widget);
    void gtk_widget_set_can_focus(GtkWidget* widget, gboolean can);

    void gtk_widget_set_tooltip_text(GtkWidget* widget, gchar* text);
    void gtk_widget_set_name(GtkWidget* widget, gchar* name);

    /// Marks the widget as needing redrawing. The only correct way to ask for
    /// a repaint: drawing outside a draw handler is not a thing GTK supports.
    void gtk_widget_queue_draw(GtkWidget* widget);
    void gtk_widget_queue_resize(GtkWidget* widget);

    GtkWidget* gtk_widget_get_parent(GtkWidget* widget);

    /// The single child of a `GtkBin` -- a window, a button, a scrolled
    /// window -- or null.
    GtkWidget* gtk_bin_get_child(GtkWidget* bin);
    GtkWidget* gtk_widget_get_toplevel(GtkWidget* widget);

    /// The events the widget asks to receive. A `GtkDrawingArea` gets almost
    /// none by default, so a mouse handler on one needs this first.
    void gtk_widget_add_events(GtkWidget* widget, gint events);
}

// ================================================================= container

public extern "C" {
    void gtk_container_add(GtkWidget* container, GtkWidget* child);
    void gtk_container_remove(GtkWidget* container, GtkWidget* child);
    void gtk_container_set_border_width(GtkWidget* container, guint width);

    /// The children, as a list the caller frees with `g_list_free` -- the
    /// widgets in it belong to the container and must not be unreffed.
    GList* gtk_container_get_children(GtkWidget* container);
}

// ==================================================================== window

public extern "C" {
    GtkWidget* gtk_window_new(gint type);

    void gtk_window_set_title(GtkWidget* window, gchar* title);
    void gtk_window_set_default_size(GtkWidget* window, gint width, gint height);
    void gtk_window_resize(GtkWidget* window, gint width, gint height);
    void gtk_window_move(GtkWidget* window, gint x, gint y);
    void gtk_window_get_size(GtkWidget* window, gint* width, gint* height);
    void gtk_window_get_position(GtkWidget* window, gint* x, gint* y);

    void gtk_window_set_resizable(GtkWidget* window, gboolean resizable);
    void gtk_window_set_modal(GtkWidget* window, gboolean modal);
    void gtk_window_set_transient_for(GtkWidget* window, GtkWidget* parent);
    void gtk_window_set_position(GtkWidget* window, gint position);
    void gtk_window_set_decorated(GtkWidget* window, gboolean decorated);

    void gtk_window_present(GtkWidget* window);
    void gtk_window_maximize(GtkWidget* window);
    void gtk_window_unmaximize(GtkWidget* window);
    void gtk_window_fullscreen(GtkWidget* window);
    void gtk_window_unfullscreen(GtkWidget* window);
}

// ======================================================================= box

public extern "C" {
    /// `expand` is whether the child takes a share of the extra space, `fill`
    /// whether it grows into the share it took. The pair reads oddly until you
    /// want a centred button: expand true, fill false.
    void gtk_box_pack_start(GtkWidget* box, GtkWidget* child,
                            gboolean expand, gboolean fill, guint padding);
    void gtk_box_pack_end(GtkWidget* box, GtkWidget* child,
                          gboolean expand, gboolean fill, guint padding);

    void gtk_box_set_spacing(GtkWidget* box, gint spacing);
    void gtk_box_set_homogeneous(GtkWidget* box, gboolean homogeneous);
    void gtk_box_reorder_child(GtkWidget* box, GtkWidget* child, gint position);
}

// ==================================================================== button

public extern "C" {
    GtkWidget* gtk_button_new();
    GtkWidget* gtk_button_new_with_label(gchar* label);

    /// A button whose label carries an underscore before the mnemonic letter,
    /// as `_File` does.
    GtkWidget* gtk_button_new_with_mnemonic(gchar* label);

    void   gtk_button_set_label(GtkWidget* button, gchar* label);
    gchar* gtk_button_get_label(GtkWidget* button);

    GtkWidget* gtk_toggle_button_new_with_label(gchar* label);
    GtkWidget* gtk_check_button_new_with_label(gchar* label);
    GtkWidget* gtk_check_button_new();

    gboolean gtk_toggle_button_get_active(GtkWidget* button);
    void     gtk_toggle_button_set_active(GtkWidget* button, gboolean active);

    /// A radio button joined to `group`, which is another radio button or null
    /// to start a new group. GTK's grouping is by widget, not by container.
    GtkWidget* gtk_radio_button_new_with_label_from_widget(GtkWidget* group, gchar* label);
}

// ===================================================================== label

public extern "C" {
    GtkWidget* gtk_label_new(gchar* text);

    void   gtk_label_set_text(GtkWidget* label, gchar* text);

    /// The text as displayed. **Borrowed**: it belongs to the label and must
    /// not be freed, and it stops being valid the next time the label changes.
    gchar* gtk_label_get_text(GtkWidget* label);

    /// Pango markup, which is the closest thing GTK has to rich text in a
    /// label: `<b>`, `<i>`, `<span foreground="red">`.
    void gtk_label_set_markup(GtkWidget* label, gchar* markup);

    void gtk_label_set_line_wrap(GtkWidget* label, gboolean wrap);
    void gtk_label_set_justify(GtkWidget* label, gint justification);
    void gtk_label_set_selectable(GtkWidget* label, gboolean selectable);
}

// ===================================================================== entry

public extern "C" {
    GtkWidget* gtk_entry_new();

    void gtk_entry_set_text(GtkWidget* entry, gchar* text);

    /// **Borrowed**, like a label's. Copy it with `Text.FromNullTerminated`
    /// before anything else touches the entry.
    gchar* gtk_entry_get_text(GtkWidget* entry);

    /// False turns the entry into a password field.
    void gtk_entry_set_visibility(GtkWidget* entry, gboolean visible);

    void gtk_entry_set_max_length(GtkWidget* entry, gint length);
    void gtk_entry_set_width_chars(GtkWidget* entry, gint chars);

    /// Read-only or not. `gtk_entry_set_editable` is the call a reader will
    /// look for and GTK 3 removed it; this one -- `GtkEditable`'s rather than
    /// `GtkEntry`'s -- is what replaced it, and it works on a text view too.
    void     gtk_editable_set_editable(GtkWidget* entry, gboolean editable);
    gboolean gtk_editable_get_editable(GtkWidget* entry);

    /// Whether Enter in this entry emits `activate`, which is what makes a
    /// form submit.
    void gtk_entry_set_activates_default(GtkWidget* entry, gboolean activates);
}

// ================================================================= text view

public extern "C" {
    GtkWidget* gtk_text_view_new();

    /// The buffer, **borrowed** and owned by the view.
    GtkWidget* gtk_text_view_get_buffer(GtkWidget* view);

    void gtk_text_view_set_editable(GtkWidget* view, gboolean editable);
    void gtk_text_view_set_wrap_mode(GtkWidget* view, gint mode);

    /// A buffer with no view on it.
    ///
    /// Worth knowing about for a reason that has nothing to do with text: a
    /// `GtkTextBuffer` is a `GObject` with signals and **is not a widget**, so
    /// it can be made and emitted from with no display open. It is what the
    /// binding's own tests connect to.
    GtkWidget* gtk_text_buffer_new(gpointer table);

    /// `length` of -1 means the text is NUL-terminated, which it always is
    /// coming from here.
    void gtk_text_buffer_set_text(GtkWidget* buffer, gchar* text, gint length);

    void gtk_text_buffer_get_bounds(GtkWidget* buffer, GtkTextIter* start, GtkTextIter* end);

    /// The text between two iterators, **owned by the caller**: free it with
    /// `g_free`. `hidden` includes characters tagged invisible.
    gchar* gtk_text_buffer_get_text(GtkWidget* buffer, GtkTextIter* start,
                                    GtkTextIter* end, gboolean hidden);

    gint gtk_text_buffer_get_char_count(GtkWidget* buffer);
}

/// `GtkWrapMode`.
public const gint GTK_WRAP_NONE      = 0;
public const gint GTK_WRAP_CHAR      = 1;
public const gint GTK_WRAP_WORD      = 2;
public const gint GTK_WRAP_WORD_CHAR = 3;

// =========================================================== scrolled window

public extern "C" {
    /// Both adjustments null means "make your own", which is what every caller
    /// wants.
    GtkWidget* gtk_scrolled_window_new(gpointer horizontal, gpointer vertical);

    void gtk_scrolled_window_set_policy(GtkWidget* scrolled, gint horizontal, gint vertical);
}

// ================================================================== combo box

public extern "C" {
    GtkWidget* gtk_combo_box_text_new();
    GtkWidget* gtk_combo_box_text_new_with_entry();

    void gtk_combo_box_text_append_text(GtkWidget* combo, gchar* text);
    void gtk_combo_box_text_insert_text(GtkWidget* combo, gint position, gchar* text);
    void gtk_combo_box_text_remove(GtkWidget* combo, gint position);

    /// **Owned by the caller**: `g_free` it.
    gchar* gtk_combo_box_text_get_active_text(GtkWidget* combo);

    gint gtk_combo_box_get_active(GtkWidget* combo);
    void gtk_combo_box_set_active(GtkWidget* combo, gint index);
}

// =============================================================== progress bar

public extern "C" {
    GtkWidget* gtk_progress_bar_new();

    /// 0.0 to 1.0.
    void   gtk_progress_bar_set_fraction(GtkWidget* bar, gdouble fraction);
    gdouble gtk_progress_bar_get_fraction(GtkWidget* bar);

    /// One step of the back-and-forth used when the total is unknown.
    void gtk_progress_bar_pulse(GtkWidget* bar);

    void gtk_progress_bar_set_text(GtkWidget* bar, gchar* text);
}

// ================================================================ spin button

public extern "C" {
    GtkWidget* gtk_spin_button_new_with_range(gdouble minimum, gdouble maximum, gdouble step);

    gdouble gtk_spin_button_get_value(GtkWidget* spin);
    gint    gtk_spin_button_get_value_as_int(GtkWidget* spin);
    void    gtk_spin_button_set_value(GtkWidget* spin, gdouble value);
    void    gtk_spin_button_set_digits(GtkWidget* spin, guint digits);
}

// ===================================================================== range

public extern "C" {
    gdouble gtk_range_get_value(GtkWidget* range);
    void    gtk_range_set_value(GtkWidget* range, gdouble value);
    void    gtk_range_set_increments(GtkWidget* range, gdouble step, gdouble page);
}

// ===================================================================== menus

public extern "C" {
    GtkWidget* gtk_menu_bar_new();
    GtkWidget* gtk_menu_new();

    GtkWidget* gtk_menu_item_new();
    GtkWidget* gtk_menu_item_new_with_label(gchar* label);
    GtkWidget* gtk_menu_item_new_with_mnemonic(gchar* label);
    GtkWidget* gtk_separator_menu_item_new();
    GtkWidget* gtk_check_menu_item_new_with_label(gchar* label);

    void gtk_menu_item_set_submenu(GtkWidget* item, GtkWidget* submenu);
    void gtk_menu_shell_append(GtkWidget* shell, GtkWidget* child);
}

// ================================================================== notebook

public extern "C" {
    GtkWidget* gtk_notebook_new();

    /// The page index, or -1. `label` is a widget, usually a `GtkLabel`.
    gint gtk_notebook_append_page(GtkWidget* notebook, GtkWidget* child, GtkWidget* label);

    void gtk_notebook_remove_page(GtkWidget* notebook, gint index);
    gint gtk_notebook_get_current_page(GtkWidget* notebook);
    void gtk_notebook_set_current_page(GtkWidget* notebook, gint index);
    gint gtk_notebook_get_n_pages(GtkWidget* notebook);
}

// ================================================================= statusbar

public extern "C" {
    GtkWidget* gtk_statusbar_new();

    /// A context id for a category of message, so that two parts of a program
    /// can push and pop without losing each other's text.
    guint gtk_statusbar_get_context_id(GtkWidget* bar, gchar* description);
    guint gtk_statusbar_push(GtkWidget* bar, guint context, gchar* text);
    void  gtk_statusbar_pop(GtkWidget* bar, guint context);
    void  gtk_statusbar_remove_all(GtkWidget* bar, guint context);
}

// ============================================================== drawing area

public extern "C" {
    /// A widget that draws nothing, so that a program can draw everything.
    ///
    /// It emits `draw` with a `cairo_t*` already clipped to the region
    /// needing repainting and translated to the widget's corner, so a handler
    /// works in its own coordinates and cannot draw outside them.
    GtkWidget* gtk_drawing_area_new();
}

// =================================================================== dialogs

public extern "C" {
    /// Variadic, and the format string is the message. Passing a caller's text
    /// straight in would let a `%s` in it read the stack, so the wrapper
    /// passes `"%s"` and the text as an argument -- the same rule `printf` has
    /// always had.
    GtkWidget* gtk_message_dialog_new(GtkWidget* parent, gint flags, gint type,
                                      gint buttons, gchar* format, ...);

    /// Runs a nested main loop until the dialog answers. Returns a
    /// `GTK_RESPONSE_*`, or `GTK_RESPONSE_DELETE_EVENT` if it was closed.
    gint gtk_dialog_run(GtkWidget* dialog);

    void       gtk_dialog_response(GtkWidget* dialog, gint response);
    GtkWidget* gtk_dialog_add_button(GtkWidget* dialog, gchar* text, gint response);
    GtkWidget* gtk_dialog_get_content_area(GtkWidget* dialog);
}

// ==================================================================== enums

/// `GtkAlign`. `BASELINE` is what a row of text-bearing widgets wants so that
/// their letters line up rather than their boxes.
public const gint GTK_ALIGN_FILL     = 0;
public const gint GTK_ALIGN_START    = 1;
public const gint GTK_ALIGN_END      = 2;
public const gint GTK_ALIGN_CENTER   = 3;
public const gint GTK_ALIGN_BASELINE = 4;

/// `GTK_STYLE_PROVIDER_PRIORITY_*`. An application's own CSS goes in at
/// `APPLICATION`, which beats the theme and loses to the user.
public const guint GTK_STYLE_PROVIDER_PRIORITY_FALLBACK    = 1u;
public const guint GTK_STYLE_PROVIDER_PRIORITY_THEME       = 200u;
public const guint GTK_STYLE_PROVIDER_PRIORITY_SETTINGS    = 400u;
public const guint GTK_STYLE_PROVIDER_PRIORITY_APPLICATION = 600u;
public const guint GTK_STYLE_PROVIDER_PRIORITY_USER        = 800u;

// ==================================================================== layout

public extern "C" {
    /// One call for both directions. `GTK_ORIENTATION_HORIZONTAL` is a row.
    GtkWidget* gtk_box_new(gint orientation, gint spacing);

    GtkWidget* gtk_separator_new(gint orientation);
    GtkWidget* gtk_paned_new(gint orientation);
    GtkWidget* gtk_scale_new_with_range(gint orientation, gdouble minimum,
                                        gdouble maximum, gdouble step);

    void gtk_paned_pack1(GtkWidget* paned, GtkWidget* child, gboolean resize, gboolean shrink);
    void gtk_paned_pack2(GtkWidget* paned, GtkWidget* child, gboolean resize, gboolean shrink);
    void gtk_paned_set_position(GtkWidget* paned, gint position);
}

// ====================================================================== grid

public extern "C" {
    GtkWidget* gtk_grid_new();

    /// `left` and `top` are the cell, `width` and `height` the span in cells
    /// -- not the grid lines a child sits between, which is what the older
    /// `GtkTable` wanted and is off by one from this in the direction that is
    /// easy to get wrong.
    void gtk_grid_attach(GtkWidget* grid, GtkWidget* child,
                         gint left, gint top, gint width, gint height);

    void gtk_grid_set_row_spacing(GtkWidget* grid, guint spacing);
    void gtk_grid_set_column_spacing(GtkWidget* grid, guint spacing);
    void gtk_grid_set_row_homogeneous(GtkWidget* grid, gboolean homogeneous);
    void gtk_grid_set_column_homogeneous(GtkWidget* grid, gboolean homogeneous);
}

// =========================================================== widget geometry

public extern "C" {
    void gtk_widget_set_halign(GtkWidget* widget, gint align);
    void gtk_widget_set_valign(GtkWidget* widget, gint align);
    void gtk_widget_set_hexpand(GtkWidget* widget, gboolean expand);
    void gtk_widget_set_vexpand(GtkWidget* widget, gboolean expand);

    /// `start` and `end` rather than left and right, because they follow the
    /// text direction: in an Arabic locale `start` is the right-hand side.
    void gtk_widget_set_margin_start(GtkWidget* widget, gint margin);
    void gtk_widget_set_margin_end(GtkWidget* widget, gint margin);
    void gtk_widget_set_margin_top(GtkWidget* widget, gint margin);
    void gtk_widget_set_margin_bottom(GtkWidget* widget, gint margin);

    /// The size the widget was actually given, which is what a draw handler
    /// needs and is only meaningful once the widget has been laid out.
    gint gtk_widget_get_allocated_width(GtkWidget* widget);
    gint gtk_widget_get_allocated_height(GtkWidget* widget);
}

// ===================================================================== entry

public extern "C" {
    /// The grey text an empty entry shows.
    void gtk_entry_set_placeholder_text(GtkWidget* entry, gchar* text);
}

// ================================================================ the rest

public extern "C" {
    /// The version as three numbers.
    guint gtk_get_major_version();
    guint gtk_get_minor_version();
    guint gtk_get_micro_version();

    /// Empties a combo box in one call.
    void gtk_combo_box_text_remove_all(GtkWidget* combo);

    /// Whether the bar draws its text over itself.
    void gtk_progress_bar_set_show_text(GtkWidget* bar, gboolean show);

    /// The size a scrolled window asks for before its scrollbars appear.
    void gtk_scrolled_window_set_min_content_width(GtkWidget* scrolled, gint width);
    void gtk_scrolled_window_set_min_content_height(GtkWidget* scrolled, gint height);

    /// A monospaced text view without going near a font description.
    void gtk_text_view_set_monospace(GtkWidget* view, gboolean monospace);

    /// Closes a window the way the title bar's button does, which is not the
    /// same as destroying it: the `delete-event` handler still gets its say.
    void gtk_window_close(GtkWidget* window);
}

// ================================================================ header bar

public extern "C" {
    /// The title bar drawn by the application rather than the window manager.
    GtkWidget* gtk_header_bar_new();

    void gtk_header_bar_set_title(GtkWidget* bar, gchar* title);
    void gtk_header_bar_set_subtitle(GtkWidget* bar, gchar* subtitle);
    void gtk_header_bar_set_show_close_button(GtkWidget* bar, gboolean show);
    void gtk_header_bar_pack_start(GtkWidget* bar, GtkWidget* child);
    void gtk_header_bar_pack_end(GtkWidget* bar, GtkWidget* child);

    void gtk_window_set_titlebar(GtkWidget* window, GtkWidget* titlebar);
}

// ======================================================================= css

public extern "C" {
    /// The widget's style context, **borrowed**.
    gpointer gtk_widget_get_style_context(GtkWidget* widget);

    /// Adds a CSS class, so that a provider's `.name { ... }` reaches this
    /// widget. The way to style one thing differently.
    void gtk_style_context_add_class(gpointer context, gchar* name);
    void gtk_style_context_remove_class(gpointer context, gchar* name);

    gpointer gtk_css_provider_new();

    /// `length` of -1 for NUL-terminated. Answers false and fills `error` on a
    /// parse failure, which is worth checking: bad CSS is silent otherwise.
    gboolean gtk_css_provider_load_from_data(gpointer provider, gchar* css,
                                             gssize length, GError** error);

    /// Applies a provider to everything on a screen. `gdk_screen_get_default`
    /// is in `Gtk.Gdk`.
    void gtk_style_context_add_provider_for_screen(gpointer screen, gpointer provider,
                                                   guint priority);
}

#endif
