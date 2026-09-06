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

// The half of GTK that only GTK 2 has.
//
// **Compiled when `-D GTK2` is given**, and not otherwise. GTK 2 and GTK 3
// cannot both be linked into one program -- they export overlapping symbols
// from two libraries that disagree about the objects behind them -- so the
// choice is made once, at build time, and this file and `Gtk.Api3` are the two
// branches of it.
//
// GTK 2 is still worth binding. It is what a machine running MATE, XFCE or an
// older distribution has, it is smaller and starts faster, and its widget set
// is the one `Gtk.Api` was written against: almost everything a program does
// is in the shared file, and this one is layout and drawing.
//
// The three differences that matter:
//
//   - **A direction per function.** `gtk_hbox_new` and `gtk_vbox_new` rather
//     than one call taking an orientation, and the same for separators, panes
//     and scales.
//   - **`GtkTable` rather than `GtkGrid`.** A table child is attached between
//     grid *lines*, so a single cell at column 2 is `left=2, right=3`. It is
//     off by one from the way a grid is described, in the direction that is
//     easy to get wrong.
//   - **`GtkMisc` for alignment.** A label is positioned inside its own
//     allocation with `gtk_misc_set_alignment`, not with the widget-level
//     halign GTK 3 added.
//
// Drawing is *not* a difference worth calling one: GTK 2.8 and later have
// cairo, and `gdk_cairo_create` on a widget's window gives the same
// `cairo_t*` that GTK 3 hands to a draw handler. The signal differs -- this
// is `expose-event` and that is `draw` -- and the wrapper hides it.
module Gtk.Api2;

import Gtk.GLib;
import Gtk.Api;

#if UNIX && GTK2

// ==================================================================== layout

public extern "C" {
    /// A row. `homogeneous` gives every child the same width whatever it asked
    /// for.
    GtkWidget* gtk_hbox_new(gboolean homogeneous, gint spacing);

    /// A column.
    GtkWidget* gtk_vbox_new(gboolean homogeneous, gint spacing);

    GtkWidget* gtk_hseparator_new();
    GtkWidget* gtk_vseparator_new();

    GtkWidget* gtk_hpaned_new();
    GtkWidget* gtk_vpaned_new();

    GtkWidget* gtk_hscale_new_with_range(gdouble minimum, gdouble maximum, gdouble step);
    GtkWidget* gtk_vscale_new_with_range(gdouble minimum, gdouble maximum, gdouble step);

    void gtk_paned_pack1(GtkWidget* paned, GtkWidget* child, gboolean resize, gboolean shrink);
    void gtk_paned_pack2(GtkWidget* paned, GtkWidget* child, gboolean resize, gboolean shrink);
    void gtk_paned_set_position(GtkWidget* paned, gint position);
}

// ===================================================================== table

public extern "C" {
    GtkWidget* gtk_table_new(guint rows, guint columns, gboolean homogeneous);

    /// **The four numbers are grid lines, not cells.** One cell in column 2 of
    /// row 3 is `left=2, right=3, top=3, bottom=4`; a child spanning two
    /// columns is `right = left + 2`. `Gtk.Grid` in the wrapper takes a cell
    /// and a span and does this arithmetic, so that a program says the same
    /// thing to both versions.
    void gtk_table_attach_defaults(GtkWidget* table, GtkWidget* child,
                                   guint left, guint right, guint top, guint bottom);

    void gtk_table_set_row_spacings(GtkWidget* table, guint spacing);
    void gtk_table_set_col_spacings(GtkWidget* table, guint spacing);
    void gtk_table_set_homogeneous(GtkWidget* table, gboolean homogeneous);
    void gtk_table_resize(GtkWidget* table, guint rows, guint columns);
}

// ============================================================== misc and size

public extern "C" {
    /// Where the widget sits inside its own allocation, 0.0 to 1.0 in each
    /// direction. GTK 3 replaced this with `gtk_widget_set_halign`.
    void gtk_misc_set_alignment(GtkWidget* misc, gfloat x, gfloat y);
    void gtk_misc_set_padding(GtkWidget* misc, gint x, gint y);

    /// An `GtkAlignment` container, which is how GTK 2 adds a margin: there is
    /// no widget-level margin, so a child that wants one is wrapped.
    GtkWidget* gtk_alignment_new(gfloat xalign, gfloat yalign, gfloat xscale, gfloat yscale);
    void gtk_alignment_set_padding(GtkWidget* alignment, guint top, guint bottom,
                                   guint left, guint right);
}

/// `GtkAllocation`, which is a `GdkRectangle`: where the widget ended up.
///
/// GTK 3 answers the same question with `gtk_widget_get_allocated_width`, so
/// the struct is only needed here.
public struct GtkAllocation {
    public gint X;
    public gint Y;
    public gint Width;
    public gint Height;
}

public extern "C" {
    /// Fills `allocation` with the widget's position and size. GTK 2.18 and
    /// later; before that the struct was read straight out of the widget.
    void gtk_widget_get_allocation(GtkWidget* widget, GtkAllocation* allocation);

    /// The `GdkWindow` a widget draws into, which `gdk_cairo_create` needs.
    /// GTK 2.14 and later.
    gpointer gtk_widget_get_window(GtkWidget* widget);
}

#endif
