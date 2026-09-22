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

// Five interfaces, one widget.
//
// **This is the sharpest thing the GTK backend has to say about the seam.** A
// list box, a checked list, a column header, a tree and a details list are
// five window classes on Windows -- `LISTBOX`, a `LISTBOX` with owner drawing,
// `SysHeader32`, `SysTreeView32`, `SysListView32` -- and the seam has an
// interface for each. GTK has one widget, `GtkTreeView`, and the difference
// between the five is which model is behind it and which columns are in front:
//
//   | interface | model | columns |
//   |---|---|---|
//   | `IListPeer` | `GtkListStore(text)` | one, no header |
//   | `ICheckListPeer` | `GtkListStore(bool, text)` | a toggle and a text |
//   | `IHeaderPeer` | none | headers with no rows under them |
//   | `ITreeViewPeer` | `GtkTreeStore(pixbuf, text)` | one, no header |
//   | `IListViewPeer` | `GtkListStore(pixbuf, text...)` | one per column |
//
// **Not one interface had to change for that**, which is the answer to
// whether `Forms.Platform` describes controls or describes Win32. It
// describes controls.
//
// **A model is set through a `GValue`.** `gtk_list_store_set` is variadic over
// column-and-value pairs, which a binding cannot spell; the `_value` form
// takes one column and one `GValue`, so `Put` below is what every write goes
// through and is the only place in this backend that touches GLib's type
// system.
module Forms.Platform.Gtk;

import Standard.Collections;
import Standard.Text;
import Forms.Drawing;
import Forms.Platform;
#if UNIX
import Gtk.GLib;
import Gtk.GObject;
import Gtk.Gdk;
import Gtk.Api;
import Gtk.Signals;
import Gtk.Events;

// =========================================================== writing a cell

/// Writes one string into one cell of a list store.
///
/// The `GValue` is initialised, set, written and unset every time rather than
/// kept: it owns a copy of the string while it holds one, and a reused value
/// would have to be unset between types anyway.
void PutText(gpointer store, GtkTreeIter* row, int column, String text, bool tree)
{
    GValue value;
    g_value_init(&value, G_TYPE_STRING);
    g_value_set_string(&value, text.ToPointer());
    if (tree)
    {
        gtk_tree_store_set_value(store, row, column, &value);
    }
    else
    {
        gtk_list_store_set_value(store, row, column, &value);
    }
    g_value_unset(&value);
}

void PutFlag(gpointer store, GtkTreeIter* row, int column, bool state)
{
    GValue value;
    g_value_init(&value, G_TYPE_BOOLEAN);
    g_value_set_boolean(&value, state ? 1 : 0);
    gtk_list_store_set_value(store, row, column, &value);
    g_value_unset(&value);
}

void PutPicture(gpointer store, GtkTreeIter* row, int column, gpointer picture,
                bool tree)
{
    GValue value;
    g_value_init(&value, gdk_pixbuf_get_type());
    g_value_set_object(&value, picture);
    if (tree)
    {
        gtk_tree_store_set_value(store, row, column, &value);
    }
    else
    {
        gtk_list_store_set_value(store, row, column, &value);
    }
    g_value_unset(&value);
}

/// Reads one string out of one cell. The value owns the string it hands back,
/// so it is copied before the value is unset.
String TakeText(gpointer model, GtkTreeIter* row, int column)
{
    GValue value;
    gtk_tree_model_get_value(model, row, column, &value);
    gchar* raw = g_value_get_string(&value);
    var text = raw == null ? "" : Text.FromNullTerminated(raw);
    g_value_unset(&value);
    return text;
}

bool TakeFlag(gpointer model, GtkTreeIter* row, int column)
{
    GValue value;
    gtk_tree_model_get_value(model, row, column, &value);
    bool state = g_value_get_boolean(&value) != 0;
    g_value_unset(&value);
    return state;
}

/// A text column, built in three calls because `new_with_attributes` is
/// variadic. `title` may be empty, for a control whose headers are hidden.
gpointer TextColumn(String title, int modelColumn)
{
    gpointer column = gtk_tree_view_column_new();
    gpointer renderer = gtk_cell_renderer_text_new();
    gtk_tree_view_column_set_title(column, title.ToPointer());
    gtk_tree_view_column_pack_start(column, renderer, 1);
    gtk_tree_view_column_add_attribute(column, renderer, "text".ToPointer(), modelColumn);
    return column;
}

// ============================================================ a scrolled view

/// What the four scrolling controls share: a scrolled window around a tree
/// view, and the model behind it.
///
/// **`widget` is the scrolled window and `inner` is the view**, which is the
/// arrangement `GtkPeer` was built to allow: the parent places the scroller,
/// and the signals, the style and the focus all belong to the view.
public class GtkModelPeer : GtkPeer
{
    protected gpointer model;
    protected gpointer selection;

    public GtkModelPeer(IControlNotify owner)
    {
        base(gtk_scrolled_window_new(null, null), owner);

        GtkWidget* view = gtk_tree_view_new();
        gtk_container_add(widget, view);
        gtk_widget_show(view);
        SetInner(view);

        gtk_scrolled_window_set_policy(widget, GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
        selection = gtk_tree_view_get_selection(view);
        gtk_tree_selection_set_mode(selection, GTK_SELECTION_SINGLE);

        WhenSignal((GtkWidget*)selection, "changed", (peer) =>
        {
            ((GtkModelPeer)peer).SelectionChanged();
        });

        // **A double click rather than `row-activated`, for the same reason
        // the tab control does not use `switch-page`:** that signal carries a
        // path *and* a column, and a handler of this shape would read the
        // boxed closure out of the column pointer. The click count is already
        // on the event, so this is the same notification from a signal that
        // fits.
        WhenEvent(view, "button-press-event", (peer, carried) =>
        {
            ((GtkModelPeer)peer).RowPressed((GdkEvent*)carried);
            return false;
        });
    }

    void SelectionChanged()
    {
        if (echoing)
            return;
        var target2 = Owner;
        if (target2 != null)
            ((IControlNotify)target2).OnPlatformValueChanged();
    }

    void RowPressed(GdkEvent* event)
    {
        guint clicks = 0u;
        if (gdk_event_get_click_count(event, &clicks) == 0 || clicks != 2u)
            return;
        var target2 = Owner;
        if (target2 != null)
            ((IControlNotify)target2).OnPlatformActivated();
    }

    /// The row at `index` among the roots, or false when there is none.
    protected bool RowAt(int index, GtkTreeIter* into)
    {
        if (index < 0)
            return false;
        return gtk_tree_model_iter_nth_child(model, into, null, index) != 0;
    }

    protected int RowCountOf()
    {
        return gtk_tree_model_iter_n_children(model, null);
    }

    /// Which root row is selected, or -1.
    ///
    /// The path's first index, which for a flat model is the row number. The
    /// indices rather than the printed path, which would have to be parsed:
    /// `"3:1"` is the second child of the fourth root, and a flat model only
    /// ever produces the first number.
    protected int SelectedRow
    {
        get
        {
            GtkTreeIter row;
            if (gtk_tree_selection_get_selected(selection, null, &row) == 0)
                return -1;

            gpointer path = gtk_tree_model_get_path(model, &row);
            if (path == null)
                return -1;

            int index = -1;
            if (gtk_tree_path_get_depth(path) > 0)
            {
                gint* indices = gtk_tree_path_get_indices(path);
                if (indices != null)
                    index = indices[0u];
            }
            gtk_tree_path_free(path);
            return index;
        }
    }

    protected void SelectRow(int index)
    {
        var chosen = selection;
        if (index < 0)
        {
            Quietly(() => { gtk_tree_selection_unselect_all(chosen); });
            return;
        }

        GtkTreeIter row;
        if (!RowAt(index, &row))
            return;
        var at = row;
        Quietly(() => { gtk_tree_selection_select_iter(chosen, &at); });
    }

    /// Removes a row of a flat model, quietly: removing the selected row
    /// changes the selection, and that was the program's doing.
    protected void RemoveListRow(int index)
    {
        GtkTreeIter row;
        if (!RowAt(index, &row))
            return;
        var store = model;
        var at = row;
        Quietly(() => { gtk_list_store_remove(store, &at); });
    }

    /// Empties a flat model, quietly, for the same reason.
    protected void ClearList()
    {
        var store = model;
        Quietly(() => { gtk_list_store_clear(store); });
    }
}

// ================================================================= list box

public class GtkListPeer : GtkModelPeer, IListPeer
{
    public GtkListPeer(IControlNotify owner)
    {
        base(owner);

        GType[1] types = [G_TYPE_STRING];
        model = gtk_list_store_newv(1, &types[0u]);
        gtk_tree_view_set_model(inner, model);
        gtk_tree_view_set_headers_visible(inner, 0);
        gtk_tree_view_append_column(inner, TextColumn("", 0));
    }

    ~GtkListPeer()
    {
        if (model != null)
        {
            g_object_unref(model);
            model = null;
        }
    }

    public void InsertItem(int index, String text)
    {
        GtkTreeIter row;
        gtk_list_store_insert(model, &row, index);
        PutText(model, &row, 0, text, false);
    }

    public void RemoveItem(int index) => RemoveListRow(index);
    public void ClearItems() => ClearList();
    public int ItemCount => RowCountOf();

    public void SetSelectedIndex(int index) => SelectRow(index);
    public int  GetSelectedIndex() => SelectedRow;
}

// ============================================================= checked list

/// A list whose rows each have a tick.
///
/// **The toggle is a second column, not a state on the row.** A
/// `GtkCellRendererToggle` draws from a boolean in the model and reports a
/// click by *path* rather than by changing anything -- the model is the
/// program's to update, which is the one thing about a cell renderer that
/// surprises everyone once.
public class GtkCheckListPeer : GtkModelPeer, ICheckListPeer
{
    public GtkCheckListPeer(IControlNotify owner)
    {
        base(owner);

        GType[2] types = [G_TYPE_BOOLEAN, G_TYPE_STRING];
        model = gtk_list_store_newv(2, &types[0u]);
        gtk_tree_view_set_model(inner, model);
        gtk_tree_view_set_headers_visible(inner, 0);

        gpointer column = gtk_tree_view_column_new();
        gpointer toggle = gtk_cell_renderer_toggle_new();
        gtk_tree_view_column_pack_start(column, toggle, 0);
        gtk_tree_view_column_add_attribute(column, toggle, "active".ToPointer(), 0);
        gtk_tree_view_append_column(inner, column);
        gtk_tree_view_append_column(inner, TextColumn("", 1));

        WhenEvent((GtkWidget*)toggle, "toggled", (peer, carried) =>
        {
            ((GtkCheckListPeer)peer).Flip(Text.FromNullTerminated((gchar*)carried));
            return false;
        });
    }

    /// Ticks or unticks the row a `GtkCellRendererToggle` reported.
    ///
    /// **The renderer changed nothing.** It draws from a boolean in the model
    /// and reports a click by path; updating the model is the program's
    /// business, which is the one thing about a cell renderer that surprises
    /// everyone once.
    void Flip(String path)
    {
        GtkTreeIter row;
        if (gtk_tree_model_get_iter_from_string(model, &row, path.ToPointer()) == 0)
        {
            return;
        }
        PutFlag(model, &row, 0, !TakeFlag(model, &row, 0));

        var target2 = Owner;
        if (target2 != null)
            ((IControlNotify)target2).OnPlatformValueChanged();
    }

    ~GtkCheckListPeer()
    {
        if (model != null)
        {
            g_object_unref(model);
            model = null;
        }
    }

    public void InsertItem(int index, String text)
    {
        GtkTreeIter row;
        gtk_list_store_insert(model, &row, index);
        PutFlag(model, &row, 0, false);
        PutText(model, &row, 1, text, false);
    }

    public void RemoveItem(int index) => RemoveListRow(index);
    public void ClearItems() => ClearList();
    public int ItemCount => RowCountOf();

    public void SetSelectedIndex(int index) => SelectRow(index);
    public int  GetSelectedIndex() => SelectedRow;

    public void SetItemChecked(int index, bool checked)
    {
        GtkTreeIter row;
        if (RowAt(index, &row))
            PutFlag(model, &row, 0, checked);
    }

    public bool GetItemChecked(int index)
    {
        GtkTreeIter row;
        if (!RowAt(index, &row))
            return false;
        return TakeFlag(model, &row, 0);
    }
}

// ============================================================ header control

/// A row of draggable column headings and nothing under them.
///
/// **GTK has no standalone header**, and this is the one control in the
/// backend that is built rather than mapped: a `GtkTreeView` with its headers
/// showing and no model. The headings drag and resize because they are real
/// tree view headers, which is more than a row of buttons would give.
public class GtkHeaderPeer : GtkPeer, IHeaderPeer
{
    List<gpointer> _sections;
    /// The widths as they were set.
    ///
    /// **`gtk_tree_view_column_get_width` is the width it was *drawn* at**,
    /// which is zero until the view has been laid out and is the theme's
    /// answer rather than the program's afterwards. Win32's `HDM_GETITEM`
    /// answers the width that was set, so that is what this does: a program
    /// that sets a width and reads it back gets the number it gave.
    List<int> _widths;

    public GtkHeaderPeer(IControlNotify owner)
    {
        base(gtk_tree_view_new(), owner);
        _sections = new List<gpointer>();
        _widths = new List<int>();
        gtk_tree_view_set_headers_visible(widget, 1);
    }

    public int AddSection(String text, int width)
    {
        gpointer column = TextColumn(text, 0);
        gtk_tree_view_column_set_resizable(column, 1);
        gtk_tree_view_column_set_sizing(column, GTK_TREE_VIEW_COLUMN_FIXED);
        gtk_tree_view_column_set_fixed_width(column, width);
        gtk_tree_view_append_column(widget, column);
        _sections.Add(column);
        _widths.Add(width);
        return (int)_sections.Count - 1;
    }

    public void SetSectionWidth(int index, int width)
    {
        if (index < 0 || (nuint)index >= _sections.Count)
            return;
        gtk_tree_view_column_set_fixed_width(_sections[(nuint)index], width);
        _widths[(nuint)index] = width;
    }

    public int GetSectionWidth(int index)
    {
        if (index < 0 || (nuint)index >= _widths.Count)
            return 0;
        return _widths[(nuint)index];
    }

    public int SectionCount => (int)_sections.Count;
}

// ================================================================== a tree

/// A node handle: a number, and a row reference behind it.
///
/// **A path is not a handle.** Inserting a sibling before a row changes its
/// path, so a handle that was one would name a different node afterwards. A
/// `GtkTreeRowReference` tracks the row through every change to the model,
/// and the number is what the seam asked for -- two handles naming one node
/// compare equal because the number is the same.
public class GtkTreeNode : ITreeNodeHandle
{
    public nuint Number { get; }
    public GtkTreeNode(nuint id) => Number = id;
    public nuint Id => Number;
}

public class GtkTreePeer : GtkModelPeer, ITreeViewPeer
{
    /// Every live node's row reference, by the number handed out for it.
    Dictionary<nuint, gpointer> _nodes;
    nuint _nextId;
    GtkImageListBackend? _pictures;

    public GtkTreePeer(IControlNotify owner)
    {
        base(owner);
        _nodes = new Dictionary<nuint, gpointer>();
        _nextId = 1u;
        _pictures = null;

        GType[2] types = [gdk_pixbuf_get_type(), G_TYPE_STRING];
        model = gtk_tree_store_newv(2, &types[0u]);
        gtk_tree_view_set_model(inner, model);
        gtk_tree_view_set_headers_visible(inner, 0);

        gpointer column = gtk_tree_view_column_new();
        gpointer icon = gtk_cell_renderer_pixbuf_new();
        gpointer text = gtk_cell_renderer_text_new();
        gtk_tree_view_column_pack_start(column, icon, 0);
        gtk_tree_view_column_add_attribute(column, icon, "pixbuf".ToPointer(), 0);
        gtk_tree_view_column_pack_start(column, text, 1);
        gtk_tree_view_column_add_attribute(column, text, "text".ToPointer(), 1);
        gtk_tree_view_append_column(inner, column);
    }

    ~GtkTreePeer()
    {
        ForgetAll();
        if (model != null)
        {
            g_object_unref(model);
            model = null;
        }
    }

    void ForgetAll()
    {
        foreach (var pair in _nodes)
            gtk_tree_row_reference_free(pair.Value);
        _nodes.Clear();
    }

    /// The iter for a handle, or false when the node has been removed --
    /// which a program holding an old handle genuinely can ask for.
    bool IterFor(ITreeNodeHandle? node, GtkTreeIter* into)
    {
        if (node == null)
            return false;

        var found = _nodes.Find(((ITreeNodeHandle)node).Id);
        if (found is Some held)
        {
            gpointer path = gtk_tree_row_reference_get_path(held.Value);
            if (path == null)
                return false;

            bool ok = gtk_tree_model_get_iter(model, into, path) != 0;
            gtk_tree_path_free(path);
            return ok;
        }
        return false;
    }

    nuint Remember(GtkTreeIter* row)
    {
        gpointer path = gtk_tree_model_get_path(model, row);
        gpointer reference = gtk_tree_row_reference_new(model, path);
        gtk_tree_path_free(path);

        nuint id = _nextId;
        _nextId = _nextId + 1u;
        _nodes.Add(id, reference);
        return id;
    }

    public ITreeNodeHandle AddNode(ITreeNodeHandle? parent, ITreeNodeHandle? previous,
                                   String text, int image)
    {
        GtkTreeIter under;
        GtkTreeIter after;
        GtkTreeIter made;

        bool hasParent = IterFor(parent, &under);
        bool hasPrevious = IterFor(previous, &after);

        gtk_tree_store_insert_after(model, &made,
                                    hasParent ? &under : null,
                                    hasPrevious ? &after : null);
        PutText(model, &made, 1, text, true);
        if (image >= 0 && _pictures != null)
        {
            PutPicture(model, &made, 0,
                       ((GtkImageListBackend)_pictures).Pixbuf(image), true);
        }
        return new GtkTreeNode(Remember(&made));
    }

    /// Quietly, because removing the selected node changes the selection.
    ///
    /// **The node's descendants go with it**, and so do their references: a
    /// reference to a removed row stays allocated and answers nothing, so each
    /// one no longer valid is freed here rather than kept for the life of the
    /// tree.
    public void RemoveNode(ITreeNodeHandle node)
    {
        GtkTreeIter row;
        if (IterFor(node, &row))
        {
            var store = model;
            var at = row;
            Quietly(() => { gtk_tree_store_remove(store, &at); });
        }

        var gone = new List<nuint>();
        foreach (var pair in _nodes)
        {
            if (pair.Key == node.Id || gtk_tree_row_reference_valid(pair.Value) == 0)
                gone.Add(pair.Key);
        }
        foreach (var id in gone)
        {
            var found = _nodes.Find(id);
            if (found is Some held)
                gtk_tree_row_reference_free(held.Value);
            _nodes.Remove(id);
        }
    }

    public void SetNodeText(ITreeNodeHandle node, String text)
    {
        GtkTreeIter row;
        if (IterFor(node, &row))
            PutText(model, &row, 1, text, true);
    }

    public String GetNodeText(ITreeNodeHandle node)
    {
        GtkTreeIter row;
        if (!IterFor(node, &row))
            return "";
        return TakeText(model, &row, 1);
    }

    public void SetNodeExpanded(ITreeNodeHandle node, bool expanded)
    {
        GtkTreeIter row;
        if (!IterFor(node, &row))
            return;

        gpointer path = gtk_tree_model_get_path(model, &row);
        if (path == null)
            return;
        if (expanded)
        {
            gtk_tree_view_expand_row(inner, path, 0);
        }
        else
        {
            gtk_tree_view_collapse_row(inner, path);
        }
        gtk_tree_path_free(path);
    }

    public void SelectNode(ITreeNodeHandle node)
    {
        GtkTreeIter row;
        if (!IterFor(node, &row))
            return;
        var chosen = selection;
        var at = row;
        Quietly(() => { gtk_tree_selection_select_iter(chosen, &at); });
    }

    /// A *fresh* handle for the node at a row path, which is why the seam says
    /// two handles naming one node need not be the same object: this looks the
    /// row up among the references rather than remembering which handle it
    /// gave out. Null when no live node names that row.
    ///
    /// The path is borrowed -- the caller frees it.
    ///
    /// Paths are compared as strings rather than with `gtk_tree_path_compare`
    /// because each reference has to be turned into a path to be looked at
    /// either way, so the comparison is the cheap half of the loop whichever
    /// way it is done.
    ITreeNodeHandle? HandleForPath(gpointer path)
    {
        if (path == null)
            return null;

        gchar* raw = gtk_tree_path_to_string(path);
        var wanted = raw == null ? "" : Text.FromNullTerminated(raw);
        if (raw != null)
            g_free((gpointer)raw);

        foreach (var pair in _nodes)
        {
            gpointer other = gtk_tree_row_reference_get_path(pair.Value);
            if (other == null)
                continue;
            gchar* text = gtk_tree_path_to_string(other);
            var seen = text == null ? "" : Text.FromNullTerminated(text);
            if (text != null)
                g_free((gpointer)text);
            gtk_tree_path_free(other);

            if (seen == wanted)
                return new GtkTreeNode(pair.Key);
        }
        return null;
    }

    public ITreeNodeHandle? GetSelectedNode()
    {
        GtkTreeIter row;
        if (gtk_tree_selection_get_selected(selection, null, &row) == 0)
            return null;

        gpointer path = gtk_tree_model_get_path(model, &row);
        if (path == null)
            return null;

        var found = HandleForPath(path);
        gtk_tree_path_free(path);
        return found;
    }

    /// The row under a point in the control's coordinates, which is what the
    /// mouse is reported in.
    ///
    /// `gtk_tree_view_get_path_at_pos` wants the rows' own coordinates, which
    /// begin below any column headers, so the point is converted first.
    ///
    /// A miss answers false *and* leaves the path null, so both are checked:
    /// the documented contract is the flag, and the null is what the rest of
    /// this method would otherwise dereference.
    public ITreeNodeHandle? GetNodeAt(Forms.Drawing.Point at)
    {
        gint x = 0;
        gint y = 0;
        gtk_tree_view_convert_widget_to_bin_window_coords(inner, at.X, at.Y, &x, &y);

        gpointer path = null;
        if (gtk_tree_view_get_path_at_pos(inner, x, y, &path, null, null, null) == 0)
            return null;
        if (path == null)
            return null;

        var found = HandleForPath(path);
        gtk_tree_path_free(path);
        return found;
    }

    public void Clear()
    {
        ForgetAll();
        var store = model;
        Quietly(() => { gtk_tree_store_clear(store); });
    }

    public void SetImages(IImageListBackend? images)
    {
        _pictures = images == null ? null : (GtkImageListBackend)images;
    }
}

// ============================================================= details list

public class GtkListViewPeer : GtkModelPeer, IListViewPeer
{
    /// How many text columns the model has. One picture column comes first,
    /// so a cell in column `n` is model column `n + 1`.
    int _columns;
    List<gpointer> _headings;
    GtkImageListBackend? _pictures;

    public GtkListViewPeer(IControlNotify owner)
    {
        base(owner);
        _headings = new List<gpointer>();
        _pictures = null;

        // **The column count is fixed when the store is made**, and a
        // `GtkListStore` cannot grow one afterwards. Sixteen is what a details
        // list gets; `TListView` programs use two or three, and a seam that
        // let a column be added at any time would need the model rebuilt and
        // every row copied.
        _columns = 16;
        GType[17] types = [gdk_pixbuf_get_type(),
                           G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING,
                           G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING,
                           G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING,
                           G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING];
        model = gtk_list_store_newv(17, &types[0u]);
        gtk_tree_view_set_model(inner, model);
        gtk_tree_view_set_headers_visible(inner, 1);
    }

    ~GtkListViewPeer()
    {
        if (model != null)
        {
            g_object_unref(model);
            model = null;
        }
    }

    /// **Only `Details` is a different widget.** GTK's answer to icons is
    /// `GtkIconView`, which is not a tree view and cannot be exchanged for
    /// one, so the three icon styles all show as a details list with its
    /// headers hidden -- which is what a `TListView` in `vsList` looks like
    /// anyway, and is stated rather than silently approximated.
    public void SetStyle(ListViewStyle style)
    {
        gtk_tree_view_set_headers_visible(inner, style == ListViewStyle.Details ? 1 : 0);
    }

    public int AddColumn(String text, int width, HorizontalAlignment alignment)
    {
        int index = (int)_headings.Count;
        if (index >= _columns)
            return -1;

        gpointer column = gtk_tree_view_column_new();
        gtk_tree_view_column_set_title(column, text.ToPointer());

        // The picture goes in the first column only, which is where every
        // details list puts it.
        if (index == 0)
        {
            gpointer icon = gtk_cell_renderer_pixbuf_new();
            gtk_tree_view_column_pack_start(column, icon, 0);
            gtk_tree_view_column_add_attribute(column, icon, "pixbuf".ToPointer(), 0);
        }

        gpointer renderer = gtk_cell_renderer_text_new();
        gtk_tree_view_column_pack_start(column, renderer, 1);
        gtk_tree_view_column_add_attribute(column, renderer, "text".ToPointer(), index + 1);

        gtk_tree_view_column_set_resizable(column, 1);
        gtk_tree_view_column_set_sizing(column, GTK_TREE_VIEW_COLUMN_FIXED);
        gtk_tree_view_column_set_fixed_width(column, width);
        gtk_tree_view_column_set_alignment(column,
            alignment == HorizontalAlignment.Center ? 0.5f
            : alignment == HorizontalAlignment.Right ? 1.0f : 0.0f);

        gtk_tree_view_append_column(inner, column);
        _headings.Add(column);
        return index;
    }

    public void SetColumnWidth(int column, int width)
    {
        if (column < 0 || (nuint)column >= _headings.Count)
            return;
        gtk_tree_view_column_set_fixed_width(_headings[(nuint)column], width);
    }

    public int AddRow(String text, int image)
    {
        GtkTreeIter row;
        gtk_list_store_append(model, &row, null);
        PutText(model, &row, 1, text, false);
        if (image >= 0 && _pictures != null)
        {
            PutPicture(model, &row, 0,
                       ((GtkImageListBackend)_pictures).Pixbuf(image), false);
        }
        return RowCountOf() - 1;
    }

    public void SetCell(int row, int column, String text)
    {
        if (column < 0 || column >= _columns)
            return;
        GtkTreeIter at;
        if (RowAt(row, &at))
            PutText(model, &at, column + 1, text, false);
    }

    public String GetCell(int row, int column)
    {
        if (column < 0 || column >= _columns)
            return "";
        GtkTreeIter at;
        if (!RowAt(row, &at))
            return "";
        return TakeText(model, &at, column + 1);
    }

    public void RemoveRow(int row) => RemoveListRow(row);
    public void Clear() => ClearList();
    public int RowCount => RowCountOf();

    public int  GetSelectedRow() => SelectedRow;
    public void SetSelectedRow(int row) => SelectRow(row);

    public void SetImages(IImageListBackend? images)
    {
        _pictures = images == null ? null : (GtkImageListBackend)images;
    }

    /// **A GTK row is always selected whole**, so the first half of this is
    /// what GTK does anyway and cannot be turned off. The grid lines are real.
    public void SetFullRowSelect(bool full, bool gridLines)
    {
        gtk_tree_view_set_grid_lines(inner,
            gridLines ? GTK_TREE_VIEW_GRID_LINES_BOTH : GTK_TREE_VIEW_GRID_LINES_NONE);
    }
}

#endif
