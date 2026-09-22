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

// The GTK backend: what a peer is here, and the conversions every peer needs.
//
// **This is the second implementation of `Forms.Platform`, and the first one
// was Win32.** That matters more than it sounds: a seam with one
// implementation has quietly stopped being a seam, and the only way to find
// out whether `IControlPeer` describes a control or describes a window handle
// is to write the other side of it. Where the answer was "a window handle",
// the comment saying so is left in place rather than tidied away.
//
// **Three things GTK does not do the way Win32 does**, and they shape
// everything below:
//
//   - **There is no absolute placement.** Every GTK container computes its
//     own layout. `forms/` has computed one already, in pixels, so every
//     container peer's children go into a `GtkFixed` -- the one container that
//     is told rather than asked. The LCL's GTK widgetset does the same.
//   - **A widget is not a window.** A `GtkButton` has no `GdkWindow` of its
//     own, so there is nothing to set a cursor on until it is realised and
//     nothing to hand a drawing context to at all. What Win32 gets from the
//     platform for nothing -- clipping, a coordinate space, a place to put a
//     cursor -- is arranged here.
//   - **Colour and font are CSS.** There is no `WM_CTLCOLOR` and no
//     `WM_SETFONT`: a widget carries a style provider, and setting a
//     foreground colour means rewriting a stylesheet and re-adding it. One
//     provider per peer, made the first time anything asks.
//
// **One widget behind four controls.** A list box, a checked list, a tree and
// a details list are all a `GtkTreeView` over a model. That is in `Lists.sl`,
// and it is the strongest evidence the seam is about controls: four interfaces
// that Win32 answers with four window classes, GTK answers with one widget and
// a column layout, and neither backend had to change the interface.
module Forms.Platform.Gtk;

import Standard.Collections;
import Standard.Text;
import Standard.Console;
import Forms.Drawing;
import Forms.Platform;
#if UNIX
import Gtk.GLib;
import Gtk.GObject;
import Gtk.Gdk;
import Gtk.Api;
import Gtk.Cairo;
import Gtk.Signals;
import Gtk.Events;

// `Point`, `Size` and `Rectangle` mean one thing to `Forms.Drawing` and
// another to GDK, and both are in scope here. An alias settles a type name; it
// does not settle a static member access, so the three makers below say the
// qualified name once each -- exactly as the Win32 backend does, for the same
// reason.
using FPoint = Forms.Drawing.Point;
using FSize  = Forms.Drawing.Size;
using FRect  = Forms.Drawing.Rectangle;

public FPoint At(int x, int y) => Forms.Drawing.Point.At(x, y);
public FSize  Extent(int width, int height) => Forms.Drawing.Size.Of(width, height);
public FSize  NoSize() => Forms.Drawing.Size.Empty;
public FRect  Area(int x, int y, int width, int height)
{
    return Forms.Drawing.Rectangle.Of(x, y, width, height);
}

extern "C"
{
    void sl_fail(byte* message);
}

/// What a control that has no GTK peer yet does.
///
/// **Loud rather than empty.** A `CreateToolBar` that answered with a peer
/// accepting every call would give a program a toolbar-shaped hole and no
/// sign of one; this stops at the first call and says which control it was.
/// The list of names this is called with is the list of what is left to do,
/// and it lives in `WidgetSet.sl` where a reader will find it.
public void NotYet(String what)
{
    sl_fail(("the GTK backend has no " + what + " peer yet").ToPointer());
}

// ==================================================== a warning about signals
//
// **A handler's C shape has to match what the signal emits, and nothing
// checks.** `Gtk.Signals` connects handlers that take a sender and user data;
// `Gtk.Events` connects handlers that take a sender, one pointer and user
// data. A signal carrying more than that -- `switch-page` carries a page and
// a page number, `row-activated` a path and a column -- delivers the user data
// in a register the handler is not reading, so the boxed closure is read out
// of whatever was there instead.
//
// That is a segfault at the first tab added, and it is what happened. It is
// worth stating here because the failure is nothing like its cause: the code
// reads correctly, the compiler is happy, the signal name is right, and the
// program dies somewhere else entirely. **Check the signal's signature in the
// GTK documentation before connecting to it**, and where it does not fit, find
// one that says the same thing and does -- `notify::page` for the first, a
// double click for the second.

// ================================================================= timers

/// What a repeating timer runs: true to stay registered, false to stop.
public closure bool Ticker();

/// A closure with an address, since a GLib source's `user_data` is one pointer
/// and a closure is two words. The same arrangement `Gtk.Signals` uses, and
/// for the same reason.
class BoxedTicker
{
    public Ticker Body;
    public BoxedTicker(Ticker body) => Body = body;
}

/// The C entry point, one for every timer rather than one per timer: a
/// module-level function, so its address is a plain C function pointer.
gboolean RunTicker(gpointer data)
{
    var boxed = (BoxedTicker)data;
    return boxed.Body() ? 1 : 0;
}

void ForgetTicker(gpointer data) => sl_release(data);

extern "C"
{
    void sl_retain(gpointer pointer);
    void sl_release(gpointer pointer);
}

/// Runs `body` every `milliseconds` until it answers false, and answers the
/// source id `g_source_remove` takes.
///
/// **Two things use this and they are not both timers.** `TTimer` is one; an
/// indeterminate progress bar is the other, because a GTK bar with no value
/// does not move unless something keeps pulsing it.
public gulong Tick(int milliseconds, Ticker body)
{
    var boxed = new BoxedTicker(body);
    sl_retain((gpointer)boxed);

    return (gulong)g_timeout_add_full(G_PRIORITY_DEFAULT, (guint)milliseconds,
                                      RunTicker, (gpointer)boxed, ForgetTicker);
}

// ================================================================ colours

/// A `Color` as CSS writes one. Alpha is dropped: every colour the seam
/// carries is opaque, and `rgba()` would only invite one that is not.
public String ToCss(Color colour)
{
    return "#" + Hex2(colour.R) + Hex2(colour.G) + Hex2(colour.B);
}

String Hex2(byte value)
{
    var digits = "0123456789abcdef";
    return digits.Substring((nuint)(value >> 4), 1u) +
           digits.Substring((nuint)(value & 0x0Fu), 1u);
}

/// A `GdkRGBA` as a `Color`, which is where a colour chooser's answer comes
/// back from. The components are 0.0 to 1.0 and are rounded rather than
/// truncated, so that 1.0 is 255 and not 254.
public Color FromRgba(GdkRGBA colour)
{
    return Color.FromRgb(Component(colour.Red), Component(colour.Green),
                         Component(colour.Blue));
}

byte Component(double value)
{
    double scaled = value * 255.0 + 0.5;
    if (scaled < 0.0)
        return 0u;
    if (scaled > 255.0)
        return 255u;
    return (byte)(int)scaled;
}

public GdkRGBA ToRgba(Color colour)
{
    GdkRGBA rgba;
    rgba.Red   = (double)(int)colour.R / 255.0;
    rgba.Green = (double)(int)colour.G / 255.0;
    rgba.Blue  = (double)(int)colour.B / 255.0;
    rgba.Alpha = 1.0;
    return rgba;
}

// ================================================================== fonts

/// A `Font` as the CSS declarations that describe it.
///
/// **In points, because the seam is in points** and CSS understands `pt`
/// directly -- which is the one place GTK is easier than Win32, where a point
/// size has to be turned into logical units against the screen's DPI first.
public String FontCss(Font font)
{
    var css = "font-family: \"" + font.Family + "\"; font-size: " +
              Text.FromInteger((long)font.Size) + "pt;";

    if (font.Bold)
        css = css + " font-weight: bold;";
    if (font.Italic)
        css = css + " font-style: italic;";

    // One declaration takes both, and a font that is neither must still say
    // so: a provider is replaced wholesale, so anything left out reverts to
    // the theme's rather than to the last value set.
    if (font.Underline && font.Strikeout)
    {
        css = css + " text-decoration: underline line-through;";
    }
    else if (font.Underline)
    {
        css = css + " text-decoration: underline;";
    }
    else if (font.Strikeout)
    {
        css = css + " text-decoration: line-through;";
    }
    return css;
}

/// The same font as Pango writes one -- `"Sans Bold Italic 10"` -- which is
/// what a font chooser answers with and what cairo's toy text API takes.
public String PangoName(Font font)
{
    var name = font.Family;
    if (font.Bold)
        name = name + " Bold";
    if (font.Italic)
        name = name + " Italic";
    return name + " " + Text.FromInteger((long)font.Size);
}

// ================================================================ cursors

/// The CSS cursor name for one of the seam's shapes.
///
/// Names rather than `GdkCursorType`, which is deprecated and whose members do
/// not all have a theme behind them. A name the theme does not know answers
/// null, and a null cursor means "inherit the parent's" -- which is a
/// reasonable thing for an unknown shape to do and is why there is no test
/// here for one.
public String CursorName(CursorKind shape)
{
    if (shape == CursorKind.Hand)
        return "pointer";
    if (shape == CursorKind.Text)
        return "text";
    if (shape == CursorKind.Wait)
        return "wait";
    if (shape == CursorKind.Cross)
        return "crosshair";
    if (shape == CursorKind.SizeWestEast)
        return "ew-resize";
    if (shape == CursorKind.SizeNorthSouth)
        return "ns-resize";
    if (shape == CursorKind.SizeAll)
        return "move";
    if (shape == CursorKind.No)
        return "not-allowed";
    return "default";
}

// ================================================================== input

/// Which modifiers an event carries.
///
/// Read from the event rather than from the keyboard, which is the opposite of
/// what the Win32 backend does and is the better answer: GDK reports the state
/// as it was when the event happened, so a handler that runs late still sees
/// what the user was holding.
public ModifierKeys ModifiersOf(GdkEvent* event)
{
    guint state = 0u;
    gdk_event_get_state(event, &state);

    var held = ModifierKeys.None;
    if ((state & GDK_SHIFT_MASK) != 0u)
        held = held | ModifierKeys.Shift;
    if ((state & GDK_CONTROL_MASK) != 0u)
        held = held | ModifierKeys.Control;
    if ((state & GDK_MOD1_MASK) != 0u)
        held = held | ModifierKeys.Alt;
    return held;
}

/// Which button an event carries. GDK numbers from one and has more than
/// three; anything past the third is `None`, which is what a control that
/// only knows about three should be told.
public MouseButton ButtonOf(GdkEvent* event)
{
    guint which = 0u;
    if (gdk_event_get_button(event, &which) == 0)
        return MouseButton.None;
    if (which == 1u)
        return MouseButton.Left;
    if (which == 2u)
        return MouseButton.Middle;
    if (which == 3u)
        return MouseButton.Right;
    return MouseButton.None;
}

/// The largest whole number not above `value`, which a cast is not for a
/// negative one.
int FloorToInt(gdouble value)
{
    int whole = (int)value;
    if ((gdouble)whole > value)
        whole--;
    return whole;
}

/// A key event as one of the seam's keys.
///
/// **The seam numbers keys the Win32 way**, which it says so in its own
/// comment: one backend has to own the numbering and Windows' is the one with
/// a name for everything. So this is the mapping that comment promised.
///
/// **The key, not the character.** A keyval says what the keystroke typed, so
/// Shift+1 is `!` and Shift+Tab is `ISO_Left_Tab`; Windows names the key, so
/// both are the unshifted key. The keycode is looked up again with nothing
/// held but Num Lock, which is what makes the answer the key's.
public Key KeyOf(GdkEvent* event)
{
    guint keyval = 0u;
    gdk_event_get_keyval(event, &keyval);

    guint16 keycode = 0u;
    gpointer keymap = gdk_keymap_get_for_display(gdk_display_get_default());
    if (keymap == null || gdk_event_get_keycode(event, &keycode) == 0)
        return KeyOfKeyval(keyval);

    guint state = 0u;
    gdk_event_get_state(event, &state);
    guint numLock = state & GDK_MOD2_MASK;

    guint plain = 0u;
    if (gdk_keymap_translate_keyboard_state(keymap, (guint)keycode, numLock, 0,
                                            &plain, null, null, null) != 0)
    {
        var key = KeyOfKeyval(plain);
        if (key != Key.None)
            return key;
    }

    // A layout whose digits are shifted, as French puts them, still has the
    // digit on the key.
    guint shifted = 0u;
    if (gdk_keymap_translate_keyboard_state(keymap, (guint)keycode,
                                            numLock | GDK_SHIFT_MASK, 0,
                                            &shifted, null, null, null) != 0
        && shifted >= 0x30u && shifted <= 0x39u)
    {
        return (Key)(int)shifted;
    }
    return KeyOfKeyval(keyval);
}

/// Whether a key press is a shortcut rather than typing: Control or Alt held,
/// and not used up in choosing the character.
///
/// Windows reports Ctrl+C as the control code 3 and Alt+C as a system
/// character, and neither reaches a text control as a C. A layout that types
/// a character through one of the two has consumed it, and that character is
/// typed.
public bool IsShortcut(GdkEvent* event)
{
    guint state = 0u;
    gdk_event_get_state(event, &state);
    guint held = state & (GDK_CONTROL_MASK | GDK_MOD1_MASK);
    if (held == 0u)
        return false;

    guint16 keycode = 0u;
    gpointer keymap = gdk_keymap_get_for_display(gdk_display_get_default());
    if (keymap == null || gdk_event_get_keycode(event, &keycode) == 0)
        return true;

    guint consumed = 0u;
    gdk_keymap_translate_keyboard_state(keymap, (guint)keycode, state, 0,
                                        null, null, null, &consumed);
    return (held & ~consumed) != 0u;
}

/// A keyval as one of the seam's keys, or `None` for one Windows has no key
/// for.
///
/// GDK's keyval for an ASCII letter *is* its character code, so `a` is 0x61
/// and `Key.A` is 65, and folding case is the whole of the conversion. The
/// digits, the function keys and the keypad digits are consecutive in both
/// numberings.
public Key KeyOfKeyval(guint keyval)
{
    if (keyval >= 0x61u && keyval <= 0x7Au)
        return (Key)(int)(keyval - 0x20u);
    if (keyval >= 0x41u && keyval <= 0x5Au)
        return (Key)(int)keyval;
    if (keyval >= 0x30u && keyval <= 0x39u)
        return (Key)(int)keyval;
    if (keyval >= GDK_KEY_F1 && keyval <= GDK_KEY_F1 + 11u)
        return (Key)(int)((keyval - GDK_KEY_F1) + 112u);
    // `VK_NUMPAD0` is 96.
    if (keyval >= GDK_KEY_KP_0 && keyval <= GDK_KEY_KP_9)
        return (Key)(int)((keyval - GDK_KEY_KP_0) + 96u);

    switch (keyval)
    {
        case GDK_KEY_space:
            return Key.Space;
        case GDK_KEY_BackSpace:
            return Key.Backspace;
        case GDK_KEY_Tab:
        case GDK_KEY_ISO_Left_Tab:
            return Key.Tab;
        case GDK_KEY_Return:
        case GDK_KEY_KP_Enter:
            return Key.Enter;
        case GDK_KEY_Escape:
            return Key.Escape;
        case GDK_KEY_Delete:
        case GDK_KEY_KP_Delete:
            return Key.Delete;
        case GDK_KEY_Insert:
        case GDK_KEY_KP_Insert:
            return Key.Insert;
        case GDK_KEY_Home:
        case GDK_KEY_KP_Home:
            return Key.Home;
        case GDK_KEY_End:
        case GDK_KEY_KP_End:
            return Key.End;
        case GDK_KEY_Left:
        case GDK_KEY_KP_Left:
            return Key.Left;
        case GDK_KEY_Up:
        case GDK_KEY_KP_Up:
            return Key.Up;
        case GDK_KEY_Right:
        case GDK_KEY_KP_Right:
            return Key.Right;
        case GDK_KEY_Down:
        case GDK_KEY_KP_Down:
            return Key.Down;
        case GDK_KEY_Page_Up:
        case GDK_KEY_KP_Page_Up:
            return Key.PageUp;
        case GDK_KEY_Page_Down:
        case GDK_KEY_KP_Page_Down:
            return Key.PageDown;
        case GDK_KEY_Shift_L:
        case GDK_KEY_Shift_R:
            return Key.Shift;
        case GDK_KEY_Control_L:
        case GDK_KEY_Control_R:
            return Key.Control;
        // AltGr is the right Alt key, and Windows calls it that.
        case GDK_KEY_Alt_L:
        case GDK_KEY_Alt_R:
        case GDK_KEY_Meta_L:
        case GDK_KEY_Meta_R:
        case GDK_KEY_ISO_Level3_Shift:
            return Key.Alt;
        case GDK_KEY_Pause:
            return Key.Pause;
        case GDK_KEY_Caps_Lock:
            return Key.CapsLock;
    }

    // Keys Windows numbers and the seam has not named yet.
    switch (keyval)
    {
        case GDK_KEY_Clear:
        case GDK_KEY_KP_Begin:
            return (Key)12;
        case GDK_KEY_Print:
            return (Key)44;
        case GDK_KEY_Super_L:
            return (Key)91;
        case GDK_KEY_Super_R:
            return (Key)92;
        case GDK_KEY_Menu:
            return (Key)93;
        case GDK_KEY_KP_Multiply:
            return (Key)106;
        case GDK_KEY_KP_Add:
            return (Key)107;
        case GDK_KEY_KP_Separator:
            return (Key)108;
        case GDK_KEY_KP_Subtract:
            return (Key)109;
        case GDK_KEY_KP_Decimal:
            return (Key)110;
        case GDK_KEY_KP_Divide:
            return (Key)111;
        case GDK_KEY_Num_Lock:
            return (Key)144;
        case GDK_KEY_Scroll_Lock:
            return (Key)145;
        // The punctuation keys of a US layout, `VK_OEM_*`.
        case 0x3Bu:
            return (Key)186;
        case 0x3Du:
            return (Key)187;
        case 0x2Cu:
            return (Key)188;
        case 0x2Du:
            return (Key)189;
        case 0x2Eu:
            return (Key)190;
        case 0x2Fu:
            return (Key)191;
        case 0x60u:
            return (Key)192;
        case 0x5Bu:
            return (Key)219;
        case 0x5Cu:
            return (Key)220;
        case 0x5Du:
            return (Key)221;
        case 0x27u:
            return (Key)222;
    }
    return Key.None;
}

// ============================================================== the relay

/// What a signal handler holds in place of the peer it reports for.
///
/// **A handler MUST NOT capture its peer.** GTK holds a handler for as long as
/// the widget lives and the peer holds the widget, so a closure over the peer
/// closes a loop that ARC cannot see into: neither is ever freed, and a form
/// that was dropped keeps its window, its timers and its handlers. A handler
/// holds one of these instead, which answers null once the peer has gone.
public class PeerRelay
{
    weak GtkPeer? _peer;
    weak IControlNotify? _target;

    public PeerRelay(GtkPeer peer, IControlNotify? owner)
    {
        _peer = peer;
        _target = owner;
    }

    /// The control the peer reports to, or null once it has gone.
    public IControlNotify? Owner
    {
        get
        {
            IControlNotify? held = _target;
            return held;
        }
    }

    public GtkPeer? Peer
    {
        get
        {
            GtkPeer? held = _peer;
            return held;
        }
    }
}

/// A handler for a signal that carries nothing, given the peer it is for.
public closure void PeerSignal(GtkPeer peer);

/// A handler for a signal that carries one pointer and answers.
public closure bool PeerEvent(GtkPeer peer, gpointer carried);

/// The key a peer's widgets carry, naming the widget that peer reports the
/// mouse in. How an event is traced back to the peer it belongs to.
static readonly String PeerMark = "forms-peer";

// ============================================================== the peer

/// What every GTK control's peer is.
///
/// **`widget` is what the parent places and `inner` is what does the work**,
/// and they differ whenever a control needs a scrolled window around it: a
/// list's `widget` is the `GtkScrolledWindow` that goes into the parent's
/// `GtkFixed`, and its `inner` is the `GtkTreeView` that carries the signals,
/// the style and the text. For everything else the two are the same widget,
/// and saying so once here is what keeps every subclass from having to ask.
public class GtkPeer : IControlPeer
{
    /// The widget the parent places. Owned: one reference, sunk at
    /// construction and dropped by `Destroy`.
    protected GtkWidget* widget;
    /// The widget that carries the text, the signals and the style.
    protected GtkWidget* inner;

    /// The `GtkFixed` this peer was put into, so that `SetBounds` has
    /// something to move it within. Null until a container adopts it, which a
    /// top-level window never is.
    protected GtkWidget* placedIn;

    /// Whether `placedIn` is a `GtkLayout` rather than a `GtkFixed`. The two
    /// take different calls to move a child and each rejects the other's.
    protected bool placedInLayout;

    protected weak IControlNotify? target;

    /// Where the control layer last put it. Kept because GTK has no
    /// `GetWindowRect` for a child of a `GtkFixed` -- the position is the
    /// container's business and is not readable from the child.
    protected FRect bounds;

    /// The style provider this peer owns, made the first time a colour or a
    /// font is set and replaced wholesale each time after. Null until then,
    /// because until then the theme's answer is the right one.
    protected gpointer styling;
    protected String foreCss;
    protected String backCss;
    protected String fontCss;

    protected bool destroyed;
    protected CursorKind shape;

    /// True while the *program* is setting a value, so that the signal GTK
    /// raises for it is not reported back as the user's doing. The seam is
    /// explicit that `OnPlatformValueChanged` is never raised for a change the
    /// program made, and this is what keeps that true. Raised by `Quietly`.
    protected bool echoing;

    /// What this peer's handlers hold instead of the peer. See `PeerRelay`.
    PeerRelay _relay;

    /// Whether this peer holds the mouse, in which case every mouse event is
    /// its to report, as it is for a window that has called `SetCapture`.
    bool _captured;

    /// Whether the `realize` handler that applies the cursor is connected.
    bool _cursorWatched;

    public GtkPeer(GtkWidget* made, IControlNotify? owner)
    {
        widget = (GtkWidget*)g_object_ref_sink((gpointer)made);
        inner = made;
        placedIn = null;
        placedInLayout = false;
        target = owner;
        bounds = Area(0, 0, 0, 0);
        styling = null;
        foreCss = "";
        backCss = "";
        fontCss = "";
        destroyed = false;
        shape = CursorKind.Default;
        echoing = false;
        _captured = false;
        _cursorWatched = false;
        _relay = new PeerRelay(this, owner);
    }

    /// Makes a change the program asked for with the echo guard up, so that
    /// the signal GTK raises for it is not reported as the user's.
    ///
    /// **Every setter whose GTK call emits a signal the peer listens to MUST
    /// go through this**, and that includes calls that change a value only as
    /// a side effect: a range narrowed past the value clamps it, removing the
    /// selected row changes the selection. The guard is restored rather than
    /// lowered, so a change made inside another does not lower it early.
    protected void Quietly(Handler change)
    {
        bool was = echoing;
        echoing = true;
        change();
        echoing = was;
    }

    ~GtkPeer() { Destroy(); }

    /// The control this peer reports to, or null once it has gone -- which a
    /// signal arriving during teardown genuinely can see, because GTK emits
    /// `destroy` while the widget is still alive.
    protected IControlNotify? Owner
    {
        get
        {
            IControlNotify? held = target;
            return held;
        }
    }

    /// What this peer's handlers hold, for one a subclass connects itself.
    protected PeerRelay Relay => _relay;

    /// Connects `handler` to a signal that carries nothing, handing it this
    /// peer for as long as the peer lives. See `PeerRelay`.
    ///
    /// **`handler` MUST NOT capture the peer**: it reaches it through its
    /// argument, which is the point.
    protected gulong WhenSignal(GtkWidget* instance, String signal, PeerSignal handler)
    {
        var relay = _relay;
        return ConnectPlain(instance, signal, () =>
        {
            var peer = relay.Peer;
            if (peer != null)
                handler((GtkPeer)peer);
        });
    }

    /// The same, for a signal that carries one pointer and answers.
    protected gulong WhenEvent(GtkWidget* instance, String signal, PeerEvent handler)
    {
        var relay = _relay;
        return ConnectEvent(instance, signal, (sender, carried) =>
        {
            var peer = relay.Peer;
            if (peer == null)
                return false;
            return handler((GtkPeer)peer, carried);
        });
    }

    /// Says which widget carries the signals and the style, for a peer whose
    /// outer widget is a scrolled window or a frame. Called by a subclass's
    /// constructor, before anything is connected.
    protected void SetInner(GtkWidget* actual) => inner = actual;

    /// Remembers the container that placed this peer. Called by
    /// `GtkContainerPeer.AddChild` and by nothing else.
    public void PlacedInto(GtkWidget* container, bool isLayout)
    {
        placedIn = container;
        placedInLayout = isLayout;
    }

    // ---------------------------------------------------------- the input

    /// The widget this peer reports the mouse from, and in whose coordinates.
    ///
    /// `inner` for everything but a window, whose surface is its client area:
    /// Win32 reports a form's mouse in client coordinates, below the menu bar,
    /// and does not report a click on the menu bar to the form at all.
    protected virtual GtkWidget* Surface => inner;

    /// Marks this peer's widgets as its own, so that `IsFor` can trace an
    /// event from the widget GTK gave it to back to this peer.
    protected virtual void Mark()
    {
        gpointer surface = (gpointer)Surface;
        g_object_set_data((gpointer)widget, PeerMark.ToPointer(), surface);
        g_object_set_data((gpointer)inner, PeerMark.ToPointer(), surface);
    }

    /// Whether a mouse event is this peer's to report.
    ///
    /// **GTK gives an event to the widget under the pointer and then to each of
    /// its ancestors in turn; Win32 sends it to one window.** So a peer
    /// reports an event only when the nearest marked widget at or above the one
    /// GTK gave it to is its own. A widget with no window of its own -- a label
    /// -- has its events given to its parent, which is also where a `STATIC`
    /// sends them on Windows.
    bool IsFor(GdkEvent* event)
    {
        if (_captured)
            return true;

        GtkWidget* at = gtk_get_event_widget(event);
        while (at != null)
        {
            gpointer mark = g_object_get_data((gpointer)at, PeerMark.ToPointer());
            if (mark != null)
                return mark == (gpointer)Surface;
            at = gtk_widget_get_parent(at);
        }
        return false;
    }

    /// Where the surface's corner is on the screen.
    ///
    /// A widget with no window of its own is drawn on its parent's, and its
    /// allocation says where on it.
    FPoint SurfaceOrigin()
    {
        GtkWidget* surface = Surface;
        gpointer window = gtk_widget_get_window(surface);
        if (window == null)
            return At(0, 0);

        gint x = 0;
        gint y = 0;
        gdk_window_get_origin((GdkWindow*)window, &x, &y);
        if (gtk_widget_get_has_window(surface) == 0)
        {
            GdkRectangle allocation;
            gtk_widget_get_allocation(surface, &allocation);
            x += allocation.X;
            y += allocation.Y;
        }
        return At(x, y);
    }

    /// Where a mouse event happened, in this peer's own coordinates.
    ///
    /// **Not the event's coordinates**, which are in whichever window GTK
    /// delivered it to -- a child's, or a parent's for a widget with no window.
    /// The position on the screen is the same whoever receives it.
    FPoint LocalPointOf(GdkEvent* event)
    {
        gdouble x = 0.0;
        gdouble y = 0.0;
        gdk_event_get_root_coords(event, &x, &y);
        var origin = SurfaceOrigin();
        return At(FloorToInt(x) - origin.X, FloorToInt(y) - origin.Y);
    }

    /// Subscribes to everything `IControlNotify` reports.
    ///
    /// **Not in the constructor**, because a subclass may not have settled
    /// which widget is `inner` yet, and because a peer with no notification
    /// target -- a menu's, a timer's -- has nothing to subscribe on behalf of.
    /// Every `Create` in `WidgetSet.sl` calls it once.
    ///
    /// The mouse is heard on `Surface` and the keyboard on `inner`, which
    /// differ only for a window: its keys arrive at the window, and its mouse
    /// at the client area.
    ///
    /// Every handler answers false, so that the widget's own handling still
    /// runs: GTK calls a handler connected here *before* the widget's class
    /// handler, and answering true would stop a button being pressed or an
    /// entry placing its cursor. `IsFor` is what keeps an ancestor quiet.
    public void Listen()
    {
        Mark();
        if (Owner == null)
            return;

        GtkWidget* mouse = Surface;
        gtk_widget_add_events(mouse,
            GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK |
            GDK_POINTER_MOTION_MASK | GDK_ENTER_NOTIFY_MASK | GDK_LEAVE_NOTIFY_MASK |
            GDK_SCROLL_MASK);
        gtk_widget_add_events(inner,
            GDK_KEY_PRESS_MASK | GDK_KEY_RELEASE_MASK | GDK_FOCUS_CHANGE_MASK);

        WhenEvent(mouse, "button-press-event", (peer, carried) =>
        {
            return peer.Pressed((GdkEvent*)carried);
        });
        WhenEvent(mouse, "button-release-event", (peer, carried) =>
        {
            peer.Released((GdkEvent*)carried);
            return false;
        });
        WhenEvent(mouse, "motion-notify-event", (peer, carried) =>
        {
            peer.Moved((GdkEvent*)carried);
            return false;
        });

        // GTK sends an enter and a leave for a crossing *within* a widget --
        // on to a child and back -- which Win32 does too, for a child window.
        // The detail field says which, and it is not one the accessors reach;
        // a control that only highlights on enter and unhighlights on leave
        // ends in the correct state either way.
        WhenEvent(mouse, "enter-notify-event", (peer, carried) =>
        {
            peer.Crossed(true);
            return false;
        });
        WhenEvent(mouse, "leave-notify-event", (peer, carried) =>
        {
            peer.Crossed(false);
            return false;
        });
        WhenEvent(mouse, "scroll-event", (peer, carried) =>
        {
            peer.Scrolled((GdkEvent*)carried);
            return false;
        });

        var relay = _relay;
        ConnectEvent(inner, "key-press-event", (sender, carried) =>
        {
            var owner = relay.Owner;
            if (owner == null)
                return false;
            var event = (GdkEvent*)carried;

            guint keyval = 0u;
            gdk_event_get_keyval(event, &keyval);
            var modifiers = ModifiersOf(event);
            ((IControlNotify)owner).OnPlatformKeyDown(KeyOf(event), modifiers);

            // The typed character, which the seam keeps separate from the key
            // for the reason it says: the layout and any dead keys have been
            // applied by now, and nothing about the keyval says so.
            guint typed = gdk_keyval_to_unicode(keyval);
            if (typed >= 32u && typed != 127u && !IsShortcut(event))
            {
                ((IControlNotify)owner).OnPlatformKeyPress((char32)typed);
            }
            return false;
        });

        ConnectEvent(inner, "key-release-event", (sender, carried) =>
        {
            var owner = relay.Owner;
            if (owner == null)
                return false;
            var event = (GdkEvent*)carried;
            ((IControlNotify)owner).OnPlatformKeyUp(KeyOf(event), ModifiersOf(event));
            return false;
        });

        WhenEvent(inner, "focus-in-event", (peer, carried) =>
        {
            peer.Focused(true);
            return false;
        });
        WhenEvent(inner, "focus-out-event", (peer, carried) =>
        {
            peer.Focused(false);
            return false;
        });
    }

    /// True when a context menu was shown, which is the one press a handler
    /// claims.
    bool Pressed(GdkEvent* event)
    {
        var owner = Owner;
        if (owner == null || !IsFor(event))
            return false;

        // GTK sends a plain press, then a second plain press, then a
        // `GDK_2BUTTON_PRESS` carrying the same position -- so the double
        // arrives as a *third* event rather than in place of anything. It
        // must not be reported as another press, or every double-click
        // would be three of them.
        if (EventType(event) == GDK_2BUTTON_PRESS)
        {
            ((IControlNotify)owner).OnPlatformDoubleClick();
            return false;
        }
        if (EventType(event) == GDK_3BUTTON_PRESS)
            return false;

        var at = LocalPointOf(event);
        ((IControlNotify)owner).OnPlatformMouseDown(ButtonOf(event), at, ModifiersOf(event));

        // **On the press, which is where a GTK program shows a menu** --
        // and unlike Win32 this needs no special message, because a GTK
        // tree does not run a loop of its own that swallows the release.
        // The notification is shared all the same: a control should not
        // have to know which platform it is on to offer a menu.
        //
        // The keyboard's menu key is not here. GTK reports it through the
        // `popup-menu` signal, whose handler answers a gboolean, and the
        // plain connector in this file returns nothing -- so wiring it
        // would put a garbage answer in the return register. It wants a
        // connector of its own and does not have one yet.
        if (ButtonOf(event) == MouseButton.Right)
            return ((IControlNotify)owner).OnPlatformContextMenu(at, false);
        return false;
    }

    void Released(GdkEvent* event)
    {
        var owner = Owner;
        if (owner == null || !IsFor(event))
            return;
        ((IControlNotify)owner).OnPlatformMouseUp(ButtonOf(event), LocalPointOf(event),
                                                  ModifiersOf(event));
    }

    void Moved(GdkEvent* event)
    {
        var owner = Owner;
        if (owner == null || !IsFor(event))
            return;
        ((IControlNotify)owner).OnPlatformMouseMove(LocalPointOf(event), ModifiersOf(event));
    }

    void Crossed(bool entered)
    {
        var owner = Owner;
        if (owner == null)
            return;
        if (entered)
        {
            ((IControlNotify)owner).OnPlatformMouseEnter();
        }
        else
        {
            ((IControlNotify)owner).OnPlatformMouseLeave();
        }
    }

    void Scrolled(GdkEvent* event)
    {
        var owner = Owner;
        if (owner == null || !IsFor(event))
            return;

        // GDK reports a direction rather than an amount. Win32's wheel delta
        // is 120 per notch and the seam took that number, so this reports
        // whole notches in the same units.
        gint direction = 0;
        if (gdk_event_get_scroll_direction(event, &direction) == 0)
            return;
        int delta = 0;
        if (direction == GDK_SCROLL_UP)
            delta = 120;
        if (direction == GDK_SCROLL_DOWN)
            delta = -120;
        if (delta == 0)
            return;

        ((IControlNotify)owner).OnPlatformMouseWheel(delta, LocalPointOf(event),
                                                     ModifiersOf(event));
    }

    void Focused(bool gained)
    {
        var owner = Owner;
        if (owner == null)
            return;
        if (gained)
        {
            ((IControlNotify)owner).OnPlatformGotFocus();
        }
        else
        {
            ((IControlNotify)owner).OnPlatformLostFocus();
        }
    }

    // ---------------------------------------------------------- the style

    /// Rewrites this peer's stylesheet from whatever has been set on it.
    ///
    /// **Wholesale, every time.** A `GtkCssProvider` has no way to change one
    /// declaration, so the provider is replaced -- which is also why each
    /// setter remembers its own fragment rather than appending to a string:
    /// setting a colour twice must not leave the first one in the sheet.
    protected void Restyle()
    {
        var body = foreCss + backCss + fontCss;

        if (styling != null)
        {
            gtk_style_context_remove_provider(gtk_widget_get_style_context(inner), styling);
            g_object_unref(styling);
            styling = null;
        }
        if (body.IsEmpty)
            return;

        styling = gtk_css_provider_new();
        GError* failed = null;
        gtk_css_provider_load_from_data(styling, ("* { " + body + " }").ToPointer(),
                                        -1, &failed);
        // Bad CSS is otherwise silent, and a typo in a colour would leave the
        // control looking untouched with nothing to read.
        if (failed != null)
            g_clear_error(&failed);

        gtk_style_context_add_provider(gtk_widget_get_style_context(inner), styling,
                                       GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    }

    /// Clips a `draw` context to the widget being drawn, and saves the state
    /// so the caller can restore it.
    ///
    /// **A draw handler MUST do this before the control paints.** GTK hands a
    /// widget a context whose clip covers whatever region is being redrawn,
    /// which is an ancestor's area and not the widget's -- an editor 755x396
    /// was given a clip of `-247,-134 1002x530`. Most drawing is bounded by
    /// its own coordinates and survives that; `Graphics.Clear` is
    /// `cairo_paint`, which fills the entire clip, so one control calling it
    /// wiped everything painted before it in the same frame.
    ///
    /// Every caller MUST pair this with `cairo_restore`.
    protected void ClipToSelf(cairo_t* context, GtkWidget* drawn)
    {
        cairo_save(context);
        cairo_new_path(context);
        cairo_rectangle(context, 0.0, 0.0,
                        (gdouble)gtk_widget_get_allocated_width(drawn),
                        (gdouble)gtk_widget_get_allocated_height(drawn));
        cairo_clip(context);
    }

    // ------------------------------------------------------- IControlPeer

    /// Moves and sizes the widget within the container its parent gave it.
    ///
    /// **A size request is a minimum, and a container is free to ignore it.**
    /// Asked for less than it insists on, a widget keeps its own minimum and
    /// overflows what the layout allowed -- GTK's minimums are larger than
    /// Win32's for the same controls, so a combo box given 24 pixels draws 34
    /// and hangs out of the band holding it.
    ///
    /// So the rectangle is *allocated* rather than requested, which is what
    /// the LCL's GTK3 widgetset does in `TGtk3Widget.SetBounds`: a library
    /// that has already computed a layout must not leave the last word to a
    /// container. The preferred size is asked for first because GTK 3 asserts
    /// on an allocation to a widget it has not measured -- the LCL's comment
    /// there reads "fixes gtk3 assertion".
    public virtual void SetBounds(FRect wanted)
    {
        bool moved = wanted.X != bounds.X || wanted.Y != bounds.Y;
        bool sized = wanted.Width != bounds.Width || wanted.Height != bounds.Height;
        bounds = wanted;

        if (placedIn != null)
        {
            if (placedInLayout)
                gtk_layout_move(placedIn, widget, wanted.X, wanted.Y);
            else
                gtk_fixed_move(placedIn, widget, wanted.X, wanted.Y);
        }

        // Clamped, because a layout can compute a negative height for a
        // control docked into a container smaller than its own margins -- and
        // GTK answers a negative size request with a `g_critical` and keeps
        // the old size, which is a warning on the terminal and a control in
        // the wrong place.
        int wide = wanted.Width < 0 ? 0 : wanted.Width;
        int high = wanted.Height < 0 ? 0 : wanted.Height;

        gtk_widget_set_size_request(widget, wide, high);

        // Reported from here rather than from a `size-allocate` handler,
        // because for a child the layout is what decided and GTK would only
        // be echoing it back one turn of the loop later. A top-level window
        // overrides this: there the user is what decided.
        var owner = Owner;
        if (owner != null)
        {
            if (moved)
                ((IControlNotify)owner).OnPlatformMoved(At(wanted.X, wanted.Y));
            if (sized)
                ((IControlNotify)owner).OnPlatformResized(Insisted(wide, high));
        }
    }

    /// The size the widget will really occupy: what it was given, raised to
    /// whatever it refuses to go below.
    ///
    /// A container is free to give a child its own minimum instead of the
    /// size requested, so a layout reading `Control.Height` afterwards MUST be
    /// told what the widget settled on. Nothing else can tell it: a child's
    /// allocation is decided by the call above, so GTK raises no event.
    FSize Insisted(int wide, int high)
    {
        gint leastWide = 0;
        gint wantsWide = 0;
        gtk_widget_get_preferred_width(widget, &leastWide, &wantsWide);

        gint leastHigh = 0;
        gint wantsHigh = 0;
        gtk_widget_get_preferred_height(widget, &leastHigh, &wantsHigh);

        return Extent(wide < leastWide ? leastWide : wide,
                      high < leastHigh ? leastHigh : high);
    }

    public virtual void SetVisible(bool visible)
    {
        if (visible)
        {
            gtk_widget_show(widget);
        }
        else
        {
            gtk_widget_hide(widget);
        }
    }

    public void SetEnabled(bool enabled)
    {
        gtk_widget_set_sensitive(widget, enabled ? 1 : 0);
    }

    /// Nothing, for a control with no caption of its own. Every control that
    /// has one overrides this, which is why the base does not guess at a
    /// property name.
    public virtual void SetText(String text) { }
    public virtual String GetText() => "";

    public void SetFont(Font font)
    {
        fontCss = " " + FontCss(font);
        Restyle();
    }

    public void SetForeColor(Color colour)
    {
        foreCss = " color: " + ToCss(colour) + ";";
        Restyle();
    }

    public void SetBackColor(Color colour)
    {
        // `background-image: none` as well, because a theme paints most
        // widgets with a gradient and a colour alone would sit under it.
        backCss = " background-image: none; background-color: " + ToCss(colour) + ";";
        Restyle();
    }

    public void Invalidate() => gtk_widget_queue_draw(widget);

    /// Paints it now, which on GTK takes more than letting the loop run.
    ///
    /// **Pumping the loop is not enough, and that is not obvious.** A GTK 3
    /// draw is scheduled on the *frame clock*, not queued as an event, so
    /// immediately after a `queue_draw` there is nothing pending:
    /// `gtk_events_pending` answers zero, the `while` below exits without
    /// painting, and the caller reads whatever the last paint left. This was
    /// written as a pump alone and the sample that caught it did so by asking
    /// where the caret was -- it was still where the previous paint had put it.
    ///
    /// So the updates are processed first, and the pump stays because the paint
    /// may raise work of its own.
    public void Update()
    {
        gtk_widget_queue_draw(widget);

        GdkWindow* surface = (GdkWindow*)gtk_widget_get_window(widget);
        if (surface != null)
            gdk_window_process_updates(surface, 1);

        while (gtk_events_pending() != 0)
            gtk_main_iteration_do(0);
    }

    public void Focus() => gtk_widget_grab_focus(inner);
    public bool HasFocus => gtk_widget_has_focus(inner) != 0;

    /// **A cursor needs a `GdkWindow` and a widget may not have one yet.**
    /// A control is given its cursor when it is made, long before it is shown,
    /// so the shape is remembered and applied again whenever the widget is
    /// realised -- which is what the `realize` handler below is for. One
    /// handler serves every later change of shape.
    public void SetCursor(CursorKind wanted)
    {
        shape = wanted;
        ApplyCursor();

        if (!_cursorWatched)
        {
            _cursorWatched = true;
            WhenSignal(CursorTarget, "realize", (peer) => { peer.ApplyCursor(); });
        }
    }

    /// The widget whose window the cursor is set on. A container whose
    /// interior has a window of its own overrides this, so that its cursor
    /// does not reach the window it sits on.
    protected virtual GtkWidget* CursorTarget => inner;

    /// GTK keeps the text on the widget and shows it itself, delays and
    /// placement included. A null takes the tip away; an empty string would
    /// leave an empty one that still pops up.
    public void SetToolTip(String text)
    {
        gtk_widget_set_tooltip_text(inner,
            text.ByteLength() == 0u ? null : text.ToPointer());

        // A tip already on screen keeps saying what it said until the pointer
        // leaves. Asking for it again is what refreshes one whose text has
        // just changed, which is what a caller answering per word needs.
        if (text.ByteLength() != 0u && gtk_widget_get_realized(inner) != 0)
            gtk_widget_trigger_tooltip_query(inner);
    }

    /// The window takes a reference of its own, so the one the cursor was
    /// made with is dropped here.
    void ApplyCursor()
    {
        gpointer window = gtk_widget_get_window(CursorTarget);
        if (window == null)
            return;
        gpointer cursor = gdk_cursor_new_from_name(gdk_display_get_default(),
                                                   CursorName(shape).ToPointer());
        gdk_window_set_cursor((GdkWindow*)window, cursor);
        if (cursor != null)
            g_object_unref(cursor);
    }

    public void SetCapture(bool captured)
    {
        _captured = captured;
        if (captured)
        {
            gtk_grab_add(inner);
        }
        else
        {
            gtk_grab_remove(inner);
        }
    }

    /// In the same coordinates the mouse is reported in: see `Surface`.
    public Point PointerPosition()
    {
        GtkWidget* measured = Surface;
        gpointer surface = gtk_widget_get_window(measured);
        if (surface == null)
            return Point.Empty;

        gpointer seat = gdk_display_get_default_seat(gdk_display_get_default());
        if (seat == null)
            return Point.Empty;

        gpointer device = gdk_seat_get_pointer(seat);
        if (device == null)
            return Point.Empty;

        gint x = 0;
        gint y = 0;
        guint buttons = 0u;
        gdk_window_get_device_position((GdkWindow*)surface, device, &x, &y, &buttons);

        // A widget with no window of its own is measured from its parent's.
        if (gtk_widget_get_has_window(measured) == 0)
        {
            GdkRectangle allocation;
            gtk_widget_get_allocation(measured, &allocation);
            x -= allocation.X;
            y -= allocation.Y;
        }
        return Point.At((int)x, (int)y);
    }

    /// Puts the widget last among its container's children.
    ///
    /// **Taken out and put back**, because most GTK widgets have no window to
    /// raise -- a button draws on its container's, and raising the window
    /// that is there raises the container. A `GtkFixed` draws and hit-tests
    /// its children in the order they were added, so the last one added is
    /// the one in front, and a widget with windows of its own gets them made
    /// again on top of its siblings'. The focus is given back if it had it.
    public void BringToFront()
    {
        if (placedIn == null)
            return;

        GList* children = gtk_container_get_children(placedIn);
        GtkWidget* last = null;
        for (GList* at = children; at != null; at = at->Next)
            last = (GtkWidget*)at->Data;
        g_list_free(children);
        if (last == widget)
            return;

        bool focused = gtk_widget_has_focus(inner) != 0;
        g_object_ref((gpointer)widget);
        gtk_container_remove(placedIn, widget);
        if (placedInLayout)
        {
            gtk_layout_put(placedIn, widget, bounds.X, bounds.Y);
        }
        else
        {
            gtk_fixed_put(placedIn, widget, bounds.X, bounds.Y);
        }
        g_object_unref((gpointer)widget);
        if (focused)
            gtk_widget_grab_focus(inner);
    }

    /// What the layout gave the widget, at the origin.
    ///
    /// The allocation rather than the requested size, because the two differ
    /// exactly when the warning on `SetBounds` applies and a control laying
    /// out its children should be told the truth.
    /// How much room children have.
    ///
    /// **What the layout set, not what GTK has allocated.** `SetBounds` asks
    /// for a size by setting a size *request*; GTK runs its own negotiation
    /// afterwards, so the allocation is still the size before the one just
    /// asked for -- and for a widget that has never been allocated it is 1x1,
    /// which GTK uses as its "no opinion yet" value.
    ///
    /// Reading it here is what made every control inside a container invisible
    /// on this backend: the container was sized correctly, its client area
    /// answered 1x1, and every child docked into one pixel. It went unnoticed
    /// because a form answers from its own `bounds` -- `GtkWindowPeer`
    /// overrides this -- so a control placed straight on a form was laid out
    /// correctly and a control inside a panel or a tab page was not.
    ///
    /// The allocation is still the answer before the layout has said anything,
    /// which is what `TabControl.PageArea` depends on: a notebook page is
    /// sized by GTK rather than by the layout, and there the allocation is the
    /// only source of truth.
    public virtual FRect ClientBounds
    {
        get
        {
            if (bounds.Width > 0 && bounds.Height > 0)
            {
                return Area(0, 0, bounds.Width, bounds.Height);
            }
            return Area(0, 0, gtk_widget_get_allocated_width(widget),
                              gtk_widget_get_allocated_height(widget));
        }
    }

    /// Zero, because a child of a `GtkFixed` is positioned from the fixed's
    /// own corner. Only a peer whose frame eats into that space -- a group
    /// box -- overrides this.
    public virtual FPoint ClientOrigin => At(0, 0);

    /// What GTK thinks the widget ought to be, which is what `AutoSize` wants.
    /// The natural size rather than the minimum: the minimum is what it can be
    /// squeezed to, and a button squeezed to its minimum has no padding left.
    public virtual FSize PreferredSize
    {
        get
        {
            GtkRequisition minimum;
            GtkRequisition natural;
            gtk_widget_get_preferred_size(widget, &minimum, &natural);
            return Extent(natural.Width, natural.Height);
        }
    }

    public nuint Handle => (nuint)(void*)widget;

    public void Destroy()
    {
        if (destroyed)
            return;
        destroyed = true;

        if (styling != null)
        {
            g_object_unref(styling);
            styling = null;
        }
        if (widget != null)
        {
            gtk_widget_destroy(widget);
            g_object_unref((gpointer)widget);
            widget = null;
            inner = null;
        }
    }

    /// The widget, for the widget set that makes children inside it and for a
    /// peer that has to reach one it was given.
    public GtkWidget* Widget => widget;
    public GtkWidget* Inner => inner;
}

// ========================================================== containers

/// A peer other controls can be put inside.
///
/// **The `GtkFixed` is the whole of it.** `content` is where children go, and
/// it is a different widget from `widget` whenever the container has a frame
/// of its own: a group box's `widget` is the `GtkFrame` and its `content` is
/// the fixed inside it.
public class GtkContainerPeer : GtkPeer, IContainerPeer
{
    protected GtkWidget* content;

    /// Whether `content` is a `GtkLayout`. A form's client area is one; every
    /// other container here is a `GtkFixed`. See `GtkWindowPeer`.
    protected bool contentIsLayout;

    /// The hidden radio button every radio put in this container joins, and
    /// the one that is ticked while none of them is. Owned: one reference,
    /// sunk when the first radio arrives. Null in a container with no radios.
    GtkWidget* _radios;

    public GtkContainerPeer(GtkWidget* made, IControlNotify? owner, GtkWidget* inside)
    {
        base(made, owner);
        content = inside;
        _radios = null;
    }

    ~GtkContainerPeer()
    {
        if (_radios != null)
        {
            g_object_unref((gpointer)_radios);
            _radios = null;
        }
    }

    /// The fixed children are placed in, for a peer that has to reach it.
    public GtkWidget* Content => content;

    /// The interior too, which is what GTK gives an event to when the
    /// interior has a window of its own.
    protected override void Mark()
    {
        base.Mark();
        g_object_set_data((gpointer)content, PeerMark.ToPointer(), (gpointer)Surface);
    }

    /// The interior, when it has a window of its own: a cursor set on the
    /// window the container sits on would reach its siblings too.
    protected override GtkWidget* CursorTarget
    {
        get
        {
            if (gtk_widget_get_has_window(content) != 0)
                return content;
            return inner;
        }
    }

    /// Reports every paint of this container's interior to the control, so
    /// that the windowless children sitting on it are drawn.
    ///
    /// **Nothing but the custom control did this, and nothing but the custom
    /// control drew.** A `GraphicControl` has no widget of its own: its parent
    /// is the only thing GTK will ever hand a cairo context to, so a parent
    /// that does not pass the context on is a parent whose `PaintBox`, `Shape`,
    /// `Bevel`, `Splitter` and `SpeedButton` are laid out, hit-tested, and
    /// invisible. Every self-test still passed -- which is the shape of bug
    /// this backend has produced twice now, and why a screenshot is the only
    /// answer to "is it drawn".
    ///
    /// Called by the containers rather than done here, because
    /// `GtkCustomPeer` has a draw handler of its own that also puts the caret
    /// on top, and two handlers would paint the control twice.
    ///
    /// **False, always.** The handler reports the paint and does not claim it:
    /// answering true would stop GTK drawing the container's real children,
    /// which are the platform controls on the form. False leaves them drawn
    /// over whatever the program painted, which is the order Win32 gets from
    /// `WS_CLIPCHILDREN` for nothing.
    ///
    /// The handler clips to the widget it was connected to, which a tab
    /// control's later change of `content` MUST NOT move.
    protected void ReportPaints()
    {
        var drawn = content;
        WhenEvent(drawn, "draw", (peer, carried) =>
        {
            ((GtkContainerPeer)peer).PaintInterior((cairo_t*)carried, drawn);
            return false;
        });
    }

    void PaintInterior(cairo_t* context, GtkWidget* drawn)
    {
        var owner = Owner;
        if (owner == null)
            return;

        ClipToSelf(context, drawn);
        var surface = new GtkGraphicsBackend((gpointer)context);
        ((IControlNotify)owner).OnPlatformPaint(new Graphics(surface));
        cairo_restore(context);
    }

    /// Virtual, because a notebook cannot honour this when it is called: see
    /// `GtkTabControlPeer.AddChild`.
    public virtual void AddChild(IControlPeer child)
    {
        var peer = (GtkPeer)child;
        if (contentIsLayout)
            gtk_layout_put(content, peer.Widget, 0, 0);
        else
            gtk_fixed_put(content, peer.Widget, 0, 0);
        peer.PlacedInto(content, contentIsLayout);

        // **Radio buttons are grouped by their container**, which is where the
        // seam leaves the question: `CreateCheck(owner, parent, radio)` says a
        // radio is wanted and nothing about which others it belongs with.
        // Without a group each is its own and they all stay ticked at once.
        //
        // **The group is a hidden radio of its own**, as the LCL's GTK3
        // widgetset makes one. A GTK group always has one member ticked and a
        // Win32 group starts with none: the hidden one is the member that is
        // ticked while the program has ticked nothing, and ticking it is how a
        // radio is unticked.
        if (child is GtkCheckPeer check)
        {
            if (check.IsRadio)
            {
                if (_radios == null)
                {
                    _radios = (GtkWidget*)g_object_ref_sink((gpointer)
                        gtk_radio_button_new_with_label_from_widget(null, "".ToPointer()));
                }
                check.JoinGroup(_radios);
            }
        }

        // A control is made visible by the control layer, not by being added,
        // so nothing is shown here -- which is also why `gtk_widget_show_all`
        // appears nowhere in this backend. It would show controls the program
        // had hidden.
    }

    public void RemoveChild(IControlPeer child)
    {
        var peer = (GtkPeer)child;
        gtk_container_remove(content, peer.Widget);
        peer.PlacedInto(null, false);
    }
}

#endif
