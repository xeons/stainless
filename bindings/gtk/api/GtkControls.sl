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

// The second half of the GTK binding: what a *widget set* needs.
//
// Same module as `Gtk.sl` -- a module spans as many files as it likes -- and
// split from it by who is calling. `Gtk.sl` is what a program writing GTK
// directly reaches for. This is what `forms/src/Platform/Gtk` reaches for, and
// the difference is sharper than it sounds:
//
//   - **Absolute placement.** A GTK program puts children in a box and lets
//     the toolkit decide. A widget set has been handed a rectangle in pixels
//     and has to obey it, so `GtkFixed` is here and is load-bearing.
//   - **Asking rather than deciding.** `gtk_widget_get_preferred_size` exists
//     because `AutoSize` has to know what the platform thinks a button ought
//     to be, which is a question a GTK program never asks out loud.
//   - **One widget behind four controls.** A list box, a checked list, a tree
//     and a details list are all `GtkTreeView` over a model. Windows has four
//     controls; the seam has four interfaces; GTK has one widget and a column
//     layout, which is the sharpest thing this backend has to say about
//     whether that seam describes controls or describes Win32.
//
// Everything here was checked against `nm -D --defined-only libgtk-3.so.0`
// before it was written, the same as the rest.
module Gtk.Api;

import Gtk.GLib;
import Gtk.GObject;
import Gtk.Gdk;

#if UNIX

// ===================================================================== fixed

public extern "C"
{
    /// A container that puts children exactly where it is told.
    ///
    /// **This is what makes a widget set possible at all.** Every other GTK
    /// container computes a layout, and `forms/` has computed one already: the
    /// control layer decided in pixels and the backend's job is to be told.
    /// The LCL's own GTK widgetset uses `GtkFixed` for the same reason, and it
    /// is why a GTK backend is a backend rather than a second control layer.
    GtkWidget* gtk_fixed_new();

    void gtk_fixed_put(GtkWidget* fixed, GtkWidget* child, gint x, gint y);
    void gtk_fixed_move(GtkWidget* fixed, GtkWidget* child, gint x, gint y);

    /// A container with a `GdkWindow` of its own, holding one child.
    ///
    /// **What a `GtkFixed` has not got.** Most GTK containers are windowless:
    /// they occupy a region of their parent's window and so cannot be given the
    /// input events or the focus, which is why a mouse handler on a `GtkFixed`
    /// never fires. An event box is the standard remedy -- a real window, and
    /// nothing drawn in it -- and it is what a control that draws itself and
    /// takes the keyboard is built out of.
    GtkWidget* gtk_event_box_new();
}

// ===================================================================== frame

public extern "C"
{
    /// A box with a caption -- a group box -- and with a null label a plain
    /// frame, which is what a panel's border is.
    GtkWidget* gtk_frame_new(gchar* label);
    void gtk_frame_set_label(GtkWidget* frame, gchar* label);
    void gtk_frame_set_shadow_type(GtkWidget* frame, gint type);
}

/// `GtkShadowType`, which is what a panel's border style becomes.
public const gint GTK_SHADOW_NONE       = 0;
public const gint GTK_SHADOW_IN         = 1;
public const gint GTK_SHADOW_OUT        = 2;
public const gint GTK_SHADOW_ETCHED_IN  = 3;
public const gint GTK_SHADOW_ETCHED_OUT = 4;

// ================================================ scrollbars and adjustments

public extern "C"
{
    /// The value, the range and the steps as one object. A scrollbar, a scale
    /// and a scrolled window are all `GtkRange`s over one of these, which is
    /// why a scrollbar's range is set through the adjustment rather than on
    /// the widget.
    gpointer gtk_adjustment_new(gdouble value, gdouble lower, gdouble upper,
                                gdouble step, gdouble page, gdouble pageSize);

    void gtk_adjustment_configure(gpointer adjustment, gdouble value, gdouble lower,
                                  gdouble upper, gdouble step, gdouble page,
                                  gdouble pageSize);

    gdouble gtk_adjustment_get_value(gpointer adjustment);
    void    gtk_adjustment_set_value(gpointer adjustment, gdouble value);

    GtkWidget* gtk_scrollbar_new(gint orientation, gpointer adjustment);

    /// **Borrowed** -- the range owns it.
    gpointer gtk_range_get_adjustment(GtkWidget* range);
    void     gtk_range_set_range(GtkWidget* range, gdouble minimum, gdouble maximum);
}

// ===================================================================== scale

public extern "C"
{
    /// Whether the slider writes its value beside itself, and where the marks
    /// under it go.
    void gtk_scale_set_draw_value(GtkWidget* scale, gboolean draw);
    void gtk_scale_set_digits(GtkWidget* scale, gint digits);
    void gtk_scale_add_mark(GtkWidget* scale, gdouble at, gint position, gchar* text);
    void gtk_scale_clear_marks(GtkWidget* scale);
}

/// `GtkPositionType`.
public const gint GTK_POS_LEFT   = 0;
public const gint GTK_POS_RIGHT  = 1;
public const gint GTK_POS_TOP    = 2;
public const gint GTK_POS_BOTTOM = 3;

// =================================================================== toolbar

public extern "C"
{
    GtkWidget* gtk_toolbar_new();

    /// A `position` of -1 appends. A tool item is a widget, so one call takes
    /// a button, a toggle and a separator alike.
    void gtk_toolbar_insert(GtkWidget* toolbar, GtkWidget* item, gint position);
    void gtk_toolbar_set_style(GtkWidget* toolbar, gint style);
    gint gtk_toolbar_get_n_items(GtkWidget* toolbar);

    /// **Borrowed.**
    GtkWidget* gtk_toolbar_get_nth_item(GtkWidget* toolbar, gint index);

    /// `icon` may be null, and then the button is text only.
    GtkWidget* gtk_tool_button_new(GtkWidget* icon, gchar* label);
    void gtk_tool_button_set_label(GtkWidget* button, gchar* label);
    void gtk_tool_button_set_icon_widget(GtkWidget* button, GtkWidget* icon);

    GtkWidget* gtk_toggle_tool_button_new();
    void     gtk_toggle_tool_button_set_active(GtkWidget* button, gboolean active);
    gboolean gtk_toggle_tool_button_get_active(GtkWidget* button);

    GtkWidget* gtk_separator_tool_item_new();
    void gtk_separator_tool_item_set_draw(GtkWidget* item, gboolean draw);
}

/// `GtkToolbarStyle`.
public const gint GTK_TOOLBAR_ICONS      = 0;
public const gint GTK_TOOLBAR_TEXT       = 1;
public const gint GTK_TOOLBAR_BOTH       = 2;
public const gint GTK_TOOLBAR_BOTH_HORIZ = 3;

// ===================================================================== image

public extern "C"
{
    GtkWidget* gtk_image_new();
    GtkWidget* gtk_image_new_from_pixbuf(gpointer pixbuf);
    void gtk_image_set_from_pixbuf(GtkWidget* image, gpointer pixbuf);
}

// ================================================================ tree model
//
// **`gtk_list_store_set` is variadic and is not bound.** It takes
// column-and-value pairs terminated by -1, which a binding cannot spell. The
// `_value` form takes one column and one `GValue`, which is the whole reason
// `Gtk.GObject` declares a `GValue` at all.

/// `GtkTreeIter`: a stamp and three pointers, thirty-two bytes on a 64-bit
/// build. Allocated by the caller, like a `GtkTextIter`, and declared as bytes
/// because a binding has no business reading which node it names.
///
/// **An iter is valid only until the model changes.** A `GtkTreePath` is what
/// survives one, which is why the tree peer keeps a path per node rather than
/// an iter.
public struct GtkTreeIter
{
    public byte[32] Private;
}

public extern "C"
{
    GtkWidget* gtk_tree_view_new();

    void     gtk_tree_view_set_model(GtkWidget* view, gpointer model);
    gpointer gtk_tree_view_get_model(GtkWidget* view);
    void     gtk_tree_view_set_headers_visible(GtkWidget* view, gboolean visible);
    void     gtk_tree_view_set_grid_lines(GtkWidget* view, gint which);
    gint     gtk_tree_view_append_column(GtkWidget* view, gpointer column);
    gpointer gtk_tree_view_get_column(GtkWidget* view, gint index);
    void     gtk_tree_view_expand_row(GtkWidget* view, gpointer path, gboolean all);
    void     gtk_tree_view_collapse_row(GtkWidget* view, gpointer path);

    /// **Borrowed.**
    gpointer gtk_tree_view_get_selection(GtkWidget* view);

    /// Which row is at a point, as a path the caller must free.
    ///
    /// **The point is in bin-window coordinates**, which is what a button
    /// event on the tree already carries: the press lands on the scrolled
    /// bin window rather than on the widget, so `event->x` and `event->y` are
    /// in the space this wants. Converting them first is the mistake, not
    /// skipping the conversion.
    ///
    /// Every out parameter may be null, and `column`, `cellX` and `cellY` are
    /// passed so here because a hit test for a context menu wants the row and
    /// nothing else.
    gboolean gtk_tree_view_get_path_at_pos(GtkWidget* view, gint x, gint y,
                                           gpointer* path, gpointer* column,
                                           gint* cellX, gint* cellY);
}

/// `GtkTreeViewGridLines`.
public const gint GTK_TREE_VIEW_GRID_LINES_NONE       = 0;
public const gint GTK_TREE_VIEW_GRID_LINES_HORIZONTAL = 1;
public const gint GTK_TREE_VIEW_GRID_LINES_VERTICAL   = 2;
public const gint GTK_TREE_VIEW_GRID_LINES_BOTH       = 3;

public extern "C"
{
    /// The `newv` forms, because `gtk_list_store_new` is variadic over its
    /// column types. `types` is an array of `GType` and `columns` its length.
    gpointer gtk_list_store_newv(gint columns, GType* types);
    gpointer gtk_tree_store_newv(gint columns, GType* types);

    void gtk_list_store_append(gpointer store, GtkTreeIter* into, gpointer unused);
    void gtk_list_store_insert(gpointer store, GtkTreeIter* into, gint position);
    void gtk_list_store_set_value(gpointer store, GtkTreeIter* row, gint column,
                                  GValue* value);
    gboolean gtk_list_store_remove(gpointer store, GtkTreeIter* row);
    void gtk_list_store_clear(gpointer store);

    /// `parent` null for a root, `after` null to go first among its siblings.
    void gtk_tree_store_insert_after(gpointer store, GtkTreeIter* into,
                                     GtkTreeIter* parent, GtkTreeIter* after);
    void gtk_tree_store_set_value(gpointer store, GtkTreeIter* row, gint column,
                                  GValue* value);
    gboolean gtk_tree_store_remove(gpointer store, GtkTreeIter* row);
    void gtk_tree_store_clear(gpointer store);

    /// Reads one column of one row into a `GValue` the caller must unset.
    void gtk_tree_model_get_value(gpointer model, GtkTreeIter* row, gint column,
                                  GValue* into);

    gboolean gtk_tree_model_get_iter_first(gpointer model, GtkTreeIter* into);
    gboolean gtk_tree_model_iter_next(gpointer model, GtkTreeIter* row);
    gint     gtk_tree_model_iter_n_children(gpointer model, GtkTreeIter* parent);
    gboolean gtk_tree_model_iter_nth_child(gpointer model, GtkTreeIter* into,
                                           GtkTreeIter* parent, gint index);

    /// A path from an iter and back. A path is **owned** and must be freed; it
    /// is what identifies a row across a change to the model.
    gpointer gtk_tree_model_get_path(gpointer model, GtkTreeIter* row);
    gboolean gtk_tree_model_get_iter(gpointer model, GtkTreeIter* into, gpointer path);
    gboolean gtk_tree_model_get_iter_from_string(gpointer model, GtkTreeIter* into,
                                                 gchar* path);

    gpointer gtk_tree_path_new_from_string(gchar* path);
    /// **Owned** -- `g_free` it. `"3"` is the fourth root, `"3:1"` its second
    /// child, which is what makes a path printable and comparable.
    gchar*   gtk_tree_path_to_string(gpointer path);

    /// The path as numbers: one per level, outermost first, so `indices[0]` is
    /// which root. **Borrowed** -- the array belongs to the path -- and valid
    /// for `gtk_tree_path_get_depth` entries, which is what makes reading a
    /// row number out of a flat model an array index rather than a parse.
    gint*    gtk_tree_path_get_indices(gpointer path);
    gint     gtk_tree_path_get_depth(gpointer path);
    void     gtk_tree_path_free(gpointer path);
}

public extern "C"
{
    /// A column shows one or more renderers. `new_with_attributes` is
    /// variadic, so a column is built in three calls instead -- which is what
    /// that call does internally anyway.
    gpointer gtk_tree_view_column_new();
    void gtk_tree_view_column_set_title(gpointer column, gchar* title);
    void gtk_tree_view_column_pack_start(gpointer column, gpointer renderer,
                                         gboolean expand);

    /// Ties a renderer's property to a model column -- `"text"` to column 0,
    /// say, or `"active"` to a boolean column for a checkbox.
    void gtk_tree_view_column_add_attribute(gpointer column, gpointer renderer,
                                            gchar* property, gint modelColumn);

    void gtk_tree_view_column_set_resizable(gpointer column, gboolean resizable);
    void gtk_tree_view_column_set_fixed_width(gpointer column, gint width);
    gint gtk_tree_view_column_get_width(gpointer column);
    void gtk_tree_view_column_set_sizing(gpointer column, gint sizing);
    void gtk_tree_view_column_set_alignment(gpointer column, gfloat alignment);

    gpointer gtk_cell_renderer_text_new();
    gpointer gtk_cell_renderer_toggle_new();
    gpointer gtk_cell_renderer_pixbuf_new();
}

/// `GtkTreeViewColumnSizing`. **`FIXED` is what a column with a width needs**:
/// the default sizes to its content and ignores anything set on it.
public const gint GTK_TREE_VIEW_COLUMN_GROW_ONLY = 0;
public const gint GTK_TREE_VIEW_COLUMN_AUTOSIZE  = 1;
public const gint GTK_TREE_VIEW_COLUMN_FIXED     = 2;

public extern "C"
{
    void gtk_tree_selection_set_mode(gpointer selection, gint mode);

    /// True when something is selected, and `into` then names it. `model` may
    /// be null when the caller already knows which model it is.
    gboolean gtk_tree_selection_get_selected(gpointer selection, gpointer* model,
                                             GtkTreeIter* into);
    void gtk_tree_selection_select_iter(gpointer selection, GtkTreeIter* row);
    void gtk_tree_selection_unselect_all(gpointer selection);
}

/// `GtkSelectionMode`.
public const gint GTK_SELECTION_NONE     = 0;
public const gint GTK_SELECTION_SINGLE   = 1;
public const gint GTK_SELECTION_BROWSE   = 2;
public const gint GTK_SELECTION_MULTIPLE = 3;

// ===================================================================== menus

public extern "C"
{
    /// Shows a menu where the pointer is. The modern spelling of
    /// `gtk_menu_popup`, which took six arguments and is deprecated.
    void gtk_menu_popup_at_pointer(GtkWidget* menu, gpointer trigger);

    void     gtk_check_menu_item_set_active(GtkWidget* item, gboolean active);
    gboolean gtk_check_menu_item_get_active(GtkWidget* item);

    void gtk_menu_item_set_label(GtkWidget* item, gchar* label);
}

// ================================================================== geometry

/// `GtkRequisition`: what a widget asks for, in pixels. Public in the header,
/// and two `int`s.
public struct GtkRequisition
{
    public gint Width;
    public gint Height;
}

public extern "C"
{
    /// The smallest it can be, and what it would like to be. `AutoSize` wants
    /// the second; a layout that has to fit wants the first.
    void gtk_widget_get_preferred_size(GtkWidget* widget, GtkRequisition* minimum,
                                       GtkRequisition* natural);

    /// The native surface under a widget. **Borrowed**, and null until the
    /// widget is realised -- which a caller has to expect, because a control
    /// is given a cursor long before it is ever shown.
    gpointer gtk_widget_get_window(GtkWidget* widget);

    /// Where a point in `from`'s coordinates lands in `to`'s. False when the
    /// two are not under one window, which is how a caller learns that a
    /// widget has not been added to anything yet.
    gboolean gtk_widget_translate_coordinates(GtkWidget* from, GtkWidget* to,
                                              gint x, gint y, gint* intoX, gint* intoY);

    gboolean gtk_widget_has_focus(GtkWidget* widget);
    gboolean gtk_widget_get_realized(GtkWidget* widget);
    void     gtk_widget_realize(GtkWidget* widget);
    void     gtk_widget_set_app_paintable(GtkWidget* widget, gboolean paintable);

    /// Takes and gives up the pointer for one widget, which is what a drag
    /// needs so that motion keeps being reported after it leaves.
    void gtk_grab_add(GtkWidget* widget);
    void gtk_grab_remove(GtkWidget* widget);
}

// ===================================================================== style

public extern "C"
{
    /// A provider on one widget rather than on the whole screen, which is what
    /// a font or a colour set on a single control needs.
    void gtk_style_context_add_provider(gpointer context, gpointer provider,
                                        guint priority);
    void gtk_style_context_remove_provider(gpointer context, gpointer provider);
}

// ================================================================== choosers

public extern "C"
{
    /// `gtk_file_chooser_dialog_new` is variadic over button-and-response
    /// pairs. Passing null for the first button ends that list at once, and
    /// `gtk_dialog_add_button` then adds them one at a time -- which is what
    /// the variadic tail does anyway.
    GtkWidget* gtk_file_chooser_dialog_new(gchar* title, GtkWidget* parent,
                                           gint action, gchar* firstButton);

    void   gtk_file_chooser_set_filename(GtkWidget* chooser, gchar* path);
    void   gtk_file_chooser_set_current_name(GtkWidget* chooser, gchar* name);
    void   gtk_file_chooser_set_current_folder(GtkWidget* chooser, gchar* path);
    void   gtk_file_chooser_set_do_overwrite_confirmation(GtkWidget* chooser,
                                                          gboolean confirm);
    /// **Owned** -- `g_free` it.
    gchar* gtk_file_chooser_get_filename(GtkWidget* chooser);

    void gtk_file_chooser_add_filter(GtkWidget* chooser, gpointer filter);

    /// A filter is floating until a chooser takes it, which is the one place
    /// in this binding where something that is not a widget is.
    gpointer gtk_file_filter_new();
    void gtk_file_filter_set_name(gpointer filter, gchar* name);
    void gtk_file_filter_add_pattern(gpointer filter, gchar* pattern);

    GtkWidget* gtk_color_chooser_dialog_new(gchar* title, GtkWidget* parent);
    void gtk_color_chooser_get_rgba(GtkWidget* chooser, GdkRGBA* into);
    void gtk_color_chooser_set_rgba(GtkWidget* chooser, GdkRGBA* colour);

    GtkWidget* gtk_font_chooser_dialog_new(gchar* title, GtkWidget* parent);
    /// **Owned** -- a Pango description as text, `"Sans Bold 12"`.
    gchar* gtk_font_chooser_get_font(GtkWidget* chooser);
    void   gtk_font_chooser_set_font(GtkWidget* chooser, gchar* font);
}

/// `GtkFileChooserAction`.
public const gint GTK_FILE_CHOOSER_ACTION_OPEN          = 0;
public const gint GTK_FILE_CHOOSER_ACTION_SAVE          = 1;
public const gint GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER = 2;

// `GtkResponseType` is in `Gtk.sl`, beside the dialog calls that answer one.

// ===================================================================== label

public extern "C"
{
    /// Where the text sits inside the label's own allocation, 0.0 to 1.0. A
    /// label centres itself by default, which no other toolkit does and which
    /// a widget set has to undo.
    void gtk_label_set_xalign(GtkWidget* label, gfloat align);
    void gtk_label_set_yalign(GtkWidget* label, gfloat align);

    /// Shortening rather than overflowing, which is what a label in a fixed
    /// layout needs: a size request is a minimum, so a label with more text
    /// than room would otherwise grow over its neighbours.
    void gtk_label_set_ellipsize(GtkWidget* label, gint mode);
}

/// `PangoEllipsizeMode`.
public const gint PANGO_ELLIPSIZE_NONE   = 0;
public const gint PANGO_ELLIPSIZE_START  = 1;
public const gint PANGO_ELLIPSIZE_MIDDLE = 2;
public const gint PANGO_ELLIPSIZE_END    = 3;

// ==================================================== the default button

public extern "C"
{
    /// **A window has the default, and a button only consents to it.** Both
    /// calls are needed: the widget must be able to take it and the window
    /// must hand it over.
    void gtk_widget_set_can_default(GtkWidget* widget, gboolean can);
    void gtk_window_set_default(GtkWidget* window, GtkWidget* button);
}

// ============================================================ window state

public extern "C"
{
    void gtk_window_iconify(GtkWidget* window);
    void gtk_window_deiconify(GtkWidget* window);

    /// What the window manager has done with it, as bits. Asked of the
    /// `GdkWindow` rather than remembered from an event, because GDK has no
    /// accessor for the state an event carries and a remembered answer is
    /// wrong the first time something else minimises the window.
    gint gdk_window_get_state(gpointer window);
}

/// `GdkWindowState`, of which these three are the ones a form cares about.
public const gint GDK_WINDOW_STATE_WITHDRAWN  = 1;
public const gint GDK_WINDOW_STATE_ICONIFIED  = 2;
public const gint GDK_WINDOW_STATE_MAXIMIZED  = 4;
public const gint GDK_WINDOW_STATE_FULLSCREEN = 16;

// ================================================================= editable

public extern "C"
{
    /// `GtkEditable`'s, so they work on an entry and on a spin button alike.
    /// An `end` of -1 means "to the end of the text".
    void gtk_editable_select_region(GtkWidget* editable, gint start, gint end);

    /// False when nothing is selected, and then the caret position is what a
    /// caller wants instead.
    gboolean gtk_editable_get_selection_bounds(GtkWidget* editable,
                                               gint* start, gint* end);
    gint gtk_editable_get_position(GtkWidget* editable);
    void gtk_editable_set_position(GtkWidget* editable, gint at);
}

// ================================================================= notebook

public extern "C"
{
    /// The widget shown on the tab, which is a label for every tab this
    /// backend makes and could be a box with a picture in it.
    void gtk_notebook_set_tab_label(GtkWidget* notebook, GtkWidget* page,
                                    GtkWidget* label);
    void gtk_notebook_set_scrollable(GtkWidget* notebook, gboolean scrollable);
}

// ========================================================== row references

public extern "C"
{
    /// **A handle to a row that survives the model changing.** An iter does
    /// not and a path does not: inserting a sibling before a row changes its
    /// path, and a reference is what tracks it instead. This is what a tree
    /// peer hands out as a node handle.
    gpointer gtk_tree_row_reference_new(gpointer model, gpointer path);

    /// **Owned** -- free the path. Null once the row has been removed, which
    /// is how a caller learns a node handle has gone stale.
    gpointer gtk_tree_row_reference_get_path(gpointer reference);
    gboolean gtk_tree_row_reference_valid(gpointer reference);
    void     gtk_tree_row_reference_free(gpointer reference);
}

// ================================================== the theme's own colours

public extern "C"
{
    /// A colour the theme named -- `"theme_bg_color"`, `"theme_fg_color"`,
    /// `"theme_selected_bg_color"`, `"insensitive_fg_color"`.
    ///
    /// **False when the theme has no such name**, which is the whole reason
    /// this is the call to use: GTK 3 removed `gtk_style_context_get_*_color`
    /// in all but name, the replacements render rather than report, and a
    /// theme that does not define a name is a fact a caller can act on. Every
    /// theme derived from Adwaita defines these, and one that does not gets
    /// the fallback.
    gboolean gtk_style_context_lookup_color(gpointer context, gchar* name,
                                            GdkRGBA* into);

    /// The application's settings object, **borrowed**. `gtk-font-name` on it
    /// is the font the desktop dresses its own dialogs in.
    gpointer gtk_settings_get_default();
}

// ============================================================== spin button

public extern "C"
{
    /// **A `GtkSpinButton` is not a `GtkRange`.** It looks like one -- it has
    /// a value, a range and steps -- and `gtk_range_set_range` on one is a
    /// `GTK_IS_RANGE` assertion at run time and nothing at compile time,
    /// because every widget is a `GtkWidget*` to a binding.
    void gtk_spin_button_set_range(GtkWidget* spin, gdouble minimum, gdouble maximum);
    void gtk_spin_button_set_increments(GtkWidget* spin, gdouble step, gdouble page);
}

// ============================================================ radio buttons

public extern "C"
{
    /// Puts `button` in `group`'s group, or in one of its own when `group` is
    /// null.
    ///
    /// **Grouping is what makes a radio button a radio button**, and the seam
    /// does not carry it: `CreateCheck(owner, parent, radio)` says only that
    /// one is wanted. Win32 groups by `WS_GROUP` on the first of a run; GTK
    /// groups by naming another button. So the container joins each radio to
    /// the first one in it, which is the same rule stated a different way --
    /// and without this every radio is its own group and they all stay ticked
    /// at once.
    void gtk_radio_button_join_group(GtkWidget* button, GtkWidget* group);
}

#endif
