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

// The Windows backend: one peer class per native widget, and the window
// procedure that turns messages into notifications.
//
// This is `lcl/interfaces/win32` with the metaclasses taken out. The LCL puts
// every control's Windows behaviour in `class procedure`s on a `TWSxxx` type
// and keeps the per-window state in a side table -- `AllocWindowInfo`, a global
// atom, a `GetProp` on every message -- because a class procedure has no
// instance to keep it in. A peer is an object, so the state lives on it and the
// table is gone.
//
// **Two window procedures, and the reason there are two.** A form is a window
// class this library registers, so its procedure is its own from the start. A
// button is a `BUTTON`, which Windows implements and which already has one; the
// only way in is to put ours in front and call the original for everything we
// do not want. `SetWindowLongPtrW(GWLP_WNDPROC)` is that, and `CallWindowProcW`
// is how the original is reached afterwards.
//
//     Stainless has no cast between a delegate and an integer, so the two calls
//     that hand window procedures about are declared here again in the shape
//     subclassing uses them at -- returning a `WindowProcedure` rather than a
//     `long`. The same C function, declared twice, exactly as `Gtk.Signals`
//     declares `g_signal_connect_data` twice.
//
// **How a message finds its peer.** `SetPropW` attaches the peer's address to
// its window, and the procedure reads it back. The pointer is *not* retained:
// the control owns its peer and outlives every message that could arrive, and
// retaining here would make a cycle that nothing breaks -- the peer would keep
// the window alive and the window would keep the peer alive. The peer's
// destructor removes the property and destroys the window, in that order.
module Forms.Platform.Win32;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;
import Win32;
import Win32.Handles;
import Win32.Kernel32;
import Win32.User32;
import Win32.Gdi32;

#if WINDOWS

#pragma comment(lib, "user32")
#pragma comment(lib, "gdi32")

// `Point`, `Size` and `Rectangle` are each declared twice within reach: once by
// `Forms.Drawing` and once by the Win32 headers, which mean different things by
// them. An alias settles a *type* name; it does not settle a static member
// access, so `FPoint.At(...)` does not resolve where `FPoint x` does. Hence the
// three makers below, which say the qualified name once each.
using FPoint = Forms.Drawing.Point;
using FSize  = Forms.Drawing.Size;
using FRect  = Forms.Drawing.Rectangle;

FPoint At(int x, int y)            { return Forms.Drawing.Point.At(x, y); }
FSize  Extent(int width, int height) { return Forms.Drawing.Size.Of(width, height); }
FSize  NoSize()                    { return Forms.Drawing.Size.Empty; }
FRect  Area(int x, int y, int width, int height) {
    return Forms.Drawing.Rectangle.Of(x, y, width, height);
}
FRect  AreaFromEdges(int left, int top, int right, int bottom) {
    return Forms.Drawing.Rectangle.FromEdges(left, top, right, bottom);
}

extern "C" {
    void sl_fail(byte* message);

    /// `SetWindowLongPtrW` in the shape subclassing needs it: taking and
    /// answering a procedure rather than a number, because Stainless has no
    /// cast between a delegate and an integer.
    ///
    /// **This declaration shadows the numeric one** for the whole of this
    /// module, since a local declaration wins over an imported one and the two
    /// differ in their return type, which is not something overloading can
    /// tell apart. So the style bits are set through `Win32.User32`'s own
    /// spelling, written out at each of the four places that needs it.
    WindowProcedure SetWindowLongPtrW(HWND window, int index, WindowProcedure value);
}

// ============================================================== conversions

/// A `Color` as a COLORREF, which is 0x00BBGGRR -- blue in the high byte,
/// which is the one thing about GDI colours everyone gets wrong once.
public uint ToColorRef(Color colour) {
    return (uint)colour.R | ((uint)colour.G << 8) | ((uint)colour.B << 16);
}

/// The other way, dropping alpha because a COLORREF has none.
public Color FromColorRef(uint raw) {
    return Color.FromRgb((byte)(raw & 0xFFu),
                         (byte)((raw >> 8) & 0xFFu),
                         (byte)((raw >> 16) & 0xFFu));
}

/// A `Rectangle` as a Win32 `RECT`, which is edges rather than an extent.
public Rect ToRect(FRect bounds) {
    Rect r;
    r.Left = bounds.X;
    r.Top = bounds.Y;
    r.Right = bounds.X + bounds.Width;
    r.Bottom = bounds.Y + bounds.Height;
    return r;
}

public FRect FromRect(Rect r) {
    return AreaFromEdges(r.Left, r.Top, r.Right, r.Bottom);
}

/// Which modifiers are down *now*. Win32 reports them in `WPARAM` for mouse
/// messages and not at all for key ones, so asking the keyboard directly is the
/// one answer that is right for both.
public ModifierKeys CurrentModifiers() {
    var held = ModifierKeys.None;
    if (KeyDown(VkShift))   { held = held | ModifierKeys.Shift; }
    if (KeyDown(VkControl)) { held = held | ModifierKeys.Control; }
    if (KeyDown(VkMenu))    { held = held | ModifierKeys.Alt; }
    return held;
}

/// Asks for one `WM_MOUSELEAVE` for this window.
///
/// Win32 reports a mouse entering a window only by the moves it sends, and
/// reports it leaving not at all until asked -- once, per window, per leave. So
/// this is called again on every enter, which is what the `tracking` flag on a
/// peer is counting.
///
/// Here rather than in `Win32.User32` because that layer is declarations only:
/// a function with a body there would make the raw bindings need `-l user32`
/// to link, and their not needing one is a property the tests check.
public bool TrackMouseLeave(HWND window) {
    TrackMouseEvent track;
    track.Size = (uint)sizeof(TrackMouseEvent);
    track.Flags = TmeLeave;
    track.Window = window;
    track.HoverTime = 0u;
    return TrackMouseEvent(&track) != 0;
}

/// True while a virtual key is held. `GetKeyState`'s high bit, which is the
/// only bit of it that means "down"; the low bit is the toggle state and is
/// what makes a naive test read Caps Lock as Shift.
public bool KeyDown(int key) { return (GetKeyState(key) & 0x8000) != 0; }

// ================================================ attaching a peer to a window

/// The property name the peer's address hangs on. One atom's worth of
/// namespace, shared by every window this library makes.
static readonly String PeerProperty = "StainlessFormsPeer";

/// Attaches a peer to its window. The pointer is borrowed, not retained; see
/// the note at the top of this file.
void BindPeer(HWND window, ControlPeer peer) {
    SetPropW(window, PeerProperty.ToUtf16().ToPointer(), (void*)peer);
}

void UnbindPeer(HWND window) {
    RemovePropW(window, PeerProperty.ToUtf16().ToPointer());
}

/// The peer of a window, or null for a window this library did not make --
/// which every procedure here must allow for, because Windows sends messages
/// to a window before `CreateWindowExW` has returned the handle to bind.
ControlPeer? PeerOf(HWND window) {
    if (window == null) { return null; }
    var raw = GetPropW(window, PeerProperty.ToUtf16().ToPointer());
    if (raw == null) { return null; }
    return (ControlPeer)raw;
}

// ========================================================= window procedures

/// The procedure every window this library makes goes through.
///
/// **One function for every window, not one per control.** It is a module-level
/// function, so its address is a plain C function pointer with no thunk
/// anywhere; which window it is for is answered by the property, and what to do
/// is answered by the peer's own `Dispatch`.
long StainlessProc(HWND window, uint message, ulong wParam, long lParam) {
    var peer = PeerOf(window);
    if (peer == null) { return DefWindowProcW(window, message, wParam, lParam); }
    return ((ControlPeer)peer).Dispatch(message, wParam, lParam);
}

// ================================================================ the base

/// What every Windows peer has: a window, the control it reports to, and the
/// procedure it displaced.
///
/// **The control is held weakly.** A control owns its peer and a peer that
/// owned its control back would make a cycle ARC cannot break, so the window
/// would outlive the program. Weak costs a check on every notification, which
/// is what the local-and-test in each handler below is doing.
public class ControlPeer : IControlPeer {
    protected HWND            window;
    protected weak IControlNotify? target;
    /// The procedure this peer put itself in front of. For a window class this
    /// library registered there is nothing in front of, and `subclassed` says
    /// which case this is.
    protected WindowProcedure  displaced;
    protected bool             subclassed;
    /// The brush `WM_CTLCOLOR*` answers with, owned and deleted by this peer.
    /// Null until a background colour is set, because until then the system's
    /// own answer is the right one.
    protected HBRUSH           backBrush;
    protected Color            backColour;
    protected Color            foreColour;
    protected bool             backSet;
    protected bool             foreSet;
    /// Whether a `WM_MOUSELEAVE` has been asked for. Win32 gives one leave per
    /// request, so entering has to ask again each time.
    protected bool             tracking;
    protected bool             inside;
    protected bool             destroyed;

    protected ControlPeer(HWND made, IControlNotify owner, bool subclass) {
        window = made;
        target = owner;
        subclassed = subclass;
        backBrush = null;
        backColour = Colors.White;
        foreColour = Colors.Black;
        backSet = false;
        foreSet = false;
        tracking = false;
        inside = false;
        destroyed = false;

        BindPeer(made, this);
        if (subclass) {
            displaced = SetWindowLongPtrW(made, GwlpWindowProc, StainlessProc);
        } else {
            displaced = StainlessProc;
        }
    }

    ~ControlPeer() { Destroy(); }

    /// Hands a message to the procedure this peer displaced: the system
    /// control's own for a subclassed widget, `DefWindowProcW` for a class of
    /// ours.
    protected long Inherited(uint message, ulong wParam, long lParam) {
        if (subclassed) {
            return CallWindowProcW(displaced, window, message, wParam, lParam);
        }
        return DefWindowProcW(window, message, wParam, lParam);
    }

    /// The control this peer reports to, or null if it has been destroyed --
    /// which a message arriving during teardown genuinely can see.
    protected IControlNotify? Owner() {
        IControlNotify? held = target;
        return held;
    }

    // ------------------------------------------------------- the dispatch

    /// Turns one Windows message into whatever it means.
    ///
    /// Virtual, so a peer with messages of its own -- a window's close, a list
    /// box's selection -- adds them and calls `base` for the rest. Everything
    /// here is common to every window: the mouse, the keyboard, focus, paint
    /// and colour.
    public virtual long Dispatch(uint message, ulong wParam, long lParam) {
        IControlNotify? owner = target;

        if (message == WmNcDestroy) {
            // The last message a window ever gets, and the only safe place to
            // let go of the binding: messages can still arrive before it.
            UnbindPeer(window);
            destroyed = true;
            return Inherited(message, wParam, lParam);
        }

        if (owner == null) { return Inherited(message, wParam, lParam); }
        var control = (IControlNotify)owner;

        // **Erase, rather than claiming to have.** A window of a class this
        // library registered has a null background brush, so if nothing fills
        // the client area nothing ever does: the window shows whatever memory
        // held, and every region a moved control vacates keeps the old picture.
        // Both were one bug.
        //
        // Only for our own classes. A subclassed system control is erased by
        // the procedure it displaced, using the brush its parent hands back
        // from `WM_CTLCOLOR*` -- filling over that would cost every `EDIT` and
        // `LISTBOX` its native appearance.
        //
        // The form carries `WS_CLIPCHILDREN`, so this paints only the parts no
        // child covers, which is what keeps a resize from flickering.
        if (message == WmEraseBackground && ErasesBackground()) {
            HDC dc = (HDC)(void*)(nuint)wParam;
            Rect client;
            GetClientRect(window, &client);
            FillRect(dc, &client, BackgroundBrush());
            return 1;
        }

        // **Notified, then passed on.** Reporting a message is not the same as
        // consuming it: a drag inside an `EDIT` is a run of `WM_MOUSEMOVE`
        // between the button going down and coming up, so swallowing the moves
        // left clicking able to place the caret and dragging unable to select
        // anything. Every one of these ends at the procedure this peer
        // displaced, which is what keeps the native behaviour intact.
        if (message == WmMouseMove) {
            if (!inside) {
                inside = true;
                control.OnPlatformMouseEnter();
            }
            if (!tracking) {
                tracking = TrackMouseLeave(window);
            }
            control.OnPlatformMouseMove(PointOfParam(lParam), CurrentModifiers());
            return Inherited(message, wParam, lParam);
        }

        if (message == WmMouseLeave) {
            tracking = false;
            inside = false;
            control.OnPlatformMouseLeave();
            return Inherited(message, wParam, lParam);
        }

        if (message == WmLeftButtonDown) {
            control.OnPlatformMouseDown(MouseButton.Left, PointOfParam(lParam), CurrentModifiers());
            return Inherited(message, wParam, lParam);
        }
        if (message == WmLeftButtonUp) {
            control.OnPlatformMouseUp(MouseButton.Left, PointOfParam(lParam), CurrentModifiers());
            return Inherited(message, wParam, lParam);
        }
        if (message == WmRightButtonDown) {
            control.OnPlatformMouseDown(MouseButton.Right, PointOfParam(lParam), CurrentModifiers());
            return Inherited(message, wParam, lParam);
        }
        if (message == WmRightButtonUp) {
            control.OnPlatformMouseUp(MouseButton.Right, PointOfParam(lParam), CurrentModifiers());
            return Inherited(message, wParam, lParam);
        }
        if (message == WmMiddleButtonDown) {
            control.OnPlatformMouseDown(MouseButton.Middle, PointOfParam(lParam), CurrentModifiers());
            return Inherited(message, wParam, lParam);
        }
        if (message == WmMiddleButtonUp) {
            control.OnPlatformMouseUp(MouseButton.Middle, PointOfParam(lParam), CurrentModifiers());
            return Inherited(message, wParam, lParam);
        }

        if (message == WmMouseWheel) {
            // The wheel's position is in *screen* coordinates, unlike every
            // other mouse message, so it has to be brought back.
            int notches = (int)(short)((wParam >> 16) & 0xFFFFu);
            Win32.User32.Point screen;
            screen.X = (int)(short)(lParam & 0xFFFF);
            screen.Y = (int)(short)((lParam >> 16) & 0xFFFF);
            ScreenToClient(window, &screen);
            control.OnPlatformMouseWheel(notches, At(screen.X, screen.Y), CurrentModifiers());
            // Likewise: a multiline text box and a list scroll themselves, and
            // only if the wheel reaches them.
            return Inherited(message, wParam, lParam);
        }

        if (message == WmKeyDown || message == WmSysKeyDown) {
            control.OnPlatformKeyDown((Key)(int)wParam, CurrentModifiers());
            return Inherited(message, wParam, lParam);
        }
        if (message == WmKeyUp || message == WmSysKeyUp) {
            control.OnPlatformKeyUp((Key)(int)wParam, CurrentModifiers());
            return Inherited(message, wParam, lParam);
        }
        if (message == WmChar) {
            control.OnPlatformKeyPress((char)(uint)wParam);
            return Inherited(message, wParam, lParam);
        }

        if (message == WmSetFocus)  { control.OnPlatformGotFocus();  return Inherited(message, wParam, lParam); }
        if (message == WmKillFocus) { control.OnPlatformLostFocus(); return Inherited(message, wParam, lParam); }

        // **Not the sizes these messages carry.** `WM_SIZE` reports the new
        // *client* extent and `WM_MOVE` the client origin, but a control's
        // `Bounds` is its *window* rectangle -- the two differ by whatever the
        // frame costs, which is 2 pixels a side for anything with
        // `WS_EX_CLIENTEDGE`. Feeding the client size back in made every
        // resize shrink a bordered control by 4 and shift it by 2, compounding
        // once per resize, while a borderless one next to it stayed put. So the
        // rectangle is asked for rather than taken from the message.
        if (message == WmSize) {
            control.OnPlatformResized(BoundsInParent().Extent);
            return Inherited(message, wParam, lParam);
        }

        if (message == WmMove) {
            control.OnPlatformMoved(BoundsInParent().Location);
            return Inherited(message, wParam, lParam);
        }

        // A child control told its parent something happened to it. Win32
        // reports a button's click, an edit's change and a list's selection
        // this way -- to the *parent*, not the control -- so every container
        // routes it back down to the peer it names, and each peer says what
        // that notification code means to it.
        if (message == WmCommand) {
            var child = PeerOf((HWND)(void*)(nuint)lParam);
            if (child != null) {
                uint code = (uint)((wParam >> 16) & 0xFFFFu);
                if (((ControlPeer)child).Notified(code)) { return 0; }
            }
        }

        // A child control asked its parent to colour it. Answering with this
        // peer's own brush is how a coloured background reaches a system
        // control, which has no other way to be told.
        if (message == WmCtlColorStatic || message == WmCtlColorEdit
            || message == WmCtlColorButton || message == WmCtlColorListBox) {
            var child = PeerOf((HWND)(void*)(nuint)lParam);
            if (child != null) {
                var painted = (ControlPeer)child;
                return painted.AnswerColour((HDC)(void*)(nuint)wParam);
            }
        }

        return Inherited(message, wParam, lParam);
    }

    /// Whether this peer fills its own background.
    ///
    /// True for a window class this library registered, since nothing else
    /// would. False for a subclassed system control, whose own procedure erases
    /// it with the brush its parent hands back from `WM_CTLCOLOR*` -- painting
    /// over that would cost it its native appearance.
    ///
    /// The exception is a widget that paints part of itself and leaves the
    /// rest to its parent; see `GroupPeer`.
    protected virtual bool ErasesBackground() { return !subclassed; }

    /// Where this control is, in the coordinates its `Bounds` are expressed in:
    /// the parent's client area for a child, and the screen for a top-level
    /// window -- which is what `Form.Location` means, as it does in C#.
    protected FRect BoundsInParent() {
        Rect frame;
        GetWindowRect(window, &frame);
        int width = frame.Right - frame.Left;
        int height = frame.Bottom - frame.Top;

        HWND parent = GetParent(window);
        if (parent == null) { return Area(frame.Left, frame.Top, width, height); }

        Win32.User32.Point corner;
        corner.X = frame.Left;
        corner.Y = frame.Top;
        ScreenToClient(parent, &corner);
        return Area(corner.X, corner.Y, width, height);
    }

    /// The brush this control's background is painted with.
    ///
    /// `backBrush` is made by `SetBackColor`, which every control gets during
    /// `AttachPeer`; the system brush is the fallback for the window that is
    /// asked to erase before that has happened, which a form is.
    protected HBRUSH BackgroundBrush() {
        if (backBrush != null) { return backBrush; }
        return GetSysColorBrush(ColorBtnFace);
    }

    /// What one of this control's own notification codes means.
    ///
    /// Answering true says the message is dealt with. The base understands
    /// none of them, because the codes overlap -- `BN_CLICKED` is 0 and so is
    /// nothing else only because a button is what received it -- and only the
    /// peer for a given control knows which numbering it is in.
    protected virtual bool Notified(uint code) { return false; }

    /// What this control wants to be drawn in, as `WM_CTLCOLOR*` wants it: the
    /// device context set up, and a brush returned for the background.
    long AnswerColour(HDC dc) {
        if (foreSet) { SetTextColor(dc, ToColorRef(foreColour)); }
        if (!backSet) { return 0; }
        SetBkColor(dc, ToColorRef(backColour));
        return (long)(nuint)(void*)backBrush;
    }

    /// The client coordinates packed into an `LPARAM`, both signed -- a drag
    /// can leave a window to the left, and an unsigned read makes that a very
    /// large positive number.
    protected FPoint PointOfParam(long lParam) {
        return At((int)(short)(lParam & 0xFFFF), (int)(short)((lParam >> 16) & 0xFFFF));
    }

    // ------------------------------------------------------- IControlPeer

    public void SetBounds(FRect bounds) {
        MoveWindow(window, bounds.X, bounds.Y, bounds.Width, bounds.Height, 1);
    }

    public void SetVisible(bool visible) {
        ShowWindow(window, visible ? SwShowNoActivate : SwHide);
    }

    public void SetEnabled(bool enabled) { EnableWindow(window, enabled ? 1 : 0); }

    public void SetText(String text) {
        SetWindowTextW(window, text.ToUtf16().ToPointer());
    }

    public String GetText() {
        int units = GetWindowTextLengthW(window);
        if (units <= 0) { return ""; }
        var buffer = new char16[(nuint)units + 1u];
        int got = GetWindowTextW(window, &buffer[0u], units + 1);
        if (got <= 0) { return ""; }
        return Text.FromUtf16(&buffer[0u], (nuint)got);
    }

    public void SetFont(Font font) {
        // `WM_SETFONT` does not take ownership, so the `Font` object must
        // outlive the control -- which it does, because the control holds it.
        SendMessageW(window, WmSetFont, (ulong)font.Resource().Handle(), 1);
    }

    public void SetForeColor(Color colour) {
        foreColour = colour;
        foreSet = true;
        Invalidate();
    }

    public void SetBackColor(Color colour) {
        backColour = colour;
        backSet = true;
        if (backBrush != null) { DeleteObject((HGDIOBJ)(void*)backBrush); }
        backBrush = CreateSolidBrush(ToColorRef(colour));
        Invalidate();
    }

    public void Invalidate() { InvalidateRect(window, null, 1); }
    public void Update()     { UpdateWindow(window); }

    public void Focus()      { SetFocus(window); }
    public bool HasFocus()   { return GetFocus() == window; }

    public virtual FRect ClientBounds() {
        Rect r;
        GetClientRect(window, &r);
        // `GetClientRect` already answers at the origin; saying so explicitly
        // is what keeps a peer that overrides this honest about the contract.
        return Area(0, 0, r.Right - r.Left, r.Bottom - r.Top);
    }

    /// Zero, because a child window's position is already measured from its
    /// parent's client origin. Only a widget whose own frame eats into that
    /// space overrides this.
    public virtual FPoint ClientOrigin() { return At(0, 0); }

    /// What Windows thinks this control should be. The base has no opinion --
    /// only a control that can measure its own content does, and each of those
    /// overrides this.
    public virtual FSize PreferredSize() { return NoSize(); }

    public nuint Handle() { return (nuint)(void*)window; }

    public void Destroy() {
        if (destroyed) { return; }
        destroyed = true;
        if (backBrush != null) {
            DeleteObject((HGDIOBJ)(void*)backBrush);
            backBrush = null;
        }
        if (window != null) {
            UnbindPeer(window);
            DestroyWindow(window);
            window = null;
        }
    }

    /// The window, for a peer that needs it and for the widget set that makes
    /// children inside it.
    public HWND Window() { return window; }
}

#endif
