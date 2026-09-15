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

// The common controls: `ToolBar`, `StatusBar`, `ProgressBar`, `TrackBar`,
// `TabControl`, `TreeView` and `ListView`.
//
// This is the LCL's `comctrls.pp` -- 4,300 lines, and the largest single unit
// in the LCL after the grids. What is here is the part a program uses, named as
// C# names it, with the collection classes replaced by the language's own:
// `TListItems`, `TListColumns`, `TStatusPanels` and `TCoolBands` are all
// `TCollection` descendants that exist because Object Pascal has no generic
// list, and `List<T>` is one.
module Forms;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;

// ================================================================ image list

/// Same-sized pictures, kept once and referred to by number.
///
/// A toolbar, a tree and a list take their icons from one of these rather than
/// holding pictures of their own -- the control stores an index and the list
/// stores the picture, which is how every platform arranges it and why one
/// image list can dress several controls.
public class ImageList {
    IImageListBackend backend;
    List<Bitmap> kept;

    public ImageList(int width, int height) {
        backend = WidgetSet.Current.CreateImageList(Size.Of(width, height));
        kept = new List<Bitmap>();
    }

    /// 16x16, which is what a toolbar and a tree use.
    public ImageList() { this(16, 16); }

    /// Adds a picture and answers its index, or -1 if the platform refused it.
    ///
    /// The `Bitmap` is kept, because the platform copied the pixels but the
    /// caller has no reason to expect that and every reason to drop the object.
    public int Add(Bitmap picture) {
        int at = backend.Add(picture.Backend());
        if (at >= 0) { kept.Add(picture); }
        return at;
    }

    /// Loads a picture and adds it. The error names the file rather than
    /// answering -1, because a missing icon is a mistake worth reading about.
    public Result<int, String> AddFile(String path) {
        var loaded = Bitmap.FromFile(path);
        if (!loaded.Ok) { return Fail(loaded.Error); }
        return Ok(Add(loaded.Value));
    }

    /// Adds a picture out of the program's own resources, by the id its
    /// resource script gave it.
    ///
    /// The usual way to dress a toolbar, because the icons are part of the
    /// program rather than part of its data: nothing to install beside the
    /// executable and nothing to find at startup. Windows only -- see
    /// `Bitmap.FromResource`, whose error this passes on.
    public Result<int, String> AddResource(int id) {
        var loaded = Bitmap.FromResource(id);
        if (!loaded.Ok) { return Fail(loaded.Error); }
        return Ok(Add(loaded.Value));
    }

    public int Count => backend.Count();
    public Size ImageSize => backend.ImageSize();

    /// The platform's list, for the controls that take one.
    public IImageListBackend Backend() { return backend; }
}

// =================================================================== toolbar

/// One button on a toolbar.
///
/// **Not a `Control`.** `TToolButton` is a `TGraphicControl` with a position
/// and a parent, which lets the LCL's designer drag one about and costs every
/// button an object the platform knows nothing about -- a Windows toolbar owns
/// its buttons and lays them out itself. This is a handle on one of those: an
/// index, a caption and a `Click`.
public class ToolButton {
    weak ToolBar? bar;
    int index;

    bool held;

    public ToolButton(ToolBar owner, int at) {
        bar = owner;
        index = at;
        held = true;
    }

    /// Where it sits on the bar, counting separators.
    public int Index => index;

    public bool Enabled {
        get => held;
        set {
            held = value;
            // A weak reference is never narrowed, so it goes into a strong
            // local first.
            ToolBar? owner = bar;
            if (owner != null) { ((ToolBar)owner).SetEnabled(index, value); }
        }
    }

    /// Whether a toggle button is pressed in. Meaningless on a plain one.
    public bool Checked {
        get {
            ToolBar? owner = bar;
            if (owner == null) { return false; }
            return ((ToolBar)owner).GetChecked(index);
        }
        set {
            ToolBar? owner = bar;
            if (owner != null) { ((ToolBar)owner).SetChecked(index, value); }
        }
    }

    /// The button was pressed.
    public event EventHandler Click;

    /// Raised by the bar, which is what the platform reports to.
    public void Raise(Control sender) { Click(sender); }

    /// What the platform calls this button, on the same terms as
    /// `MenuItem.PlatformId`.
    public nuint PlatformId {
        get {
            ToolBar? owner = bar;
            if (owner == null) { return 0u; }
            return ((ToolBar)owner).ButtonId(index);
        }
    }
}

/// A row of buttons.
public class ToolBar : WindowedControl {
    IToolBarPeer native;
    List<ToolButton> buttons;
    ImageList? pictures;
    bool captions;

    public ToolBar(WindowedControl parent) {
        base(parent);
        buttons = new List<ToolButton>();
        pictures = null;
        captions = true;
        native = WidgetSet.Current.CreateToolBar(this, ParentPeer());
        AttachPeer(native);
    }

    /// Adds a button and answers it, so a handler can be attached to the result.
    public ToolButton Add(String text, int image) {
        int at = native.AddButton(text, image, ToolButtonKind.Button);
        var made = new ToolButton(this, at);
        buttons.Add(made);
        native.ResizeToFit();
        return made;
    }

    public ToolButton Add(String text) { return Add(text, -1); }

    /// A button that stays pressed until pressed again.
    public ToolButton AddToggle(String text, int image) {
        int at = native.AddButton(text, image, ToolButtonKind.Toggle);
        var made = new ToolButton(this, at);
        buttons.Add(made);
        native.ResizeToFit();
        return made;
    }

    /// A gap between groups of buttons. Answers nothing: a separator has no
    /// state and nothing to handle.
    public void AddSeparator() {
        int at = native.AddButton("", -1, ToolButtonKind.Separator);
        buttons.Add(new ToolButton(this, at));
        native.ResizeToFit();
    }

    public List<ToolButton> Buttons => buttons;

    /// Where the buttons' pictures come from.
    public ImageList? Images {
        get => pictures;
        set {
            pictures = value;
            if (value != null) { native.SetImages(((ImageList)value).Backend()); }
            native.ResizeToFit();
        }
    }

    /// Whether a caption is shown beside each picture.
    public bool ShowText {
        get => captions;
        set {
            captions = value;
            native.SetTextVisible(value);
        }
    }

    nuint ButtonId(int index) { return native.ButtonId(index); }
    void SetEnabled(int index, bool enabled) { native.SetButtonEnabled(index, enabled); }
    void SetChecked(int index, bool checked) { native.SetButtonChecked(index, checked); }
    bool GetChecked(int index) { return native.GetButtonChecked(index); }

    public override Size PreferredSize => native.PreferredSize();

    /// The platform says which button; the bar turns that into the button's own
    /// event, so a program never handles "a click on the toolbar" and then
    /// works out which one it was.
    public override void OnPlatformToolClicked(int index) {
        if (index < 0 || (nuint)index >= buttons.Count()) { return; }
        buttons.At((nuint)index).Raise(this);
    }
}

// =============================================================== status bar

/// The strip along the bottom, divided into panels.
public class StatusBar : WindowedControl {
    IStatusBarPeer native;
    List<String> texts;
    List<int>    widths;

    public StatusBar(WindowedControl parent) {
        base(parent);
        texts = new List<String>();
        widths = new List<int>();
        native = WidgetSet.Current.CreateStatusBar(this, ParentPeer());
        AttachPeer(native);
        Dock = DockStyle.Bottom;
    }

    /// Adds a panel and answers its index. A width of -1 means "the rest of the
    /// bar", and only the last panel should have one.
    public int AddPanel(int width) {
        widths.Add(width);
        texts.Add("");
        Rebuild();
        return (int)widths.Count() - 1;
    }

    /// What a panel says.
    public String PanelText(int index) {
        if (index < 0 || (nuint)index >= texts.Count()) { return ""; }
        return texts.At((nuint)index);
    }

    public void SetPanelText(int index, String text) {
        if (index < 0 || (nuint)index >= texts.Count()) { return; }
        texts.Set((nuint)index, text);
        native.SetPanelText(index, text);
    }

    public nuint PanelCount => widths.Count();

    /// Turns the panel widths into the running edges Windows wants.
    ///
    /// The platform takes the right-hand edge of each panel rather than its
    /// width, which is one subtraction nobody should have to remember -- so the
    /// widths are what a program gives and this is where they become edges.
    void Rebuild() {
        var edges = new int[widths.Count()];
        int running = 0;
        for (nuint i = 0u; i < widths.Count(); i += 1u) {
            int width = widths.At(i);
            if (width < 0) {
                edges[i] = -1;
            } else {
                running = running + width;
                edges[i] = running;
            }
        }
        native.SetPanels(edges);
        for (nuint i = 0u; i < texts.Count(); i += 1u) {
            native.SetPanelText((int)i, texts.At(i));
        }
    }

    public override Size PreferredSize => native.PreferredSize();
}

// ============================================================= progress bar

/// How far along something is.
public class ProgressBar : WindowedControl {
    IProgressPeer native;
    int low;
    int high;
    bool rolling;

    public ProgressBar(WindowedControl parent) {
        base(parent);
        low = 0;
        high = 100;
        rolling = false;
        native = WidgetSet.Current.CreateProgress(this, ParentPeer());
        AttachPeer(native);
    }

    public int Minimum {
        get => low;
        set {
            low = value;
            native.SetRange(low, high);
        }
    }

    public int Maximum {
        get => high;
        set {
            high = value;
            native.SetRange(low, high);
        }
    }

    public int Value {
        get => native.GetValue();
        set { native.SetValue(value); }
    }

    /// A bar that moves without saying how far along it is, for work whose
    /// length is unknown. C#'s `ProgressBarStyle.Marquee` under a plainer name.
    public bool Indeterminate {
        get => rolling;
        set {
            rolling = value;
            native.SetIndeterminate(value);
        }
    }
}

// ================================================================ track bar

/// A slider.
public class TrackBar : WindowedControl {
    ITrackBarPeer native;
    int low;
    int high;
    int ticks;

    public TrackBar(WindowedControl parent, bool vertical) {
        base(parent);
        low = 0;
        high = 100;
        ticks = 10;
        native = WidgetSet.Current.CreateTrackBar(this, ParentPeer(), vertical);
        AttachPeer(native);
    }

    public TrackBar(WindowedControl parent) { this(parent, false); }

    public int Minimum {
        get => low;
        set {
            low = value;
            native.SetRange(low, high);
        }
    }

    public int Maximum {
        get => high;
        set {
            high = value;
            native.SetRange(low, high);
        }
    }

    public int Value {
        get => native.GetValue();
        set { native.SetValue(value); }
    }

    /// How often a tick is drawn beneath the slider.
    public int TickFrequency {
        get => ticks;
        set {
            ticks = value;
            native.SetTickFrequency(value);
        }
    }

    /// The slider moved, whoever moved it.
    public event EventHandler ValueChanged;

    protected virtual void OnValueChanged() { ValueChanged(this); }

    public override void OnPlatformValueChanged() { OnValueChanged(); }
}

// ============================================================== tab control

/// One page of a `TabControl`.
///
/// A real container, so controls are put on it exactly as they are put on a
/// panel -- which is what makes a tabbed form no different from an untabbed one
/// once the page is chosen.
public class TabPage : WindowedControl {
    IPanelPeer native;
    int index;

    public TabPage(TabControl owner, String text) {
        base(owner);
        native = WidgetSet.Current.CreatePanel(this, ParentPeer());
        AttachContainerPeer(native);
        StoredText = text;
        index = owner.Register(this, text);
    }

    /// Which tab this page is behind.
    public int Index => index;

    /// Told its new number after a page in front of it was removed. Called by
    /// `TabControl.RemovePage` and by nothing else.
    public void Renumber(int now) { index = now; }

    /// The caption on the tab.
    public String Caption {
        get => StoredText;
        set {
            StoredText = value;
            var owner = Parent;
            if (owner != null) {
                if (owner is TabControl tabs) { tabs.SetTabText(index, value); }
            }
        }
    }
}

/// A stack of pages with tabs across the top.
public class TabControl : WindowedControl {
    ITabControlPeer native;
    List<TabPage> pages;
    ImageList? pictures;

    public TabControl(WindowedControl parent) {
        base(parent);
        pages = new List<TabPage>();
        pictures = null;
        native = WidgetSet.Current.CreateTabControl(this, ParentPeer());
        AttachContainerPeer(native);
    }

    /// Called by a `TabPage` as it is built. Not public: a page joins the
    /// control it was constructed with, and there is no other way in.
    int Register(TabPage page, String text) {
        int at = native.AddTab(text, -1);
        pages.Add(page);
        // **Inserting a tab does not make it current.** Windows leaves the
        // selection at -1 until something is chosen, so a control that simply
        // showed whichever page was selected would show none of them -- every
        // page hidden, and a tab strip over an empty rectangle.
        if (native.GetSelectedTab() < 0) { native.SetSelectedTab(0); }
        ShowOnly(native.GetSelectedTab());
        return at;
    }

    void SetTabText(int index, String text) { native.SetTabText(index, text); }

    public List<TabPage> Pages => pages;

    /// Takes a page out and answers whether it was there.
    ///
    /// **Every page after it is renumbered**, which is the whole difficulty. A
    /// `TabPage` remembers which tab it is behind so that setting its caption
    /// can name one, and removing the tab in front of it silently makes that
    /// number point at its neighbour. So the indices are rewritten here rather
    /// than left for the next caption change to get wrong -- a bug that would
    /// have shown up as renaming the wrong tab, long after the close that
    /// caused it.
    ///
    /// The page is hidden rather than destroyed: a control's lifetime is its
    /// parent's, and what a caller does with the page afterwards is its
    /// business. Dropping the last reference to it is what destroys it.
    public bool RemovePage(TabPage page) {
        nuint at = 0u;
        bool found = false;
        for (nuint i = 0u; i < pages.Count(); i += 1u) {
            if (pages.At(i) == page) { at = i; found = true; break; }
        }
        if (!found) { return false; }

        native.RemoveTab((int)at);
        pages.RemoveAt(at);
        page.Visible = false;

        for (nuint i = at; i < pages.Count(); i += 1u) { pages.At(i).Renumber((int)i); }

        // Removing the selected tab leaves the platform's selection wherever it
        // landed, which may be -1 with pages still here.
        int chosen = native.GetSelectedTab();
        if (chosen < 0 && !pages.IsEmpty()) {
            chosen = (int)(at >= pages.Count() ? pages.Count() - 1u : at);
            native.SetSelectedTab(chosen);
        }
        ShowOnly(native.GetSelectedTab());
        OnSelectedIndexChanged();
        return true;
    }

    /// How many tabs the platform has, which is not the same question as how
    /// many pages this control is holding -- and is the one that notices when
    /// an insertion quietly did nothing.
    public int TabCount => native.TabCount();

    /// Which page is showing.
    public int SelectedIndex {
        get => native.GetSelectedTab();
        set {
            native.SetSelectedTab(value);
            ShowOnly(value);
            OnSelectedIndexChanged();
        }
    }

    public TabPage? SelectedPage {
        get {
            int at = SelectedIndex;
            if (at < 0 || (nuint)at >= pages.Count()) { return null; }
            return pages.At((nuint)at);
        }
    }

    public ImageList? Images {
        get => pictures;
        set {
            pictures = value;
            if (value != null) { native.SetImages(((ImageList)value).Backend()); }
        }
    }

    /// **The pages are shown and hidden here, not by the platform.** A Windows
    /// tab control draws the tabs and nothing else: what is underneath them is
    /// the program's business, and a control that did not hide the page it left
    /// would leave both drawn on top of each other. Every toolkit does this
    /// somewhere, and the LCL does it in `TCustomTabControl.ShowCurrentPage`.
    void ShowOnly(int chosen) {
        var area = native.PageArea();
        for (nuint i = 0u; i < pages.Count(); i += 1u) {
            var page = pages.At(i);
            bool wanted = (int)i == chosen;
            page.Visible = wanted;
            if (wanted) { page.Bounds = area; }
        }
    }

    /// The chosen page changed.
    public event EventHandler SelectedIndexChanged;

    protected virtual void OnSelectedIndexChanged() { SelectedIndexChanged(this); }

    public override void OnPlatformValueChanged() {
        ShowOnly(native.GetSelectedTab());
        OnSelectedIndexChanged();
    }

    /// A resize moves the page area, so whichever page is showing follows it.
    protected override void OnResize() {
        base.OnResize();
        ShowOnly(native.GetSelectedTab());
    }
}

// ================================================================ tree view

/// One node of a `TreeView`.
public class TreeNode {
    weak TreeView? tree;
    ITreeNodeHandle handle;
    List<TreeNode> children;

    public TreeNode(TreeView owner, ITreeNodeHandle place) {
        tree = owner;
        handle = place;
        children = new List<TreeNode>();
    }

    /// The platform's idea of where this node is.
    public ITreeNodeHandle Handle() { return handle; }

    public String Text {
        get {
            TreeView? owner = tree;
            if (owner == null) { return ""; }
            return ((TreeView)owner).TextOf(handle);
        }
        set {
            TreeView? owner = tree;
            if (owner != null) { ((TreeView)owner).SetTextOf(handle, value); }
        }
    }

    public List<TreeNode> Nodes => children;

    /// Adds a node under this one and answers it.
    public TreeNode Add(String text, int image) {
        TreeView? owner = tree;
        if (owner == null) { sl_fail("this node is not on a tree".ToPointer()); }
        var made = ((TreeView)owner).Insert(this, text, image);
        children.Add(made);
        return made;
    }

    public TreeNode Add(String text) { return Add(text, -1); }

    public void Expand() {
        TreeView? owner = tree;
        if (owner != null) { ((TreeView)owner).SetExpanded(handle, true); }
    }

    public void Collapse() {
        TreeView? owner = tree;
        if (owner != null) { ((TreeView)owner).SetExpanded(handle, false); }
    }
}

/// A tree of nodes that open and close.
public class TreeView : WindowedControl {
    ITreeViewPeer native;
    ImageList? pictures;
    List<TreeNode> roots;
    /// Every node made, so that the handle the platform reports can be turned
    /// back into the object a program holds.
    List<TreeNode> all;

    public TreeView(WindowedControl parent) {
        base(parent);
        roots = new List<TreeNode>();
        all = new List<TreeNode>();
        pictures = null;
        native = WidgetSet.Current.CreateTreeView(this, ParentPeer());
        AttachPeer(native);
    }

    /// Adds a node at the top level and answers it.
    public TreeNode Add(String text, int image) {
        var made = new TreeNode(this, native.AddNode(null, null, text, image));
        roots.Add(made);
        all.Add(made);
        return made;
    }

    public TreeNode Add(String text) { return Add(text, -1); }

    /// Adds under an existing node. Called by `TreeNode.Add`.
    TreeNode Insert(TreeNode parent, String text, int image) {
        var made = new TreeNode(this, native.AddNode(parent.Handle(), null, text, image));
        all.Add(made);
        return made;
    }

    String TextOf(ITreeNodeHandle node) { return native.GetNodeText(node); }
    void SetTextOf(ITreeNodeHandle node, String text) { native.SetNodeText(node, text); }
    void SetExpanded(ITreeNodeHandle node, bool open) { native.Expand(node, open); }

    public List<TreeNode> Nodes => roots;

    public void Clear() {
        native.Clear();
        roots.Clear();
        all.Clear();
    }

    /// Which node is selected, or null.
    public TreeNode? SelectedNode {
        get {
            var chosen = native.GetSelectedNode();
            if (chosen == null) { return null; }
            return Lookup((ITreeNodeHandle)chosen);
        }
        set {
            if (value != null) { native.SelectNode(((TreeNode)value).Handle()); }
        }
    }

    /// The node a platform handle belongs to.
    ///
    /// **By identity, not by reference.** A backend asked which node is
    /// selected may wrap the answer in a fresh handle object each time, and
    /// this one does -- so comparing the references finds nothing and every
    /// selection reads back as null.
    ///
    /// A search rather than a table, because a tree small enough to be usable
    /// is a tree small enough to walk. A table would be the right answer for
    /// one with thousands of nodes, and so would virtual nodes.
    TreeNode? Lookup(ITreeNodeHandle handle) {
        nuint wanted = handle.Id();
        foreach (var node in all) {
            if (node.Handle().Id() == wanted) { return node; }
        }
        return null;
    }

    public ImageList? Images {
        get => pictures;
        set {
            pictures = value;
            if (value != null) { native.SetImages(((ImageList)value).Backend()); }
        }
    }

    /// The selection changed.
    public event EventHandler SelectedNodeChanged;

    protected virtual void OnSelectedNodeChanged() { SelectedNodeChanged(this); }

    public override void OnPlatformValueChanged() { OnSelectedNodeChanged(); }
}

// ================================================================ list view

/// A table of rows and columns.
///
/// **No `ListViewItem` object.** `TListItem` is a `TPersistent` with a
/// `SubItems: TStrings` hanging off it, so a table of a thousand rows is two
/// thousand objects before any text. Here a row is an index and its cells are
/// set through the list, which is what the platform stores anyway -- and what
/// C#'s virtual mode exists to get back to.
public class ListView : WindowedControl {
    IListViewPeer native;
    ListViewStyle showing;
    ImageList? pictures;

    public ListView(WindowedControl parent) {
        base(parent);
        showing = ListViewStyle.Details;
        pictures = null;
        native = WidgetSet.Current.CreateListView(this, ParentPeer());
        AttachPeer(native);
        native.SetFullRowSelect(true, false);
    }

    /// Adds a column and answers its index. Only a `Details` list shows them.
    public int AddColumn(String text, int width, HorizontalAlignment alignment) {
        return native.AddColumn(text, width, alignment);
    }

    public int AddColumn(String text, int width) {
        return AddColumn(text, width, HorizontalAlignment.Left);
    }

    public void SetColumnWidth(int column, int width) {
        native.SetColumnWidth(column, width);
    }

    /// Adds a row with its first cell, and answers the row's index.
    public int AddRow(String text, int image) { return native.AddRow(text, image); }
    public int AddRow(String text) { return AddRow(text, -1); }

    /// Sets a cell other than the first. Column zero is the row's own text.
    public void SetCell(int row, int column, String text) {
        native.SetCell(row, column, text);
    }

    /// Adds a row and fills every column of it.
    public int AddRow(String[] cells) {
        if (cells.Length == 0u) { return -1; }
        int row = AddRow(cells[0u], -1);
        for (nuint i = 1u; i < cells.Length; i += 1u) {
            SetCell(row, (int)i, cells[i]);
        }
        return row;
    }

    /// What one cell says, read from the control rather than remembered.
    ///
    /// Worth having beyond the obvious: it is the only way to tell that the
    /// text really arrived, which a row count cannot.
    public String CellText(int row, int column) {
        return native.GetCell(row, column);
    }

    public void RemoveRow(int row) { native.RemoveRow(row); }
    public void Clear() { native.Clear(); }
    public int Count => native.RowCount();

    /// Which row is selected, or -1.
    public int SelectedIndex {
        get => native.GetSelectedRow();
        set { native.SetSelectedRow(value); }
    }

    /// How the list shows what it holds.
    public ListViewStyle View {
        get => showing;
        set {
            showing = value;
            native.SetStyle(value);
        }
    }

    /// Whether clicking anywhere on a row selects the whole of it, and whether
    /// the grid is drawn.
    public void SetFullRowSelect(bool full, bool gridLines) {
        native.SetFullRowSelect(full, gridLines);
    }

    public ImageList? Images {
        get => pictures;
        set {
            pictures = value;
            if (value != null) { native.SetImages(((ImageList)value).Backend()); }
        }
    }

    /// The selection changed.
    public event EventHandler SelectedIndexChanged;

    protected virtual void OnSelectedIndexChanged() { SelectedIndexChanged(this); }

    public override void OnPlatformValueChanged() { OnSelectedIndexChanged(); }
}

// ==================================================================== coolbar

/// The two pixels between one band and the next, and between one row and the
/// next. `TCoolBand.cDivider`.
const int CoolDivider = 2;
/// How far in from a band's left edge its grab handle starts.
const int CoolGrabIndent = 2;

/// What a drag of the mouse over a cool bar is doing right now.
const int CoolDragNone = 0;
const int CoolDragMove = 1;
const int CoolDragResize = 2;

/// What `CoolBar.BandAt` answers for the empty space below the last row and
/// above the first: a band dropped there gets a row of its own.
const int CoolRowBelow = -1;
const int CoolRowAbove = -2;
/// And for a point that is over no band and neither of those.
const int CoolNowhere = -3;

/// How a `CoolBand`'s grab handle is drawn.
///
/// `TGrabStyle` has two more, `gsGripper` and `gsButton`, and both are a call
/// into `ThemeServices` for an element this library cannot draw yet. They are
/// left out rather than approximated, because a gripper drawn by hand is a
/// gripper that does not match the three real ones on the same screen.
public enum GrabberStyle { Simple, Double, HorizontalLines, VerticalLines }

/// One band of a `CoolBar`: a grab handle, an optional caption, and a control.
///
/// **A band is not a control.** It is a row entry that owns a rectangle and
/// points at a control which is an ordinary child of the cool bar -- so a
/// toolbar in a band is made with the cool bar as its parent and then handed
/// over, exactly as `TCoolBand.Control` works.
public class CoolBand {
    weak CoolBar? bar;
    Control? held;
    String   caption;
    bool     breaks;
    bool     shown;
    bool     fixedWidth;
    int      wanted;
    int      leastWide;
    int      leastHigh;
    Color    tint;
    bool     tinted;

    /// Where the layout pass put it. Read-only to a program, as in the LCL --
    /// a band's position is the cool bar's business.
    int placedLeft;
    int placedTop;
    int placedHeight;
    /// How wide it is *drawn*, which for the last band in a row is everything
    /// left over rather than `Width`. `TCoolBand.FRealWidth`.
    int drawnWidth;

    public CoolBand(CoolBar owner) {
        bar = owner;
        held = null;
        caption = "";
        breaks = true;
        shown = true;
        fixedWidth = false;
        wanted = 180;
        leastWide = 100;
        leastHigh = 25;
        tint = Colors.Transparent;
        tinted = false;
        placedLeft = 0;
        placedTop = 0;
        placedHeight = 0;
        drawnWidth = 0;
        owner.Register(this);
    }

    /// The control this band carries, or null for a band that is only a label.
    ///
    /// It must already be a child of the cool bar. Nothing here reparents it:
    /// a control chooses its parent once, at birth, which is the rule
    /// everywhere in this library.
    public Control? Control {
        get => held;
        set {
            held = value;
            Refresh();
        }
    }

    /// The caption drawn after the grab handle, when `CoolBar.ShowText` is on.
    public String Text {
        get => caption;
        set {
            caption = value;
            Refresh();
        }
    }

    /// Whether this band starts a new row rather than following the one before
    /// it. True by default, as `TCoolBand.Break` is -- a bar of bands each on
    /// its own row is what a program that set nothing should get.
    public bool Break {
        get => breaks;
        set {
            breaks = value;
            Refresh();
        }
    }

    public bool Visible {
        get => shown;
        set {
            shown = value;
            var one = held;
            if (one != null) { ((Control)one).Visible = value; }
            Refresh();
        }
    }

    /// Whether the user may drag this band's right edge. A fixed band is also
    /// one its neighbour cannot be resized against.
    public bool FixedSize {
        get => fixedWidth;
        set { fixedWidth = value; }
    }

    /// How wide the band asks to be. Never below `MinWidth`.
    public int Width {
        get => wanted;
        set {
            int now = value < leastWide ? leastWide : value;
            if (now == wanted) { return; }
            wanted = now;
            Refresh();
        }
    }

    public int MinWidth {
        get => leastWide;
        set {
            leastWide = value;
            if (wanted < leastWide) { wanted = leastWide; }
            Refresh();
        }
    }

    public int MinHeight {
        get => leastHigh;
        set {
            leastHigh = value;
            Refresh();
        }
    }

    /// The band's own background, or nothing set -- the default -- to use the
    /// cool bar's.
    public Color Color {
        get => tint;
        set {
            tint = value;
            tinted = true;
            Refresh();
        }
    }

    public bool HasColor => tinted;

    public int Left   => placedLeft;
    public int Top    => placedTop;
    public int Height => placedHeight;
    /// How wide it is drawn, which is `Width` except for the last band of a
    /// row, which is given whatever is left.
    public int DrawnWidth => drawnWidth;

    /// Widens the band to just fit its control, which is what double-clicking
    /// a grabber does in a real rebar and what `TCoolBand.AutosizeWidth` is.
    public void AutoSizeWidth() {
        CoolBar? owner = bar;
        if (owner == null) { return; }
        Width = ((CoolBar)owner).ContentLeft(this) + ControlWidth()
              + ((CoolBar)owner).HorizontalSpacing + CoolDivider;
    }

    int ControlWidth() {
        var one = held;
        return one == null ? 0 : ((Control)one).Width;
    }

    /// Called by the cool bar's layout pass, and by nothing else.
    public void PlaceAt(int left, int top, int height, int drawn) {
        placedLeft = left;
        placedTop = top;
        placedHeight = height;
        drawnWidth = drawn;
    }

    void Refresh() {
        CoolBar? owner = bar;
        if (owner != null) { ((CoolBar)owner).Rebuild(); }
    }
}

/// A bar of bands, each holding a control the user can move and resize.
///
/// **Nothing about this is a platform control, on either platform.** Windows
/// has `REBARCLASSNAME`, and the LCL does not use it: `TCoolBar` is drawn from
/// nothing in `coolbar.inc`, and the GTK 3 widgetset does not mention a cool
/// bar at all. So this is a `CustomControl` that paints bands and places the
/// controls in them, which is what `TCustomCoolBar` is.
///
/// ```
/// var bar = new CoolBar(this);
/// bar.Dock = DockStyle.Top;
///
/// var tools = new ToolBar(bar);
/// var first = new CoolBand(bar);
/// first.Text = "Tools";
/// first.Control = tools;
///
/// var box = new ComboBox(bar);
/// var second = new CoolBand(bar);
/// second.Text = "Zoom";
/// second.Break = false;     // share the row with the band before it
/// second.Control = box;
/// ```
///
/// **Bands wrap into rows and the wrap is recomputed on every resize**, which
/// is the behaviour that makes a cool bar worth having and the reason its
/// height is not a number a program sets. `PreferredSize` answers how tall the
/// rows came out; a program that wants the bar to fit assigns that to `Height`
/// after building it, or docks it and lets `AutoSize` do it.
///
/// **What is not here.** `Vertical` -- a cool bar down the side of a window --
/// is every coordinate in this file mirrored, and `TCustomCoolBar` pays for it
/// with an `if Vertical` in each of forty places; it is left out rather than
/// half done. So is right-to-left, for the same reason, and so are the two
/// themed grab styles.
public class CoolBar : CustomControl {
    List<CoolBand>? bands;
    /// The visible ones, in order, rebuilt by every layout pass. Held rather
    /// than recomputed per hit-test because the paint, the mouse and the layout
    /// all walk the same list and must agree about it.
    List<CoolBand>? visible;

    GrabberStyle grabbing;
    int         grabWide;
    int         acrossGap;
    int         downGap;
    bool        text;
    bool        fixedWidths;
    bool        fixedOrder;
    ImageList?  pictures;

    int  dragging;
    int  draggedBand;
    int  dragFrom;
    int  rowsHigh;
    bool ready;

    public CoolBar(WindowedControl parent) {
        base(parent);
        bands = new List<CoolBand>();
        visible = new List<CoolBand>();
        grabbing = GrabberStyle.Double;
        grabWide = 10;
        acrossGap = 5;
        downGap = 3;
        text = true;
        fixedWidths = false;
        fixedOrder = false;
        pictures = null;
        dragging = CoolDragNone;
        draggedBand = CoolNowhere;
        dragFrom = 0;
        rowsHigh = 0;

        // A cool bar takes no keystrokes, so it stays out of the tab order --
        // the controls *in* it are what the keyboard reaches, and they are
        // ordinary children with windows of their own.
        Focusable = false;
        Dock = DockStyle.Top;
        Height = 34;

        ready = true;
        Rebuild();
    }

    /// Called by a `CoolBand` as it is built. Not public: a band joins the bar
    /// it was constructed with, and there is no other way in.
    public void Register(CoolBand band) {
        var held = bands;
        if (held == null) { return; }
        ((List<CoolBand>)held).Add(band);
        Rebuild();
    }

    public List<CoolBand> Bands {
        get {
            var held = bands;
            if (held == null) { return new List<CoolBand>(); }
            return (List<CoolBand>)held;
        }
    }

    public int BandCount => (int)Bands.Count();

    /// How the grab handles are drawn.
    public GrabberStyle GrabStyle {
        get => grabbing;
        set {
            grabbing = value;
            Invalidate();
        }
    }

    /// How wide a grab handle is.
    public int GrabWidth {
        get => grabWide;
        set {
            grabWide = value;
            Rebuild();
        }
    }

    /// Pixels between a band's parts -- the handle, the caption, the control.
    public int HorizontalSpacing {
        get => acrossGap;
        set {
            acrossGap = value;
            Rebuild();
        }
    }

    /// Pixels above and below a band's control, which is what makes a row
    /// taller than the tallest thing in it.
    public int VerticalSpacing {
        get => downGap;
        set {
            downGap = value;
            Rebuild();
        }
    }

    /// Whether a band's `Text` is drawn.
    public bool ShowText {
        get => text;
        set {
            text = value;
            Rebuild();
        }
    }

    /// Whether any band may be resized by dragging. Overrides every band's own
    /// `FixedSize`, which is what `TCustomCoolBar.FixedSize` does.
    public bool FixedSize {
        get => fixedWidths;
        set { fixedWidths = value; }
    }

    /// Whether the bands may be dragged into a different order.
    public bool FixedOrder {
        get => fixedOrder;
        set { fixedOrder = value; }
    }

    /// The pictures a band's `ImageIndex` names. Declared so that a band that
    /// wants an icon has somewhere to get one; nothing draws one yet.
    public ImageList? Images {
        get => pictures;
        set {
            pictures = value;
            Invalidate();
        }
    }

    /// One band was moved or resized by the user. Not raised for a change a
    /// program made, as `TCustomCoolBar.OnChange` is not.
    public event EventHandler Change;

    protected virtual void OnChange() { Change(this); }

    // -------------------------------------------------------------- layout

    /// How tall the bar came out: every row's height, plus the dividers between
    /// them. What a program assigns to `Height` after building the bands.
    public override Size PreferredSize => Size.Of(0, rowsHigh);

    /// Where a band's control begins, measured from the band's left edge: past
    /// the handle, the caption and the gaps between them.
    /// `TCoolBand.CalcControlLeft`.
    public int ContentLeft(CoolBand band) {
        int at = CoolGrabIndent + grabWide + acrossGap;
        int bare = at;
        if (text && !band.Text.IsEmpty()) {
            at = at + TextWidth(band.Text) + acrossGap;
        }
        // A band with no caption still gets one gap, so its control does not
        // sit against the handle.
        if (at == bare) { at = at + acrossGap; }
        return at;
    }

    /// How wide a caption is.
    ///
    /// **Measured against the font and not against a surface**, because there
    /// is no `Graphics` outside a paint and the layout pass runs long before
    /// one exists. Seven pixels per character is what a proportional UI font
    /// averages at the sizes a cool bar uses; the cost of being wrong is a
    /// caption a few pixels from where the control starts, and the cost of
    /// being right would be keeping a measuring surface alive for the life of
    /// the control.
    int TextWidth(String caption) { return (int)caption.ByteLength() * 7; }

    /// How tall one band wants to be: its own minimum, its control plus the
    /// vertical spacing, and the caption -- whichever is largest.
    /// `TCoolBand.CalcPreferredHeight`.
    int BandHeight(CoolBand band) {
        int high = band.MinHeight;
        var one = band.Control;
        if (one != null) {
            int wanted = ((Control)one).Height + 2 * downGap;
            if (wanted > high) { high = wanted; }
        }
        if (text) {
            int wanted = Font.Size + 4 + 2 * downGap;
            if (wanted > high) { high = wanted; }
        }
        return high;
    }

    /// Whether the band after this one will not fit beside it.
    bool WrapsAfter(List<CoolBand> row, nuint index, int left) {
        if (index + 1u >= row.Count()) { return false; }
        var next = row.At(index + 1u);
        if (next.Break) { return true; }
        return left + next.Width - CoolDivider >= Width;
    }

    /// Recomputes the rows, places every band and every band's control, and
    /// repaints.
    ///
    /// **Two passes, because a row's height is not known until the row ends.**
    /// Every band in a row is drawn the same height -- the tallest of them --
    /// so the first pass finds the wraps and the heights and the second places
    /// things. `TCustomCoolBar.CalculateAndAlign` does exactly this and for
    /// exactly this reason.
    public void Rebuild() {
        if (!ready) { return; }

        var all = Bands;
        var showing = new List<CoolBand>();
        for (nuint i = 0u; i < all.Count(); i += 1u) {
            if (all.At(i).Visible) { showing.Add(all.At(i)); }
        }
        visible = showing;

        // ---- pass one: where the rows break, and how tall each is.
        var heights = new int[showing.Count()];
        int tallest = 0;
        nuint rowStart = 0u;
        int left = 0;
        bool rowEnd = true;

        for (nuint i = 0u; i < showing.Count(); i += 1u) {
            if (rowEnd || showing.At(i).Break) { left = 0; }
            int wanted = BandHeight(showing.At(i));
            if (wanted > tallest) { tallest = wanted; }
            left = left + showing.At(i).Width;

            rowEnd = i + 1u >= showing.Count() || WrapsAfter(showing, i, left);
            if (!rowEnd) { continue; }

            for (nuint y = rowStart; y <= i; y += 1u) { heights[y] = tallest; }
            tallest = 0;
            rowStart = i + 1u;
        }

        // ---- pass two: place the bands and the controls in them.
        int top = 0;
        left = 0;
        rowEnd = true;

        for (nuint i = 0u; i < showing.Count(); i += 1u) {
            var band = showing.At(i);
            if (rowEnd || band.Break) { left = 0; }

            int height = heights[i];
            int width = band.Width;
            rowEnd = WrapsAfter(showing, i, left + width) || i + 1u >= showing.Count();
            // The last band of a row is drawn out to the far edge, whatever
            // width it asked for -- otherwise every row would end in a gap the
            // user could not fill.
            int drawn = rowEnd ? Width - left : width;
            if (drawn < width) { drawn = width; }

            band.PlaceAt(left, top, height, drawn);

            var one = band.Control;
            if (one != null) {
                var child = (Control)one;
                int contentLeft = left + ContentLeft(band);
                int room = drawn - ContentLeft(band) - acrossGap - CoolDivider;
                if (room < 0) { room = 0; }
                child.SetBounds(contentLeft, top + (height - child.Height) / 2,
                                room, child.Height);
            }

            left = left + width;
            if (rowEnd) { top = top + height + CoolDivider; }
        }

        rowsHigh = top;
        Invalidate();
    }

    /// A resize changes where the rows wrap, so the whole layout is redone.
    ///
    /// The null test is the trap the composites all have: the base constructor
    /// resizes, and this override runs before this class's own fields exist.
    protected override void OnResize() {
        base.OnResize();
        if (bands == null) { return; }
        Rebuild();
    }

    List<CoolBand> Showing {
        get {
            var held = visible;
            if (held == null) { return new List<CoolBand>(); }
            return (List<CoolBand>)held;
        }
    }

    // ------------------------------------------------------------- painting

    protected override void OnPaint(PaintEventArgs args) {
        var surface = args.Graphics;
        surface.Clear(BackColor);

        var showing = Showing;
        var light = new Pen(SystemColors.ControlLight);
        var dark = new Pen(SystemColors.ControlDark);

        for (nuint i = 0u; i < showing.Count(); i += 1u) {
            var band = showing.At(i);
            var whole = Rectangle.Of(band.Left, band.Top, band.DrawnWidth, band.Height);

            if (band.HasColor) { surface.FillRectangle(new Brush(band.Color), whole); }

            PaintGrabber(surface, light, dark,
                         Rectangle.Of(band.Left + CoolGrabIndent, band.Top + 2,
                                      grabWide - 1, band.Height - 5));

            if (text && !band.Text.IsEmpty()) {
                int x = band.Left + CoolGrabIndent + grabWide + acrossGap;
                var measured = surface.MeasureString(band.Text, Font);
                int y = band.Top + (band.Height - measured.Height) / 2;
                surface.DrawString(band.Text, Font, ForeColor, x, y);
            }

            bool last = i + 1u >= showing.Count();
            bool endsRow = last || showing.At(i + 1u).Top != band.Top;

            if (endsRow) {
                // The line under a finished row, which is what separates one
                // row from the next and the last row from the client area.
                int y = band.Top + band.Height;
                surface.DrawLine(dark, 0, y, Width, y);
                surface.DrawLine(light, 0, y + 1, Width, y + 1);
            } else {
                // The upright between two bands sharing a row.
                int x = band.Left + band.DrawnWidth;
                surface.DrawLine(dark, x, band.Top + 1, x, band.Top + band.Height - 1);
                surface.DrawLine(light, x + 1, band.Top + 1, x + 1,
                                 band.Top + band.Height - 1);
            }
        }

        base.OnPaint(args);
    }

    /// The grab handle, in whichever of the four styles is set.
    void PaintGrabber(Graphics surface, Pen light, Pen dark, Rectangle at) {
        if (at.Width <= 0 || at.Height <= 0) { return; }
        int left = at.X;
        int top = at.Y;
        int right = at.X + at.Width;
        int bottom = at.Y + at.Height;

        if (grabbing == GrabberStyle.Simple) {
            surface.DrawLine(light, left, top, right, top);
            surface.DrawLine(light, left, top, left, bottom);
            surface.DrawLine(dark, left, bottom, right, bottom);
            surface.DrawLine(dark, right, top, right, bottom);
            return;
        }

        if (grabbing == GrabberStyle.Double) {
            // Two narrow raised bars side by side, which is the default and the
            // one a Windows rebar draws.
            int half = (grabWide - 2) / 2;
            if (half < 1) { half = 1; }
            surface.DrawLine(light, left, top, left + half, top);
            surface.DrawLine(light, left, top, left, bottom);
            surface.DrawLine(dark, left, bottom, left + half, bottom);
            surface.DrawLine(dark, left + half, top, left + half, bottom);

            surface.DrawLine(light, right - half, top, right, top);
            surface.DrawLine(light, right - half, top, right - half, bottom);
            surface.DrawLine(dark, right - half, bottom, right, bottom);
            surface.DrawLine(dark, right, top, right, bottom);
            return;
        }

        if (grabbing == GrabberStyle.HorizontalLines) {
            int lines = (at.Height + 1) / 3;
            for (int w = 0; w < lines; w += 1) {
                int y = top + 1 + w * 3;
                surface.DrawLine(dark, left, y, right, y);
                surface.DrawLine(light, left, y + 1, right, y + 1);
            }
            return;
        }

        int columns = (at.Width + 1) / 3;
        for (int w = 0; w < columns; w += 1) {
            int x = left + 1 + w * 3;
            surface.DrawLine(dark, x, top, x, bottom);
            surface.DrawLine(light, x + 1, top, x + 1, bottom);
        }
    }

    // ---------------------------------------------------------- the mouse

    /// Which band a point is over, and whether it is over that band's grab
    /// handle. `TCustomCoolBar.MouseToBandPos`, with its two sentinels: a point
    /// below the last row or above the first is where a band dropped gets a row
    /// of its own.
    (int, bool) BandAt(Point at) {
        var showing = Showing;
        if (showing.IsEmpty()) { return (CoolNowhere, false); }

        var last = showing.At(showing.Count() - 1u);
        if (at.Y > last.Top + last.Height + CoolDivider) { return (CoolRowBelow, false); }
        if (at.Y < 0) { return (CoolRowAbove, false); }

        for (nuint i = 0u; i < showing.Count(); i += 1u) {
            var band = showing.At(i);
            var whole = Rectangle.Of(band.Left, band.Top, band.DrawnWidth, band.Height);
            if (!whole.Contains(at)) { continue; }
            return ((int)i, at.X <= band.Left + grabWide + 1);
        }
        return (CoolNowhere, false);
    }

    /// Whether this band is the first of its row, which is the one whose
    /// handle cannot resize anything: there is no band to its left to take the
    /// pixels from.
    bool FirstOfRow(int index) {
        var showing = Showing;
        if (index <= 0) { return true; }
        return showing.At((nuint)index).Top != showing.At((nuint)(index - 1)).Top;
    }

    protected override void OnMouseDown(MouseEventArgs args) {
        base.OnMouseDown(args);
        if (args.Button != MouseButton.Left) { return; }

        var found = BandAt(args.Location);
        int index = found.Item1;
        bool onGrabber = found.Item2;
        draggedBand = index;
        dragging = CoolDragNone;
        if (index < 0) { return; }

        var showing = Showing;
        if (onGrabber && !FirstOfRow(index) && !fixedWidths
            && !showing.At((nuint)index).FixedSize
            && !showing.At((nuint)(index - 1)).FixedSize) {
            // Dragging a handle resizes the band to its *left*, which is the
            // one whose right edge the handle sits against.
            dragging = CoolDragResize;
            var before = showing.At((nuint)(index - 1));
            dragFrom = args.X - before.Width - before.Left;
            CaptureMouse(true);
            return;
        }

        if (!fixedOrder) {
            dragging = CoolDragMove;
            CaptureMouse(true);
        }
    }

    protected override void OnMouseMove(MouseEventArgs args) {
        base.OnMouseMove(args);
        var showing = Showing;
        if (showing.IsEmpty()) { return; }

        if (dragging == CoolDragResize) {
            var before = showing.At((nuint)(draggedBand - 1));
            before.Width = args.X - dragFrom - before.Left;
            return;
        }

        if (dragging == CoolDragMove) { return; }

        // Nothing is being dragged, so the cursor says what a drag would do.
        var found = BandAt(args.Location);
        int index = found.Item1;
        bool onGrabber = found.Item2;
        if (index < 0) { Cursor = CursorKind.Default; return; }

        if (onGrabber && index > 0 && !FirstOfRow(index) && !fixedWidths
            && !showing.At((nuint)index).FixedSize
            && !showing.At((nuint)(index - 1)).FixedSize) {
            Cursor = CursorKind.SizeWestEast;
        } else if (!fixedOrder && showing.Count() > 1u) {
            Cursor = CursorKind.SizeAll;
        } else {
            Cursor = CursorKind.Default;
        }
    }

    protected override void OnMouseUp(MouseEventArgs args) {
        base.OnMouseUp(args);
        int was = dragging;
        int dragged = draggedBand;
        dragging = CoolDragNone;
        draggedBand = CoolNowhere;
        Cursor = CursorKind.Default;

        if (was == CoolDragNone) { return; }
        CaptureMouse(false);

        if (was == CoolDragResize) {
            OnChange();
            return;
        }

        if (dragged < 0) { return; }
        if (Drop(dragged, args.Location)) {
            Rebuild();
            OnChange();
        }
    }

    /// Moves the dragged band to where it was dropped, and answers whether
    /// anything changed.
    ///
    /// **Three cases, which is the whole of `TCustomCoolBar.MouseUp`'s long
    /// branch.** Dropped above the first row or below the last, the band gets a
    /// row of its own -- it is moved to that end of the list and told to break.
    /// Dropped past the right-hand end of a row, it goes after that row's last
    /// band and does *not* break, so it joins the row. Dropped on another band,
    /// it takes that band's place and inherits whether the place breaks a row.
    bool Drop(int dragged, Point at) {
        var showing = Showing;
        if ((nuint)dragged >= showing.Count()) { return false; }
        var moving = showing.At((nuint)dragged);

        var found = BandAt(at);
        int onto = found.Item1;
        if (onto == CoolNowhere) { return false; }

        // A band that broke a row and is leaving it must hand the break to
        // whoever now begins that row, or the row above swallows it.
        if (moving.Break && (nuint)(dragged + 1) < showing.Count()) {
            showing.At((nuint)(dragged + 1)).Break = true;
        }

        if (onto == CoolRowAbove) {
            if (dragged == 0) { return false; }
            moving.Break = true;
            return MoveTo(moving, 0);
        }

        if (onto == CoolRowBelow) {
            moving.Break = true;
            return MoveTo(moving, (int)Bands.Count() - 1);
        }

        if (onto == dragged) { return false; }

        var target = showing.At((nuint)onto);
        bool pastEnd = at.X > target.Left + target.DrawnWidth;

        if (pastEnd) {
            // Joining the end of the target's row.
            moving.Break = false;
            int after = dragged > onto ? onto + 1 : onto;
            return MoveTo(moving, RealIndexOf(showing, after));
        }

        moving.Break = target.Break;
        if (dragged > onto) {
            // Moving left or up: the band it landed on stops beginning the row,
            // because the dropped one now does.
            target.Break = false;
            return MoveTo(moving, RealIndexOf(showing, onto));
        }

        // Moving right or down.
        if (showing.At((nuint)dragged).Top == target.Top) {
            moving.Break = false;
            return MoveTo(moving, RealIndexOf(showing, onto));
        }
        target.Break = false;
        return MoveTo(moving, RealIndexOf(showing, onto - 1));
    }

    /// The position in `Bands` of the nth visible band. The two lists differ
    /// whenever a band is hidden, and every move is expressed in visible terms
    /// and applied in real ones.
    int RealIndexOf(List<CoolBand> showing, int visibleIndex) {
        if (visibleIndex < 0) { return 0; }
        if ((nuint)visibleIndex >= showing.Count()) {
            return (int)Bands.Count() - 1;
        }
        var wanted = showing.At((nuint)visibleIndex);
        var all = Bands;
        for (nuint i = 0u; i < all.Count(); i += 1u) {
            if (all.At(i) == wanted) { return (int)i; }
        }
        return 0;
    }

    /// Takes a band out of the list and puts it back at another position.
    bool MoveTo(CoolBand band, int index) {
        var all = Bands;
        nuint from = 0u;
        bool found = false;
        for (nuint i = 0u; i < all.Count(); i += 1u) {
            if (all.At(i) == band) { from = i; found = true; break; }
        }
        if (!found) { return false; }

        int to = index;
        if (to < 0) { to = 0; }
        if ((nuint)to >= all.Count()) { to = (int)all.Count() - 1; }
        if ((nuint)to == from) { return false; }

        all.RemoveAt(from);
        all.Insert((nuint)to, band);
        return true;
    }
}
