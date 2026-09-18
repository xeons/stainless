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

// Menus: `MainMenu` across the top of a window, `PopupMenu` under the pointer,
// and `MenuItem` in both.
//
// **A menu is described first and built second.** Every item is an ordinary
// object with a caption, children and a `Click` -- no platform menu exists
// until the whole tree is handed over, which happens when a `MainMenu` is given
// to a form or a `PopupMenu` is shown.
//
// That is not how the LCL does it, and the reason is a real one. On Windows a
// submenu has to exist before the item that opens it can be created, because
// the item *is* the submenu's handle; building as you go therefore means either
// adding items bottom-up or patching the parent afterwards, and `TMenuItem`
// does the second, with `HandleNeeded` and a rebuild whenever anything is
// inserted. Describing first removes the ordering problem rather than managing
// it: a tree with no handles can be assembled in any order at all.
//
//     var file = new MenuItem("&File");
//     file.Add("&Open").Click += this.OnOpen;
//     file.Add(MenuItem.Separator());
//     file.Add("E&xit").Click += this.OnExit;
//
//     var bar = new MainMenu();
//     bar.Add(file);
//     Menu = bar;
module Forms;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;

/// What a menu item's handler is given. Not `EventHandler`, because a menu item
/// is not a `Control` -- it has no position, no parent window and nothing to
/// paint.
public closure void MenuEventHandler(MenuItem sender);

// =================================================================== an item

/// One line in a menu: a command, a separator, or a heading with more under it.
public class MenuItem : IMenuItemNotify
{
    IMenuItemPeer? _realised;
    IMenuPeer? _below;
    List<MenuItem> _children;
    String _caption;
    bool _enabled;
    bool _ticked;
    bool _divider;

    public MenuItem(String text)
    {
        _caption = text;
        _enabled = true;
        _ticked = false;
        _divider = false;
        _realised = null;
        _below = null;
        _children = new List<MenuItem>();
    }

    /// The line between groups of commands.
    ///
    /// A `MenuItem` with a flag rather than a type of its own, because it goes
    /// in the same list as everything else and a separate type would mean the
    /// list holding a base nobody else derives from.
    public static MenuItem Separator()
    {
        var made = new MenuItem("");
        made._divider = true;
        return made;
    }

    public bool IsSeparator => _divider;

    /// What the item says. `&` before a letter underlines it and makes it the
    /// key that chooses the item while the menu is open, as everywhere else on
    /// Windows.
    public String Text
    {
        get => _caption;
        set
        {
            _caption = value;
            var peer = _realised;
            if (peer != null)
                ((IMenuItemPeer)peer).SetText(value);
        }
    }

    public bool Enabled
    {
        get => _enabled;
        set
        {
            _enabled = value;
            var peer = _realised;
            if (peer != null)
                ((IMenuItemPeer)peer).SetEnabled(value);
        }
    }

    /// Whether a tick is drawn beside it.
    public bool Checked
    {
        get => _ticked;
        set
        {
            _ticked = value;
            var peer = _realised;
            if (peer != null)
                ((IMenuItemPeer)peer).SetChecked(value);
        }
    }

    /// The items under this one. Adding any makes it a heading rather than a
    /// command, and a heading raises nothing when chosen.
    public List<MenuItem> Items => _children;

    public bool HasItems => !_children.IsEmpty;

    /// Adds an item underneath and answers **the item**, so that a handler can
    /// be attached to the result of the call.
    public MenuItem Add(MenuItem child)
    {
        _children.Add(child);
        return child;
    }

    /// The same, building the item from its caption.
    public MenuItem Add(String text) => Add(new MenuItem(text));

    /// The item was chosen.
    public event MenuEventHandler Click;

    protected virtual void OnClick() => Click(this);

    /// What the platform calls when the user picks this item.
    public void OnPlatformMenuClicked() => OnClick();

    /// What the platform calls this item, or zero before the menu is built.
    ///
    /// Here for the same reason `Control.Handle` is: a program that must reach
    /// the platform directly has to be able to name what it is reaching for.
    public nuint PlatformId
    {
        get
        {
            var peer = _realised;
            if (peer == null)
                return 0u;
            return ((IMenuItemPeer)peer).Id;
        }
    }

    /// Builds this item, and everything under it, into a platform menu.
    ///
    /// Depth first, because a submenu must exist before the item that opens it
    /// can be made -- which is the ordering this whole arrangement exists to
    /// make invisible.
    void Realise(IMenuPeer into)
    {
        if (_divider)
        {
            into.AddSeparator();
            return;
        }

        IMenuPeer? submenu = null;
        if (!_children.IsEmpty)
        {
            var made = WidgetSet.Current.CreateMenu();
            foreach (var child in _children)
                child.Realise(made);
            submenu = made;
            _below = made;
        }

        var peer = into.AddItem(this, _caption, submenu);
        _realised = peer;

        // The state was set while there was nothing to tell, so it is told now.
        if (!_enabled)
            peer.SetEnabled(false);
        if (_ticked)
            peer.SetChecked(true);
    }

    /// Forgets the platform side, so the tree can be built again into a new
    /// menu -- which is what happens when a form is given a second menu bar.
    void Forget()
    {
        _realised = null;
        _below = null;
        foreach (var child in _children)
            child.Forget();
    }
}

// =================================================================== a menu

/// What a menu bar and a popup have in common: a list of items, and the moment
/// they become a real menu.
public abstract class Menu
{
    protected IMenuPeer? peer;
    List<MenuItem> _items;

    protected Menu()
    {
        peer = null;
        _items = new List<MenuItem>();
    }

    public List<MenuItem> Items => _items;

    /// Adds a top-level item and answers it.
    public MenuItem Add(MenuItem item)
    {
        _items.Add(item);
        return item;
    }

    public MenuItem Add(String text) => Add(new MenuItem(text));

    /// Builds the whole tree into `into`, which becomes this menu's platform
    /// side.
    protected void RealiseInto(IMenuPeer into)
    {
        foreach (var item in _items)
        {
            item.Forget();
            item.Realise(into);
        }
        peer = into;
    }
}

/// The bar across the top of a window.
///
/// ```
/// var bar = new MainMenu();
/// var file = bar.Add("&File");
/// file.Add("&Open").Click += this.OnOpen;
/// file.Add(MenuItem.Separator());
/// file.Add("E&xit").Click += this.OnExit;
/// Menu = bar;
/// ```
public class MainMenu : Menu
{
    public MainMenu() => base();

    /// Builds the bar and gives it to a form. Called by `Form.Menu`, which is
    /// how a program attaches one.
    IMenuPeer Build()
    {
        var bar = WidgetSet.Current.CreateMenuBar();
        RealiseInto(bar);
        return bar;
    }
}

/// A menu shown under the pointer.
///
/// Built afresh on every showing, which costs one menu's worth of handles and
/// buys the thing a context menu almost always wants: items enabled according
/// to what is selected *now*, decided in the handler that opens it rather than
/// kept in step from everywhere that changes the selection.
public class PopupMenu : Menu
{
    public PopupMenu() => base();

    /// Shows it at a point in the control's own coordinates, and does not
    /// return until the user has chosen or dismissed it.
    public void Show(Control owner, Point at)
    {
        var form = owner.FindForm();
        if (form == null)
            return;

        var built = WidgetSet.Current.CreateMenu();
        RealiseInto(built);
        built.ShowPopup(((Form)form).WindowPeer(), ((Form)form).ToScreen(owner, at));
    }
}
