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

// The lists on AppKit: a combo box, and five controls on one table.
//
// **A list box, a check list, a header, a details list and a tree are all
// `NSTableView`**, the tree as its subclass `NSOutlineView`, as GTK's five are
// all `GtkTreeView`. The table is view-based, as the LCL's `TCocoaTableListView`
// is: each visible cell is an `NSTableCellView` holding a label, and a tick box
// or a picture before it when the control has them.
//
// **The rows live here, not in the table.** AppKit asks a data source how many
// rows there are and a delegate for each visible cell, so every peer keeps its
// items and answers from them. Nothing is copied into AppKit but the cells on
// screen.
//
// **AppKit reports a selection the program made**, as GTK does, so every
// change the program makes runs quietly; see `RunQuietly`.
module Forms.Platform.AppKit;

import Standard.Collections;
import Standard.Text;
import Forms;
import Forms.Drawing;
import Forms.Platform;
#if MACOS && FORMS_APPKIT
import Standard.ObjC;
import MacOS.System;
import MacOS.CoreFoundation;
import MacOS.CoreGraphics;
import MacOS.Foundation;
import MacOS.AppKit;

// ================================================================ the views

/// Selects the row under a press of the left button into a window that is
/// not key. AppKit's table selects only in the key window; this backend takes
/// the first click everywhere, as every view's `acceptsFirstMouse:` says.
void SelectRowUnderPress(NSTableView table, NSEvent event)
{
    var window = table.Window;
    if (window == null || ((NSWindow)window).KeyWindow || !table.Enabled ||
        event.Type != NSEventType.LeftMouseDown)
        return;
    var row = table.RowAtPoint(table.ConvertPointFromView(event.LocationInWindow, null));
    if (row >= (NSInteger)0)
        table.SelectRowIndexesByExtendingSelection(NSIndexSet.IndexSetWithIndex((nuint)row), false);
}

/// A table that reports a press, a key and the focus before AppKit acts on
/// them. Its `mouseDown:` tracks the press to the release, as a button's does.
public objc class FormsTableView : NSTableView
{
    public weak AppKitPeer? Peer;

    AppKitPeer? FindPeer()
    {
        AppKitPeer? held = Peer;
        return held;
    }

    public override bool AcceptsFirstMouse(NSEvent? event) => true;

    public override void MouseDown(NSEvent event)
    {
        var peer = FindPeer();
        if (peer != null)
            ((AppKitPeer)peer).ReportPress(event, FindEventPoint(this, event));
        SelectRowUnderPress(this, event);
        base.MouseDown(event);
        if (peer != null)
            ((AppKitPeer)peer).ReportRelease(event, FindEventPoint(this, event));
    }

    public override void RightMouseDown(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportPress(event, FindEventPoint(this, event));
        base.RightMouseDown(event);
    }

    public override void KeyDown(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportKey(event, true);
        base.KeyDown(event);
    }

    public override void KeyUp(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportKey(event, false);
        base.KeyUp(event);
    }

    public override bool BecomeFirstResponder()
    {
        bool taken = base.BecomeFirstResponder();
        if (taken && FindPeer() is AppKitPeer peer)
            peer.ReportFocus(true);
        return taken;
    }

    public override bool ResignFirstResponder()
    {
        bool given = base.ResignFirstResponder();
        if (given && FindPeer() is AppKitPeer peer)
            peer.ReportFocus(false);
        return given;
    }
}

/// The same for a tree.
public objc class FormsOutlineView : NSOutlineView
{
    public weak AppKitPeer? Peer;

    AppKitPeer? FindPeer()
    {
        AppKitPeer? held = Peer;
        return held;
    }

    public override bool AcceptsFirstMouse(NSEvent? event) => true;

    public override void MouseDown(NSEvent event)
    {
        var peer = FindPeer();
        if (peer != null)
            ((AppKitPeer)peer).ReportPress(event, FindEventPoint(this, event));
        SelectRowUnderPress(this, event);
        base.MouseDown(event);
        if (peer != null)
            ((AppKitPeer)peer).ReportRelease(event, FindEventPoint(this, event));
    }

    public override void RightMouseDown(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportPress(event, FindEventPoint(this, event));
        base.RightMouseDown(event);
    }

    public override void KeyDown(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportKey(event, true);
        base.KeyDown(event);
    }

    public override void KeyUp(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportKey(event, false);
        base.KeyUp(event);
    }

    public override bool BecomeFirstResponder()
    {
        bool taken = base.BecomeFirstResponder();
        if (taken && FindPeer() is AppKitPeer peer)
            peer.ReportFocus(true);
        return taken;
    }

    public override bool ResignFirstResponder()
    {
        bool given = base.ResignFirstResponder();
        if (given && FindPeer() is AppKitPeer peer)
            peer.ReportFocus(false);
        return given;
    }
}

/// What a table asks of its rows, answered by its peer.
public objc class FormsTableSource : NSObject, NSTableViewDataSource, NSTableViewDelegate
{
    public weak AppKitTablePeer? Peer;

    AppKitTablePeer? FindPeer()
    {
        AppKitTablePeer? held = Peer;
        return held;
    }

    public NSInteger NumberOfRowsInTableView(NSTableView tableView)
    {
        if (FindPeer() is AppKitTablePeer peer)
            return (NSInteger)peer.RowCount;
        return (NSInteger)0;
    }

    public NSView? TableViewViewForTableColumnRow(NSTableView tableView, NSTableColumn? tableColumn, NSInteger row)
    {
        if (FindPeer() is AppKitTablePeer peer)
            return peer.CreateCell(tableColumn, (int)row);
        return null;
    }

    public void TableViewSelectionDidChange(NSNotification notification)
    {
        if (FindPeer() is AppKitTablePeer peer)
            peer.ReportSelection();
    }

    public void TableViewColumnDidResize(NSNotification notification)
    {
        if (FindPeer() is AppKitTablePeer peer)
            peer.ReportColumnResized();
    }

    /// A row's tick box was clicked.
    [Selector("tick:")]
    public void Tick(AnyObject? sender)
    {
        if (sender is NSButton box && FindPeer() is AppKitTablePeer peer)
            peer.ReportTicked(box);
    }
}

/// A row's cell, which hands a click to the table unless it is on the tick
/// box: a label refuses the first click into an inactive window, and the
/// table, which takes it, would never see it.
public objc class FormsCellView : NSTableCellView
{
    public override bool AcceptsFirstMouse(NSEvent? event) => true;

    public override NSView? HitTest(NSPoint point)
    {
        var hit = base.HitTest(point);
        if (hit == null || (NSView)hit is NSButton)
            return hit;
        return this;
    }
}

/// A tree node as the outline view knows it. The view compares nodes by
/// pointer and does not keep them, so the peer holds each one for as long as
/// the node lives.
public objc class FormsTreeItem : NSObject
{
    public nuint Id;
}

/// What a tree asks of its nodes, answered by its peer.
public objc class FormsTreeSource : NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate
{
    public weak AppKitTreePeer? Peer;

    AppKitTreePeer? FindPeer()
    {
        AppKitTreePeer? held = Peer;
        return held;
    }

    public NSInteger OutlineViewNumberOfChildrenOfItem(NSOutlineView outlineView, AnyObject? item)
    {
        if (FindPeer() is AppKitTreePeer peer)
            return (NSInteger)peer.CountChildren(item);
        return (NSInteger)0;
    }

    /// Never asked for a child the count did not promise; `this` answers
    /// the impossible case without inventing a node.
    public AnyObject OutlineViewChildOfItem(NSOutlineView outlineView, NSInteger index, AnyObject? item)
    {
        if (FindPeer() is AppKitTreePeer peer && peer.FindChild(item, (int)index) is FormsTreeItem child)
            return child;
        return this;
    }

    public bool OutlineViewIsItemExpandable(NSOutlineView outlineView, AnyObject item)
    {
        if (FindPeer() is AppKitTreePeer peer)
            return peer.CountChildren(item) > 0;
        return false;
    }

    public NSView? OutlineViewViewForTableColumnItem(NSOutlineView outlineView, NSTableColumn? tableColumn, AnyObject item)
    {
        if (FindPeer() is AppKitTreePeer peer)
            return peer.CreateCell(item);
        return null;
    }

    public void OutlineViewSelectionDidChange(NSNotification notification)
    {
        if (FindPeer() is AppKitTreePeer peer)
            peer.ReportSelection();
    }
}

// ================================================================ a cell

/// What a table's cells are drawn with: the font, and the colours when the
/// program chose its own.
///
/// **The theme's own colours are left to AppKit.** A label in a table is
/// drawn in a colour AppKit inverts on a selected row and changes with Dark
/// Mode; one set to the same colour as fixed numbers would do neither, so a
/// colour that is the theme's is not applied.
public class AppKitCellStyle
{
    public NSFont Font;
    public NSColor? TextColor;

    public AppKitCellStyle()
    {
        Font = NSFont.SystemFontOfSize(NSFont.SystemFontSize);
        TextColor = null;
    }

    /// A row tall enough for a line of the font, with room above and below.
    public double RowHeight => (double)(FloorToInt(Font.Ascender - Font.Descender + Font.Leading) + 6);

    public void SetForeColor(Color color) =>
        TextColor = color.Equals(FromNSColor(NSColor.TextColor)) ? null : ToNSColor(color);
}

/// A row's cell: a label, after a tick box and a picture when it has them.
/// Its parts keep their places by their autoresizing as the table sizes it.
NSTableCellView CreateCellView(double width, double height, AppKitCellStyle style, NSButton? tick,
                               NSImage? picture, FSize pictureSize, String text, NSTextAlignment alignment)
{
    var cell = FormsCellView.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, width, height));
    var centred = NSAutoresizingMaskOptions.MinYMargin | NSAutoresizingMaskOptions.MaxYMargin;
    double x = 2.0;
    if (tick != null)
    {
        var box = (NSButton)tick;
        box.Frame = MakeNSRect(x, (height - 18.0) / 2.0, 18.0, 18.0);
        box.AutoresizingMask = centred;
        cell.AddSubview(box);
        x += 20.0;
    }
    if (picture != null)
    {
        double wide = (double)pictureSize.Width;
        double tall = (double)pictureSize.Height;
        var shown = NSImageView.Alloc().InitWithFrame(MakeNSRect(x, (height - tall) / 2.0, wide, tall));
        shown.Image = picture;
        shown.ImageScaling = NSImageScaling.ImageScaleProportionallyDown;
        shown.AutoresizingMask = centred;
        cell.AddSubview(shown);
        cell.ImageView = shown;
        x += wide + 4.0;
    }

    var label = NSTextField.LabelWithString(ToNSString(text));
    label.Font = style.Font;
    var color = style.TextColor;
    if (color != null)
        label.TextColor = (NSColor)color;
    label.Alignment = alignment;
    label.LineBreakMode = NSLineBreakMode.TruncatingTail;
    double line = label.FittingSize.height;
    double room = width - x - 2.0;
    label.Frame = MakeNSRect(x, (height - line) / 2.0, room < 0.0 ? 0.0 : room, line);
    label.AutoresizingMask = centred | NSAutoresizingMaskOptions.WidthSizable;
    cell.AddSubview(label);
    cell.TextField = label;
    return cell;
}

/// The picture at `index` in an image list, or null for none.
NSImage? FindListPicture(AppKitImageListBackend? images, int index)
{
    if (images == null)
        return null;
    var picture = ((AppKitImageListBackend)images).GetPicture(index);
    if (picture == null)
        return null;
    var bitmap = (AppKitBitmapBackend)picture;
    NSSize size;
    size.width = (double)bitmap.Width;
    size.height = (double)bitmap.Height;
    return NSImage.Alloc().InitWithCGImageSize(bitmap.Image, size);
}

NSTextAlignment ToNSTextAlignment(HorizontalAlignment alignment)
{
    switch (alignment)
    {
        case HorizontalAlignment.Center: return NSTextAlignment.Center;
        case HorizontalAlignment.Right: return NSTextAlignment.Right;
        default: return NSTextAlignment.Left;
    }
}

/// A column, which AppKit names by a string; the index serves.
NSTableColumn CreateTableColumn(int index, String title, int width)
{
    var column = NSTableColumn.Alloc().InitWithIdentifier(ToNSString(Standard.Text.FromInteger(index)));
    column.Title = ToNSString(title);
    column.Width = (double)width;
    column.ResizingMask = NSTableColumnResizingOptions.UserResizingMask;
    return column;
}

/// A scroll view around a table, which is what the parent places.
NSScrollView CreateTableScroller(NSTableView table, bool scrolls)
{
    var scroller = NSScrollView.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 120.0, 80.0));
    scroller.HasVerticalScroller = scrolls;
    scroller.HasHorizontalScroller = scrolls;
    scroller.AutohidesScrollers = true;
    scroller.BorderType = NSBorderType.BezelBorder;
    table.Style = NSTableViewStyle.Plain;
    table.RowSizeStyle = NSTableViewRowSizeStyle.Custom;
    table.ColumnAutoresizingStyle = NSTableViewColumnAutoresizingStyle.NoColumnAutoresizing;
    table.AllowsEmptySelection = true;
    table.AllowsMultipleSelection = false;
    scroller.DocumentView = table;
    return scroller;
}

// ================================================================ a table

/// What the four table controls share: the scroll view the parent places,
/// the table inside it, the source that answers the table, and the style of
/// the cells.
///
/// **A double click is the table's double action**, sent to a relay as a
/// button's action is; the single click's action is left unset.
///
/// AppKit asks the source for the rows as soon as it is set, which is here,
/// in this constructor: a derived class's rows have their values by then.
public class AppKitTablePeer : AppKitPeer
{
    protected FormsTableView Table;
    protected AppKitCellStyle Style;
    protected FormsTableSource Source;
    FormsTarget _relay;
    bool _quiet;

    public AppKitTablePeer(IControlNotify owner, bool scrolls)
    {
        Table = FormsTableView.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 120.0, 80.0));
        Style = new AppKitCellStyle();
        Table.RowHeight = Style.RowHeight;
        _quiet = false;
        Source = FormsTableSource.Alloc().Init()!;
        _relay = FormsTarget.Alloc().Init()!;
        Table.Target = _relay;
        Table.DoubleAction = Selector.Named("act:");
        base(CreateTableScroller(Table, scrolls), owner);

        Table.Peer = this;
        Source.Peer = this;
        _relay.Peer = this;
        Table.DataSource = Source;
        Table.Delegate = Source;
    }

    protected override void ForgetReporters()
    {
        base.ForgetReporters();
        Table.Peer = null;
        Source.Peer = null;
        _relay.Peer = null;
    }

    protected override NSView FocusView => Table;

    // ------------------------------------------------------------ the rows

    /// How many rows the table shows.
    public virtual int RowCount => 0;

    /// The cell at one row of one column.
    public virtual NSView? CreateCell(NSTableColumn? column, int row) => null;

    /// A row's tick box was clicked.
    public virtual void ReportTicked(NSButton box) { }

    /// A column was resized, by the user or by the program.
    public virtual void ReportColumnResized() { }

    // ------------------------------------------------------------ reports

    public void ReportSelection()
    {
        if (_quiet)
            return;
        var owner = Owner;
        if (owner != null)
            ((IControlNotify)owner).OnPlatformValueChanged();
    }

    public override void ReportAction()
    {
        var owner = Owner;
        if (owner != null && Table.ClickedRow >= (NSInteger)0)
            ((IControlNotify)owner).OnPlatformActivated();
    }

    /// Whether the change being made is the program's.
    protected bool IsQuiet => _quiet;

    /// Runs a change the program made without reporting what it moves.
    protected void RunQuietly(Action change)
    {
        bool was = _quiet;
        _quiet = true;
        change();
        _quiet = was;
    }

    /// The rows read again after a change to them.
    protected void ReloadRows() => RunQuietly(() => { Table.ReloadData(); });

    protected int SelectedRow => (int)Table.SelectedRow;

    protected void SelectRow(int index)
    {
        RunQuietly(() =>
        {
            if (index < 0 || index >= RowCount)
            {
                Table.DeselectAll(null);
                return;
            }
            Table.SelectRowIndexesByExtendingSelection(NSIndexSet.IndexSetWithIndex((nuint)index), false);
            Table.ScrollRowToVisible((NSInteger)index);
        });
    }

    /// The selection a row's insertion or removal leaves, which AppKit does
    /// not move by itself when the rows are read again.
    protected void SelectAfterInsert(int was, int index) => SelectRow(was >= index && was >= 0 ? was + 1 : was);

    protected void SelectAfterRemove(int was, int index) =>
        SelectRow(was == index ? -1 : was > index ? was - 1 : was);

    // ------------------------------------------------------------ IControlPeer

    public override void SetFont(Forms.Drawing.Font font)
    {
        Style.Font = ((AppKitFontBackend)font.Resource).Font;
        Table.RowHeight = Style.RowHeight;
        ReloadRows();
    }

    public override void SetForeColor(Color color)
    {
        Style.SetForeColor(color);
        ReloadRows();
    }

    public override void SetBackColor(Color color)
    {
        if (!color.Equals(FromNSColor(NSColor.TextBackgroundColor)))
            Table.BackgroundColor = ToNSColor(color);
    }

    public override void SetEnabled(bool enabled) => Table.Enabled = enabled;

    public override bool AcceptsTabFocus => !View.Hidden && Table.Enabled;
}

// ================================================================= list box

/// A list box, or with a tick box before each row a checked list.
public class AppKitListPeer : AppKitTablePeer, IListPeer
{
    List<String> _items;
    /// Whether each row is ticked; empty when the rows have no tick boxes.
    List<bool> _ticks;
    bool _ticked;
    NSTableColumn _column;

    public AppKitListPeer(IControlNotify owner, bool ticked)
    {
        _items = new List<String>();
        _ticks = new List<bool>();
        _ticked = ticked;
        _column = CreateTableColumn(0, "", 100);
        _column.ResizingMask = NSTableColumnResizingOptions.AutoresizingMask;
        base(owner, true);
        Table.AddTableColumn(_column);
        Table.HeaderView = null;
        Table.ColumnAutoresizingStyle = NSTableViewColumnAutoresizingStyle.LastColumnOnlyAutoresizingStyle;
    }

    public override int RowCount => (int)_items.Count;

    public override NSView? CreateCell(NSTableColumn? column, int row)
    {
        if (row < 0 || row >= RowCount)
            return null;
        NSButton? box = null;
        if (_ticked)
        {
            var made = NSButton.CheckboxWithTitleTargetAction(ToNSString(""), Source, Selector.Named("tick:"));
            made.State = _ticks[(nuint)row] ? 1 : 0;
            box = made;
        }
        return CreateCellView(_column.Width, Table.RowHeight, Style, box, null, CreateSize(0, 0),
                              _items[(nuint)row], NSTextAlignment.Left);
    }

    /// The box has already changed; the row it is in is found and kept.
    public override void ReportTicked(NSButton box)
    {
        int row = (int)Table.RowForView(box);
        if (!_ticked || row < 0 || row >= RowCount)
            return;
        _ticks[(nuint)row] = box.State == 1;
        var owner = Owner;
        if (owner != null)
            ((IControlNotify)owner).OnPlatformValueChanged();
    }

    /// The one column fills the width, as a list box's text does.
    public override void SetBounds(FRect bounds)
    {
        base.SetBounds(bounds);
        Table.SizeLastColumnToFit();
    }

    public void InsertItem(int index, String text)
    {
        if (index < 0 || index > RowCount)
            return;
        int was = SelectedRow;
        _items.Insert((nuint)index, text);
        _ticks.Insert((nuint)index, false);
        ReloadRows();
        SelectAfterInsert(was, index);
    }

    public void RemoveItem(int index)
    {
        if (index < 0 || index >= RowCount)
            return;
        int was = SelectedRow;
        _items.RemoveAt((nuint)index);
        _ticks.RemoveAt((nuint)index);
        ReloadRows();
        SelectAfterRemove(was, index);
    }

    public void ClearItems()
    {
        _items.Clear();
        _ticks.Clear();
        ReloadRows();
        SelectRow(-1);
    }

    public int ItemCount => RowCount;

    public void SetSelectedIndex(int index) => SelectRow(index);
    public int GetSelectedIndex() => SelectedRow;

    public void SetItemChecked(int index, bool checked)
    {
        if (index < 0 || index >= RowCount)
            return;
        _ticks[(nuint)index] = checked;
        ReloadRows();
    }

    public bool GetItemChecked(int index)
    {
        if (index < 0 || index >= RowCount)
            return false;
        return _ticks[(nuint)index];
    }
}

/// A list whose rows each have a tick box before the text.
public class AppKitCheckListPeer : AppKitListPeer, ICheckListPeer
{
    public AppKitCheckListPeer(IControlNotify owner) => base(owner, true);
}

// ============================================================ header control

/// A row of column headings and nothing under them: a table with no rows, as
/// GTK's is a tree view with no model.
public class AppKitHeaderPeer : AppKitTablePeer, IHeaderPeer
{
    List<NSTableColumn> _sections;

    public AppKitHeaderPeer(IControlNotify owner)
    {
        _sections = new List<NSTableColumn>();
        base(owner, false);
        ((NSScrollView)View).BorderType = NSBorderType.NoBorder;
    }

    /// A heading dragged wider or narrower.
    public override void ReportColumnResized()
    {
        var owner = Owner;
        if (!IsQuiet && owner != null)
            ((IControlNotify)owner).OnPlatformValueChanged();
    }

    public int AddSection(String text, int width)
    {
        int index = (int)_sections.Count;
        var column = CreateTableColumn(index, text, width);
        RunQuietly(() => { Table.AddTableColumn(column); });
        _sections.Add(column);
        return index;
    }

    public void SetSectionWidth(int index, int width)
    {
        if (index < 0 || (nuint)index >= _sections.Count)
            return;
        var column = _sections[(nuint)index];
        RunQuietly(() => { column.Width = (double)width; });
    }

    public int GetSectionWidth(int index)
    {
        if (index < 0 || (nuint)index >= _sections.Count)
            return 0;
        return RoundToInt(_sections[(nuint)index].Width);
    }

    public int SectionCount => (int)_sections.Count;

    public override bool AcceptsTabFocus => false;
}

// ============================================================= details list

/// One row of a details list: its cells, the first being its text, and its
/// picture.
public class AppKitListViewRow
{
    public List<String> Cells;
    public int Image;

    public AppKitListViewRow(String text, int image)
    {
        Cells = new List<String>();
        Cells.Add(text);
        Image = image;
    }
}

public class AppKitListViewPeer : AppKitTablePeer, IListViewPeer
{
    List<AppKitListViewRow> _rows;
    List<NSTableColumn> _columns;
    List<NSTextAlignment> _alignments;
    /// Whether the one column is the table's own, made for rows added before
    /// any column was: a list in the `List` style has none of its own.
    bool _implicit;
    NSTableHeaderView? _header;
    AppKitImageListBackend? _images;

    public AppKitListViewPeer(IControlNotify owner)
    {
        _rows = new List<AppKitListViewRow>();
        _columns = new List<NSTableColumn>();
        _alignments = new List<NSTextAlignment>();
        _implicit = false;
        _images = null;
        base(owner, true);
        _header = Table.HeaderView;
    }

    public override int RowCount => (int)_rows.Count;

    int FindColumn(NSTableColumn? column)
    {
        if (column == null)
            return -1;
        for (nuint i = 0u; i < _columns.Count; i++)
        {
            if (_columns[i] == (NSTableColumn)column)
                return (int)i;
        }
        return -1;
    }

    /// The picture goes in the first column only, as every details list puts it.
    public override NSView? CreateCell(NSTableColumn? column, int row)
    {
        int index = FindColumn(column);
        if (row < 0 || row >= RowCount || index < 0)
            return null;
        var shown = _rows[(nuint)row];
        String text = (nuint)index < shown.Cells.Count ? shown.Cells[(nuint)index] : "";
        NSImage? picture = index == 0 ? FindListPicture(_images, shown.Image) : null;
        var images = _images;
        var size = images == null ? CreateSize(0, 0) : ((AppKitImageListBackend)images).ImageSize;
        return CreateCellView(_columns[(nuint)index].Width, Table.RowHeight, Style, null, picture, size, text,
                              _alignments[(nuint)index]);
    }

    /// **Only `Details` shows its headings**; the icon styles show as a list,
    /// as on GTK and for the same reason: AppKit's icons are a collection
    /// view, which is not a table.
    public void SetStyle(ListViewStyle style) => Table.HeaderView = style == ListViewStyle.Details ? _header : null;

    public int AddColumn(String text, int width, HorizontalAlignment alignment)
    {
        if (_implicit)
        {
            _implicit = false;
            var column = _columns[0u];
            column.Title = ToNSString(text);
            column.Width = (double)width;
            column.HeaderCell.Alignment = ToNSTextAlignment(alignment);
            _alignments[0u] = ToNSTextAlignment(alignment);
            ReloadRows();
            return 0;
        }
        int index = (int)_columns.Count;
        var made = CreateTableColumn(index, text, width);
        made.HeaderCell.Alignment = ToNSTextAlignment(alignment);
        Table.AddTableColumn(made);
        _columns.Add(made);
        _alignments.Add(ToNSTextAlignment(alignment));
        return index;
    }

    public void SetColumnWidth(int column, int width)
    {
        if (column >= 0 && (nuint)column < _columns.Count)
            _columns[(nuint)column].Width = (double)width;
    }

    public int AddRow(String text, int image)
    {
        if (_columns.Count == 0u)
        {
            AddColumn("", RoundToInt(View.Bounds.size.width), HorizontalAlignment.Left);
            _implicit = true;
        }
        _rows.Add(new AppKitListViewRow(text, image));
        ReloadRows();
        return RowCount - 1;
    }

    public void SetCell(int row, int column, String text)
    {
        if (row < 0 || row >= RowCount || column < 0)
            return;
        var cells = _rows[(nuint)row].Cells;
        while (cells.Count <= (nuint)column)
            cells.Add("");
        cells[(nuint)column] = text;
        ReloadRows();
    }

    public String GetCell(int row, int column)
    {
        if (row < 0 || row >= RowCount || column < 0)
            return "";
        var cells = _rows[(nuint)row].Cells;
        return (nuint)column < cells.Count ? cells[(nuint)column] : "";
    }

    public void RemoveRow(int row)
    {
        if (row < 0 || row >= RowCount)
            return;
        int was = SelectedRow;
        _rows.RemoveAt((nuint)row);
        ReloadRows();
        SelectAfterRemove(was, row);
    }

    public void Clear()
    {
        _rows.Clear();
        ReloadRows();
        SelectRow(-1);
    }

    public int GetSelectedRow() => SelectedRow;
    public void SetSelectedRow(int row) => SelectRow(row);

    public void SetImages(IImageListBackend? images)
    {
        _images = images == null ? null : (AppKitImageListBackend)images;
        ReloadRows();
    }

    /// **An AppKit row is always selected whole**, as a GTK one is. The grid
    /// lines are real.
    public void SetFullRowSelect(bool full, bool gridLines) =>
        Table.GridStyleMask = gridLines
            ? NSTableViewGridLineStyle.SolidVerticalGridLineMask | NSTableViewGridLineStyle.SolidHorizontalGridLineMask
            : NSTableViewGridLineStyle.GridNone;
}

// ================================================================== a tree

/// A node handle: the number the peer gave the node.
public class AppKitTreeNode : ITreeNodeHandle
{
    nuint _id;
    public AppKitTreeNode(nuint id) => _id = id;
    public nuint Id => _id;
}

/// One node: the item the outline view knows it by, where it is, and what it
/// shows.
public class AppKitTreeRecord
{
    public FormsTreeItem Item;
    /// Zero for a root.
    public nuint Parent;
    public String Text;
    public int Image;
    public List<nuint> Children;

    public AppKitTreeRecord(nuint id, nuint parent, String text, int image)
    {
        Item = FormsTreeItem.Alloc().Init()!;
        Item.Id = id;
        Parent = parent;
        Text = text;
        Image = image;
        Children = new List<nuint>();
    }
}

public class AppKitTreePeer : AppKitPeer, ITreeViewPeer
{
    FormsOutlineView _outline;
    NSTableColumn _column;
    FormsTreeSource _source;
    FormsTarget _relay;
    AppKitCellStyle _style;
    Dictionary<nuint, AppKitTreeRecord> _nodes;
    List<nuint> _roots;
    nuint _nextId;
    AppKitImageListBackend? _images;
    bool _quiet;

    public AppKitTreePeer(IControlNotify owner)
    {
        _outline = FormsOutlineView.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 120.0, 80.0));
        _style = new AppKitCellStyle();
        _outline.RowHeight = _style.RowHeight;
        _column = CreateTableColumn(0, "", 100);
        _column.ResizingMask = NSTableColumnResizingOptions.AutoresizingMask;
        _outline.AddTableColumn(_column);
        _outline.OutlineTableColumn = _column;
        _outline.HeaderView = null;
        _outline.ColumnAutoresizingStyle = NSTableViewColumnAutoresizingStyle.LastColumnOnlyAutoresizingStyle;
        _nodes = new Dictionary<nuint, AppKitTreeRecord>();
        _roots = new List<nuint>();
        _nextId = 1u;
        _images = null;
        _quiet = false;
        _source = FormsTreeSource.Alloc().Init()!;
        _relay = FormsTarget.Alloc().Init()!;
        _outline.Target = _relay;
        _outline.DoubleAction = Selector.Named("act:");
        base(CreateTableScroller(_outline, true), owner);

        _outline.Peer = this;
        _source.Peer = this;
        _relay.Peer = this;
        _outline.DataSource = _source;
        _outline.Delegate = _source;
    }

    protected override void ForgetReporters()
    {
        base.ForgetReporters();
        _outline.Peer = null;
        _source.Peer = null;
        _relay.Peer = null;
    }

    protected override NSView FocusView => _outline;

    // ------------------------------------------------------------ the source

    AppKitTreeRecord? FindRecord(nuint id)
    {
        var found = _nodes.TryGetValue(id);
        if (found is Some held)
            return held.Value;
        return null;
    }

    AppKitTreeRecord? FindItemRecord(AnyObject? item)
    {
        if (item is FormsTreeItem node)
            return FindRecord(node.Id);
        return null;
    }

    /// The children of the node `item` names, or the roots for none.
    List<nuint> FindSiblings(nuint parent)
    {
        if (FindRecord(parent) is AppKitTreeRecord record)
            return record.Children;
        return _roots;
    }

    public int CountChildren(AnyObject? item)
    {
        if (item == null)
            return (int)_roots.Count;
        if (FindItemRecord(item) is AppKitTreeRecord record)
            return (int)record.Children.Count;
        return 0;
    }

    public FormsTreeItem? FindChild(AnyObject? item, int index)
    {
        var siblings = _roots;
        if (item != null)
        {
            var record = FindItemRecord(item);
            if (record == null)
                return null;
            siblings = ((AppKitTreeRecord)record).Children;
        }
        if (index < 0 || (nuint)index >= siblings.Count)
            return null;
        if (FindRecord(siblings[(nuint)index]) is AppKitTreeRecord child)
            return child.Item;
        return null;
    }

    public NSView? CreateCell(AnyObject item)
    {
        var record = FindItemRecord(item);
        if (record == null)
            return null;
        var shown = (AppKitTreeRecord)record;
        var images = _images;
        var size = images == null ? CreateSize(0, 0) : ((AppKitImageListBackend)images).ImageSize;
        return CreateCellView(_column.Width, _outline.RowHeight, _style, null, FindListPicture(_images, shown.Image),
                              size, shown.Text, NSTextAlignment.Left);
    }

    public void ReportSelection()
    {
        if (_quiet)
            return;
        var owner = Owner;
        if (owner != null)
            ((IControlNotify)owner).OnPlatformValueChanged();
    }

    public override void ReportAction()
    {
        var owner = Owner;
        if (owner != null && _outline.ClickedRow >= (NSInteger)0)
            ((IControlNotify)owner).OnPlatformActivated();
    }

    void RunQuietly(Action change)
    {
        bool was = _quiet;
        _quiet = true;
        change();
        _quiet = was;
    }

    /// The children of one node read again, or every node for a root.
    void ReloadChildren(nuint parent)
    {
        RunQuietly(() =>
        {
            if (FindRecord(parent) is AppKitTreeRecord record)
                _outline.ReloadItemReloadChildren(record.Item, true);
            else
                _outline.ReloadData();
        });
    }

    // ------------------------------------------------------------ ITreeViewPeer

    public ITreeNodeHandle AddNode(ITreeNodeHandle? parent, ITreeNodeHandle? previous, String text, int image)
    {
        nuint under = 0u;
        if (parent != null && FindRecord(((ITreeNodeHandle)parent).Id) != null)
            under = ((ITreeNodeHandle)parent).Id;
        var siblings = FindSiblings(under);

        nuint at = siblings.Count;
        if (previous != null)
        {
            nuint after = ((ITreeNodeHandle)previous).Id;
            for (nuint i = 0u; i < siblings.Count; i++)
            {
                if (siblings[i] == after)
                    at = i + 1u;
            }
        }

        nuint id = _nextId;
        _nextId++;
        _nodes.Add(id, new AppKitTreeRecord(id, under, text, image));
        siblings.Insert(at, id);
        ReloadChildren(under);
        return new AppKitTreeNode(id);
    }

    /// **The node's descendants go with it.** Their records are kept until the
    /// view has been read again, since it does not hold the items it shows.
    public void RemoveNode(ITreeNodeHandle node)
    {
        var record = FindRecord(node.Id);
        if (record == null)
            return;
        nuint parent = ((AppKitTreeRecord)record).Parent;
        var siblings = FindSiblings(parent);
        for (nuint i = 0u; i < siblings.Count; i++)
        {
            if (siblings[i] == node.Id)
            {
                siblings.RemoveAt(i);
                break;
            }
        }
        var gone = new List<AppKitTreeRecord>();
        ForgetNode(node.Id, gone);
        ReloadChildren(parent);
        gone.Clear();
    }

    void ForgetNode(nuint id, List<AppKitTreeRecord> gone)
    {
        var record = FindRecord(id);
        if (record == null)
            return;
        var forgotten = (AppKitTreeRecord)record;
        gone.Add(forgotten);
        _nodes.Remove(id);
        foreach (var child in forgotten.Children)
            ForgetNode(child, gone);
    }

    public void SetNodeText(ITreeNodeHandle node, String text)
    {
        if (FindRecord(node.Id) is AppKitTreeRecord record)
        {
            record.Text = text;
            RunQuietly(() => { _outline.ReloadItem(record.Item); });
        }
    }

    public String GetNodeText(ITreeNodeHandle node)
    {
        if (FindRecord(node.Id) is AppKitTreeRecord record)
            return record.Text;
        return "";
    }

    public void SetNodeExpanded(ITreeNodeHandle node, bool expanded)
    {
        if (FindRecord(node.Id) is AppKitTreeRecord record)
        {
            if (expanded)
                _outline.ExpandItem(record.Item);
            else
                RunQuietly(() => { _outline.CollapseItem(record.Item); });
        }
    }

    /// The node's ancestors are expanded first, as a Win32 tree does, since a
    /// row that is not shown cannot be selected.
    public void SelectNode(ITreeNodeHandle node)
    {
        var record = FindRecord(node.Id);
        if (record == null)
            return;
        RevealNode(((AppKitTreeRecord)record).Parent);
        int row = (int)_outline.RowForItem(((AppKitTreeRecord)record).Item);
        if (row < 0)
            return;
        RunQuietly(() =>
        {
            _outline.SelectRowIndexesByExtendingSelection(NSIndexSet.IndexSetWithIndex((nuint)row), false);
            _outline.ScrollRowToVisible((NSInteger)row);
        });
    }

    void RevealNode(nuint id)
    {
        if (FindRecord(id) is AppKitTreeRecord record)
        {
            RevealNode(record.Parent);
            _outline.ExpandItem(record.Item);
        }
    }

    ITreeNodeHandle? FindRowHandle(NSInteger row)
    {
        if (row < (NSInteger)0)
            return null;
        if (_outline.ItemAtRow(row) is FormsTreeItem item)
            return new AppKitTreeNode(item.Id);
        return null;
    }

    public ITreeNodeHandle? GetSelectedNode() => FindRowHandle(_outline.SelectedRow);

    /// `at` is where the outline view reported the press, in its own
    /// coordinates, which are the rows'.
    public ITreeNodeHandle? GetNodeAt(Forms.Drawing.Point at)
    {
        NSPoint point;
        point.x = (double)at.X;
        point.y = (double)at.Y;
        return FindRowHandle(_outline.RowAtPoint(point));
    }

    public void Clear()
    {
        var gone = new List<AppKitTreeRecord>();
        foreach (var pair in _nodes)
            gone.Add(pair.Value);
        _nodes.Clear();
        _roots.Clear();
        RunQuietly(() =>
        {
            _outline.ReloadData();
            _outline.DeselectAll(null);
        });
        gone.Clear();
    }

    public void SetImages(IImageListBackend? images)
    {
        _images = images == null ? null : (AppKitImageListBackend)images;
        RunQuietly(() => { _outline.ReloadData(); });
    }

    // ------------------------------------------------------------ IControlPeer

    public override void SetBounds(FRect bounds)
    {
        base.SetBounds(bounds);
        _outline.SizeLastColumnToFit();
    }

    public override void SetFont(Forms.Drawing.Font font)
    {
        _style.Font = ((AppKitFontBackend)font.Resource).Font;
        _outline.RowHeight = _style.RowHeight;
        RunQuietly(() => { _outline.ReloadData(); });
    }

    public override void SetForeColor(Color color)
    {
        _style.SetForeColor(color);
        RunQuietly(() => { _outline.ReloadData(); });
    }

    public override void SetBackColor(Color color)
    {
        if (!color.Equals(FromNSColor(NSColor.TextBackgroundColor)))
            _outline.BackgroundColor = ToNSColor(color);
    }

    public override void SetEnabled(bool enabled) => _outline.Enabled = enabled;

    public override bool AcceptsTabFocus => !View.Hidden && _outline.Enabled;
}

// ================================================================ combo box

/// What an editable combo box tells its peer: the user chose from the list.
public objc class FormsComboDelegate : NSObject, NSComboBoxDelegate
{
    public weak AppKitComboPeer? Peer;

    public void ComboBoxSelectionDidChange(NSNotification notification)
    {
        AppKitComboPeer? peer = Peer;
        if (peer != null)
            ((AppKitComboPeer)peer).ReportAction();
    }
}

/// A combo box: an `NSPopUpButton` to choose from, or an `NSComboBox` that
/// takes typing too, as the LCL's `TCocoaReadOnlyComboBox` and `TCocoaComboBox`.
///
/// **Being editable changes the class**, as masking a text box does, so
/// `SetEditable` puts the other kind where this one was with the items, the
/// choice and the settings carried across.
///
/// **A pop-up button's items are menu items**, inserted into its menu rather
/// than through `insertItemWithTitle:atIndex:`, which removes any item of the
/// same title first -- and a list may hold the same text twice.
public class AppKitComboPeer : AppKitControlPeer, IComboPeer
{
    List<String> _items;
    bool _editable;
    /// The choice last reported or made, so that AppKit's report of a choice
    /// that did not change is not passed on.
    int _chosen;
    /// Whether the program is changing the items or the choice, which AppKit
    /// reports as it happens: removing a combo box's items is a selection.
    bool _quiet;
    FormsTarget _itemRelay;
    FormsComboDelegate _delegate;

    public AppKitComboPeer(IControlNotify owner)
    {
        _items = new List<String>();
        _editable = false;
        _chosen = -1;
        _quiet = false;
        _itemRelay = FormsTarget.Alloc().Init()!;
        _delegate = FormsComboDelegate.Alloc().Init()!;
        base(CreateComboView(false), owner);
        _itemRelay.Peer = this;
        _delegate.Peer = this;
        ListenForAction();
    }

    static NSControl CreateComboView(bool editable)
    {
        if (editable)
        {
            var box = NSComboBox.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 120.0, 24.0));
            box.Completes = true;
            box.UsesDataSource = false;
            return box;
        }
        return NSPopUpButton.Alloc().InitWithFramePullsDown(MakeNSRect(0.0, 0.0, 120.0, 24.0), false);
    }

    protected override void ForgetReporters()
    {
        base.ForgetReporters();
        _itemRelay.Peer = null;
        _delegate.Peer = null;
    }

    public override void ReportAction()
    {
        int now = GetSelectedIndex();
        if (_quiet || now == _chosen)
            return;
        _chosen = now;
        var owner = Owner;
        if (owner != null)
            ((IControlNotify)owner).OnPlatformValueChanged();
    }

    /// Every item put back from the list here, and the choice with them.
    void ApplyItems()
    {
        _quiet = true;
        if (Control is NSComboBox box)
        {
            box.RemoveAllItems();
            foreach (var item in _items)
                box.AddItemWithObjectValue(ToNSString(item));
        }
        else
        {
            var popup = (NSPopUpButton)Control;
            popup.RemoveAllItems();
            var menu = popup.Menu;
            for (nuint i = 0u; i < _items.Count && menu != null; i++)
            {
                var made = ((NSMenu)menu).InsertItemWithTitleActionKeyEquivalentAtIndex(
                    ToNSString(_items[i]), Selector.Named("act:"), ToNSString(""), (NSInteger)i);
                made.Target = _itemRelay;
            }
        }
        _quiet = false;
        ApplyChoice();
    }

    /// The choice here, shown.
    void ApplyChoice()
    {
        _quiet = true;
        if (Control is NSComboBox box)
        {
            if (_chosen >= 0)
                box.SelectItemAtIndex((NSInteger)_chosen);
            else if (box.IndexOfSelectedItem >= (NSInteger)0)
                box.DeselectItemAtIndex(box.IndexOfSelectedItem);
        }
        else
        {
            ((NSPopUpButton)Control).SelectItemAtIndex((NSInteger)_chosen);
        }
        _quiet = false;
    }

    public void InsertItem(int index, String text)
    {
        if (index < 0 || (nuint)index > _items.Count)
            return;
        int was = GetSelectedIndex();
        _items.Insert((nuint)index, text);
        _chosen = was >= index && was >= 0 ? was + 1 : was;
        ApplyItems();
    }

    public void RemoveItem(int index)
    {
        if (index < 0 || (nuint)index >= _items.Count)
            return;
        int was = GetSelectedIndex();
        _items.RemoveAt((nuint)index);
        _chosen = was == index ? -1 : was > index ? was - 1 : was;
        ApplyItems();
    }

    public void ClearItems()
    {
        _items.Clear();
        _chosen = -1;
        ApplyItems();
    }

    public int ItemCount => (int)_items.Count;

    public void SetSelectedIndex(int index)
    {
        _chosen = index < 0 || (nuint)index >= _items.Count ? -1 : index;
        ApplyChoice();
    }

    public int GetSelectedIndex()
    {
        if (Control is NSComboBox box)
            return (int)box.IndexOfSelectedItem;
        return (int)((NSPopUpButton)Control).IndexOfSelectedItem;
    }

    public override String GetText()
    {
        if (Control is NSComboBox box)
            return FromNSString(box.StringValue);
        var title = ((NSPopUpButton)Control).TitleOfSelectedItem;
        return title == null ? "" : FromNSString((NSString)title);
    }

    public override void SetText(String text)
    {
        if (Control is NSComboBox box)
            box.StringValue = ToNSString(text);
    }

    public void SetEditable(bool editable)
    {
        if (editable == _editable)
            return;
        _editable = editable;
        _chosen = GetSelectedIndex();

        var old = Control;
        var made = CreateComboView(editable);
        made.Frame = old.Frame;
        made.Font = old.Font;
        made.Enabled = old.Enabled;
        if (made is NSComboBox box)
            box.Delegate = _delegate;
        var parent = old.Superview;
        if (parent != null)
            ((NSView)parent).ReplaceSubviewWith(old, made);
        View = made;
        if (!editable)
            ListenForAction();
        ApplyItems();
    }

    public override bool AcceptsTabFocus => !View.Hidden && Control.Enabled;

    /// **A combo box is its own height**, at the top of the bounds, as on
    /// Windows, where the height asked for includes the list that drops down.
    public override void SetBounds(FRect bounds)
    {
        int tall = PreferredSize.Height;
        base.SetBounds(CreateRectangle(bounds.X, bounds.Y, bounds.Width, tall < bounds.Height ? tall : bounds.Height));
        LastBounds = bounds;
    }
}

#endif
