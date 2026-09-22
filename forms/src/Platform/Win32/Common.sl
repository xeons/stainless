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
// before it casts. `OnNotify` is where that happens.
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
uint GetFixedBarStyle() => CcsNoResize | CcsNoParentAlign | CcsNoDivider;

/// An image list's handle, or null for none, which every `*_SETIMAGELIST`
/// takes as "no pictures".
nuint GetImageListHandle(IImageListBackend? images) =>
    images == null ? 0u : ((IImageListBackend)images).Handle;

// ================================================================== toolbar

public class ToolBarPeer : ControlPeer, IToolBarPeer
{
    /// The command id of each button, in the order they were added, so that an
    /// index can be turned into an id and back.
    List<int> _commands;
    weak IControlNotify? _owner;
    bool _isOwnerDrawn;

    public ToolBarPeer(IControlNotify owner, IContainerPeer parent)
    {
        base(CreateChildWindow("ToolbarWindow32", GetContainerWindow(parent),
                       GetChildStyle() | GetFixedBarStyle() | TbStyleFlat | TbStyleList, 0u),
             owner, true);
        _owner = owner;
        _commands = new List<int>();
        _isOwnerDrawn = false;

        // Windows needs to be told how wide a `TBBUTTON` is before any is
        // added, because the structure grew between versions and this is how it
        // knows which one it has been handed.
        SendMessageW(Window, TbButtonStructSize, (ulong)sizeof(ToolBarButton), 0);
        SendMessageW(Window, TbSetMaxTextRows, 1u, 0);
    }

    ~ToolBarPeer()
    {
        for (nuint i = 0u; i < _commands.Count; i++)
            ReleaseCommandId(_commands[i]);
    }

    public int AddButton(String text, int image, ToolButtonKind kind)
    {
        ToolBarButton button;

        // A negative index means no picture, and it has to be said as
        // `I_IMAGENONE`: -1 is `I_IMAGECALLBACK`, which reserves the space and
        // then asks for a bitmap through `TBN_GETDISPINFO`. Nothing here
        // answers that, so every text-only button carried a blank gap where
        // its picture would have gone.
        button.Bitmap = image >= 0 ? image : IImageNone;
        button.Command = AllocateCommandId();
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
#if !X86
        button.Reserved2 = 0u;
        button.Reserved3 = 0u;
        button.Reserved4 = 0u;
        button.Reserved5 = 0u;
#endif
        button.Data = 0u;

        // The caption is a pointer to text the toolbar reads while the message
        // runs, so the wide string has to outlive the call and no longer.
        var wide = text.ToUtf16();
        button.Text = (nuint)(void*)wide.ToPointer();

        SendMessageW(Window, TbAddButtonsW, 1u, (long)(nuint)&button);
        _commands.Add(button.Command);
        return (int)_commands.Count - 1;
    }

    /// Which button a command id belongs to, or -1.
    int IndexOfCommand(int command)
    {
        for (nuint i = 0u; i < _commands.Count; i++)
        {
            if (_commands[i] == command)
                return (int)i;
        }
        return -1;
    }

    int GetCommandAt(int index)
    {
        if (index < 0 || (nuint)index >= _commands.Count)
            return -1;
        return _commands[(nuint)index];
    }

    /// A toolbar's buttons all report through the toolbar's own window, so the
    /// notification says *which* button in its low word rather than naming a
    /// control of its own.
    protected override bool OnCommand(uint code, int id)
    {
        int at = IndexOfCommand(id);
        if (at < 0)
            return false;
        IControlNotify? held = _owner;
        if (held == null)
            return false;
        ((IControlNotify)held).OnPlatformToolClicked(at);
        return true;
    }

    /// Windows will hand a toolbar's buttons over, so this only ever answers
    /// what it was asked.
    ///
    /// **Custom draw, not owner draw**, which is the same request through a
    /// different mechanism. A menu item is given a `MF_OWNERDRAW` flag and the
    /// window is sent `WM_DRAWITEM`; a toolbar has no such flag -- comctl32
    /// asks its parent through `WM_NOTIFY` on every paint whether to do its
    /// own drawing, and a control that is never asked is one whose parent
    /// never answered. So there is nothing to set here beyond remembering that
    /// the answer is now yes.
    public bool SetOwnerDrawn(bool drawn)
    {
        _isOwnerDrawn = drawn;
        Invalidate();
        return drawn;
    }

    /// comctl32 asking, several times per paint, how much of its own drawing
    /// to keep.
    ///
    /// **`CDRF_NOTIFYITEMDRAW` at the first stage is what makes the rest
    /// happen.** Without it the bar asks once about itself, is told nothing in
    /// particular, and draws every button natively -- which looks exactly like
    /// a renderer that was never set, and is the one mistake this mechanism
    /// invites.
    protected override bool OnNotify(int code, void* raw, long* answer)
    {
        if (!_isOwnerDrawn || code != NmCustomDraw)
            return false;

        IControlNotify? held = _owner;
        if (held == null)
            return false;
        var asked = (CustomDraw*)raw;

        if (asked->Stage == CddsPrePaint)
        {
            // **The client rectangle rather than the one the notification
            // carries.** `CustomDraw.Box` at this stage is the region being
            // repainted, which after a button changes state is that button and
            // nothing else -- so filling it would leave the rest of the strip
            // in whatever colour it happened to have. The background is the
            // whole bar or it is a patch.
            Rect client;
            GetClientRect(Window, &client);
            var bounds = FromRect(client);
            var surface = new Graphics(new GraphicsBackend(asked->Surface, bounds));
            if (!((IControlNotify)held).OnPlatformDrawToolBackground(surface, bounds))
                return false;

            *answer = CdrfNotifyItemDraw;
            return true;
        }

        if (asked->Stage == CddsItemPrePaint)
        {
            // A toolbar names a button by its command id here, not by its
            // position -- the same numbering `WM_COMMAND` uses and the same
            // map back.
            int at = IndexOfCommand((int)asked->Item);
            if (at < 0)
                return false;

            var bounds = FromRect(asked->Box);
            var surface = new Graphics(new GraphicsBackend(asked->Surface, bounds));
            if (!((IControlNotify)held).OnPlatformDrawTool(surface, bounds, at,
                                                           ToToolItemState(asked->State)))
            {
                // Handing one button back is allowed, and costs nothing: the
                // answer is zero, which is `CDRF_DODEFAULT`.
                return false;
            }

            *answer = CdrfSkipDefault;
            return true;
        }

        return false;
    }

    /// What comctl32 says a button looks like, in the control layer's terms.
    ///
    /// `CDIS_GRAYED` and `CDIS_DISABLED` both mean unavailable and a toolbar
    /// sets them together, so either one is taken as the answer -- reading only
    /// one of them is a disabled button drawn as though it could be pressed.
    static ToolItemState ToToolItemState(uint reported)
    {
        var state = ToolItemState.None;
        if ((reported & CdisHot) != 0u)
            state = state | ToolItemState.Hot;
        if ((reported & CdisSelected) != 0u)
            state = state | ToolItemState.Pressed;
        if ((reported & CdisChecked) != 0u)
            state = state | ToolItemState.Checked;
        if ((reported & (CdisDisabled | CdisGrayed)) != 0u)
            state = state | ToolItemState.Disabled;
        return state;
    }

    public nuint GetButtonId(int index)
    {
        int command = GetCommandAt(index);
        if (command < 0)
            return 0u;
        return (nuint)command;
    }

    public void SetButtonEnabled(int index, bool enabled)
    {
        int command = GetCommandAt(index);
        if (command < 0)
            return;
        SendMessageW(Window, TbEnableButton, (ulong)command, (long)(enabled ? 1 : 0));
    }

    public void SetButtonChecked(int index, bool checked)
    {
        int command = GetCommandAt(index);
        if (command < 0)
            return;
        SendMessageW(Window, TbCheckButton, (ulong)command, (long)(checked ? 1 : 0));
    }

    public bool GetButtonChecked(int index)
    {
        int command = GetCommandAt(index);
        if (command < 0)
            return false;
        return SendMessageW(Window, TbIsButtonChecked, (ulong)command, 0) != 0;
    }

    public void SetImages(IImageListBackend? images)
    {
        SendMessageW(Window, TbSetImageList, 0u, (long)GetImageListHandle(images));
    }

    /// `TBSTYLE_LIST` puts the caption beside the picture; without it there is
    /// room for one or the other. A creation-time style, so this re-sets it and
    /// asks the bar to lay itself out again.
    public void SetTextVisible(bool visible)
    {
        long style = Win32.User32.GetWindowLongPtrW(Window, GwlStyle);
        if (visible)
        {
            style = style | (long)TbStyleList;
        }
        else
        {
            style = style & ~(long)TbStyleList;
        }
        Win32.User32.SetWindowLongPtrW(Window, GwlStyle, style);
        ResizeToFit();
    }

    public void ResizeToFit() => SendMessageW(Window, TbAutoSize, 0u, 0);

    /// As tall as the bar makes itself, and as wide as it is given.
    public override FSize PreferredSize
    {
        get
        {
            long packed = SendMessageW(Window, TbGetButtonSize, 0u, 0);
            int height = (int)((packed >> 16) & 0xFFFFu);
            if (height <= 0)
                height = 24;
            return CreateSize(0, height + 8);
        }
    }
}

// =============================================================== status bar

public class StatusBarPeer : ControlPeer, IStatusBarPeer
{
    public StatusBarPeer(IControlNotify owner, IContainerPeer parent)
    {
        base(CreateChildWindow("msctls_statusbar32", GetContainerWindow(parent),
                       (GetChildStyle() & ~WsTabStop) | GetFixedBarStyle(), 0u),
             owner, true);
    }

    public void SetPanels(int[] edges)
    {
        if (edges.Length == 0u)
            return;
        SendMessageW(Window, SbSetParts, (ulong)edges.Length, (long)(nuint)&edges[0u]);
    }

    public void SetPanelText(int index, String text)
    {
        SendMessageW(Window, SbSetTextW, (ulong)index,
                     (long)(nuint)text.ToUtf16().ToPointer());
    }

    /// A status bar decides its own height from the font, and is right about it.
    public override FSize PreferredSize
    {
        get
        {
            Rect frame;
            GetWindowRect(Window, &frame);
            int height = frame.Bottom - frame.Top;
            if (height <= 0)
                height = 22;
            return CreateSize(0, height);
        }
    }
}

// ============================================================= progress bar

public class ProgressPeer : ControlPeer, IProgressPeer
{
    public ProgressPeer(IControlNotify owner, IContainerPeer parent)
    {
        base(CreateChildWindow("msctls_progress32", GetContainerWindow(parent),
                       (GetChildStyle() & ~WsTabStop) | PbsSmooth, 0u),
             owner, true);
        SendMessageW(Window, PbmSetRange32, 0u, 100);
    }

    public void SetRange(int minimum, int maximum)
    {
        SendMessageW(Window, PbmSetRange32, (ulong)minimum, (long)maximum);
    }

    public void SetValue(int value)
    {
        SendMessageW(Window, PbmSetPos, (ulong)value, 0);
    }

    public int GetValue() => (int)SendMessageW(Window, PbmGetPos, 0u, 0);

    /// A bar with no value that simply moves. The style is read at creation, so
    /// it is set here and the marquee then started or stopped -- which is why
    /// this is two calls rather than one.
    public void SetIndeterminate(bool indeterminate)
    {
        long style = Win32.User32.GetWindowLongPtrW(Window, GwlStyle);
        if (indeterminate)
        {
            style = style | (long)PbsMarquee;
        }
        else
        {
            style = style & ~(long)PbsMarquee;
        }
        Win32.User32.SetWindowLongPtrW(Window, GwlStyle, style);
        SendMessageW(Window, PbmSetMarquee, (ulong)(indeterminate ? 1 : 0), 30);
    }
}

// ================================================================ track bar

public class TrackBarPeer : ControlPeer, ITrackBarPeer
{
    weak IControlNotify? _owner;

    public TrackBarPeer(IControlNotify owner, IContainerPeer parent, bool vertical)
    {
        base(CreateChildWindow("msctls_trackbar32", GetContainerWindow(parent),
                       GetChildStyle() | TbsAutoTicks
                                    | (vertical ? TbsVertical : TbsHorizontal), 0u),
             owner, true);
        _owner = owner;
        SendMessageW(Window, TbmSetRange, 1u, (long)((100 << 16) | 0));
    }

    public void SetRange(int minimum, int maximum)
    {
        SendMessageW(Window, TbmSetRangeMin, 1u, (long)minimum);
        SendMessageW(Window, TbmSetRangeMax, 1u, (long)maximum);
    }

    public void SetValue(int value)
    {
        SendMessageW(Window, TbmSetPos, 1u, (long)value);
    }

    public int GetValue() => (int)SendMessageW(Window, TbmGetPos, 0u, 0);

    public void SetTickFrequency(int every)
    {
        SendMessageW(Window, TbmSetTicFreq, (ulong)every, 0);
    }

    /// The slider moved. Like a scroll bar, it tells its *parent* rather than
    /// itself, so the parent hands it back here.
    public void OnScroll()
    {
        IControlNotify? held = _owner;
        if (held == null)
            return;
        ((IControlNotify)held).OnPlatformValueChanged();
    }
}

// ============================================================== tab control

public class TabControlPeer : ControlPeer, ITabControlPeer
{
    weak IControlNotify? _owner;
    int _tabs;

    public TabControlPeer(IControlNotify owner, IContainerPeer parent)
    {
        base(CreateChildWindow("SysTabControl32", GetContainerWindow(parent),
                       GetChildStyle() | WsClipChildren, 0u),
             owner, true);
        _owner = owner;
        _tabs = 0;
    }

    /// A tab control is a container, so a page's controls are children of it.
    public void AddChild(IControlPeer child)
    {
        SetParent((HWND)(void*)child.Handle, Window);
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

        int at = (int)SendMessageW(Window, TcmInsertItemW, (ulong)_tabs,
                                   (long)(nuint)&item);
        _tabs = _tabs + 1;
        return at;
    }

    public void RemoveTab(int index)
    {
        SendMessageW(Window, TcmDeleteItem, (ulong)index, 0);
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
        SendMessageW(Window, TcmSetItemW, (ulong)index, (long)(nuint)&item);
    }

    public void SetSelectedTab(int index)
    {
        SendMessageW(Window, TcmSetCurSel, (ulong)index, 0);
    }

    public int GetSelectedTab()
    {
        return (int)SendMessageW(Window, TcmGetCurSel, 0u, 0);
    }

    public int TabCount
    {
        get
        {
            return (int)SendMessageW(Window, TcmGetItemCount, 0u, 0);
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
            GetClientRect(Window, &area);
            SendMessageW(Window, TcmAdjustRect, 0u, (long)(nuint)&area);
            return CreateRectangle(area.Left, area.Top, area.Right - area.Left, area.Bottom - area.Top);
        }
    }

    public void SetImages(IImageListBackend? images)
    {
        SendMessageW(Window, TcmSetImageList, 0u, (long)GetImageListHandle(images));
    }

    protected override bool OnNotify(int code, void* raw, long* answer)
    {
        if (code != TcnSelChange)
            return false;
        IControlNotify? held = _owner;
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
    weak IControlNotify? _owner;

    public TreeViewPeer(IControlNotify owner, IContainerPeer parent)
    {
        base(CreateChildWindow("SysTreeView32", GetContainerWindow(parent),
                       GetChildStyle() | TvsHasButtons | TvsHasLines
                                    | TvsLinesAtRoot | TvsShowSelAlways,
                       WsExClientEdge),
             owner, true);
        _owner = owner;
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

        long made = SendMessageW(Window, TvmInsertItemW, 0u, (long)(nuint)&insert);
        return new TreeNodeHandle((HTREEITEM)(void*)(nuint)made);
    }

    HTREEITEM ToNativeItem(ITreeNodeHandle node)
    {
        if (node is TreeNodeHandle real)
            return real.Native;
        return null;
    }

    /// Quiet, because removing the selected node moves the selection.
    public void RemoveNode(ITreeNodeHandle node)
    {
        SendMessageQuietly(TvmDeleteItem, 0u, (long)(nuint)(void*)ToNativeItem(node));
    }

    public void SetNodeText(ITreeNodeHandle node, String text)
    {
        TreeItem item;
        var wide = text.ToUtf16();
        item.Mask = TvifText | TvifHandle;
        item.Item = ToNativeItem(node);
        item.State = 0u;
        item.StateMask = 0u;
        item.Text = wide.ToPointer();
        item.TextLength = 0;
        item.Image = -1;
        item.SelectedImage = -1;
        item.Children = 0;
        item.Param = 0u;
        SendMessageW(Window, TvmSetItemW, 0u, (long)(nuint)&item);
    }

    public String GetNodeText(ITreeNodeHandle node)
    {
        var buffer = new char16[512u];
        TreeItem item;
        item.Mask = TvifText | TvifHandle;
        item.Item = ToNativeItem(node);
        item.State = 0u;
        item.StateMask = 0u;
        item.Text = &buffer[0u];
        item.TextLength = 512;
        item.Image = 0;
        item.SelectedImage = 0;
        item.Children = 0;
        item.Param = 0u;
        if (SendMessageW(Window, TvmGetItemW, 0u, (long)(nuint)&item) == 0)
            return "";
        return Text.FromNullTerminatedUtf16(&buffer[0u]);
    }

    public void SetNodeExpanded(ITreeNodeHandle node, bool expanded)
    {
        SendMessageW(Window, TvmExpand, expanded ? TveExpand : TveCollapse,
                     (long)(nuint)(void*)ToNativeItem(node));
    }

    public void SelectNode(ITreeNodeHandle node)
    {
        SendMessageQuietly(TvmSelectItem, TvgnCaret, (long)(nuint)(void*)ToNativeItem(node));
    }

    public ITreeNodeHandle? GetSelectedNode()
    {
        long chosen = SendMessageW(Window, TvmGetNextItem, TvgnCaret, 0);
        if (chosen == 0)
            return null;
        return new TreeNodeHandle((HTREEITEM)(void*)(nuint)chosen);
    }

    public ITreeNodeHandle? GetNodeAt(Forms.Drawing.Point at)
    {
        TreeHitTest probe;
        probe.At.X = at.X;
        probe.At.Y = at.Y;
        probe.Flags = 0u;
        probe.Item = null;

        // The item comes back in the structure rather than in the return
        // value, and it is filled even for a hit on the expand button or the
        // indent -- so the flags decide, not whether `Item` is set.
        SendMessageW(Window, TvmHitTest, 0u, (long)(nuint)&probe);

        if ((probe.Flags & TvhtOnItem) == 0u)
            return null;
        if (probe.Item == null)
            return null;
        return new TreeNodeHandle(probe.Item);
    }

    public void Clear()
    {
        SendMessageQuietly(TvmDeleteItem, 0u, (long)(nuint)(void*)TreeRoot());
    }

    /// A tree view never destroys the image list it is given.
    public void SetImages(IImageListBackend? images)
    {
        SendMessageW(Window, TvmSetImageList, 0u, (long)GetImageListHandle(images));
    }

    protected override bool OnNotify(int code, void* raw, long* answer)
    {
        if (code != TvnSelChangedW)
            return false;
        if (Echoing)
            return true;
        IControlNotify? held = _owner;
        if (held == null)
            return false;
        ((IControlNotify)held).OnPlatformValueChanged();
        return true;
    }
}

// ========================================================= report list view

/// Posted by a list view to itself when a row loses the selection. See
/// `ReportListPeer`.
const uint WmSelectionSettled = 0x8001u;   // WM_APP + 1

/// An `LVITEMW` that sets the state bits in `mask` to `state`.
ListItem CreateListItemState(uint state, uint mask)
{
    ListItem item;
    item.Mask = LvifState;
    item.Item = 0;
    item.SubItem = 0;
    item.State = state;
    item.StateMask = mask;
    item.Text = null;
    item.TextLength = 0;
    item.Image = 0;
    item.Param = 0u;
    item.Indent = 0;
    item.GroupId = 0;
    item.Columns = 0u;
    item.ColumnFormat = null;
    return item;
}

/// What a list view and a check list share: at most one row selected, set and
/// reported on the seam's terms.
///
/// **`LVN_ITEMCHANGED` is one notification per row.** Moving the selection is
/// one row losing it and another gaining it, in an order comctl32 does not
/// promise. So a gain is reported at once, and a loss only once the messages
/// already queued have run and no row has gained it since.
public class ReportListPeer : ControlPeer
{
    /// The row last reported as selected, or -1.
    int _reported;

    protected ReportListPeer(HWND made, IControlNotify owner)
    {
        base(made, owner, true);
        _reported = -1;
    }

    /// The selected row, or -1.
    protected int SelectedRow
    {
        get
        {
            return (int)SendMessageW(Window, LvmGetNextItem, (ulong)(nuint)(nint)(-1),
                                     (long)LvniSelected);
        }
    }

    /// Selects one row, or none for -1.
    ///
    /// Every row is cleared first: `LVM_SETITEMSTATE` adds a row to the
    /// selection rather than moving it there.
    protected void SelectRow(int row)
    {
        var item = CreateListItemState(0u, LvisSelected);
        SendMessageQuietly(LvmSetItemState, (ulong)(nuint)(nint)(-1), (long)(nuint)&item);
        if (row >= 0)
        {
            item = CreateListItemState(LvisSelected | LvisFocused, LvisSelected | LvisFocused);
            SendMessageQuietly(LvmSetItemState, (ulong)row, (long)(nuint)&item);
            SendMessageW(Window, LvmEnsureVisible, (ulong)row, 0);
        }
        MarkSelectionReported();
    }

    /// Takes the selection as it now is, after the program changed it.
    protected void MarkSelectionReported() => _reported = SelectedRow;

    /// Whether a change to a row's state bits, other than its selection, is
    /// the control's value changing. A tick is, in a check list.
    protected virtual bool IsValueChange(uint flipped) => false;

    void ReportSelectionChange()
    {
        var owner = Owner;
        if (owner != null)
            ((IControlNotify)owner).OnPlatformValueChanged();
    }

    protected override bool OnNotify(int code, void* raw, long* answer)
    {
        if (code != LvnItemChanged)
            return false;
        if (Echoing)
            return true;
        NotifyListView* details = (NotifyListView*)raw;
        if ((details->Changed & LvifState) == 0u)
            return true;

        uint flipped = details->NewState ^ details->OldState;
        bool moved = (flipped & LvisSelected) != 0u;
        bool gained = moved && (details->NewState & LvisSelected) != 0u;
        if (moved && !gained)
            PostMessageW(Window, WmSelectionSettled, 0u, 0);
        if (gained)
            _reported = details->Item;
        if (gained || IsValueChange(flipped))
            ReportSelectionChange();
        return true;
    }

    public override long WndProc(uint message, ulong wParam, long lParam)
    {
        if (message == WmSelectionSettled)
        {
            if (_reported >= 0 && SelectedRow < 0)
            {
                _reported = -1;
                ReportSelectionChange();
            }
            return 0;
        }
        return base.WndProc(message, wParam, lParam);
    }
}

// ================================================================ list view

/// **`LVS_SHAREIMAGELISTS`, because the image list is not this control's.** A
/// list view without it destroys its image lists with itself, and the
/// `ImageList` that made one goes on to destroy it again -- while a tree or a
/// toolbar sharing it draws from a handle that is gone.
public class ListViewPeer : ReportListPeer, IListViewPeer
{
    int _columns;
    int _rows;

    public ListViewPeer(IControlNotify owner, IContainerPeer parent)
    {
        base(CreateChildWindow("SysListView32", GetContainerWindow(parent),
                       GetChildStyle() | LvsReport | LvsShowSelAlways | LvsSingleSel
                                    | LvsShareImageLists,
                       WsExClientEdge),
             owner);
        _columns = 0;
        _rows = 0;
    }

    public void SetStyle(ListViewStyle style)
    {
        long was = Win32.User32.GetWindowLongPtrW(Window, GwlStyle);
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
        Win32.User32.SetWindowLongPtrW(Window, GwlStyle, was);
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

        int at = (int)SendMessageW(Window, LvmInsertColumnW, (ulong)_columns,
                                   (long)(nuint)&column);
        _columns = _columns + 1;
        return at;
    }

    public void SetColumnWidth(int column, int width)
    {
        SendMessageW(Window, LvmSetColumnWidth, (ulong)column, (long)width);
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

        int at = (int)SendMessageQuietly(LvmInsertItemW, 0u, (long)(nuint)&item);
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
        SendMessageW(Window, LvmSetItemW, 0u, (long)(nuint)&item);
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
        SendMessageW(Window, LvmGetItemW, 0u, (long)(nuint)&item);
        return Text.FromNullTerminatedUtf16(&buffer[0u]);
    }

    public void RemoveRow(int row)
    {
        if (SendMessageQuietly(LvmDeleteItem, (ulong)row, 0) != 0 && _rows > 0)
        {
            _rows = _rows - 1;
        }
        MarkSelectionReported();
    }

    public void Clear()
    {
        SendMessageQuietly(LvmDeleteAllItems, 0u, 0);
        _rows = 0;
        MarkSelectionReported();
    }

    public int RowCount => (int)SendMessageW(Window, LvmGetItemCount, 0u, 0);

    public int GetSelectedRow() => SelectedRow;

    public void SetSelectedRow(int row) => SelectRow(row);

    public void SetImages(IImageListBackend? images)
    {
        SendMessageW(Window, LvmSetImageList, 1u, (long)GetImageListHandle(images));
    }

    public void SetFullRowSelect(bool full, bool gridLines)
    {
        uint wanted = 0u;
        if (full)
            wanted = wanted | LvsExFullRowSelect;
        if (gridLines)
            wanted = wanted | LvsExGridLines;
        SendMessageW(Window, LvmSetExtendedStyle,
                     (ulong)(LvsExFullRowSelect | LvsExGridLines), (long)wanted);
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
    weak IControlNotify? _owner;

    public SpinPeer(IControlNotify owner, IContainerPeer parent)
    {
        base(CreateChildWindow("EDIT", GetContainerWindow(parent),
                       GetChildStyle() | EsAutoHScroll | EsRight, WsExClientEdge),
             owner, true);
        _owner = owner;

        _arrows = CreateChildWindow("msctls_updown32", GetContainerWindow(parent),
                           GetChildStyle() | UdsSetBuddyInt | UdsAlignRight
                                        | UdsArrowKeys | UdsAutoBuddy, 0u);
        SendMessageW(_arrows, UdmSetBuddy, (ulong)(nuint)(void*)Window, 0);
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

    /// Both quiet: the arrows write the edit's text, and the edit reports it.
    public void SetRange(int minimum, int maximum)
    {
        SendMessageQuietly(_arrows, UdmSetRange32, (ulong)minimum, (long)maximum);
    }

    public void SetValue(int value)
    {
        SendMessageQuietly(_arrows, UdmSetPos32, 0u, (long)value);
    }

    public int GetValue()
    {
        return (int)SendMessageW(_arrows, UdmGetPos32, 0u, 0);
    }

    /// The edit reports its own changes, which is what makes typing a number
    /// count as well as clicking the arrows.
    protected override bool OnCommand(uint code, int id)
    {
        if (code != EnChange)
            return false;
        if (Echoing)
            return true;
        IControlNotify? held = _owner;
        if (held == null)
            return false;
        ((IControlNotify)held).OnPlatformValueChanged();
        return true;
    }

    /// The arrows sit inside the edit's right-hand edge, so the pair is laid out
    /// as one control -- which is the whole illusion.
    public override void SetBounds(FRect bounds)
    {
        MoveWindow(Window, bounds.X, bounds.Y, bounds.Width, bounds.Height, 1);
        // `UDM_SETBUDDY` re-docks the arrows against whatever the buddy now is.
        SendMessageW(_arrows, UdmSetBuddy, (ulong)(nuint)(void*)Window, 0);
    }

    public override void SetVisible(bool visible)
    {
        ShowWindow(Window, visible ? SwShowNoActivate : SwHide);
        ShowWindow(_arrows, visible ? SwShowNoActivate : SwHide);
    }

    public override void SetEnabled(bool enabled)
    {
        EnableWindow(Window, enabled ? 1 : 0);
        EnableWindow(_arrows, enabled ? 1 : 0);
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
public class CheckListPeer : ReportListPeer, ICheckListPeer
{
    int _rows;

    /// `LVS_NOCOLUMNHEADER`, since the one column exists to hold the text and
    /// has no heading to show.
    public CheckListPeer(IControlNotify owner, IContainerPeer parent)
    {
        base(CreateChildWindow("SysListView32", GetContainerWindow(parent),
                       GetChildStyle() | LvsReport | LvsShowSelAlways | LvsSingleSel
                                    | LvsNoColumnHeader,
                       WsExClientEdge),
             owner);
        _rows = 0;
        SendMessageW(Window, LvmSetExtendedStyle,
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
        SendMessageW(Window, LvmInsertColumnW, 0u, (long)(nuint)&column);
    }

    /// The one column follows the control, so the text fills it and no
    /// horizontal scroll bar appears.
    public override void SetBounds(FRect bounds)
    {
        MoveWindow(Window, bounds.X, bounds.Y, bounds.Width, bounds.Height, 1);
        Rect client;
        GetClientRect(Window, &client);
        int width = client.Right - client.Left;
        if (width > 0)
        {
            SendMessageW(Window, LvmSetColumnWidth, 0u, (long)width);
        }
    }

    /// Quiet, because a new row is given its empty tick as it goes in.
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
        if (SendMessageQuietly(LvmInsertItemW, 0u, (long)(nuint)&item) >= 0)
        {
            _rows = _rows + 1;
        }
    }

    public void RemoveItem(int index)
    {
        if (SendMessageQuietly(LvmDeleteItem, (ulong)index, 0) != 0 && _rows > 0)
        {
            _rows = _rows - 1;
        }
        MarkSelectionReported();
    }

    public void ClearItems()
    {
        SendMessageQuietly(LvmDeleteAllItems, 0u, 0);
        _rows = 0;
        MarkSelectionReported();
    }

    public int ItemCount => (int)SendMessageW(Window, LvmGetItemCount, 0u, 0);

    public void SetSelectedIndex(int index) => SelectRow(index);

    public int GetSelectedIndex() => SelectedRow;

    /// The tick is the *state image*, one-based: 1 is empty and 2 is ticked.
    public void SetItemChecked(int index, bool checked)
    {
        var item = CreateListItemState(GetCheckedStateMask(checked), LvisStateImageMask);
        SendMessageQuietly(LvmSetItemState, (ulong)index, (long)(nuint)&item);
    }

    public bool GetItemChecked(int index)
    {
        var item = CreateListItemState(0u, LvisStateImageMask);
        item.Item = index;
        SendMessageW(Window, LvmGetItemW, 0u, (long)(nuint)&item);
        return ((item.State & LvisStateImageMask) >> 12) == 2u;
    }

    /// A tick is a change of value as much as a selection is.
    protected override bool IsValueChange(uint flipped)
    {
        return (flipped & LvisStateImageMask) != 0u;
    }
}

// ================================================================== header

/// A row of column headings that can be dragged wider.
public class HeaderPeer : ControlPeer, IHeaderPeer
{
    weak IControlNotify? _owner;
    int _sections;

    public HeaderPeer(IControlNotify owner, IContainerPeer parent)
    {
        base(CreateChildWindow("SysHeader32", GetContainerWindow(parent),
                       GetChildStyle() | HdsButtons | HdsHorizontal, 0u),
             owner, true);
        _owner = owner;
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

        int at = (int)SendMessageQuietly(HdmInsertItemW, (ulong)_sections, (long)(nuint)&item);
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
        // Quiet: a header reports `HDN_ITEMCHANGED` for this as for a drag.
        SendMessageQuietly(HdmSetItemW, (ulong)index, (long)(nuint)&item);
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
        if (SendMessageW(Window, HdmGetItemW, (ulong)index, (long)(nuint)&item) == 0)
        {
            return 0;
        }
        return item.Width;
    }

    public int SectionCount
    {
        get
        {
            return (int)SendMessageW(Window, HdmGetItemCount, 0u, 0);
        }
    }

    /// A section was dragged wider or narrower.
    protected override bool OnNotify(int code, void* raw, long* answer)
    {
        if (code != HdnItemChangedW)
            return false;
        if (Echoing)
            return true;
        IControlNotify? held = _owner;
        if (held == null)
            return false;
        ((IControlNotify)held).OnPlatformValueChanged();
        return true;
    }
}

#endif
