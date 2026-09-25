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
#if FORMS_REFLECT
import Standard.Reflection;
#endif

// ================================================================ image list

/// Same-sized pictures, kept once and referred to by number.
///
/// A toolbar, a tree and a list take their icons from one of these rather than
/// holding pictures of their own -- the control stores an index and the list
/// stores the picture, which is how every platform arranges it and why one
/// image list can dress several controls.
public class ImageList
{
    IImageListBackend _backend;
    List<Bitmap> _kept;

    public ImageList(int width, int height)
    {
        _backend = WidgetSet.Current.CreateImageList(Size.FromDimensions(width, height));
        _kept = new List<Bitmap>();
    }

    /// 16x16, which is what a toolbar and a tree use.
    public ImageList() => this(16, 16);

    /// Adds a picture and answers its index, or -1 if the platform refused it.
    ///
    /// The `Bitmap` is kept, because the platform copied the pixels but the
    /// caller has no reason to expect that and every reason to drop the object.
    public int Add(Bitmap picture)
    {
        int at = _backend.Add(picture.Backend);
        if (at >= 0)
            _kept.Add(picture);
        return at;
    }

    /// Loads a picture and adds it. The error names the file rather than
    /// answering -1, because a missing icon is a mistake worth reading about.
    public Result<int, String> AddFile(String path)
    {
        var loaded = Bitmap.FromFile(path);
        if (!loaded.Ok)
            return Fail(loaded.Error);
        return Ok(Add(loaded.Value));
    }

    /// Adds a picture out of the program's own resources, by the id its
    /// resource script gave it.
    ///
    /// The usual way to dress a toolbar, because the icons are part of the
    /// program rather than part of its data: nothing to install beside the
    /// executable and nothing to find at startup. Windows only -- see
    /// `Bitmap.FromResource`, whose error this passes on.
    public Result<int, String> AddResource(int id)
    {
        var loaded = Bitmap.FromResource(id);
        if (!loaded.Ok)
            return Fail(loaded.Error);
        return Ok(Add(loaded.Value));
    }

    public int Count => _backend.Count;
    public Size ImageSize => _backend.ImageSize;

    /// The picture at an index, or null if there is none there.
    ///
    /// **The list was already keeping these**, to stop a caller's `Bitmap`
    /// being collected out from under a platform that copied the pixels. That
    /// they can be handed back is what lets a renderer draw a toolbar button
    /// itself: the alternative is reaching through `Backend.Handle` to an
    /// `HIMAGELIST` and calling `ImageList_Draw`, which would put a Win32 call
    /// in a class that is meant to have none.
    public Bitmap? GetImage(int index)
    {
        if (index < 0 || (nuint)index >= _kept.Count)
            return null;
        return _kept[(nuint)index];
    }

    /// The platform's list, for the controls that take one.
    public IImageListBackend Backend => _backend;
}

// =================================================================== toolbar

/// One button on a toolbar.
///
/// **Not a `Control`.** `TToolButton` is a `TGraphicControl` with a position
/// and a parent, which lets the LCL's designer drag one about and costs every
/// button an object the platform knows nothing about -- a Windows toolbar owns
/// its buttons and lays them out itself. This is a handle on one of those: an
/// index, a caption and a `Click`.
public class ToolButton
{
    weak ToolBar? _bar;
    int _index;
    String _text;
    int _image;
    ToolButtonKind _kind;

    bool _enabled;

    public ToolButton(ToolBar owner, int at, String text, int image,
                      ToolButtonKind kind)
    {
        _bar = owner;
        _index = at;
        _text = text;
        _image = image;
        _kind = kind;
        _enabled = true;
    }

    /// Where it sits on the bar, counting separators.
    public int Index => _index;

    /// The caption, exactly as it was given -- accelerator markers and all,
    /// since it is the platform that eats those and the platform that draws
    /// the underline.
    ///
    /// **Kept here as well as in the toolbar**, which is a duplicate worth
    /// having: comctl32 owns the string it draws, and asking for it back means
    /// `TB_GETBUTTONTEXTW` twice per button per paint -- once for the length
    /// and once for the text -- into a buffer, during a paint.
    public String Text => _text;

    /// Which picture in the bar's image list, or -1 for none.
    public int Image => _image;

    /// A gap between groups rather than something that can be pressed.
    public bool IsSeparator => _kind == ToolButtonKind.Separator;

    /// This button's picture, or null if it has none or the bar has no list.
    public Bitmap? Picture
    {
        get
        {
            if (_image < 0)
                return null;
            ToolBar? owner = _bar;
            if (owner == null)
                return null;
            ImageList? pictures = ((ToolBar)owner).Images;
            if (pictures == null)
                return null;
            return ((ImageList)pictures).GetImage(_image);
        }
    }

    /// Whether the bar is drawing captions at all, which is the bar's setting
    /// and not this button's.
    public bool ShowsText
    {
        get
        {
            ToolBar? owner = _bar;
            if (owner == null)
                return false;
            return ((ToolBar)owner).ShowText;
        }
    }

    public bool Enabled
    {
        get => _enabled;
        set
        {
            _enabled = value;
            // A weak reference is never narrowed, so it goes into a strong
            // local first.
            ToolBar? owner = _bar;
            if (owner != null)
                ((ToolBar)owner).SetButtonEnabled(_index, value);
        }
    }

    /// Whether a toggle button is pressed in. Meaningless on a plain one.
    public bool Checked
    {
        get
        {
            ToolBar? owner = _bar;
            if (owner == null)
                return false;
            return ((ToolBar)owner).GetButtonChecked(_index);
        }
        set
        {
            ToolBar? owner = _bar;
            if (owner != null)
                ((ToolBar)owner).SetButtonChecked(_index, value);
        }
    }

    /// The button was pressed.
    public event EventHandler Click;

    /// Raised by the bar, which is what the platform reports to.
    public void RaiseClick(Control sender) => Click(sender);

    /// What the platform calls this button, on the same terms as
    /// `MenuItem.PlatformId`.
    public nuint PlatformId
    {
        get
        {
            ToolBar? owner = _bar;
            if (owner == null)
                return 0u;
            return ((ToolBar)owner).GetButtonId(_index);
        }
    }
}

/// A row of buttons.
public class ToolBar : WindowedControl
{
    IToolBarPeer _native;
    List<ToolButton> _buttons;
    ImageList? _images;
    bool _showText;
    ChromeRenderer _renderer;

    public ToolBar(WindowedControl parent)
    {
        base(parent);
        _buttons = new List<ToolButton>();
        _images = null;
        _showText = true;
        _renderer = new SystemChromeRenderer();
        _native = WidgetSet.Current.CreateToolBar(this, ParentPeer);
        AttachPeer(_native);
    }

    /// What draws the buttons. The platform's own, unless a program says
    /// otherwise -- the same default, and the same reason for it, as
    /// `Menu.Renderer`.
    ///
    /// Setting it is a request: a backend that will not hand its buttons over
    /// says so, and the bar goes on being native. Whether it did is
    /// `IsOwnerDrawn`.
    public ChromeRenderer Renderer
    {
        get => _renderer;
        set
        {
            _renderer = value;
            _isOwnerDrawn = _native.SetOwnerDrawn(value.IsOwnerDrawn);
            Invalidate();
        }
    }

    bool _isOwnerDrawn;

    /// Whether the platform actually handed the buttons over.
    ///
    /// **A renderer being set is not the same as it being used**, and the
    /// difference is worth a property rather than an assumption: on GTK the
    /// answer is always false. Read it in a self test and it says the request
    /// was made and granted -- it does not say anything reached the screen,
    /// which is what a screenshot is for.
    public bool IsOwnerDrawn => _isOwnerDrawn;

    /// Adds a button and answers it, so a handler can be attached to the result.
    public ToolButton Add(String text, int image)
    {
        int at = _native.AddButton(text, image, ToolButtonKind.Button);
        var made = new ToolButton(this, at, text, image, ToolButtonKind.Button);
        _buttons.Add(made);
        _native.ResizeToFit();
        return made;
    }

    public ToolButton Add(String text) => Add(text, -1);

    /// A button that stays pressed until pressed again.
    public ToolButton AddToggle(String text, int image)
    {
        int at = _native.AddButton(text, image, ToolButtonKind.Toggle);
        var made = new ToolButton(this, at, text, image, ToolButtonKind.Toggle);
        _buttons.Add(made);
        _native.ResizeToFit();
        return made;
    }

    /// A gap between groups of buttons. Answers nothing: a separator has no
    /// state and nothing to handle.
    public void AddSeparator()
    {
        int at = _native.AddButton("", -1, ToolButtonKind.Separator);
        _buttons.Add(new ToolButton(this, at, "", -1, ToolButtonKind.Separator));
        _native.ResizeToFit();
    }

    public List<ToolButton> Buttons => _buttons;

    /// Where the buttons' pictures come from.
    public ImageList? Images
    {
        get => _images;
        set
        {
            _images = value;
            _native.SetImages(value == null ? null : ((ImageList)value).Backend);
            _native.ResizeToFit();
        }
    }

    /// Whether a caption is shown beside each picture.
    public bool ShowText
    {
        get => _showText;
        set
        {
            _showText = value;
            _native.SetTextVisible(value);
        }
    }

    nuint GetButtonId(int index) => _native.GetButtonId(index);
    void SetButtonEnabled(int index, bool enabled) => _native.SetButtonEnabled(index, enabled);
    void SetButtonChecked(int index, bool checked) => _native.SetButtonChecked(index, checked);
    bool GetButtonChecked(int index) => _native.GetButtonChecked(index);

    public override Size PreferredSize => _native.PreferredSize;

    /// The platform says which button; the bar turns that into the button's own
    /// event, so a program never handles "a click on the toolbar" and then
    /// works out which one it was.
    public override void OnPlatformToolClicked(int index)
    {
        if (index < 0 || (nuint)index >= _buttons.Count)
            return;
        _buttons[(nuint)index].RaiseClick(this);
    }

    public override bool OnPlatformDrawToolBackground(Graphics surface,
                                                      Rectangle bounds)
    {
        if (!_isOwnerDrawn)
            return false;
        _renderer.DrawToolBackground(surface, bounds);
        return true;
    }

    public override bool OnPlatformDrawTool(Graphics surface, Rectangle bounds,
                                            int index, ToolItemState state)
    {
        if (!_isOwnerDrawn || index < 0 || (nuint)index >= _buttons.Count)
            return false;
        _renderer.DrawToolButton(surface, _buttons[(nuint)index], bounds, state);
        return true;
    }
}

// =============================================================== status bar

/// The strip along the bottom, divided into panels.
public class StatusBar : WindowedControl
{
    IStatusBarPeer _native;
    List<String> _texts;
    List<int> _widths;

    public StatusBar(WindowedControl parent)
    {
        base(parent);
        _texts = new List<String>();
        _widths = new List<int>();
        _native = WidgetSet.Current.CreateStatusBar(this, ParentPeer);
        AttachPeer(_native);
        Dock = DockStyle.Bottom;
    }

    /// Adds a panel and answers its index. A width of -1 means "the rest of the
    /// bar", and only the last panel should have one.
    public int AddPanel(int width)
    {
        _widths.Add(width);
        _texts.Add("");
        RebuildPanels();
        return (int)_widths.Count - 1;
    }

    /// What a panel says.
    public String GetPanelText(int index)
    {
        if (index < 0 || (nuint)index >= _texts.Count)
            return "";
        return _texts[(nuint)index];
    }

    public void SetPanelText(int index, String text)
    {
        if (index < 0 || (nuint)index >= _texts.Count)
            return;
        _texts[(nuint)index] = text;
        _native.SetPanelText(index, text);
    }

    public nuint PanelCount => _widths.Count;

    /// Turns the panel widths into the running edges Windows wants.
    ///
    /// The platform takes the right-hand edge of each panel rather than its
    /// width, which is one subtraction nobody should have to remember -- so the
    /// widths are what a program gives and this is where they become edges.
    void RebuildPanels()
    {
        var edges = new int[_widths.Count];
        int running = 0;
        for (nuint i = 0u; i < _widths.Count; i++)
        {
            int width = _widths[i];
            if (width < 0)
            {
                edges[i] = -1;
            }
            else
            {
                running = running + width;
                edges[i] = running;
            }
        }
        _native.SetPanels(edges);
        for (nuint i = 0u; i < _texts.Count; i++)
        {
            _native.SetPanelText((int)i, _texts[i]);
        }
    }

    public override Size PreferredSize => _native.PreferredSize;
}

// ============================================================= progress bar

/// `value` pulled into `low` to `high`. What every control with a range does
/// to a value set outside it, since the platforms differ about whether they
/// do it themselves.
int ClampToRange(int value, int low, int high)
{
    if (value < low)
        return low;
    if (value > high)
        return high;
    return value;
}

/// How far along something is.
#if FORMS_REFLECT
[Reflect]
#endif
public class ProgressBar : WindowedControl
{
    IProgressPeer _native;
    int _minimum;
    int _maximum;
    bool _indeterminate;

    public ProgressBar(WindowedControl parent)
    {
        base(parent);
        _minimum = 0;
        _maximum = 100;
        _indeterminate = false;
        _native = WidgetSet.Current.CreateProgress(this, ParentPeer);
        AttachPeer(_native);
    }

    /// Raises `Maximum` when set above it.
    public int Minimum
    {
        get => _minimum;
        set
        {
            _minimum = value;
            if (_maximum < value)
                _maximum = value;
            ApplyRange();
        }
    }

    /// Lowers `Minimum` when set below it.
    public int Maximum
    {
        get => _maximum;
        set
        {
            _maximum = value;
            if (_minimum > value)
                _minimum = value;
            ApplyRange();
        }
    }

    /// Kept inside the range.
    public int Value
    {
        get => _native.GetValue();
        set => _native.SetValue(ClampToRange(value, _minimum, _maximum));
    }

    void ApplyRange()
    {
        _native.SetRange(_minimum, _maximum);
        int now = _native.GetValue();
        int kept = ClampToRange(now, _minimum, _maximum);
        if (kept != now)
            _native.SetValue(kept);
    }

    /// A bar that moves without saying how far along it is, for work whose
    /// length is unknown. C#'s `ProgressBarStyle.Marquee` under a plainer name.
    public bool Indeterminate
    {
        get => _indeterminate;
        set
        {
            _indeterminate = value;
            _native.SetIndeterminate(value);
        }
    }
}

// ================================================================ track bar

/// A slider.
#if FORMS_REFLECT
[Reflect]
#endif
public class TrackBar : WindowedControl
{
    ITrackBarPeer _native;
    int _minimum;
    int _maximum;
    int _tickFrequency;

    public TrackBar(WindowedControl parent, bool vertical)
    {
        base(parent);
        _minimum = 0;
        _maximum = 100;
        _tickFrequency = 10;
        _native = WidgetSet.Current.CreateTrackBar(this, ParentPeer, vertical);
        AttachPeer(_native);
    }

    public TrackBar(WindowedControl parent) => this(parent, false);

    /// Raises `Maximum` when set above it.
    public int Minimum
    {
        get => _minimum;
        set
        {
            _minimum = value;
            if (_maximum < value)
                _maximum = value;
            ApplyRange();
        }
    }

    /// Lowers `Minimum` when set below it.
    public int Maximum
    {
        get => _maximum;
        set
        {
            _maximum = value;
            if (_minimum > value)
                _minimum = value;
            ApplyRange();
        }
    }

    /// Kept inside the range.
    public int Value
    {
        get => _native.GetValue();
        set => _native.SetValue(ClampToRange(value, _minimum, _maximum));
    }

    void ApplyRange()
    {
        _native.SetRange(_minimum, _maximum);
        int now = _native.GetValue();
        int kept = ClampToRange(now, _minimum, _maximum);
        if (kept != now)
            _native.SetValue(kept);
    }

    /// How often a tick is drawn beneath the slider.
    public int TickFrequency
    {
        get => _tickFrequency;
        set
        {
            _tickFrequency = value;
            _native.SetTickFrequency(value);
        }
    }

    /// The user moved the slider. Setting `Value` raises nothing, as the seam's
    /// `OnPlatformValueChanged` says.
    public event EventHandler ValueChanged;

    protected virtual void OnValueChanged() => ValueChanged(this);

    public override void OnPlatformValueChanged() => OnValueChanged();
}

// ============================================================== tab control

/// One page of a `TabControl`.
///
/// A real container, so controls are put on it exactly as they are put on a
/// panel -- which is what makes a tabbed form no different from an untabbed one
/// once the page is chosen.
public class TabPage : WindowedControl
{
    IPanelPeer _native;
    int _index;

    public TabPage(TabControl owner, String text)
    {
        base(owner);
        _native = WidgetSet.Current.CreatePanel(this, ParentPeer);
        AttachContainerPeer(_native);
        StoredText = text;
        _index = owner.RegisterPage(this, text);
    }

    /// Which tab this page is behind.
    public int Index => _index;

    /// Told its new number after a page in front of it was removed. Called by
    /// `TabControl.RemovePage` and by nothing else.
    public void SetIndex(int now) => _index = now;

    /// The caption on the tab. The same as `Text`.
    public String Caption
    {
        get => Text;
        set => Text = value;
    }

    /// A page's text is its tab's caption. The page's own panel shows no text,
    /// so the base, which would tell the panel, is not called.
    protected override void SetTextValue(String value)
    {
        if (StoredText == value)
            return;
        StoredText = value;
        if (Parent is TabControl tabs)
            tabs.SetTabText(_index, value);
        OnTextChanged();
    }
}

/// A stack of pages with tabs across the top.
public class TabControl : WindowedControl
{
    ITabControlPeer _native;
    List<TabPage> _pages;
    ImageList? _images;

    public TabControl(WindowedControl parent)
    {
        base(parent);
        _pages = new List<TabPage>();
        _images = null;
        _native = WidgetSet.Current.CreateTabControl(this, ParentPeer);
        AttachContainerPeer(_native);
    }

    /// Called by a `TabPage` as it is built. Not public: a page joins the
    /// control it was constructed with, and there is no other way in.
    int RegisterPage(TabPage page, String text)
    {
        int at = _native.AddTab(text, -1);
        _pages.Add(page);
        // **Inserting a tab does not make it current.** Windows leaves the
        // selection at -1 until something is chosen, so a control that simply
        // showed whichever page was selected would show none of them -- every
        // page hidden, and a tab strip over an empty rectangle.
        if (_native.GetSelectedTab() < 0)
            _native.SetSelectedTab(0);
        ShowOnlyPage(_native.GetSelectedTab());
        return at;
    }

    void SetTabText(int index, String text) => _native.SetTabText(index, text);

    public List<TabPage> Pages => _pages;

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
    /// The page leaves this control's children as well, and its window is
    /// destroyed; see `RemoveControl`. Dropping the last reference to it is
    /// what frees it.
    public bool RemovePage(TabPage page)
    {
        nuint at = 0u;
        bool found = false;
        for (nuint i = 0u; i < _pages.Count; i++)
        {
            if (_pages[i] == page)
            {
                at = i;
                found = true;
                break;
            }
        }
        if (!found)
            return false;

        var showing = SelectedPage;
        _native.RemoveTab((int)at);
        _pages.RemoveAt(at);
        RemoveControl(page);

        for (nuint i = at; i < _pages.Count; i++)
            _pages[i].SetIndex((int)i);

        // Removing the selected tab leaves the platform's selection wherever it
        // landed, which may be -1 with pages still here.
        int chosen = _native.GetSelectedTab();
        if (chosen < 0 && !_pages.IsEmpty)
        {
            chosen = (int)(at >= _pages.Count ? _pages.Count - 1u : at);
            _native.SetSelectedTab(chosen);
        }
        ShowOnlyPage(_native.GetSelectedTab());
        if (showing == page)
            OnSelectedIndexChanged();
        return true;
    }

    /// How many tabs the platform has, which is not the same question as how
    /// many pages this control is holding -- and is the one that notices when
    /// an insertion quietly did nothing.
    public int TabCount => _native.TabCount;

    /// Which page is showing. An index naming no page is ignored.
    public int SelectedIndex
    {
        get => _native.GetSelectedTab();
        set
        {
            if (value < 0 || (nuint)value >= _pages.Count)
                return;
            int was = _native.GetSelectedTab();
            _native.SetSelectedTab(value);
            int now = _native.GetSelectedTab();
            ShowOnlyPage(now);
            if (now != was)
                OnSelectedIndexChanged();
        }
    }

    public TabPage? SelectedPage
    {
        get
        {
            int at = SelectedIndex;
            if (at < 0 || (nuint)at >= _pages.Count)
                return null;
            return _pages[(nuint)at];
        }
    }

    public ImageList? Images
    {
        get => _images;
        set
        {
            _images = value;
            _native.SetImages(value == null ? null : ((ImageList)value).Backend);
        }
    }

    /// **The pages are shown and hidden here, not by the platform.** A Windows
    /// tab control draws the tabs and nothing else: what is underneath them is
    /// the program's business, and a control that did not hide the page it left
    /// would leave both drawn on top of each other. Every toolkit does this
    /// somewhere, and the LCL does it in `TCustomTabControl.ShowCurrentPage`.
    void ShowOnlyPage(int chosen)
    {
        var area = _native.PageArea;
        for (nuint i = 0u; i < _pages.Count; i++)
        {
            var page = _pages[i];
            bool wanted = (int)i == chosen;
            page.Visible = wanted;
            if (wanted)
                page.Bounds = area;
        }
    }

    /// The chosen page changed.
    public event EventHandler SelectedIndexChanged;

    protected virtual void OnSelectedIndexChanged() => SelectedIndexChanged(this);

    public override void OnPlatformValueChanged()
    {
        ShowOnlyPage(_native.GetSelectedTab());
        OnSelectedIndexChanged();
    }

    /// A resize moves the page area, so whichever page is showing follows it.
    protected override void OnResize()
    {
        base.OnResize();
        ShowOnlyPage(_native.GetSelectedTab());
    }
}

// ================================================================ tree view

/// One node of a `TreeView`.
public class TreeNode
{
    weak TreeView? _tree;
    ITreeNodeHandle _handle;
    List<TreeNode> _nodes;

    public TreeNode(TreeView owner, ITreeNodeHandle place)
    {
        _tree = owner;
        _handle = place;
        _nodes = new List<TreeNode>();
    }

    /// The platform's idea of where this node is.
    public ITreeNodeHandle Handle => _handle;

    public String Text
    {
        get
        {
            TreeView? owner = _tree;
            if (owner == null)
                return "";
            return ((TreeView)owner).GetNodeText(_handle);
        }
        set
        {
            TreeView? owner = _tree;
            if (owner != null)
                ((TreeView)owner).SetNodeText(_handle, value);
        }
    }

    public List<TreeNode> Nodes => _nodes;

    /// Adds a node under this one and answers it.
    public TreeNode Add(String text, int image)
    {
        TreeView? owner = _tree;
        if (owner == null)
            sl_fail("this node is not on a tree".ToPointer());
        var made = ((TreeView)owner).InsertNode(this, text, image);
        _nodes.Add(made);
        return made;
    }

    public TreeNode Add(String text) => Add(text, -1);

    public void Expand()
    {
        TreeView? owner = _tree;
        if (owner != null)
            ((TreeView)owner).SetNodeExpanded(_handle, true);
    }

    public void Collapse()
    {
        TreeView? owner = _tree;
        if (owner != null)
            ((TreeView)owner).SetNodeExpanded(_handle, false);
    }
}

/// A tree of nodes that open and close.
#if FORMS_REFLECT
[Reflect]
#endif
public class TreeView : WindowedControl
{
    ITreeViewPeer _native;
    ImageList? _images;
    List<TreeNode> _nodes;
    /// Every node made, so that the handle the platform reports can be turned
    /// back into the object a program holds.
    List<TreeNode> _all;

    public TreeView(WindowedControl parent)
    {
        base(parent);
        _nodes = new List<TreeNode>();
        _all = new List<TreeNode>();
        _images = null;
        _native = WidgetSet.Current.CreateTreeView(this, ParentPeer);
        AttachPeer(_native);
    }

    /// Adds a node at the top level and answers it.
    public TreeNode Add(String text, int image)
    {
        var made = new TreeNode(this, _native.AddNode(null, null, text, image));
        _nodes.Add(made);
        _all.Add(made);
        return made;
    }

    public TreeNode Add(String text) => Add(text, -1);

    /// Adds under an existing node. Called by `TreeNode.Add`.
    TreeNode InsertNode(TreeNode parent, String text, int image)
    {
        var made = new TreeNode(this, _native.AddNode(parent.Handle, null, text, image));
        _all.Add(made);
        return made;
    }

    String GetNodeText(ITreeNodeHandle node) => _native.GetNodeText(node);
    void SetNodeText(ITreeNodeHandle node, String text) => _native.SetNodeText(node, text);
    void SetNodeExpanded(ITreeNodeHandle node, bool open) => _native.SetNodeExpanded(node, open);

    public List<TreeNode> Nodes => _nodes;

    public void Clear()
    {
        _native.Clear();
        _nodes.Clear();
        _all.Clear();
    }

    /// Which node is selected, or null.
    public TreeNode? SelectedNode
    {
        get
        {
            var chosen = _native.GetSelectedNode();
            if (chosen == null)
                return null;
            return FindNode((ITreeNodeHandle)chosen);
        }
        set
        {
            if (value != null)
                _native.SelectNode(((TreeNode)value).Handle);
        }
    }

    /// The node under a point, or null when the point is not on one.
    ///
    /// `at` is the position a mouse event reported, passed on unchanged --
    /// the seam says why that distinction is load-bearing on GTK.
    ///
    /// **This is what a context menu is built from**, because neither platform
    /// moves the selection on a right-click: a menu that asked `SelectedNode`
    /// would act on whatever was selected before the click.
    public TreeNode? GetNodeAt(Point at)
    {
        var found = _native.GetNodeAt(at);
        if (found == null)
            return null;
        return FindNode((ITreeNodeHandle)found);
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
    TreeNode? FindNode(ITreeNodeHandle handle)
    {
        nuint wanted = handle.Id;
        foreach (var node in _all)
        {
            if (node.Handle.Id == wanted)
                return node;
        }
        return null;
    }

    public ImageList? Images
    {
        get => _images;
        set
        {
            _images = value;
            _native.SetImages(value == null ? null : ((ImageList)value).Backend);
        }
    }

    /// The selection changed.
    public event EventHandler SelectedNodeChanged;

    protected virtual void OnSelectedNodeChanged() => SelectedNodeChanged(this);

    public override void OnPlatformValueChanged() => OnSelectedNodeChanged();
}

// ================================================================ list view

/// A table of rows and columns.
///
/// **No `ListViewItem` object.** `TListItem` is a `TPersistent` with a
/// `SubItems: TStrings` hanging off it, so a table of a thousand rows is two
/// thousand objects before any text. Here a row is an index and its cells are
/// set through the list, which is what the platform stores anyway -- and what
/// C#'s virtual mode exists to get back to.
#if FORMS_REFLECT
[Reflect]
#endif
public class ListView : WindowedControl
{
    IListViewPeer _native;
    ListViewStyle _view;
    ImageList? _images;

    public ListView(WindowedControl parent)
    {
        base(parent);
        _view = ListViewStyle.Details;
        _images = null;
        _native = WidgetSet.Current.CreateListView(this, ParentPeer);
        AttachPeer(_native);
        _native.SetFullRowSelect(true, false);
    }

    /// Adds a column and answers its index. Only a `Details` list shows them.
    public int AddColumn(String text, int width, HorizontalAlignment alignment)
    {
        return _native.AddColumn(text, width, alignment);
    }

    public int AddColumn(String text, int width)
    {
        return AddColumn(text, width, HorizontalAlignment.Left);
    }

    public void SetColumnWidth(int column, int width)
    {
        _native.SetColumnWidth(column, width);
    }

    /// Adds a row with its first cell, and answers the row's index.
    public int AddRow(String text, int image) => _native.AddRow(text, image);
    public int AddRow(String text) => AddRow(text, -1);

    /// Sets a cell other than the first. Column zero is the row's own text.
    public void SetCell(int row, int column, String text)
    {
        _native.SetCell(row, column, text);
    }

    /// Adds a row and fills every column of it.
    public int AddRow(String[] cells)
    {
        if (cells.Length == 0u)
            return -1;
        int row = AddRow(cells[0u], -1);
        for (nuint i = 1u; i < cells.Length; i++)
        {
            SetCell(row, (int)i, cells[i]);
        }
        return row;
    }

    /// What one cell says, read from the control rather than remembered.
    ///
    /// Worth having beyond the obvious: it is the only way to tell that the
    /// text really arrived, which a row count cannot.
    public String GetCellText(int row, int column)
    {
        return _native.GetCell(row, column);
    }

    public void RemoveRow(int row) => _native.RemoveRow(row);
    public void Clear() => _native.Clear();
    public int Count => _native.RowCount;

    /// Which row is selected, or -1.
    public int SelectedIndex
    {
        get => _native.GetSelectedRow();
        set => _native.SetSelectedRow(value);
    }

    /// How the list shows what it holds.
    public ListViewStyle View
    {
        get => _view;
        set
        {
            _view = value;
            _native.SetStyle(value);
        }
    }

    /// Whether clicking anywhere on a row selects the whole of it, and whether
    /// the grid is drawn.
    public void SetFullRowSelect(bool full, bool gridLines)
    {
        _native.SetFullRowSelect(full, gridLines);
    }

    public ImageList? Images
    {
        get => _images;
        set
        {
            _images = value;
            _native.SetImages(value == null ? null : ((ImageList)value).Backend);
        }
    }

    /// The selection changed.
    public event EventHandler SelectedIndexChanged;

    protected virtual void OnSelectedIndexChanged() => SelectedIndexChanged(this);

    public override void OnPlatformValueChanged() => OnSelectedIndexChanged();
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
public class CoolBand
{
    weak CoolBar? _bar;
    Control? _control;
    String _text;
    bool _break;
    bool _visible;
    bool _fixedSize;
    int _width;
    int _minWidth;
    int _minHeight;
    Color _color;
    bool _hasColor;

    /// Where the layout pass put it. Read-only to a program, as in the LCL --
    /// a band's position is the cool bar's business.
    /// How wide the caption came out when it was last drawn, or -1 before
    /// anything has drawn it.
    ///
    /// A layout pass has no surface to measure with, so the measurement is
    /// taken while painting and used by the pass after it.
    int _measuredText;

    int _left;
    int _top;
    int _height;
    /// How wide it is *drawn*, which for the last band in a row is everything
    /// left over rather than `Width`. `TCoolBand.FRealWidth`.
    int _drawnWidth;

    public CoolBand(CoolBar owner)
    {
        _measuredText = -1;
        _bar = owner;
        _control = null;
        _text = "";
        _break = true;
        _visible = true;
        _fixedSize = false;
        _width = 180;
        _minWidth = 100;
        _minHeight = 25;
        _color = Colors.Transparent;
        _hasColor = false;
        _left = 0;
        _top = 0;
        _height = 0;
        _drawnWidth = 0;
        owner.RegisterBand(this);
    }

    /// The control this band carries, or null for a band that is only a label.
    ///
    /// It must already be a child of the cool bar. Nothing here reparents it:
    /// a control chooses its parent once, at birth, which is the rule
    /// everywhere in this library.
    public Control? Control
    {
        get => _control;
        set
        {
            var was = _control;
            if (was == value)
                return;
            if (was != null)
                ((Control)was).Resize -= this.OnControlResized;
            _control = value;

            // A band is as tall as what it holds, and a widget set MAY decide
            // that for itself -- GTK reports a combo box taller than the
            // height it was given. Laying the bands out once, from the height
            // that was asked for, leaves the control standing outside its
            // band.
            if (value != null)
            {
                var one = (Control)value;
                one.Resize += this.OnControlResized;
                if (!_visible)
                    one.Visible = false;
            }

            RequestBarRebuild();
        }
    }

    /// What the caption measured, or -1 if it has not been drawn yet.
    /// Written by `CoolBar.OnPaint`.
    public int MeasuredText
    {
        get => _measuredText;
        set => _measuredText = value;
    }

    void OnControlResized(Control sender)
    {
        // A weak reference is never narrowed, so it goes into a strong local
        // first.
        CoolBar? owner = _bar;
        if (owner != null)
            ((CoolBar)owner).LayoutBands();
    }

    /// The caption drawn after the grab handle, when `CoolBar.ShowText` is on.
    public String Text
    {
        get => _text;
        set
        {
            _text = value;
            RequestBarRebuild();
        }
    }

    /// Whether this band starts a new row rather than following the one before
    /// it. True by default, as `TCoolBand.Break` is -- a bar of bands each on
    /// its own row is what a program that set nothing should get.
    public bool Break
    {
        get => _break;
        set
        {
            _break = value;
            RequestBarRebuild();
        }
    }

    public bool Visible
    {
        get => _visible;
        set
        {
            _visible = value;
            var one = _control;
            if (one != null)
                ((Control)one).Visible = value;
            RequestBarRebuild();
        }
    }

    /// Whether the user may drag this band's right edge. A fixed band is also
    /// one its neighbour cannot be resized against.
    public bool FixedSize
    {
        get => _fixedSize;
        set => _fixedSize = value;
    }

    /// How wide the band asks to be. Never below `MinWidth`.
    public int Width
    {
        get => _width;
        set
        {
            int now = value < _minWidth ? _minWidth : value;
            if (now == _width)
                return;
            _width = now;
            RequestBarRebuild();
        }
    }

    public int MinWidth
    {
        get => _minWidth;
        set
        {
            _minWidth = value;
            if (_width < _minWidth)
                _width = _minWidth;
            RequestBarRebuild();
        }
    }

    public int MinHeight
    {
        get => _minHeight;
        set
        {
            _minHeight = value;
            RequestBarRebuild();
        }
    }

    /// The band's own background, or nothing set -- the default -- to use the
    /// cool bar's.
    public Color Color
    {
        get => _color;
        set
        {
            _color = value;
            _hasColor = true;
            RequestBarRebuild();
        }
    }

    public bool HasColor => _hasColor;

    public int Left   => _left;
    public int Top    => _top;
    public int Height => _height;
    /// How wide it is drawn, which is `Width` except for the last band of a
    /// row, which is given whatever is left.
    public int DrawnWidth => _drawnWidth;

    /// Widens the band to just fit its control, which is what double-clicking
    /// a grabber does in a real rebar and what `TCoolBand.AutosizeWidth` is.
    public void FitWidthToControl()
    {
        CoolBar? owner = _bar;
        if (owner == null)
            return;
        Width = ((CoolBar)owner).GetContentLeft(this) + ControlWidth
              + ((CoolBar)owner).HorizontalSpacing + CoolDivider;
    }

    int ControlWidth
    {
        get
        {
            var one = _control;
            return one == null ? 0 : ((Control)one).Width;
        }
    }

    /// Called by the cool bar's layout pass, and by nothing else.
    public void SetLayoutPlacement(int left, int top, int height, int drawn)
    {
        _left = left;
        _top = top;
        _height = height;
        _drawnWidth = drawn;
    }

    void RequestBarRebuild()
    {
        CoolBar? owner = _bar;
        if (owner != null)
            ((CoolBar)owner).RebuildBands();
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
/// after building it, or docks it and lets `ResizeToPreferredSize` do it.
///
/// **What is not here.** `Vertical` -- a cool bar down the side of a window --
/// is every coordinate in this file mirrored, and `TCustomCoolBar` pays for it
/// with an `if Vertical` in each of forty places; it is left out rather than
/// half done. So is right-to-left, for the same reason, and so are the two
/// themed grab styles.
public class CoolBar : CustomControl
{
    List<CoolBand>? _bands;
    /// The visible ones, in order, rebuilt by every layout pass. Held rather
    /// than recomputed per hit-test because the paint, the mouse and the layout
    /// all walk the same list and must agree about it.
    List<CoolBand>? _showing;

    GrabberStyle _grabStyle;
    int _grabWidth;
    int _horizontalSpacing;
    int _verticalSpacing;
    bool _showText;
    bool _fixedSize;
    bool _fixedOrder;
    ImageList? _images;

    int _dragging;
    int _draggedBand;
    int _dragFrom;
    int _rowsHigh;
    bool _ready;

    public CoolBar(WindowedControl parent)
    {
        base(parent);
        _bands = new List<CoolBand>();
        _showing = new List<CoolBand>();
        _grabStyle = GrabberStyle.Double;
        _grabWidth = 10;
        _horizontalSpacing = 5;
        _verticalSpacing = 3;
        _showText = true;
        _fixedSize = false;
        _fixedOrder = false;
        _images = null;
        _dragging = CoolDragNone;
        _draggedBand = CoolNowhere;
        _dragFrom = 0;
        _rowsHigh = 0;

        // A cool bar takes no keystrokes, so it stays out of the tab order --
        // the controls *in* it are what the keyboard reaches, and they are
        // ordinary children with windows of their own.
        Focusable = false;
        Dock = DockStyle.Top;
        Height = 34;

        _ready = true;
        RebuildBands();
    }

    /// Called by a `CoolBand` as it is built. Not public: a band joins the bar
    /// it was constructed with, and there is no other way in.
    public void RegisterBand(CoolBand band)
    {
        var held = _bands;
        if (held == null)
            return;
        ((List<CoolBand>)held).Add(band);
        RebuildBands();
    }

    public List<CoolBand> Bands
    {
        get
        {
            var held = _bands;
            if (held == null)
                return new List<CoolBand>();
            return (List<CoolBand>)held;
        }
    }

    public int BandCount => (int)Bands.Count;

    /// How the grab handles are drawn.
    public GrabberStyle GrabStyle
    {
        get => _grabStyle;
        set
        {
            _grabStyle = value;
            Invalidate();
        }
    }

    /// How wide a grab handle is.
    public int GrabWidth
    {
        get => _grabWidth;
        set
        {
            _grabWidth = value;
            RebuildBands();
        }
    }

    /// Pixels between a band's parts -- the handle, the caption, the control.
    public int HorizontalSpacing
    {
        get => _horizontalSpacing;
        set
        {
            _horizontalSpacing = value;
            RebuildBands();
        }
    }

    /// Pixels above and below a band's control, which is what makes a row
    /// taller than the tallest thing in it.
    public int VerticalSpacing
    {
        get => _verticalSpacing;
        set
        {
            _verticalSpacing = value;
            RebuildBands();
        }
    }

    /// Whether a band's `Text` is drawn.
    public bool ShowText
    {
        get => _showText;
        set
        {
            _showText = value;
            RebuildBands();
        }
    }

    /// Whether any band may be resized by dragging. Overrides every band's own
    /// `FixedSize`, which is what `TCustomCoolBar.FixedSize` does.
    public bool FixedSize
    {
        get => _fixedSize;
        set => _fixedSize = value;
    }

    /// Whether the bands may be dragged into a different order.
    public bool FixedOrder
    {
        get => _fixedOrder;
        set => _fixedOrder = value;
    }

    /// The pictures a band's `ImageIndex` names. Declared so that a band that
    /// wants an icon has somewhere to get one; nothing draws one yet.
    public ImageList? Images
    {
        get => _images;
        set
        {
            _images = value;
            Invalidate();
        }
    }

    /// One band was moved or resized by the user. Not raised for a change a
    /// program made, as `TCustomCoolBar.OnChange` is not.
    public event EventHandler Change;

    protected virtual void OnChange() => Change(this);

    // -------------------------------------------------------------- layout

    /// How tall the bar came out: every row's height, plus the dividers between
    /// them. What a program assigns to `Height` after building the bands.
    public override Size PreferredSize => Size.FromDimensions(0, _rowsHigh);

    /// Where a band's control begins, measured from the band's left edge: past
    /// the handle, the caption and the gaps between them.
    /// `TCoolBand.CalcControlLeft`.
    public int GetContentLeft(CoolBand band)
    {
        int at = CoolGrabIndent + _grabWidth + _horizontalSpacing;
        int bare = at;
        if (_showText && !band.Text.IsEmpty)
        {
            at = at + MeasureTextWidth(band) + _horizontalSpacing;
        }
        // A band with no caption still gets one gap, so its control does not
        // sit against the handle.
        if (at == bare)
            at = at + _horizontalSpacing;
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
    /// How wide a caption is.
    ///
    /// Measured where it was drawn, because a layout pass has no surface to
    /// measure with. Seven pixels a byte is the estimate used until the first
    /// paint: it is close for the Windows UI font and too narrow for GTK's,
    /// where an unmeasured caption is drawn over by the band's control.
    int MeasureTextWidth(CoolBand band)
    {
        if (band.MeasuredText >= 0)
            return band.MeasuredText;
        return (int)band.Text.ByteLength() * 7;
    }

    /// How tall one band wants to be: its own minimum, its control plus the
    /// vertical spacing, and the caption -- whichever is largest.
    /// `TCoolBand.CalcPreferredHeight`.
    int MeasureBandHeight(CoolBand band)
    {
        int high = band.MinHeight;
        var one = band.Control;
        if (one != null)
        {
            int wanted = ((Control)one).Height + 2 * _verticalSpacing;
            if (wanted > high)
                high = wanted;
        }
        if (_showText)
        {
            int wanted = Font.Size + 4 + 2 * _verticalSpacing;
            if (wanted > high)
                high = wanted;
        }
        return high;
    }

    /// Whether the band after this one will not fit beside it.
    bool ShouldWrapAfter(List<CoolBand> row, nuint index, int left)
    {
        if (index + 1u >= row.Count)
            return false;
        var next = row[index + 1u];
        if (next.Break)
            return true;
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
    public void RebuildBands()
    {
        if (!_ready)
            return;

        var all = Bands;
        var showing = new List<CoolBand>();
        for (nuint i = 0u; i < all.Count; i++)
        {
            if (all[i].Visible)
                showing.Add(all[i]);
        }
        _showing = showing;

        // ---- pass one: where the rows break, and how tall each is.
        var heights = new int[showing.Count];
        int tallest = 0;
        nuint rowStart = 0u;
        int left = 0;
        bool rowEnd = true;

        for (nuint i = 0u; i < showing.Count; i++)
        {
            if (rowEnd || showing[i].Break)
                left = 0;
            int wanted = MeasureBandHeight(showing[i]);
            if (wanted > tallest)
                tallest = wanted;
            left = left + showing[i].Width;

            rowEnd = i + 1u >= showing.Count || ShouldWrapAfter(showing, i, left);
            if (!rowEnd)
                continue;

            for (nuint y = rowStart; y <= i; y++)
                heights[y] = tallest;
            tallest = 0;
            rowStart = i + 1u;
        }

        // ---- pass two: place the bands and the controls in them.
        int top = 0;
        left = 0;
        rowEnd = true;

        for (nuint i = 0u; i < showing.Count; i++)
        {
            var band = showing[i];
            if (rowEnd || band.Break)
                left = 0;

            int height = heights[i];
            int width = band.Width;
            rowEnd = ShouldWrapAfter(showing, i, left + width) || i + 1u >= showing.Count;
            // The last band of a row is drawn out to the far edge, whatever
            // width it asked for -- otherwise every row would end in a gap the
            // user could not fill.
            int drawn = rowEnd ? Width - left : width;
            if (drawn < width)
                drawn = width;

            band.SetLayoutPlacement(left, top, height, drawn);

            var one = band.Control;
            if (one != null)
            {
                var child = (Control)one;
                int contentLeft = left + GetContentLeft(band);
                int room = drawn - GetContentLeft(band) - _horizontalSpacing - CoolDivider;
                if (room < 0)
                    room = 0;
                child.SetBounds(contentLeft, top + (height - child.Height) / 2,
                                room, child.Height);
            }

            left = left + width;
            if (rowEnd)
                top = top + height + CoolDivider;
        }

        _rowsHigh = top;
        Invalidate();
    }

    /// Lays the bands out again, and grows the bar to what they now need.
    ///
    /// For a band whose control turned out to be a different size from the one
    /// it was given. The bar's own height is set here as well as the bands',
    /// because a bar docked to an edge keeps whatever height it was given and
    /// would otherwise clip the room it has just made.
    public void LayoutBands()
    {
        if (_bands == null)
            return;

        int was = _rowsHigh;
        RebuildBands();

        if (_rowsHigh != was && _rowsHigh > 0)
            Height = _rowsHigh;
    }

    /// A resize changes where the rows wrap, so the whole layout is redone.
    ///
    /// The null test is the trap the composites all have: the base constructor
    /// resizes, and this override runs before this class's own fields exist.
    protected override void OnResize()
    {
        base.OnResize();
        if (_bands == null)
            return;
        RebuildBands();
    }

    List<CoolBand> Showing
    {
        get
        {
            var held = _showing;
            if (held == null)
                return new List<CoolBand>();
            return (List<CoolBand>)held;
        }
    }

    // ------------------------------------------------------------- painting

    protected override void OnPaint(PaintEventArgs args)
    {
        var surface = args.Graphics;
        surface.Clear(BackColor);

        var showing = Showing;
        var light = new Pen(SystemColors.ControlLight);
        var dark = new Pen(SystemColors.ControlDark);
        bool remeasured = false;

        for (nuint i = 0u; i < showing.Count; i++)
        {
            var band = showing[i];
            var whole = Rectangle.FromBounds(band.Left, band.Top, band.DrawnWidth, band.Height);

            if (band.HasColor)
                surface.FillRectangle(new Brush(band.Color), whole);

            PaintGrabber(surface, light, dark,
                         Rectangle.FromBounds(band.Left + CoolGrabIndent, band.Top + 2,
                                      _grabWidth - 1, band.Height - 5));

            if (_showText && !band.Text.IsEmpty)
            {
                int x = band.Left + CoolGrabIndent + _grabWidth + _horizontalSpacing;
                var measured = surface.MeasureString(band.Text, Font);
                int y = band.Top + (band.Height - measured.Height) / 2;
                surface.DrawString(band.Text, Font, ForeColor, x, y);

                // The one place there is a surface to measure with. A pass
                // that ran on the estimate is redone once, with the truth.
                if (band.MeasuredText != measured.Width)
                {
                    band.MeasuredText = measured.Width;
                    remeasured = true;
                }
            }

            bool last = i + 1u >= showing.Count;
            bool endsRow = last || showing[i + 1u].Top != band.Top;

            if (endsRow)
            {
                // The line under a finished row, which is what separates one
                // row from the next and the last row from the client area.
                int y = band.Top + band.Height;
                surface.DrawLine(dark, 0, y, Width, y);
                surface.DrawLine(light, 0, y + 1, Width, y + 1);
            }
            else
            {
                // The upright between two bands sharing a row.
                int x = band.Left + band.DrawnWidth;
                surface.DrawLine(dark, x, band.Top + 1, x, band.Top + band.Height - 1);
                surface.DrawLine(light, x + 1, band.Top + 1, x + 1,
                                 band.Top + band.Height - 1);
            }
        }

        // A caption measured for the first time, or measured differently
        // after a font change. The pass that placed these bands ran on the
        // estimate, so it is run again and the result painted next time.
        // Once: the second pass measures the same widths and stops.
        if (remeasured)
            RebuildBands();

        base.OnPaint(args);
    }

    /// The grab handle, in whichever of the four styles is set.
    void PaintGrabber(Graphics surface, Pen light, Pen dark, Rectangle at)
    {
        if (at.Width <= 0 || at.Height <= 0)
            return;
        int left = at.X;
        int top = at.Y;
        int right = at.X + at.Width;
        int bottom = at.Y + at.Height;

        if (_grabStyle == GrabberStyle.Simple)
        {
            surface.DrawLine(light, left, top, right, top);
            surface.DrawLine(light, left, top, left, bottom);
            surface.DrawLine(dark, left, bottom, right, bottom);
            surface.DrawLine(dark, right, top, right, bottom);
            return;
        }

        if (_grabStyle == GrabberStyle.Double)
        {
            // Two narrow raised bars side by side, which is the default and the
            // one a Windows rebar draws.
            int half = (_grabWidth - 2) / 2;
            if (half < 1)
                half = 1;
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

        if (_grabStyle == GrabberStyle.HorizontalLines)
        {
            int lines = (at.Height + 1) / 3;
            for (int w = 0; w < lines; w++)
            {
                int y = top + 1 + w * 3;
                surface.DrawLine(dark, left, y, right, y);
                surface.DrawLine(light, left, y + 1, right, y + 1);
            }
            return;
        }

        int columns = (at.Width + 1) / 3;
        for (int w = 0; w < columns; w++)
        {
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
    (int, bool) BandAt(Point at)
    {
        var showing = Showing;
        if (showing.IsEmpty)
            return (CoolNowhere, false);

        var last = showing[showing.Count - 1u];
        if (at.Y > last.Top + last.Height + CoolDivider)
            return (CoolRowBelow, false);
        if (at.Y < 0)
            return (CoolRowAbove, false);

        for (nuint i = 0u; i < showing.Count; i++)
        {
            var band = showing[i];
            var whole = Rectangle.FromBounds(band.Left, band.Top, band.DrawnWidth, band.Height);
            if (!whole.Contains(at))
                continue;
            return ((int)i, at.X <= band.Left + _grabWidth + 1);
        }
        return (CoolNowhere, false);
    }

    /// Whether this band is the first of its row, which is the one whose
    /// handle cannot resize anything: there is no band to its left to take the
    /// pixels from.
    bool IsFirstOfRow(int index)
    {
        var showing = Showing;
        if (index <= 0)
            return true;
        return showing[(nuint)index].Top != showing[(nuint)(index - 1)].Top;
    }

    protected override void OnMouseDown(MouseEventArgs args)
    {
        base.OnMouseDown(args);
        if (args.Button != MouseButton.Left)
            return;

        var found = BandAt(args.Location);
        int index = found.Item1;
        bool onGrabber = found.Item2;
        _draggedBand = index;
        _dragging = CoolDragNone;
        if (index < 0)
            return;

        var showing = Showing;
        if (onGrabber && !IsFirstOfRow(index) && !_fixedSize
            && !showing[(nuint)index].FixedSize
            && !showing[(nuint)(index - 1)].FixedSize)
        {
            // Dragging a handle resizes the band to its *left*, which is the
            // one whose right edge the handle sits against.
            _dragging = CoolDragResize;
            var before = showing[(nuint)(index - 1)];
            _dragFrom = args.X - before.Width - before.Left;
            CaptureMouse(true);
            return;
        }

        // **By the gripper, and not by anywhere on the band.** A rebar moves a
        // band by its grab handle; the rest of a band belongs to the control
        // sitting in it, and a press there is that control's business.
        if (onGrabber && !_fixedOrder)
        {
            _dragging = CoolDragMove;
            CaptureMouse(true);
        }
    }

    protected override void OnMouseMove(MouseEventArgs args)
    {
        base.OnMouseMove(args);
        var showing = Showing;
        if (showing.IsEmpty)
            return;

        if (_dragging == CoolDragResize)
        {
            var before = showing[(nuint)(_draggedBand - 1)];
            before.Width = args.X - _dragFrom - before.Left;
            return;
        }

        if (_dragging == CoolDragMove)
            return;

        // Nothing is being dragged, so the cursor says what a drag would do.
        //
        // **Only over a gripper.** A cursor set here is inherited by every
        // child that does not set one of its own -- `WM_SETCURSOR` walks up to
        // the parent -- so a bar that claimed the move cursor for the whole of
        // a band claimed it over the toolbar buttons sitting in that band too,
        // which is how this was reported.
        var found = BandAt(args.Location);
        int index = found.Item1;
        bool onGrabber = found.Item2;
        if (index < 0 || !onGrabber)
        {
            Cursor = CursorKind.Default;
            return;
        }

        if (index > 0 && !IsFirstOfRow(index) && !_fixedSize
            && !showing[(nuint)index].FixedSize
            && !showing[(nuint)(index - 1)].FixedSize)
        {
            Cursor = CursorKind.SizeWestEast;
        }
        else if (!_fixedOrder && showing.Count > 1u)
        {
            Cursor = CursorKind.SizeAll;
        }
        else
        {
            Cursor = CursorKind.Default;
        }
    }

    protected override void OnMouseUp(MouseEventArgs args)
    {
        base.OnMouseUp(args);
        int was = _dragging;
        int dragged = _draggedBand;
        _dragging = CoolDragNone;
        _draggedBand = CoolNowhere;
        Cursor = CursorKind.Default;

        if (was == CoolDragNone)
            return;
        CaptureMouse(false);

        if (was == CoolDragResize)
        {
            OnChange();
            return;
        }

        if (dragged < 0)
            return;
        if (DropBand(dragged, args.Location))
        {
            RebuildBands();
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
    bool DropBand(int dragged, Point at)
    {
        var showing = Showing;
        if ((nuint)dragged >= showing.Count)
            return false;
        var moving = showing[(nuint)dragged];

        var found = BandAt(at);
        int onto = found.Item1;
        if (onto == CoolNowhere || onto == dragged)
            return false;
        if (onto == CoolRowAbove && dragged == 0)
            return false;

        // A drop can change only where rows break, and can also change
        // nothing at all, so what it did is found by comparing.
        var order = new List<CoolBand>();
        var breaks = new List<bool>();
        foreach (var band in Bands)
        {
            order.Add(band);
            breaks.Add(band.Break);
        }

        // Read before anything moves: changing a break lays the bar out again.
        bool pastEnd = false;
        bool sameRow = false;
        if (onto >= 0)
        {
            var target = showing[(nuint)onto];
            pastEnd = at.X > target.Left + target.DrawnWidth;
            sameRow = moving.Top == target.Top;
        }

        // A band that broke a row and is leaving it must hand the break to
        // whoever now begins that row, or the row above swallows it.
        if (moving.Break && (nuint)(dragged + 1) < showing.Count)
        {
            showing[(nuint)(dragged + 1)].Break = true;
        }

        PlaceDroppedBand(showing, dragged, onto, pastEnd, sameRow);

        var now = Bands;
        for (nuint i = 0u; i < now.Count; i++)
        {
            if (now[i] != order[i] || now[i].Break != breaks[i])
                return true;
        }
        return false;
    }

    /// The three cases `DropBand` describes, applied.
    void PlaceDroppedBand(List<CoolBand> showing, int dragged, int onto,
                      bool pastEnd, bool sameRow)
    {
        var moving = showing[(nuint)dragged];

        if (onto == CoolRowAbove)
        {
            moving.Break = true;
            MoveBandTo(moving, 0);
            return;
        }

        if (onto == CoolRowBelow)
        {
            moving.Break = true;
            MoveBandTo(moving, (int)Bands.Count - 1);
            return;
        }

        var target = showing[(nuint)onto];
        if (pastEnd)
        {
            // Joining the end of the target's row.
            moving.Break = false;
            int after = dragged > onto ? onto + 1 : onto;
            MoveBandTo(moving, GetRealIndex(showing, after));
            return;
        }

        moving.Break = target.Break;
        if (dragged > onto)
        {
            // Moving left or up: the band it landed on stops beginning the row,
            // because the dropped one now does.
            target.Break = false;
            MoveBandTo(moving, GetRealIndex(showing, onto));
            return;
        }

        // Moving right or down.
        if (sameRow)
        {
            moving.Break = false;
            MoveBandTo(moving, GetRealIndex(showing, onto));
            return;
        }
        target.Break = false;
        MoveBandTo(moving, GetRealIndex(showing, onto - 1));
    }

    /// The position in `Bands` of the nth visible band. The two lists differ
    /// whenever a band is hidden, and every move is expressed in visible terms
    /// and applied in real ones.
    int GetRealIndex(List<CoolBand> showing, int visibleIndex)
    {
        if (visibleIndex < 0)
            return 0;
        if ((nuint)visibleIndex >= showing.Count)
        {
            return (int)Bands.Count - 1;
        }
        var wanted = showing[(nuint)visibleIndex];
        var all = Bands;
        for (nuint i = 0u; i < all.Count; i++)
        {
            if (all[i] == wanted)
                return (int)i;
        }
        return 0;
    }

    /// Takes a band out of the list and puts it back at another position.
    void MoveBandTo(CoolBand band, int index)
    {
        var all = Bands;
        nuint from = 0u;
        bool found = false;
        for (nuint i = 0u; i < all.Count; i++)
        {
            if (all[i] == band)
            {
                from = i;
                found = true;
                break;
            }
        }
        if (!found)
            return;

        int to = index;
        if (to < 0)
            to = 0;
        if ((nuint)to >= all.Count)
            to = (int)all.Count - 1;
        if ((nuint)to == from)
            return;

        all.RemoveAt(from);
        all.Insert((nuint)to, band);
    }
}
