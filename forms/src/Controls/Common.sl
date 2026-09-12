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
