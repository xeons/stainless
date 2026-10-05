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

// The AppKit backend: what every peer has in common, and the view the
// controls this library draws itself are made of.
//
// **Every view here is flipped.** AppKit puts the origin at the bottom left and
// this library at the top left, so `FormsView` answers `isFlipped` and a
// child's frame is then the control's bounds as they stand. A point is a
// pixel, as GTK's logical pixel is; a scaled screen draws each one with more.
//
// **Command is Control.** A Forms program reads Ctrl+C as copy, and a Mac user
// presses Command+C, so both keys report `ModifierKeys.Control`; Option is Alt.
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
import MacOS.QuartzCore;
import MacOS.Foundation;
import MacOS.AppKit;

using FPoint = Forms.Drawing.Point;
using FSize  = Forms.Drawing.Size;
using FRect  = Forms.Drawing.Rectangle;

// =================================================================== values

public FPoint CreatePoint(int x, int y) => Forms.Drawing.Point.FromXY(x, y);
public FSize  CreateSize(int width, int height) => Forms.Drawing.Size.FromDimensions(width, height);

public FRect CreateRectangle(int x, int y, int width, int height) =>
    Forms.Drawing.Rectangle.FromBounds(x, y, width, height);

public NSRect ToNSRect(FRect bounds)
{
    NSRect rect;
    rect.origin.x = (double)bounds.X;
    rect.origin.y = (double)bounds.Y;
    rect.size.width = (double)bounds.Width;
    rect.size.height = (double)bounds.Height;
    return rect;
}

public NSRect MakeNSRect(double x, double y, double width, double height)
{
    NSRect rect;
    rect.origin.x = x;
    rect.origin.y = y;
    rect.size.width = width;
    rect.size.height = height;
    return rect;
}

/// Whole pixels, rounded toward the top left, as a rectangle a control holds.
public FRect FromNSRect(NSRect rect) =>
    CreateRectangle(FloorToInt(rect.origin.x), FloorToInt(rect.origin.y),
                    RoundToInt(rect.size.width), RoundToInt(rect.size.height));

public int FloorToInt(double value)
{
    int whole = (int)value;
    return (double)whole > value ? whole - 1 : whole;
}

public int RoundToInt(double value) => FloorToInt(value + 0.5);

/// A String as AppKit holds text.
public NSString ToNSString(String text) => NSString.StringWithUTF8String(text.ToPointer())!;

/// AppKit's text as a String, or "" for none.
public String FromNSString(NSString? text)
{
    if (text == null)
        return "";
    var bytes = ((NSString)text).UTF8String;
    return bytes == null ? "" : Text.FromNullTerminated((byte*)bytes);
}

public NSColor ToNSColor(Color color) =>
    NSColor.ColorWithSRGBRedGreenBlueAlpha((double)(int)color.R / 255.0, (double)(int)color.G / 255.0,
                                           (double)(int)color.B / 255.0, (double)(int)color.A / 255.0);

/// A colour AppKit names -- a theme's, which may be a pattern or a catalog
/// entry -- as the four bytes it comes to in sRGB now.
public Color FromNSColor(NSColor? color)
{
    var space = NSColorSpace.SRGBColorSpace;
    if (color == null || space == null)
        return Colors.Black;
    var resolved = ((NSColor)color).ColorUsingColorSpace((NSColorSpace)space);
    if (resolved == null)
        return Colors.Black;
    var srgb = (NSColor)resolved;
    return Color.FromArgb(ToChannel(srgb.AlphaComponent), ToChannel(srgb.RedComponent),
                          ToChannel(srgb.GreenComponent), ToChannel(srgb.BlueComponent));
}

byte ToChannel(double value)
{
    int scaled = RoundToInt(value * 255.0);
    return (byte)(scaled < 0 ? 0 : scaled > 255 ? 255 : scaled);
}

// ==================================================================== input

/// The modifiers held during an event. See the file's header for Command.
public ModifierKeys GetModifiers(NSEventModifierFlags flags)
{
    var held = ModifierKeys.None;
    if (flags.HasFlag(NSEventModifierFlags.Shift))
        held = held | ModifierKeys.Shift;
    if (flags.HasFlag(NSEventModifierFlags.Command) || flags.HasFlag(NSEventModifierFlags.Control))
        held = held | ModifierKeys.Control;
    if (flags.HasFlag(NSEventModifierFlags.Option))
        held = held | ModifierKeys.Alt;
    return held;
}

/// A key by what it means, from the hardware key code a Mac reports -- which
/// names a position on an ANSI keyboard, as Win32's scan code does, and which
/// is what a shortcut wants whatever the layout types there.
public Key GetKey(ushort code)
{
    switch ((int)code)
    {
        case 0: return Key.A;
        case 1: return Key.S;
        case 2: return Key.D;
        case 3: return Key.F;
        case 4: return Key.H;
        case 5: return Key.G;
        case 6: return Key.Z;
        case 7: return Key.X;
        case 8: return Key.C;
        case 9: return Key.V;
        case 11: return Key.B;
        case 12: return Key.Q;
        case 13: return Key.W;
        case 14: return Key.E;
        case 15: return Key.R;
        case 16: return Key.Y;
        case 17: return Key.T;
        case 18: return Key.D1;
        case 19: return Key.D2;
        case 20: return Key.D3;
        case 21: return Key.D4;
        case 22: return Key.D6;
        case 23: return Key.D5;
        case 25: return Key.D9;
        case 26: return Key.D7;
        case 28: return Key.D8;
        case 29: return Key.D0;
        case 31: return Key.O;
        case 32: return Key.U;
        case 34: return Key.I;
        case 35: return Key.P;
        case 36: return Key.Enter;
        case 37: return Key.L;
        case 38: return Key.J;
        case 40: return Key.K;
        case 45: return Key.N;
        case 46: return Key.M;
        case 48: return Key.Tab;
        case 49: return Key.Space;
        case 51: return Key.Backspace;
        case 53: return Key.Escape;
        case 56: return Key.Shift;
        case 57: return Key.CapsLock;
        case 58: return Key.Alt;
        case 55:
        case 59: return Key.Control;
        case 76: return Key.Enter;
        case 96: return Key.F5;
        case 97: return Key.F6;
        case 98: return Key.F7;
        case 99: return Key.F3;
        case 100: return Key.F8;
        case 101: return Key.F9;
        case 103: return Key.F11;
        case 109: return Key.F10;
        case 111: return Key.F12;
        case 114: return Key.Insert;
        case 115: return Key.Home;
        case 116: return Key.PageUp;
        case 117: return Key.Delete;
        case 118: return Key.F4;
        case 119: return Key.End;
        case 120: return Key.F2;
        case 121: return Key.PageDown;
        case 122: return Key.F1;
        case 123: return Key.Left;
        case 124: return Key.Right;
        case 125: return Key.Down;
        case 126: return Key.Up;
        default: return Key.None;
    }
}

MouseButton GetMouseButton(NSEvent event)
{
    switch ((int)event.ButtonNumber)
    {
        case 0: return (event.ModifierFlags.HasFlag(NSEventModifierFlags.Control)) ? MouseButton.Right : MouseButton.Left;
        case 1: return MouseButton.Right;
        default: return MouseButton.Middle;
    }
}

// ===================================================================== view

/// The view behind every control this library draws itself, and the content
/// of every window: flipped, drawn by the control, and reporting the pointer
/// and the keyboard to it.
public objc class FormsView : NSView
{
    /// The peer this view belongs to. Weak, since the peer holds the view.
    public weak AppKitPeer? Peer;

    /// The fill behind what the control draws, or none for a view the siblings
    /// beneath show through.
    public bool FillsBackground;
    public Color Background;

    /// Whether clicking it gives it the keyboard.
    public bool Focusable;

    /// Whether the views under it show through, though it still takes the
    /// pointer over its whole area.
    public bool Transparent;

    NSTrackingArea? _tracking;

    /// The peer, if it is still alive.
    public AppKitPeer? FindPeer()
    {
        AppKitPeer? held = Peer;
        return held;
    }

    public override bool Flipped => true;

    public override bool AcceptsFirstResponder => Focusable;

    /// A click on a window that is not in front is the control's as well as
    /// the window's, as it is on Windows and GTK. AppKit's own default spends
    /// it on bringing the window forward.
    public override bool AcceptsFirstMouse(NSEvent? event) => true;

    public override bool BecomeFirstResponder()
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportFocus(true);
        return true;
    }

    public override bool ResignFirstResponder()
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportFocus(false);
        return true;
    }

    /// The background is the view's bounds and not the dirty rectangle, which
    /// AppKit may make the whole window.
    public override void DrawRect(NSRect dirtyRect)
    {
        if (FillsBackground && !Transparent)
        {
            ToNSColor(Background).SetFill();
            NSBezierPath.FillRect(Bounds);
        }
        if (FindPeer() is AppKitPeer peer)
            peer.ReportPaint(dirtyRect);
    }

    /// Hears the pointer move with no button down, and cross the edge, for as
    /// long as the view is in a window. `InVisibleRect` keeps the area the
    /// view's own as it is resized.
    public void TrackPointer()
    {
        if (_tracking != null)
            return;
        var options = NSTrackingAreaOptions.MouseMoved | NSTrackingAreaOptions.MouseEnteredAndExited
                      | NSTrackingAreaOptions.ActiveInKeyWindow | NSTrackingAreaOptions.InVisibleRect;
        var area = NSTrackingArea.Alloc().InitWithRectOptionsOwnerUserInfo(Bounds, options, this, null);
        AddTrackingArea(area);
        _tracking = area;
    }

    public override void MouseDown(NSEvent event) => ReportPress(event);
    public override void RightMouseDown(NSEvent event) => ReportPress(event);
    public override void OtherMouseDown(NSEvent event) => ReportPress(event);
    public override void MouseUp(NSEvent event) => ReportRelease(event);
    public override void RightMouseUp(NSEvent event) => ReportRelease(event);
    public override void MouseMoved(NSEvent event) => ReportMove(event);
    public override void MouseDragged(NSEvent event) => ReportMove(event);
    public override void RightMouseDragged(NSEvent event) => ReportMove(event);

    public override void MouseEntered(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportCrossing(true);
    }

    public override void MouseExited(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportCrossing(false);
    }

    public override void ScrollWheel(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportWheel(event, PointOf(event));
    }

    public override void KeyDown(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportKey(event, true);
    }

    public override void KeyUp(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportKey(event, false);
    }

    void ReportPress(NSEvent event)
    {
        var window = Window;
        if (Focusable && window != null)
            ((NSWindow)window).MakeFirstResponder(this);
        if (FindPeer() is AppKitPeer peer)
            peer.ReportPress(event, PointOf(event));
    }

    void ReportRelease(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportRelease(event, PointOf(event));
    }

    void ReportMove(NSEvent event)
    {
        if (FindPeer() is AppKitPeer peer)
            peer.ReportMove(event, PointOf(event));
    }

    FPoint PointOf(NSEvent event) => FindEventPoint(this, event);
}

/// Where an event happened, in a view's own coordinates. A native control is
/// not flipped, so its height is taken off; a `FormsView` already measures
/// down from the top.
public FPoint FindEventPoint(NSView view, NSEvent event)
{
    var at = view.ConvertPointFromView(event.LocationInWindow, null);
    double y = view.Flipped ? at.y : view.Bounds.size.height - at.y;
    return CreatePoint(FloorToInt(at.x), FloorToInt(y));
}

// ===================================================================== peer

/// What every AppKit control's peer is: a view, and the control it reports to.
public class AppKitPeer : IControlPeer
{
    /// The view the parent places.
    public NSView View { get; protected set; }

    protected weak IControlNotify? Target;

    /// Where the control layer last put it, as asked.
    protected FRect LastBounds;

    protected bool IsDestroyed;
    protected bool IsDesigning;
    CursorKind _cursor;
    bool _captured;

    public AppKitPeer(NSView made, IControlNotify? owner)
    {
        View = made;
        Target = owner;
        LastBounds = CreateRectangle(0, 0, 0, 0);
        IsDestroyed = false;
        IsDesigning = false;
        _cursor = CursorKind.Default;
        _captured = false;
        if (made is FormsView drawn)
        {
            drawn.Peer = this;
            drawn.TrackPointer();
        }
    }

    ~AppKitPeer() { DestroyHandle(); }

    protected IControlNotify? Owner
    {
        get
        {
            IControlNotify? held = Target;
            return held;
        }
    }

    // ------------------------------------------------------------ reports

    /// The native control's action: a click, a step, a value set by the user.
    public virtual void ReportAction() { }

    public void ReportPaint(NSRect dirty)
    {
        var owner = Owner;
        var context = NSGraphicsContext.CurrentContext;
        if (owner == null || context == null)
            return;
        var surface = new Graphics(new AppKitGraphicsBackend(((NSGraphicsContext)context).CGContext, View));
        ((IControlNotify)owner).OnPlatformPaint(surface);
    }

    public void ReportPress(NSEvent event, FPoint at)
    {
        var owner = Owner;
        if (owner == null)
            return;
        var button = GetMouseButton(event);
        var notify = (IControlNotify)owner;
        notify.OnPlatformMouseDown(button, at, GetModifiers(event.ModifierFlags));
        if (button == MouseButton.Left && event.ClickCount == 2)
            notify.OnPlatformDoubleClick();
        if (button == MouseButton.Right)
            notify.OnPlatformContextMenu(at, false);
    }

    public void ReportRelease(NSEvent event, FPoint at)
    {
        var owner = Owner;
        if (owner != null)
            ((IControlNotify)owner).OnPlatformMouseUp(GetMouseButton(event), at, GetModifiers(event.ModifierFlags));
    }

    public void ReportMove(NSEvent event, FPoint at)
    {
        var owner = Owner;
        if (owner != null)
            ((IControlNotify)owner).OnPlatformMouseMove(at, GetModifiers(event.ModifierFlags));
    }

    public void ReportCrossing(bool entered)
    {
        var owner = Owner;
        if (owner == null)
            return;
        if (entered)
        {
            ApplyCursor();
            ((IControlNotify)owner).OnPlatformMouseEnter();
        }
        else
        {
            ((IControlNotify)owner).OnPlatformMouseLeave();
        }
    }

    /// A notch is 120, as everywhere: a wheel's line is AppKit's one unit, and
    /// a trackpad's fractions of one are kept rather than rounded away.
    public void ReportWheel(NSEvent event, FPoint at)
    {
        var owner = Owner;
        if (owner == null)
            return;
        double lines = event.HasPreciseScrollingDeltas ? event.ScrollingDeltaY / 10.0 : event.ScrollingDeltaY;
        ((IControlNotify)owner).OnPlatformMouseWheel(RoundToInt(lines * 120.0), at,
                                                     GetModifiers(event.ModifierFlags));
    }

    public void ReportKey(NSEvent event, bool down)
    {
        var owner = Owner;
        if (owner == null)
            return;
        var notify = (IControlNotify)owner;
        var modifiers = GetModifiers(event.ModifierFlags);
        var key = GetKey(event.KeyCode);
        if (!down)
        {
            notify.OnPlatformKeyUp(key, modifiers);
            return;
        }
        notify.OnPlatformKeyDown(key, modifiers);

        // Tab moves the focus in the order the form's controls were made.
        if (key == Key.Tab)
        {
            var form = FindWindowNotify();
            if (form != null)
            {
                ((IWindowNotify)form).OnPlatformNavigate(key, modifiers.HasFlag(ModifierKeys.Shift));
                return;
            }
        }

        // The typed text, with the layout and any dead keys applied. A shortcut
        // types nothing, and AppKit's private-use characters are function keys.
        if (modifiers.HasFlag(ModifierKeys.Control))
            return;
        String typed = FromNSString(event.Characters);
        for (nuint at = 0u; at < typed.ByteLength(); at = typed.SkipCodePoint(at))
        {
            char32 scalar = typed.GetCodePointAt(at);
            if (scalar >= (char32)32 && scalar != (char32)127 && (scalar < (char32)0xF700 || scalar > (char32)0xF8FF))
                notify.OnPlatformKeyPress(scalar);
        }
    }

    public void ReportFocus(bool gained)
    {
        var owner = Owner;
        if (owner == null)
            return;
        if (gained)
            ((IControlNotify)owner).OnPlatformGotFocus();
        else
            ((IControlNotify)owner).OnPlatformLostFocus();
    }

    /// Moves the focus from this control in the form's order, as Tab does,
    /// and answers whether there was a form to do it.
    public bool NavigateFromHere(bool backward)
    {
        var form = FindWindowNotify();
        if (form == null)
            return false;
        return ((IWindowNotify)form).OnPlatformNavigate(Key.Tab, backward);
    }

    /// The form this control is on, which hears Tab: the peer of the window's
    /// content view.
    IWindowNotify? FindWindowNotify()
    {
        var window = View.Window;
        if (window == null)
            return null;
        var content = ((NSWindow)window).ContentView;
        if (content is FormsView root && root.FindPeer() is AppKitWindowPeer framed)
            return framed.WindowOwner;
        return null;
    }

    // ------------------------------------------------------------ IControlPeer

    public virtual void SetBounds(FRect bounds)
    {
        LastBounds = bounds;
        View.Frame = ToNSRect(bounds);
    }

    public virtual void SetVisible(bool visible) => View.Hidden = !visible;

    public virtual void SetEnabled(bool enabled) { }

    public virtual void SetText(String text) { }
    public virtual String GetText() => "";
    public virtual void SetFont(Font font) { }
    public virtual void SetForeColor(Color color) { }

    public virtual void SetBackColor(Color color)
    {
        if (View is FormsView drawn)
        {
            drawn.FillsBackground = true;
            drawn.Background = color;
            drawn.NeedsDisplay = true;
        }
    }

    public void Invalidate() => View.NeedsDisplay = true;

    public void Update() => View.DisplayIfNeeded();

    /// The view that takes the keyboard, which for a control in a scroll view
    /// or a box is not the one the parent places.
    protected virtual NSView FocusView => View;

    public void Focus()
    {
        var window = View.Window;
        if (window != null)
            ((NSWindow)window).MakeFirstResponder(FocusView);
    }

    /// A field being edited is not the first responder; the window's field
    /// editor is, on the field's behalf.
    public bool HasFocus
    {
        get
        {
            var window = View.Window;
            if (window == null)
                return false;
            var focused = FocusView;
            var first = ((NSWindow)window).FirstResponder;
            if (first != null && (NSResponder)first == (NSResponder)focused)
                return true;
            return focused is NSControl control && control.CurrentEditor() != null;
        }
    }

    public void SetCursor(CursorKind cursor)
    {
        _cursor = cursor;
        if (View.Window != null)
            ApplyCursor();
    }

    /// Sets the pointer's shape now; AppKit keeps no shape per view without a
    /// cursor rectangle, so it is set again each time the pointer comes in.
    void ApplyCursor() => FindCursor(_cursor).Set();

    static NSCursor FindCursor(CursorKind cursor)
    {
        switch (cursor)
        {
            case CursorKind.Hand: return (NSCursor)NSCursor.PointingHandCursor;
            case CursorKind.Text: return (NSCursor)NSCursor.IBeamCursor;
            case CursorKind.Cross: return (NSCursor)NSCursor.CrosshairCursor;
            case CursorKind.SizeWestEast: return (NSCursor)NSCursor.ResizeLeftRightCursor;
            case CursorKind.SizeNorthSouth: return (NSCursor)NSCursor.ResizeUpDownCursor;
            case CursorKind.SizeAll: return (NSCursor)NSCursor.OpenHandCursor;
            case CursorKind.No: return (NSCursor)NSCursor.OperationNotAllowedCursor;
            default: return (NSCursor)NSCursor.ArrowCursor;
        }
    }

    public void SetToolTip(String text) => View.ToolTip = text == "" ? null : ToNSString(text);

    /// AppKit gives a dragged pointer to the view it was pressed in until it is
    /// released, which is the capture every drag needs; nothing more is asked.
    public void SetCapture(bool captured) => _captured = captured;

    public virtual bool AcceptsTabFocus => !View.Hidden && View.AcceptsFirstResponder;

    public virtual void SetDesigning(bool designing) => IsDesigning = designing;

    public void BringToFront()
    {
        var parent = View.Superview;
        if (parent == null)
            return;
        var keep = View;
        View.RemoveFromSuperview();
        ((NSView)parent).AddSubview(keep);
    }

    public FPoint GetPointerPosition()
    {
        var window = View.Window;
        if (window == null)
            return CreatePoint(-1, -1);
        var inWindow = ((NSWindow)window).MouseLocationOutsideOfEventStream;
        var at = View.ConvertPointFromView(inWindow, null);
        return CreatePoint(FloorToInt(at.x), FloorToInt(at.y));
    }

    public virtual FRect ClientBounds
    {
        get
        {
            var bounds = View.Bounds;
            return CreateRectangle(0, 0, RoundToInt(bounds.size.width), RoundToInt(bounds.size.height));
        }
    }

    public virtual FPoint ClientOrigin => CreatePoint(0, 0);

    public virtual FSize PreferredSize => CreateSize(LastBounds.Width, LastBounds.Height);

    public nuint Handle => IsDestroyed ? 0u : (nuint)(byte*)View;

    public virtual void DestroyHandle()
    {
        if (IsDestroyed)
            return;
        IsDestroyed = true;
        ForgetReporters();
        View.RemoveFromSuperview();
    }

    /// Empties every weak slot that names this peer: the view's, and the
    /// relays' and delegates' a subclass made.
    ///
    /// **Not left to the views to outlive.** A weak reference keeps its
    /// target's memory, though not its life, until the slot is emptied, and
    /// AppKit frees a closed window's views when its autorelease pool drains
    /// -- which for the last window of a program is after the program has
    /// ended. A peer that left its slots full would be counted as alive.
    protected virtual void ForgetReporters() => ForgetPeer(View);
}

/// Empties the `Peer` of any of this backend's views.
public void ForgetPeer(NSView view)
{
    if (view is FormsView drawn)
        drawn.Peer = null;
    else if (view is FormsButton button)
        button.Peer = null;
    else if (view is FormsSecureTextField hidden)
        hidden.Peer = null;
    else if (view is FormsTextField field)
        field.Peer = null;
    else if (view is FormsTextView text)
        text.Peer = null;
    else if (view is FormsSlider slider)
        slider.Peer = null;
}

/// A peer other controls can be put inside.
public class AppKitContainerPeer : AppKitPeer, IContainerPeer
{
    public AppKitContainerPeer(NSView made, IControlNotify? owner) => base(made, owner);

    /// Where children go: the view itself, or for a window its content.
    protected virtual NSView Content => View;

    public void AddChild(IControlPeer child)
    {
        var added = (AppKitPeer)child;
        added.View.RemoveFromSuperview();
        Content.AddSubview(added.View);
    }

    public void RemoveChild(IControlPeer child) => ((AppKitPeer)child).View.RemoveFromSuperview();
}

/// A panel: a plain container with an optional border.
public class AppKitPanelPeer : AppKitContainerPeer, IPanelPeer
{
    ControlBorder _border;

    public AppKitPanelPeer(IControlNotify owner) => base(CreateFormsView(), owner);

    public void SetBorder(ControlBorder border)
    {
        _border = border;
        ApplyBorder(View, border);
    }
}

/// A one-pixel line around a view, drawn by its layer so the content does not
/// have to leave room for it.
void ApplyBorder(NSView view, ControlBorder border)
{
    view.WantsLayer = border != ControlBorder.None;
    var layer = view.Layer;
    var line = NSColor.SeparatorColor;
    if (layer == null || line == null)
        return;
    ((CALayer)layer).BorderWidth = border == ControlBorder.None ? 0.0 : 1.0;
    ((CALayer)layer).BorderColor = ((NSColor)line).CGColor;
}

/// A control the program draws, and that takes the keyboard.
public class AppKitCustomPeer : AppKitContainerPeer, ICustomPeer
{
    public AppKitCustomPeer(IControlNotify owner)
    {
        base(CreateFormsView(), owner);
        ((FormsView)View).Focusable = true;
    }

    public void SetBorder(ControlBorder border) => ApplyBorder(View, border);

    public void SetFocusable(bool focusable) => ((FormsView)View).Focusable = focusable;

    public void SetTransparent(bool transparent)
    {
        ((FormsView)View).Transparent = transparent;
        View.NeedsDisplay = true;
    }

    /// AppKit composites a view over its siblings every time either is drawn,
    /// so drawing this one again is asking for it to be drawn.
    public void RedrawOver() => View.NeedsDisplay = true;

    /// The insertion point is drawn by the control in this backend; AppKit's
    /// own caret belongs to its text views.
    public void SetCaret(FRect place) { }

    public override bool AcceptsTabFocus => !View.Hidden && ((FormsView)View).Focusable;
}

/// A new flipped view, at the origin and empty.
///
/// **Nothing it draws reaches outside its bounds**, as no control's does on
/// Windows or GTK. Since macOS 14 a view is not clipped unless it asks, and
/// a control drawing past its edge paints over its siblings.
public FormsView CreateFormsView()
{
    var made = FormsView.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 0.0, 0.0));
    made.ClipsToBounds = true;
    return made;
}

#endif
