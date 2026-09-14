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

// One peer per native widget.
//
// Every one of these is the same three things: a `CreateWindowExW` with the
// right class and style bits, an override of `Notified` saying what this
// control's notification codes mean, and the handful of messages that are its
// own API. That is the whole of a Windows control, and it is why the LCL needs
// a `TWSxxx` class for each and why this needs a peer for each.
//
// **`BUTTON` is four controls.** A push button, a check box, a radio button and
// a group box are all the `BUTTON` window class differing only in style bits,
// which is a Windows quirk worth naming because it is the reason `CheckPeer`
// and `GroupPeer` look like `ButtonPeer` with an argument changed.
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

/// The styles every child control shares. `WS_CLIPSIBLINGS` is the one worth
/// naming: without it two overlapping children each paint over the other and
/// the form flickers on every move.
///
/// A function rather than a `const`, because a module-level constant must be
/// initialized with a literal and this is four of them combined.
uint ChildStyle() { return WsChild | WsVisible | WsClipSiblings | WsTabStop; }

/// The width of a check box's box, which `GetSystemMetrics` reports under an
/// index `Win32.User32` does not yet name.
const int SmCheckBoxWidth = 71;

/// A thin sunken border, the one `WS_EX_CLIENTEDGE`'s lighter sibling.
const uint WsExStaticEdge = 0x00020000u;

/// Makes a child window of one of the system classes.
///
/// The bounds are zero because the control layer sets them immediately
/// afterwards through `SetBounds`, and creating at a real position would put
/// the widget on screen at a size nothing had decided yet.
HWND MakeChild(String className, HWND parent, uint style, uint extended) {
    return CreateWindowExW(extended,
                           className.ToUtf16().ToPointer(),
                           "".ToUtf16().ToPointer(),
                           style, 0, 0, 0, 0,
                           parent, null, GetModuleHandleW(null), null);
}

/// The peer of whatever a widget set was handed as a parent, as a window.
HWND WindowOf(IContainerPeer parent) {
    return (HWND)(void*)parent.Handle();
}

// =================================================================== button

/// A push button.
public class ButtonPeer : ControlPeer, IButtonPeer {
    public ButtonPeer(IControlNotify owner, IContainerPeer parent) {
        base(MakeChild("BUTTON", WindowOf(parent), ChildStyle() | BsPushButton, 0u),
             owner, true);
    }

    /// `BN_CLICKED` arrives whether the button was clicked or pressed with the
    /// keyboard, which is exactly what `OnPlatformActivated` means.
    protected override bool Notified(uint code, int id) {
        if (code != BnClicked) { return false; }
        var owner = Owner();
        if (owner == null) { return false; }
        ((IControlNotify)owner).OnPlatformActivated();
        return true;
    }

    /// Makes this the button Enter presses.
    ///
    /// The style change has to be followed by a repaint: Windows draws the
    /// heavier border from the style bit and does not notice it changed.
    public void SetDefault(bool isDefault) {
        SendMessageW(window, BmSetStyle,
                     (ulong)(isDefault ? BsDefPushButton : BsPushButton), 1);
    }

    /// Wide enough for the caption plus the padding a Windows button has, and
    /// never narrower than the 75x23 dialog units every Windows button is.
    public override FSize PreferredSize() {
        var owner = Owner();
        var measured = MeasureNative();
        int width = measured.Width + 20;
        int height = measured.Height + 10;
        if (width < 75)  { width = 75; }
        if (height < 23) { height = 23; }
        return Extent(width, height);
    }

    /// The text this widget holds, measured in the font it is set to.
    protected FSize MeasureNative() {
        HDC dc = GetDC(window);
        HGDIOBJ wasFont = SelectObject(dc, (HGDIOBJ)(nuint)(ulong)SendMessageW(window, WmGetFont, 0u, 0));
        var wide = GetText().ToUtf16();
        Win32.User32.Size measured;
        GetTextExtentPoint32W(dc, wide.ToPointer(), (int)wide.UnitCount(), &measured);
        SelectObject(dc, wasFont);
        ReleaseDC(window, dc);
        return Extent(measured.Width, measured.Height);
    }
}

// ================================================== check box and radio button

/// A check box or a radio button, which differ from each other and from a push
/// button only in style bits.
///
/// **`BS_AUTOCHECKBOX` rather than `BS_CHECKBOX`.** The auto form toggles
/// itself when clicked; the plain one expects the program to do it, which is
/// what the LCL does and what makes an LCL check box feel a frame slow. The
/// cost is that the state has to be read back rather than assumed, which
/// `GetChecked` does.
public class CheckPeer : ControlPeer, ICheckPeer {
    bool isRadio;

    public CheckPeer(IControlNotify owner, IContainerPeer parent, bool radio) {
        base(MakeChild("BUTTON", WindowOf(parent),
                       ChildStyle() | (radio ? BsAutoRadioButton : BsAutoCheckBox), 0u),
             owner, true);
        isRadio = radio;
    }

    protected override bool Notified(uint code, int id) {
        if (code != BnClicked) { return false; }
        var owner = Owner();
        if (owner == null) { return false; }
        var control = (IControlNotify)owner;
        // A tick is both an activation and a change of value, and a program
        // may reasonably listen for either.
        control.OnPlatformActivated();
        control.OnPlatformValueChanged();
        return true;
    }

    public void SetDefault(bool isDefault) { }

    public void SetChecked(bool checked) {
        SendMessageW(window, BmSetCheck, checked ? (ulong)BstChecked : (ulong)BstUnchecked, 0);
    }

    public bool GetChecked() {
        return SendMessageW(window, BmGetCheck, 0u, 0) == (long)BstChecked;
    }

    /// The box or the dot, plus a gap, plus the caption.
    public override FSize PreferredSize() {
        HDC dc = GetDC(window);
        HGDIOBJ wasFont = SelectObject(dc, (HGDIOBJ)(nuint)(ulong)SendMessageW(window, WmGetFont, 0u, 0));
        var wide = GetText().ToUtf16();
        Win32.User32.Size measured;
        GetTextExtentPoint32W(dc, wide.ToPointer(), (int)wide.UnitCount(), &measured);
        SelectObject(dc, wasFont);
        ReleaseDC(window, dc);
        int box = GetSystemMetrics(SmCheckBoxWidth);
        if (box <= 0) { box = 13; }
        int height = measured.Height;
        if (height < box) { height = box; }
        return Extent(measured.Width + box + 8, height + 4);
    }
}

// ==================================================================== label

/// A `STATIC`, which is what Windows calls a label.
///
/// **`SS_NOTIFY`, always.** Without it a static control swallows every mouse
/// message and a label can never be clicked; with it, the click arrives as a
/// `WM_COMMAND` to the parent like any other control's.
public class LabelPeer : ControlPeer, ILabelPeer {
    public LabelPeer(IControlNotify owner, IContainerPeer parent) {
        base(MakeChild("STATIC", WindowOf(parent),
                       (ChildStyle() & ~WsTabStop) | SsNotify | SsLeft, 0u),
             owner, true);
    }

    /// The alignment is a style bit, so changing it is a read, a mask and a
    /// write -- and a repaint, since Windows does not notice.
    public void SetAlignment(HorizontalAlignment alignment) {
        long style = Win32.User32.GetWindowLongPtrW(window, GwlStyle);
        style = style & ~(long)(SsLeft | SsCenter | SsRight);
        if (alignment == HorizontalAlignment.Center)     { style = style | (long)SsCenter; }
        else if (alignment == HorizontalAlignment.Right) { style = style | (long)SsRight; }
        Win32.User32.SetWindowLongPtrW(window, GwlStyle, style);
        Invalidate();
    }

    /// A `STATIC` wraps unless told not to, so this sets the bit that stops it.
    public void SetWordWrap(bool wrap) {
        long style = Win32.User32.GetWindowLongPtrW(window, GwlStyle);
        if (wrap) { style = style & ~(long)SsLeftNoWordWrap; }
        else      { style = style | (long)SsLeftNoWordWrap; }
        Win32.User32.SetWindowLongPtrW(window, GwlStyle, style);
        Invalidate();
    }

    public override FSize PreferredSize() {
        HDC dc = GetDC(window);
        HGDIOBJ wasFont = SelectObject(dc, (HGDIOBJ)(nuint)(ulong)SendMessageW(window, WmGetFont, 0u, 0));
        var wide = GetText().ToUtf16();
        Win32.User32.Size measured;
        GetTextExtentPoint32W(dc, wide.ToPointer(), (int)wide.UnitCount(), &measured);
        SelectObject(dc, wasFont);
        ReleaseDC(window, dc);
        return Extent(measured.Width, measured.Height);
    }
}

// ================================================================= text entry

/// An `EDIT`, single line or multiline.
///
/// **Multiline is decided at creation and cannot change.** `ES_MULTILINE` is
/// one of the style bits Windows reads once, when the control is made; setting
/// it afterwards changes the number and nothing else. So `SetMultiline` is
/// honest about doing nothing, and a control that must change re-creates.
public class TextEntryPeer : ControlPeer, ITextEntryPeer {
    bool multi;

    public TextEntryPeer(IControlNotify owner, IContainerPeer parent, bool multiline) {
        base(MakeChild("EDIT", WindowOf(parent),
                       ChildStyle() | (multiline
                           ? (EsMultiline | EsAutoVScroll | EsWantReturn | WsVerticalScroll)
                           : EsAutoHScroll),
                       WsExClientEdge),
             owner, true);
        multi = multiline;
    }

    protected override bool Notified(uint code, int id) {
        if (code != EnChange) { return false; }
        var owner = Owner();
        if (owner == null) { return false; }
        ((IControlNotify)owner).OnPlatformValueChanged();
        return true;
    }

    public void SetReadOnly(bool readOnly) {
        SendMessageW(window, EmSetReadOnly, (ulong)(readOnly ? 1 : 0), 0);
    }

    public void SetMaxLength(int length) {
        SendMessageW(window, EmSetLimitText, (ulong)length, 0);
    }

    public void SetPasswordChar(char mask) {
        SendMessageW(window, EmSetPasswordChar, (ulong)(uint)mask, 0);
        Invalidate();
    }

    public void SetSelection(int start, int length) {
        SendMessageW(window, EmSetSel, (ulong)start, (long)(start + length));
        SendMessageW(window, EmScrollCaret, 0u, 0);
    }

    public (int, int) GetSelection() {
        uint first = 0u;
        uint last = 0u;
        SendMessageW(window, EmGetSel, (ulong)(nuint)&first, (long)(nuint)&last);
        return ((int)first, (int)(last - first));
    }

    public void SetMultiline(bool multiline) { }

    /// The text split on newlines.
    ///
    /// Done here rather than through `EM_GETLINE`, which wants a buffer whose
    /// first word is its own capacity and answers without a terminator -- an
    /// interface that is easy to get wrong and buys nothing over splitting the
    /// text this control already hands back whole.
    public String[] GetLines() {
        var whole = GetText();
        // Windows keeps CRLF in a multiline edit, so the CR has to go or every
        // line ends with an invisible character that compares unequal.
        return whole.Replace("\r\n", "\n").Split('\n');
    }

    public void SetLines(String[] lines) {
        var joined = new StringBuilder();
        for (nuint i = 0u; i < lines.Length; i += 1u) {
            if (i > 0u) { joined.Append("\r\n"); }
            joined.Append(lines[i]);
        }
        SetText(joined.ToText());
    }

    public override FSize PreferredSize() {
        HDC dc = GetDC(window);
        HGDIOBJ wasFont = SelectObject(dc, (HGDIOBJ)(nuint)(ulong)SendMessageW(window, WmGetFont, 0u, 0));
        var wide = "Wg".ToUtf16();
        Win32.User32.Size measured;
        GetTextExtentPoint32W(dc, wide.ToPointer(), (int)wide.UnitCount(), &measured);
        SelectObject(dc, wasFont);
        ReleaseDC(window, dc);
        return Extent(120, measured.Height + 8);
    }
}

// ================================================================= list box

/// A `LISTBOX`.
public class ListPeer : ControlPeer, IListPeer {
    public ListPeer(IControlNotify owner, IContainerPeer parent) {
        base(MakeChild("LISTBOX", WindowOf(parent),
                       ChildStyle() | LbsNotify | LbsHasStrings
                                    | LbsNoIntegralHeight | WsVerticalScroll,
                       WsExClientEdge),
             owner, true);
    }

    protected override bool Notified(uint code, int id) {
        var owner = Owner();
        if (owner == null) { return false; }
        if (code == LbnSelChange) {
            ((IControlNotify)owner).OnPlatformValueChanged();
            return true;
        }
        if (code == LbnDoubleClick) {
            ((IControlNotify)owner).OnPlatformActivated();
            return true;
        }
        return false;
    }

    public void InsertItem(int index, String text) {
        SendMessageW(window, LbInsertString, (ulong)index,
                     (long)(nuint)text.ToUtf16().ToPointer());
    }

    public void RemoveItem(int index) {
        SendMessageW(window, LbDeleteString, (ulong)index, 0);
    }

    public void ClearItems() { SendMessageW(window, LbResetContent, 0u, 0); }

    public int ItemCount() { return (int)SendMessageW(window, LbGetCount, 0u, 0); }

    public void SetSelectedIndex(int index) {
        SendMessageW(window, LbSetCurSel, (ulong)index, 0);
    }

    public int GetSelectedIndex() {
        return (int)SendMessageW(window, LbGetCurSel, 0u, 0);
    }
}

// ================================================================ combo box

/// A `COMBOBOX`, either a drop-down list or one that can also be typed into.
///
/// **The height passed at creation is the *dropped* height**, not the closed
/// one: a combo box created 24 pixels tall has a list with no room in it and
/// looks broken in a way nothing about the call says. `SetBounds` here adds
/// room for the list, which is the one place this backend does not pass the
/// control layer's bounds through unchanged.
public class ComboPeer : ControlPeer, IComboPeer {
    public ComboPeer(IControlNotify owner, IContainerPeer parent) {
        base(MakeChild("COMBOBOX", WindowOf(parent),
                       ChildStyle() | CbsDropDownList | CbsHasStrings
                                    | CbsNoIntegralHeight | WsVerticalScroll, 0u),
             owner, true);
    }

    protected override bool Notified(uint code, int id) {
        var owner = Owner();
        if (owner == null) { return false; }
        if (code == CbnSelChange || code == CbnEditChange) {
            ((IControlNotify)owner).OnPlatformValueChanged();
            return true;
        }
        return false;
    }

    public void InsertItem(int index, String text) {
        SendMessageW(window, CbInsertString, (ulong)index,
                     (long)(nuint)text.ToUtf16().ToPointer());
    }

    public void RemoveItem(int index) {
        SendMessageW(window, CbDeleteString, (ulong)index, 0);
    }

    public void ClearItems() { SendMessageW(window, CbResetContent, 0u, 0); }

    public int ItemCount() { return (int)SendMessageW(window, CbGetCount, 0u, 0); }

    public void SetSelectedIndex(int index) {
        SendMessageW(window, CbSetCurSel, (ulong)index, 0);
    }

    public int GetSelectedIndex() {
        return (int)SendMessageW(window, CbGetCurSel, 0u, 0);
    }

    /// Editable or not is a creation-time style, as multiline is on an edit.
    public void SetEditable(bool editable) { }
}

// ============================================================== group box

/// **Stops a list sizing itself.** By default a `LISTBOX` rounds its height
/// down to a whole number of rows and a `COMBOBOX` its drop-down likewise, so a
/// control given 220 pixels quietly becomes 214 and every anchor measured
/// against it is then measured against a number nobody chose. The LCL sets
/// these for the same reason.
const uint LbsNoIntegralHeight = 0x0100u;
const uint CbsNoIntegralHeight = 0x0400u;

/// How much of a group box's own rectangle its caption occupies.
const int CaptionHeight = 16;

/// A `BUTTON` with `BS_GROUPBOX`: a frame with a caption, that children go
/// inside.
public class GroupPeer : ControlPeer, IGroupPeer {
    public GroupPeer(IControlNotify owner, IContainerPeer parent) {
        base(MakeChild("BUTTON", WindowOf(parent),
                       (ChildStyle() & ~WsTabStop) | BsGroupBox | WsClipChildren, 0u),
             owner, true);
    }

    public void AddChild(IControlPeer child) {
        SetParent((HWND)(void*)child.Handle(), window);
    }

    public void RemoveChild(IControlPeer child) {
        SetParent((HWND)(void*)child.Handle(), null);
    }

    /// The frame is the `BUTTON`'s to draw and the children are this peer's;
    /// see `PaintOver`.
    public override long Dispatch(uint message, ulong wParam, long lParam) {
        if (message == WmPaint) { return PaintOver(message, wParam, lParam); }
        return base.Dispatch(message, wParam, lParam);
    }

    /// **A group box has to erase itself, alone among the subclassed ones.**
    ///
    /// `BS_GROUPBOX` paints a frame and a caption and nothing else: its
    /// interior is transparent, and Windows expects whatever is behind it to
    /// show through. Nothing is behind it, because the form carries
    /// `WS_CLIPCHILDREN` and so never paints under a child -- which it must
    /// keep, since dropping it is what makes every other control flicker on
    /// resize. So the interior belonged to nobody, and after a resize it showed
    /// whatever the previous contents of that memory were.
    protected override bool ErasesBackground() { return true; }

    /// The frame costs 8 pixels a side and the caption the top of the box.
    ///
    /// Windows hands a group box its whole rectangle as a client area, so
    /// without this a child at (0, 0) is drawn across the caption. The two
    /// halves have to agree: this is how much room there is, `ClientOrigin` is
    /// where it starts, and the control layer adds the second to every child it
    /// places.
    public override FRect ClientBounds() {
        Rect r;
        GetClientRect(window, &r);
        int width = r.Right - r.Left;
        int height = r.Bottom - r.Top;
        return Area(0, 0, width - 16, height - CaptionHeight - 8);
    }

    public override FPoint ClientOrigin() { return At(8, CaptionHeight); }
}

// =================================================================== panel

/// A plain container, which Windows has no class for.
///
/// **`STATIC` with no text**, rather than a class of this library's own. A
/// registered class would want a window procedure, a background brush and a
/// name that could collide; a static control is already a window that does
/// nothing, takes children, and paints its background in the colour
/// `WM_CTLCOLORSTATIC` says -- which is exactly the whole specification of a
/// panel.
public class PanelPeer : ControlPeer, IPanelPeer {
    public PanelPeer(IControlNotify owner, IContainerPeer parent) {
        base(MakeChild("STATIC", WindowOf(parent),
                       (ChildStyle() & ~WsTabStop) | WsClipChildren, 0u),
             owner, true);
    }

    public void AddChild(IControlPeer child) {
        SetParent((HWND)(void*)child.Handle(), window);
    }

    public void RemoveChild(IControlPeer child) {
        SetParent((HWND)(void*)child.Handle(), null);
    }

    /// A panel is a container, so anything windowless on it is its to draw.
    public override long Dispatch(uint message, ulong wParam, long lParam) {
        if (message == WmPaint) { return PaintOver(message, wParam, lParam); }
        return base.Dispatch(message, wParam, lParam);
    }

    public void SetBorder(ControlBorder border) {
        long extended = Win32.User32.GetWindowLongPtrW(window, GwlExtendedStyle);
        extended = extended & ~(long)(WsExClientEdge | WsExStaticEdge);
        if (border == ControlBorder.Single)      { extended = extended | (long)WsExStaticEdge; }
        else if (border == ControlBorder.Sunken) { extended = extended | (long)WsExClientEdge; }
        Win32.User32.SetWindowLongPtrW(window, GwlExtendedStyle, extended);
        // The frame is not part of the client area, so changing it changes the
        // layout; `SWP_FRAMECHANGED` is what makes Windows recompute that.
        SetWindowPos(window, null, 0, 0, 0, 0,
                     SwpNoMove | SwpNoSize | SwpNoZOrder | SwpFrameChanged);
    }
}

// =============================================================== scroll bar

/// A `SCROLLBAR` standing on its own, rather than attached to a window.
///
/// The position arrives at the *parent* as `WM_VSCROLL` or `WM_HSCROLL` with
/// this control's handle in `LPARAM`, which is why the scroll handling is in
/// `WindowPeer` and reaches back here.
public class ScrollBarPeer : ControlPeer, IScrollBarPeer {
    public ScrollBarPeer(IControlNotify owner, IContainerPeer parent, bool vertical) {
        base(MakeChild("SCROLLBAR", WindowOf(parent),
                       ChildStyle() | (vertical ? SbsVertical : SbsHorizontal), 0u),
             owner, true);
    }

    public void SetRange(int minimum, int maximum, int pageSize) {
        ScrollInfo info;
        info.Size = (uint)sizeof(ScrollInfo);
        info.Mask = SifRange | SifPage;
        info.Minimum = minimum;
        info.Maximum = maximum;
        info.Page = (uint)pageSize;
        info.Position = 0;
        info.TrackPosition = 0;
        SetScrollInfo(window, ScrollBarControl, &info, 1);
    }

    public void SetValue(int value) {
        ScrollInfo info;
        info.Size = (uint)sizeof(ScrollInfo);
        info.Mask = SifPosition;
        info.Minimum = 0;
        info.Maximum = 0;
        info.Page = 0u;
        info.Position = value;
        info.TrackPosition = 0;
        SetScrollInfo(window, ScrollBarControl, &info, 1);
    }

    public int GetValue() {
        ScrollInfo info;
        info.Size = (uint)sizeof(ScrollInfo);
        info.Mask = SifPosition;
        info.Minimum = 0;
        info.Maximum = 0;
        info.Page = 0u;
        info.Position = 0;
        info.TrackPosition = 0;
        GetScrollInfo(window, ScrollBarControl, &info);
        return info.Position;
    }

    /// Told what the user did, by the parent that was told.
    public void Scrolled(uint action, int thumb) {
        int now = GetValue();
        if (action == SbLineUp)          { now = now - 1; }
        else if (action == SbLineDown)   { now = now + 1; }
        else if (action == SbPageUp)     { now = now - 10; }
        else if (action == SbPageDown)   { now = now + 10; }
        else if (action == SbThumbTrack || action == SbThumbPosition) { now = thumb; }
        else { return; }

        SetValue(now);
        var owner = Owner();
        if (owner != null) { ((IControlNotify)owner).OnPlatformValueChanged(); }
    }
}

#endif
