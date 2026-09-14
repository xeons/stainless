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

// The controls that hold other controls, and the scroll bar.
//
// A `Panel` and a `GroupBox` are the two ways of grouping: one invisible and
// one with a frame and a caption. Both matter beyond their appearance, because
// a parent is what decides a radio button's group and what a docked child docks
// inside -- so `Panel` is the answer to "two sets of radio buttons on one form"
// as much as it is to "a toolbar strip along the top".
module Forms;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;

// ==================================================================== panel

/// A plain container, optionally with a border.
///
/// ```
/// var strip = new Panel(this);
/// strip.Dock = DockStyle.Top;
/// strip.Height = 32;
/// ```
public class Panel : WindowedControl {
    IPanelPeer native;
    ControlBorder edging;

    public Panel(WindowedControl parent) {
        base(parent);
        edging = ControlBorder.None;
        native = WidgetSet.Current.CreatePanel(this, ParentPeer());
        AttachContainerPeer(native);
    }

    /// The frame drawn around it.
    public ControlBorder Border {
        get => edging;
        set {
            edging = value;
            native.SetBorder(value);
            PerformLayout();
        }
    }
}

// ================================================================= group box

/// A frame with a caption, that other controls sit inside.
///
/// Its client area is inset by the frame and the caption, which the platform
/// works out -- so a control docked to the top of a group box lands under the
/// caption rather than through it.
public class GroupBox : WindowedControl {
    IGroupPeer native;

    public GroupBox(WindowedControl parent) {
        base(parent);
        native = WidgetSet.Current.CreateGroup(this, ParentPeer());
        AttachContainerPeer(native);
    }

    /// The caption across the top of the frame.
    public String Caption {
        get => Text;
        set { Text = value; }
    }
}

// =============================================================== scroll bar

/// A scroll bar standing on its own.
///
/// **Not what a scrolling container uses.** A `ScrollBox` -- which does not
/// exist yet -- would use the scroll bars the platform attaches to a window,
/// which are a different thing with a different API. This is the control you
/// place on a form when the thing being scrolled is yours.
public class ScrollBar : WindowedControl {
    IScrollBarPeer native;
    bool vertical;
    int  minimum;
    int  maximum;
    int  page;

    public ScrollBar(WindowedControl parent, bool vertical) {
        base(parent);
        this.vertical = vertical;
        minimum = 0;
        maximum = 100;
        page = 10;
        native = WidgetSet.Current.CreateScrollBar(this, ParentPeer(), vertical);
        AttachPeer(native);
        native.SetRange(minimum, maximum, page);
    }

    /// Whether it scrolls up and down rather than left and right.
    public bool IsVertical => vertical;

    public int Minimum {
        get => minimum;
        set {
            minimum = value;
            native.SetRange(minimum, maximum, page);
        }
    }

    public int Maximum {
        get => maximum;
        set {
            maximum = value;
            native.SetRange(minimum, maximum, page);
        }
    }

    /// How much one page-down moves by, and how large the thumb is drawn -- the
    /// two are the same number on every platform, because the thumb's size is
    /// what shows how much of the whole is visible.
    public int PageSize {
        get => page;
        set {
            page = value;
            native.SetRange(minimum, maximum, page);
        }
    }

    /// Where the thumb is.
    public int Value {
        get => native.GetValue();
        set { native.SetValue(value); }
    }

    /// The thumb moved, whoever moved it.
    public event EventHandler ValueChanged;

    protected virtual void OnValueChanged() { ValueChanged(this); }

    public override void OnPlatformValueChanged() { OnValueChanged(); }
}

// ============================================================ custom control

/// A control the program draws every pixel of, and that takes the keyboard.
///
/// ```
/// public class Grid : CustomControl {
///     public Grid(WindowedControl parent) {
///         base(parent);
///         Border = ControlBorder.Sunken;
///     }
///
///     protected override void OnPaint(PaintEventArgs args) {
///         args.Graphics.Clear(BackColor);
///         args.Graphics.DrawString("cell", Font, ForeColor, 4, 4);
///     }
///
///     protected override void OnKeyDown(KeyEventArgs args) {
///         if (args.Key == Key.Down) { Invalidate(); }
///     }
/// }
/// ```
///
/// **`PaintBox` is the one to reach for first.** A `PaintBox` is a
/// `GraphicControl`: it costs nothing but an object, its parent draws it, and
/// for anything that only displays -- a chart, a gauge, a preview -- that is
/// the right trade. What it cannot do is take the focus, because it has no
/// window to give the focus to, so no keystroke ever reaches one. This is the
/// other half: a real window of its own, which is what the keyboard, a caret
/// and a scroll bar of its own all need.
///
/// **It draws its whole client area, and nothing else does.** The platform is
/// told not to erase the background, so a paint handler that does not cover
/// every pixel shows whatever the buffer held. `Clear` on the first line is the
/// usual answer. What that buys is a control drawn into an off-screen buffer
/// and copied over in one go, which is the difference between a caret blinking
/// over text and the text blinking with it.
///
/// **A container, like a `Panel`.** Anything may be put inside one, and the
/// children are drawn over what the control painted -- which is the order a
/// scroll bar beside its own content needs.
public class CustomControl : WindowedControl {
    ICustomPeer   native;
    ControlBorder edging;
    Rectangle     insertion;
    bool          takesFocus;

    public CustomControl(WindowedControl parent) {
        base(parent);
        edging = ControlBorder.None;
        insertion = Rectangle.Empty;
        takesFocus = true;
        native = WidgetSet.Current.CreateCustom(this, ParentPeer());
        AttachContainerPeer(native);
    }

    /// The frame drawn around it.
    public ControlBorder Border {
        get => edging;
        set {
            edging = value;
            native.SetBorder(value);
            PerformLayout();
        }
    }

    /// Whether clicking it and tabbing to it give it the keyboard.
    ///
    /// A drawn control that only displays says false and leaves the tab order
    /// alone -- which is a different thing from one that takes the focus and
    /// happens to handle no keys, because the second still takes the focus away
    /// from whatever had it.
    public bool Focusable {
        get => takesFocus;
        set {
            takesFocus = value;
            native.SetFocusable(value);
        }
    }

    /// Where the insertion point is and how big, in this control's own
    /// coordinates. `Rectangle.Empty` -- the default -- for a control with no
    /// caret at all.
    ///
    /// **Set it, and stop thinking about it.** The platform owns the blink and
    /// owns the appearing and disappearing as the focus moves, so a control
    /// that has just moved its caret has finished: there is no timer to start,
    /// nothing to hide before painting and nothing to put back after.
    public Rectangle Caret {
        get => insertion;
        set {
            insertion = value;
            native.SetCaret(value);
        }
    }
}
