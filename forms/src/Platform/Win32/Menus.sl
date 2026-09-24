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

/// The range command ids are handed out from.
///
/// `WM_COMMAND` carries an id in its low word, so an id MUST fit in sixteen
/// bits. The upper half keeps clear of `IDOK` and its relatives, which
/// `IsDialogMessageW` sends as commands of its own.
const int FirstCommandId = 0x8000;
const int CommandIdCount = 0x8000;

/// One bit per id, set while an item or a button holds it. A popup menu is
/// built afresh on every showing, so ids MUST come back when their holders go.
static readonly ulong[] s_commandIdsHeld = new ulong[512];

/// Where the search for a free id starts: just past the last one handed out,
/// so a freed id is the last to be reused rather than the first -- a click
/// already queued for it then finds nothing rather than someone else.
static int s_commandIdCursor = 0;

int AllocateCommandId()
{
    for (int tried = 0; tried < CommandIdCount; tried++)
    {
        int slot = s_commandIdCursor;
        s_commandIdCursor = (s_commandIdCursor + 1) % CommandIdCount;
        nuint word = (nuint)(slot / 64);
        ulong bit = (ulong)1u << (nuint)(slot % 64);
        if ((s_commandIdsHeld[word] & bit) == 0u)
        {
            s_commandIdsHeld[word] = s_commandIdsHeld[word] | bit;
            return FirstCommandId + slot;
        }
    }
    sl_fail("more than 32768 menu items and toolbar buttons are alive at once".ToPointer());
    return 0;
}

/// Gives an id back. The caller MUST NOT use it afterwards.
void ReleaseCommandId(int id)
{
    int slot = id - FirstCommandId;
    if (slot < 0 || slot >= CommandIdCount)
        return;
    nuint word = (nuint)(slot / 64);
    s_commandIdsHeld[word] = s_commandIdsHeld[word] & ~((ulong)1u << (nuint)(slot % 64));
}

// ====================================================================== items

/// One item in a menu.
public class MenuItemPeer : IMenuItemPeer
{
    HMENU _owner;
    int _id;

    /// Where in the owning menu this item sits.
    ///
    /// **Every call below addresses the item by position, and that is a fix
    /// rather than a preference.** An item that opens a submenu is appended
    /// with `MF_POPUP` and the submenu's handle *in place of* a command id, so
    /// it has none -- and `MF_BYCOMMAND` finds items by their id. Windows
    /// documents this for `EnableMenuItem` and it is true of the whole family:
    /// a by-command call naming a submenu heading matches nothing, changes
    /// nothing, and reports nothing.
    ///
    /// So `SetText`, `SetEnabled`, `SetChecked` and `SetDefault` had all been
    /// quietly doing nothing to every heading in every menu since they were
    /// written, and it took owner drawing to show it: a renderer drew every
    /// item except the ones with submenus, which Windows went on drawing
    /// itself, and one row in a menu looked wrong.
    ///
    /// Positions are stable because a menu is only ever appended to and
    /// cleared whole -- `AddItem` and `AddSeparator` both append, and `Clear`
    /// empties everything.
    int _at;

    weak IMenuItemNotify? _target;
    /// The menu underneath it, kept so that a search for an id can descend.
    IMenuPeer? _submenu;

    public MenuItemPeer(HMENU menu, int command, int position,
                        IMenuItemNotify? notify, IMenuPeer? submenu)
    {
        _owner = menu;
        _id = command;
        _at = position;
        _target = notify;
        _submenu = submenu;
    }

    ~MenuItemPeer()
    {
        ReleaseCommandId(_id);
    }

    /// The id `WM_COMMAND` will carry for this item.
    public int Command => _id;

    public nuint Id => (nuint)_id;

    /// The menu under this item, if it is a heading rather than a command.
    public IMenuPeer? Submenu => _submenu;

    /// Runs the handler. Called by whichever window resolved the id.
    public void RaiseClick()
    {
        IMenuItemNotify? held = _target;
        if (held == null)
            return;
        ((IMenuItemNotify)held).OnPlatformMenuClicked();
    }

    public void SetText(String text)
    {
        MenuItemInfo info;
        ClearMenuItemInfo(&info);
        info.Mask = MiimString;
        var wide = text.ToUtf16();
        info.TypeData = wide.ToPointer();
        SetMenuItemInfoW(_owner, (uint)_at, 1, &info);
    }

    public void SetEnabled(bool enabled)
    {
        EnableMenuItem(_owner, (uint)_at, MfByPosition | (enabled ? MfEnabled : MfGrayed));
    }

    public void SetChecked(bool checked)
    {
        CheckMenuItem(_owner, (uint)_at, MfByPosition | (checked ? MfChecked : MfUnchecked));
    }

    /// Turns owner drawing on or off for this item.
    ///
    /// `MIIM_FTYPE` and not `MIIM_TYPE`: the older mask means the type *and*
    /// the string together, so setting it with `TypeData` left null is how an
    /// item loses its caption -- which is a long way from where anyone would
    /// look for the cause.
    ///
    /// The caption stays either way, and a renderer needs it: an owner-drawn
    /// item still knows what it says, and `GetText` on the control layer is
    /// what a renderer asks rather than the menu.
    public bool SetOwnerDrawn(bool drawn)
    {
        MenuItemInfo info;
        ClearMenuItemInfo(&info);
        info.Mask = MiimFType;

        // Read what the type is now, so that a separator does not quietly
        // become a command by being written back without its flag.
        if (GetMenuItemInfoW(_owner, (uint)_at, 1, &info) == 0)
            return false;

        info.Type = drawn ? (info.Type | MftOwnerDraw)
                          : (info.Type & ~MftOwnerDraw);

        // **The id goes in `MIIM_DATA`, and that is not belt and braces.**
        // `WM_MEASUREITEM` and `WM_DRAWITEM` name an item by its command id --
        // and an item that opens a submenu has none, which is the same fact
        // that made the by-command calls above fail. So a window could turn
        // every *leaf* item back into an object and no heading, answered the
        // default size for those, and a menu bar of nothing but headings
        // collapsed to no height at all.
        //
        // `itemData` is carried through both messages untouched, so the item
        // says who it is rather than being asked. A plain integer, because a
        // reference handed to Windows is a reference nothing is counting.
        info.Mask = MiimFType | MiimData;
        info.ItemData = drawn ? (nuint)_id : 0u;
        return SetMenuItemInfoW(_owner, (uint)_at, 1, &info) != 0;
    }

    /// What the item is notified through, for a window that has resolved an id
    /// and needs to ask it to draw.
    public IMenuItemNotify? Notify => _target;

    public void SetDefault(bool isDefault)
    {
        MenuItemInfo info;
        ClearMenuItemInfo(&info);
        info.Mask = MiimState;
        info.State = isDefault ? MfsDefault : MfsEnabled;
        SetMenuItemInfoW(_owner, (uint)_at, 1, &info);
    }
}

/// A `MENUITEMINFO` with its size filled in and everything else zeroed, because
/// Windows reads the whole structure and a field left as whatever was on the
/// stack is a field it will act on.
void ClearMenuItemInfo(MenuItemInfo* info)
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
    bool _isMenuBar;
    /// True once a window has taken this menu, because a window destroys the
    /// menu it holds and destroying it twice is a crash.
    bool _isAttached;

    public MenuPeer(bool bar)
    {
        _isMenuBar = bar;
        _isAttached = false;
        _items = new List<MenuItemPeer>();
        _menu = bar ? CreateMenu() : CreatePopupMenu();
    }

    ~MenuPeer()
    {
        if (_menu != null && !_isAttached)
        {
            DestroyMenu(_menu);
            _menu = null;
        }
    }

    public nuint Handle => (nuint)(void*)_menu;

    /// The same, as the type the Windows calls want.
    public HMENU Native => _menu;

    /// Says that something else has taken ownership, so this will not destroy
    /// it: a window frees its menu bar, and a menu frees the submenus under it.
    ///
    /// Not on `IMenuPeer`. It is this backend talking to itself, reached by
    /// narrowing the interface back to the class behind it -- which is what the
    /// seam should be spared.
    public void MarkOwnedByParent() => _isAttached = true;

    /// Says that whatever held it has let go, so this destroys it again.
    public void MarkReleasedByParent() => _isAttached = false;

    public IMenuItemPeer AddItem(IMenuItemNotify owner, String text, IMenuPeer? submenu)
    {
        int id = AllocateCommandId();

        // Read before the append, so it is this item's index rather than the
        // count afterwards. Separators are appended too and take a position,
        // which is why this asks the menu rather than counting `_items`.
        int at = GetMenuItemCount(_menu);
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
                under.MarkOwnedByParent();
                AppendMenuW(_menu, MfString | MfPopup, (nuint)(void*)under.Native,
                            text.ToUtf16().ToPointer());
            }
        }

        var made = new MenuItemPeer(_menu, id, at, owner, submenu);
        _items.Add(made);
        return made;
    }

    public void AddSeparator()
    {
        AppendMenuW(_menu, MfSeparator, 0u, null);
    }

    /// `RemoveMenu` rather than `DeleteMenu`, which would destroy each submenu
    /// while its own `MenuPeer` still holds the handle. A submenu let go of is
    /// its peer's to destroy again.
    public void Clear()
    {
        while (GetMenuItemCount(_menu) > 0)
        {
            RemoveMenu(_menu, 0u, MfByPosition);
        }
        foreach (var item in _items)
        {
            var under = item.Submenu;
            if (under != null)
            {
                IMenuPeer held = (IMenuPeer)under;
                if (held is MenuPeer below)
                    below.MarkReleasedByParent();
            }
        }
        _items.Clear();
    }

    /// The item with this command id, anywhere below this menu.
    ///
    /// Depth first, because a menu is a tree and the id could be at any level.
    /// Linear, because a menu with enough items for that to matter is a menu
    /// nobody can use.
    public MenuItemPeer? FindCommand(int id)
    {
        foreach (var item in _items)
        {
            var under = item.Submenu;
            // **A heading is not a command.** An item with a submenu opens it,
            // and Windows sends no `WM_COMMAND` for that -- the id handed to
            // `AppendMenuW` for such an item is the submenu's handle, so the
            // command id this item was given is never used by anything. Letting
            // it match here would run a handler nothing could have raised.
            if (under == null && item.Command == id)
                return item;
            if (under != null)
            {
                IMenuPeer held = (IMenuPeer)under;
                if (held is MenuPeer below)
                {
                    var deeper = below.FindCommand(id);
                    if (deeper != null)
                        return deeper;
                }
            }
        }
        return null;
    }

    /// The item with this command id, heading or not.
    ///
    /// **The other question, and `FindCommand` above can only answer one of
    /// them.** That one is asked by `WM_COMMAND` routing, where a heading must
    /// *not* match: an item with a submenu raises no command, and letting its
    /// id match would run a handler nothing could have raised.
    ///
    /// Drawing asks the opposite. `WM_DRAWITEM` for a heading is Windows
    /// asking the program to draw that very item, and a lookup that skipped it
    /// answered null -- so the window fell back to the default size, every
    /// heading came out no pixels wide, and a menu bar made only of headings
    /// disappeared. One method was answering two questions and could only be
    /// right about one.
    public MenuItemPeer? FindItem(int id)
    {
        foreach (var item in _items)
        {
            if (item.Command == id)
                return item;

            var under = item.Submenu;
            if (under != null)
            {
                IMenuPeer held = (IMenuPeer)under;
                if (held is MenuPeer below)
                {
                    var deeper = below.FindItem(id);
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
        HWND window = (HWND)(void*)owner.Handle;
        // Windows will not dismiss a popup on a click outside it unless the
        // owning window is foreground first; without this the menu can be left
        // on screen with nothing able to close it.
        SetForegroundWindow(window);

        // **The window has to be told this menu exists.** `WM_MEASUREITEM` and
        // `WM_DRAWITEM` arrive at the window rather than at the menu, naming
        // an item by its command id and nothing else -- and a popup belongs to
        // no menu bar, so the window would have nowhere to look the id up. It
        // is told for exactly as long as the menu is on screen.
        WindowPeer? host = null;
        if (owner is WindowPeer named)
            host = named;
        if (host != null)
            ((WindowPeer)host).SetPoppedUpMenu(this);

        int chosen = TrackPopupMenu(_menu, TpmLeftAlign | TpmTopAlign
                                        | TpmRightButton | TpmReturnCmd,
                                    atScreen.X, atScreen.Y, 0, window, null);
        // Documented for `TrackPopupMenu`: without a message after it, the
        // next time the menu is shown it can close again at once.
        PostMessageW(window, WmNull, 0u, 0);

        if (host != null)
            ((WindowPeer)host).SetPoppedUpMenu(null);

        if (chosen == 0)
            return;
        var item = FindCommand(chosen);
        if (item != null)
            ((MenuItemPeer)item).RaiseClick();
    }
}

// =================================================================== pictures

/// A picture, held as a GDI bitmap.
public class BitmapBackend : IBitmapBackend
{
    HBITMAP _bitmap;
    int _width;
    int _height;
    bool _hasAlpha;

    public BitmapBackend(HBITMAP handle, int width, int height)
    {
        _bitmap = handle;
        _width = width;
        _height = height;
        _hasAlpha = false;
    }

    /// The same, for a bitmap whose alpha channel means something -- which is
    /// the one this library made itself, from pixels a decoder produced.
    public BitmapBackend(HBITMAP handle, int width, int height, bool alpha)
    {
        _bitmap = handle;
        _width = width;
        _height = height;
        _hasAlpha = alpha;
    }

    ~BitmapBackend()
    {
        if (_bitmap != null)
        {
            DeleteObject((HGDIOBJ)(void*)_bitmap);
            _bitmap = null;
        }
    }

    public int Width => _width;
    public int Height => _height;
    public nuint Handle => (nuint)(void*)_bitmap;
    public bool HasAlpha => _hasAlpha;
    public HBITMAP Native => _bitmap;
}

/// A picture from pixels the caller already has.
///
/// `pixels` is blue, green, red, alpha, rows top to bottom -- which is a DIB's
/// own byte order, so the copy is a `memcpy` rather than a conversion. The
/// header asks for a *negative* height to say the rows are top-down; without
/// it GDI would read them bottom-up and the picture would be upside down.
///
/// **The alpha arrives straight and is stored premultiplied.** `AlphaBlend`
/// is the only thing on Windows that reads this channel and it requires
/// premultiplied colour -- given straight colour it lightens every
/// partly-transparent pixel, which looks like a halo round every icon. Doing
/// it here means the seam can promise one thing and each backend can want
/// what it wants.
public Result<IBitmapBackend, String> CreateBitmapFromPixels(int width, int height,
                                                             byte[] pixels)
{
    if (width <= 0 || height <= 0)
        return Fail("a bitmap needs a positive width and height");

    nuint needed = (nuint)width * (nuint)height * 4u;
    if (pixels.Length < needed)
        return Fail("a bitmap of " + Text.FromInteger((long)width) + "x"
                    + Text.FromInteger((long)height) + " needs "
                    + Text.FromInteger((long)needed) + " bytes and was given "
                    + Text.FromInteger((long)pixels.Length));

    BitmapInfo info;
    info.Header.Size = (uint)sizeof(BitmapInfoHeader);
    info.Header.Width = width;
    info.Header.Height = -height;               // top-down, as above
    info.Header.Planes = (ushort)1;
    info.Header.BitCount = (ushort)32;
    info.Header.Compression = BitmapCompressionRgb;
    info.Header.ImageByteLength = 0u;
    info.Header.PixelsPerMeterX = 0;
    info.Header.PixelsPerMeterY = 0;
    info.Header.ColoursUsed = 0u;
    info.Header.ColoursImportant = 0u;
    info.FirstColour = 0u;

    void* bits = null;
    var handle = CreateDIBSection(null, &info, DibRgbColours, &bits, null, 0u);
    if (handle == null || bits == null)
        return Fail("Windows would not make a bitmap of that size");

    byte* into = (byte*)bits;
    for (nuint i = 0u; i < needed; i = i + 4u)
    {
        uint alpha = (uint)pixels[i + 3u];
        into[i]      = (byte)(((uint)pixels[i] * alpha) / 255u);
        into[i + 1u] = (byte)(((uint)pixels[i + 1u] * alpha) / 255u);
        into[i + 2u] = (byte)(((uint)pixels[i + 2u] * alpha) / 255u);
        into[i + 3u] = (byte)alpha;
    }

    return Ok(new BitmapBackend(handle, width, height, true));
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
    var handle = LoadImageW((HINSTANCE)GetModuleHandleW(null), Resources.MakeIntResource(id),
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
    FSize _imageSize;
    int _addedCount;

    public ImageListBackend(FSize size)
    {
        _imageSize = size;
        _addedCount = 0;
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

    /// Adds a picture: by its alpha channel where it has one, and by magenta
    /// where it does not.
    ///
    /// **Both, because the two kinds of picture arrive here.** A `.bmp` read
    /// by the platform's loader has no alpha -- its fourth byte is zero, which
    /// is what "invisible" is spelled as -- and magenta is the colour every
    /// toolbar bitmap has keyed on since Windows 95. A picture the program
    /// generated or decoded carries a real channel, and `ImageList_AddMasked`
    /// would throw it away and then key on a magenta that is not there,
    /// leaving every soft edge as a hard one against the wrong colour.
    ///
    /// `HasAlpha` is what tells them apart, and it answers true only where the
    /// pixels came from somewhere that says what the channel means.
    public int Add(IBitmapBackend picture)
    {
        if (picture is BitmapBackend native)
        {
            int at = native.HasAlpha
                   ? ImageList_Add(_list, native.Native, null)
                   : ImageList_AddMasked(_list, native.Native, 0x00FF00FFu);
            if (at >= 0)
                _addedCount = _addedCount + 1;
            return at;
        }
        return -1;
    }

    /// How many have been added, for a caller that wants the number without
    /// asking the platform.
    public int AddedCount => _addedCount;

    public int Count => ImageList_GetImageCount(_list);
    public FSize ImageSize => _imageSize;
    public nuint Handle => (nuint)(void*)_list;
    public HIMAGELIST Native => _list;
}

#endif
