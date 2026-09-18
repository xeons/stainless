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

// The controls that hold other controls, and the scroll bar.
//
// A `Panel` and a `GroupBox` are the two ways of grouping: one invisible and
// one with a frame and a caption. Both matter beyond their appearance, because
// a parent is what decides a radio button's group and what a docked child docks
// inside -- so `Panel` is the answer to "two sets of radio buttons on one form"
// as much as it is to "a toolbar strip along the top".
module Forms;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;

// ==================================================================== panel

/// A plain container, optionally with a border.
///
/// ```
/// var strip = new Panel(this);
/// strip.Dock = DockStyle.Top;
/// strip.Height = 32;
/// ```
public class Panel : WindowedControl
{
    IPanelPeer _native;
    ControlBorder _edging;

    public Panel(WindowedControl parent)
    {
        base(parent);
        _edging = ControlBorder.None;
        _native = WidgetSet.Current.CreatePanel(this, ParentPeer());
        AttachContainerPeer(_native);
    }

    /// The frame drawn around it.
    public ControlBorder Border
    {
        get => _edging;
        set
        {
            _edging = value;
            _native.SetBorder(value);
            PerformLayout();
        }
    }
}

// ================================================================= group box

/// A frame with a caption, that other controls sit inside.
///
/// Its client area is inset by the frame and the caption, which the platform
/// works out -- so a control docked to the top of a group box lands under the
/// caption rather than through it.
public class GroupBox : WindowedControl
{
    IGroupPeer _native;

    public GroupBox(WindowedControl parent)
    {
        base(parent);
        _native = WidgetSet.Current.CreateGroup(this, ParentPeer());
        AttachContainerPeer(_native);
    }

    /// The caption across the top of the frame.
    public String Caption
    {
        get => Text;
        set => Text = value;
    }
}

// =============================================================== scroll bar

/// A scroll bar standing on its own.
///
/// **Not what a scrolling container uses.** A `ScrollBox` -- which does not
/// exist yet -- would use the scroll bars the platform attaches to a window,
/// which are a different thing with a different API. This is the control you
/// place on a form when the thing being scrolled is yours.
public class ScrollBar : WindowedControl
{
    IScrollBarPeer _native;
    bool _vertical;
    int _minimum;
    int _maximum;
    int _page;

    public ScrollBar(WindowedControl parent, bool vertical)
    {
        base(parent);
        this._vertical = vertical;
        _minimum = 0;
        _maximum = 100;
        _page = 10;
        _native = WidgetSet.Current.CreateScrollBar(this, ParentPeer(), vertical);
        AttachPeer(_native);
        _native.SetRange(_minimum, _maximum, _page);
    }

    /// Whether it scrolls up and down rather than left and right.
    public bool IsVertical => _vertical;

    public int Minimum
    {
        get => _minimum;
        set
        {
            _minimum = value;
            _native.SetRange(_minimum, _maximum, _page);
        }
    }

    public int Maximum
    {
        get => _maximum;
        set
        {
            _maximum = value;
            _native.SetRange(_minimum, _maximum, _page);
        }
    }

    /// How much one page-down moves by, and how large the thumb is drawn -- the
    /// two are the same number on every platform, because the thumb's size is
    /// what shows how much of the whole is visible.
    public int PageSize
    {
        get => _page;
        set
        {
            _page = value;
            _native.SetRange(_minimum, _maximum, _page);
        }
    }

    /// Where the thumb is.
    public int Value
    {
        get => _native.GetValue();
        set => _native.SetValue(value);
    }

    /// The thumb moved, whoever moved it.
    public event EventHandler ValueChanged;

    protected virtual void OnValueChanged() => ValueChanged(this);

    public override void OnPlatformValueChanged() => OnValueChanged();
}

// ============================================================ custom control

/// A control the program draws every pixel of, and that takes the keyboard.
///
/// ```
/// public class Grid : CustomControl {
///     public Grid(WindowedControl parent) {
///         base(parent);
///         Border = ControlBorder.Sunken;
///     }
///
///     protected override void OnPaint(PaintEventArgs args) {
///         args.Graphics.Clear(BackColor);
///         args.Graphics.DrawString("cell", Font, ForeColor, 4, 4);
///     }
///
///     protected override void OnKeyDown(KeyEventArgs args) {
///         if (args.Key == Key.Down) { Invalidate(); }
///     }
/// }
/// ```
///
/// **`PaintBox` is the one to reach for first.** A `PaintBox` is a
/// `GraphicControl`: it costs nothing but an object, its parent draws it, and
/// for anything that only displays -- a chart, a gauge, a preview -- that is
/// the right trade. What it cannot do is take the focus, because it has no
/// window to give the focus to, so no keystroke ever reaches one. This is the
/// other half: a real window of its own, which is what the keyboard, a caret
/// and a scroll bar of its own all need.
///
/// **It draws its whole client area, and nothing else does.** The platform is
/// told not to erase the background, so a paint handler that does not cover
/// every pixel shows whatever the buffer held. `Clear` on the first line is the
/// usual answer. What that buys is a control drawn into an off-screen buffer
/// and copied over in one go, which is the difference between a caret blinking
/// over text and the text blinking with it.
///
/// **A container, like a `Panel`.** Anything may be put inside one, and the
/// children are drawn over what the control painted -- which is the order a
/// scroll bar beside its own content needs.
public class CustomControl : WindowedControl
{
    ICustomPeer _native;
    ControlBorder _edging;
    Rectangle _insertion;
    bool _takesFocus;

    public CustomControl(WindowedControl parent)
    {
        base(parent);
        _edging = ControlBorder.None;
        _insertion = Rectangle.Empty;
        _takesFocus = true;
        _native = WidgetSet.Current.CreateCustom(this, ParentPeer());
        AttachContainerPeer(_native);
    }

    /// The frame drawn around it.
    public ControlBorder Border
    {
        get => _edging;
        set
        {
            _edging = value;
            _native.SetBorder(value);
            PerformLayout();
        }
    }

    /// Whether clicking it and tabbing to it give it the keyboard.
    ///
    /// A drawn control that only displays says false and leaves the tab order
    /// alone -- which is a different thing from one that takes the focus and
    /// happens to handle no keys, because the second still takes the focus away
    /// from whatever had it.
    public bool Focusable
    {
        get => _takesFocus;
        set
        {
            _takesFocus = value;
            _native.SetFocusable(value);
        }
    }

    /// Where the insertion point is and how big, in this control's own
    /// coordinates. `Rectangle.Empty` -- the default -- for a control with no
    /// caret at all.
    ///
    /// **Set it, and stop thinking about it.** The platform owns the blink and
    /// owns the appearing and disappearing as the focus moves, so a control
    /// that has just moved its caret has finished: there is no timer to start,
    /// nothing to hide before painting and nothing to put back after.
    public Rectangle Caret
    {
        get => _insertion;
        set
        {
            _insertion = value;
            _native.SetCaret(value);
        }
    }
}

// ================================================================= notebook

/// One page of a `Notebook`.
///
/// A real container, so controls are put on it exactly as they are put on a
/// panel. It is never laid out by the program: the notebook fills itself with
/// whichever page is showing and hides the rest.
public class NotebookPage : Panel
{
    int _index;

    public NotebookPage(Notebook owner, String name)
    {
        base(owner);
        StoredText = name;
        _index = owner.Register(this);
    }

    /// Which page this is, counting from zero.
    public int Index => _index;

    /// Told its new number after a page in front of it was removed. Called by
    /// `Notebook.RemovePage` and by nothing else.
    public void Renumber(int now) => _index = now;

    /// What this page is called. Not drawn anywhere -- there are no tabs -- so
    /// it is what a program looks a page up by and what a status line or a
    /// wizard's heading would show. `Caption` rather than `Name` because
    /// `Control.Name` already means the identifier a program knows a control
    /// by, and because `TabPage` spells the same thing the same way.
    public String Caption
    {
        get => StoredText;
        set => StoredText = value;
    }
}

/// A stack of pages with no tabs, of which one shows at a time.
///
/// **`TabControl` without the tabs, and that is the entire point.** The LCL
/// keeps `TNotebook`/`TPage` beside `TPageControl`/`TTabSheet` for the case
/// where the program decides which page is showing and the user never does:
/// a wizard driven by Back and Next, a settings dialog whose list on the left
/// chooses the panel on the right, a status area that swaps between three
/// layouts. Done with a `TabControl` those need the tab strip hidden, which no
/// platform offers -- Windows has no style for it and GTK's
/// `gtk_notebook_set_show_tabs` leaves the border behind.
///
/// So this is not a platform control at all. It is a `Panel` that fills itself
/// with one child and hides the others, which is exactly what `TNotebook` is:
/// the GTK 3 widgetset registers `TGtk3WSNotebook` and `TGtk3WSPage` as empty
/// classes, because there is nothing for a widgetset to do.
///
/// ```
/// var steps = new Notebook(this);
/// steps.Dock = DockStyle.Fill;
/// var welcome = new NotebookPage(steps, "Welcome");
/// var options = new NotebookPage(steps, "Options");
/// var done    = new NotebookPage(steps, "Finished");
/// steps.SelectedIndex = 0;
/// ```
public class Notebook : Panel
{
    List<NotebookPage>? _pages;
    int _chosen;

    public Notebook(WindowedControl parent)
    {
        base(parent);
        _pages = new List<NotebookPage>();
        _chosen = -1;
    }

    /// Called by a `NotebookPage` as it is built. Not public: a page joins the
    /// notebook it was constructed with, and there is no other way in.
    int Register(NotebookPage page)
    {
        var held = _pages;
        if (held == null)
            return -1;
        var list = (List<NotebookPage>)held;
        list.Add(page);
        int at = (int)list.Count - 1;
        // The first page added becomes the one showing, so a notebook is never
        // a blank rectangle with pages in it that nothing selected.
        if (_chosen < 0)
            _chosen = 0;
        ShowOnly();
        return at;
    }

    public List<NotebookPage> Pages
    {
        get
        {
            var held = _pages;
            if (held == null)
                return new List<NotebookPage>();
            return (List<NotebookPage>)held;
        }
    }

    public int PageCount => (int)Pages.Count;

    /// Which page is showing, or -1 for a notebook with none.
    public int SelectedIndex
    {
        get => _chosen;
        set
        {
            int count = PageCount;
            int wanted = value;
            if (wanted >= count)
                wanted = count - 1;
            if (wanted < 0)
                wanted = count == 0 ? -1 : 0;
            if (wanted == _chosen)
                return;
            _chosen = wanted;
            ShowOnly();
            OnSelectedIndexChanged();
        }
    }

    public NotebookPage? SelectedPage
    {
        get
        {
            var list = Pages;
            if (_chosen < 0 || (nuint)_chosen >= list.Count)
                return null;
            return list[(nuint)_chosen];
        }
    }

    /// The page of that name, or null if there is none. What a program that
    /// named its pages rather than counting them asks with.
    public NotebookPage? Find(String name)
    {
        var list = Pages;
        for (nuint i = 0u; i < list.Count; i++)
        {
            if (list[i].Caption == name)
                return list[i];
        }
        return null;
    }

    /// Takes a page out and answers whether it was there.
    ///
    /// The page is hidden rather than destroyed, as `TabControl.RemovePage`
    /// does it and for the same reason: a control's lifetime is its parent's,
    /// and dropping the last reference to it is what destroys it.
    public bool RemovePage(NotebookPage page)
    {
        var list = Pages;
        nuint at = 0u;
        bool found = false;
        for (nuint i = 0u; i < list.Count; i++)
        {
            if (list[i] == page)
            {
                at = i;
                found = true;
                break;
            }
        }
        if (!found)
            return false;

        list.RemoveAt(at);
        page.Visible = false;
        for (nuint i = at; i < list.Count; i++)
            list[i].Renumber((int)i);

        // Removing the page that was showing moves the selection to whatever
        // took its place, or to the last page when it was the last.
        if (_chosen >= (int)list.Count)
            _chosen = (int)list.Count - 1;
        ShowOnly();
        OnSelectedIndexChanged();
        return true;
    }

    /// Shows the chosen page filling the client area and hides the rest.
    ///
    /// The same job `TabControl.ShowOnly` does, minus the platform: there is no
    /// tab control underneath to ask where the page area is, so it is the whole
    /// of the client area.
    void ShowOnly()
    {
        var held = _pages;
        if (held == null)
            return;
        var list = (List<NotebookPage>)held;
        var area = ClientBounds;
        for (nuint i = 0u; i < list.Count; i++)
        {
            var page = list[i];
            bool wanted = (int)i == _chosen;
            page.Visible = wanted;
            if (wanted)
                page.Bounds = area;
        }
    }

    /// The chosen page changed.
    public event EventHandler SelectedIndexChanged;

    protected virtual void OnSelectedIndexChanged() => SelectedIndexChanged(this);

    /// A resize moves the page area, so whichever page is showing follows it.
    ///
    /// **The null test is not defensive.** The base constructor resizes, and
    /// this override runs before this class's own fields exist -- the same trap
    /// C# has with a virtual call from a base constructor, and the same one
    /// `RadioGroup` and `CheckGroup` guard against.
    protected override void OnResize()
    {
        base.OnResize();
        if (_pages == null)
            return;
        ShowOnly();
    }
}
