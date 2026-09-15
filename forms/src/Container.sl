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

// The two halves of the LCL's control split, and the layout pass that arranges
// them.
//
// `GraphicControl` is `TGraphicControl`: no platform window, drawn by whatever
// contains it. `WindowedControl` is `TWinControl`: it owns a peer, so the
// platform knows where it is, gives it the keyboard and clips its children.
//
// **The layout algorithm is the LCL's, and deliberately.** Docking to an edge
// and anchoring to one are two rules that interact, and the order they are
// applied in is the whole of whether a form looks right: docked controls take
// their bite out of the client area in sequence, each seeing what the ones
// before it left, and only then do the undocked controls stretch to their
// anchors in what remains. WinForms does the same thing in the opposite order
// and has the dock-fill-under-a-toolbar bug to show for it.
module Forms;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;

/// Aborts with a message, for a mistake in the calling program.
extern "C" void sl_fail(byte* message);

// =========================================================== graphic control

/// A control with no platform window, painted by its parent.
///
/// **What it costs and what it saves.** No handle means no keyboard focus, no
/// native scrolling, and nothing underneath it clipped away -- so it cannot
/// contain anything and cannot be typed into. What it saves is the handle: on
/// Windows a window is a kernel object with a message queue slot, and a form
/// with two hundred labels that each had one is a form that is slow to build
/// and slow to close. This is the LCL's answer to that and it is the right one.
///
/// A derived class overrides `OnPaint` and draws. It is called with the
/// parent's `Graphics`, already translated so that (0,0) is this control's
/// top-left corner and already clipped to its bounds.
public abstract class GraphicControl : Control
{
    protected GraphicControl(WindowedControl parent)
    {
        base();
        parent.Add(this);
    }

    /// A graphic control has no window to capture with, so it asks its parent
    /// -- which is also what routes the events back to it while it holds it.
    public override void CaptureMouse(bool captured)
    {
        var parent = Parent;
        if (parent == null)
            return;
        ((WindowedControl)parent).CaptureFor(captured ? this : null);
    }

    /// The cursor is the parent's to set, for the same reason: there is no
    /// window here for Windows to ask about.
    protected override void ApplyCursor()
    {
        var parent = Parent;
        if (parent != null)
            ((WindowedControl)parent).RefreshCursor();
    }

    /// Repainting a graphic control means repainting the part of the parent it
    /// sits on, because the parent is what will draw it.
    public override void Invalidate()
    {
        var parent = Parent;
        if (parent != null)
            ((WindowedControl)parent).InvalidateRegion(Bounds);
    }

    /// Draws this control on its parent's surface.
    ///
    /// Called only by `WindowedControl.OnPaint`, which is the one thing that
    /// knows a graphic control needs asking.
    ///
    /// **The layer is what makes the coordinates its own.** Without it the
    /// surface is the parent's: a control drawing at (0, 0) would draw at the
    /// *form's* corner rather than its own, and could draw over its siblings --
    /// the protection a real window gets from the platform for nothing. The
    /// clip and the origin are pushed together and put back together.
    void PaintOn(Graphics surface)
    {
        int layer = surface.PushLayer(Bounds);
        OnPaint(PaintEventArgs.Of(surface, Rectangle.Of(0, 0, Width, Height)));
        surface.PopLayer(layer);
    }
}

// =========================================================== windowed control

/// A control the platform knows about, and the only thing that may contain
/// others.
///
/// **The peer arrives after the constructor body of the base has run.** A
/// derived control calls `base(parent)` to be parented, then `AttachPeer` with
/// whatever the widget set made for it. Between those two moments the control
/// exists with no platform side, which is why every property setter here works
/// whether or not there is a peer yet and `AttachPeer` pushes the lot down when
/// one appears. That replaces the LCL's `HandleNeeded`/`CreateWnd` dance and
/// the `csCreating` flag that guards it.
public abstract class WindowedControl : Control
{
    IControlPeer? _platform;
    /// The same peer again, when it is one children can go inside.
    ///
    /// Held separately rather than tested for, because `is` does not ask
    /// whether a reference also implements an interface -- it converts an
    /// interface reference down to a class, which is the other direction. So
    /// the control that knows its peer is a container is the one that says so,
    /// by calling `AttachContainerPeer` instead of `AttachPeer`.
    IContainerPeer? _asContainer;
    List<Control> _inside;
    bool _laying;

    protected WindowedControl(WindowedControl? parent)
    {
        base();
        _platform = null;
        _asContainer = null;
        _inside = new List<Control>();
        _laying = false;
        _grabbed = null;
        _hovered = null;
        _lastClient = Size.Empty;
        if (parent != null)
            ((WindowedControl)parent).Add(this);
    }

    // ---------------------------------------------------------------- peer

    /// The platform's side of this control, once it has one.
    protected IControlPeer? Peer => _platform;

    /// This control as something children can be put inside. Fails if the peer
    /// is not a container, which is a mistake in the control that attached it
    /// rather than anything a program did.
    protected IContainerPeer ContainerPeer()
    {
        var mine = _asContainer;
        if (mine == null)
        {
            sl_fail("this control cannot contain others".ToPointer());
        }
        return (IContainerPeer)mine;
    }

    /// The peer of whatever contains this control, which is what a widget set
    /// needs to make a child widget.
    protected IContainerPeer ParentPeer()
    {
        var parent = Parent;
        if (parent == null)
        {
            sl_fail("this control has no parent to be created inside".ToPointer());
        }
        return ((WindowedControl)parent).ContainerPeer();
    }

    /// Takes ownership of the platform widget and pushes down everything that
    /// was set before it existed.
    ///
    /// Called once, from the constructor of the concrete control. The order
    /// matters: bounds before visibility, so the widget is never shown at the
    /// wrong size for one frame.
    protected void AttachPeer(IControlPeer made)
    {
        _platform = made;
        PushDown(made);
    }

    /// The same, for a peer that other controls may be put inside.
    protected void AttachContainerPeer(IContainerPeer made)
    {
        IControlPeer asControl = made;
        _platform = asControl;
        _asContainer = made;
        PushDown(made);
    }

    void PushDown(IControlPeer made)
    {
        made.SetBounds(Bounds);
        made.SetFont(Font);
        made.SetForeColor(ForeColor);
        made.SetBackColor(BackColor);
        if (StoredText.ByteLength() > 0u)
            made.SetText(StoredText);
        made.SetEnabled(Enabled);
        made.SetVisible(Visible);
    }

    /// The platform handle, for reaching an API this layer does not wrap: an
    /// `HWND` on Windows, a `GtkWidget*` on GTK. Zero when there is no peer.
    public nuint Handle
    {
        get
        {
            var mine = _platform;
            if (mine == null)
                return 0u;
            return ((IControlPeer)mine).Handle();
        }
    }

    // ------------------------------------------------------------- children

    /// The controls inside this one, in the order they were added -- which is
    /// also the order the layout pass gives them the client area in.
    public List<Control> Controls => _inside;

    /// Takes a control in. Called by the child's own constructor, which is why
    /// it is not public: a control chooses its parent once, at birth.
    void Add(Control child)
    {
        _inside.Add(child);
        child.Adopt(this);
        PerformLayout();
    }

    /// Every control inside this one, and inside those, and so on.
    public List<Control> Descendants()
    {
        var found = new List<Control>();
        Gather(found);
        return found;
    }

    void Gather(List<Control> into)
    {
        foreach (var child in _inside)
        {
            into.Add(child);
            if (child is WindowedControl container)
                container.Gather(into);
        }
    }

    // --------------------------------------------------------- the overrides

    /// The area children go in, which the platform decides -- a group box keeps
    /// room for its caption, a form for its menu bar, and neither figure is
    /// anything this layer could work out.
    public override Rectangle ClientBounds
    {
        get
        {
            var mine = _platform;
            if (mine == null)
                return base.ClientBounds;
            return ((IControlPeer)mine).ClientBounds();
        }
    }

    public override Size PreferredSize
    {
        get
        {
            var mine = _platform;
            if (mine == null)
                return Size.Empty;
            return ((IControlPeer)mine).PreferredSize();
        }
    }

    /// Where this control's own children begin, inside it. Zero for everything
    /// but a group box; see `IControlPeer.ClientOrigin`.
    public Point ClientOrigin
    {
        get
        {
            var mine = _platform;
            if (mine == null)
                return Point.Empty;
            return ((IControlPeer)mine).ClientOrigin();
        }
    }

    protected override void ApplyBounds()
    {
        var mine = _platform;
        if (mine == null || IsEchoing)
            return;
        ((IControlPeer)mine).SetBounds(InParentSpace(Bounds));
    }

    /// This control's bounds as the platform wants them: measured from the
    /// parent widget's own corner rather than from the corner of the area it
    /// gives its children. The two differ only under a group box.
    Rectangle InParentSpace(Rectangle bounds)
    {
        var parent = Parent;
        if (parent == null)
            return bounds;
        var origin = ((WindowedControl)parent).ClientOrigin;
        if (origin.X == 0 && origin.Y == 0)
            return bounds;
        return Rectangle.Of(bounds.X + origin.X, bounds.Y + origin.Y,
                            bounds.Width, bounds.Height);
    }

    protected override void ApplyVisible()
    {
        var mine = _platform;
        if (mine != null)
            ((IControlPeer)mine).SetVisible(Visible);
    }

    protected override void ApplyEnabled()
    {
        var mine = _platform;
        if (mine != null)
            ((IControlPeer)mine).SetEnabled(Enabled);
    }

    protected override void ApplyText()
    {
        var mine = _platform;
        if (mine != null && !IsEchoing)
            ((IControlPeer)mine).SetText(StoredText);
    }

    protected override void ApplyFont()
    {
        var mine = _platform;
        if (mine != null)
            ((IControlPeer)mine).SetFont(Font);
        // A child that inherits its font has just had it changed too, and only
        // this control knows that happened.
        foreach (var child in _inside)
        {
            if (child is WindowedControl windowed)
                windowed.ApplyFont();
        }
    }

    protected override void ApplyForeColor()
    {
        var mine = _platform;
        if (mine != null)
            ((IControlPeer)mine).SetForeColor(ForeColor);
    }

    protected override void ApplyBackColor()
    {
        var mine = _platform;
        if (mine != null)
            ((IControlPeer)mine).SetBackColor(BackColor);
    }

    protected override void ApplyCursor()
    {
        var mine = _platform;
        if (mine != null)
            ((IControlPeer)mine).SetCursor(Cursor);
    }

    public override void CaptureMouse(bool captured)
    {
        var mine = _platform;
        if (mine != null)
            ((IControlPeer)mine).SetCapture(captured);
    }

    // ------------------------------------------- the mouse, for the windowless
    //
    // A `GraphicControl` has no window, so every message about it arrives here
    // instead and has to be hit-tested and passed on. That is the cost of the
    // LCL's control split, and it is paid once -- here -- rather than by each
    // control that wants it.

    /// Which graphic child holds the mouse, or null.
    GraphicControl? _grabbed;
    /// Which one the pointer was last over, so that entering and leaving can be
    /// reported at all -- Windows says nothing about a control it cannot see.
    GraphicControl? _hovered;

    /// The topmost graphic child at a point in this control's coordinates.
    ///
    /// Backwards, because a later child is drawn on top of an earlier one, and
    /// what is on top is what the mouse should find.
    GraphicControl? GraphicAt(Point at)
    {
        nuint count = _inside.Count();
        for (nuint i = count; i > 0u; i--)
        {
            var child = _inside.At(i - 1u);
            if (!child.Visible || !child.Enabled)
                continue;
            if (child is GraphicControl drawn)
            {
                if (drawn.Bounds.Contains(at))
                    return drawn;
            }
        }
        return null;
    }

    /// Called by a graphic child taking or giving up the mouse.
    void CaptureFor(GraphicControl? child)
    {
        _grabbed = child;
        var mine = _platform;
        if (mine != null)
            ((IControlPeer)mine).SetCapture(child != null);
    }

    /// Re-asks the platform what the pointer should look like, after a graphic
    /// child changed its mind about it.
    void RefreshCursor() { }

    /// Where a point in this control's coordinates is in a child's.
    Point Within(Control child, Point at)
    {
        return Point.At(at.X - child.Left, at.Y - child.Top);
    }

    /// Whichever graphic child a mouse message belongs to: the one holding the
    /// mouse if any, otherwise whatever is under the pointer.
    GraphicControl? MouseTarget(Point at)
    {
        var held = _grabbed;
        if (held != null)
            return held;
        return GraphicAt(at);
    }

    public override void OnPlatformMouseDown(MouseButton button, Point at,
                                             ModifierKeys modifiers)
    {
        var target = MouseTarget(at);
        if (target != null)
        {
            var child = (GraphicControl)target;
            child.OnPlatformMouseDown(button, Within(child, at), modifiers);
            return;
        }
        base.OnPlatformMouseDown(button, at, modifiers);
    }

    public override void OnPlatformMouseUp(MouseButton button, Point at,
                                           ModifierKeys modifiers)
    {
        var target = MouseTarget(at);
        if (target != null)
        {
            var child = (GraphicControl)target;
            child.OnPlatformMouseUp(button, Within(child, at), modifiers);
            return;
        }
        base.OnPlatformMouseUp(button, at, modifiers);
    }

    public override void OnPlatformMouseMove(Point at, ModifierKeys modifiers)
    {
        var target = MouseTarget(at);

        // Entering and leaving a windowless control is this method's doing --
        // the pointer never crosses a window boundary, so nothing else would
        // ever notice. Reported before the move, so a handler that sets up on
        // enter has done so before the first move arrives.
        var was = _hovered;
        if (was != target)
        {
            if (was != null)
                ((GraphicControl)was).OnPlatformMouseLeave();
            _hovered = target;
            if (target != null)
                ((GraphicControl)target).OnPlatformMouseEnter();
        }

        if (target != null)
        {
            var child = (GraphicControl)target;
            child.OnPlatformMouseMove(Within(child, at), modifiers);
            return;
        }
        base.OnPlatformMouseMove(at, modifiers);
    }

    /// The pointer left this control's window, so it has left any graphic child
    /// it was over too.
    public override void OnPlatformMouseLeave()
    {
        var was = _hovered;
        if (was != null)
        {
            _hovered = null;
            ((GraphicControl)was).OnPlatformMouseLeave();
        }
        base.OnPlatformMouseLeave();
    }

    public override void Invalidate()
    {
        var mine = _platform;
        if (mine != null)
            ((IControlPeer)mine).Invalidate();
    }

    /// Marks part of this control as needing repainting. Falls back to the
    /// whole of it, since no peer interface takes a region yet -- a real
    /// narrowing is worth having once anything paints enough to need it.
    public void InvalidateRegion(Rectangle part) => Invalidate();

    /// Paints it now rather than when the platform gets round to it.
    public void Update()
    {
        var mine = _platform;
        if (mine != null)
            ((IControlPeer)mine).Update();
    }

    /// Gives this control the keyboard.
    public void Focus()
    {
        var mine = _platform;
        if (mine != null)
            ((IControlPeer)mine).Focus();
    }

    public bool Focused
    {
        get
        {
            var mine = _platform;
            if (mine == null)
                return false;
            return ((IControlPeer)mine).HasFocus();
        }
    }

    // -------------------------------------------------------------- layout

    /// Arranges the children: docked ones first, in order, then anchored ones
    /// in what is left.
    ///
    /// **Docked first, and in order.** Each docked control takes a full edge of
    /// what remains and hands the smaller rectangle to the next, so a menu
    /// docked to the top and a status bar docked to the bottom leave a middle
    /// that a third control set to `Fill` gets exactly. Reversing the two
    /// passes, or sorting the docked ones by anything but insertion order, is
    /// what makes a toolbar end up underneath a filled editor.
    ///
    /// **Re-entrant by one flag.** Setting a child's bounds raises its resize,
    /// which a handler may answer by changing something that lays out again;
    /// without the guard that is unbounded recursion the first time anyone
    /// writes such a handler.
    public void PerformLayout()
    {
        if (_laying)
            return;
        var mine = _platform;
        if (mine == null)
            return;

        _laying = true;

        var free = ClientBounds;

        foreach (var child in _inside)
        {
            if (!child.Visible)
                continue;
            var how = child.Dock;
            if (how == DockStyle.None)
                continue;

            if (how == DockStyle.Top)
            {
                int height = child.Height;
                if (height > free.Height)
                    height = free.Height;
                child.SetBounds(free.X, free.Y, free.Width, height);
                free = Rectangle.Of(free.X, free.Y + height, free.Width, free.Height - height);
            }
            else if (how == DockStyle.Bottom)
            {
                int height = child.Height;
                if (height > free.Height)
                    height = free.Height;
                child.SetBounds(free.X, free.Bottom - height, free.Width, height);
                free = Rectangle.Of(free.X, free.Y, free.Width, free.Height - height);
            }
            else if (how == DockStyle.Left)
            {
                int width = child.Width;
                if (width > free.Width)
                    width = free.Width;
                child.SetBounds(free.X, free.Y, width, free.Height);
                free = Rectangle.Of(free.X + width, free.Y, free.Width - width, free.Height);
            }
            else if (how == DockStyle.Right)
            {
                int width = child.Width;
                if (width > free.Width)
                    width = free.Width;
                child.SetBounds(free.Right - width, free.Y, width, free.Height);
                free = Rectangle.Of(free.X, free.Y, free.Width - width, free.Height);
            }
        }

        // `Fill` takes everything the edges left, and the last one wins if a
        // program docked two -- which is a mistake, and one the LCL also lets
        // through rather than diagnosing.
        foreach (var child in _inside)
        {
            if (!child.Visible)
                continue;
            if (child.Dock == DockStyle.Fill)
            {
                child.SetBounds(free.X, free.Y, free.Width, free.Height);
            }
        }

        _laying = false;
    }

    /// Re-anchors the undocked children after this control changed size.
    ///
    /// Separate from `PerformLayout` because it needs the *previous* client
    /// size to work out what each edge distance was, and only the resize
    /// notification knows that. An anchor is a distance held constant: a
    /// control anchored left and right keeps both gaps and therefore stretches;
    /// one anchored left only keeps its left gap and its width.
    void ReAnchor(Size wasClient, Size nowClient)
    {
        int growX = nowClient.Width - wasClient.Width;
        int growY = nowClient.Height - wasClient.Height;
        if (growX == 0 && growY == 0)
            return;

        foreach (var child in _inside)
        {
            if (child.Dock != DockStyle.None)
                continue;

            var at = child.Bounds;
            var how = child.Anchors;

            int x = at.X;
            int width = at.Width;
            bool left = how.HasFlag(AnchorStyles.Left);
            bool right = how.HasFlag(AnchorStyles.Right);
            if (left && right)
            {
                width = width + growX;
            }
            else if (right)
            {
                x = x + growX;
            }
            else if (!left)   // neither: stay centred
            {
                x = x + growX / 2;
            }

            int y = at.Y;
            int height = at.Height;
            bool top = how.HasFlag(AnchorStyles.Top);
            bool bottom = how.HasFlag(AnchorStyles.Bottom);
            if (top && bottom)
            {
                height = height + growY;
            }
            else if (bottom)
            {
                y = y + growY;
            }
            else if (!top)
            {
                y = y + growY / 2;
            }

            if (width < 0)
                width = 0;
            if (height < 0)
                height = 0;

            child.SetBounds(x, y, width, height);
        }
    }

    /// A resize is where both layout rules run: the anchored children move by
    /// how much the client area grew, and the docked ones are laid out afresh.
    protected override void OnResize()
    {
        var mine = _platform;
        if (mine != null && !_laying)
        {
            var now = ClientBounds.Extent;
            var was = _lastClient;
            _lastClient = now;
            if (!was.Equals(Size.Empty))
            {
                _laying = true;
                ReAnchor(was, now);
                _laying = false;
            }
        }
        base.OnResize();
        PerformLayout();
    }

    Size _lastClient;

    // --------------------------------------------------- painting children

    /// Paints this control, then every `GraphicControl` on it.
    ///
    /// A graphic control has no window, so nothing else would ever ask it to
    /// draw. The `Graphics` it is handed is this control's, so a graphic
    /// control's coordinates are its parent's -- the offset is applied by the
    /// control itself when it draws, which keeps the backend free of any idea
    /// that graphic controls exist.
    protected override void OnPaint(PaintEventArgs args)
    {
        base.OnPaint(args);
        foreach (var child in _inside)
        {
            if (!child.Visible)
                continue;
            if (child is GraphicControl drawn)
            {
                drawn.PaintOn(args.Graphics);
            }
        }
    }
}
