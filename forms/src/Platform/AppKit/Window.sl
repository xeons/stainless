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

// A form's window.
//
// **A window's bounds are where it is and how much room is inside it**, as on
// GTK: the position is the frame's top-left corner on the screen, measured
// down from the top of the main screen, and the size is the content's. AppKit
// measures the screen up from the bottom, and turning one into the other is
// this file's business and nobody else's.
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
import MacOS.Foundation;
import MacOS.AppKit;

/// The height of the screen the menu bar is on, which every window's position
/// is measured down from.
double FindScreenTop()
{
    var screens = NSScreen.Screens;
    if (screens.Count == 0u)
        return 0.0;
    var first = (NSScreen)screens.ObjectAtIndex(0u);
    return first.Frame.size.height;
}

/// What AppKit tells a form's window, passed on to the form.
public objc class FormsWindowDelegate : NSObject, NSWindowDelegate
{
    public weak IWindowNotify? Owner;
    public weak AppKitWindowPeer? Peer;

    AppKitWindowPeer? FindPeer()
    {
        AppKitWindowPeer? held = Peer;
        return held;
    }

    public bool WindowShouldClose(NSWindow sender)
    {
        IWindowNotify? owner = Owner;
        return owner == null || ((IWindowNotify)owner).OnPlatformClosing();
    }

    public void WindowWillClose(NSNotification notification)
    {
        IWindowNotify? owner = Owner;
        if (owner != null)
            ((IWindowNotify)owner).OnPlatformClosed();
        if (FindPeer() is AppKitWindowPeer peer)
            peer.EndModal();
    }

    public void WindowDidResize(NSNotification notification)
    {
        if (FindPeer() is AppKitWindowPeer peer)
            peer.ReportGeometry();
    }

    public void WindowDidMove(NSNotification notification)
    {
        if (FindPeer() is AppKitWindowPeer peer)
            peer.ReportGeometry();
    }

    public void WindowDidBecomeKey(NSNotification notification)
    {
        IWindowNotify? owner = Owner;
        if (owner != null)
            ((IWindowNotify)owner).OnPlatformActivatedWindow();
    }

    public void WindowDidResignKey(NSNotification notification)
    {
        IWindowNotify? owner = Owner;
        if (owner != null)
            ((IWindowNotify)owner).OnPlatformDeactivated();
    }
}

/// A top-level window, whose content view is the form's own.
public class AppKitWindowPeer : AppKitContainerPeer, IWindowPeer
{
    NSWindow _window;
    FormsWindowDelegate _delegate;
    weak IWindowNotify? _owner;
    bool _isModal;
    bool _shown;

    public AppKitWindowPeer(IWindowNotify owner, WindowBorder border)
    {
        base(CreateFormsView(), (IControlNotify)owner);
        _owner = owner;
        _isModal = false;
        _shown = false;

        _window = NSWindow.Alloc().InitWithContentRectStyleMaskBackingDefer(
            MakeNSRect(0.0, 0.0, 320.0, 240.0), FindStyle(border), NSBackingStoreType.Buffered, false);
        _window.ReleasedWhenClosed = false;
        _window.ContentView = View;
        ((FormsView)View).Focusable = true;

        _delegate = FormsWindowDelegate.Alloc().Init()!;
        _delegate.Owner = owner;
        _delegate.Peer = this;
        _window.Delegate = _delegate;
    }

    static NSWindowStyleMask FindStyle(WindowBorder border)
    {
        switch (border)
        {
            case WindowBorder.None:
                return NSWindowStyleMask.Borderless;
            case WindowBorder.Fixed:
            case WindowBorder.Tool:
                return NSWindowStyleMask.Titled | NSWindowStyleMask.Closable | NSWindowStyleMask.Miniaturizable;
            default:
                return NSWindowStyleMask.Titled | NSWindowStyleMask.Closable | NSWindowStyleMask.Miniaturizable
                       | NSWindowStyleMask.Resizable;
        }
    }

    /// The window itself, for what reaches past the seam.
    public NSWindow Window => _window;

    /// The form, if it is still alive.
    public IWindowNotify? WindowOwner
    {
        get
        {
            IWindowNotify? held = _owner;
            return held;
        }
    }

    /// Where the window is and how big its content is, reported to the form.
    /// Written down first: a layout asks `ClientBounds`, which reads it.
    public void ReportGeometry()
    {
        var frame = _window.Frame;
        var content = _window.ContentRectForFrameRect(frame);
        int x = FloorToInt(frame.origin.x);
        int y = FloorToInt(FindScreenTop() - frame.origin.y - frame.size.height);
        int width = RoundToInt(content.size.width);
        int height = RoundToInt(content.size.height);

        bool moved = x != LastBounds.X || y != LastBounds.Y;
        bool sized = width != LastBounds.Width || height != LastBounds.Height;
        LastBounds = CreateRectangle(x, y, width, height);

        var owner = WindowOwner;
        if (owner == null)
            return;
        if (moved)
            ((IWindowNotify)owner).OnPlatformMoved(CreatePoint(x, y));
        if (sized)
            ((IWindowNotify)owner).OnPlatformResized(CreateSize(width, height));
    }

    public override void SetBounds(FRect wanted)
    {
        LastBounds = wanted;
        var content = MakeNSRect((double)wanted.X, 0.0, (double)wanted.Width, (double)wanted.Height);
        var frame = _window.FrameRectForContentRect(content);
        frame.origin.x = (double)wanted.X;
        frame.origin.y = FindScreenTop() - (double)wanted.Y - frame.size.height;
        _window.SetFrameDisplay(frame, true);
    }

    public override void SetVisible(bool visible)
    {
        if (!visible)
        {
            _window.OrderOut(null);
            return;
        }
        _window.MakeKeyAndOrderFront(null);
        if (!_shown)
        {
            _shown = true;
            NSApplication.SharedApplication.ActivateIgnoringOtherApps(true);
        }
    }

    public override void SetEnabled(bool enabled) { }

    public override void SetText(String text) => SetTitle(text);
    public override String GetText() => FromNSString(_window.Title);

    public void SetTitle(String title) => _window.Title = ToNSString(title);

    /// A Mac application's icon is its bundle's, and a title bar has none.
    public bool SetIconResource(int id) => false;

    public void SetMenu(IMenuPeer? menu) { }

    public void SetBorder(WindowBorder border) => _window.StyleMask = FindStyle(border);

    public void SetState(WindowState state)
    {
        switch (state)
        {
            case WindowState.Minimized:
                _window.Miniaturize(null);
                break;
            case WindowState.Maximized:
                if (!_window.Zoomed)
                    _window.Zoom(null);
                break;
            default:
                if (_window.Miniaturized)
                    _window.Deminiaturize(null);
                else if (_window.Zoomed)
                    _window.Zoom(null);
                break;
        }
    }

    public WindowState GetState()
    {
        if (_window.Miniaturized)
            return WindowState.Minimized;
        if (_window.Zoomed)
            return WindowState.Maximized;
        return WindowState.Normal;
    }

    public void Activate() => _window.MakeKeyAndOrderFront(null);

    /// As the close box does: the form is asked first.
    public void Close()
    {
        var shots = FindScreenshotDirectory();
        if (shots != null)
            WriteWindowScreenshot(_window, (String)shots);
        _window.PerformClose(null);
    }

    public void CenterOnScreen()
    {
        _window.Center();
        ReportGeometry();
    }

    /// AppKit's own modal loop, which the close ends. Every other window of the
    /// program is refused input meanwhile, and the owner is not needed for
    /// that.
    public void ShowModal(IWindowPeer? owner)
    {
        SetVisible(true);
        _isModal = true;
        NSApplication.SharedApplication.RunModalForWindow(_window);
        _isModal = false;
    }

    /// Ends the modal loop this window is running, if it is.
    public void EndModal()
    {
        if (!_isModal)
            return;
        _isModal = false;
        NSApplication.SharedApplication.StopModal();
    }

    public override bool AcceptsTabFocus => false;

    public override void DestroyHandle()
    {
        if (IsDestroyed)
            return;
        _delegate.Owner = null;
        _delegate.Peer = null;
        _window.Delegate = null;
        _window.OrderOut(null);
        base.DestroyHandle();
    }
}

#endif
