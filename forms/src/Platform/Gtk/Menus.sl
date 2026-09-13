// Stainless - an experimental systems language.
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

// Menus: a bar, a drop-down and a popup, which are three widgets here and one
// interface in the seam.
//
// **This is where GTK is simpler than Win32 and the seam already knew.** An
// `HMENU` is a handle with items addressed by command id, and a chosen item
// arrives as a `WM_COMMAND` carrying that id -- which is why `IMenuItemPeer`
// has an `Id` at all. A GTK menu item is a widget with an `activate` signal,
// so the id is the widget's address and nothing has to look anything up. The
// interface fits both because it asks what the platform calls an item rather
// than assuming the answer is a number the platform assigned.
//
// **A checked item is a different widget.** `GtkCheckMenuItem` and
// `GtkMenuItem` are not exchangeable, and a menu item does not know at
// construction whether it will ever be ticked -- so every command item is a
// check item that is not drawing its tick, which is what `TMenuItem` is too.
module Forms.Platform.Gtk;

import Standard.Collections;
import Standard.Text;
import Forms.Drawing;
import Forms.Platform;
#if UNIX
import Gtk.GLib;
import Gtk.GObject;
import Gtk.Gdk;
import Gtk.Api;
import Gtk.Signals;
import Gtk.Events;

// ============================================================== one item

public class GtkMenuItemPeer : IMenuItemPeer {
    GtkWidget* item;
    /// True while the program is setting the tick, so that the `activate` GTK
    /// raises for it is not reported as the user choosing the item.
    bool echoing;

    /// **Through a call, because a lambda captures a member read by value.**
    /// `if (echoing)` in the handler below would test what the flag said when
    /// the handler was connected. This is the peer that proved it: a program
    /// that ticked a menu item from its own click handler recursed until the
    /// stack ran out, because `gtk_check_menu_item_set_active` emits
    /// `activate` and the guard was not guarding. Win32 never had the problem
    /// -- `CheckMenuItem` raises nothing at all.
    bool Echoing() { return echoing; }

    public GtkMenuItemPeer(GtkWidget* made, IMenuItemNotify owner) {
        item = made;
        echoing = false;

        ConnectPlain(item, "activate", () => {
            if (Echoing()) { return; }
            owner.OnPlatformMenuClicked();
        });
    }

    /// The widget's address. Win32 needs a number because its items share a
    /// window and a `WM_COMMAND` carries nothing else; here the item *is* the
    /// thing that was activated.
    public nuint Id() { return (nuint)(void*)item; }

    public void SetText(String text) { gtk_menu_item_set_label(item, text.ToPointer()); }

    public void SetEnabled(bool enabled) {
        gtk_widget_set_sensitive(item, enabled ? 1 : 0);
    }

    public void SetChecked(bool checked) {
        echoing = true;
        gtk_check_menu_item_set_active(item, checked ? 1 : 0);
        echoing = false;
    }

    /// **GTK does not draw a default menu item.** Windows bolds one and
    /// double-clicking the parent chooses it; there is no such idea in GTK and
    /// no theme that expresses one, so this does nothing rather than
    /// approximating it with markup that would not match the theme.
    public void SetDefault(bool isDefault) { }

    public GtkWidget* Widget() { return item; }
}

// ================================================================ a menu

public class GtkMenuPeer : IMenuPeer {
    GtkWidget* menu;
    /// Owned: one reference, sunk at construction. A menu bar goes into a
    /// window and a popup goes nowhere, so neither can be left to a parent.
    List<GtkWidget*> items;

    public GtkMenuPeer(bool isBar) {
        menu = (GtkWidget*)g_object_ref_sink(
            (gpointer)(isBar ? gtk_menu_bar_new() : gtk_menu_new()));
        items = new List<GtkWidget*>();
    }

    ~GtkMenuPeer() {
        if (menu == null) { return; }
        gtk_widget_destroy(menu);
        g_object_unref((gpointer)menu);
        menu = null;
    }

    public nuint Handle() { return (nuint)(void*)menu; }

    /// Adds a command, or a heading when `submenu` is given.
    ///
    /// A check item every time, drawing no tick until something sets one: GTK
    /// will not turn a plain item into a checkable one, and a menu item does
    /// not know at construction whether it will ever be ticked.
    public IMenuItemPeer AddItem(IMenuItemNotify owner, String text, IMenuPeer? submenu) {
        GtkWidget* made = gtk_check_menu_item_new_with_label(text.ToPointer());
        if (submenu != null) {
            gtk_menu_item_set_submenu(made, ((GtkMenuPeer)submenu).Widget());
        }

        gtk_menu_shell_append(menu, made);
        gtk_widget_show(made);
        items.Add(made);
        return new GtkMenuItemPeer(made, owner);
    }

    public void AddSeparator() {
        GtkWidget* line = gtk_separator_menu_item_new();
        gtk_menu_shell_append(menu, line);
        gtk_widget_show(line);
        items.Add(line);
    }

    public void Clear() {
        for (nuint i = 0u; i < items.Count(); i++) {
            gtk_container_remove(menu, items[i]);
        }
        items.Clear();
    }

    /// Shows the menu under the pointer and does not return until it is over.
    ///
    /// **The position is ignored, and that is the right answer.**
    /// `gtk_menu_popup_at_pointer` puts a menu where the pointer is, which is
    /// where the seam's caller computed its point from in the first place; the
    /// six-argument `gtk_menu_popup` that takes a position is deprecated and
    /// gets the placement wrong under Wayland, which has no global coordinates
    /// to place anything at.
    ///
    /// Not returning until the menu is over is a nested `gtk_main`, ended by
    /// the menu's own `deactivate` -- the same arrangement a modal window
    /// uses, and for the same reason: GTK pops a menu up and returns.
    public void ShowPopup(IWindowPeer owner, Point atScreen) {
        var id = ConnectPlain(menu, "deactivate", () => { gtk_main_quit(); });

        gtk_menu_popup_at_pointer(menu, null);
        gtk_main();

        // Disconnected rather than left in place: the menu may be shown again,
        // and a second `deactivate` reaching a loop that has already returned
        // would quit the application's.
        Disconnect(menu, id);
    }

    public GtkWidget* Widget() { return menu; }
}

#endif
