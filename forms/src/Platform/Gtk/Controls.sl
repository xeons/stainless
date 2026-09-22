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

// One peer per GTK widget: windows, buttons, text, and the rest of the tier
// every platform has.
//
// **Each is short, and that is the finding.** The seam was written against
// Win32 and every interface in it turned out to be one GTK widget and its
// properties -- no interface had to change, and none of these peers keeps
// state the control layer already has. The two places that were not free are
// worth naming, because they are what a seam costs:
//
//   - **A window is three widgets.** `GtkWindow` takes one child, and a
//     window needs a menu bar above a client area, so there is a box in
//     between. `ClientBounds` then has to answer for the fixed rather than
//     for the window, or every control on a form with a menu would be placed
//     under the menu.
//   - **A modal window runs its own loop.** Win32 has `DialogBoxParam`; GTK
//     has `gtk_dialog_run` for a `GtkDialog` and nothing at all for a plain
//     window, so `ShowModal` nests a `gtk_main` and the window's own close
//     ends it.
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

// ================================================================== window

public class GtkWindowPeer : GtkContainerPeer, IWindowPeer
{
    /// The vertical box between the window and its client area, which exists
    /// only so that a menu bar has somewhere to go.
    GtkWidget* _stack;

    /// Between the box and the client area. It scrolls nothing and shows no
    /// scrollbars; it is there so that the client area's size request cannot
    /// reach the window. See where it is made.
    GtkWidget* _scroller;
    /// The menu bar currently in that box, so that replacing one can take the
    /// old one out first.
    GtkWidget* _bar;
    /// The peer that owns `_bar`. Held because a peer destroys its widget when
    /// dropped, and the program drops the old bar before handing over the new.
    IMenuPeer? _barPeer;
    /// True while `ShowModal`'s nested loop is running, so that the close
    /// which ends it does not also quit the application's loop.
    bool _modal;
    /// Whether the window has ever been laid out. The first `configure-event`
    /// is reported even when the numbers match what was asked for, because a
    /// form built before GTK allocated anything has laid itself out against a
    /// size it was promised rather than one it was given.
    bool _laidOut;

    /// **A resize is a request here, not an instruction.** `MoveWindow` on
    /// Win32 has resized the window by the time it returns; `gtk_window_resize`
    /// asks the window manager, which answers with a `configure-event` some
    /// time later -- and the events already in flight describe the size
    /// *before* the request. Reporting one of those puts the form back to a
    /// size it has already left, and a program that resized twice in quick
    /// succession ends up laid out for the first.
    ///
    /// So a request is outstanding until a configure matches it, and the
    /// echoes in between are dropped. `skipped` bounds that: a window manager
    /// is allowed to refuse a size, and after four it is taken at its word
    /// rather than ignored for ever.
    bool _pending;
    int _skipped;
    FRect _requested;
    weak IWindowNotify? window;

    public GtkWindowPeer(IWindowNotify owner, WindowBorder border)
    {
        base(gtk_window_new(GTK_WINDOW_TOPLEVEL), (IControlNotify)owner,
             gtk_layout_new(null, null));
        window = owner;
        _bar = null;
        _barPeer = null;
        _scroller = null;
        _modal = false;
        _laidOut = false;
        _pending = false;
        _skipped = 0;
        _requested = Area(0, 0, 0, 0);

        // **A window's size MUST NOT be decided by what is in it**, and this
        // is the arrangement the LCL's GTK3 widgetset uses for a form:
        // `TGtk3Window.CreateWidget` builds a box, a `GtkScrolledWindow` with
        // both policies `NEVER`, and a `GtkLayout` with a window of its own.
        //
        // A `GtkFixed` reports a minimum as wide as the furthest right edge of
        // any child. This library places children absolutely, so a control
        // insisting on a couple of pixels more than the layout gave it makes
        // the window's minimum wider than the window: a window manager
        // obliges, the form lays out against the new width, the control lands
        // further right, and round it goes -- two pixels a turn, several turns
        // a second, until the window is twenty thousand pixels wide. Under
        // `Xvfb` there is no window manager to oblige, which is why every
        // headless run looked right.
        //
        // A `GtkLayout` asks for no room of its own, so where its children sit
        // reaches nothing. Geometry hints do not do this: GTK takes the larger
        // of the hint and what the contents ask for.
        contentIsLayout = true;
        gtk_widget_set_has_window(content, 1);

        _stack = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
        gtk_container_add(widget, _stack);

        _scroller = gtk_scrolled_window_new(null, null);
        gtk_scrolled_window_set_policy(_scroller, GTK_POLICY_NEVER,
                                       GTK_POLICY_NEVER);
        gtk_container_add(_scroller, content);

        gtk_box_pack_end(_stack, _scroller, 1, 1, 0);
        gtk_widget_show(_stack);
        gtk_widget_show(_scroller);
        gtk_widget_show(content);
        ReportPaints();

        SetBorder(border);

        // **Every one of these goes through a method.** A lambda captures a
        // member read by value (spec §2.15), so `window`, `modal` and `bounds`
        // read as fields here would be whatever they were when the handler was
        // connected -- which for `bounds` is the zero rectangle, for ever.
        //
        // `delete-event` is the close the user asked for, and answering true
        // refuses it -- which is the one place the seam lets a control decide
        // and the reason `OnPlatformClosing` returns a bool at all.
        ConnectEvent(widget, "delete-event", (sender, carried) => { return Closing(); });

        // A window is the one control whose size the *user* decides, so this
        // is the one place the platform reports a resize rather than echoing
        // one back at the layout that asked for it.
        ConnectEvent(widget, "configure-event", (sender, carried) =>
        {
            Reconfigured();
            return false;
        });

        ConnectEvent(widget, "focus-in-event", (sender, carried) =>
        {
            var owner2 = Reporting();
            if (owner2 != null)
                ((IWindowNotify)owner2).OnPlatformActivatedWindow();
            return false;
        });

        ConnectEvent(widget, "focus-out-event", (sender, carried) =>
        {
            var owner2 = Reporting();
            if (owner2 != null)
                ((IWindowNotify)owner2).OnPlatformDeactivated();
            return false;
        });
    }

    /// The form this window reports to, or null once it has gone.
    IWindowNotify? Reporting()
    {
        IWindowNotify? held = window;
        return held;
    }

    /// True refuses the close, which is what `delete-event` means by it.
    bool Closing()
    {
        var owner2 = Reporting();
        if (owner2 == null)
            return false;
        if (!((IWindowNotify)owner2).OnPlatformClosing())
            return true;

        ((IWindowNotify)owner2).OnPlatformClosed();
        if (_modal)
        {
            _modal = false;
            gtk_main_quit();
        }
        return false;
    }

    /// What the window manager made of the window, reported on.
    ///
    /// The first one is reported whatever the numbers say: a form lays itself
    /// out against the size it *asked* for, and this is where it learns what
    /// it was given.
    void Reconfigured()
    {
        var owner2 = Reporting();
        if (owner2 == null)
            return;

        gint x = 0;
        gint y = 0;
        gtk_window_get_position(widget, &x, &y);
        gint width = 0;
        gint height = 0;
        gtk_window_get_size(widget, &width, &height);

        // An echo of a size the program has already replaced. Dropped, but
        // only so many times: a window manager that refuses the size outright
        // must not silence the window for ever.
        if (_pending)
        {
            if (width == _requested.Width && height == _requested.Height)
            {
                _pending = false;
            }
            else if (_skipped >= 4)
            {
                _pending = false;
            }
            else
            {
                _skipped = _skipped + 1;
                return;
            }
        }

        bool first = !_laidOut;
        _laidOut = true;
        bool moved = x != bounds.X || y != bounds.Y;
        bool sized = width != bounds.Width || height != bounds.Height;

        // **Written down before it is reported**, which is the whole of the
        // ordering and was got wrong once. `OnPlatformResized` lays the form
        // out again, and a layout asks this peer for `ClientBounds` -- which
        // reads `bounds`. Reporting first meant every relayout used the size
        // before the one being reported, so a window that opened at its
        // natural size and was then resized to the one it was asked for laid
        // its controls out against the natural one and never corrected them.
        bounds = Area(x, y, width, height);

        if (first || moved)
            ((IWindowNotify)owner2).OnPlatformMoved(At(x, y));
        if (first || sized)
        {
            ((IWindowNotify)owner2).OnPlatformResized(Extent(width, height));
        }
    }

    /// A top-level window is not inside anything, so there is no `GtkFixed` to
    /// move it within: position is the window manager's business and size is
    /// the window's own.
    ///
    /// **Which call sizes it depends on whether it has been realised.**
    /// `gtk_window_resize` asks the window manager to resize a window that
    /// exists; before there is one it is `gtk_window_set_default_size` that
    /// decides, and calling the wrong one leaves a window the size of its
    /// contents -- which for a form whose contents are an empty `GtkFixed` is
    /// one pixel by one, and every docked control then lays out against
    /// nothing.
    public override void SetBounds(FRect wanted)
    {
        bounds = wanted;
        _requested = wanted;
        _pending = true;
        _skipped = 0;
        gtk_window_move(widget, wanted.X, wanted.Y);

        if (gtk_widget_get_realized(widget) == 0)
        {
            gtk_window_set_default_size(widget, wanted.Width, wanted.Height);
        }
        else
        {
            gtk_window_resize(widget, wanted.Width, wanted.Height);
        }
    }

    /// The room inside the window, which is its own size less whatever the
    /// menu bar takes.
    ///
    /// **Not the fixed's allocation**, which is the obvious answer and the
    /// wrong one. A form lays itself out the moment it is built, and GTK has
    /// allocated nothing by then -- a fixed holding one label reports about
    /// 180 by 24 whatever the window was asked to be, so a header docked to
    /// the top came out 180 wide on a window 700 wide. `bounds` is what the
    /// window was set to and what a resize writes back, so it is right at
    /// every moment including the first.
    ///
    /// Win32 needs none of this: `GetClientRect` is right the instant
    /// `CreateWindowExW` returns, because Windows sizes a window when it is
    /// told to rather than when the loop next runs.
    ///
    /// **A GTK window's size is its content**, where a Win32 window's includes
    /// its frame -- so a form 700 wide has 700 of room here and about 684
    /// there. Nothing in the seam says which a window's bounds mean; the
    /// platform does, and a program assuming the Windows answer is assuming
    /// rather than reading.
    public override FRect ClientBounds
    {
        get
        {
            int spare = 0;
            if (_bar != null)
            {
                GtkRequisition minimum;
                GtkRequisition natural;
                gtk_widget_get_preferred_size(_bar, &minimum, &natural);
                spare = natural.Height;
            }
            return Area(0, 0, bounds.Width, bounds.Height - spare);
        }
    }

    public override void SetVisible(bool visible)
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

    public void SetTitle(String title) => gtk_window_set_title(widget, title.ToPointer());

    /// A window's text is its title, as it is on Win32, which is the route a
    /// form's `Text` arrives by.
    public override void SetText(String text) => SetTitle(text);

    public override String GetText()
    {
        gchar* title = gtk_window_get_title(widget);
        if (title == null)
            return "";
        return Text.FromNullTerminated(title);
    }

    /// There is no resource section to read an icon out of; see
    /// `LoadBitmapResource` on the widget set for why this is a difference in
    /// the binary format rather than a gap in this backend. GTK takes an icon
    /// from a file or from the desktop's icon theme instead.
    public bool SetIconResource(int id) => false;

    public void SetMenu(IMenuPeer? menu)
    {
        if (_bar != null)
        {
            gtk_container_remove(_stack, _bar);
            _bar = null;
        }
        _barPeer = menu;
        if (menu == null)
            return;

        var peer = (GtkMenuPeer)menu;
        _bar = peer.Widget;
        gtk_box_pack_start(_stack, _bar, 0, 0, 0);

        // Above the client area rather than below it, which is what packing
        // first would have given -- the fixed was packed in the constructor.
        gtk_box_reorder_child(_stack, _bar, 0);
        gtk_widget_show(_bar);
    }

    /// **A border is decoration and resizability, and nothing else.** GTK has
    /// no tool window: a window manager decides what a small caption looks
    /// like, and asking for one is `gtk_window_set_type_hint`, which several
    /// compositors ignore. So `Tool` is an undecorated, unresizable window --
    /// the closest thing that is true everywhere rather than a hint that is
    /// true sometimes.
    public void SetBorder(WindowBorder border)
    {
        if (border == WindowBorder.None)
        {
            gtk_window_set_decorated(widget, 0);
            gtk_window_set_resizable(widget, 0);
        }
        else if (border == WindowBorder.Fixed)
        {
            gtk_window_set_decorated(widget, 1);
            gtk_window_set_resizable(widget, 0);
        }
        else if (border == WindowBorder.Tool)
        {
            gtk_window_set_decorated(widget, 0);
            gtk_window_set_resizable(widget, 0);
        }
        else
        {
            gtk_window_set_decorated(widget, 1);
            gtk_window_set_resizable(widget, 1);
        }
    }

    public void SetState(WindowState state)
    {
        if (state == WindowState.Minimized)
        {
            gtk_window_iconify(widget);
        }
        else if (state == WindowState.Maximized)
        {
            gtk_window_deiconify(widget);
            gtk_window_maximize(widget);
        }
        else
        {
            gtk_window_deiconify(widget);
            gtk_window_unmaximize(widget);
        }
    }

    /// What the window manager has done with it, asked rather than
    /// remembered.
    ///
    /// A remembered answer is wrong the first time something *else* minimises
    /// the window -- a panel's window list, a keyboard shortcut -- and GDK
    /// has no accessor for the state a `window-state-event` carries, so the
    /// `GdkWindow` is what to ask. A window that has never been shown has no
    /// `GdkWindow`, and is `Normal`.
    public WindowState GetState()
    {
        gpointer native = gtk_widget_get_window(widget);
        if (native == null)
            return WindowState.Normal;

        gint state = gdk_window_get_state(native);
        if ((state & GDK_WINDOW_STATE_ICONIFIED) != 0)
            return WindowState.Minimized;
        if ((state & GDK_WINDOW_STATE_MAXIMIZED) != 0)
            return WindowState.Maximized;
        return WindowState.Normal;
    }

    public void Activate() => gtk_window_present(widget);

    public void Close() => gtk_window_close(widget);

    public void CenterOnScreen()
    {
        gtk_window_set_position(widget, GTK_WIN_POS_CENTER);
    }

    /// Shows the window and does not return until it is closed.
    ///
    /// **A nested `gtk_main`.** `gtk_dialog_run` does this for a `GtkDialog`
    /// and there is nothing for a plain window, so the loop is nested here and
    /// the `delete-event` handler above ends it. GTK supports nesting, which
    /// is what makes a modal window possible at all without a second thread.
    public void ShowModal()
    {
        gtk_window_set_modal(widget, 1);
        gtk_widget_show(widget);
        _modal = true;
        gtk_main();
        _modal = false;
        gtk_window_set_modal(widget, 0);
    }
}

// ================================================================== button

public class GtkButtonPeer : GtkPeer, IPushButtonPeer
{
    /// The `GtkImage` the button draws, or null for a button with none. Owned
    /// by the button once given to it, so this is a borrowed pointer kept only
    /// to change the margin that makes the spacing.
    GtkWidget* _glyph;
    ImageAlignment _placed;
    int _gap;

    public GtkButtonPeer(IControlNotify owner)
    {
        base(gtk_button_new_with_label(""), owner);
        _glyph = null;
        _placed = ImageAlignment.Left;
        _gap = 4;
        ConnectPlain(widget, "clicked", () =>
        {
            var target2 = Owner;
            if (target2 != null)
                ((IControlNotify)target2).OnPlatformActivated();
        });
    }

    /// The picture beside the caption, or null for none.
    ///
    /// **`always_show_image`, or nothing appears.** GTK hides a button's image
    /// when the desktop's `gtk-button-images` setting is off, which on every
    /// theme since GNOME 3.10 it is. A button given a picture and left to the
    /// setting draws the caption alone, with no warning anywhere -- which is
    /// the same trap `TGtk3WSBitBtn` falls into and works around.
    public void SetImage(IBitmapBackend? picture)
    {
        if (picture == null)
        {
            _glyph = null;
            gtk_button_set_image(widget, null);
            gtk_button_set_always_show_image(widget, 0);
            return;
        }

        var source = (IBitmapBackend)picture;
        gpointer pixbuf = null;
        if (source is GtkBitmapBackend made)
            pixbuf = made.Pixbuf;
        if (pixbuf == null)
            return;

        _glyph = gtk_image_new_from_pixbuf(pixbuf);
        gtk_button_set_image(widget, _glyph);
        gtk_button_set_always_show_image(widget, 1);
        ApplyImagePlacement();
    }

    public void SetImageAlign(ImageAlignment place)
    {
        _placed = place;
        ApplyImagePlacement();
    }

    public void SetImageSpacing(int pixels)
    {
        _gap = pixels;
        ApplyImagePlacement();
    }

    /// **The gap is a margin on the image, because GTK has no spacing to set.**
    /// The space between a button's image and its label is a style property,
    /// `image-spacing`, and GTK 3 offers no way to set a style property on one
    /// widget. So the gap is put on the side of the image the label is on,
    /// which is the same answer `TGtk3Button.SetSpacing` reaches and calls a
    /// cheat.
    void ApplyImagePlacement()
    {
        gint position = GTK_POS_LEFT;
        if (_placed == ImageAlignment.Right)
            position = GTK_POS_RIGHT;
        if (_placed == ImageAlignment.Top)
            position = GTK_POS_TOP;
        if (_placed == ImageAlignment.Bottom)
            position = GTK_POS_BOTTOM;
        gtk_button_set_image_position(widget, position);

        if (_glyph == null)
            return;
        int room = _gap < 0 ? 0 : _gap;
        gtk_widget_set_margin_start(_glyph, _placed == ImageAlignment.Right ? room : 0);
        gtk_widget_set_margin_end(_glyph, _placed == ImageAlignment.Left ? room : 0);
        gtk_widget_set_margin_top(_glyph, _placed == ImageAlignment.Bottom ? room : 0);
        gtk_widget_set_margin_bottom(_glyph, _placed == ImageAlignment.Top ? room : 0);
    }

    public override void SetText(String text)
    {
        gtk_button_set_label(widget, text.ToPointer());
    }

    public override String GetText()
    {
        return Text.FromNullTerminated(gtk_button_get_label(widget));
    }

    /// **The default is a window's property, not a button's.** GTK needs the
    /// button to be able to take it and the window to hand it over, and the
    /// window is only reachable once the button is in one -- which it is by
    /// the time a control layer sets this.
    public void SetDefault(bool isDefault)
    {
        gtk_widget_set_can_default(widget, isDefault ? 1 : 0);
        if (!isDefault)
            return;

        GtkWidget* top = gtk_widget_get_toplevel(widget);
        if (top != null)
            gtk_window_set_default(top, widget);
    }
}

// ============================================================ check and radio

public class GtkCheckPeer : GtkPeer, ICheckPeer
{
    /// Which of the three this is, which the container it goes into has to
    /// know: it joins every radio in it to the first, and there is nothing
    /// about a `GtkWidget*` that says which kind it is.
    CheckKind _sort;

    public bool IsRadio => _sort == CheckKind.Radio;

    /// Which widget each kind is. A toggle button is the plain
    /// `GtkToggleButton` that `GtkCheckButton` itself descends from, so the
    /// active state, the `toggled` signal and the label all work unchanged --
    /// only the indicator is gone, which is the whole of what a toggle button
    /// is.
    static GtkWidget* WidgetFor(CheckKind kind)
    {
        if (kind == CheckKind.Radio)
        {
            return gtk_radio_button_new_with_label_from_widget(null, "".ToPointer());
        }
        if (kind == CheckKind.Toggle)
        {
            return gtk_toggle_button_new_with_label("".ToPointer());
        }
        return gtk_check_button_new_with_label("".ToPointer());
    }

    public GtkCheckPeer(IControlNotify owner, CheckKind kind)
    {
        base(WidgetFor(kind), owner);
        _sort = kind;

        ConnectPlain(widget, "toggled", () =>
        {
            if (this.Echoing)
                return;
            var target2 = Owner;
            if (target2 == null)
                return;
            ((IControlNotify)target2).OnPlatformValueChanged();
            ((IControlNotify)target2).OnPlatformActivated();
        });
    }

    public override void SetText(String text)
    {
        gtk_button_set_label(widget, text.ToPointer());
    }

    public override String GetText()
    {
        return Text.FromNullTerminated(gtk_button_get_label(widget));
    }

    public void SetChecked(bool checked)
    {
        Echo(true);
        gtk_toggle_button_set_active(widget, checked ? 1 : 0);
    }

    public bool GetChecked() => gtk_toggle_button_get_active(widget) != 0;

    /// A checkbox is never the default button, and GTK would refuse to make
    /// one so. Stated rather than left to do nothing by accident.
    public void SetDefault(bool isDefault) { }
}

// =================================================================== label

public class GtkLabelPeer : GtkPeer, ILabelPeer
{
    public GtkLabelPeer(IControlNotify owner)
    {
        base(gtk_label_new("".ToPointer()), owner);

        // Left and top by default, which is what every other backend does and
        // what GTK does not: a label centres itself in its allocation.
        gtk_widget_set_halign(widget, GTK_ALIGN_START);
        gtk_widget_set_valign(widget, GTK_ALIGN_START);
        gtk_label_set_xalign(widget, 0.0f);

        // The mitigation the size-request warning in `Common.sl` promised: a
        // label whose text is wider than its bounds shortens the text rather
        // than widening itself over its neighbours.
        gtk_label_set_ellipsize(widget, PANGO_ELLIPSIZE_END);
    }

    public override void SetText(String text)
    {
        gtk_label_set_text(widget, text.ToPointer());
    }

    public override String GetText()
    {
        return Text.FromNullTerminated(gtk_label_get_text(widget));
    }

    public void SetAlignment(HorizontalAlignment alignment)
    {
        if (alignment == HorizontalAlignment.Center)
        {
            gtk_widget_set_halign(widget, GTK_ALIGN_CENTER);
            gtk_label_set_xalign(widget, 0.5f);
        }
        else if (alignment == HorizontalAlignment.Right)
        {
            gtk_widget_set_halign(widget, GTK_ALIGN_END);
            gtk_label_set_xalign(widget, 1.0f);
        }
        else
        {
            gtk_widget_set_halign(widget, GTK_ALIGN_START);
            gtk_label_set_xalign(widget, 0.0f);
        }
    }

    /// Wrapping and ellipsizing are the same property to Pango, so a label
    /// that wraps stops shortening -- which is the right way round: a wrapped
    /// label was given the height to wrap into.
    public void SetWordWrap(bool wrap)
    {
        gtk_label_set_line_wrap(widget, wrap ? 1 : 0);
        gtk_label_set_ellipsize(widget, wrap ? PANGO_ELLIPSIZE_NONE : PANGO_ELLIPSIZE_END);
    }
}

// ============================================================== text entry

/// One peer over two widgets.
///
/// **A single-line entry and a multi-line one are not the same widget in GTK**
/// and cannot be exchanged afterwards: a `GtkEntry` holds its own text, a
/// `GtkTextView` holds a `GtkTextBuffer` and wants a scrolled window around
/// it. `SetMultiline` therefore cannot do what its name says on a live
/// control, which is exactly the position the Win32 backend is in -- there it
/// is a creation-time style bit -- and the seam already carries that limit.
public class GtkEntryPeer : GtkPeer, ITextEntryPeer
{
    bool _multiline;
    /// The buffer, for a multi-line entry. Null for a single-line one.
    gpointer _buffer;

    public GtkEntryPeer(IControlNotify owner, bool lines)
    {
        base(lines ? gtk_scrolled_window_new(null, null) : gtk_entry_new(), owner);
        _multiline = lines;

        if (lines)
        {
            GtkWidget* view = gtk_text_view_new();
            gtk_container_add(widget, view);
            gtk_widget_show(view);
            SetInner(view);
            _buffer = gtk_text_view_get_buffer(view);
            gtk_scrolled_window_set_policy(widget, GTK_POLICY_AUTOMATIC,
                                                  GTK_POLICY_AUTOMATIC);

            // `changed` is on the buffer rather than on the view, which is the
            // one place in this backend where a signal is not on `inner`.
            ConnectPlain((GtkWidget*)_buffer, "changed", () =>
            {
                if (this.Echoing)
                    return;
                var target2 = Owner;
                if (target2 != null)
                    ((IControlNotify)target2).OnPlatformValueChanged();
            });
        }
        else
        {
            _buffer = null;
            ConnectPlain(widget, "changed", () =>
            {
                if (this.Echoing)
                    return;
                var target2 = Owner;
                if (target2 != null)
                    ((IControlNotify)target2).OnPlatformValueChanged();
            });
            ConnectPlain(widget, "activate", () =>
            {
                var target2 = Owner;
                if (target2 != null)
                    ((IControlNotify)target2).OnPlatformActivated();
            });
        }
    }

    public override void SetText(String text)
    {
        Echo(true);
        if (_multiline)
        {
            gtk_text_buffer_set_text(_buffer, text.ToPointer(), -1);
        }
        else
        {
            gtk_entry_set_text(widget, text.ToPointer());
        }
    }

    public override String GetText()
    {
        if (!_multiline)
            return Text.FromNullTerminated(gtk_entry_get_text(widget));

        GtkTextIter from;
        GtkTextIter to;
        gtk_text_buffer_get_bounds(_buffer, &from, &to);
        gchar* raw = gtk_text_buffer_get_text(_buffer, &from, &to, 0);
        if (raw == null)
            return "";

        var text = Text.FromNullTerminated(raw);
        g_free((gpointer)raw);
        return text;
    }

    public void SetReadOnly(bool readOnly)
    {
        if (_multiline)
        {
            gtk_text_view_set_editable(inner, readOnly ? 0 : 1);
        }
        else
        {
            gtk_editable_set_editable(widget, readOnly ? 0 : 1);
        }
    }

    /// A `GtkTextView` has no length limit, and neither has `TMemo`. Ignored
    /// for a multi-line entry rather than approximated with a `changed`
    /// handler that truncates, which would fight the user's cursor.
    public void SetMaxLength(int length)
    {
        if (!_multiline)
            gtk_entry_set_max_length(widget, length);
    }

    /// **GTK hides with a fixed character and will not be told which.**
    /// `gtk_entry_set_visibility` turns hiding on and the theme picks the
    /// glyph. A mask of zero means "show the text", which is the one thing
    /// this can honour exactly.
    public void SetPasswordChar(char mask)
    {
        if (_multiline)
            return;
        gtk_entry_set_visibility(widget, mask == 0u ? 1 : 0);
    }

    /// In characters on both kinds. An offset past the end is the end, which is
    /// what `SelectAll`'s large length relies on.
    public void SetSelection(int start, int length)
    {
        if (!_multiline)
        {
            gtk_editable_select_region(widget, start, start + length);
            return;
        }

        // The insertion point at the far end, as `EM_SETSEL` leaves it.
        GtkTextIter from;
        GtkTextIter to;
        gtk_text_buffer_get_iter_at_offset(_buffer, &from, start);
        gtk_text_buffer_get_iter_at_offset(_buffer, &to, start + length);
        gtk_text_buffer_select_range(_buffer, &to, &from);
        gtk_text_view_scroll_mark_onscreen(inner, gtk_text_buffer_get_insert(_buffer));
    }

    public (int, int) GetSelection()
    {
        if (_multiline)
        {
            // With nothing selected both ends are the insertion point, which
            // is the empty selection a caller wants.
            GtkTextIter first;
            GtkTextIter last;
            gtk_text_buffer_get_selection_bounds(_buffer, &first, &last);
            int start = gtk_text_iter_get_offset(&first);
            return (start, gtk_text_iter_get_offset(&last) - start);
        }

        gint from = 0;
        gint to = 0;
        if (gtk_editable_get_selection_bounds(widget, &from, &to) == 0)
        {
            gint at = gtk_editable_get_position(widget);
            return (at, 0);
        }
        return (from, to - from);
    }

    /// Nothing, and it is not an oversight: see the note on the class. A
    /// control that changes its mind is given a new peer, which is the same
    /// answer the Win32 backend gives for the same reason.
    public void SetMultiline(bool wanted) { }

    public String[] GetLines()
    {
        var whole = GetText();
        if (whole.IsEmpty)
            return new String[0u];
        return whole.Split('\n');
    }

    public void SetLines(String[] lines)
    {
        var joined = "";
        for (nuint i = 0u; i < lines.Length; i++)
        {
            if (i > 0u)
                joined = joined + "\n";
            joined = joined + lines[i];
        }
        SetText(joined);
    }

    public void CutToClipboard()
    {
        if (_multiline)
        {
            gtk_text_buffer_cut_clipboard(_buffer, DefaultClipboard(),
                                          gtk_text_view_get_editable(inner));
        }
        else
        {
            gtk_editable_cut_clipboard(widget);
        }
    }

    public void CopyToClipboard()
    {
        if (_multiline)
        {
            gtk_text_buffer_copy_clipboard(_buffer, DefaultClipboard());
        }
        else
        {
            gtk_editable_copy_clipboard(widget);
        }
    }

    public void PasteFromClipboard()
    {
        if (_multiline)
        {
            gtk_text_buffer_paste_clipboard(_buffer, DefaultClipboard(), null,
                                            gtk_text_view_get_editable(inner));
        }
        else
        {
            gtk_editable_paste_clipboard(widget);
        }
    }
}

// ============================================================== combo box

public class GtkComboPeer : GtkPeer, IComboPeer
{
    int _count;

    public GtkComboPeer(IControlNotify owner)
    {
        base(gtk_combo_box_text_new(), owner);
        _count = 0;

        ConnectPlain(widget, "changed", () =>
        {
            if (this.Echoing)
                return;
            var target2 = Owner;
            if (target2 != null)
                ((IControlNotify)target2).OnPlatformValueChanged();
        });
    }

    public void InsertItem(int index, String text)
    {
        gtk_combo_box_text_insert_text(widget, index, text.ToPointer());
        _count = _count + 1;
    }

    public void RemoveItem(int index)
    {
        gtk_combo_box_text_remove(widget, index);
        _count = _count - 1;
    }

    public void ClearItems()
    {
        gtk_combo_box_text_remove_all(widget);
        _count = 0;
    }

    public int ItemCount => _count;

    public void SetSelectedIndex(int index)
    {
        Echo(true);
        gtk_combo_box_set_active(widget, index);
    }

    public int GetSelectedIndex() => gtk_combo_box_get_active(widget);

    public override String GetText()
    {
        gchar* raw = gtk_combo_box_text_get_active_text(widget);
        if (raw == null)
            return "";
        var text = Text.FromNullTerminated(raw);
        g_free((gpointer)raw);
        return text;
    }

    /// **Editable is decided when the widget is made.**
    /// `gtk_combo_box_text_new_with_entry` is a different construction, and
    /// there is no property that turns one into the other -- the same
    /// creation-time limit a Win32 combo has, which is why the seam's own
    /// notes say a combo's editability is fixed at construction.
    public void SetEditable(bool editable) { }
}

// ============================================================== scroll bar

public class GtkScrollBarPeer : GtkPeer, IScrollBarPeer
{
    gpointer _adjustment;

    public GtkScrollBarPeer(IControlNotify owner, bool vertical)
    {
        base(gtk_scrollbar_new(vertical ? GTK_ORIENTATION_VERTICAL
                                        : GTK_ORIENTATION_HORIZONTAL, null),
             owner);
        _adjustment = gtk_range_get_adjustment(widget);

        ConnectPlain(widget, "value-changed", () =>
        {
            if (this.Echoing)
                return;
            var target2 = Owner;
            if (target2 != null)
                ((IControlNotify)target2).OnPlatformValueChanged();
        });
    }

    /// **The page size is part of the range, not beside it.** A scrollbar's
    /// thumb can never reach `maximum`: it stops a page short, which is what
    /// makes the thumb's size mean something. Win32 takes the same three
    /// numbers and does the same arithmetic internally.
    public void SetRange(int minimum, int maximum, int pageSize)
    {
        double page = (double)pageSize;
        if (page < 1.0)
            page = 1.0;

        gtk_adjustment_configure(_adjustment, gtk_adjustment_get_value(_adjustment),
                                 (double)minimum, (double)maximum + page,
                                 1.0, page, page);
    }

    public void SetValue(int value)
    {
        Echo(true);
        gtk_adjustment_set_value(_adjustment, (double)value);
    }

    public int GetValue() => (int)gtk_adjustment_get_value(_adjustment);
}

// ================================================================== group

public class GtkGroupPeer : GtkContainerPeer, IGroupPeer
{
    public GtkGroupPeer(IControlNotify owner)
    {
        base(gtk_frame_new(null), owner, gtk_fixed_new());
        gtk_container_add(widget, content);
        gtk_widget_show(content);
        ReportPaints();
    }

    public override void SetText(String text)
    {
        gtk_frame_set_label(widget, text.ToPointer());
    }

    /// A frame's caption and border occupy the top of its own rectangle, so a
    /// child placed at (0, 0) would be drawn over them. This is the one
    /// control that overrides it, which is what the seam's own note predicts.
    public override FPoint ClientOrigin
    {
        get
        {
            gint x = 0;
            gint y = 0;
            if (gtk_widget_translate_coordinates(content, widget, 0, 0, &x, &y) == 0)
            {
                return At(0, 0);
            }
            return At(x, y);
        }
    }
}

// ================================================================== panel

public class GtkPanelPeer : GtkContainerPeer, IPanelPeer
{
    public GtkPanelPeer(IControlNotify owner)
    {
        base(gtk_frame_new(null), owner, gtk_fixed_new());
        gtk_container_add(widget, content);
        gtk_widget_show(content);
        gtk_frame_set_shadow_type(widget, GTK_SHADOW_NONE);
        ReportPaints();
    }

    public void SetBorder(ControlBorder border)
    {
        if (border == ControlBorder.Single)
        {
            gtk_frame_set_shadow_type(widget, GTK_SHADOW_IN);
        }
        else if (border == ControlBorder.Sunken)
        {
            gtk_frame_set_shadow_type(widget, GTK_SHADOW_ETCHED_IN);
        }
        else
        {
            gtk_frame_set_shadow_type(widget, GTK_SHADOW_NONE);
        }
    }
}

// =================================================================== spin

public class GtkSpinPeer : GtkPeer, ISpinPeer
{

    public GtkSpinPeer(IControlNotify owner)
    {
        base(gtk_spin_button_new_with_range(0.0, 100.0, 1.0), owner);
        gtk_spin_button_set_digits(widget, 0);

        ConnectPlain(widget, "value-changed", () =>
        {
            if (this.Echoing)
                return;
            var target2 = Owner;
            if (target2 != null)
                ((IControlNotify)target2).OnPlatformValueChanged();
        });
    }

    public void SetRange(int minimum, int maximum)
    {
        gtk_spin_button_set_range(widget, (double)minimum, (double)maximum);
    }

    public void SetValue(int value)
    {
        Echo(true);
        gtk_spin_button_set_value(widget, (double)value);
    }

    public int GetValue() => gtk_spin_button_get_value_as_int(widget);
}

// ================================================================ progress

public class GtkProgressPeer : GtkPeer, IProgressPeer
{
    int _low;
    int _high;
    int _now;
    bool _pulsing;
    /// The source pulsing an indeterminate bar, or zero.
    gulong _pulse;

    public GtkProgressPeer(IControlNotify owner)
    {
        base(gtk_progress_bar_new(), owner);
        _low = 0;
        _high = 100;
        _now = 0;
        _pulsing = false;
        _pulse = 0u;
    }

    public void SetRange(int minimum, int maximum)
    {
        _low = minimum;
        _high = maximum;
        Show();
    }

    public void SetValue(int value)
    {
        _now = value;
        Show();
    }
    public int  GetValue() => _now;

    /// **A GTK bar with no value does not move on its own.** `pulse` advances
    /// it one step, and something has to keep calling it -- so an
    /// indeterminate bar here is a timer that pulses four times a second,
    /// which is what the LCL's GTK widgetset does for the same reason.
    public void SetIndeterminate(bool indeterminate)
    {
        if (indeterminate == _pulsing)
            return;
        _pulsing = indeterminate;

        if (!indeterminate)
        {
            if (_pulse != 0u)
            {
                g_source_remove((guint)_pulse);
                _pulse = 0u;
            }
            Show();
            return;
        }
        // Through a method: a lambda captures `widget` by value, and a peer
        // destroyed while pulsing would leave this one pulsing a widget that
        // is gone.
        _pulse = Tick(250, () => { return Pulse(); });
    }

    /// One step of the back-and-forth, and false once there is nothing left to
    /// step -- which is what takes the source off the loop when the control
    /// is destroyed.
    bool Pulse()
    {
        if (widget == null)
            return false;
        gtk_progress_bar_pulse(widget);
        return true;
    }

    /// The value as a fraction, which is what a GTK bar takes. A range of no
    /// width is an empty bar rather than a division by zero.
    void Show()
    {
        if (_pulsing)
            return;
        int span = _high - _low;
        double fraction = span <= 0 ? 0.0 : (double)(_now - _low) / (double)span;
        if (fraction < 0.0)
            fraction = 0.0;
        if (fraction > 1.0)
            fraction = 1.0;
        gtk_progress_bar_set_fraction(widget, fraction);
    }
}

// =============================================================== track bar

public class GtkTrackBarPeer : GtkPeer, ITrackBarPeer
{
    int _low;
    int _high;

    public GtkTrackBarPeer(IControlNotify owner, bool vertical)
    {
        base(gtk_scale_new_with_range(vertical ? GTK_ORIENTATION_VERTICAL
                                               : GTK_ORIENTATION_HORIZONTAL,
                                      0.0, 100.0, 1.0),
             owner);
        _low = 0;
        _high = 100;
        gtk_scale_set_draw_value(widget, 0);
        gtk_scale_set_digits(widget, 0);

        ConnectPlain(widget, "value-changed", () =>
        {
            if (this.Echoing)
                return;
            var target2 = Owner;
            if (target2 != null)
                ((IControlNotify)target2).OnPlatformValueChanged();
        });
    }

    public void SetRange(int minimum, int maximum)
    {
        _low = minimum;
        _high = maximum;
        gtk_range_set_range(widget, (double)minimum, (double)maximum);
    }

    public void SetValue(int value)
    {
        Echo(true);
        gtk_range_set_value(widget, (double)value);
    }

    public int GetValue() => (int)gtk_range_get_value(widget);

    /// Marks rather than a tick frequency, because GTK has no frequency: each
    /// tick is added by hand, and changing the interval means clearing them
    /// and adding them again.
    public void SetTickFrequency(int every)
    {
        gtk_scale_clear_marks(widget);
        if (every <= 0)
            return;

        int at = _low;
        while (at <= _high)
        {
            gtk_scale_add_mark(widget, (double)at, GTK_POS_BOTTOM, null);
            at = at + every;
        }
    }
}

// ============================================================== tab control

public class GtkTabControlPeer : GtkContainerPeer, ITabControlPeer
{
    /// One fixed per tab, because a notebook page *is* a widget and the
    /// control layer expects one client area per tab. `content` is whichever
    /// of them is showing, so that a child added now lands on the right page.
    List<GtkWidget*> _pages;

    /// What `PageArea` answered the last time the control layer was told to
    /// lay out again, so that the same answer is not reported twice. See
    /// `Reallocated`.
    FRect _reported;

    /// Whether a relayout is already on the main loop waiting to run.
    bool _queued;

    /// A child that has been added but has no page to go on yet.
    ///
    /// **The control layer parents a page's content before it makes the page.**
    /// `TabPage`'s constructor builds its panel -- which is what reaches
    /// `AddChild` -- and only then calls `TabControl.Register`, which is what
    /// reaches `AddTab`. Every other container can answer `AddChild`
    /// immediately because it has somewhere to put the child; a notebook does
    /// not, because the page is what `AddTab` is about to create.
    ///
    /// Putting it on `content` anyway is what the first version did, and it
    /// put the first tab's controls on a `GtkFixed` that is not in the
    /// notebook at all, and every later tab's controls on the *previous*
    /// page. Both are invisible, and the second is invisible in a way that
    /// looks like the first.
    GtkPeer? _waiting;

    public GtkTabControlPeer(IControlNotify owner)
    {
        base(gtk_notebook_new(), owner, gtk_fixed_new());
        _pages = new List<GtkWidget*>();
        _reported = Area(0, 0, 0, 0);
        _queued = false;
        _waiting = null;

        // **A page is the one child GTK sizes rather than the layout.**
        //
        // Everywhere else in this backend a child's size is what the layout
        // decided, and `SetBounds` reports it rather than waiting for GTK to
        // echo it back a turn of the loop later. A notebook page is the
        // exception: the control layer does not decide the page area, it
        // *asks* for it -- and the answer is the page's allocation, which is
        // 1x1 until GTK has run a size negotiation.
        //
        // `ShowOnly` asks during construction, long before that, so every
        // control on every page was laid out into one pixel and never drawn.
        // On Win32 the same call works because `TCM_ADJUSTRECT` computes from
        // the control's own rectangle rather than reading an allocation.
        //
        // So this waits for the allocation and then asks the control layer to
        // lay out again. It reports the tab control's own extent unchanged --
        // nothing about *it* moved -- which is enough to reach `OnResize`, and
        // `TabControl.OnResize` is what calls `ShowOnly`.
        ConnectEvent(widget, "size-allocate", (sender, carried) =>
        {
            return Reallocated();
        });

        // **`notify::page` rather than `switch-page`, and the reason is a
        // crash.** A handler's C shape has to match what the signal emits, and
        // `Gtk.Events` connects handlers of one shape: sender, one pointer,
        // user data. `switch-page` carries a page *and* a page number, so the
        // user data would arrive in the wrong register -- the boxed closure
        // read out of a `guint`, and a segfault at the first tab added. The
        // property notification carries a `GParamSpec*` and fits, and it says
        // the same thing.
        ConnectEvent(widget, "notify::page", (sender, carried) =>
        {
            if (this.Echoing)
                return false;
            var target2 = Owner;
            if (target2 != null)
                ((IControlNotify)target2).OnPlatformValueChanged();
            return false;
        });
    }

    /// **Owned, and that is what makes removing one safe.** A notebook holds
    /// the only reference to a page, so `gtk_notebook_remove_page` drops it to
    /// zero and destroys the page *and every control the program put on it* --
    /// while the control layer goes on holding those widgets, because a
    /// `TabPage` is a control whose lifetime is its own. The next layout then
    /// moves a freed widget, which is a use-after-free that shows up as
    /// `GTK_IS_WIDGET` assertions long before it shows up as a crash.
    ///
    /// A reference of this peer's own means removal unparents rather than
    /// destroys, and the page is still there if the program puts it back.
    /// Holds the child until `AddTab` has a page to put it on.
    public override void AddChild(IControlPeer child)
    {
        _waiting = (GtkPeer)child;
    }

    public int AddTab(String text, int image)
    {
        GtkWidget* page = (GtkWidget*)g_object_ref_sink((gpointer)gtk_fixed_new());
        gtk_widget_show(page);
        int index = gtk_notebook_append_page(widget, page,
                                             gtk_label_new(text.ToPointer()));
        _pages.Add(page);
        if (_pages.Count == 1u)
            content = page;

        // The page this tab was made for, which is the child added just before
        // it. Anything else would be a program putting a control straight on a
        // tab control rather than on one of its pages, which the control layer
        // does not do.
        var held = _waiting;
        if (held != null)
        {
            var peer = (GtkPeer)held;
            gtk_fixed_put(page, peer.Widget, 0, 0);
            peer.PlacedInto(page, false);
            _waiting = null;
        }
        return index;
    }

    public void RemoveTab(int index)
    {
        if (index < 0 || (nuint)index >= _pages.Count)
            return;

        // The reference taken in `AddTab` is dropped with the peer rather than
        // here: the page keeps whatever the program put on it, and the control
        // layer is still holding those controls.
        gtk_notebook_remove_page(widget, index);
        _pages.RemoveAt((nuint)index);
        content = _pages.Count == 0u ? content : _pages[0u];
    }

    ~GtkTabControlPeer()
    {
        for (nuint i = 0u; i < _pages.Count; i++)
        {
            g_object_unref((gpointer)_pages[i]);
        }
        _pages.Clear();
    }

    public void SetTabText(int index, String text)
    {
        if (index < 0 || (nuint)index >= _pages.Count)
            return;
        gtk_notebook_set_tab_label(widget, _pages[(nuint)index],
                                   gtk_label_new(text.ToPointer()));
    }

    public void SetSelectedTab(int index)
    {
        Echo(true);
        gtk_notebook_set_current_page(widget, index);
        if (index >= 0 && (nuint)index < _pages.Count)
            content = _pages[(nuint)index];
    }

    public int GetSelectedTab() => gtk_notebook_get_current_page(widget);
    public int TabCount => gtk_notebook_get_n_pages(widget);

    /// The area inside the tabs, which is what the seam asks for rather than
    /// the client area -- the tabs themselves are part of that.
    ///
    /// **Derived from the bounds the layout set, minus what the tabs take**,
    /// rather than read straight off the page's allocation. Reading the
    /// allocation is a feedback loop: the layout sizes the page's content to
    /// it, the content's size request grows the notebook, the notebook grows
    /// the window, and the next allocation is bigger again. It ratchets a
    /// window open to the size of the screen in a few frames, which is exactly
    /// what it did.
    ///
    /// The tabs' size is the one thing here GTK has to be asked, and it is
    /// stable once the notebook has been allocated: the difference between
    /// what the notebook got and what it passed on to the page. Before that it
    /// is not known at all, so the whole of the bounds is the best answer
    /// available, and the `size-allocate` that follows corrects it.
    public Rectangle PageArea
    {
        get
        {
            if (_pages.Count == 0u)
                return ClientBounds;

            int bookWidth = gtk_widget_get_allocated_width(widget);
            int bookHeight = gtk_widget_get_allocated_height(widget);
            int pageWidth = gtk_widget_get_allocated_width(content);
            int pageHeight = gtk_widget_get_allocated_height(content);

            // 1x1 is GTK's "never allocated", and a page cannot be larger than the
            // notebook holding it -- either says the measurement is not real yet.
            if (pageHeight <= 1 || bookHeight < pageHeight || bookWidth < pageWidth)
            {
                return Area(0, 0, bounds.Width, bounds.Height);
            }

            int across = bookWidth - pageWidth;
            int down = bookHeight - pageHeight;
            return Area(0, 0, bounds.Width - across, bounds.Height - down);
        }
    }

    /// GTK has allocated the notebook, so the page area may have become real.
    ///
    /// **Guarded on the answer rather than on the signal**, because laying out
    /// again sets bounds on the page's child, which asks GTK for another
    /// allocation, which raises this again. Reporting only a *changed* page
    /// area is what makes that settle instead of spinning: the second pass
    /// finds the same width and height and stops.
    ///
    /// **The relayout is queued, not run here.** Laying out from inside a
    /// `size-allocate` means calling `gtk_fixed_move` while GTK is part-way
    /// through allocating that very container, and it segfaults -- the
    /// backtrace is `gtk_fixed_move` under `ShowOnly` under this handler,
    /// under `gtk_widget_size_allocate`. Queueing it lets GTK finish, and the
    /// layout then runs against a notebook that is no longer being edited
    /// underneath it.
    ///
    /// False, so that GTK's own handler still runs -- it is what allocates the
    /// children.
    bool Reallocated()
    {
        var now = PageArea;
        if (now.Width == _reported.Width && now.Height == _reported.Height)
        {
            return false;
        }
        _reported = now;

        // One at a time. A queued pass sets bounds, which asks for another
        // allocation, which arrives here again; without this a burst of
        // allocations would queue a pass each.
        if (!_queued)
        {
            _queued = true;
            Tick(0, () => { return Relayout(); });
        }
        return false;
    }

    /// The queued pass, on the main loop with GTK's allocation finished.
    /// Answers false, which takes the source off the loop.
    bool Relayout()
    {
        _queued = false;
        var owner = Owner;
        if (owner != null)
        {
            ((IControlNotify)owner).OnPlatformResized(bounds.Extent);
        }
        return false;
    }

    /// A tab's picture would be an image packed beside its label. Left until
    /// image lists are, so that a tab and a toolbar get pictures the same way.
    public void SetImages(IImageListBackend images) { }
}

// =============================================================== status bar

/// **GTK's status bar is one message, not a row of panels.**
///
/// `GtkStatusbar` holds a stack of strings and shows the top one, which is a
/// different idea from `TStatusBar`'s panels. So this is a `GtkBox` of frames
/// with a label in each -- which is what the widget would have to be anyway to
/// honour the seam's `SetPanels`, and is what the theme draws a status bar as.
public class GtkStatusBarPeer : GtkPeer, IStatusBarPeer
{
    List<GtkWidget*> _cells;

    public GtkStatusBarPeer(IControlNotify owner)
    {
        base(gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 2), owner);
        _cells = new List<GtkWidget*>();
    }

    public void SetPanels(int[] edges)
    {
        for (nuint i = 0u; i < _cells.Count; i++)
        {
            gtk_container_remove(widget, _cells[i]);
        }
        _cells.Clear();

        int left = 0;
        for (nuint i = 0u; i < edges.Length; i++)
        {
            GtkWidget* frame = gtk_frame_new(null);
            gtk_frame_set_shadow_type(frame, GTK_SHADOW_IN);

            GtkWidget* label = gtk_label_new("".ToPointer());
            gtk_label_set_xalign(label, 0.0f);
            gtk_label_set_ellipsize(label, PANGO_ELLIPSIZE_END);
            gtk_container_add(frame, label);

            // The last edge may be -1, meaning "to the end", and that is the
            // one panel that expands. Every other is a fixed width, which is
            // the difference between two consecutive edges.
            int edge = edges[i];
            bool last = edge < 0;
            if (!last)
                gtk_widget_set_size_request(frame, edge - left, -1);
            gtk_box_pack_start(widget, frame, last ? 1 : 0, 1, 0);

            gtk_widget_show(label);
            gtk_widget_show(frame);
            _cells.Add(frame);
            left = edge;
        }
    }

    public void SetPanelText(int index, String text)
    {
        if (index < 0 || (nuint)index >= _cells.Count)
            return;
        GtkWidget* label = gtk_bin_get_child(_cells[(nuint)index]);
        if (label != null)
            gtk_label_set_text(label, text.ToPointer());
    }
}

// ================================================================= toolbar

public class GtkToolBarPeer : GtkPeer, IToolBarPeer
{
    List<GtkWidget*> _items;
    /// Which of them are toggles, so that a checked state can be refused for
    /// a plain button rather than silently doing nothing to one.
    List<bool> _toggles;
    GtkImageListBackend? _pictures;
    bool _captions;

    public GtkToolBarPeer(IControlNotify owner)
    {
        base(gtk_toolbar_new(), owner);
        _items = new List<GtkWidget*>();
        _toggles = new List<bool>();
        _pictures = null;
        _captions = false;
        gtk_toolbar_set_style(widget, GTK_TOOLBAR_ICONS);

        // Items that do not fit go into a drop-down at the end, which is what
        // lets the toolbar be made smaller than the sum of its items. Without
        // it the toolbar insists on room for all of them and whatever holds it
        // is pushed wider.
        gtk_toolbar_set_show_arrow(widget, 1);
    }

    public int AddButton(String text, int image, ToolButtonKind kind)
    {
        GtkWidget* item;
        if (kind == ToolButtonKind.Separator)
        {
            item = gtk_separator_tool_item_new();
        }
        else if (kind == ToolButtonKind.Toggle)
        {
            item = gtk_toggle_tool_button_new();
            gtk_tool_button_set_label(item, text.ToPointer());
        }
        else
        {
            item = gtk_tool_button_new(null, text.ToPointer());
        }

        if (kind != ToolButtonKind.Separator && image >= 0 && _pictures != null)
        {
            gpointer picture = ((GtkImageListBackend)_pictures).Pixbuf(image);
            if (picture != null)
            {
                gtk_tool_button_set_icon_widget(item, gtk_image_new_from_pixbuf(picture));
            }
        }

        int index = (int)_items.Count;
        gtk_toolbar_insert(widget, item, -1);
        gtk_widget_show_all(item);
        _items.Add(item);
        _toggles.Add(kind == ToolButtonKind.Toggle);

        if (kind != ToolButtonKind.Separator)
        {
            ConnectPlain(item, "clicked", () =>
            {
                // **A toggle set by the program emits this too**, which is the
                // difference between the two backends and was a crash rather
                // than a cosmetic bug: `gtk_toggle_tool_button_set_active`
                // raises `clicked` synchronously, so `BoldButton.Checked =
                // true` in a form's constructor ran the button's own handler
                // before the rest of the form existed. Windows does not --
                // `TB_CHECKBUTTON` notifies nobody -- so a program written and
                // tested there met it for the first time on Linux.
                //
                // `this.Echoing`, never the bare field: a lambda captures a
                // bare member read by value when it is made, so the field form
                // tests what the flag said at connection time and guards
                // nothing at all. See `GtkPeer.Echoing`.
                if (this.Echoing)
                    return;
                var target2 = Owner;
                if (target2 != null)
                {
                    ((IControlNotify)target2).OnPlatformToolClicked(index);
                }
            });
        }
        return index;
    }

    /// A GTK tool item is a widget, so what the platform calls one is its
    /// address -- where Win32 has a command id because its buttons share a
    /// window and nothing else tells them apart.
    public nuint ButtonId(int index)
    {
        if (index < 0 || (nuint)index >= _items.Count)
            return 0u;
        return (nuint)(void*)_items[(nuint)index];
    }

    public void SetButtonEnabled(int index, bool enabled)
    {
        if (index < 0 || (nuint)index >= _items.Count)
            return;
        gtk_widget_set_sensitive(_items[(nuint)index], enabled ? 1 : 0);
    }

    public void SetButtonChecked(int index, bool checked)
    {
        if (index < 0 || (nuint)index >= _items.Count)
            return;
        if (!_toggles[(nuint)index])
            return;

        // Quiet, because this is the program speaking and not the user. The
        // click that comes back out of this call is the one the handler above
        // drops.
        Echo(true);
        gtk_toggle_tool_button_set_active(_items[(nuint)index], checked ? 1 : 0);
        Echo(false);
    }

    public bool GetButtonChecked(int index)
    {
        if (index < 0 || (nuint)index >= _items.Count)
            return false;
        if (!_toggles[(nuint)index])
            return false;
        return gtk_toggle_tool_button_get_active(_items[(nuint)index]) != 0;
    }

    public void SetImages(IImageListBackend images)
    {
        _pictures = (GtkImageListBackend)images;
    }

    public void SetTextVisible(bool visible)
    {
        _captions = visible;
        gtk_toolbar_set_style(widget, visible ? GTK_TOOLBAR_BOTH : GTK_TOOLBAR_ICONS);
    }

    /// A toolbar in a `GtkFixed` has already been given its size, so fitting
    /// it to its buttons means asking what it would like and taking that --
    /// which is what `PreferredSize` answers.
    public void ResizeToFit()
    {
        var wanted = PreferredSize;
        gtk_widget_set_size_request(widget, bounds.Width, wanted.Height);
    }

    /// No, and for the reason the menus say no: a GTK toolbar is drawn by the
    /// desktop theme, and a program painting Office XP over it would be the
    /// one application on the machine that ignored the user's choice of how
    /// their desktop looks.
    ///
    /// The refusal is the whole point of the question being asked. A program
    /// sets a renderer on both platforms and this one goes on being a GTK
    /// toolbar, rather than the program having to know where it is running.
    public bool SetOwnerDrawn(bool drawn) => false;
}

// ==================================================================== timer

/// A GLib timeout, which is the whole of a timer here.
///
/// **There is no window and no `WM_TIMER`.** A GTK timer is a source on the
/// main loop, so it runs on whichever thread is running the loop -- which is
/// the thread that owns the widgets, which is what a control expects.
public class GtkTimerPeer : ITimerPeer
{
    weak ITimerNotify? target;
    gulong _source;

    public GtkTimerPeer(ITimerNotify owner)
    {
        target = owner;
        _source = 0u;
    }

    ~GtkTimerPeer() { Stop(); }

    public void Start(int milliseconds)
    {
        Stop();
        if (milliseconds <= 0)
            return;

        // Through a method, for the reason every handler in this backend is:
        // a lambda captures a member read by value, and `target` is a member.
        _source = Tick(milliseconds, () => { return Fire(); });
    }

    /// Reports a tick, and false once there is nobody to report to -- which
    /// is what takes the source off the loop when the control has gone.
    bool Fire()
    {
        ITimerNotify? owner = target;
        if (owner == null)
            return false;
        ((ITimerNotify)owner).OnPlatformTick();
        return true;
    }

    public void Stop()
    {
        if (_source == 0u)
            return;
        g_source_remove((guint)_source);
        _source = 0u;
    }
}

// ================================================================== custom

/// How long the caret spends showing, and then hiding, in milliseconds.
///
/// GTK's own rate is the `gtk-cursor-blink-time` setting, which is the whole
/// cycle rather than a half of it and which this does not read yet. 530 is
/// Windows's default half-cycle, and a caret agreeing with the other platform
/// is a better wrong answer than one agreeing with nothing.
const int BlinkHalfCycle = 530;

/// A control the program draws every pixel of, and that takes the keyboard.
///
/// **Three widgets, and each earns its place.** A frame on the outside, so that
/// `SetBorder` has something to set, exactly as `GtkPanelPeer` does. An event
/// box inside it, because a `GtkFixed` is windowless and a windowless widget
/// can be given neither the input events nor the focus -- which is the whole
/// specification of this control. A fixed inside that, so it is a container
/// like every other one here and the scroll bars a drawn control needs are
/// ordinary children.
///
/// **The draw handler answers false.** For a container, GTK's own `draw` runs
/// last and is what draws the children; answering true would stop it, and every
/// child of this control would silently never appear. So this paints the
/// background and the caret, says it has not finished, and the children land on
/// top -- which is also the order that puts a scroll bar over the text rather
/// than under it.
public class GtkCustomPeer : GtkContainerPeer, ICustomPeer
{
    /// Where the caret is and how big, or empty for a control with none.
    FRect _caret;
    /// Which half of the blink it is in. GTK has no caret of its own -- unlike
    /// Windows, where the system owns one and blinks it -- so the phase, the
    /// timer and the drawing are all this peer's.
    bool _blinkOn;
    bool _blinking;
    bool _focusable;

    public GtkCustomPeer(IControlNotify owner)
    {
        base(gtk_frame_new(null), owner, gtk_fixed_new());

        // **The fixed is the drawing surface, and it needs a window to be one.**
        //
        // A `GtkFixed` is windowless by default: it occupies a region of its
        // parent's window, so it can be given neither the input events nor the
        // focus. The first version put an event box in between to get those --
        // and an event box renders its own background, on every frame, over
        // everything the program had just drawn. `OnPaint` was being called and
        // nothing appeared, which is the worst shape a bug can have.
        //
        // A `GtkFixed` renders no background at all. So the fix is not another
        // widget but a flag: the fixed gets a window of its own and becomes the
        // thing that is clicked, focused and painted. Lazarus's GTK3 widgetset
        // does exactly this behind every custom control.
        gtk_widget_set_has_window(content, 1);

        gtk_container_add(widget, content);
        gtk_widget_show(content);
        gtk_frame_set_shadow_type(widget, GTK_SHADOW_NONE);

        SetInner(content);

        _caret = Area(0, 0, 0, 0);
        _blinkOn = true;
        _blinking = false;
        _focusable = true;
        gtk_widget_set_can_focus(content, 1);

        // Through methods rather than reading the fields, for the reason every
        // handler in this backend is: a lambda captures a bare member read by
        // value at the moment it is made.
        ConnectEvent(content, "draw", (sender, carried) => { return Painted(carried); });

        // GTK does not focus a clicked widget either; only an entry and a
        // button do, from their own handlers.
        ConnectEvent(content, "button-press-event", (sender, carried) =>
        {
            TakeFocus();
            return false;
        });

        ConnectEvent(content, "focus-in-event",  (sender, carried) => { Blink(true);  return false; });
        ConnectEvent(content, "focus-out-event", (sender, carried) => { Blink(false); return false; });
    }

    public void SetBorder(ControlBorder border)
    {
        if (border == ControlBorder.Single)
        {
            gtk_frame_set_shadow_type(widget, GTK_SHADOW_IN);
        }
        else if (border == ControlBorder.Sunken)
        {
            gtk_frame_set_shadow_type(widget, GTK_SHADOW_ETCHED_IN);
        }
        else
        {
            gtk_frame_set_shadow_type(widget, GTK_SHADOW_NONE);
        }
    }

    public void SetFocusable(bool wanted)
    {
        _focusable = wanted;
        gtk_widget_set_can_focus(content, wanted ? 1 : 0);
    }

    /// Remembered, and shown from the next paint. The phase is restarted so
    /// that a caret being moved is solid while it moves -- a caret that blinked
    /// on its own schedule would be invisible for half of every keystroke.
    public void SetCaret(FRect place)
    {
        // See `CustomPeer.SetCaret` on Win32: a control that positions its
        // caret while painting sets it on every paint, and here a repaint is
        // exactly what this asks for -- so an unchanged caret has to ask for
        // nothing, or the widget paints for ever.
        if (place.X == _caret.X && place.Y == _caret.Y
            && place.Width == _caret.Width && place.Height == _caret.Height)
        {
            return;
        }

        _caret = place;
        _blinkOn = true;
        if (!place.IsEmpty && Focused)
            Blink(true);
        gtk_widget_queue_draw(content);
    }

    bool Focused => gtk_widget_has_focus(content) != 0;

    /// Not `Take`. An unqualified `Take(...)` finds the standard library's
    /// generic sequence operation of that name, and the error is about
    /// inferring a type argument rather than about the focus.
    void TakeFocus()
    {
        if (!_focusable)
            return;
        gtk_widget_grab_focus(content);
    }

    /// Starts or stops the blink.
    ///
    /// The source is not held and never removed: `Phase` answers false as soon
    /// as the control is unfocused or gone, and a GLib source that answers
    /// false takes itself off the loop. Holding the tag would mean removing it
    /// from a destructor that may run after the loop has stopped.
    void Blink(bool on)
    {
        _blinkOn = true;
        if (!on)
        {
            _blinking = false;
            gtk_widget_queue_draw(content);
            return;
        }
        if (_blinking)
            return;
        _blinking = true;
        Tick(BlinkHalfCycle, () => { return this.Phase; });
    }

    bool Phase
    {
        get
        {
            if (Owner == null || !_blinking || !Focused)
            {
                _blinking = false;
                return false;
            }
            _blinkOn = !_blinkOn;
            gtk_widget_queue_draw(content);
            return true;
        }
    }

    /// **False, so that GTK's own handler still runs.** For a `GtkFixed` that
    /// handler draws the children and nothing else -- no background of its own
    /// -- so the controls on this one land on top of what the program drew,
    /// which is the order wanted. Answering true would paint over every scroll
    /// bar and button placed on the control.
    bool Painted(gpointer carried)
    {
        var owner = Owner;
        if (owner == null)
            return false;

        ClipToSelf((cairo_t*)carried, content);

        var surface = new GtkGraphicsBackend(carried);
        ((IControlNotify)owner).OnPlatformPaint(new Graphics(surface));

        if (!_caret.IsEmpty && _blinkOn && Focused)
            DrawCaret((cairo_t*)carried);

        cairo_restore((cairo_t*)carried);
        return false;
    }

    /// The caret, in whatever colour the theme says text is.
    ///
    /// Asked rather than assumed, because a caret is the one thing on a drawn
    /// control that has to be visible without knowing what was drawn under it,
    /// and black on a dark theme is not.
    void DrawCaret(cairo_t* context)
    {
        GdkRGBA ink;
        gtk_style_context_get_color(gtk_widget_get_style_context(content),
                                    GTK_STATE_FLAG_NORMAL, &ink);
        cairo_set_source_rgb(context, ink.Red, ink.Green, ink.Blue);
        cairo_rectangle(context, (gdouble)_caret.X, (gdouble)_caret.Y,
                        (gdouble)_caret.Width, (gdouble)_caret.Height);
        cairo_fill(context);
    }
}

#endif
