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

// The things you press: `Button`, `CheckBox`, `RadioButton`, `ToggleButton` and
// `SpeedButton`.
//
// The LCL calls the shared base `TButtonControl` and hangs `TCustomButton`,
// `TCustomCheckBox` and `TToggleBox` off it. C# calls it `ButtonBase` and hangs
// `Button`, `CheckBox` and `RadioButton` off it, which is the same shape with
// the names a C# reader expects -- and the `TCustom`/`T` pair that the LCL uses
// to separate "the machinery" from "the published version" is exactly C#'s
// `XBase`/`X` pair, so the translation is one for one.
//
// **Two of the five are not that shape**, and both for the platform's reasons.
// `TBitBtn` is folded into `Button`, because a picture on a button is a
// property in C# and a subclass only in the LCL. `SpeedButton` cannot be:
// `TSpeedButton` is a `TGraphicControl` -- no window, drawn by its parent, and
// so nothing a `ButtonBase` could descend from.
module Forms;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;
#if FORMS_REFLECT
import Standard.Reflection;
#endif

// =============================================================== button base

/// What a button, a check box and a radio button have in common.
///
/// Abstract, because pressing is all it knows how to do and there is no such
/// widget on any platform.
public abstract class ButtonBase : WindowedControl
{
    protected ButtonBase(WindowedControl parent) => base(parent);

    /// The button's caption, which is what `Text` already means.
    public String Caption
    {
        get => Text;
        set => Text = value;
    }

    public override Size PreferredSize
    {
        get
        {
            var peer = Peer;
            if (peer == null)
                return Size.Empty;
            return ((IControlPeer)peer).PreferredSize;
        }
    }

    /// Raises `Click` as though the user had pressed it.
    ///
    /// C# has this on `ButtonBase` for the same two reasons: a default button
    /// pressed by Enter elsewhere on the form, and a test with nobody in front
    /// of it. Raising the event rather than telling the platform to draw a
    /// press is deliberate -- what a caller wants is the effect, not the
    /// animation.
    public void PerformClick() => OnClick();
}

// ==================================================================== button

/// An ordinary push button.
///
/// ```
/// var save = new Button(this);
/// save.Text = "Save";
/// save.SetBounds(10, 10, 90, 26);
/// save.Image = disk;
/// save.Click += this.OnSave;
/// ```
///
/// **`TBitBtn` is this class.** The LCL gives a button with a picture a class of
/// its own, because `TButton` is a Windows `BUTTON` and a picture on one needed
/// owner drawing when `TBitBtn` was written. C# does not: `ButtonBase.Image`
/// and `ImageAlign` are on every button, and a button with no picture is the
/// ordinary case rather than a different class. That is the better of the two
/// and it costs nothing here -- a `BUTTON` with no image list and a `GtkButton`
/// with no image behave exactly as they did before this existed.
///
/// `TBitBtn.Kind` -- the `bkOK`/`bkCancel` family that fills in a caption and a
/// stock glyph -- is not here. It is one table of translated strings and stock
/// icon names serving one caller, and that caller is `ButtonPanel`, which now
/// holds the table itself.
#if FORMS_REFLECT
[Reflect]
#endif
public class Button : ButtonBase
{
    IPushButtonPeer _native;
    Bitmap? _image;
    ImageAlignment _imageAlign;
    int _imageSpacing;

    public Button(WindowedControl parent)
    {
        base(parent);
        _image = null;
        _imageAlign = ImageAlignment.Left;
        _imageSpacing = 4;
        _native = WidgetSet.Current.CreateButton(this, ParentPeer);
        AttachPeer(_native);
    }

    /// Whether Enter presses this button. At most one per window: setting it
    /// clears it on every other button of the form, so the first need not be
    /// unset.
    public bool IsDefault
    {
        get => _isDefault;
        set
        {
            if (value)
            {
                var form = FindForm();
                if (form != null)
                    ClearDefaultButtonIn((WindowedControl)form);
            }
            _isDefault = value;
            _native.SetDefault(value);
        }
    }

    bool _isDefault;

    /// Clears `IsDefault` on every button under `holder` but this one.
    void ClearDefaultButtonIn(WindowedControl holder)
    {
        foreach (var child in holder.Controls)
        {
            if (child is Button other)
            {
                if (other != this && other._isDefault)
                    other.IsDefault = false;
            }
            if (child is WindowedControl inner)
                ClearDefaultButtonIn(inner);
        }
    }

    /// The picture drawn beside the caption, or null for none.
    ///
    /// **The button does not own it.** A `Bitmap` may be on ten buttons at once
    /// and is released when the last reference to it goes, which is what ARC is
    /// for; what the peer keeps is the platform's own copy of it.
    public Bitmap? Image
    {
        get => _image;
        set
        {
            _image = value;
            _native.SetImage(value == null ? null : ((Bitmap)value).Backend);
        }
    }

    /// Which side of the caption the picture sits on.
    public ImageAlignment ImageAlign
    {
        get => _imageAlign;
        set
        {
            _imageAlign = value;
            _native.SetImageAlign(value);
        }
    }

    /// Pixels between the picture and the caption. `TBitBtn.Spacing`, which
    /// defaults to 4 there and here.
    public int ImageSpacing
    {
        get => _imageSpacing;
        set
        {
            _imageSpacing = value;
            _native.SetImageSpacing(value);
        }
    }
}

// ================================================================= check box

/// A box that is ticked or not.
///
/// **There is no third state.** `TCheckBox` has `cbGrayed` and C# has
/// `CheckState.Indeterminate`, and both exist for a property grid showing a
/// value that differs across a selection. Nothing here needs one yet, and a
/// two-state box whose property is a `bool` is a much better thing to use than
/// a three-state one whose property is an enum that is usually two of three.
#if FORMS_REFLECT
[Reflect]
#endif
public class CheckBox : ButtonBase
{
    ICheckPeer _native;

    public CheckBox(WindowedControl parent)
    {
        base(parent);
        _native = WidgetSet.Current.CreateCheck(this, ParentPeer, CheckKind.Check);
        AttachPeer(_native);
    }

    /// For `RadioButton` and `ToggleButton`, each of which is the same widget
    /// with one style bit changed.
    protected CheckBox(WindowedControl parent, CheckKind kind)
    {
        base(parent);
        _native = WidgetSet.Current.CreateCheck(this, ParentPeer, kind);
        AttachPeer(_native);
    }

    /// Whether it is ticked.
    ///
    /// Read from the platform rather than from a field, because the platform
    /// toggles it when the user clicks and a field would be one click behind.
    ///
    /// **Setting it raises no `CheckedChanged`**, and both backends agree about
    /// that for the same reason: `BM_SETCHECK` sends no `BN_CLICKED`, and the
    /// GTK peer suppresses the `toggled` its own call caused. C# raises the
    /// event here; this does not, because the only listener that could learn
    /// anything from it is one the program has just told. What the event
    /// reports is the *user* changing the tick, which is the question a handler
    /// is written to answer.
    ///
    /// Virtual because a radio button has to clear its siblings when it is
    /// ticked, and a check box must not.
    public virtual bool Checked
    {
        get => _native.GetChecked();
        set => _native.SetChecked(value);
    }

    /// Sets the tick without telling anything else, for a derived class that
    /// has more to do around it.
    protected void SetCheckedOnly(bool ticked) => _native.SetChecked(ticked);

    /// The user changed the tick. Setting `Checked` raises nothing.
    public event EventHandler CheckedChanged;

    protected virtual void OnCheckedChanged() => CheckedChanged(this);

    /// The platform reports a tick as a change of value, which for this control
    /// means the tick and not the caption.
    public override void OnPlatformValueChanged() => OnCheckedChanged();
}

// ============================================================== radio button

/// One of a set of choices, of which the platform keeps exactly one chosen.
///
/// **Grouping is by parent, not by a property.** Every radio button sharing a
/// parent is one group, which is Windows' rule, GTK's rule and the LCL's rule,
/// and is why a form with two sets of choices puts each set in its own `Panel`
/// or `GroupBox`. A `GroupName` property would have to fight the platform for
/// the behaviour it already has.
#if FORMS_REFLECT
[Reflect]
#endif
public class RadioButton : CheckBox
{
    public RadioButton(WindowedControl parent) => base(parent, CheckKind.Radio);

    /// Ticking one unticks the rest of its group.
    ///
    /// **Windows does not do this for a programmatic set.** `BS_AUTORADIOBUTTON`
    /// clears the other buttons when the *user* clicks one; `BM_SETCHECK`
    /// clears nothing, so a program that ticked one by hand ended up with two
    /// ticked and a group whose selected index was whichever came first. C#
    /// does exactly this in `RadioButton.Checked`, for the same reason.
    public override bool Checked
    {
        get => base.Checked;
        set
        {
            SetCheckedOnly(value);
            if (!value)
                return;
            UncheckSiblings();
        }
    }

    /// Unticks every other radio button with the same parent, which is what
    /// makes a group a group on every platform.
    void UncheckSiblings()
    {
        var parent = Parent;
        if (parent == null)
            return;
        foreach (var sibling in ((WindowedControl)parent).Controls)
        {
            if (sibling == this)
                continue;
            if (sibling is RadioButton other)
                other.SetCheckedOnly(false);
        }
    }
}

// ============================================================ toggle button

/// A check box that stays pressed in instead of ticking.
///
/// **A check box, not a button, and that is the whole design.** `TToggleBox`
/// descends from `TCustomCheckBox`; Windows draws one with `BS_PUSHLIKE` on top
/// of `BS_AUTOCHECKBOX`; GTK's `GtkCheckButton` descends from
/// `GtkToggleButton`, so dropping the indicator is dropping a subclass rather
/// than changing a widget. All three say the same thing: what is on the screen
/// looks like a button and what it *is* is a two-state box, so `Checked`,
/// `CheckedChanged` and everything else here mean exactly what they mean on a
/// check box.
///
/// WPF and Avalonia call this `ToggleButton`; WinForms spells it
/// `CheckBox.Appearance = Appearance.Button`, which is not a type name to
/// borrow.
///
/// ```
/// var bold = new ToggleButton(this);
/// bold.Text = "B";
/// bold.SetBounds(8, 8, 32, 26);
/// bold.CheckedChanged += this.OnBoldChanged;
/// ```
///
/// A group of these is *not* a radio group: nothing unticks the others, which
/// is what `RadioButton` is for. A toolbar's mutually exclusive buttons are
/// `ToolButton` toggles and the program clears them, as they are in the LCL.
#if FORMS_REFLECT
[Reflect]
#endif
public class ToggleButton : CheckBox
{
    public ToggleButton(WindowedControl parent) => base(parent, CheckKind.Toggle);
}

// ============================================================= speed button

/// What a `SpeedButton` looks like at this moment.
///
/// `Hot` is the one a Windows 95 button did not have: the pointer is over it
/// and nothing has been pressed, which is how a flat button says it is a button
/// at all. `TButtonState` has a fifth, `bsExclusive`, for the down button of a
/// group -- which is drawn exactly as `Down` is, so it is not a state here.
public enum ButtonState { Up, Down, Hot, Disabled }

/// A button with no window, drawn by its parent.
///
/// **This is the one button that could not be a `ButtonBase`.**
/// `TSpeedButton` is a `TGraphicControl`: it has no handle, no place in the tab
/// order and no keyboard, and its parent draws it inside a layer. That is what
/// makes a palette of twenty of them cost twenty objects instead of twenty
/// windows, and it is the whole reason the class exists beside `Button`.
///
/// What it buys over a `Button`, besides the cost: it can be `Flat`, and it can
/// stay `Down`. A set of them sharing a `GroupIndex` behaves as radio buttons
/// do -- pressing one raises the rest -- which is how every toolbar built
/// before `TToolBar` existed was made, and still the easiest way to build a
/// palette.
///
/// ```
/// var pen = new SpeedButton(this);
/// pen.Image = penIcon;
/// pen.SetBounds(4, 4, 28, 28);
/// pen.Flat = true;
/// pen.GroupIndex = 1;
/// pen.Down = true;
/// ```
public class SpeedButton : GraphicControl
{
    Bitmap? _image;
    ImageAlignment _imageAlign;
    int _margin;
    int _spacing;
    bool _flat;
    bool _down;
    bool _allowAllUp;
    int _groupIndex;
    bool _showCaption;
    bool _hot;
    bool _pressing;
    HorizontalAlignment _alignment;

    public SpeedButton(WindowedControl parent)
    {
        base(parent);
        _image = null;
        _imageAlign = ImageAlignment.Left;
        _margin = -1;
        _spacing = 4;
        _flat = false;
        _down = false;
        _allowAllUp = false;
        _groupIndex = 0;
        _showCaption = true;
        _hot = false;
        _pressing = false;
        _alignment = HorizontalAlignment.Center;
        Width = 23;
        Height = 22;
    }

    /// The picture, or null for a button that is only a caption.
    public Bitmap? Image
    {
        get => _image;
        set
        {
            _image = value;
            Invalidate();
        }
    }

    /// Which side of the caption the picture sits on.
    public ImageAlignment ImageAlign
    {
        get => _imageAlign;
        set
        {
            _imageAlign = value;
            Invalidate();
        }
    }

    /// Pixels between the edge and the content, or -1 -- the default -- to
    /// centre the content in whatever room there is.
    ///
    /// `TSpeedButton.Margin` means exactly this, and the -1 is why: a button
    /// whose picture should sit in the middle is the common case, and a button
    /// whose picture should sit four pixels from the left is the rare one.
    public int Margin
    {
        get => _margin;
        set
        {
            _margin = value;
            Invalidate();
        }
    }

    /// Pixels between the picture and the caption.
    public int Spacing
    {
        get => _spacing;
        set
        {
            _spacing = value;
            Invalidate();
        }
    }

    /// Whether it draws no border until the pointer is over it.
    ///
    /// What a toolbar button has looked like since Office 97, and what
    /// `TSpeedButton.Flat` turns on.
    public bool Flat
    {
        get => _flat;
        set
        {
            _flat = value;
            Invalidate();
        }
    }

    /// Whether it is pressed in and staying there.
    ///
    /// Setting this on a button with a `GroupIndex` raises the others in its
    /// group, exactly as ticking a radio button unticks its siblings -- and for
    /// the same reason, which is that a group with two down is not a group.
    ///
    /// As in `TSpeedButton.SetDown`, a button with no group is never down, and
    /// the down button of a group that does not `AllowAllUp` is raised only by
    /// pressing another.
    public bool Down
    {
        get => _down;
        set
        {
            bool wanted = _groupIndex != 0 && value;
            if (wanted == _down)
                return;
            if (_down && !_allowAllUp)
                return;
            if (wanted)
                RaiseGroupSiblings();
            _down = wanted;
            Invalidate();
        }
    }

    /// Which set of buttons this one belongs to. Zero -- the default -- is a
    /// button that does not stay down at all.
    public int GroupIndex
    {
        get => _groupIndex;
        set
        {
            _groupIndex = value;
            Invalidate();
        }
    }

    /// Whether clicking the one that is down raises it, leaving the group with
    /// nothing chosen. False, as in the LCL, because a palette usually has to
    /// have a tool selected.
    public bool AllowAllUp
    {
        get => _allowAllUp;
        set => _allowAllUp = value;
    }

    /// Whether the caption is drawn at all. A palette of icons sets this false
    /// and keeps its `Text` for the tooltip it will one day have.
    public bool ShowCaption
    {
        get => _showCaption;
        set
        {
            _showCaption = value;
            Invalidate();
        }
    }

    /// Where the caption sits across the room left for it.
    public HorizontalAlignment Alignment
    {
        get => _alignment;
        set
        {
            _alignment = value;
            Invalidate();
        }
    }

    /// What it would be drawn as right now.
    public ButtonState State
    {
        get
        {
            if (!Enabled)
                return ButtonState.Disabled;
            if (_down || _pressing)
                return ButtonState.Down;
            if (_hot)
                return ButtonState.Hot;
            return ButtonState.Up;
        }
    }

    /// Raises every other button of this one's group.
    void RaiseGroupSiblings()
    {
        var parent = Parent;
        if (parent == null)
            return;
        foreach (var sibling in ((WindowedControl)parent).Controls)
        {
            if (sibling == this)
                continue;
            if (sibling is SpeedButton other)
            {
                if (other.GroupIndex != _groupIndex)
                    continue;
                if (!other.Down)
                    continue;
                other.SetDownOnly(false);
            }
        }
    }

    /// Raises or presses without touching the group, for a sibling being raised
    /// by the one that was just pressed.
    void SetDownOnly(bool pressed)
    {
        _down = pressed;
        Invalidate();
    }

    // ------------------------------------------------------------- the mouse
    //
    // A graphic control has no window, so entering and leaving it are the
    // parent's to notice -- which it does by hit-testing, and which is the same
    // machinery a `Splitter` runs on.

    protected override void OnMouseEnter()
    {
        base.OnMouseEnter();
        _hot = true;
        Invalidate();
    }

    protected override void OnMouseLeave()
    {
        base.OnMouseLeave();
        _hot = false;
        // A press abandoned by dragging off the button is not a click, so the
        // pressed look goes with it and `OnMouseUp` finds nothing to do.
        _pressing = false;
        Invalidate();
    }

    protected override void OnMouseDown(MouseEventArgs args)
    {
        base.OnMouseDown(args);
        if (args.Button != MouseButton.Left)
            return;
        if (!Enabled)
            return;
        _pressing = true;
        CaptureMouse(true);
        Invalidate();
    }

    protected override void OnMouseUp(MouseEventArgs args)
    {
        base.OnMouseUp(args);
        if (!_pressing)
            return;
        _pressing = false;
        CaptureMouse(false);

        bool inside = args.X >= 0 && args.Y >= 0 && args.X < Width && args.Y < Height;
        if (inside)
            ToggleInGroup();
        Invalidate();
        if (inside)
            OnClick();
    }

    /// Raises `Click` as though it had been pressed, and moves the group with
    /// it. What `ButtonBase.PerformClick` is, on the one button that is not a
    /// `ButtonBase`.
    public void PerformClick()
    {
        ToggleInGroup();
        Invalidate();
        OnClick();
    }

    /// What a completed press does to a grouped button: presses it and raises
    /// the rest, or -- if it was the one down and the group may be empty --
    /// raises it. A button with no group does nothing here.
    void ToggleInGroup()
    {
        if (_groupIndex == 0)
            return;
        if (_down)
        {
            if (_allowAllUp)
                _down = false;
            return;
        }
        RaiseGroupSiblings();
        _down = true;
    }

    // ---------------------------------------------------------- the drawing

    public override Size PreferredSize
    {
        get
        {
            var picture = _image;
            int glyphWide = picture == null ? 0 : ((Bitmap)picture).Width;
            int glyphHigh = picture == null ? 0 : ((Bitmap)picture).Height;

            // **The caption is not measured here**, because measuring needs a
            // surface and there is none outside a paint. This is the picture
            // plus its margins, floored at a Windows button's smallest size,
            // which is what a palette button wants and all
            // `ResizeToPreferredSize` can honestly promise for one that also
            // has text.
            int room = _margin < 0 ? 4 : _margin;
            int wide = glyphWide + room * 2;
            int high = glyphHigh + room * 2;
            if (wide < 23)
                wide = 23;
            if (high < 22)
                high = 22;
            return Size.FromDimensions(wide, high);
        }
    }

    protected override void OnPaint(PaintEventArgs args)
    {
        var surface = args.Graphics;
        var whole = Rectangle.FromBounds(0, 0, Width, Height);
        var state = State;

        // **A flat button that is neither hot nor down draws nothing at all**,
        // which is what lets whatever it sits on show through it. That is the
        // only difference between flat and not, and it is why `Flat` is one
        // test in two places rather than a second paint routine.
        bool face = !_flat || state == ButtonState.Down || state == ButtonState.Hot;
        if (face)
        {
            surface.FillRectangle(new Brush(BackColor), whole);
            DrawEdge(surface, whole, state == ButtonState.Down);
        }

        var picture = _image;
        int glyphWide = picture == null ? 0 : ((Bitmap)picture).Width;
        int glyphHigh = picture == null ? 0 : ((Bitmap)picture).Height;

        var caption = _showCaption ? Text : "";
        var textSize = caption.IsEmpty ? Size.Empty
                                         : surface.MeasureString(caption, Font);
        int gap = (glyphWide > 0 && !caption.IsEmpty) ? _spacing : 0;
        if (gap < 0)
            gap = 0;

        bool sideways = _imageAlign == ImageAlignment.Left
                     || _imageAlign == ImageAlignment.Right;

        // The picture and the caption as one block, sized on the axis they
        // share and on the axis they stack.
        int blockWide = sideways ? glyphWide + gap + textSize.Width
                                 : (glyphWide > textSize.Width ? glyphWide : textSize.Width);
        int blockHigh = sideways ? (glyphHigh > textSize.Height ? glyphHigh : textSize.Height)
                                 : glyphHigh + gap + textSize.Height;

        // A margin of -1 centres that block; anything else pins it that many
        // pixels from the edge the picture is on. `TSpeedButton.Margin` again.
        int startX = (Width - blockWide) / 2;
        int startY = (Height - blockHigh) / 2;
        if (_margin >= 0)
        {
            if (_imageAlign == ImageAlignment.Left)
                startX = _margin;
            if (_imageAlign == ImageAlignment.Right)
                startX = Width - _margin - blockWide;
            if (_imageAlign == ImageAlignment.Top)
                startY = _margin;
            if (_imageAlign == ImageAlignment.Bottom)
                startY = Height - _margin - blockHigh;
        }
        if (startX < 0)
            startX = 0;
        if (startY < 0)
            startY = 0;

        int glyphX = startX;
        int glyphY = startY;
        int textX = startX;
        int textY = startY;

        if (_imageAlign == ImageAlignment.Left)
        {
            glyphY = startY + (blockHigh - glyphHigh) / 2;
            textX = startX + glyphWide + gap;
            textY = startY + (blockHigh - textSize.Height) / 2;
        }
        else if (_imageAlign == ImageAlignment.Right)
        {
            glyphX = startX + textSize.Width + gap;
            glyphY = startY + (blockHigh - glyphHigh) / 2;
            textY = startY + (blockHigh - textSize.Height) / 2;
        }
        else if (_imageAlign == ImageAlignment.Top)
        {
            glyphX = startX + (blockWide - glyphWide) / 2;
            textX = startX + (blockWide - textSize.Width) / 2;
            textY = startY + glyphHigh + gap;
        }
        else
        {
            glyphX = startX + (blockWide - glyphWide) / 2;
            textX = startX + (blockWide - textSize.Width) / 2;
            glyphY = startY + textSize.Height + gap;
        }

        // The caption may be pushed to one end of the room left for it, which
        // is what `Alignment` is for and is only visible on a wide button.
        if (!caption.IsEmpty && sideways && _margin >= 0)
        {
            if (_alignment == HorizontalAlignment.Right)
            {
                textX = Width - _margin - textSize.Width;
            }
            else if (_alignment == HorizontalAlignment.Left
                       && _imageAlign == ImageAlignment.Right)
            {
                textX = _margin;
            }
        }

        // A pressed button's content moves a pixel down and right, which is
        // most of what makes it look pressed.
        if (state == ButtonState.Down)
        {
            glyphX = glyphX + 1; glyphY = glyphY + 1;
            textX = textX + 1;   textY = textY + 1;
        }

        if (picture != null)
        {
            surface.DrawBitmap((Bitmap)picture, Point.FromXY(glyphX, glyphY));
        }

        if (!caption.IsEmpty)
        {
            // A disabled caption is grey, which is the only thing about a
            // disabled speed button that is not the same drawing.
            var ink = Enabled ? ForeColor : SystemColors.GrayText;
            surface.DrawString(caption, Font, ink, textX, textY);
        }

        base.OnPaint(args);
    }

    /// The two-line border every classic button has: highlight along the top
    /// and left, shadow along the bottom and right, and the other way round
    /// when it is pressed. The same two lines a `Bevel` draws, for the same
    /// reason -- there is no theme drawing here yet, and two lines is what a
    /// button looked like before there was.
    void DrawEdge(Graphics surface, Rectangle bounds, bool sunken)
    {
        var first = new Pen(sunken ? SystemColors.ControlDark : SystemColors.ControlLight);
        var second = new Pen(sunken ? SystemColors.ControlLight : SystemColors.ControlDark);

        int right = bounds.Width - 1;
        int low = bounds.Height - 1;
        surface.DrawLine(first, 0, 0, right, 0);
        surface.DrawLine(first, 0, 0, 0, low);
        surface.DrawLine(second, 0, low, right, low);
        surface.DrawLine(second, right, 0, right, low);
    }
}
