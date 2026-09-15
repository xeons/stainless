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

public FPoint At(int x, int y) { return Forms.Drawing.Point.At(x, y); }
public FSize  Extent(int width, int height) { return Forms.Drawing.Size.Of(width, height); }
public FSize  NoSize() { return Forms.Drawing.Size.Empty; }
public FRect  Area(int x, int y, int width, int height) {
    return Forms.Drawing.Rectangle.Of(x, y, width, height);
}

extern "C" {
    void sl_fail(byte* message);
}

/// What a control that has no GTK peer yet does.
///
/// **Loud rather than empty.** A `CreateToolBar` that answered with a peer
/// accepting every call would give a program a toolbar-shaped hole and no
/// sign of one; this stops at the first call and says which control it was.
/// The list of names this is called with is the list of what is left to do,
/// and it lives in `WidgetSet.sl` where a reader will find it.
public void NotYet(String what) {
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
class BoxedTicker {
    public Ticker Body;
    public BoxedTicker(Ticker body) { Body = body; }
}

/// The C entry point, one for every timer rather than one per timer: a
/// module-level function, so its address is a plain C function pointer.
gboolean RunTicker(gpointer data) {
    var boxed = (BoxedTicker)data;
    return boxed.Body() ? 1 : 0;
}

void ForgetTicker(gpointer data) { sl_release(data); }

extern "C" {
    void sl_retain(gpointer pointer);
    void sl_release(gpointer pointer);
}

/// Runs `body` every `milliseconds` until it answers false, and answers the
/// source id `g_source_remove` takes.
///
/// **Two things use this and they are not both timers.** `TTimer` is one; an
/// indeterminate progress bar is the other, because a GTK bar with no value
/// does not move unless something keeps pulsing it.
public gulong Tick(int milliseconds, Ticker body) {
    var boxed = new BoxedTicker(body);
    sl_retain((gpointer)boxed);

    return (gulong)g_timeout_add_full(G_PRIORITY_DEFAULT, (guint)milliseconds,
                                      RunTicker, (gpointer)boxed, ForgetTicker);
}

// ================================================================ colours

/// A `Color` as CSS writes one. Alpha is dropped: every colour the seam
/// carries is opaque, and `rgba()` would only invite one that is not.
public String ToCss(Color colour) {
    return "#" + Hex2(colour.R) + Hex2(colour.G) + Hex2(colour.B);
}

String Hex2(byte value) {
    var digits = "0123456789abcdef";
    return digits.Substring((nuint)(value >> 4), 1u) +
           digits.Substring((nuint)(value & 0x0Fu), 1u);
}

/// A `GdkRGBA` as a `Color`, which is where a colour chooser's answer comes
/// back from. The components are 0.0 to 1.0 and are rounded rather than
/// truncated, so that 1.0 is 255 and not 254.
public Color FromRgba(GdkRGBA colour) {
    return Color.FromRgb(Component(colour.Red), Component(colour.Green),
                         Component(colour.Blue));
}

byte Component(double value) {
    double scaled = value * 255.0 + 0.5;
    if (scaled < 0.0)   { return 0u; }
    if (scaled > 255.0) { return 255u; }
    return (byte)(int)scaled;
}

public GdkRGBA ToRgba(Color colour) {
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
public String FontCss(Font font) {
    var css = "font-family: \"" + font.Family + "\"; font-size: " +
              Text.FromInteger((long)font.Size) + "pt;";

    if (font.Bold)   { css = css + " font-weight: bold;"; }
    if (font.Italic) { css = css + " font-style: italic;"; }

    // One declaration takes both, and a font that is neither must still say
    // so: a provider is replaced wholesale, so anything left out reverts to
    // the theme's rather than to the last value set.
    if (font.Underline && font.Strikeout) {
        css = css + " text-decoration: underline line-through;";
    } else if (font.Underline) {
        css = css + " text-decoration: underline;";
    } else if (font.Strikeout) {
        css = css + " text-decoration: line-through;";
    }
    return css;
}

/// The same font as Pango writes one -- `"Sans Bold Italic 10"` -- which is
/// what a font chooser answers with and what cairo's toy text API takes.
public String PangoName(Font font) {
    var name = font.Family;
    if (font.Bold)   { name = name + " Bold"; }
    if (font.Italic) { name = name + " Italic"; }
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
public String CursorName(CursorKind shape) {
    if (shape == CursorKind.Hand)           { return "pointer"; }
    if (shape == CursorKind.Text)           { return "text"; }
    if (shape == CursorKind.Wait)           { return "wait"; }
    if (shape == CursorKind.Cross)          { return "crosshair"; }
    if (shape == CursorKind.SizeWestEast)   { return "ew-resize"; }
    if (shape == CursorKind.SizeNorthSouth) { return "ns-resize"; }
    if (shape == CursorKind.SizeAll)        { return "move"; }
    if (shape == CursorKind.No)             { return "not-allowed"; }
    return "default";
}

// ================================================================== input

/// Which modifiers an event carries.
///
/// Read from the event rather than from the keyboard, which is the opposite of
/// what the Win32 backend does and is the better answer: GDK reports the state
/// as it was when the event happened, so a handler that runs late still sees
/// what the user was holding.
public ModifierKeys ModifiersOf(GdkEvent* event) {
    guint state = 0u;
    gdk_event_get_state(event, &state);

    var held = ModifierKeys.None;
    if ((state & GDK_SHIFT_MASK) != 0u)   { held = held | ModifierKeys.Shift; }
    if ((state & GDK_CONTROL_MASK) != 0u) { held = held | ModifierKeys.Control; }
    if ((state & GDK_MOD1_MASK) != 0u)    { held = held | ModifierKeys.Alt; }
    return held;
}

/// Which button an event carries. GDK numbers from one and has more than
/// three; anything past the third is `None`, which is what a control that
/// only knows about three should be told.
public MouseButton ButtonOf(GdkEvent* event) {
    guint which = 0u;
    if (gdk_event_get_button(event, &which) == 0) { return MouseButton.None; }
    if (which == 1u) { return MouseButton.Left; }
    if (which == 2u) { return MouseButton.Middle; }
    if (which == 3u) { return MouseButton.Right; }
    return MouseButton.None;
}

/// Where an event happened, in the widget's own coordinates.
public FPoint PointOf(GdkEvent* event) {
    gdouble x = 0.0;
    gdouble y = 0.0;
    gdk_event_get_coords(event, &x, &y);
    return At((int)x, (int)y);
}

/// A GDK keyval as one of the seam's keys.
///
/// **The seam numbers keys the Win32 way**, which it says so in its own
/// comment: one backend has to own the numbering and Windows' is the one with
/// a name for everything. So this is the mapping that comment promised.
///
/// The printable range needs no table. GDK's keyval for an ASCII letter *is*
/// its character code, so `a` is 0x61 and `A` is 0x41, and the seam's `Key.A`
/// is 65 -- which means folding case is the whole of the conversion. The
/// digits line up exactly.
public Key KeyOf(guint keyval) {
    if (keyval >= 0x61u && keyval <= 0x7Au) { return (Key)(int)(keyval - 0x20u); }
    if (keyval >= 0x41u && keyval <= 0x5Au) { return (Key)(int)keyval; }
    if (keyval >= 0x30u && keyval <= 0x39u) { return (Key)(int)keyval; }
    if (keyval == 0x20u) { return Key.Space; }

    if (keyval == GDK_KEY_BackSpace) { return Key.Backspace; }
    if (keyval == GDK_KEY_Tab)       { return Key.Tab; }
    if (keyval == GDK_KEY_Return)    { return Key.Enter; }
    if (keyval == GDK_KEY_Escape)    { return Key.Escape; }
    if (keyval == GDK_KEY_Delete)    { return Key.Delete; }
    if (keyval == GDK_KEY_Insert)    { return Key.Insert; }
    if (keyval == GDK_KEY_Home)      { return Key.Home; }
    if (keyval == GDK_KEY_End)       { return Key.End; }
    if (keyval == GDK_KEY_Left)      { return Key.Left; }
    if (keyval == GDK_KEY_Up)        { return Key.Up; }
    if (keyval == GDK_KEY_Right)     { return Key.Right; }
    if (keyval == GDK_KEY_Down)      { return Key.Down; }
    if (keyval == GDK_KEY_Page_Up)   { return Key.PageUp; }
    if (keyval == GDK_KEY_Page_Down) { return Key.PageDown; }

    // The function keys are consecutive in both numberings, so one subtraction
    // covers all twelve rather than twelve comparisons.
    if (keyval >= GDK_KEY_F1 && keyval <= GDK_KEY_F1 + 11u) {
        return (Key)(int)((keyval - GDK_KEY_F1) + 112u);
    }
    return Key.None;
}

// ============================================================== the peer

/// What every GTK control's peer is.
///
/// **`widget` is what the parent places and `inner` is what does the work**,
/// and they differ whenever a control needs a scrolled window around it: a
/// list's `widget` is the `GtkScrolledWindow` that goes into the parent's
/// `GtkFixed`, and its `inner` is the `GtkTreeView` that carries the signals,
/// the style and the text. For everything else the two are the same widget,
/// and saying so once here is what keeps every subclass from having to ask.
public class GtkPeer : IControlPeer {
    /// The widget the parent places. Owned: one reference, sunk at
    /// construction and dropped by `Destroy`.
    protected GtkWidget* widget;
    /// The widget that carries the text, the signals and the style.
    protected GtkWidget* inner;

    /// The `GtkFixed` this peer was put into, so that `SetBounds` has
    /// something to move it within. Null until a container adopts it, which a
    /// top-level window never is.
    protected GtkWidget* placedIn;

    protected weak IControlNotify? target;

    /// Where the control layer last put it. Kept because GTK has no
    /// `GetWindowRect` for a child of a `GtkFixed` -- the position is the
    /// container's business and is not readable from the child.
    protected FRect bounds;

    /// The style provider this peer owns, made the first time a colour or a
    /// font is set and replaced wholesale each time after. Null until then,
    /// because until then the theme's answer is the right one.
    protected gpointer styling;
    protected String   foreCss;
    protected String   backCss;
    protected String   fontCss;

    protected bool destroyed;
    protected CursorKind shape;

    /// True while the *program* is setting a value, so that the signal GTK
    /// raises for it is not reported back as the user's doing. The seam is
    /// explicit that `OnPlatformValueChanged` is never raised for a change the
    /// program made, and this is what keeps that true.
    protected bool echoing;

    public GtkPeer(GtkWidget* made, IControlNotify? owner) {
        widget = (GtkWidget*)g_object_ref_sink((gpointer)made);
        inner = made;
        placedIn = null;
        target = owner;
        bounds = Area(0, 0, 0, 0);
        styling = null;
        foreCss = "";
        backCss = "";
        fontCss = "";
        destroyed = false;
        shape = CursorKind.Default;
        echoing = false;
    }

    /// **Never read as a bare field from inside a lambda.**
    ///
    /// A lambda captures a bare member *read* by value at the moment it is
    /// made (spec §2.15), so `if (echoing)` inside a handler tests what the
    /// flag said when the handler was connected -- which is false, for ever.
    /// Written that way it compiles, runs, and silently guards nothing: a
    /// program that ticked a checked menu item from its own click handler
    /// recursed until the stack ran out, and the backtrace was thirty frames
    /// of GObject with nothing in it to suggest a capture rule.
    ///
    /// `this.echoing` would do -- naming the receiver captures the object and
    /// reads the field through it -- and a call does the same thing for the
    /// same reason. The call is what this backend uses, because the two names
    /// say what the pair is for at every one of the dozen sites that uses it.
    ///
    /// The compiler warns about the bare form now (SL0610), which it did not
    /// while this was being written.
    protected bool Echoing() { return echoing; }
    protected void Echo(bool on) { echoing = on; }

    ~GtkPeer() { Destroy(); }

    /// The control this peer reports to, or null once it has gone -- which a
    /// signal arriving during teardown genuinely can see, because GTK emits
    /// `destroy` while the widget is still alive.
    protected IControlNotify? Owner() {
        IControlNotify? held = target;
        return held;
    }

    /// Says which widget carries the signals and the style, for a peer whose
    /// outer widget is a scrolled window or a frame. Called by a subclass's
    /// constructor, before anything is connected.
    protected void SetInner(GtkWidget* actual) { inner = actual; }

    /// Remembers the container that placed this peer. Called by
    /// `GtkContainerPeer.AddChild` and by nothing else.
    public void PlacedInto(GtkWidget* fixed) { placedIn = fixed; }

    // ---------------------------------------------------------- the input

    /// Subscribes to everything `IControlNotify` reports.
    ///
    /// **Not in the constructor**, because a subclass may not have settled
    /// which widget is `inner` yet, and because a peer with no notification
    /// target -- a menu's, a timer's -- has nothing to subscribe on behalf of.
    /// Every `Create` in `WidgetSet.sl` calls it once.
    public void Listen() {
        if (Owner() == null) { return; }

        gtk_widget_add_events(inner,
            GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK |
            GDK_POINTER_MOTION_MASK | GDK_ENTER_NOTIFY_MASK | GDK_LEAVE_NOTIFY_MASK |
            GDK_KEY_PRESS_MASK | GDK_KEY_RELEASE_MASK |
            GDK_FOCUS_CHANGE_MASK | GDK_SCROLL_MASK);

        ConnectEvent(inner, "button-press-event", (sender, carried) => {
            var owner = Owner();
            if (owner == null) { return false; }
            var event = (GdkEvent*)carried;
            ((IControlNotify)owner).OnPlatformMouseDown(
                ButtonOf(event), PointOf(event), ModifiersOf(event));
            return false;
        });

        ConnectEvent(inner, "button-release-event", (sender, carried) => {
            var owner = Owner();
            if (owner == null) { return false; }
            var event = (GdkEvent*)carried;
            ((IControlNotify)owner).OnPlatformMouseUp(
                ButtonOf(event), PointOf(event), ModifiersOf(event));
            return false;
        });

        ConnectEvent(inner, "motion-notify-event", (sender, carried) => {
            var owner = Owner();
            if (owner == null) { return false; }
            var event = (GdkEvent*)carried;
            ((IControlNotify)owner).OnPlatformMouseMove(PointOf(event), ModifiersOf(event));
            return false;
        });

        // GTK sends an enter and a leave for a crossing *within* a widget --
        // on to a child and back -- which Win32 does not, so a control would
        // otherwise see pairs of these while the pointer never left it. The
        // detail field says which, and it is not one the accessors reach, so
        // this is the one place the backend accepts being approximately right:
        // a control that only highlights on enter and unhighlights on leave
        // ends in the correct state either way.
        ConnectEvent(inner, "enter-notify-event", (sender, carried) => {
            var owner = Owner();
            if (owner != null) { ((IControlNotify)owner).OnPlatformMouseEnter(); }
            return false;
        });

        ConnectEvent(inner, "leave-notify-event", (sender, carried) => {
            var owner = Owner();
            if (owner != null) { ((IControlNotify)owner).OnPlatformMouseLeave(); }
            return false;
        });

        ConnectEvent(inner, "scroll-event", (sender, carried) => {
            var owner = Owner();
            if (owner == null) { return false; }
            var event = (GdkEvent*)carried;

            // GDK reports a direction rather than an amount. Win32's wheel
            // delta is 120 per notch and the seam took that number, so this
            // reports whole notches in the same units.
            gint direction = 0;
            if (gdk_event_get_scroll_direction(event, &direction) == 0) { return false; }
            int delta = 0;
            if (direction == GDK_SCROLL_UP)   { delta = 120; }
            if (direction == GDK_SCROLL_DOWN) { delta = -120; }
            if (delta == 0) { return false; }

            ((IControlNotify)owner).OnPlatformMouseWheel(
                delta, PointOf(event), ModifiersOf(event));
            return false;
        });

        ConnectEvent(inner, "key-press-event", (sender, carried) => {
            var owner = Owner();
            if (owner == null) { return false; }
            var event = (GdkEvent*)carried;

            guint keyval = 0u;
            gdk_event_get_keyval(event, &keyval);
            var modifiers = ModifiersOf(event);
            ((IControlNotify)owner).OnPlatformKeyDown(KeyOf(keyval), modifiers);

            // The typed character, which the seam keeps separate from the key
            // for the reason it says: the layout and any dead keys have been
            // applied by now, and nothing about the keyval says so.
            guint typed = gdk_keyval_to_unicode(keyval);
            if (typed >= 32u && typed != 127u) {
                ((IControlNotify)owner).OnPlatformKeyPress((char)typed);
            }
            return false;
        });

        ConnectEvent(inner, "key-release-event", (sender, carried) => {
            var owner = Owner();
            if (owner == null) { return false; }
            var event = (GdkEvent*)carried;
            guint keyval = 0u;
            gdk_event_get_keyval(event, &keyval);
            ((IControlNotify)owner).OnPlatformKeyUp(KeyOf(keyval), ModifiersOf(event));
            return false;
        });

        ConnectEvent(inner, "focus-in-event", (sender, carried) => {
            var owner = Owner();
            if (owner != null) { ((IControlNotify)owner).OnPlatformGotFocus(); }
            return false;
        });

        ConnectEvent(inner, "focus-out-event", (sender, carried) => {
            var owner = Owner();
            if (owner != null) { ((IControlNotify)owner).OnPlatformLostFocus(); }
            return false;
        });
    }

    // ---------------------------------------------------------- the style

    /// Rewrites this peer's stylesheet from whatever has been set on it.
    ///
    /// **Wholesale, every time.** A `GtkCssProvider` has no way to change one
    /// declaration, so the provider is replaced -- which is also why each
    /// setter remembers its own fragment rather than appending to a string:
    /// setting a colour twice must not leave the first one in the sheet.
    protected void Restyle() {
        var body = foreCss + backCss + fontCss;

        if (styling != null) {
            gtk_style_context_remove_provider(gtk_widget_get_style_context(inner), styling);
            g_object_unref(styling);
            styling = null;
        }
        if (body.IsEmpty()) { return; }

        styling = gtk_css_provider_new();
        GError* failed = null;
        gtk_css_provider_load_from_data(styling, ("* { " + body + " }").ToPointer(),
                                        -1, &failed);
        // Bad CSS is otherwise silent, and a typo in a colour would leave the
        // control looking untouched with nothing to read.
        if (failed != null) { g_clear_error(&failed); }

        gtk_style_context_add_provider(gtk_widget_get_style_context(inner), styling,
                                       GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    }

    // ------------------------------------------------------- IControlPeer

    /// Moves and sizes the widget within the `GtkFixed` its parent gave it.
    ///
    /// **A size request is a minimum, not a size.** Inside a `GtkFixed` a
    /// child is given its natural size unless the request is larger, so a
    /// control whose content wants more room than the layout allowed will
    /// overflow rather than clip. It is the same trade the LCL's GTK
    /// widgetset makes, and the mitigations are per control -- a label
    /// ellipsizes, an entry scrolls.
    public virtual void SetBounds(FRect wanted) {
        bool moved = wanted.X != bounds.X || wanted.Y != bounds.Y;
        bool sized = wanted.Width != bounds.Width || wanted.Height != bounds.Height;
        bounds = wanted;

        if (placedIn != null) {
            gtk_fixed_move(placedIn, widget, wanted.X, wanted.Y);
        }

        // Clamped, because a layout can compute a negative height for a
        // control docked into a container smaller than its own margins -- and
        // GTK answers a negative size request with a `g_critical` and keeps
        // the old size, which is a warning on the terminal and a control in
        // the wrong place.
        gtk_widget_set_size_request(widget,
            wanted.Width < 0 ? 0 : wanted.Width,
            wanted.Height < 0 ? 0 : wanted.Height);

        // Reported from here rather than from a `size-allocate` handler,
        // because for a child the layout is what decided and GTK would only
        // be echoing it back one turn of the loop later. A top-level window
        // overrides this: there the user is what decided.
        var owner = Owner();
        if (owner != null) {
            if (moved) { ((IControlNotify)owner).OnPlatformMoved(At(wanted.X, wanted.Y)); }
            if (sized) {
                ((IControlNotify)owner).OnPlatformResized(
                    Extent(wanted.Width, wanted.Height));
            }
        }
    }

    public virtual void SetVisible(bool visible) {
        if (visible) { gtk_widget_show(widget); } else { gtk_widget_hide(widget); }
    }

    public void SetEnabled(bool enabled) {
        gtk_widget_set_sensitive(widget, enabled ? 1 : 0);
    }

    /// Nothing, for a control with no caption of its own. Every control that
    /// has one overrides this, which is why the base does not guess at a
    /// property name.
    public virtual void SetText(String text) { }
    public virtual String GetText() { return ""; }

    public void SetFont(Font font) {
        fontCss = " " + FontCss(font);
        Restyle();
    }

    public void SetForeColor(Color colour) {
        foreCss = " color: " + ToCss(colour) + ";";
        Restyle();
    }

    public void SetBackColor(Color colour) {
        // `background-image: none` as well, because a theme paints most
        // widgets with a gradient and a colour alone would sit under it.
        backCss = " background-image: none; background-color: " + ToCss(colour) + ";";
        Restyle();
    }

    public void Invalidate() { gtk_widget_queue_draw(widget); }

    /// GTK has no `UpdateWindow`: a repaint happens when the main loop next
    /// runs, and the way to make that now is to let the loop run now.
    public void Update() {
        gtk_widget_queue_draw(widget);
        while (gtk_events_pending() != 0) { gtk_main_iteration_do(0); }
    }

    public void Focus()    { gtk_widget_grab_focus(inner); }
    public bool HasFocus() { return gtk_widget_has_focus(inner) != 0; }

    /// **A cursor needs a `GdkWindow` and a widget may not have one yet.**
    /// A control is given its cursor when it is made, long before it is shown,
    /// so the shape is remembered and applied again once the widget is
    /// realised -- which is what the `realize` handler below is for.
    public void SetCursor(CursorKind wanted) {
        shape = wanted;
        ApplyCursor();

        if (gtk_widget_get_realized(inner) == 0) {
            ConnectPlain(inner, "realize", () => { ApplyCursor(); });
        }
    }

    void ApplyCursor() {
        gpointer window = gtk_widget_get_window(inner);
        if (window == null) { return; }
        gdk_window_set_cursor((GdkWindow*)window,
            gdk_cursor_new_from_name(gdk_display_get_default(),
                                     CursorName(shape).ToPointer()));
    }

    public void SetCapture(bool captured) {
        if (captured) { gtk_grab_add(inner); } else { gtk_grab_remove(inner); }
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
    public virtual FRect ClientBounds() {
        if (bounds.Width > 0 && bounds.Height > 0) {
            return Area(0, 0, bounds.Width, bounds.Height);
        }
        return Area(0, 0, gtk_widget_get_allocated_width(widget),
                          gtk_widget_get_allocated_height(widget));
    }

    /// Zero, because a child of a `GtkFixed` is positioned from the fixed's
    /// own corner. Only a peer whose frame eats into that space -- a group
    /// box -- overrides this.
    public virtual FPoint ClientOrigin() { return At(0, 0); }

    /// What GTK thinks the widget ought to be, which is what `AutoSize` wants.
    /// The natural size rather than the minimum: the minimum is what it can be
    /// squeezed to, and a button squeezed to its minimum has no padding left.
    public virtual FSize PreferredSize() {
        GtkRequisition minimum;
        GtkRequisition natural;
        gtk_widget_get_preferred_size(widget, &minimum, &natural);
        return Extent(natural.Width, natural.Height);
    }

    public nuint Handle() { return (nuint)(void*)widget; }

    public void Destroy() {
        if (destroyed) { return; }
        destroyed = true;

        if (styling != null) { g_object_unref(styling); styling = null; }
        if (widget != null) {
            gtk_widget_destroy(widget);
            g_object_unref((gpointer)widget);
            widget = null;
            inner = null;
        }
    }

    /// The widget, for the widget set that makes children inside it and for a
    /// peer that has to reach one it was given.
    public GtkWidget* Widget() { return widget; }
    public GtkWidget* Inner()  { return inner; }
}

// ========================================================== containers

/// A peer other controls can be put inside.
///
/// **The `GtkFixed` is the whole of it.** `content` is where children go, and
/// it is a different widget from `widget` whenever the container has a frame
/// of its own: a group box's `widget` is the `GtkFrame` and its `content` is
/// the fixed inside it.
public class GtkContainerPeer : GtkPeer, IContainerPeer {
    protected GtkWidget* content;

    /// The first radio button put in this container, which every later one
    /// joins. Null until there is one, and a container with no radios never
    /// has one.
    GtkWidget* radios;

    public GtkContainerPeer(GtkWidget* made, IControlNotify? owner, GtkWidget* inside) {
        base(made, owner);
        content = inside;
        radios = null;
    }

    /// The fixed children are placed in, for a peer that has to reach it.
    public GtkWidget* Content() { return content; }

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
    protected void ReportPaints() {
        ConnectEvent(content, "draw", (sender, carried) => {
            var owner = Owner();
            if (owner == null) { return false; }
            var surface = new GtkGraphicsBackend(carried);
            ((IControlNotify)owner).OnPlatformPaint(new Graphics(surface));
            return false;
        });
    }

    /// Virtual, because a notebook cannot honour this when it is called: see
    /// `GtkTabControlPeer.AddChild`.
    public virtual void AddChild(IControlPeer child) {
        var peer = (GtkPeer)child;
        gtk_fixed_put(content, peer.Widget(), 0, 0);
        peer.PlacedInto(content);

        // **Radio buttons are grouped by their container**, which is where the
        // seam leaves the question: `CreateCheck(owner, parent, radio)` says a
        // radio is wanted and nothing about which others it belongs with. Win32
        // reads that off `WS_GROUP` on the first of a run; here the first radio
        // in a container is the group and every later one joins it, which is
        // the same rule. Without it each is its own group and they all stay
        // ticked at once.
        if (child is GtkCheckPeer check) {
            if (check.IsRadio()) {
                if (radios == null) { radios = check.Widget(); }
                else { gtk_radio_button_join_group(check.Widget(), radios); }
            }
        }

        // A control is made visible by the control layer, not by being added,
        // so nothing is shown here -- which is also why `gtk_widget_show_all`
        // appears nowhere in this backend. It would show controls the program
        // had hidden.
    }

    public void RemoveChild(IControlPeer child) {
        var peer = (GtkPeer)child;
        gtk_container_remove(content, peer.Widget());
        peer.PlacedInto(null);
    }
}

#endif
