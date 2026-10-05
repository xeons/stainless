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

// Menus on AppKit: an `NSMenu` for a bar, a drop-down and a popup alike.
//
// **A Mac's menu bar belongs to the application, not to a window.** A form's
// bar is shown across the top of the screen while that form is the key
// window -- `AppKitWindowPeer` puts it there as the window becomes key, as
// the LCL's Cocoa widgetset does. AppKit draws the first item of the main
// menu as the application's own menu whatever it is titled, so every bar
// begins with one: Hide, Hide Others, Show All and Quit, which closes each
// window as its close button would, so a form may still refuse.
//
// **Captions lose their mnemonics.** A Mac menu has no underlined keys, so
// `&File` is shown as `File` and `&&` as `&`.
module Forms.Platform.AppKit;

import Standard.Collections;
import Standard.Text;
import Forms.Drawing;
import Forms.Platform;
#if MACOS && FORMS_APPKIT
import Standard.ObjC;
import MacOS.System;
import MacOS.CoreFoundation;
import MacOS.CoreGraphics;
import MacOS.Foundation;
import MacOS.AppKit;

/// `&File` as a Mac shows it, which is `File`; `&&` is one ampersand.
String RemoveMnemonics(String caption)
{
    var built = new StringBuilder();
    nuint at = 0u;
    nuint size = caption.ByteLength();
    while (at < size)
    {
        byte c = caption.GetByteAt(at);
        if (c == (byte)'&')
        {
            if (at + 1u < size && caption.GetByteAt(at + 1u) == (byte)'&')
            {
                built.Append("&");
                at += 2u;
                continue;
            }
            at++;
            continue;
        }
        nuint next = caption.SkipCodePoint(at);
        built.Append(caption.Substring(at, next - at));
        at = next;
    }
    return built.ToText();
}

/// The target of every command item: it hands the choice to the item's peer.
public objc class FormsMenuTarget : NSObject
{
    public weak AppKitMenuItemPeer? Peer;

    [Selector("choose:")]
    public void Choose(AnyObject? sender)
    {
        AppKitMenuItemPeer? peer = Peer;
        if (peer != null)
            ((AppKitMenuItemPeer)peer).ReportChosen();
    }
}

/// The application menu's Quit: each window is asked to close, as its own
/// close button would ask it.
public objc class FormsQuitTarget : NSObject
{
    [Selector("quit:")]
    public void Quit(AnyObject? sender)
    {
        var windows = NSApplication.SharedApplication.Windows;
        for (nuint i = windows.Count; i > 0u; i--)
        {
            var window = (NSWindow)windows.ObjectAtIndex(i - 1u);
            if (window.Visible)
                window.PerformClose(null);
        }
    }
}

public class AppKitMenuItemPeer : IMenuItemPeer
{
    NSMenuItem _item;
    FormsMenuTarget? _target;
    weak IMenuItemNotify? _owner;

    public AppKitMenuItemPeer(NSMenuItem item, IMenuItemNotify owner, bool command)
    {
        _item = item;
        _owner = owner;
        _target = null;
        if (command)
        {
            var target = FormsMenuTarget.Alloc().Init()!;
            target.Peer = this;
            _item.Target = target;
            _item.Action = Selector.Named("choose:");
            _target = target;
        }
    }

    ~AppKitMenuItemPeer()
    {
        if (_target is FormsMenuTarget target)
            target.Peer = null;
    }

    public void ReportChosen()
    {
        IMenuItemNotify? owner = _owner;
        if (owner != null)
            ((IMenuItemNotify)owner).OnPlatformMenuClicked();
    }

    public nuint Id => (nuint)(byte*)_item;

    public void SetText(String text)
    {
        _item.Title = ToNSString(RemoveMnemonics(text));
        var submenu = _item.Submenu;
        if (submenu != null)
            ((NSMenu)submenu).Title = _item.Title;
    }

    public void SetEnabled(bool enabled) => _item.Enabled = enabled;

    /// AppKit ticks nothing by itself when an item is chosen, as Windows does
    /// not, so the tick is only ever the program's.
    public void SetChecked(bool checked) => _item.State = checked ? 1 : 0;

    /// A Mac menu has no default item.
    public void SetDefault(bool isDefault) { }

    /// A Mac menu is drawn by AppKit, as on GTK.
    public bool SetOwnerDrawn(bool drawn) => false;
}

public class AppKitMenuPeer : IMenuPeer
{
    NSMenu _menu;
    bool _isBar;
    FormsQuitTarget? _quit;

    public AppKitMenuPeer(bool isBar)
    {
        _menu = NSMenu.Alloc().InitWithTitle(ToNSString(""));
        _menu.AutoenablesItems = false;
        _isBar = isBar;
        _quit = null;
        if (isBar)
            AddApplicationMenu();
    }

    public NSMenu Menu => _menu;

    public nuint Handle => (nuint)(byte*)_menu;

    /// The menu AppKit shows under the application's name.
    void AddApplicationMenu()
    {
        String name = FromNSString(NSProcessInfo.ProcessInfo.ProcessName);
        var quit = FormsQuitTarget.Alloc().Init()!;
        _quit = quit;

        var menu = NSMenu.Alloc().InitWithTitle(ToNSString(name));
        menu.AddItem(CreateCommand("Hide " + name, "hide:", "h", NSEventModifierFlags.Command));
        menu.AddItem(CreateCommand("Hide Others", "hideOtherApplications:", "h",
                                   NSEventModifierFlags.Command | NSEventModifierFlags.Option));
        menu.AddItem(CreateCommand("Show All", "unhideAllApplications:", "", (NSEventModifierFlags)0u));
        menu.AddItem(NSMenuItem.ClassSeparatorItem());
        var leave = CreateCommand("Quit " + name, "quit:", "q", NSEventModifierFlags.Command);
        leave.Target = quit;
        menu.AddItem(leave);

        var item = NSMenuItem.Alloc().InitWithTitleActionKeyEquivalent(ToNSString(name), Selector.Named("submenuAction:"),
                                                                       ToNSString(""));
        item.Submenu = menu;
        _menu.AddItem(item);
    }

    static NSMenuItem CreateCommand(String title, String action, String key, NSEventModifierFlags modifiers)
    {
        var item = NSMenuItem.Alloc().InitWithTitleActionKeyEquivalent(ToNSString(title), Selector.Named(action),
                                                                       ToNSString(key));
        item.KeyEquivalentModifierMask = modifiers;
        return item;
    }

    /// The first of the items this menu's program added: after the application
    /// menu on a bar.
    int FirstOwnItem => _isBar ? 1 : 0;

    public IMenuItemPeer AddItem(IMenuItemNotify owner, String text, IMenuPeer? submenu)
    {
        var title = ToNSString(RemoveMnemonics(text));
        var item = NSMenuItem.Alloc().InitWithTitleActionKeyEquivalent(title, Selector.Named("choose:"),
                                                                       ToNSString(""));
        if (submenu != null)
        {
            var opened = ((AppKitMenuPeer)submenu).Menu;
            opened.Title = title;
            item.Submenu = opened;
        }
        _menu.AddItem(item);
        return new AppKitMenuItemPeer(item, owner, submenu == null);
    }

    public void AddSeparator() => _menu.AddItem(NSMenuItem.ClassSeparatorItem());

    public void Clear()
    {
        while ((int)_menu.NumberOfItems > FirstOwnItem)
            _menu.RemoveItemAtIndex(_menu.NumberOfItems - (NSInteger)1);
    }

    /// Pops the menu up at a point on the screen, measured down from its top,
    /// and returns once it is over; AppKit tracks it in a loop of its own.
    public void ShowPopup(IWindowPeer owner, Forms.Drawing.Point atScreen)
    {
        NSPoint at;
        at.x = (double)atScreen.X;
        at.y = FindScreenTop() - (double)atScreen.Y;
        _menu.PopUpMenuPositioningItemAtLocationInView(null, at, null);
    }
}

#endif
