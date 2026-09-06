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

// The half of GTK that only GTK 3 has.
//
// **Compiled unless `-D GTK2` was given.** GTK 3 is the default because it is
// what a current distribution ships and what `libgtk-3.so.0` is; `Gtk.Api2` is
// the other branch of the same `#if`, so exactly one of the two is ever in a
// program and the wrapper in `Gtk` can call whichever is there by name.
//
// What GTK 3 changed, and why the split falls where it does:
//
//   - **Layout takes an orientation instead of a direction in the name.**
//     `gtk_hbox_new` and `gtk_vbox_new` became one `gtk_box_new` taking a
//     `GtkOrientation`, and the same happened to separators, scales and panes.
//   - **`GtkGrid` replaced `GtkTable`**, and is not a rename: a grid places a
//     child at a column and row with a span, where a table wanted the left,
//     right, top and bottom lines it sat between.
//   - **Drawing is `draw` with a `cairo_t*`**, already clipped and translated
//     to the widget. GTK 2's `expose-event` handed over a `GdkEventExpose*`
//     and left the caller to make a context from the window.
//   - **Appearance is CSS.** `GtkStyleContext` and `GtkCssProvider` replaced
//     the `GtkStyle` struct, which is the one change here that has no GTK 2
//     equivalent worth binding.
//   - **Margins and alignment are widget properties**, so a wrapper no longer
//     has to reach for `GtkMisc` and `GtkAlignment` to move something.
module Gtk.Api3;

import Gtk.GLib;
import Gtk.Api;

#if UNIX && !GTK2

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

    /// `left` and `top` are the cell, `width` and `height` the span in cells.
    /// A table's four edge numbers became this, which is why the two layouts
    /// cannot share a wrapper call.
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
    /// The grey text an empty entry shows. GTK 2 has nothing like it, so the
    /// wrapper's setter does nothing there rather than pretending.
    void gtk_entry_set_placeholder_text(GtkWidget* entry, gchar* text);
}

// ============================================== widgets GTK 2 did not have

// Each of these looks as though it belongs in the shared file and does not.
// They were found by asking the two libraries -- `nm -D` over `libgtk-3.so.0`
// and `libgtk-x11-2.0.so.0` -- rather than by reading, which is the only way
// to be sure of a hand-written binding: a call in the wrong file is a link
// error on the version that lacks it, and a link error names one symbol at a
// time.

public extern "C" {
    /// The version as three numbers. GTK 2 exports these as *variables*
    /// (`gtk_major_version`), not functions, so a test that has to work on
    /// both calls `gtk_check_version` in `Gtk.Api` instead.
    guint gtk_get_major_version();
    guint gtk_get_minor_version();
    guint gtk_get_micro_version();

    /// Empties a combo box in one call. GTK 2 removes by position, from the
    /// end, in a loop.
    void gtk_combo_box_text_remove_all(GtkWidget* combo);

    /// Whether the bar draws its text over itself. GTK 2 always did.
    void gtk_progress_bar_set_show_text(GtkWidget* bar, gboolean show);

    /// The size a scrolled window asks for before its scrollbars appear.
    /// GTK 2 had only `gtk_widget_set_size_request` on the child.
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
    /// widget. The way to style one thing differently in GTK 3.
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
