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

    /// Which renderer drew this item, taken from the menu as it was built.
    ///
    /// Held rather than looked up, because an item has no reference to the
    /// menu it is in -- and giving it one for this would be a back-pointer on
    /// every item of every menu for the sake of the few that are drawn by a
    /// program.
    MenuRenderer? _renderer;

    /// Whether this item sits on a menu bar rather than in something that
    /// drops down.
    ///
    /// **A renderer needs it and the platform does not say.** `WM_DRAWITEM`
    /// reports where the item is and what state it is in, and nothing about
    /// which kind of menu it belongs to -- but a bar item and a dropdown item
    /// look nothing alike: one is a word on the window's own background, the
    /// other is a row with a gutter down its left. Drawing a gutter across the
    /// top of a window is what this exists to stop, and it is what the first
    /// version did.
    ///
    /// Set as the menu is built, because that is the moment the answer is
    /// known: the top level of a `MainMenu` is a bar and everything else,
    /// including every level of a `PopupMenu`, is not.
    public bool OnMenuBar { get; private set; }

    /// Whether the platform agreed to hand this item over to the renderer.
    ///
    /// **Asked rather than assumed**, and worth reading: `SetOwnerDrawn`
    /// answers false on GTK for every item, and can answer false on Windows
    /// for one the menu will not describe -- so an item drawn by the platform
    /// inside a menu drawn by the program is a thing that can happen, and this
    /// is how a test sees it rather than a person noticing one row that looks
    /// wrong.
    public bool IsOwnerDrawn { get; private set; }

    public Size OnPlatformMeasureItem(Graphics surface)
    {
        var drawing = _renderer;
        if (drawing == null)
            return Size.Of(0, 0);
        return ((MenuRenderer)drawing).Measure(surface, this);
    }

    public void OnPlatformDrawItem(Graphics surface, Rectangle bounds,
                                   MenuItemState state)
    {
        var drawing = _renderer;
        if (drawing != null)
            ((MenuRenderer)drawing).Draw(surface, this, bounds, state);
    }

    /// Gives this item and everything under it a renderer, and tells the
    /// platform whether to hand them over.
    ///
    /// Called when a menu is built and again whenever its renderer changes, so
    /// that a program may change how its menus look while they exist.
    void Restyle(MenuRenderer renderer)
    {
        _renderer = renderer;

        var peer = _realised;
        if (peer != null)
            IsOwnerDrawn = ((IMenuItemPeer)peer).SetOwnerDrawn(renderer.OwnerDrawn)
                        && renderer.OwnerDrawn;

        foreach (var child in _children)
            child.Restyle(renderer);
    }

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
    void Realise(IMenuPeer into, MenuRenderer renderer, bool onBar)
    {
        _renderer = renderer;
        OnMenuBar = onBar;

        if (_divider)
        {
            // **A separator is owner-drawn too, or it is not drawn at all.** A
            // platform separator in a menu whose items are the program's is a
            // grey line at the platform's height in the platform's colours,
            // across a background nothing else uses -- so a renderer that
            // draws the items has to draw these as well. `AddSeparator` is
            // therefore only used where the platform is drawing.
            if (!renderer.OwnerDrawn)
            {
                into.AddSeparator();
                return;
            }

            var line = into.AddItem(this, "", null);
            _realised = line;
            IsOwnerDrawn = line.SetOwnerDrawn(true);
            return;
        }

        IMenuPeer? submenu = null;
        if (!_children.IsEmpty)
        {
            var made = WidgetSet.Current.CreateMenu();
            foreach (var child in _children)
                child.Realise(made, renderer, false);
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
        if (renderer.OwnerDrawn)
            IsOwnerDrawn = peer.SetOwnerDrawn(true);
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
    /// Whether this menu's own items sit on a bar. False for everything but
    /// `MainMenu`, and it is what tells a renderer which shape to draw.
    protected virtual bool IsBar => false;

    protected IMenuPeer? peer;
    List<MenuItem> _items;

    /// How this menu is drawn. The platform's own until a program says
    /// otherwise.
    MenuRenderer _renderer;

    protected Menu()
    {
        peer = null;
        _items = new List<MenuItem>();
        _renderer = new SystemMenuRenderer();
    }

    /// What draws this menu.
    ///
    /// Setting it restyles a menu that already exists, so a program may change
    /// how its menus look at any point rather than only before the window is
    /// built -- which matters for a theme a person chooses from a menu of its
    /// own.
    ///
    /// A renderer that the platform will not honour changes nothing:
    /// `SetOwnerDrawn` answers false on GTK and the menu stays native.
    public MenuRenderer Renderer
    {
        get => _renderer;
        set
        {
            _renderer = value;
            foreach (var item in _items)
                item.Restyle(value);
        }
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
            item.Realise(into, _renderer, IsBar);
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

    protected override bool IsBar => true;

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
