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

// The `comctl32` peers: toolbar, status bar, progress, slider, tabs, tree and
// list.
//
// Three things set these apart from the standard tier, and each shows up in
// every peer below.
//
// **They report through `WM_NOTIFY`.** A pointer to a structure whose first
// field says which longer structure it really is, so a peer recognises the code
// before it casts. `NotifiedBy` is where that happens.
//
// **They position themselves unless told not to.** A toolbar and a status bar
// read their parent's size and move to an edge on their own, which is exactly
// what a layout pass is for and exactly what must not happen underneath one.
// `CCS_NORESIZE | CCS_NOPARENTALIGN | CCS_NODIVIDER` turns it off, and every
// peer here that would otherwise wander carries all three.
//
// **They must be asked for.** `InitCommonControlsEx` registers the window
// classes; without it `CreateWindowExW` fails on a class name Windows has never
// heard of, and the failure looks like a control that silently did not appear.
module Forms.Platform.Win32;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;
#if WINDOWS
import Win32;
import Win32.Handles;
import Win32.Kernel32;
import Win32.User32;
import Win32.Gdi32;
import Win32.ComCtl32;

#pragma comment(lib, "comctl32")

/// The styles a common control needs so that the layout pass, rather than the
/// control, decides where it goes.
uint StaysPut() => CcsNoResize | CcsNoParentAlign | CcsNoDivider;

// ================================================================== toolbar

public class ToolBarPeer : ControlPeer, IToolBarPeer
{
    /// The command id of each button, in the order they were added, so that an
    /// index can be turned into an id and back.
    List<int> _commands;
    weak IControlNotify? owning;

    public ToolBarPeer(IControlNotify owner, IContainerPeer parent)
    {
        base(MakeChild("ToolbarWindow32", WindowOf(parent),
                       ChildStyle() | StaysPut() | TbStyleFlat | TbStyleList, 0u),
             owner, true);
        owning = owner;
        _commands = new List<int>();

        // Windows needs to be told how wide a `TBBUTTON` is before any is
        // added, because the structure grew between versions and this is how it
        // knows which one it has been handed.
        SendMessageW(window, TbButtonStructSize, (ulong)sizeof(ToolBarButton), 0);
        SendMessageW(window, TbSetMaxTextRows, 1u, 0);
    }

    public int AddButton(String text, int image, ToolButtonKind kind)
    {
        ToolBarButton button;
        button.Bitmap = image;
        button.Command = NewCommandId();
        button.State = TbStateEnabled;
        button.Style = BtnsButton;
        if (kind == ToolButtonKind.Separator)
        {
            button.Style = BtnsSeparator;
        }
        else if (kind == ToolButtonKind.Toggle)
        {
            button.Style = BtnsCheck;
        }
        if (kind != ToolButtonKind.Separator)
        {
            button.Style = (byte)(button.Style | BtnsAutoSize);
        }
        button.Reserved0 = 0u;
        button.Reserved1 = 0u;
        button.Reserved2 = 0u;
        button.Reserved3 = 0u;
        button.Reserved4 = 0u;
        button.Reserved5 = 0u;
        button.Data = 0u;

        // The caption is a pointer to text the toolbar reads while the message
        // runs, so the wide string has to outlive the call and no longer.
        var wide = text.ToUtf16();
        button.Text = (nuint)(void*)wide.ToPointer();

        SendMessageW(window, TbAddButtonsW, 1u, (long)(nuint)&button);
        _commands.Add(button.Command);
        return (int)_commands.Count - 1;
    }

    /// Which button a command id belongs to, or -1.
    int IndexOf(int command)
    {
        for (nuint i = 0u; i < _commands.Count; i++)
        {
            if (_commands[i] == command)
                return (int)i;
        }
        return -1;
    }

    int CommandAt(int index)
    {
        if (index < 0 || (nuint)index >= _commands.Count)
            return -1;
        return _commands[(nuint)index];
    }

    /// A toolbar's buttons all report through the toolbar's own window, so the
    /// notification says *which* button in its low word rather than naming a
    /// control of its own.
    protected override bool Notified(uint code, int id)
    {
        int at = IndexOf(id);
        if (at < 0)
            return false;
        IControlNotify? held = owning;
        if (held == null)
            return false;
        ((IControlNotify)held).OnPlatformToolClicked(at);
        return true;
    }

    public nuint ButtonId(int index)
    {
        int command = CommandAt(index);
        if (command < 0)
            return 0u;
        return (nuint)command;
    }

    public void SetButtonEnabled(int index, bool enabled)
    {
        int command = CommandAt(index);
        if (command < 0)
            return;
        SendMessageW(window, TbEnableButton, (ulong)command, (long)(enabled ? 1 : 0));
    }

    public void SetButtonChecked(int index, bool checked)
    {
        int command = CommandAt(index);
        if (command < 0)
            return;
        SendMessageW(window, TbCheckButton, (ulong)command, (long)(checked ? 1 : 0));
    }

    public bool GetButtonChecked(int index)
    {
        int command = CommandAt(index);
        if (command < 0)
            return false;
        return SendMessageW(window, TbIsButtonChecked, (ulong)command, 0) != 0;
    }

    public void SetImages(IImageListBackend images)
    {
        SendMessageW(window, TbSetImageList, 0u, (long)(nuint)images.Handle);
    }

    /// `TBSTYLE_LIST` puts the caption beside the picture; without it there is
    /// room for one or the other. A creation-time style, so this re-sets it and
    /// asks the bar to lay itself out again.
    public void SetTextVisible(bool visible)
    {
        long style = Win32.User32.GetWindowLongPtrW(window, GwlStyle);
        if (visible)
        {
            style = style | (long)TbStyleList;
        }
        else
        {
            style = style & ~(long)TbStyleList;
        }
        Win32.User32.SetWindowLongPtrW(window, GwlStyle, style);
        ResizeToFit();
    }

    public void ResizeToFit() => SendMessageW(window, TbAutoSize, 0u, 0);

    /// As tall as the bar makes itself, and as wide as it is given.
    public override FSize PreferredSize
    {
        get
        {
            long packed = SendMessageW(window, TbGetButtonSize, 0u, 0);
            int height = (int)((packed >> 16) & 0xFFFFu);
            if (height <= 0)
                height = 24;
            return Extent(0, height + 8);
        }
    }
}

// =============================================================== status bar

public class StatusBarPeer : ControlPeer, IStatusBarPeer
{
    public StatusBarPeer(IControlNotify owner, IContainerPeer parent)
    {
        base(MakeChild("msctls_statusbar32", WindowOf(parent),
                       (ChildStyle() & ~WsTabStop) | StaysPut(), 0u),
             owner, true);
    }

    public void SetPanels(int[] edges)
    {
        if (edges.Length == 0u)
            return;
        SendMessageW(window, SbSetParts, (ulong)edges.Length, (long)(nuint)&edges[0u]);
    }

    public void SetPanelText(int index, String text)
    {
        SendMessageW(window, SbSetTextW, (ulong)index,
                     (long)(nuint)text.ToUtf16().ToPointer());
    }

    /// A status bar decides its own height from the font, and is right about it.
    public override FSize PreferredSize
    {
        get
        {
            Rect frame;
            GetWindowRect(window, &frame);
            int height = frame.Bottom - frame.Top;
            if (height <= 0)
                height = 22;
            return Extent(0, height);
        }
    }
}

// ============================================================= progress bar

public class ProgressPeer : ControlPeer, IProgressPeer
{
    public ProgressPeer(IControlNotify owner, IContainerPeer parent)
    {
        base(MakeChild("msctls_progress32", WindowOf(parent),
                       (ChildStyle() & ~WsTabStop) | PbsSmooth, 0u),
             owner, true);
        SendMessageW(window, PbmSetRange32, 0u, 100);
    }

    public void SetRange(int minimum, int maximum)
    {
        SendMessageW(window, PbmSetRange32, (ulong)minimum, (long)maximum);
    }

    public void SetValue(int value)
    {
        SendMessageW(window, PbmSetPos, (ulong)value, 0);
    }

    public int GetValue() => (int)SendMessageW(window, PbmGetPos, 0u, 0);

    /// A bar with no value that simply moves. The style is read at creation, so
    /// it is set here and the marquee then started or stopped -- which is why
    /// this is two calls rather than one.
    public void SetIndeterminate(bool indeterminate)
    {
        long style = Win32.User32.GetWindowLongPtrW(window, GwlStyle);
        if (indeterminate)
        {
            style = style | (long)PbsMarquee;
        }
        else
        {
            style = style & ~(long)PbsMarquee;
        }
        Win32.User32.SetWindowLongPtrW(window, GwlStyle, style);
        SendMessageW(window, PbmSetMarquee, (ulong)(indeterminate ? 1 : 0), 30);
    }
}

// ================================================================ track bar

public class TrackBarPeer : ControlPeer, ITrackBarPeer
{
    weak IControlNotify? owning;

    public TrackBarPeer(IControlNotify owner, IContainerPeer parent, bool vertical)
    {
        base(MakeChild("msctls_trackbar32", WindowOf(parent),
                       ChildStyle() | TbsAutoTicks
                                    | (vertical ? TbsVertical : TbsHorizontal), 0u),
             owner, true);
        owning = owner;
        SendMessageW(window, TbmSetRange, 1u, (long)((100 << 16) | 0));
    }

    public void SetRange(int minimum, int maximum)
    {
        SendMessageW(window, TbmSetRangeMin, 1u, (long)minimum);
        SendMessageW(window, TbmSetRangeMax, 1u, (long)maximum);
    }

    public void SetValue(int value)
    {
        SendMessageW(window, TbmSetPos, 1u, (long)value);
    }

    public int GetValue() => (int)SendMessageW(window, TbmGetPos, 0u, 0);

    public void SetTickFrequency(int every)
    {
        SendMessageW(window, TbmSetTicFreq, (ulong)every, 0);
    }

    /// The slider moved. Like a scroll bar, it tells its *parent* rather than
    /// itself, so the parent hands it back here.
    public void Scrolled()
    {
        IControlNotify? held = owning;
        if (held == null)
            return;
        ((IControlNotify)held).OnPlatformValueChanged();
    }
}

// ============================================================== tab control

public class TabControlPeer : ControlPeer, ITabControlPeer
{
    weak IControlNotify? owning;
    int _tabs;

    public TabControlPeer(IControlNotify owner, IContainerPeer parent)
    {
        base(MakeChild("SysTabControl32", WindowOf(parent),
                       ChildStyle() | WsClipChildren, 0u),
             owner, true);
        owning = owner;
        _tabs = 0;
    }

    /// A tab control is a container, so a page's controls are children of it.
    public void AddChild(IControlPeer child)
    {
        SetParent((HWND)(void*)child.Handle, window);
    }

    public void RemoveChild(IControlPeer child)
    {
        SetParent((HWND)(void*)child.Handle, null);
    }

    public int AddTab(String text, int image)
    {
        TabItem item;
        item.Mask = TcifText;
        item.State = 0u;
        item.StateMask = 0u;
        var wide = text.ToUtf16();
        item.Text = wide.ToPointer();
        item.TextLength = 0;
        item.Image = -1;
        item.Param = 0u;
        if (image >= 0)
        {
            item.Mask = item.Mask | TcifImage;
            item.Image = image;
        }

        int at = (int)SendMessageW(window, TcmInsertItemW, (ulong)_tabs,
                                   (long)(nuint)&item);
        _tabs = _tabs + 1;
        return at;
    }

    public void RemoveTab(int index)
    {
        SendMessageW(window, TcmDeleteItem, (ulong)index, 0);
        if (_tabs > 0)
            _tabs = _tabs - 1;
    }

    public void SetTabText(int index, String text)
    {
        TabItem item;
        item.Mask = TcifText;
        item.State = 0u;
        item.StateMask = 0u;
        var wide = text.ToUtf16();
        item.Text = wide.ToPointer();
        item.TextLength = 0;
        item.Image = -1;
        item.Param = 0u;
        SendMessageW(window, TcmSetItemW, (ulong)index, (long)(nuint)&item);
    }

    public void SetSelectedTab(int index)
    {
        SendMessageW(window, TcmSetCurSel, (ulong)index, 0);
    }

    public int GetSelectedTab()
    {
        return (int)SendMessageW(window, TcmGetCurSel, 0u, 0);
    }

    public int TabCount
    {
        get
        {
            return (int)SendMessageW(window, TcmGetItemCount, 0u, 0);
        }
    }

    /// The area under the tabs, which is what a page gets.
    ///
    /// `TCM_ADJUSTRECT` converts between the whole control and the part inside,
    /// and is the only thing that knows how tall a row of tabs is -- which
    /// depends on the font, the theme and how many rows the tabs wrapped on to.
    public FRect PageArea
    {
        get
        {
            Rect area;
            GetClientRect(window, &area);
            SendMessageW(window, TcmAdjustRect, 0u, (long)(nuint)&area);
            return Area(area.Left, area.Top, area.Right - area.Left, area.Bottom - area.Top);
        }
    }

    public void SetImages(IImageListBackend images)
    {
        SendMessageW(window, TcmSetImageList, 0u, (long)(nuint)images.Handle);
    }

    protected override bool NotifiedBy(int code, void* raw)
    {
        if (code != TcnSelChange)
            return false;
        IControlNotify? held = owning;
        if (held == null)
            return false;
        ((IControlNotify)held).OnPlatformValueChanged();
        return true;
    }
}

// ================================================================ tree view

/// A place in a tree. A class rather than the raw `HTREEITEM`, because the seam
/// must not name a Windows type -- and because a handle wrapped in an object is
/// something the control layer can hold in a list.
public class TreeNodeHandle : ITreeNodeHandle
{
    HTREEITEM _item;
    public TreeNodeHandle(HTREEITEM handle) => _item = handle;
    public HTREEITEM Native => _item;
    public nuint Id => (nuint)(void*)_item;
}

public class TreeViewPeer : ControlPeer, ITreeViewPeer
{
    weak IControlNotify? owning;

    public TreeViewPeer(IControlNotify owner, IContainerPeer parent)
    {
        base(MakeChild("SysTreeView32", WindowOf(parent),
                       ChildStyle() | TvsHasButtons | TvsHasLines
                                    | TvsLinesAtRoot | TvsShowSelAlways,
                       WsExClientEdge),
             owner, true);
        owning = owner;
    }

    public ITreeNodeHandle AddNode(ITreeNodeHandle? parent, ITreeNodeHandle? previous,
                                   String text, int image)
    {
        TreeInsert insert;
        insert.Parent = TreeRoot();
        insert.InsertAfter = TreeLast();

        if (parent != null)
        {
            ITreeNodeHandle above = (ITreeNodeHandle)parent;
            if (above is TreeNodeHandle real)
                insert.Parent = real.Native;
        }
        if (previous != null)
        {
            ITreeNodeHandle before = (ITreeNodeHandle)previous;
            if (before is TreeNodeHandle real)
                insert.InsertAfter = real.Native;
        }

        var wide = text.ToUtf16();
        insert.Item.Mask = TvifText;
        insert.Item.Item = null;
        insert.Item.State = 0u;
        insert.Item.StateMask = 0u;
        insert.Item.Text = wide.ToPointer();
        insert.Item.TextLength = 0;
        insert.Item.Image = -1;
        insert.Item.SelectedImage = -1;
        insert.Item.Children = 0;
        insert.Item.Param = 0u;
        if (image >= 0)
        {
            insert.Item.Mask = insert.Item.Mask | TvifImage | TvifSelectedImage;
            insert.Item.Image = image;
            insert.Item.SelectedImage = image;
        }

        long made = SendMessageW(window, TvmInsertItemW, 0u, (long)(nuint)&insert);
        return new TreeNodeHandle((HTREEITEM)(void*)(nuint)made);
    }

    HTREEITEM NativeOf(ITreeNodeHandle node)
    {
        if (node is TreeNodeHandle real)
            return real.Native;
        return null;
    }

    public void RemoveNode(ITreeNodeHandle node)
    {
        SendMessageW(window, TvmDeleteItem, 0u, (long)(nuint)(void*)NativeOf(node));
    }

    public void SetNodeText(ITreeNodeHandle node, String text)
    {
        TreeItem item;
        var wide = text.ToUtf16();
        item.Mask = TvifText | TvifHandle;
        item.Item = NativeOf(node);
        item.State = 0u;
        item.StateMask = 0u;
        item.Text = wide.ToPointer();
        item.TextLength = 0;
        item.Image = -1;
        item.SelectedImage = -1;
        item.Children = 0;
        item.Param = 0u;
        SendMessageW(window, TvmSetItemW, 0u, (long)(nuint)&item);
    }

    public String GetNodeText(ITreeNodeHandle node)
    {
        var buffer = new char16[512u];
        TreeItem item;
        item.Mask = TvifText | TvifHandle;
        item.Item = NativeOf(node);
        item.State = 0u;
        item.StateMask = 0u;
        item.Text = &buffer[0u];
        item.TextLength = 512;
        item.Image = 0;
        item.SelectedImage = 0;
        item.Children = 0;
        item.Param = 0u;
        if (SendMessageW(window, TvmGetItemW, 0u, (long)(nuint)&item) == 0)
            return "";
        return Text.FromNullTerminatedUtf16(&buffer[0u]);
    }

    public void Expand(ITreeNodeHandle node, bool expanded)
    {
        SendMessageW(window, TvmExpand, expanded ? TveExpand : TveCollapse,
                     (long)(nuint)(void*)NativeOf(node));
    }

    public void SelectNode(ITreeNodeHandle node)
    {
        SendMessageW(window, TvmSelectItem, TvgnCaret,
                     (long)(nuint)(void*)NativeOf(node));
    }

    public ITreeNodeHandle? GetSelectedNode()
    {
        long chosen = SendMessageW(window, TvmGetNextItem, TvgnCaret, 0);
        if (chosen == 0)
            return null;
        return new TreeNodeHandle((HTREEITEM)(void*)(nuint)chosen);
    }

    public ITreeNodeHandle? NodeAt(Forms.Drawing.Point at)
    {
        TreeHitTest probe;
        probe.At.X = at.X;
        probe.At.Y = at.Y;
        probe.Flags = 0u;
        probe.Item = null;

        // The item comes back in the structure rather than in the return
        // value, and it is filled even for a hit on the expand button or the
        // indent -- so the flags decide, not whether `Item` is set.
        SendMessageW(window, TvmHitTest, 0u, (long)(nuint)&probe);

        if ((probe.Flags & TvhtOnItem) == 0u)
            return null;
        if (probe.Item == null)
            return null;
        return new TreeNodeHandle(probe.Item);
    }

    public void Clear()
    {
        SendMessageW(window, TvmDeleteItem, 0u, (long)(nuint)(void*)TreeRoot());
    }

    public void SetImages(IImageListBackend images)
    {
        SendMessageW(window, TvmSetImageList, 0u, (long)(nuint)images.Handle);
    }

    protected override bool NotifiedBy(int code, void* raw)
    {
        if (code != TvnSelChangedW)
            return false;
        IControlNotify? held = owning;
        if (held == null)
            return false;
        ((IControlNotify)held).OnPlatformValueChanged();
        return true;
    }
}

// ================================================================ list view

public class ListViewPeer : ControlPeer, IListViewPeer
{
    weak IControlNotify? owning;
    int _columns;
    int _rows;

    public ListViewPeer(IControlNotify owner, IContainerPeer parent)
    {
        base(MakeChild("SysListView32", WindowOf(parent),
                       ChildStyle() | LvsReport | LvsShowSelAlways,
                       WsExClientEdge),
             owner, true);
        owning = owner;
        _columns = 0;
        _rows = 0;
    }

    public void SetStyle(ListViewStyle style)
    {
        long was = Win32.User32.GetWindowLongPtrW(window, GwlStyle);
        was = was & ~(long)(LvsReport | LvsList | LvsSmallIcon | LvsIcon);
        if (style == ListViewStyle.Details)
        {
            was = was | (long)LvsReport;
        }
        else if (style == ListViewStyle.List)
        {
            was = was | (long)LvsList;
        }
        else if (style == ListViewStyle.SmallIcon)
        {
            was = was | (long)LvsSmallIcon;
        }
        Win32.User32.SetWindowLongPtrW(window, GwlStyle, was);
        Invalidate();
    }

    public int AddColumn(String text, int width, HorizontalAlignment alignment)
    {
        ListColumn column;
        var wide = text.ToUtf16();
        column.Mask = LvcfText | LvcfWidth | LvcfSubItem | LvcfFormat;
        column.Format = LvcfmtLeft;
        if (alignment == HorizontalAlignment.Right)
        {
            column.Format = LvcfmtRight;
        }
        else if (alignment == HorizontalAlignment.Center)
        {
            column.Format = LvcfmtCenter;
        }
        column.Width = width;
        column.Text = wide.ToPointer();
        column.TextLength = 0;
        column.SubItem = _columns;
        column.Image = 0;
        column.Order = 0;

        int at = (int)SendMessageW(window, LvmInsertColumnW, (ulong)_columns,
                                   (long)(nuint)&column);
        _columns = _columns + 1;
        return at;
    }

    public void SetColumnWidth(int column, int width)
    {
        SendMessageW(window, LvmSetColumnWidth, (ulong)column, (long)width);
    }

    public int AddRow(String text, int image)
    {
        ListItem item;
        var wide = text.ToUtf16();
        item.Mask = LvifText;
        item.Item = _rows;
        item.SubItem = 0;
        item.State = 0u;
        item.StateMask = 0u;
        item.Text = wide.ToPointer();
        item.TextLength = 0;
        item.Image = -1;
        item.Param = 0u;
        item.Indent = 0;
        item.GroupId = 0;
        item.Columns = 0u;
        item.ColumnFormat = null;
        if (image >= 0)
        {
            item.Mask = item.Mask | LvifImage;
            item.Image = image;
        }

        int at = (int)SendMessageW(window, LvmInsertItemW, 0u, (long)(nuint)&item);
        if (at >= 0)
            _rows = _rows + 1;
        return at;
    }

    /// A cell other than the first, which Windows calls a sub-item and which is
    /// set rather than inserted -- column zero is the row itself.
    public void SetCell(int row, int column, String text)
    {
        ListItem item;
        var wide = text.ToUtf16();
        item.Mask = LvifText;
        item.Item = row;
        item.SubItem = column;
        item.State = 0u;
        item.StateMask = 0u;
        item.Text = wide.ToPointer();
        item.TextLength = 0;
        item.Image = 0;
        item.Param = 0u;
        item.Indent = 0;
        item.GroupId = 0;
        item.Columns = 0u;
        item.ColumnFormat = null;
        SendMessageW(window, LvmSetItemW, 0u, (long)(nuint)&item);
    }

    public String GetCell(int row, int column)
    {
        var buffer = new char16[512u];
        ListItem item;
        item.Mask = LvifText;
        item.Item = row;
        item.SubItem = column;
        item.State = 0u;
        item.StateMask = 0u;
        item.Text = &buffer[0u];
        item.TextLength = 512;
        item.Image = 0;
        item.Param = 0u;
        item.Indent = 0;
        item.GroupId = 0;
        item.Columns = 0u;
        item.ColumnFormat = null;
        SendMessageW(window, LvmGetItemW, 0u, (long)(nuint)&item);
        return Text.FromNullTerminatedUtf16(&buffer[0u]);
    }

    public void RemoveRow(int row)
    {
        if (SendMessageW(window, LvmDeleteItem, (ulong)row, 0) != 0 && _rows > 0)
        {
            _rows = _rows - 1;
        }
    }

    public void Clear()
    {
        SendMessageW(window, LvmDeleteAllItems, 0u, 0);
        _rows = 0;
    }

    public int RowCount => (int)SendMessageW(window, LvmGetItemCount, 0u, 0);

    public int GetSelectedRow()
    {
        return (int)SendMessageW(window, LvmGetNextItem, (ulong)(nuint)(nint)(-1),
                                 (long)LvniSelected);
    }

    public void SetSelectedRow(int row)
    {
        ListItem item;
        item.Mask = LvifState;
        item.Item = row;
        item.SubItem = 0;
        item.State = LvisSelected | LvisFocused;
        item.StateMask = LvisSelected | LvisFocused;
        item.Text = null;
        item.TextLength = 0;
        item.Image = 0;
        item.Param = 0u;
        item.Indent = 0;
        item.GroupId = 0;
        item.Columns = 0u;
        item.ColumnFormat = null;
        SendMessageW(window, LvmSetItemState, (ulong)row, (long)(nuint)&item);
        SendMessageW(window, LvmEnsureVisible, (ulong)row, 0);
    }

    public void SetImages(IImageListBackend images)
    {
        SendMessageW(window, LvmSetImageList, 1u, (long)(nuint)images.Handle);
    }

    public void SetFullRowSelect(bool full, bool gridLines)
    {
        uint wanted = 0u;
        if (full)
            wanted = wanted | LvsExFullRowSelect;
        if (gridLines)
            wanted = wanted | LvsExGridLines;
        SendMessageW(window, LvmSetExtendedStyle,
                     (ulong)(LvsExFullRowSelect | LvsExGridLines), (long)wanted);
    }

    /// `LVN_ITEMCHANGED` fires for every change to every row, including the one
    /// losing the selection -- so the state mask is checked, or a single click
    /// raises two changes.
    protected override bool NotifiedBy(int code, void* raw)
    {
        if (code != LvnItemChanged)
            return false;
        NotifyListView* details = (NotifyListView*)raw;
        if ((details->Changed & 0x0008u) == 0u)   // LVIF_STATE
            return false;
        if ((details->NewState & LvisSelected) == 0u)
            return false;
        IControlNotify? held = owning;
        if (held == null)
            return false;
        ((IControlNotify)held).OnPlatformValueChanged();
        return true;
    }
}

// ==================================================================== spin

/// An `EDIT` with an `msctls_updown32` glued to it.
///
/// **Two windows, not one.** Windows has no spin control: it has an up-down,
/// which is a pair of arrows that knows how to drive a *buddy* window. So this
/// makes both, tells the up-down which edit it belongs to, and lets it keep the
/// text in step -- `UDS_SETBUDDYINT` is what makes the edit show a number at
/// all, and without it the arrows move a value nothing displays.
public class SpinPeer : ControlPeer, ISpinPeer
{
    HWND _arrows;
    weak IControlNotify? owning;

    public SpinPeer(IControlNotify owner, IContainerPeer parent)
    {
        base(MakeChild("EDIT", WindowOf(parent),
                       ChildStyle() | EsAutoHScroll | EsRight, WsExClientEdge),
             owner, true);
        owning = owner;

        _arrows = MakeChild("msctls_updown32", WindowOf(parent),
                           ChildStyle() | UdsSetBuddyInt | UdsAlignRight
                                        | UdsArrowKeys | UdsAutoBuddy, 0u);
        SendMessageW(_arrows, UdmSetBuddy, (ulong)(nuint)(void*)window, 0);
        SetRange(0, 100);
    }

    ~SpinPeer()
    {
        if (_arrows != null)
        {
            DestroyWindow(_arrows);
            _arrows = null;
        }
    }

    public void SetRange(int minimum, int maximum)
    {
        SendMessageW(_arrows, UdmSetRange32, (ulong)minimum, (long)maximum);
    }

    public void SetValue(int value)
    {
        SendMessageW(_arrows, UdmSetPos32, 0u, (long)value);
    }

    public int GetValue()
    {
        return (int)SendMessageW(_arrows, UdmGetPos32, 0u, 0);
    }

    /// The edit reports its own changes, which is what makes typing a number
    /// count as well as clicking the arrows.
    protected override bool Notified(uint code, int id)
    {
        if (code != EnChange)
            return false;
        IControlNotify? held = owning;
        if (held == null)
            return false;
        ((IControlNotify)held).OnPlatformValueChanged();
        return true;
    }

    /// The arrows sit inside the edit's right-hand edge, so the pair is laid out
    /// as one control -- which is the whole illusion.
    public override void SetBounds(FRect bounds)
    {
        MoveWindow(window, bounds.X, bounds.Y, bounds.Width, bounds.Height, 1);
        // `UDM_SETBUDDY` re-docks the arrows against whatever the buddy now is.
        SendMessageW(_arrows, UdmSetBuddy, (ulong)(nuint)(void*)window, 0);
    }

    public override void SetVisible(bool visible)
    {
        ShowWindow(window, visible ? SwShowNoActivate : SwHide);
        ShowWindow(_arrows, visible ? SwShowNoActivate : SwHide);
    }
}

// ========================================================== check list box

/// A list whose items each have a tick.
///
/// **A list *view*, not a list box.** Windows has no checked list box; every
/// program that shows one uses a report-mode list view with
/// `LVS_EX_CHECKBOXES`, and the LCL owner-draws a list box instead. The list
/// view is the one that looks native and the one that already knows how to
/// report a tick.
public class CheckListPeer : ControlPeer, ICheckListPeer
{
    weak IControlNotify? owning;
    int _rows;

    public CheckListPeer(IControlNotify owner, IContainerPeer parent)
    {
        base(MakeChild("SysListView32", WindowOf(parent),
                       ChildStyle() | LvsReport | LvsShowSelAlways | LvsNoSortHeader,
                       WsExClientEdge),
             owner, true);
        owning = owner;
        _rows = 0;
        SendMessageW(window, LvmSetExtendedStyle,
                     (ulong)(LvsExCheckBoxes | LvsExFullRowSelect),
                     (long)(LvsExCheckBoxes | LvsExFullRowSelect));

        // One column: a report-mode list with no columns shows nothing at all,
        // which is the trap this control is otherwise. Its width follows the
        // control's in `SetBounds`, because a column wider than the list is a
        // horizontal scroll bar under a single column of text.
        ListColumn column;
        column.Mask = LvcfWidth | LvcfSubItem;
        column.Format = LvcfmtLeft;
        column.Width = 100;
        column.Text = null;
        column.TextLength = 0;
        column.SubItem = 0;
        column.Image = 0;
        column.Order = 0;
        SendMessageW(window, LvmInsertColumnW, 0u, (long)(nuint)&column);
    }

    /// The one column follows the control, so the text fills it and no
    /// horizontal scroll bar appears.
    public override void SetBounds(FRect bounds)
    {
        MoveWindow(window, bounds.X, bounds.Y, bounds.Width, bounds.Height, 1);
        Rect client;
        GetClientRect(window, &client);
        int width = client.Right - client.Left;
        if (width > 0)
        {
            SendMessageW(window, LvmSetColumnWidth, 0u, (long)width);
        }
    }

    public void InsertItem(int index, String text)
    {
        ListItem item;
        var wide = text.ToUtf16();
        item.Mask = LvifText;
        item.Item = index;
        item.SubItem = 0;
        item.State = 0u;
        item.StateMask = 0u;
        item.Text = wide.ToPointer();
        item.TextLength = 0;
        item.Image = 0;
        item.Param = 0u;
        item.Indent = 0;
        item.GroupId = 0;
        item.Columns = 0u;
        item.ColumnFormat = null;
        if (SendMessageW(window, LvmInsertItemW, 0u, (long)(nuint)&item) >= 0)
        {
            _rows = _rows + 1;
        }
    }

    public void RemoveItem(int index)
    {
        if (SendMessageW(window, LvmDeleteItem, (ulong)index, 0) != 0 && _rows > 0)
        {
            _rows = _rows - 1;
        }
    }

    public void ClearItems()
    {
        SendMessageW(window, LvmDeleteAllItems, 0u, 0);
        _rows = 0;
    }

    public int ItemCount => (int)SendMessageW(window, LvmGetItemCount, 0u, 0);

    public void SetSelectedIndex(int index)
    {
        ListItem item;
        item.Mask = LvifState;
        item.Item = index;
        item.SubItem = 0;
        item.State = LvisSelected | LvisFocused;
        item.StateMask = LvisSelected | LvisFocused;
        item.Text = null;
        item.TextLength = 0;
        item.Image = 0;
        item.Param = 0u;
        item.Indent = 0;
        item.GroupId = 0;
        item.Columns = 0u;
        item.ColumnFormat = null;
        SendMessageW(window, LvmSetItemState, (ulong)index, (long)(nuint)&item);
    }

    public int GetSelectedIndex()
    {
        return (int)SendMessageW(window, LvmGetNextItem, (ulong)(nuint)(nint)(-1),
                                 (long)LvniSelected);
    }

    /// The tick is the *state image*, one-based: 1 is empty and 2 is ticked.
    public void SetItemChecked(int index, bool checked)
    {
        ListItem item;
        item.Mask = LvifState;
        item.Item = index;
        item.SubItem = 0;
        item.State = CheckedState(checked);
        item.StateMask = LvisStateImageMask;
        item.Text = null;
        item.TextLength = 0;
        item.Image = 0;
        item.Param = 0u;
        item.Indent = 0;
        item.GroupId = 0;
        item.Columns = 0u;
        item.ColumnFormat = null;
        SendMessageW(window, LvmSetItemState, (ulong)index, (long)(nuint)&item);
    }

    public bool GetItemChecked(int index)
    {
        ListItem item;
        item.Mask = LvifState;
        item.Item = index;
        item.SubItem = 0;
        item.State = 0u;
        item.StateMask = LvisStateImageMask;
        item.Text = null;
        item.TextLength = 0;
        item.Image = 0;
        item.Param = 0u;
        item.Indent = 0;
        item.GroupId = 0;
        item.Columns = 0u;
        item.ColumnFormat = null;
        SendMessageW(window, LvmGetItemW, 0u, (long)(nuint)&item);
        return ((item.State & LvisStateImageMask) >> 12) == 2u;
    }

    /// A tick and a selection both arrive as `LVN_ITEMCHANGED`; the state mask
    /// says which, and both are worth reporting.
    protected override bool NotifiedBy(int code, void* raw)
    {
        if (code != LvnItemChanged)
            return false;
        NotifyListView* details = (NotifyListView*)raw;
        if ((details->Changed & 0x0008u) == 0u)
            return false;
        IControlNotify? held = owning;
        if (held == null)
            return false;
        ((IControlNotify)held).OnPlatformValueChanged();
        return true;
    }
}

// ================================================================== header

/// A row of column headings that can be dragged wider.
public class HeaderPeer : ControlPeer, IHeaderPeer
{
    weak IControlNotify? owning;
    int _sections;

    public HeaderPeer(IControlNotify owner, IContainerPeer parent)
    {
        base(MakeChild("SysHeader32", WindowOf(parent),
                       ChildStyle() | HdsButtons | HdsHorizontal, 0u),
             owner, true);
        owning = owner;
        _sections = 0;
    }

    public int AddSection(String text, int width)
    {
        HeaderItem item;
        var wide = text.ToUtf16();
        item.Mask = HdiWidth | HdiText | HdiFormat;
        item.Width = width;
        item.Text = wide.ToPointer();
        item.Bitmap = null;
        item.TextLength = 0;
        item.Format = HdfLeft | HdfString;
        item.Param = 0u;
        item.Image = 0;
        item.Order = 0;
        item.Type = 0u;
        item.FilterData = null;
        item.State = 0u;

        int at = (int)SendMessageW(window, HdmInsertItemW, (ulong)_sections,
                                   (long)(nuint)&item);
        if (at >= 0)
            _sections = _sections + 1;
        return at;
    }

    public void SetSectionWidth(int index, int width)
    {
        HeaderItem item;
        item.Mask = HdiWidth;
        item.Width = width;
        item.Text = null;
        item.Bitmap = null;
        item.TextLength = 0;
        item.Format = 0;
        item.Param = 0u;
        item.Image = 0;
        item.Order = 0;
        item.Type = 0u;
        item.FilterData = null;
        item.State = 0u;
        SendMessageW(window, HdmSetItemW, (ulong)index, (long)(nuint)&item);
    }

    public int GetSectionWidth(int index)
    {
        HeaderItem item;
        item.Mask = HdiWidth;
        item.Width = 0;
        item.Text = null;
        item.Bitmap = null;
        item.TextLength = 0;
        item.Format = 0;
        item.Param = 0u;
        item.Image = 0;
        item.Order = 0;
        item.Type = 0u;
        item.FilterData = null;
        item.State = 0u;
        if (SendMessageW(window, HdmGetItemW, (ulong)index, (long)(nuint)&item) == 0)
        {
            return 0;
        }
        return item.Width;
    }

    public int SectionCount
    {
        get
        {
            return (int)SendMessageW(window, HdmGetItemCount, 0u, 0);
        }
    }

    /// A section was dragged wider or narrower.
    protected override bool NotifiedBy(int code, void* raw)
    {
        if (code != HdnItemChangedW)
            return false;
        IControlNotify? held = owning;
        if (held == null)
            return false;
        ((IControlNotify)held).OnPlatformValueChanged();
        return true;
    }
}

#endif
