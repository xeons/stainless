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
        parent.AddControl(this);
    }

    /// A graphic control has no window to capture with, so it asks its parent
    /// -- which is also what routes the events back to it while it holds it.
    public override void CaptureMouse(bool captured)
    {
        var parent = Parent;
        if (parent == null)
            return;
        ((WindowedControl)parent).CaptureMouseFor(captured ? this : null);
    }

    /// The cursor is the parent's to set, for the same reason: there is no
    /// window here for Windows to ask about.
    protected override void ApplyCursor()
    {
        var parent = Parent;
        if (parent != null)
            ((WindowedControl)parent).RefreshCursor();
    }

    /// **A graphic control cannot have a tip of its own**, and the parent's
    /// would be wrong: a tool is a window, and this control does not have one,
    /// so the tip would cover the whole parent. Saying nothing is the honest
    /// answer until `forms/` has a tool that is a rectangle.
    protected override void ApplyToolTip() { }

    /// Repainting a graphic control means repainting the part of the parent it
    /// sits on, because the parent is what will draw it.
    public override void Invalidate()
    {
        var parent = Parent;
        if (parent != null)
            ((WindowedControl)parent).InvalidateRegion(Bounds);
    }

    // Nothing here tells a platform anything, so every change that alters how
    // the control looks MUST ask its parent to paint it again. A hidden one is
    // repainted over where it was.
    protected override void ApplyVisible()   => Invalidate();
    protected override void ApplyEnabled()   => Invalidate();
    protected override void ApplyText()      => Invalidate();
    protected override void ApplyFont()      => Invalidate();
    protected override void ApplyForeColor() => Invalidate();
    protected override void ApplyBackColor() => Invalidate();

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
    ///
    /// The surface is the parent widget's, which starts at the widget's corner
    /// rather than at its client area; under a group box the two differ.
    void PaintOnSurface(Graphics surface, Point origin)
    {
        var at = Bounds;
        int layer = surface.PushLayer(Rectangle.FromBounds(at.X + origin.X, at.Y + origin.Y,
                                                   at.Width, at.Height));
        OnPaint(PaintEventArgs.FromGraphics(surface, Rectangle.FromBounds(0, 0, Width, Height)));
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
    IControlPeer? _peer;
    /// The same peer again, when it is one children can go inside.
    ///
    /// Held separately rather than tested for, because `is` does not ask
    /// whether a reference also implements an interface -- it converts an
    /// interface reference down to a class, which is the other direction. So
    /// the control that knows its peer is a container is the one that says so,
    /// by calling `AttachContainerPeer` instead of `AttachPeer`.
    IContainerPeer? _containerPeer;
    List<Control> _children;
    ControlList _controls;
    bool _isLayingOut;

    protected WindowedControl(WindowedControl? parent)
    {
        base();
        _peer = null;
        _containerPeer = null;
        _children = new List<Control>();
        _controls = new ControlList(_children);
        _isLayingOut = false;
        _grabbed = null;
        _hovered = null;
        _pressed = null;
        if (parent != null)
            ((WindowedControl)parent).AddControl(this);
    }

    // ---------------------------------------------------------------- peer

    /// The platform's side of this control, once it has one.
    protected IControlPeer? Peer => _peer;

    /// This control as something children can be put inside. Fails if the peer
    /// is not a container, which is a mistake in the control that attached it
    /// rather than anything a program did.
    protected IContainerPeer ContainerPeer
    {
        get
        {
            var mine = _containerPeer;
            if (mine == null)
            {
                sl_fail("this control cannot contain others".ToPointer());
            }
            return (IContainerPeer)mine;
        }
    }

    /// The peer of whatever contains this control, which is what a widget set
    /// needs to make a child widget.
    protected IContainerPeer ParentPeer
    {
        get
        {
            var parent = Parent;
            if (parent == null)
            {
                sl_fail("this control has no parent to be created inside".ToPointer());
            }
            return ((WindowedControl)parent).ContainerPeer;
        }
    }

    /// Takes ownership of the platform widget and pushes down everything that
    /// was set before it existed.
    ///
    /// Called once, from the constructor of the concrete control. The order
    /// matters: bounds before visibility, so the widget is never shown at the
    /// wrong size for one frame.
    protected void AttachPeer(IControlPeer made)
    {
        _peer = made;
        PushStateToPeer(made);
    }

    /// The same, for a peer that other controls may be put inside.
    protected void AttachContainerPeer(IContainerPeer made)
    {
        IControlPeer asControl = made;
        _peer = asControl;
        _containerPeer = made;
        PushStateToPeer(made);
    }

    void PushStateToPeer(IControlPeer made)
    {
        made.SetBounds(Bounds);
        made.SetFont(Font);
        made.SetForeColor(ForeColor);
        made.SetBackColor(BackColor);
        if (StoredText.ByteLength() > 0u)
            made.SetText(StoredText);
        made.SetEnabled(IsEnabled);
        made.SetVisible(Visible);
    }

    /// Lets go of the platform widget, and of every one inside it: the
    /// control stays an object, with nothing on screen behind it.
    void ReleasePeer()
    {
        foreach (var child in _children)
        {
            if (child is WindowedControl windowed)
                windowed.ReleasePeer();
        }
        var mine = _peer;
        if (mine != null)
            ((IControlPeer)mine).DestroyHandle();
        _peer = null;
        _containerPeer = null;
    }

    /// The platform handle, for reaching an API this layer does not wrap: an
    /// `HWND` on Windows, a `GtkWidget*` on GTK. Zero when there is no peer.
    public nuint Handle
    {
        get
        {
            var mine = _peer;
            if (mine == null)
                return 0u;
            return ((IControlPeer)mine).Handle;
        }
    }

    // ------------------------------------------------------------- children

    /// The controls inside this one, in the order they were added -- which is
    /// also the order the layout pass gives them the client area in.
    ///
    /// A view, not a copy, and not a list to change: a control joins by being
    /// made with this as its parent and leaves by `RemoveControl`.
    public ControlList Controls => _controls;

    /// Takes a control in. Called by the child's own constructor, which is why
    /// it is not public: a control chooses its parent once, at birth.
    void AddControl(Control child)
    {
        _children.Add(child);
        child.AttachToParent(this);
        PerformLayout();
    }

    /// Takes a child out, and answers whether it was one.
    ///
    /// **Its platform widget is destroyed**, and those of everything inside
    /// it: a control cannot be given another parent, so the widget has nowhere
    /// left to be. The object lives on while something holds it, with `Parent`
    /// null and nothing on screen; dropping the last reference frees it.
    public bool RemoveControl(Control child)
    {
        nuint count = _children.Count;
        for (nuint i = 0u; i < count; i++)
        {
            if (_children[i] != child)
                continue;

            _children.RemoveAt(i);
            ClearMouseStateFor(child);
            child.DetachFromParent();
            if (child is WindowedControl windowed)
                windowed.ReleasePeer();
            Invalidate();
            PerformLayout();
            return true;
        }
        return false;
    }

    /// Drops every reference the mouse routing holds to a child that is going.
    void ClearMouseStateFor(Control child)
    {
        if (_grabbed == child)
        {
            _grabbed = null;
            var mine = _peer;
            if (mine != null)
                ((IControlPeer)mine).SetCapture(false);
        }
        if (_hovered == child)
            _hovered = null;
        if (_pressed == child)
            _pressed = null;
    }

    /// Every control inside this one, and inside those, and so on.
    public List<Control> GetDescendants()
    {
        var found = new List<Control>();
        CollectDescendants(found);
        return found;
    }

    void CollectDescendants(List<Control> into)
    {
        foreach (var child in _children)
        {
            into.Add(child);
            if (child is WindowedControl container)
                container.CollectDescendants(into);
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
            var mine = _peer;
            if (mine == null)
                return base.ClientBounds;
            return ((IControlPeer)mine).ClientBounds;
        }
    }

    public override Size PreferredSize
    {
        get
        {
            var mine = _peer;
            if (mine == null)
                return Size.Empty;
            return ((IControlPeer)mine).PreferredSize;
        }
    }

    /// Where this control's own children begin, inside it. Zero for everything
    /// but a group box; see `IControlPeer.ClientOrigin`.
    public Point ClientOrigin
    {
        get
        {
            var mine = _peer;
            if (mine == null)
                return Point.Empty;
            return ((IControlPeer)mine).ClientOrigin;
        }
    }

    protected override void ApplyBounds()
    {
        var mine = _peer;
        if (mine == null || IsEchoing)
            return;
        ((IControlPeer)mine).SetBounds(ToParentSpace(Bounds));
    }

    /// This control's bounds as the platform wants them: measured from the
    /// parent widget's own corner rather than from the corner of the area it
    /// gives its children. The two differ only under a group box.
    Rectangle ToParentSpace(Rectangle bounds)
    {
        var parent = Parent;
        if (parent == null)
            return bounds;
        var origin = ((WindowedControl)parent).ClientOrigin;
        if (origin.X == 0 && origin.Y == 0)
            return bounds;
        return Rectangle.FromBounds(bounds.X + origin.X, bounds.Y + origin.Y,
                            bounds.Width, bounds.Height);
    }

    protected override void ApplyVisible()
    {
        var mine = _peer;
        if (mine != null)
            ((IControlPeer)mine).SetVisible(Visible);
    }

    /// Tells the platform whether this control can be used, which a disabled
    /// parent decides as well; see `IsEnabled`. Every child is told again,
    /// because its answer has just changed too.
    protected override void ApplyEnabled()
    {
        var mine = _peer;
        if (mine != null)
            ((IControlPeer)mine).SetEnabled(IsEnabled);
        foreach (var child in _children)
        {
            if (child is WindowedControl windowed)
            {
                windowed.ApplyEnabled();
            }
            else
            {
                child.Invalidate();
            }
        }
    }

    protected override void ApplyText()
    {
        var mine = _peer;
        if (mine != null && !IsEchoing)
            ((IControlPeer)mine).SetText(StoredText);
    }

    protected override void ApplyFont()
    {
        var mine = _peer;
        if (mine != null)
            ((IControlPeer)mine).SetFont(Font);
        // A child that inherits its font has just had it changed too, and only
        // this control knows that happened.
        foreach (var child in _children)
        {
            if (child is WindowedControl windowed)
                windowed.ApplyFont();
        }
    }

    /// A child with no colour of its own inherits this one, so it has just
    /// changed too -- and only this control knows that happened.
    protected override void ApplyForeColor()
    {
        var mine = _peer;
        if (mine != null)
            ((IControlPeer)mine).SetForeColor(ForeColor);
        foreach (var child in _children)
        {
            if (!child.HasOwnForeColor)
                child.ApplyForeColor();
        }
    }

    protected override void ApplyBackColor()
    {
        var mine = _peer;
        if (mine != null)
            ((IControlPeer)mine).SetBackColor(BackColor);
        foreach (var child in _children)
        {
            if (!child.HasOwnBackColor)
                child.ApplyBackColor();
        }
    }

    protected override void ApplyCursor()
    {
        var mine = _peer;
        if (mine != null)
            ((IControlPeer)mine).SetCursor(Cursor);
    }

    protected override void ApplyToolTip()
    {
        var mine = _peer;
        if (mine != null)
            ((IControlPeer)mine).SetToolTip(ToolTip);
    }

    public override void CaptureMouse(bool captured)
    {
        var mine = _peer;
        if (mine != null)
            ((IControlPeer)mine).SetCapture(captured);
    }

    public override void BringToFront()
    {
        var mine = _peer;
        if (mine != null)
            ((IControlPeer)mine).BringToFront();
    }

    public override Point GetPointerPosition()
    {
        var mine = _peer;
        if (mine == null)
            return Point.Empty;
        return ((IControlPeer)mine).GetPointerPosition();
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
    /// Which one took the last press, or null for this control itself.
    GraphicControl? _pressed;

    /// The topmost graphic child at a point the platform reported, which is
    /// measured from this widget's corner rather than its client area.
    ///
    /// Backwards, because a later child is drawn on top of an earlier one, and
    /// what is on top is what the mouse should find.
    GraphicControl? FindGraphicAt(Point reported)
    {
        var origin = ClientOrigin;
        var at = Point.FromXY(reported.X - origin.X, reported.Y - origin.Y);
        nuint count = _children.Count;
        for (nuint i = count; i > 0u; i--)
        {
            var child = _children[i - 1u];
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
    void CaptureMouseFor(GraphicControl? child)
    {
        _grabbed = child;
        var mine = _peer;
        if (mine != null)
            ((IControlPeer)mine).SetCapture(child != null);
    }

    /// What the pointer should look like, given which windowless child it is
    /// over.
    ///
    /// **The platform never asks a graphic control**, because there is no
    /// window to ask about. It asks this one, so this one answers for whichever
    /// windowless child the pointer is over and for itself when it is over
    /// none -- which is what puts a resize cursor over a splitter.
    void RefreshCursor()
    {
        var mine = _peer;
        if (mine == null)
            return;

        var over = _hovered;
        ((IControlPeer)mine).SetCursor(over == null
                                       ? Cursor : ((Control)over).Cursor);
    }

    /// Where a point the platform reported is in a child's coordinates.
    Point ToChildSpace(Control child, Point reported)
    {
        var origin = ClientOrigin;
        return Point.FromXY(reported.X - origin.X - child.Left,
                        reported.Y - origin.Y - child.Top);
    }

    /// Whichever graphic child a mouse message belongs to: the one holding the
    /// mouse if any, otherwise whatever is under the pointer.
    GraphicControl? FindMouseTarget(Point at)
    {
        var held = _grabbed;
        if (held != null)
            return held;
        return FindGraphicAt(at);
    }

    public override void OnPlatformMouseDown(MouseButton button, Point at,
                                             ModifierKeys modifiers)
    {
        var target = FindMouseTarget(at);
        _pressed = target;
        if (target != null)
        {
            var child = (GraphicControl)target;
            child.OnPlatformMouseDown(button, ToChildSpace(child, at), modifiers);
            return;
        }
        base.OnPlatformMouseDown(button, at, modifiers);
    }

    public override void OnPlatformMouseUp(MouseButton button, Point at,
                                           ModifierKeys modifiers)
    {
        var target = FindMouseTarget(at);
        if (target != null)
        {
            var child = (GraphicControl)target;
            child.OnPlatformMouseUp(button, ToChildSpace(child, at), modifiers);
            return;
        }
        base.OnPlatformMouseUp(button, at, modifiers);
    }

    public override void OnPlatformMouseMove(Point at, ModifierKeys modifiers)
    {
        var target = FindMouseTarget(at);

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

            // The cursor belongs to whatever the pointer is over, and a
            // windowless child is only ever discovered here.
            RefreshCursor();
        }

        if (target != null)
        {
            var child = (GraphicControl)target;
            child.OnPlatformMouseMove(ToChildSpace(child, at), modifiers);
            return;
        }
        base.OnPlatformMouseMove(at, modifiers);
    }

    /// The second click of a double-click has already been reported as a
    /// press, so the child that took that press takes this.
    public override void OnPlatformDoubleClick()
    {
        var pressed = _pressed;
        if (pressed != null)
        {
            ((GraphicControl)pressed).OnPlatformDoubleClick();
            return;
        }
        base.OnPlatformDoubleClick();
    }

    public override void OnPlatformMouseWheel(int delta, Point at, ModifierKeys modifiers)
    {
        var target = FindMouseTarget(at);
        if (target != null)
        {
            var child = (GraphicControl)target;
            child.OnPlatformMouseWheel(delta, ToChildSpace(child, at), modifiers);
            return;
        }
        base.OnPlatformMouseWheel(delta, at, modifiers);
    }

    /// A menu asked for over a graphic child is offered to it first, and to
    /// this control when it shows none. One asked for from the keyboard has no
    /// pointer, so it is this control's.
    public override bool OnPlatformContextMenu(Point at, bool fromKeyboard)
    {
        if (!fromKeyboard)
        {
            var target = FindMouseTarget(at);
            if (target != null)
            {
                var child = (GraphicControl)target;
                if (child.OnPlatformContextMenu(ToChildSpace(child, at), false))
                    return true;
            }
        }
        return base.OnPlatformContextMenu(at, fromKeyboard);
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
        var mine = _peer;
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
        var mine = _peer;
        if (mine != null)
            ((IControlPeer)mine).Update();
    }

    /// Gives this control the keyboard.
    public void Focus()
    {
        var mine = _peer;
        if (mine != null)
            ((IControlPeer)mine).Focus();
    }

    public bool Focused
    {
        get
        {
            var mine = _peer;
            if (mine == null)
                return false;
            return ((IControlPeer)mine).HasFocus;
        }
    }

    // -------------------------------------------------------------- layout

    /// The room children are laid out in, or empty when there is none: no
    /// peer yet, or a window minimised to its icon.
    Size LayoutClient
    {
        get
        {
            if (_peer == null)
                return Size.Empty;
            return ClientBounds.Extent;
        }
    }

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
    /// **Everything is computed from what was asked for.** A docked control
    /// is sized from its request, and an anchored one from the request its
    /// anchors were measured against, so a layout never reads back what an
    /// earlier layout squeezed. An area with no room at all lays out nothing,
    /// since a minimised window reports one, and the next layout with room
    /// puts every control back.
    ///
    /// **Re-entrant by one flag.** Setting a child's bounds raises its resize,
    /// which a handler may answer by changing something that lays out again;
    /// without the guard that is unbounded recursion the first time anyone
    /// writes such a handler.
    public void PerformLayout()
    {
        if (_isLayingOut)
            return;
        var client = LayoutClient;
        if (client.IsEmpty)
            return;

        _isLayingOut = true;

        var free = ClientBounds;

        foreach (var child in _children)
        {
            if (!child.Visible)
                continue;
            var asked = child.RequestedBounds;

            switch (child.Dock)
            {
                case DockStyle.Top:
                {
                    child.SetBoundsCore(Rectangle.FromBounds(free.X, free.Y, free.Width,
                                             ClampToRoom(asked.Height, free.Height)));
                    int took = ClampToRoom(child.Height, free.Height);
                    free = Rectangle.FromBounds(free.X, free.Y + took, free.Width, free.Height - took);
                    break;
                }

                case DockStyle.Bottom:
                {
                    int height = ClampToRoom(asked.Height, free.Height);
                    child.SetBoundsCore(Rectangle.FromBounds(free.X, free.Bottom - height, free.Width, height));
                    int took = ClampToRoom(child.Height, free.Height);
                    free = Rectangle.FromBounds(free.X, free.Y, free.Width, free.Height - took);
                    break;
                }

                case DockStyle.Left:
                {
                    child.SetBoundsCore(Rectangle.FromBounds(free.X, free.Y,
                                             ClampToRoom(asked.Width, free.Width), free.Height));
                    int took = ClampToRoom(child.Width, free.Width);
                    free = Rectangle.FromBounds(free.X + took, free.Y, free.Width - took, free.Height);
                    break;
                }

                case DockStyle.Right:
                {
                    int width = ClampToRoom(asked.Width, free.Width);
                    child.SetBoundsCore(Rectangle.FromBounds(free.Right - width, free.Y, width, free.Height));
                    int took = ClampToRoom(child.Width, free.Width);
                    free = Rectangle.FromBounds(free.X, free.Y, free.Width - took, free.Height);
                    break;
                }

                default:
                    break;
            }
        }

        // `Fill` takes everything the edges left, and the last one wins if a
        // program docked two -- which is a mistake, and one the LCL also lets
        // through rather than diagnosing.
        foreach (var child in _children)
        {
            if (!child.Visible)
                continue;
            if (child.Dock == DockStyle.Fill)
                child.SetBoundsCore(free);
        }

        foreach (var child in _children)
        {
            if (child.Dock == DockStyle.None)
                child.SetBoundsCore(child.ComputeAnchoredBounds(client));
        }

        _isLayingOut = false;
    }

    /// A size, held between zero and what is left.
    ///
    /// The platform MAY make a control larger than it was given -- GTK keeps a
    /// widget at its minimum -- so what a docked control took is read back from
    /// it, and held to the room there was.
    static int ClampToRoom(int wanted, int room)
    {
        if (wanted > room)
            wanted = room;
        if (wanted < 0)
            wanted = 0;
        return wanted;
    }

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
        var origin = ClientOrigin;
        foreach (var child in _children)
        {
            if (!child.Visible)
                continue;
            if (child is GraphicControl drawn)
            {
                drawn.PaintOnSurface(args.Graphics, origin);
            }
        }
    }
}

// ============================================================== the children

/// The controls inside a `WindowedControl`, to read and not to change.
///
/// A view of the live list rather than a copy, so it is always current and
/// costs nothing to ask for. `RemoveControl` is how a child leaves.
public class ControlList : IReadOnlyList<Control>
{
    List<Control> _items;

    ControlList(List<Control> items) => _items = items;

    public nuint Count => _items.Count;
    public bool IsEmpty => _items.IsEmpty;
    public Control this[nuint index] { get => _items[index]; }

    public IEnumerator<Control> GetEnumerator() => new ListEnumerator<Control>(this);
}
