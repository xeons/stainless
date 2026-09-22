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

// GTK as classes: a widget hierarchy, ARC ownership, and events that are
// lambdas.
//
// The raw bindings under `bindings/gtk/api` are GTK spelled as GTK spells
// itself. This is the layer a program should actually use, and it differs in
// four ways that are worth stating before any of it makes sense.
//
// **One class per widget, and the hierarchy does the checking.** GTK's C API
// is `GtkWidget*` everywhere with `GTK_WINDOW()` macros that check at run time
// and cost a warning when they fail. Here `Window` is a `Container` is a
// `Widget`, and passing a `Label` where a `Window` belongs is a compile error.
//
// **A wrapper owns one reference to its widget.** The constructor sinks the
// floating reference GTK hands back, and the destructor drops it. That is the
// whole of the memory management, and it composes with ARC: a `Window` field
// on a class keeps its window alive exactly as long as the class lives.
//
//     A program must keep its wrappers. Dropping the last reference to a
//     `Window` does not close the window -- GTK keeps its own reference to a
//     toplevel until it is destroyed -- but it does throw away the handle. An
//     `Application` holds its windows for this reason.
//
// **An event is a closure** (§2.14.1): a method and the object it belongs to.
// So a handler is either a method of whatever cares, bound to it --
//
//     button.OnClicked(this.Save);
//
// -- or a lambda that captures what it needs:
//
//     var count = new Counter();
//     button.OnClicked(() => { count.Bump(); label.SetText(count.Text()); });
//
// Both are the same two words, and both keep alive whatever they refer to for
// as long as GTK holds them. `Gtk.Signals` is where the retain and the matching
// release live, and why the arrangement is leak-free with no bookkeeping here.
//
// **The names read as a toolkit rather than as GTK.** `new Box(true, 6)` is
// a column, `Grid.AttachChild` takes a cell and a span, and a `ScrollView` has
// a minimum content size. This layer is what `forms/`'s GTK backend is written
// against, so it is shaped by what a widget set behind a seam needs rather
// than by what the C header happens to be called.
module Gtk;

import Standard.Collections;
import Gtk.GLib;
import Gtk.GObject;
import Gtk.Gdk;
import Gtk.Api;
import Gtk.Signals;
import Gtk.Events;


#if UNIX

extern "C"
{
    void sl_retain(gpointer pointer);
    void sl_release(gpointer pointer);
}

// ==================================================================== events

// A widget's events are `closure` types (§2.14.1), so a handler is either a
// method bound to the object that cares -- `field.OnChanged(this.Revalidate)`
// -- or a lambda that captures what it needs. Both are the same two words, and
// both keep alive whatever they refer to for as long as the widget holds them.
//
// `Handler` itself comes from `Gtk.Signals`, because that is where the C side
// of it lives. Only the answering shape is declared here, since the raw layer's
// version carries the sender and the pointer and almost no handler wants either.

/// An event that can refuse: **true means handled**, and nothing else sees it.
///
/// The one to know is `Window.OnClosing`, where true keeps the window open.
public closure bool Question();

// ==================================================================== widget

/// Anything that can appear on screen.
///
/// Not abstract, because GTK has widgets this binding does not wrap and
/// `Widget` is a usable handle on one: `Handle` is public, and the raw layer
/// takes it.
public class Widget
{
    protected GtkWidget* handle;

    /// Takes ownership of a widget.
    ///
    /// `g_object_ref_sink` rather than `g_object_ref`, because a freshly
    /// constructed widget's reference is *floating*: GTK hands back a count of
    /// one that nobody owns, expecting the container it is added to to claim
    /// it. Sinking converts that into a reference this wrapper owns, so the
    /// destructor's unref is balanced whether or not the widget is ever
    /// parented.
    protected Widget(GtkWidget* raw)
    {
        handle = raw;
        g_object_ref_sink(raw);
    }

    ~Widget()
    {
        if (handle != null)
            g_object_unref(handle);
    }

    /// The GTK widget, for reaching a call this layer does not wrap.
    ///
    /// **Borrowed.** It is valid while this wrapper is, and the wrapper is
    /// what owns the reference.
    public GtkWidget* Handle => handle;

    public void Show() => gtk_widget_show(handle);

    /// Shows this widget and everything inside it. What a window wants once,
    /// after it has been filled, and the thing every first GTK program
    /// forgets.
    public void ShowAll() => gtk_widget_show_all(handle);

    public void Hide() => gtk_widget_hide(handle);

    public void SetVisible(bool visible)
    {
        gtk_widget_set_visible(handle, visible ? 1 : 0);
    }

    public bool IsVisible() => gtk_widget_get_visible(handle) != 0;

    /// Greys the widget out and stops it responding.
    public void SetEnabled(bool enabled)
    {
        gtk_widget_set_sensitive(handle, enabled ? 1 : 0);
    }

    public bool IsEnabled() => gtk_widget_get_sensitive(handle) != 0;

    /// The smallest the widget will be laid out at. -1 for either means "ask
    /// the widget", which is the default.
    public void SetSize(int width, int height)
    {
        gtk_widget_set_size_request(handle, width, height);
    }

    public void Focus() => gtk_widget_grab_focus(handle);

    public void SetTooltip(String text)
    {
        gtk_widget_set_tooltip_text(handle, text.ToPointer());
    }

    /// Asks for a repaint. The only correct way: drawing outside a paint
    /// handler is not something GTK supports.
    public void Invalidate() => gtk_widget_queue_draw(handle);

    /// Space outside the widget, on all four sides.
    ///
    /// A widget property rather than a wrapper around the child, so it can be
    /// set on a widget that already has a parent and does not change the tree.
    public void SetMargin(int margin)
    {
        gtk_widget_set_margin_start(handle, margin);
        gtk_widget_set_margin_end(handle, margin);
        gtk_widget_set_margin_top(handle, margin);
        gtk_widget_set_margin_bottom(handle, margin);
    }

    /// Whether the widget takes a share of any extra space in its container.
    ///
    /// Also settable per child at the point a `Box` packs it, which is the
    /// older spelling and the one a box's own arguments still offer.
    public void SetExpands(bool horizontal, bool vertical)
    {
        gtk_widget_set_hexpand(handle, horizontal ? 1 : 0);
        gtk_widget_set_vexpand(handle, vertical ? 1 : 0);
    }

    /// Destroys the widget and everything in it, breaking it out of its
    /// container. The wrapper stays valid and its calls stop doing anything,
    /// which is what GTK does with a destroyed widget too.
    public void DestroyWidget() => gtk_widget_destroy(handle);

    /// Runs when the widget is destroyed.
    public void OnDestroyed(Handler handler)
    {
        ConnectPlainSignal(handle, "destroy", handler);
    }

    // The input events. `Pointer`, `Key` and their handler interfaces are in
    // `Drawing.sl`, which is the same module: a widget that paints itself is
    // the one that usually wants these, and they read better next to it.
    //
    // **A `DrawingArea` receives none of these until `EnableInputEvents` is
    // called.** Most other widgets receive the mouse and not the keyboard, and a widget
    // that cannot take focus never sees a key at all.

    public void OnMouseDown(PointerHandler handler)
    {
        ConnectEvent(handle, "button-press-event", PointerAdapter(handler));
    }

    public void OnMouseUp(PointerHandler handler)
    {
        ConnectEvent(handle, "button-release-event", PointerAdapter(handler));
    }

    public void OnMouseMoved(PointerHandler handler)
    {
        ConnectEvent(handle, "motion-notify-event", PointerAdapter(handler));
    }

    public void OnKeyDown(KeyHandler handler)
    {
        ConnectEvent(handle, "key-press-event", KeyAdapter(handler));
    }
}

// ================================================================= container

/// A widget that holds others.
public class Container : Widget
{
    protected Container(GtkWidget* raw) => base(raw);

    /// Puts a child in. A container that holds exactly one -- a window, a
    /// button, a scrolled view -- replaces what was there.
    public void Add(Widget child) => gtk_container_add(handle, child.Handle);

    public void Remove(Widget child) => gtk_container_remove(handle, child.Handle);

    /// Blank space inside the container's own edge, around everything in it.
    public void SetPadding(int padding)
    {
        gtk_container_set_border_width(handle, (guint)padding);
    }
}

// ======================================================================= box

/// A row or a column.
///
/// The commonest layout in GTK: children packed end to end, each taking its
/// natural size unless it was asked to expand.
public class Box : Container
{
    /// A column when `vertical`, a row otherwise.
    public Box(bool vertical, int spacing)
    {
        base(gtk_box_new(vertical ? GTK_ORIENTATION_VERTICAL
                                  : GTK_ORIENTATION_HORIZONTAL, spacing));
    }

    /// Adds a child at the end of what is there.
    ///
    /// `expand` gives the child a share of any space left over. It is the one
    /// argument worth understanding: a column of five labels and one expanding
    /// text area puts all the slack in the text area, which is almost always
    /// what a form wants.
    public void PackStart(Widget child, bool expand)
    {
        gtk_box_pack_start(handle, child.Handle, expand ? 1 : 0, 1, 0u);
    }

    /// The same, packed from the other end -- the right of a row, the bottom
    /// of a column. Where an OK button goes.
    public void PackEnd(Widget child, bool expand)
    {
        gtk_box_pack_end(handle, child.Handle, expand ? 1 : 0, 1, 0u);
    }

    public void SetSpacing(int spacing) => gtk_box_set_spacing(handle, spacing);

    /// Every child the same size, whatever it asked for.
    public void SetUniform(bool uniform)
    {
        gtk_box_set_homogeneous(handle, uniform ? 1 : 0);
    }
}

// ====================================================================== grid

/// A table of cells.
///
/// **`AttachChild` takes a cell and a span on both versions**, which is the one
/// place this layer does arithmetic rather than just renaming. `GtkGrid` is
/// already described that way; `GtkTable` wants the grid *lines* a child sits
/// between, so a single cell at column 2 is `left=2, right=3`. Passing a grid's
/// numbers to a table is off by one in the direction that looks plausible, so
/// it is done here once instead of in every program.
public class Grid : Container
{
    public Grid()
    {
        base(gtk_grid_new());
    }

    /// Puts a child at a cell, spanning `columns` by `rows` of them.
    public void AttachChild(Widget child, int column, int row, int columns, int rows)
    {
        gtk_grid_attach(handle, child.Handle, column, row, columns, rows);
    }

    /// One cell at one place, which is what most calls want.
    public void PlaceChild(Widget child, int column, int row)
    {
        AttachChild(child, column, row, 1, 1);
    }

    public void SetSpacing(int columns, int rows)
    {
        gtk_grid_set_column_spacing(handle, (guint)columns);
        gtk_grid_set_row_spacing(handle, (guint)rows);
    }
}

// ==================================================================== window

/// A top-level window.
public class Window : Container
{
    public Window(String title)
    {
        base(gtk_window_new(GTK_WINDOW_TOPLEVEL));
        gtk_window_set_title(handle, title.ToPointer());
    }

    public void SetTitle(String title)
    {
        gtk_window_set_title(handle, title.ToPointer());
    }

    /// The size the window opens at, which the user may change afterwards.
    public void SetDefaultSize(int width, int height)
    {
        gtk_window_set_default_size(handle, width, height);
    }

    /// The size right now, whatever it was opened at.
    public void ResizeWindow(int width, int height)
    {
        gtk_window_resize(handle, width, height);
    }

    public void SetResizable(bool resizable)
    {
        gtk_window_set_resizable(handle, resizable ? 1 : 0);
    }

    /// Centres the window on the screen, or on its parent if it has one.
    public void CenterWindow()
    {
        gtk_window_set_position(handle, GTK_WIN_POS_CENTER_ON_PARENT);
    }

    /// Makes this window block its parent, which is what a dialog is.
    public void SetModalFor(Window parent)
    {
        gtk_window_set_transient_for(handle, parent.Handle);
        gtk_window_set_modal(handle, 1);
    }

    /// Shows the window and brings it to the front.
    public void Activate() => gtk_window_present(handle);

    public void MaximizeWindow() => gtk_window_maximize(handle);
    public void EnterFullscreen() => gtk_window_fullscreen(handle);

    /// Runs when the user tries to close the window. **Answering true keeps it
    /// open**, which is how an "unsaved changes" prompt works:
    ///
    ///     window.OnClosing(() => { return document.IsDirty(); });
    public void OnClosing(Question handler)
    {
        // A lambda is the adapter: it takes the shape the raw layer emits and
        // drops the two arguments no window-closing handler wants.
        ConnectEvent(handle, "delete-event", (sender, carried) => { return handler(); });
    }
}

// ===================================================================== label

/// Text that is not editable.
public class Label : Widget
{
    public Label(String text) => base(gtk_label_new(text.ToPointer()));

    public void SetText(String text) => gtk_label_set_text(handle, text.ToPointer());

    public String GetText() => Text.FromNullTerminated(gtk_label_get_text(handle));

    /// Pango markup: `<b>`, `<i>`, `<span foreground="red">`. The closest
    /// thing GTK has to rich text in a label.
    ///
    /// **The markup is parsed**, so text a program did not write itself has to
    /// have its `&` and `<` escaped first or the label will be blank and GTK
    /// will complain on stderr.
    public void SetMarkup(String markup)
    {
        gtk_label_set_markup(handle, markup.ToPointer());
    }

    public void SetWrap(bool wrap) => gtk_label_set_line_wrap(handle, wrap ? 1 : 0);

    /// Lets the user select and copy the text.
    public void SetSelectable(bool selectable)
    {
        gtk_label_set_selectable(handle, selectable ? 1 : 0);
    }
}

// ===================================================================== entry

/// One line of editable text.
public class Entry : Widget
{
    public Entry() => base(gtk_entry_new());

    public void SetText(String text) => gtk_entry_set_text(handle, text.ToPointer());

    /// A copy of what is in the entry. GTK's own answer is borrowed and stops
    /// being valid the next time the entry changes, so this copies it.
    public String GetText() => Text.FromNullTerminated(gtk_entry_get_text(handle));

    /// Turns the entry into a password field.
    public void SetMasked(bool masked)
    {
        gtk_entry_set_visibility(handle, masked ? 0 : 1);
    }

    public void SetReadOnly(bool readOnly)
    {
        gtk_editable_set_editable(handle, readOnly ? 0 : 1);
    }

    public void SetMaxLength(int characters)
    {
        gtk_entry_set_max_length(handle, characters);
    }

    /// The grey prompt an empty entry shows.
    public void SetPlaceholder(String text)
    {
        gtk_entry_set_placeholder_text(handle, text.ToPointer());
    }

    /// Runs on every keystroke.
    public void OnChanged(Handler handler)
    {
        ConnectPlainSignal(handle, "changed", handler);
    }

    /// Runs when the user presses Enter.
    public void OnEntered(Handler handler)
    {
        ConnectPlainSignal(handle, "activate", handler);
    }
}

// ==================================================================== button

public class Button : Container
{
    public Button(String label) => base(gtk_button_new_with_label(label.ToPointer()));

    /// For a derived button -- a check box, a radio button -- which is a
    /// different GTK widget with the same signals.
    protected Button(GtkWidget* raw) => base(raw);

    public void SetLabel(String label) => gtk_button_set_label(handle, label.ToPointer());

    public String GetLabel() => Text.FromNullTerminated(gtk_button_get_label(handle));

    public void OnClicked(Handler handler)
    {
        ConnectPlainSignal(handle, "clicked", handler);
    }
}

/// A button that stays in.
public class CheckBox : Button
{
    public CheckBox(String label) => base(gtk_check_button_new_with_label(label.ToPointer()));

    protected CheckBox(GtkWidget* raw) => base(raw);

    public bool IsChecked() => gtk_toggle_button_get_active(handle) != 0;

    /// **This emits `toggled`**, so a handler that sets another box will hear
    /// from it. Setting a value in a handler for the same value is how a GTK
    /// program gets into a loop.
    public void SetChecked(bool checked)
    {
        gtk_toggle_button_set_active(handle, checked ? 1 : 0);
    }

    public void OnToggled(Handler handler)
    {
        ConnectPlainSignal(handle, "toggled", handler);
    }
}

/// One of a set, of which exactly one is chosen.
///
/// **The group is a widget, not a container.** Every radio button after the
/// first names one already in the group, which is GTK's model and not the one
/// a reader coming from a form designer expects: putting two groups in one box
/// is fine, and putting one group across two boxes is fine as well.
public class RadioButton : CheckBox
{
    /// Starts a new group.
    public RadioButton(String label)
    {
        base(gtk_radio_button_new_with_label_from_widget(null, label.ToPointer()));
    }

    /// Joins the group `sibling` is in.
    public RadioButton(String label, RadioButton sibling)
    {
        base(gtk_radio_button_new_with_label_from_widget(
            sibling.Handle, label.ToPointer()));
    }
}

// ================================================================= text area

/// Editable text of any length, with its own scrollbars if it is in a
/// `ScrollView`.
public class TextArea : Widget
{
    /// The buffer, borrowed from the view. Not a `Widget`: it is a `GObject`
    /// but not a widget, and wrapping it as one would put `Show()` on
    /// something that cannot be shown.
    GtkWidget* _buffer;

    public TextArea()
    {
        base(gtk_text_view_new());
        _buffer = gtk_text_view_get_buffer(handle);
    }

    public void SetText(String text)
    {
        gtk_text_buffer_set_text(_buffer, text.ToPointer(), -1);
    }

    /// Everything in the buffer.
    ///
    /// GTK allocates the answer and the caller frees it, which is what the
    /// `g_free` is doing: it is one of the few places in this binding where
    /// ownership crosses in that direction.
    public String GetText()
    {
        GtkTextIter start;
        GtkTextIter stop;
        gtk_text_buffer_get_bounds(_buffer, &start, &stop);

        gchar* raw = gtk_text_buffer_get_text(_buffer, &start, &stop, 0);
        var text = Text.FromNullTerminated(raw);
        g_free(raw);
        return text;
    }

    public void SetReadOnly(bool readOnly)
    {
        gtk_text_view_set_editable(handle, readOnly ? 0 : 1);
    }

    public void SetWrap(bool wrap)
    {
        gtk_text_view_set_wrap_mode(handle, wrap ? GTK_WRAP_WORD_CHAR : GTK_WRAP_NONE);
    }

    /// Runs whenever the text changes. Connected to the *buffer*, because that
    /// is what changes -- the view is only a window onto it.
    public void OnChanged(Handler handler)
    {
        ConnectPlainSignal(_buffer, "changed", handler);
    }
}

// ================================================================ scroll view

/// Scrollbars around one child that is bigger than the space for it.
public class ScrollView : Container
{
    public ScrollView()
    {
        base(gtk_scrolled_window_new(null, null));
        gtk_scrolled_window_set_policy(handle, GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
    }

    /// Whether each bar is always there, there when needed, or never.
    public void SetPolicy(bool horizontal, bool vertical)
    {
        gtk_scrolled_window_set_policy(handle,
            horizontal ? GTK_POLICY_AUTOMATIC : GTK_POLICY_NEVER,
            vertical ? GTK_POLICY_AUTOMATIC : GTK_POLICY_NEVER);
    }

    /// The size the view asks for before it starts scrolling.
    ///
    /// Not the same as `SetSize`, which asks for the size of the whole view
    /// with its scrollbars; this is the part the content gets.
    public void SetMinimumContent(int width, int height)
    {
        gtk_scrolled_window_set_min_content_width(handle, width);
        gtk_scrolled_window_set_min_content_height(handle, height);
    }
}

// ================================================================= combo box

/// A drop-down list of strings.
public class ComboBox : Widget
{
    /// How many have been added, so that `ItemCount` can answer without
    /// walking the model.
    int _count;

    public ComboBox()
    {
        base(gtk_combo_box_text_new());
        _count = 0;
    }

    public void Add(String text)
    {
        gtk_combo_box_text_append_text(handle, text.ToPointer());
        _count = _count + 1;
    }

    public void Clear()
    {
        gtk_combo_box_text_remove_all(handle);
        _count = 0;
    }

    /// The index of what is chosen, or -1 for nothing.
    public int GetSelectedIndex() => gtk_combo_box_get_active(handle);

    public void SetSelectedIndex(int index) => gtk_combo_box_set_active(handle, index);

    /// The text of what is chosen, or "" for nothing.
    ///
    /// GTK allocates this one too, so it is freed here.
    public String GetSelectedText()
    {
        gchar* raw = gtk_combo_box_text_get_active_text(handle);
        if (raw == null)
            return "";

        var text = Text.FromNullTerminated(raw);
        g_free(raw);
        return text;
    }

    public void OnChanged(Handler handler)
    {
        ConnectPlainSignal(handle, "changed", handler);
    }
}

// ============================================================== progress bar

public class ProgressBar : Widget
{
    public ProgressBar() => base(gtk_progress_bar_new());

    /// 0.0 to 1.0.
    public void SetFraction(double fraction)
    {
        gtk_progress_bar_set_fraction(handle, fraction);
    }

    public double GetFraction() => gtk_progress_bar_get_fraction(handle);

    /// One step of the back-and-forth a bar shows when the total is unknown.
    public void PulseProgress() => gtk_progress_bar_pulse(handle);

    /// Text drawn over the bar.
    ///
    /// A bar shows no text until it is told to, so setting some turns it on:
    /// a program says this once rather than twice.
    public void SetText(String text)
    {
        gtk_progress_bar_set_text(handle, text.ToPointer());
        gtk_progress_bar_set_show_text(handle, 1);
    }
}

// ================================================================ spin button

/// A number with arrows.
public class SpinBox : Widget
{
    public SpinBox(double minimum, double maximum, double step)
    {
        base(gtk_spin_button_new_with_range(minimum, maximum, step));
    }

    public double Value => gtk_spin_button_get_value(handle);
    public int    GetIntegerValue() => gtk_spin_button_get_value_as_int(handle);

    public void SetValue(double value) => gtk_spin_button_set_value(handle, value);

    /// How many places after the point. Zero makes it an integer box.
    public void SetDecimals(int digits) => gtk_spin_button_set_digits(handle, (guint)digits);

    public void OnChanged(Handler handler)
    {
        ConnectPlainSignal(handle, "value-changed", handler);
    }
}

// ==================================================================== slider

/// A number as a track and a handle.
public class Slider : Widget
{
    public Slider(bool vertical, double minimum, double maximum, double step)
    {
        base(gtk_scale_new_with_range(
            vertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL,
            minimum, maximum, step));
    }

    public double Value => gtk_range_get_value(handle);
    public void   SetValue(double value) => gtk_range_set_value(handle, value);

    public void OnChanged(Handler handler)
    {
        ConnectPlainSignal(handle, "value-changed", handler);
    }
}

// ================================================================= separator

/// A line between things.
public class Separator : Widget
{
    public Separator(bool vertical)
    {
        base(gtk_separator_new(vertical ? GTK_ORIENTATION_VERTICAL
                                        : GTK_ORIENTATION_HORIZONTAL));
    }
}

// ================================================================== notebook

/// Tabbed pages.
public class Notebook : Container
{
    public Notebook() => base(gtk_notebook_new());

    /// Adds a page with a text tab. Answers its index.
    public int AddPage(Widget page, String tab)
    {
        var label = new Label(tab);
        return gtk_notebook_append_page(handle, page.Handle, label.Handle);
    }

    public int  GetCurrentPage() => gtk_notebook_get_current_page(handle);
    public void SetCurrentPage(int index) => gtk_notebook_set_current_page(handle, index);
    public int  GetPageCount() => gtk_notebook_get_n_pages(handle);

    public void OnPageChanged(Handler handler)
    {
        ConnectPlainSignal(handle, "switch-page", handler);
    }
}

// ================================================================= statusbar

/// A line of text along the bottom of a window.
public class StatusBar : Widget
{
    guint _context;

    public StatusBar()
    {
        base(gtk_statusbar_new());
        _context = gtk_statusbar_get_context_id(handle, "stainless");
    }

    /// Replaces what is showing.
    ///
    /// GTK's status bar is a *stack*, so that two parts of a program can each
    /// push and pop without losing the other's message. This wrapper uses one
    /// context and replaces, because that is what a status bar looks like from
    /// the outside; a program that wants the stack has `Handle`.
    public void SetText(String text)
    {
        gtk_statusbar_pop(handle, _context);
        gtk_statusbar_push(handle, _context, text.ToPointer());
    }
}

// ===================================================================== menus

/// An item in a menu.
public class MenuItem : Container
{
    public MenuItem(String label)
    {
        base(gtk_menu_item_new_with_mnemonic(label.ToPointer()));
    }

    /// A dividing line, which is an item that does nothing.
    ///
    /// Not called `Separator`, because that is the name of the widget between
    /// two things in a box and this is a different GTK type with a different
    /// parent.
    public static MenuItem CreateDivider()
    {
        return new MenuItem(gtk_separator_menu_item_new());
    }

    MenuItem(GtkWidget* raw) => base(raw);

    /// Hangs a menu off this item, which is what makes it a submenu.
    public void SetSubmenu(Menu submenu)
    {
        gtk_menu_item_set_submenu(handle, submenu.Handle);
    }

    public void OnChosen(Handler handler)
    {
        ConnectPlainSignal(handle, "activate", handler);
    }
}

/// A drop-down menu.
public class Menu : Container
{
    public Menu() => base(gtk_menu_new());

    protected Menu(GtkWidget* raw) => base(raw);

    public void AppendItem(MenuItem item) => gtk_menu_shell_append(handle, item.Handle);
}

/// The bar across the top of a window.
public class MenuBar : Menu
{
    public MenuBar() => base(gtk_menu_bar_new());

    /// Adds a top-level menu -- File, Edit -- and answers the item it hangs
    /// from, for anything else the caller wants to do to it.
    public MenuItem AddMenu(String label, Menu menu)
    {
        var item = new MenuItem(label);
        item.SetSubmenu(menu);
        Append(item);
        return item;
    }
}

// =================================================================== dialogs

/// What a message dialog answered.
public variant Answer
{
    Yes;
    No;
    Cancelled;
}

/// The modal message boxes, which are the one part of GTK that is a function
/// rather than a widget in ordinary use.
public static class Dialogs
{

    /// Shows a message and waits for OK.
    public static void ShowInformation(Window parent, String title, String message)
    {
        ShowMessageDialog(parent, GTK_MESSAGE_INFO, GTK_BUTTONS_OK, title, message);
    }

    public static void ShowWarning(Window parent, String title, String message)
    {
        ShowMessageDialog(parent, GTK_MESSAGE_WARNING, GTK_BUTTONS_OK, title, message);
    }

    public static void ShowError(Window parent, String title, String message)
    {
        ShowMessageDialog(parent, GTK_MESSAGE_ERROR, GTK_BUTTONS_OK, title, message);
    }

    /// Asks a yes-or-no question. `Cancelled` is what closing the dialog
    /// gives, which is not the same as No and should not be treated as one.
    public static Answer AskQuestion(Window parent, String title, String message)
    {
        int response = ShowMessageDialog(parent, GTK_MESSAGE_QUESTION, GTK_BUTTONS_YES_NO,
            title, message);
        if (response == GTK_RESPONSE_YES)
            return Yes;
        if (response == GTK_RESPONSE_NO)
            return No;
        return Cancelled;
    }

    /// **The message goes in as an argument, not as the format string.**
    ///
    /// `gtk_message_dialog_new` is variadic and its last named parameter is a
    /// `printf` format. Passing a caller's text straight in would let a `%s`
    /// in it read the stack -- the oldest bug in C, and it would arrive here
    /// through something as ordinary as a filename. So the format is `"%s"`
    /// and the text is data.
    static int ShowMessageDialog(Window parent, int kind, int buttons, String title, String message)
    {
        var dialog = gtk_message_dialog_new(parent.Handle,
            GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
            kind, buttons, "%s", message.ToPointer());

        gtk_window_set_title(dialog, title.ToPointer());

        int response = gtk_dialog_run(dialog);
        gtk_widget_destroy(dialog);
        return response;
    }
}

// =============================================================== application

/// Starting GTK, running it, and stopping it.
///
/// A class rather than free functions because it holds the windows: a
/// `Window` whose last reference goes away leaves its widget on screen with
/// nothing to reach it by, and the toplevel windows of a program are exactly
/// the things that should live as long as the program does.
public class Application
{
    List<Window> _windows;
    bool _started;

    public Application()
    {
        _windows = new List<Window>();
        _started = false;
    }

    /// Starts GTK. **False means there is no display**, which is an ordinary
    /// outcome over ssh and in a container, and the reason this is
    /// `gtk_init_check` rather than `gtk_init`: the latter ends the program
    /// before `Main` has a chance to say anything.
    public bool StartToolkit()
    {
        _started = gtk_init_check(null, null) != 0;
        return _started;
    }

    /// Keeps a window alive for as long as this application is, and closes the
    /// application when the window is destroyed.
    ///
    /// That last part is the behaviour every small program wants and no
    /// toolkit does by default: GTK's main loop runs until something calls
    /// `gtk_main_quit`, and a program that never does hangs after its last
    /// window closes.
    public void AddWindow(Window window)
    {
        _windows.Add(window);
        window.OnDestroyed(() => { Exit(); });
    }

    /// Whether `StartToolkit` found a display.
    public bool IsStarted => _started;

    /// Runs until `Exit`. Everything a GUI program does happens inside here.
    public void Run() => gtk_main();

    public void Exit() => gtk_main_quit();

    /// Handles everything waiting and returns, for a long computation that
    /// wants to keep its window painting without a thread.
    ///
    /// **This re-enters every handler**, so a button that starts the
    /// computation can be pressed again in the middle of it. Disable it first;
    /// that is what `SetEnabled` is for.
    public void DoEvents()
    {
        while (gtk_events_pending() != 0)
            gtk_main_iteration();
    }

    /// Runs `body` after `milliseconds`, again and again while it answers
    /// true.
    ///
    /// The only correct way to do something later in a GUI program: a sleep in
    /// a handler stops the loop, and the loop is what repaints.
    public void RepeatEvery(int milliseconds, Question body)
    {
        ScheduleTicker((uint)milliseconds, body);
    }
}

// The timer plumbing, which is `Gtk.Signals`' trick again for a GLib source
// rather than a GObject signal.

class Ticker
{
    public Question Body;
    public Ticker(Question body) => Body = body;
}

gboolean InvokeTicker(gpointer data)
{
    var ticker = (Ticker)data;
    return ticker.Body() ? 1 : 0;
}

void ReleaseTicker(gpointer data) => sl_release(data);

void ScheduleTicker(uint milliseconds, Question body)
{
    var ticker = new Ticker(body);
    sl_retain((gpointer)ticker);

    g_timeout_add_full(G_PRIORITY_DEFAULT, milliseconds, InvokeTicker,
        (gpointer)ticker, ReleaseTicker);
}

#endif
