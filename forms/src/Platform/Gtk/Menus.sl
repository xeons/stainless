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

// ============================================================== mnemonics

/// `&File` as GTK writes it, which is `_File`.
///
/// **Both toolkits mark the key with a character in the caption**, and they
/// disagree about which: Windows uses `&` and GTK uses `_`, each escaping its
/// own by doubling it. So the seam carries Windows' spelling -- it is the one
/// `Forms` declares, and the one every caption in every sample is written in
/// -- and this translates.
///
/// A literal underscore has to be doubled on the way out or GTK would read it
/// as a marker, which is how `Save _As` would have lost its underscore and
/// gained an accelerator nobody asked for.
String ToMnemonic(String caption)
{
    var built = new StringBuilder();
    nuint at = 0u;
    nuint size = caption.ByteLength();

    while (at < size)
    {
        byte c = caption.ByteAt(at);
        if (c == (byte)'&')
        {
            // `&&` is one literal ampersand, and the marker is dropped.
            if (at + 1u < size && caption.ByteAt(at + 1u) == (byte)'&')
            {
                built.Append("&");
                at += 2u;
                continue;
            }
            built.Append("_");
            at++;
            continue;
        }
        if (c == (byte)'_')
        {
            built.Append("__");
            at++;
            continue;
        }
        built.Append(caption.Substring(at, 1u));
        at++;
    }
    return built.ToText();
}

// ============================================================== one item

public class GtkMenuItemPeer : IMenuItemPeer
{
    GtkWidget* _item;
    /// True while the program is setting the tick, so that the `activate` GTK
    /// raises for it is not reported as the user choosing the item.
    bool _echoing;

    /// **Through a call, because a lambda captures a member read by value.**
    /// `if (echoing)` in the handler below would test what the flag said when
    /// the handler was connected. This is the peer that proved it: a program
    /// that ticked a menu item from its own click handler recursed until the
    /// stack ran out, because `gtk_check_menu_item_set_active` emits
    /// `activate` and the guard was not guarding. Win32 never had the problem
    /// -- `CheckMenuItem` raises nothing at all.
    bool Echoing => _echoing;

    public GtkMenuItemPeer(GtkWidget* made, IMenuItemNotify owner)
    {
        _item = made;
        _echoing = false;

        ConnectPlain(_item, "activate", () =>
        {
            if (Echoing)
                return;
            owner.OnPlatformMenuClicked();
        });
    }

    /// The widget's address. Win32 needs a number because its items share a
    /// window and a `WM_COMMAND` carries nothing else; here the item *is* the
    /// thing that was activated.
    public nuint Id => (nuint)(void*)_item;

    public void SetText(String text)
    {
        gtk_menu_item_set_label(_item, ToMnemonic(text).ToPointer());
        gtk_menu_item_set_use_underline(_item, 1);
    }

    public void SetEnabled(bool enabled)
    {
        gtk_widget_set_sensitive(_item, enabled ? 1 : 0);
    }

    public void SetChecked(bool checked)
    {
        _echoing = true;
        gtk_check_menu_item_set_active(_item, checked ? 1 : 0);
        _echoing = false;
    }

    /// **GTK does not draw a default menu item.** Windows bolds one and
    /// double-clicking the parent chooses it; there is no such idea in GTK and
    /// no theme that expresses one, so this does nothing rather than
    /// approximating it with markup that would not match the theme.
    public void SetDefault(bool isDefault) { }

    public GtkWidget* Widget => _item;
}

// ================================================================ a menu

public class GtkMenuPeer : IMenuPeer
{
    GtkWidget* _menu;
    /// Owned: one reference, sunk at construction. A menu bar goes into a
    /// window and a popup goes nowhere, so neither can be left to a parent.
    List<GtkWidget*> _items;

    public GtkMenuPeer(bool isBar)
    {
        _menu = (GtkWidget*)g_object_ref_sink(
            (gpointer)(isBar ? gtk_menu_bar_new() : gtk_menu_new()));
        _items = new List<GtkWidget*>();
    }

    ~GtkMenuPeer()
    {
        if (_menu == null)
            return;
        gtk_widget_destroy(_menu);
        g_object_unref((gpointer)_menu);
        _menu = null;
    }

    public nuint Handle => (nuint)(void*)_menu;

    /// Adds a command, or a heading when `submenu` is given.
    ///
    /// **A heading is a plain item and a command is a check item**, and the
    /// split is what stops every entry on the menu bar drawing an empty tick
    /// box. GTK will not turn a plain item into a checkable one, and a command
    /// does not know at construction whether it will ever be ticked -- so a
    /// command stays a check item, which draws its indicator only once
    /// something has set one. A heading is different in kind: it opens a
    /// submenu and there is nothing it could mean to tick it, so the question
    /// never arises and the plain widget is the honest one.
    public IMenuItemPeer AddItem(IMenuItemNotify owner, String text, IMenuPeer? submenu)
    {
        String label = ToMnemonic(text);
        GtkWidget* made = submenu != null
            ? gtk_menu_item_new_with_mnemonic(label.ToPointer())
            : gtk_check_menu_item_new_with_mnemonic(label.ToPointer());
        if (submenu != null)
        {
            gtk_menu_item_set_submenu(made, ((GtkMenuPeer)submenu).Widget);
        }

        gtk_menu_shell_append(_menu, made);
        gtk_widget_show(made);
        _items.Add(made);
        return new GtkMenuItemPeer(made, owner);
    }

    public void AddSeparator()
    {
        GtkWidget* line = gtk_separator_menu_item_new();
        gtk_menu_shell_append(_menu, line);
        gtk_widget_show(line);
        _items.Add(line);
    }

    public void Clear()
    {
        for (nuint i = 0u; i < _items.Count; i++)
        {
            gtk_container_remove(_menu, _items[i]);
        }
        _items.Clear();
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
    public void ShowPopup(IWindowPeer owner, Point atScreen)
    {
        var id = ConnectPlain(_menu, "deactivate", () => { gtk_main_quit(); });

        gtk_menu_popup_at_pointer(_menu, null);
        gtk_main();

        // Disconnected rather than left in place: the menu may be shown again,
        // and a second `deactivate` reaching a loop that has already returned
        // would quit the application's.
        Disconnect(_menu, id);
    }

    public GtkWidget* Widget => _menu;
}

#endif
