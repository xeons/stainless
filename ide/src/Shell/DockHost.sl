// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// The Visual Studio arrangement: tool windows in wells down the sides and
// along the bottom, editors in the middle, splitters between, and a pane that
// is unpinned sliding away to a strip on its edge.
//
// **In the IDE and not in `forms/`, deliberately.** Lazarus's `anchordocking`
// is 310 KB of Pascal because a *general* dock manager -- one where anything
// can float, dock to anything else, and be dragged into a tree of splitters --
// is a project of its own. This is not that. It is one window's fixed
// arrangement, built out of the `Panel`, `Splitter` and `TabControl` that
// `forms/` already has, and it is about six hundred lines because it does not
// try to be more.
//
// **What is here and what is not.** Wells, splitters that size them, tool
// windows with a caption that closes and pins, auto-hide with a slide-out, and
// all of it remembered between runs. Not here: floating a pane into a window of
// its own, and dragging one from one well to another. Both need a drag with a
// dock-target preview and one of them needs a second top-level window, and
// neither is what makes the difference between an editor and an IDE. A pane's
// edge is read from the layout file and honoured, so a hand edit moves one
// today and a drag will move one later without the file changing.
//
// **A pane never changes parent.** `forms/` has no reparenting -- a control's
// parent is fixed when it is constructed -- and every docking design that
// starts by moving widgets between containers dies on that. So a well is a
// child of the host for the whole session and auto-hide changes how it is
// *docked*, not what it belongs to: pinned it is `DockStyle.Left` and sized by
// its splitter, hidden it is invisible, and slid out it is `DockStyle.None`
// with bounds over the document area and raised in front. That constraint made
// the design simpler rather than worse, which is worth recording.
//
// `Layout.sl` is the other half -- which pane is where, and how wide -- and it
// mentions no control so that it can be tested without a screen. Everything in
// *this* file is the half only a screenshot can check.
module Ide.Shell;

import Standard.Collections;
import Standard.Text;
import Forms;
import Forms.Drawing;
import Forms.Platform;

/// How tall a tool window's caption is, and how big the glyphs in it are.
const int CaptionHeight = 22;
const int GlyphBox = 16;
const int GlyphInset = 4;

/// How wide an auto-hide strip is, and how much room one label takes along it.
const int StripThickness = 22;
const int StripLabelGap = 12;

/// How far a slid-out pane comes over the document area, as a fraction it
/// never exceeds: a pane that covered everything would have nothing to slide
/// back over and would read as having docked itself.
const int FlyoutMostOfWindow = 2;

// =============================================================== the caption

/// The bar across the top of a tool window: a title, a pin and a close box.
///
/// A `CustomControl` rather than a `Panel` with two buttons on it. Two real
/// buttons would be the shorter code and the wrong result -- a 16-pixel push
/// button is a push button, with a border and a focus rectangle and a theme's
/// idea of padding, and the thing being imitated has none of those. What is
/// actually wanted is two glyphs that light up under the pointer, which is a
/// paint and a hit test.
class CaptionBar : CustomControl
{
    String _title;
    bool _pinned;
    bool _active;
    /// Which glyph the pointer is over: 0 for neither, 1 for the pin, 2 for
    /// the close box. One field rather than two bools, because the two states
    /// are exclusive and two bools can represent a state that is not real.
    int _hotGlyph;

    public event EventHandler CloseClicked;
    public event EventHandler PinClicked;

    public CaptionBar(WindowedControl parent)
    {
        base(parent);
        _title = "";
        _pinned = true;
        _active = false;
        _hotGlyph = 0;
        // It is chrome. Taking the focus would move the caret out of the editor
        // every time someone pinned a pane.
        Focusable = false;
        Height = CaptionHeight;
        Dock = DockStyle.Top;
    }

    public String Title
    {
        get => _title;
        set
        {
            _title = value;
            Invalidate();
        }
    }

    /// Whether the pin is drawn pushed in. Set by the tool window; this control
    /// reports the click and does not decide what it means.
    public bool Pinned
    {
        get => _pinned;
        set
        {
            _pinned = value;
            Invalidate();
        }
    }

    /// Whether this is the pane being looked at, which is drawn darker.
    public bool Active
    {
        get => _active;
        set
        {
            if (_active == value)
                return;
            _active = value;
            Invalidate();
        }
    }

    Rectangle CloseBox() =>
        Rectangle.FromBounds(Width - GlyphBox - GlyphInset, (CaptionHeight - GlyphBox) / 2,
                     GlyphBox, GlyphBox);

    Rectangle PinBox() =>
        Rectangle.FromBounds(Width - (GlyphBox * 2) - GlyphInset - 2,
                     (CaptionHeight - GlyphBox) / 2, GlyphBox, GlyphBox);

    protected override void OnPaint(PaintEventArgs args)
    {
        var canvas = args.Graphics;
        var whole = Rectangle.FromBounds(0, 0, Width, Height);

        Color back = _active ? SystemColors.Highlight : SystemColors.Control;
        Color ink = _active ? SystemColors.HighlightText : SystemColors.ControlText;

        canvas.FillRectangle(new Brush(back), whole);

        // A single rule along the bottom rather than a frame: the pane below
        // has its own border, and two lines a pixel apart is what makes a
        // window look assembled out of parts.
        canvas.DrawLine(new Pen(SystemColors.ControlDark), 0, Height - 1,
                        Width, Height - 1);

        canvas.DrawString(_title, Font, ink, GlyphInset + 2,
                          (Height - canvas.MeasureString("M", Font).Height) / 2);

        DrawPinGlyph(canvas, PinBox, ink);
        DrawCloseGlyph(canvas, CloseBox, ink);
    }

    /// The pointer being over a glyph is drawn as a box around it, which is
    /// what Office XP does and what Phase 2 will do everywhere.
    void DrawHighlight(Graphics canvas, Rectangle box)
    {
        canvas.FillRectangle(new Brush(SystemColors.ControlLight), box);
        canvas.DrawRectangle(new Pen(SystemColors.ControlDark), box);
    }

    /// A pushpin: a head, a shaft, and a point. Pinned it faces down the way a
    /// pin pushed into a board does; unpinned it lies on its side, which is how
    /// every IDE since Visual Studio 2002 has drawn the difference.
    void DrawPinGlyph(Graphics canvas, Rectangle box, Color ink)
    {
        if (_hotGlyph == 1)
            DrawHighlight(canvas, box);

        var pen = new Pen(ink);
        var fill = new Brush(ink);
        int midX = box.X + box.Width / 2;
        int midY = box.Y + box.Height / 2;

        if (_pinned)
        {
            canvas.FillRectangle(fill, Rectangle.FromBounds(midX - 3, box.Y + 3, 6, 4));
            canvas.DrawLine(pen, midX, box.Y + 7, midX, box.Y + 11);
            canvas.DrawLine(pen, midX - 4, box.Y + 11, midX + 4, box.Y + 11);
            canvas.DrawLine(pen, midX, box.Y + 11, midX, box.Bottom - 2);
        }
        else
        {
            canvas.FillRectangle(fill, Rectangle.FromBounds(box.Right - 7, midY - 3, 4, 6));
            canvas.DrawLine(pen, box.Right - 8, midY, box.Right - 11, midY);
            canvas.DrawLine(pen, box.Right - 11, midY - 4, box.Right - 11, midY + 4);
            canvas.DrawLine(pen, box.Right - 11, midY, box.X + 2, midY);
        }
    }

    /// An X, drawn twice a pixel apart so that it reads as a stroke rather than
    /// as a hairline -- there is no line width above one that is not also a
    /// different shape, and no antialiasing to lean on.
    void DrawCloseGlyph(Graphics canvas, Rectangle box, Color ink)
    {
        if (_hotGlyph == 2)
            DrawHighlight(canvas, box);

        var pen = new Pen(ink);
        int left = box.X + 4;
        int top = box.Y + 4;
        int right = box.Right - 5;
        int bottom = box.Bottom - 5;

        canvas.DrawLine(pen, left, top, right, bottom);
        canvas.DrawLine(pen, left + 1, top, right + 1, bottom);
        canvas.DrawLine(pen, right, top, left, bottom);
        canvas.DrawLine(pen, right - 1, top, left - 1, bottom);
    }

    int GetGlyphAt(int x, int y)
    {
        var point = Point.FromXY(x, y);
        if (PinBox().Contains(point))
            return 1;
        if (CloseBox.Contains(point))
            return 2;
        return 0;
    }

    protected override void OnMouseMove(MouseEventArgs args)
    {
        base.OnMouseMove(args);
        int now = GetGlyphAt(args.X, args.Y);
        if (now == _hotGlyph)
            return;
        _hotGlyph = now;
        Invalidate();
    }

    protected override void OnMouseLeave()
    {
        base.OnMouseLeave();
        if (_hotGlyph == 0)
            return;
        _hotGlyph = 0;
        Invalidate();
    }

    protected override void OnMouseUp(MouseEventArgs args)
    {
        base.OnMouseUp(args);
        if (args.Button != MouseButton.Left)
            return;

        // On the release and over the same glyph, which is what every button
        // on every platform does: pressing one and sliding off must cancel.
        int which = GetGlyphAt(args.X, args.Y);
        if (which == 1)
            PinClicked(this);
        else if (which == 2)
            CloseClicked(this);
    }
}

// ============================================================= a tool window

/// A named pane. The IDE builds its tree or its list straight into this.
///
/// **It carries no caption of its own.** The caption belongs to the *well*, and
/// shows whichever pane in it is in front -- which is what Visual Studio does,
/// and is also the only arrangement that does not draw two titles for one pane
/// when a well holds several. A pane is therefore a panel with a name, which is
/// almost nothing, and that is the right amount.
///
/// **A control belongs to the parent it was constructed with**, and `forms/`
/// cannot move it afterwards. So a tool window cannot be handed a finished
/// control; it has to exist first and be built into. `host.AddPane(...)`
/// answers one, and the caller does `new TreeView(pane)` against it.
public class ToolWindow : Panel
{
    String _paneName;
    String _title;
    weak TabPage? _tab;

    public ToolWindow(TabPage parent, String name, String title)
    {
        base(parent);
        _paneName = name;
        _title = title;
        _tab = parent;
        Dock = DockStyle.Fill;
        parent.Caption = title;
    }

    /// The name this pane is known by in the layout file.
    ///
    /// `PaneName` rather than `Name`, because `Control.Name` already exists and
    /// is not virtual -- and shadowing it would leave two spellings of "what is
    /// this called" on one object, which is worse than a slightly longer name.
    public String PaneName => _paneName;

    /// What the caption and the tab both say.
    public String Title
    {
        get => _title;
        set
        {
            _title = value;
            TabPage? tab = _tab;
            if (tab != null)
                ((TabPage)tab).Caption = value;
        }
    }
}

// =========================================================== auto-hide strip

/// The labelled edge a pane collapses to, and slides back out of.
///
/// One strip per edge holding every unpinned pane on it, drawn as a row of
/// labels. Horizontal text on the bottom strip and on the side ones too, which
/// is the one place this deliberately differs from Visual Studio: rotated text
/// needs a transform `Graphics` does not have, and a side strip wide enough for
/// upright words is a worse-looking honest thing than a strip of text drawn
/// sideways by hand.
class AutoHideStrip : CustomControl
{
    List<ToolWindow> _panes;
    List<Rectangle> _labelBounds;
    DockEdge _edge;
    int _hotLabel;

    /// Which pane was clicked, by index into `Panes`.
    public event EventHandler Chosen;
    public nuint ChosenIndex;

    public AutoHideStrip(WindowedControl parent, DockEdge edge)
    {
        base(parent);
        _panes = new List<ToolWindow>();
        _labelBounds = new List<Rectangle>();
        _edge = edge;
        _hotLabel = -1;
        ChosenIndex = 0u;
        Focusable = false;

        if (edge == DockEdge.Bottom)
        {
            Dock = DockStyle.Bottom;
            Height = StripThickness;
        }
        else
        {
            Dock = edge == DockEdge.Left ? DockStyle.Left : DockStyle.Right;
            Width = StripThickness;
        }

        Visible = false;
    }

    public List<ToolWindow> Panes => _panes;

    public void ClearPanes()
    {
        _panes.Clear();
        _hotLabel = -1;
    }

    public void AddPane(ToolWindow pane) => _panes.Add(pane);

    /// A side strip has to be wide enough for the longest label, since the text
    /// runs across it rather than along it. Measured from the font rather than
    /// guessed, so a larger system font does not clip every name.
    ///
    /// **Done during the paint**, because measuring text needs a `Graphics` and
    /// the only one there is belongs to a paint. A strip whose width changes
    /// asks its parent to lay out again, which repaints it -- at the new width,
    /// where the measurement now agrees and nothing changes. So it settles
    /// after one extra pass rather than looping, and the `!=` is what
    /// guarantees that.
    bool ResizeToLabels(Graphics canvas)
    {
        if (_panes.IsEmpty || _edge == DockEdge.Bottom)
            return false;

        int widest = StripThickness;
        foreach (var pane in _panes)
        {
            int wide = canvas.MeasureString(pane.Title, Font).Width + StripLabelGap;
            if (wide > widest)
                widest = wide;
        }

        if (widest == Width)
            return false;

        Width = widest;
        return true;
    }

    /// Where each label sits. Rebuilt on every paint and every hit test rather
    /// than cached, because the two must agree and the cheapest way to
    /// guarantee that is for there to be one answer.
    void LayOutLabels(Graphics canvas)
    {
        _labelBounds.Clear();
        int line = canvas.MeasureString("M", Font).Height;

        if (_edge == DockEdge.Bottom)
        {
            int x = 2;
            foreach (var pane in _panes)
            {
                int wide = canvas.MeasureString(pane.Title, Font).Width + StripLabelGap;
                _labelBounds.Add(Rectangle.FromBounds(x, 1, wide, StripThickness - 2));
                x = x + wide + 2;
            }
        }
        else
        {
            int y = 2;
            int tall = line + 8;
            foreach (var pane in _panes)
            {
                _labelBounds.Add(Rectangle.FromBounds(1, y, Width - 2, tall));
                y = y + tall + 2;
            }
        }
    }

    protected override void OnPaint(PaintEventArgs args)
    {
        var canvas = args.Graphics;

        if (ResizeToLabels(canvas))
        {
            var parent = Parent;
            if (parent != null)
                ((WindowedControl)parent).PerformLayout();
        }

        canvas.FillRectangle(new Brush(SystemColors.Control),
                             Rectangle.FromBounds(0, 0, Width, Height));
        LayOutLabels(canvas);

        for (nuint i = 0u; i < _labelBounds.Count && i < _panes.Count; i++)
        {
            var box = _labelBounds[i];
            bool hot = (int)i == _hotLabel;

            canvas.FillRectangle(new Brush(hot ? SystemColors.ControlLight
                                              : SystemColors.Control), box);
            canvas.DrawRectangle(new Pen(SystemColors.ControlDark), box);

            String label = _panes[i].Title;
            var size = canvas.MeasureString(label, Font);
            canvas.DrawString(label, Font, SystemColors.ControlText,
                              box.X + (box.Width - size.Width) / 2,
                              box.Y + (box.Height - size.Height) / 2);
        }
    }

    int GetLabelAt(int x, int y)
    {
        var point = Point.FromXY(x, y);
        for (nuint i = 0u; i < _labelBounds.Count; i++)
        {
            if (_labelBounds[i].Contains(point))
                return (int)i;
        }
        return -1;
    }

    protected override void OnMouseMove(MouseEventArgs args)
    {
        base.OnMouseMove(args);
        int now = GetLabelAt(args.X, args.Y);
        if (now == _hotLabel)
            return;
        _hotLabel = now;
        Invalidate();

        // Hovering is what opens it, as it is in Visual Studio -- a pane you
        // have to click to peek at is a pane you unpin rather than use.
        if (now >= 0)
        {
            ChosenIndex = (nuint)now;
            Chosen(this);
        }
    }

    protected override void OnMouseLeave()
    {
        base.OnMouseLeave();
        if (_hotLabel < 0)
            return;
        _hotLabel = -1;
        Invalidate();
    }
}

// ==================================================================== a well

/// One edge's worth of tool windows: a caption, a tab per pane, and the panes.
///
/// A well is a child of the host for the whole session and never changes
/// parent. What changes is how it is docked -- see the note at the top of this
/// file -- so a well is pinned, hidden, or slid out over the documents, and all
/// three are this same object in the same place in the tree.
public class DockWell : Panel
{
    CaptionBar _caption;
    TabControl _tabs;
    List<ToolWindow> _panes;
    DockEdge _edge;

    /// The pane in front asked to be closed, or to be pinned or unpinned. The
    /// host decides what either does; a well reports and nothing more.
    public event EventHandler CloseRequested;
    public event EventHandler PinToggled;

    public DockWell(WindowedControl parent, DockEdge edge)
    {
        base(parent);
        _edge = edge;
        _panes = new List<ToolWindow>();

        // The book first so the caption, made second, stacks in front of it.
        // The layout would put them in different places anyway; this is about
        // the one pixel of overlap a border can produce.
        _tabs = new TabControl(this);
        _tabs.Dock = DockStyle.Fill;
        _tabs.SelectedIndexChanged += this.OnPageChanged;

        _caption = new CaptionBar(this);
        _caption.CloseClicked += this.OnCloseClicked;
        _caption.PinClicked += this.OnPinClicked;

        Border = ControlBorder.Single;
        Visible = false;
    }

    public DockEdge Edge => _edge;
    public List<ToolWindow> Panes => _panes;
    public bool IsEmpty => _panes.IsEmpty;

    /// Whether the caption is drawn as the pane being worked in.
    public bool Active
    {
        get => _caption.Active;
        set => _caption.Active = value;
    }

    /// Whether the pin is drawn pushed in. The host sets it; the well does not
    /// infer it, because a well whose panes disagree has no single answer and
    /// the host is what knows which pane the caption is speaking for.
    public bool Pinned
    {
        get => _caption.Pinned;
        set => _caption.Pinned = value;
    }

    /// Makes a pane in this well and answers it, ready to be built into.
    public ToolWindow AddPane(String name, String title)
    {
        var page = new TabPage(_tabs, title);
        var pane = new ToolWindow(page, name, title);
        _panes.Add(pane);
        UpdateCaption();
        Visible = true;
        return pane;
    }

    /// The pane in front, or null when the well is empty.
    public ToolWindow? Current
    {
        get
        {
            int at = _tabs.SelectedIndex;
            if (at < 0 || (nuint)at >= _panes.Count)
                return null;
            return _panes[(nuint)at];
        }
    }

    /// Brings a pane to the front of its well. Answers whether it is here.
    public bool SelectPane(String name)
    {
        for (nuint i = 0u; i < _panes.Count; i++)
        {
            if (_panes[i].PaneName == name)
            {
                _tabs.SelectedIndex = (int)i;
                UpdateCaption();
                return true;
            }
        }
        return false;
    }

    public ToolWindow? FindPane(String name)
    {
        foreach (var pane in _panes)
        {
            if (pane.PaneName == name)
                return pane;
        }
        return null;
    }

    /// The caption says what the front tab says.
    void UpdateCaption()
    {
        var now = Current;
        _caption.Title = now == null ? "" : ((ToolWindow)now).Title;
    }

    void OnPageChanged(Control sender) => UpdateCaption();
    void OnCloseClicked(Control sender) => CloseRequested(this);
    void OnPinClicked(Control sender) => PinToggled(this);
}

// ==================================================================== the host

/// The whole arrangement: three wells, three splitters, three auto-hide strips
/// and the document area in the middle.
///
/// **The order the children are made in is the layout**, because the layout
/// pass walks them in that order and each takes a full edge of what is left.
/// Strip, then well, then splitter, per edge -- so the strip is outermost
/// against the window edge, the well is inside it, and the splitter sits
/// between the well and the middle. The left and right edges are taken before
/// the bottom, which is what makes the side wells run the full height and the
/// bottom one span only the space between them, as Visual Studio does.
///
/// Changing that order changes the arrangement and nothing else says so, which
/// is why this paragraph is here rather than a comment per line.
public class DockHost : Panel
{
    DockLayout _layout;

    AutoHideStrip _leftStrip;
    AutoHideStrip _rightStrip;
    AutoHideStrip _bottomStrip;

    DockWell _leftWell;
    DockWell _rightWell;
    DockWell _bottomWell;

    Splitter _leftSplit;
    Splitter _rightSplit;
    Splitter _bottomSplit;

    Panel _documents;

    /// The well currently slid out over the documents, or null.
    DockWell? _flyout;
    /// Polls the pointer while a pane is slid out, so that it can slide back.
    Timer _pointerTimer;

    /// A pane was closed. The shell may want to update a menu tick.
    public event EventHandler PaneClosed;

    public DockHost(WindowedControl parent, DockLayout layout)
    {
        base(parent);
        _layout = layout;
        _flyout = null;

        _leftStrip = new AutoHideStrip(this, DockEdge.Left);
        _leftWell = new DockWell(this, DockEdge.Left);
        _leftWell.Dock = DockStyle.Left;
        _leftWell.Width = layout.LeftWidth;
        _leftSplit = new Splitter(this);
        _leftSplit.Dock = DockStyle.Left;
        _leftSplit.MinimumSize = SmallestWell;
        _leftSplit.Visible = false;

        _rightStrip = new AutoHideStrip(this, DockEdge.Right);
        _rightWell = new DockWell(this, DockEdge.Right);
        _rightWell.Dock = DockStyle.Right;
        _rightWell.Width = layout.RightWidth;
        _rightSplit = new Splitter(this);
        _rightSplit.Dock = DockStyle.Right;
        _rightSplit.MinimumSize = SmallestWell;
        _rightSplit.Visible = false;

        _bottomStrip = new AutoHideStrip(this, DockEdge.Bottom);
        _bottomWell = new DockWell(this, DockEdge.Bottom);
        _bottomWell.Dock = DockStyle.Bottom;
        _bottomWell.Height = layout.BottomHeight;
        _bottomSplit = new Splitter(this);
        _bottomSplit.Dock = DockStyle.Bottom;
        _bottomSplit.Cursor = CursorKind.SizeNorthSouth;
        _bottomSplit.MinimumSize = SmallestWell;
        _bottomSplit.Visible = false;

        // Last, so it takes what the edges left -- and so it is behind the
        // wells in the stacking order, which is what lets one slide out over it.
        _documents = new Panel(this);
        _documents.Dock = DockStyle.Fill;

        _leftWell.CloseRequested += this.OnCloseRequested;
        _rightWell.CloseRequested += this.OnCloseRequested;
        _bottomWell.CloseRequested += this.OnCloseRequested;

        _leftWell.PinToggled += this.OnPinToggled;
        _rightWell.PinToggled += this.OnPinToggled;
        _bottomWell.PinToggled += this.OnPinToggled;

        _leftStrip.Chosen += this.OnStripChosen;
        _rightStrip.Chosen += this.OnStripChosen;
        _bottomStrip.Chosen += this.OnStripChosen;

        _pointerTimer = new Timer(250);
        _pointerTimer.Tick += this.OnPointerTimerTick;
    }

    /// Where the editors go.
    public Panel Documents => _documents;

    /// The layout this is showing, which the shell saves on the way out.
    public DockLayout Layout => _layout;

    // ------------------------------------------------------------- the panes

    /// Makes a pane where the layout says it goes, and answers it to be built
    /// into.
    ///
    /// A pane the layout has never heard of goes where the caller says, which
    /// is what makes adding one to a later build work without anybody having to
    /// migrate a settings file.
    public ToolWindow AddPane(String name, String title, DockEdge fallback)
    {
        var placed = _layout.Find(name);
        DockEdge edge = placed == null ? fallback : ((DockPlacement)placed).Edge;
        bool pinned = placed == null ? true : ((DockPlacement)placed).IsPinned;

        if (placed == null)
            _layout.PlacePane(name, edge, pinned);

        return GetWellOn(edge).AddPane(name, title);
    }

    public ToolWindow AddPane(String name, String title) =>
        AddPane(name, title, DockEdge.Left);

    /// Brings a pane to the front of whatever well it is in, sliding that well
    /// out first if it is hidden. Answers whether the pane exists at all.
    public bool ShowPane(String name)
    {
        var well = FindWellHolding(name);
        if (well == null)
            return false;

        var found = (DockWell)well;
        var pane = found.FindPane(name);
        if (pane != null)
            ((ToolWindow)pane).Visible = true;

        if (!found.Visible)
            SlideOutWell(found);

        found.SelectPane(name);
        return true;
    }

    DockWell GetWellOn(DockEdge edge)
    {
        switch (edge)
        {
            case DockEdge.Right:
                return _rightWell;
            case DockEdge.Bottom:
                return _bottomWell;
            default:
                // Left, and the document well too: a pane cannot go among the
                // editors, so a layout saying it does puts it on the left
                // rather than nowhere.
                return _leftWell;
        }
    }

    DockWell? FindWellHolding(String name)
    {
        if (_leftWell.FindPane(name) != null)
            return _leftWell;
        if (_rightWell.FindPane(name) != null)
            return _rightWell;
        if (_bottomWell.FindPane(name) != null)
            return _bottomWell;
        return null;
    }

    AutoHideStrip GetStripOn(DockEdge edge)
    {
        switch (edge)
        {
            case DockEdge.Right:
                return _rightStrip;
            case DockEdge.Bottom:
                return _bottomStrip;
            default:
                return _leftStrip;
        }
    }

    Splitter GetSplitterOn(DockEdge edge)
    {
        switch (edge)
        {
            case DockEdge.Right:
                return _rightSplit;
            case DockEdge.Bottom:
                return _bottomSplit;
            default:
                return _leftSplit;
        }
    }

    // ------------------------------------------------------- showing a well

    /// Puts every well where the layout says, after the panes have been made.
    ///
    /// Called once, by the shell, when it has finished adding panes -- rather
    /// than on each `AddPane`, which would lay the window out four times and
    /// show each pane appearing.
    public void ArrangeWells()
    {
        ArrangeWell(_leftWell);
        ArrangeWell(_rightWell);
        ArrangeWell(_bottomWell);
        PerformLayout();
    }

    /// One well, shown pinned, or hidden behind its strip.
    void ArrangeWell(DockWell well)
    {
        var strip = GetStripOn(well.Edge);
        var split = GetSplitterOn(well.Edge);

        strip.ClearPanes();

        if (CountOpenPanes(well) == 0u)
        {
            well.Visible = false;
            split.Visible = false;
            strip.Visible = false;
            return;
        }

        bool pinned = IsAnyPanePinned(well);
        well.Pinned = pinned;

        if (pinned)
        {
            DockWellToEdge(well, well.Edge);
            well.Visible = true;
            split.Visible = true;
            strip.Visible = false;
            return;
        }

        // Unpinned: the well goes away and its panes become labels on the
        // strip. The well is not destroyed -- it cannot be, and it must not be,
        // since what is inside it is the live tree the IDE is still holding.
        well.Visible = false;
        split.Visible = false;

        foreach (var pane in well.Panes)
        {
            if (pane.Visible)
                strip.AddPane(pane);
        }
        strip.Visible = true;
    }

    /// How many panes in a well have not been closed.
    nuint CountOpenPanes(DockWell well)
    {
        nuint alive = 0u;
        foreach (var pane in well.Panes)
        {
            if (pane.Visible)
                alive++;
        }
        return alive;
    }

    /// Whether the layout says any pane in this well is pinned.
    ///
    /// **Any, not all**, because a well shows one pane at a time and pinning is
    /// a property of the well as far as the screen is concerned. The layout
    /// records it per pane because that is what the file has always meant and
    /// what a later build with draggable panes will need.
    bool IsAnyPanePinned(DockWell well)
    {
        foreach (var pane in well.Panes)
        {
            if (!pane.Visible)
                continue;
            var placed = _layout.Find(pane.PaneName);
            if (placed == null || ((DockPlacement)placed).IsPinned)
                return true;
        }
        return false;
    }

    void DockWellToEdge(DockWell well, DockEdge edge)
    {
        switch (edge)
        {
            case DockEdge.Bottom:
                well.Dock = DockStyle.Bottom;
                well.Height = _layout.BottomHeight;
                break;
            case DockEdge.Right:
                well.Dock = DockStyle.Right;
                well.Width = _layout.RightWidth;
                break;
            default:
                well.Dock = DockStyle.Left;
                well.Width = _layout.LeftWidth;
                break;
        }
    }

    // --------------------------------------------------------- sliding out

    /// Brings an unpinned well out over the documents, and starts watching for
    /// the pointer to leave.
    ///
    /// `DockStyle.None` and explicit bounds: the well is still a child of this
    /// host, so it can only cover this host's client area -- which is exactly
    /// the area the documents occupy, and is why the flyout looks right without
    /// anything being reparented or floated.
    void SlideOutWell(DockWell well)
    {
        if (_flyout == well)
            return;

        SlideBackWell();

        var room = ClientBounds;
        var over = _documents.Bounds;

        if (well.Edge == DockEdge.Bottom)
        {
            int tall = ClampFlyoutSize(_layout.BottomHeight, room.Height);
            well.Dock = DockStyle.None;
            well.SetBounds(over.X, over.Bottom - tall, over.Width, tall);
        }
        else if (well.Edge == DockEdge.Right)
        {
            int wide = ClampFlyoutSize(_layout.RightWidth, room.Width);
            well.Dock = DockStyle.None;
            well.SetBounds(over.Right - wide, over.Y, wide, over.Height);
        }
        else
        {
            int wide = ClampFlyoutSize(_layout.LeftWidth, room.Width);
            well.Dock = DockStyle.None;
            well.SetBounds(over.X, over.Y, wide, over.Height);
        }

        well.Visible = true;
        well.BringToFront();
        _flyout = well;
        _pointerTimer.Start();
    }

    /// How far a slid-out pane may come over the documents. Never more than
    /// half: a pane covering everything has nothing left to slide back over,
    /// and reads as having docked itself rather than as being temporary.
    int ClampFlyoutSize(int wanted, int available)
    {
        int most = available / FlyoutMostOfWindow;
        if (most < SmallestWell)
            return available;
        return wanted > most ? most : wanted;
    }

    /// Puts a slid-out well away again.
    void SlideBackWell()
    {
        var flying = _flyout;
        if (flying == null)
            return;

        _pointerTimer.Stop();
        _flyout = null;

        var well = (DockWell)flying;
        well.Visible = false;
        // Back to a docked style even though it is hidden, so that pinning it
        // again is one flag rather than a rebuild -- and so that a well left in
        // `None` can never be laid out as an overlay it no longer is.
        DockWellToEdge(well, well.Edge);
        PerformLayout();
    }

    /// The pointer left the slid-out pane, so it goes away.
    ///
    /// **A poll rather than a leave event**, and the seam carries
    /// `GetPointerPosition` for this reason. A container is told the pointer left
    /// the moment it moves onto one of that container's own children -- so a
    /// well would slide shut as soon as the pointer reached the tree inside it,
    /// which is the one place it is certainly meant to stay open.
    void OnPointerTimerTick(Timer sender)
    {
        var flying = _flyout;
        if (flying == null)
        {
            _pointerTimer.Stop();
            return;
        }

        var well = (DockWell)flying;
        var here = GetPointerPosition();

        // The strip counts as inside: the pointer travelling from the label
        // that opened the pane to the pane itself crosses it, and a pane that
        // shut on the way to being used would be unusable.
        if (well.Bounds.Contains(here) || GetStripOn(well.Edge).Bounds.Contains(here))
            return;

        SlideBackWell();
    }

    void OnStripChosen(Control sender)
    {
        var strip = (AutoHideStrip)sender;
        if (strip.ChosenIndex >= strip.Panes.Count)
            return;

        var pane = strip.Panes[strip.ChosenIndex];
        var well = FindWellHolding(pane.PaneName);
        if (well == null)
            return;

        SlideOutWell((DockWell)well);
        ((DockWell)well).SelectPane(pane.PaneName);
    }

    // ----------------------------------------------------- pinning, closing

    /// The pin was clicked. An unpinned well slides away to its strip; a pinned
    /// one comes back and takes its space again.
    void OnPinToggled(Control sender)
    {
        var well = (DockWell)sender;
        bool pinned = !IsAnyPanePinned(well);

        // Every pane in the well, because the well is what is being pinned --
        // see `IsAnyPanePinned` for why the file still records it per pane.
        foreach (var pane in well.Panes)
        {
            _layout.PlacePane(pane.PaneName, well.Edge, pinned);
        }

        SlideBackWell();
        ArrangeWell(well);
        PerformLayout();
    }

    /// The close box was clicked. Only the pane in front closes; the others in
    /// the well stay where they are.
    void OnCloseRequested(Control sender)
    {
        var well = (DockWell)sender;
        var pane = well.Current;
        if (pane != null)
            ClosePane(((ToolWindow)pane).PaneName);
    }

    /// Hides one pane. It is hidden rather than destroyed -- what is inside it
    /// is live and the IDE still holds it -- and the layout remembers, so a
    /// closed pane stays closed between runs.
    public bool ClosePane(String name)
    {
        var well = FindWellHolding(name);
        if (well == null)
            return false;

        var found = (DockWell)well;
        var pane = found.FindPane(name);
        if (pane == null)
            return false;

        ((ToolWindow)pane).Visible = false;

        SlideBackWell();
        ArrangeWell(found);
        PerformLayout();
        PaneClosed(this);
        return true;
    }

    /// Whether a pane is on the screen at all, as opposed to merely existing.
    public bool IsPaneShowing(String name)
    {
        var well = FindWellHolding(name);
        if (well == null)
            return false;
        var pane = ((DockWell)well).FindPane(name);
        return pane != null && ((ToolWindow)pane).Visible;
    }

    // -------------------------------------------------- remembering the drag

    /// Reads the well sizes back off the controls, which is where a splitter
    /// drag leaves them, so that the layout about to be written says what is on
    /// the screen.
    ///
    /// Pulled rather than pushed: a splitter sets its neighbour's width
    /// directly and raises nothing, so there is no drag-finished event to
    /// listen for. Asking at the point the answer is wanted is both simpler and
    /// impossible to miss.
    public void RememberWellSizes()
    {
        if (_leftWell.Visible && _leftWell.Dock == DockStyle.Left)
            _layout.LeftWidth = _leftWell.Width;
        if (_rightWell.Visible && _rightWell.Dock == DockStyle.Right)
            _layout.RightWidth = _rightWell.Width;
        if (_bottomWell.Visible && _bottomWell.Dock == DockStyle.Bottom)
            _layout.BottomHeight = _bottomWell.Height;
    }

    // ------------------------------------------------------------ self test

    /// What a headless check can ask of the host. Everything here is a fact
    /// about the model the controls are showing, not about pixels -- the
    /// arrangement itself is only provable by screenshot, and `ide/README.md`
    /// says so.
    public nuint PaneCount =>
        _leftWell.Panes.Count + _rightWell.Panes.Count + _bottomWell.Panes.Count;

    public bool HasPane(String name) => FindWellHolding(name) != null;

    /// The rectangle the splitter for an edge occupies, in this host's own
    /// coordinates.
    ///
    /// **A splitter is windowless**, so nothing about it is visible to the
    /// platform: whether it can be grabbed is entirely whether this rectangle
    /// is where the pointer is. An empty one is a divider nobody can drag and
    /// a cursor that never changes, which is invisible to every other check.
    public Rectangle GetSplitterBounds(DockEdge edge) => GetSplitterOn(edge).Bounds;

    public bool IsSplitterShowing(DockEdge edge) => GetSplitterOn(edge).Visible;

    /// Which edge a pane is actually on, as opposed to what the file asked for.
    public DockEdge GetEdgeOf(String name)
    {
        var well = FindWellHolding(name);
        if (well == null)
            return DockEdge.Document;
        return ((DockWell)well).Edge;
    }

    public bool IsWellShowing(DockEdge edge) => GetWellOn(edge).Visible;
    public bool IsStripShowing(DockEdge edge) => GetStripOn(edge).Visible;
}
