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

// Menus and pictures: the two things here that are not windows.
//
// **A menu is a handle with items in it, and an item is a number.** Choosing
// one posts `WM_COMMAND` to the window the menu is on, carrying the id and
// nothing else -- the same message a button's click arrives on, told apart by
// `lParam` being null where a control would have put its handle.
//
// **Which means the id has to be resolved back to an item.** The obvious way is
// a table keyed by id, and the obvious way is wrong here: it would be a mutable
// global that every menu in the program shares, and something would have to
// remember to take entries out of it. A menu is a tree this module already
// holds, and a tree of a dozen items is quicker to walk than a hash is to
// consult -- so the window asks its own menu to find the id, recursively, and
// nothing global exists at all.
module Forms.Platform.Win32;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;
#if WINDOWS
import Win32;
import Win32.Handles;
import Win32.Kernel32;
import Win32.User32;
import Win32.Gdi32;
import Win32.ComCtl32;
import Win32.Resources;

/// The next command id to hand out.
///
/// A plain `int`, so it crosses no thread boundary the compiler would object to
/// -- and it never needs to be reused, because ids are only ever compared for
/// equality and a program that exhausts two billion menu items has other
/// problems. Starting above the range a dialog's own controls use keeps it
/// clear of `IDOK` and its relatives.
static int nextCommandId = 0x8000;

int NewCommandId()
{
    nextCommandId = nextCommandId + 1;
    return nextCommandId;
}

// ====================================================================== items

/// One item in a menu.
public class MenuItemPeer : IMenuItemPeer
{
    HMENU _owner;
    int _id;
    weak IMenuItemNotify? target;
    /// The menu underneath it, kept so that a search for an id can descend.
    IMenuPeer? _below;

    public MenuItemPeer(HMENU menu, int command, IMenuItemNotify? notify, IMenuPeer? submenu)
    {
        _owner = menu;
        _id = command;
        target = notify;
        _below = submenu;
    }

    /// The id `WM_COMMAND` will carry for this item.
    public int Command() => _id;

    public nuint Id() => (nuint)_id;

    /// The menu under this item, if it is a heading rather than a command.
    public IMenuPeer? Submenu() => _below;

    /// Runs the handler. Called by whichever window resolved the id.
    public void Raise()
    {
        IMenuItemNotify? held = target;
        if (held == null)
            return;
        ((IMenuItemNotify)held).OnPlatformMenuClicked();
    }

    public void SetText(String text)
    {
        MenuItemInfo info;
        Blank(&info);
        info.Mask = MiimString;
        info.TypeData = text.ToUtf16().ToPointer();
        SetMenuItemInfoW(_owner, (uint)_id, 0, &info);
    }

    public void SetEnabled(bool enabled)
    {
        EnableMenuItem(_owner, (uint)_id, MfByCommand | (enabled ? MfEnabled : MfGrayed));
    }

    public void SetChecked(bool checked)
    {
        CheckMenuItem(_owner, (uint)_id, MfByCommand | (checked ? MfChecked : MfUnchecked));
    }

    public void SetDefault(bool isDefault)
    {
        MenuItemInfo info;
        Blank(&info);
        info.Mask = MiimState;
        info.State = isDefault ? MfsDefault : MfsEnabled;
        SetMenuItemInfoW(_owner, (uint)_id, 0, &info);
    }
}

/// A `MENUITEMINFO` with its size filled in and everything else zeroed, because
/// Windows reads the whole structure and a field left as whatever was on the
/// stack is a field it will act on.
void Blank(MenuItemInfo* info)
{
    info->Size = (uint)sizeof(MenuItemInfo);
    info->Mask = 0u;
    info->Type = 0u;
    info->State = 0u;
    info->Id = 0u;
    info->SubMenu = null;
    info->Checked = null;
    info->Unchecked = null;
    info->ItemData = 0u;
    info->TypeData = null;
    info->TypeDataLength = 0u;
    info->Item = null;
}

// ====================================================================== menus

/// A menu: a bar, a drop-down or a popup, which on Windows are one thing.
public class MenuPeer : IMenuPeer
{
    HMENU _menu;
    List<MenuItemPeer> _items;
    /// Whether this menu is a bar. A bar and a popup are created by different
    /// calls and drawn differently, and cannot be exchanged afterwards.
    bool _asBar;
    /// True once a window has taken this menu, because a window destroys the
    /// menu it holds and destroying it twice is a crash.
    bool _attached;

    public MenuPeer(bool bar)
    {
        _asBar = bar;
        _attached = false;
        _items = new List<MenuItemPeer>();
        _menu = bar ? CreateMenu() : CreatePopupMenu();
    }

    ~MenuPeer()
    {
        if (_menu != null && !_attached)
        {
            DestroyMenu(_menu);
            _menu = null;
        }
    }

    public nuint Handle() => (nuint)(void*)_menu;

    /// The same, as the type the Windows calls want.
    public HMENU Native() => _menu;

    /// Says that something else has taken ownership, so this will not destroy
    /// it: a window frees its menu bar, and a menu frees the submenus under it.
    ///
    /// Not on `IMenuPeer`. It is this backend talking to itself, reached by
    /// narrowing the interface back to the class behind it -- which is what the
    /// seam should be spared.
    public void OwnedByParent() => _attached = true;

    public IMenuItemPeer AddItem(IMenuItemNotify owner, String text, IMenuPeer? submenu)
    {
        int id = NewCommandId();
        if (submenu == null)
        {
            AppendMenuW(_menu, MfString, (nuint)id, text.ToUtf16().ToPointer());
        }
        else
        {
            IMenuPeer given = (IMenuPeer)submenu;
            if (given is MenuPeer under)
            {
                // A submenu is freed with the menu that holds it, so it must
                // stop freeing itself.
                under.OwnedByParent();
                AppendMenuW(_menu, MfString | MfPopup, (nuint)(void*)under.Native(),
                            text.ToUtf16().ToPointer());
            }
        }

        var made = new MenuItemPeer(_menu, id, owner, submenu);
        _items.Add(made);
        return made;
    }

    public void AddSeparator()
    {
        AppendMenuW(_menu, MfSeparator, 0u, null);
    }

    public void Clear()
    {
        while (GetMenuItemCount(_menu) > 0)
        {
            DeleteMenu(_menu, 0u, MfByPosition);
        }
        _items.Clear();
    }

    /// The item with this command id, anywhere below this menu.
    ///
    /// Depth first, because a menu is a tree and the id could be at any level.
    /// Linear, because a menu with enough items for that to matter is a menu
    /// nobody can use.
    public MenuItemPeer? Find(int id)
    {
        foreach (var item in _items)
        {
            var under = item.Submenu();
            // **A heading is not a command.** An item with a submenu opens it,
            // and Windows sends no `WM_COMMAND` for that -- the id handed to
            // `AppendMenuW` for such an item is the submenu's handle, so the
            // command id this item was given is never used by anything. Letting
            // it match here would run a handler nothing could have raised.
            if (under == null && item.Command() == id)
                return item;
            if (under != null)
            {
                IMenuPeer held = (IMenuPeer)under;
                if (held is MenuPeer below)
                {
                    var deeper = below.Find(id);
                    if (deeper != null)
                        return deeper;
                }
            }
        }
        return null;
    }

    /// Shows this menu at a point and waits.
    ///
    /// `TPM_RETURNCMD` makes it answer the chosen id rather than posting
    /// `WM_COMMAND`, so a popup resolves its own item and needs no routing
    /// through the window at all.
    public void ShowPopup(IWindowPeer owner, FPoint atScreen)
    {
        HWND window = (HWND)(void*)owner.Handle();
        // Windows will not dismiss a popup on a click outside it unless the
        // owning window is foreground first; without this the menu can be left
        // on screen with nothing able to close it.
        SetForegroundWindow(window);
        int chosen = TrackPopupMenu(_menu, TpmLeftAlign | TpmTopAlign
                                        | TpmRightButton | TpmReturnCmd,
                                    atScreen.X, atScreen.Y, 0, window, null);
        if (chosen == 0)
            return;
        var item = Find(chosen);
        if (item != null)
            ((MenuItemPeer)item).Raise();
    }
}

// =================================================================== pictures

/// A picture, held as a GDI bitmap.
public class BitmapBackend : IBitmapBackend
{
    HBITMAP _bitmap;
    int _wide;
    int _high;

    public BitmapBackend(HBITMAP handle, int width, int height)
    {
        _bitmap = handle;
        _wide = width;
        _high = height;
    }

    ~BitmapBackend()
    {
        if (_bitmap != null)
        {
            DeleteObject((HGDIOBJ)(void*)_bitmap);
            _bitmap = null;
        }
    }

    public int Width() => _wide;
    public int Height() => _high;
    public nuint Handle() => (nuint)(void*)_bitmap;
    public HBITMAP Native() => _bitmap;
}

/// Reads a `.bmp` from disk.
///
/// **Only `.bmp`**, because `LoadImageW` is the whole of what Windows will
/// decode without a library: PNG and JPEG need GDI+ or WIC, each of which is a
/// binding of its own. The error says so rather than answering a null nobody
/// checks.
public Result<IBitmapBackend, String> LoadBitmapFile(String path)
{
    var handle = LoadImageW(null, path.ToUtf16().ToPointer(), ImageBitmap,
                            0, 0, LrLoadFromFile | LrCreateDibSection);
    if (handle == null)
    {
        return Fail("could not load '" + path + "' as a bitmap; only .bmp is read");
    }

    HBITMAP bitmap = (HBITMAP)(void*)handle;

    // `BITMAP`'s first three fields, which is all that is wanted and which
    // spares a structure nothing else here needs.
    int[] header = new int[10];
    GetObjectW((HGDIOBJ)(void*)bitmap, 40, (void*)&header[0u]);
    int width = header[1u];
    int height = header[2u];
    if (height < 0)
        height = -height;

    return Ok(new BitmapBackend(bitmap, width, height));
}

/// Reads a bitmap out of this program's own resources.
///
/// The same `LoadImageW` as above with the other half of its contract: given a
/// module and a `MAKEINTRESOURCE` name instead of `LrLoadFromFile` and a path,
/// it reads an `RT_BITMAP` out of the mapped image. Nothing touches the disk,
/// so an icon cannot go missing between building the program and running it --
/// which is the whole reason to put one in the binary.
///
/// `LrCreateDibSection` for the same reason as above: a device-independent
/// bitmap keeps its own colours rather than being matched to the screen's
/// palette on load.
public Result<IBitmapBackend, String> LoadResourceBitmap(int id)
{
    var handle = LoadImageW((HINSTANCE)GetModuleHandleW(null), Resources.Id(id),
                            ImageBitmap, 0, 0, LrCreateDibSection);
    if (handle == null)
    {
        return Fail($"this program has no bitmap resource with id {id}");
    }

    HBITMAP bitmap = (HBITMAP)(void*)handle;

    int[] header = new int[10];
    GetObjectW((HGDIOBJ)(void*)bitmap, 40, (void*)&header[0u]);
    int width = header[1u];
    int height = header[2u];
    if (height < 0)
        height = -height;

    return Ok(new BitmapBackend(bitmap, width, height));
}

/// Same-sized pictures, indexed by number.
public class ImageListBackend : IImageListBackend
{
    HIMAGELIST _list;
    FSize _each;
    int _held;

    public ImageListBackend(FSize size)
    {
        _each = size;
        _held = 0;
        _list = ImageList_Create(size.Width, size.Height,
                                IlcColor32 | IlcMask, 4, 4);
    }

    ~ImageListBackend()
    {
        if (_list != null)
        {
            ImageList_Destroy(_list);
            _list = null;
        }
    }

    /// Adds a picture, treating magenta as the part not to draw.
    ///
    /// A mask colour rather than an alpha channel, because a `.bmp` has no
    /// alpha and magenta is the colour every toolbar bitmap has used for this
    /// since Windows 95.
    public int Add(IBitmapBackend picture)
    {
        if (picture is BitmapBackend native)
        {
            int at = ImageList_AddMasked(_list, native.Native(), 0x00FF00FFu);
            if (at >= 0)
                _held = _held + 1;
            return at;
        }
        return -1;
    }

    /// How many have been added, for a caller that wants the number without
    /// asking the platform.
    public int Added() => _held;

    public int Count() => ImageList_GetImageCount(_list);
    public FSize ImageSize() => _each;
    public nuint Handle() => (nuint)(void*)_list;
    public HIMAGELIST Native() => _list;
}

#endif
