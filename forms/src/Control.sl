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

// The control hierarchy: what every visible thing has in common.
//
// This is the LCL's `controls.pp`, which is 4,700 lines and carries docking,
// accessibility, bi-directional text, action links, drag and drop, hints and
// DPI scaling alongside the part every program uses. What is here is that part,
// named as C# names it, with the rest left for later and listed in the package
// README so nobody has to guess whether it was forgotten or declined.
//
// **The split is the LCL's, and it earns its keep.** A `TControl` is anything
// with a position; a `TWinControl` is one the platform knows about. Keeping
// them apart means a `Label` costs no window handle -- which on Windows is a
// kernel object, a message queue entry and a z-order slot -- and a form with
// two hundred labels costs two hundred fewer of each. WinForms has no such
// split and pays for it; WPF has it and calls the halves `UIElement` and
// `FrameworkElement`. Here they are `Control` and `WindowedControl`, because
// what actually distinguishes the second is that it owns a platform window.
//
// **Events are C#'s, both halves of them.** A public `event` anyone may
// subscribe to, and a `protected virtual void On...` that raises it -- so a
// derived class overrides the raiser, decides whether to call `base`, and is
// never tempted to subscribe to its own event. The LCL has only the first half,
// as a published `OnClick` property, which is why every LCL descendant that
// wants to react to its own click has to save and chain the user's handler.
module Forms;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;

// ================================================================ event data

/// What happened with the mouse. A `struct`, because a mouse move raises one of
/// these on every pixel and C#'s class-per-event would allocate on each.
public struct MouseEventArgs
{
    public MouseButton Button;
    public Point Location;
    public ModifierKeys Modifiers;
    /// How far a wheel turned, in notches times 120 -- the number every
    /// platform reports, kept rather than divided because a high-resolution
    /// wheel sends fractions of a notch and dividing would throw them away.
    public int Delta;

    public int X => Location.X;
    public int Y => Location.Y;

    public static MouseEventArgs Of(MouseButton button, Point at,
                                    ModifierKeys modifiers, int delta)
    {
        MouseEventArgs args;
        args.Button = button;
        args.Location = at;
        args.Modifiers = modifiers;
        args.Delta = delta;
        return args;
    }
}

/// What happened with the keyboard.
public struct KeyEventArgs
{
    public Key Key;
    public ModifierKeys Modifiers;

    public bool Shift   => Modifiers.HasFlag(ModifierKeys.Shift);
    public bool Control => Modifiers.HasFlag(ModifierKeys.Control);
    public bool Alt     => Modifiers.HasFlag(ModifierKeys.Alt);

    public static KeyEventArgs Of(Key key, ModifierKeys modifiers)
    {
        KeyEventArgs args;
        args.Key = key;
        args.Modifiers = modifiers;
        return args;
    }
}

/// One character the user typed.
public struct KeyPressEventArgs
{
    public char KeyChar;

    public static KeyPressEventArgs Of(char typed)
    {
        KeyPressEventArgs args;
        args.KeyChar = typed;
        return args;
    }
}

/// Where to paint, and what needs painting.
public struct PaintEventArgs
{
    /// Valid only until the handler returns; see `Graphics`.
    public Graphics Graphics;
    /// The part that needs repainting. A handler may paint more and the rest is
    /// clipped away, so only a handler with expensive drawing needs to look.
    public Rectangle ClipRectangle;

    public static PaintEventArgs Of(Graphics surface, Rectangle clip)
    {
        PaintEventArgs args;
        args.Graphics = surface;
        args.ClipRectangle = clip;
        return args;
    }
}

/// Something is about to happen and a handler may stop it.
///
/// A class rather than a struct, and the only event argument that is one: the
/// handler answers by writing to it, and a struct passed by value would carry
/// the answer nowhere. Which is also why C# makes all of them classes -- it
/// needed this one to be, and made the rest match.
public class CancelEventArgs
{
    /// Set it to true to stop whatever was about to happen.
    public bool Cancel { get; set; }

    public CancelEventArgs() => Cancel = false;
}

// =================================================================== handlers

public closure void EventHandler(Control sender);
public closure void MouseEventHandler(Control sender, MouseEventArgs args);
public closure void KeyEventHandler(Control sender, KeyEventArgs args);
public closure void KeyPressEventHandler(Control sender, KeyPressEventArgs args);
public closure void PaintEventHandler(Control sender, PaintEventArgs args);
public closure void CancelEventHandler(Control sender, CancelEventArgs args);

// ==================================================================== layout

/// Which edge a control sticks to, taking the full width or height of what is
/// left as it does.
///
/// The LCL calls this `TAlign` with members `alTop`, `alClient` and so on; C#
/// calls the same thing `DockStyle` with `Fill` for `alClient`. The names are
/// C#'s and the algorithm is the LCL's, because the LCL's is the one that
/// handles several controls docked to the same edge in a defined order.
public enum DockStyle { None, Top, Bottom, Left, Right, Fill }

/// Which edges of the parent a control keeps a fixed distance from when the
/// parent resizes. Bits, so they combine, and the default is top-left -- which
/// is what makes a control that says nothing simply stay where it was put.
[Flags]
public enum AnchorStyles
{
    None   = 0,
    Top    = 1,
    Bottom = 2,
    Left   = 4,
    Right  = 8,
}

// =================================================================== control

/// Anything with a position, a size and a parent.
///
/// **Abstract, unlike `TControl`.** The LCL lets one be instantiated and it
/// means nothing on screen; every concrete thing here is either a
/// `GraphicControl` its parent paints or a `WindowedControl` the platform
/// paints, and a third option would have nowhere to appear.
///
/// **A control does not own its position.** `Bounds` is what the program asked
/// for; where the control actually is depends on its `Dock`, its `Anchors` and
/// its parent's size, and the parent works that out in `PerformLayout`. Writing
/// `Bounds` on a docked control therefore does nothing lasting, which is the
/// same bargain every layout system makes and is stated here because the LCL
/// silently allows it.
public abstract class Control : IControlNotify
{
    WindowedControl? _owner;
    Rectangle _area;
    DockStyle _docking;
    AnchorStyles _anchoring;
    bool _shown;
    bool _usable;
    String _caption;
    Font? _typeface;
    Color _foreground;
    Color _background;
    bool _backgroundSet;
    bool _foregroundSet;
    /// Set while the platform is telling us something, so that the setter we
    /// call in response does not tell the platform straight back. One flag
    /// replaces the LCL's `csLoading`/`csUpdating` pair for this layer's needs.
    bool _echoing;
    CursorKind _pointer;

    protected Control()
    {
        _owner = null;
        _area = Rectangle.Of(0, 0, 100, 24);
        _docking = DockStyle.None;
        _anchoring = AnchorStyles.Top | AnchorStyles.Left;
        _shown = true;
        _usable = true;
        _caption = "";
        _typeface = null;
        _foreground = Colors.Black;
        _background = Colors.White;
        _backgroundSet = false;
        _foregroundSet = false;
        _echoing = false;
        _pointer = CursorKind.Default;
        Name = "";
    }

    // ------------------------------------------------------------- identity

    /// A name for the control, used by nothing here and by a program that keeps
    /// its own index of them. The LCL's `TComponent.Name` without the
    /// registration, the uniqueness check or the streaming that came with it.
    public String Name { get; set; }

    // -------------------------------------------------------------- parent

    /// What contains this control, or null for a top-level window.
    ///
    /// Read-only: a control is given its parent when it is made and does not
    /// change it. That is narrower than the LCL, where assigning `Parent` moves
    /// a control between forms, and it is narrower on purpose -- on Windows
    /// re-parenting means destroying and re-creating the window for several
    /// control classes, so the operation that looks like an assignment is
    /// really a rebuild, and a program that wants one should say so.
    public WindowedControl? Parent => _owner;

    /// Called by `WindowedControl` when it takes this control in.
    void Adopt(WindowedControl newParent) => _owner = newParent;

    /// The form this control is on, walking up until it finds one.
    public Form? FindForm()
    {
        Control? walk = this;
        while (walk != null)
        {
            var here = (Control)walk;
            if (here is Form form)
                return form;
            walk = here.Parent;
        }
        return null;
    }

    // -------------------------------------------------------------- bounds

    /// Where the control is, relative to its parent's client area.
    public Rectangle Bounds
    {
        get => _area;
        set
        {
            if (_area.Equals(value))
                return;
            var was = _area;
            _area = value;
            ApplyBounds();
            if (!was.Extent.Equals(value.Extent))
                OnResize();
            if (!was.Location.Equals(value.Location))
                OnMove();
            if (this is WindowedControl container)
                container.PerformLayout();
        }
    }

    public int Left   { get => _area.X;      set { Bounds = Rectangle.Of(value, _area.Y, _area.Width, _area.Height); } }
    public int Top    { get => _area.Y;      set { Bounds = Rectangle.Of(_area.X, value, _area.Width, _area.Height); } }
    public int Width  { get => _area.Width;  set { Bounds = Rectangle.Of(_area.X, _area.Y, value, _area.Height); } }
    public int Height { get => _area.Height; set { Bounds = Rectangle.Of(_area.X, _area.Y, _area.Width, value); } }

    /// The far edges, which a layout calculation wants far more often than it
    /// wants the width. Read-only: setting `Right` could mean moving or
    /// resizing, and C# leaves them read-only for the same reason.
    public int Right  => _area.X + _area.Width;
    public int Bottom => _area.Y + _area.Height;

    public Point Location
    {
        get => _area.Location;
        set => Bounds = Rectangle.Of(value.X, value.Y, _area.Width, _area.Height);
    }

    public Size Extent
    {
        get => _area.Extent;
        set => Bounds = Rectangle.Of(_area.X, _area.Y, value.Width, value.Height);
    }

    /// The area inside this control that its own children use. The same as the
    /// bounds at the origin for anything without a frame, and overridden by
    /// what has one.
    public virtual Rectangle ClientBounds =>
        Rectangle.Of(0, 0, _area.Width, _area.Height);

    /// Moves and sizes in one step, which is what a layout pass wants: two
    /// assignments would lay the children out twice and paint an intermediate
    /// position.
    public void SetBounds(int x, int y, int width, int height)
    {
        Bounds = Rectangle.Of(x, y, width, height);
    }

    /// Pushes the current bounds at the platform. Overridden by
    /// `WindowedControl`, which has a peer to tell; a `GraphicControl` has
    /// nothing to tell and only needs its parent to repaint.
    protected virtual void ApplyBounds()
    {
        var parent = _owner;
        if (parent != null)
            ((WindowedControl)parent).Invalidate();
    }

    /// How large the control would like to be, given its text and font. Zero
    /// means "no opinion", which is what the base says and what stops
    /// `AutoSize` doing anything to a control that has not overridden it.
    public virtual Size PreferredSize => Size.Empty;

    /// Resizes to `PreferredSize`, keeping the top-left corner. Does nothing
    /// when the control has no opinion.
    public void AutoSize()
    {
        var wanted = PreferredSize;
        if (wanted.IsEmpty)
            return;
        Bounds = Rectangle.Of(_area.X, _area.Y, wanted.Width, wanted.Height);
    }

    // -------------------------------------------------------------- layout

    /// Which edge this control fills. Setting it re-lays out the parent at
    /// once, because a docked control's position is the parent's decision and
    /// leaving it stale would show the old one.
    public DockStyle Dock
    {
        get => _docking;
        set
        {
            if (_docking == value)
                return;
            _docking = value;
            var parent = _owner;
            if (parent != null)
                ((WindowedControl)parent).PerformLayout();
        }
    }

    /// Which of the parent's edges this control keeps its distance from.
    /// Ignored entirely when `Dock` is anything but `None`.
    public AnchorStyles Anchors
    {
        get => _anchoring;
        set => _anchoring = value;
    }

    // ---------------------------------------------------------- appearance

    /// Whether the control is shown. A control whose parent is hidden is not
    /// visible on screen however this reads, which is why the question a
    /// program usually wants is `IsShowing`.
    public bool Visible
    {
        get => _shown;
        set
        {
            if (_shown == value)
                return;
            _shown = value;
            ApplyVisible();
            var parent = _owner;
            if (parent != null)
                ((WindowedControl)parent).PerformLayout();
        }
    }

    /// Whether this control and every parent above it is visible -- the
    /// question "can the user see it", which `Visible` alone does not answer.
    public bool IsShowing
    {
        get
        {
            if (!_shown)
                return false;
            var parent = _owner;
            if (parent == null)
                return true;
            return ((WindowedControl)parent).IsShowing;
        }
    }

    /// Makes the control visible. Virtual because a `Form` has more to do:
    /// it registers itself with the `Application` so that showing a window
    /// built in a local variable keeps it alive.
    public virtual void Show() => Visible = true;
    public void Hide() => Visible = false;

    /// Whether the control responds to the user.
    public bool Enabled
    {
        get => _usable;
        set
        {
            if (_usable == value)
                return;
            _usable = value;
            ApplyEnabled();
        }
    }

    /// The control's text: a button's caption, a text box's contents, a form's
    /// title. One property for all of them, as `TControl.Caption` and
    /// `TControl.Text` both were before Delphi split them and had to keep them
    /// in step ever after.
    public String Text
    {
        get => GetTextValue();
        set => SetTextValue(value);
    }

    /// Overridable so a control backed by a platform widget can read the live
    /// value rather than the last one set -- which for a text box is the only
    /// correct answer, since the user has been typing into it.
    protected virtual String GetTextValue() => _caption;

    protected virtual void SetTextValue(String value)
    {
        if (_caption == value)
            return;
        _caption = value;
        ApplyText();
        OnTextChanged();
    }

    /// The stored text, for a derived class that has overridden the accessors
    /// and still needs the field.
    protected String StoredText
    {
        get => _caption;
        set => _caption = value;
    }

    /// The font this control draws with. Inherited from the parent when nothing
    /// has been set here, which is what makes setting a form's font change
    /// every control on it -- the LCL's `ParentFont` without the extra flag,
    /// because "nothing set here" is exactly what a null field already says.
    public Font Font
    {
        get
        {
            var mine = _typeface;
            if (mine != null)
                return (Font)mine;
            var parent = _owner;
            if (parent != null)
                return ((WindowedControl)parent).Font;
            return WidgetSet.Current.DefaultFont();
        }
        set
        {
            _typeface = value;
            ApplyFont();
            OnFontChanged();
        }
    }

    /// What this control is drawn on when nothing has been set on it.
    ///
    /// **Inheriting from the parent is right for most controls and wrong for
    /// the ones you type into.** A label or a panel on a coloured form should
    /// take the form's colour; a text box, a list and a combo should be the
    /// window colour -- white under a light theme -- because that is what they
    /// are on every platform and what Windows would have drawn if nothing had
    /// been pushed at it. Each of those overrides this, exactly as C# does with
    /// `TextBoxBase.DefaultBackColor`.
    protected virtual Color DefaultBackColor
    {
        get
        {
            var parent = _owner;
            if (parent != null)
                return ((WindowedControl)parent).BackColor;
            return SystemColors.Control;
        }
    }

    /// And what it draws its text in, on the same terms.
    protected virtual Color DefaultForeColor
    {
        get
        {
            var parent = _owner;
            if (parent != null)
                return ((WindowedControl)parent).ForeColor;
            return SystemColors.ControlText;
        }
    }

    /// The colour text is drawn in, inherited the same way.
    public Color ForeColor
    {
        get
        {
            if (_foregroundSet)
                return _foreground;
            return DefaultForeColor;
        }
        set
        {
            _foreground = value;
            _foregroundSet = true;
            ApplyForeColor();
        }
    }

    /// The colour behind it, inherited the same way.
    public Color BackColor
    {
        get
        {
            if (_backgroundSet)
                return _background;
            return DefaultBackColor;
        }
        set
        {
            _background = value;
            _backgroundSet = true;
            ApplyBackColor();
        }
    }

    // What a derived class overrides to reach a platform widget. Each does
    // nothing here, because a control with no platform side has nothing to do.
    protected virtual void ApplyVisible()   { }
    protected virtual void ApplyEnabled()   { }
    protected virtual void ApplyText()      { }
    protected virtual void ApplyFont()      { }
    protected virtual void ApplyForeColor() { }
    protected virtual void ApplyBackColor() { }

    /// What the pointer looks like over this control.
    public CursorKind Cursor
    {
        get => _pointer;
        set
        {
            _pointer = value;
            ApplyCursor();
        }
    }

    protected virtual void ApplyCursor() { }

    /// Takes the mouse, so that a drag keeps being reported after the pointer
    /// has left this control -- which is what every drag needs and nothing else
    /// does.
    ///
    /// Virtual because a `GraphicControl` has no window to capture with and has
    /// to ask its parent, which is also what then routes the events back.
    public virtual void CaptureMouse(bool captured) { }

    /// Marks the control as needing repainting.
    public virtual void Invalidate()
    {
        var parent = _owner;
        if (parent != null)
            ((WindowedControl)parent).Invalidate();
    }

    // -------------------------------------------------------------- events

    /// The control was activated: clicked, or chosen with the keyboard.
    public event EventHandler Click;
    public event EventHandler DoubleClick;
    public event EventHandler Resize;
    public event EventHandler Move;
    public event EventHandler TextChanged;
    public event EventHandler FontChanged;
    public event EventHandler GotFocus;
    public event EventHandler LostFocus;
    public event EventHandler MouseEnter;
    public event EventHandler MouseLeave;
    public event MouseEventHandler MouseDown;
    public event MouseEventHandler MouseUp;
    public event MouseEventHandler MouseMove;
    public event MouseEventHandler MouseWheel;
    public event KeyEventHandler KeyDown;
    public event KeyEventHandler KeyUp;
    public event KeyPressEventHandler KeyPress;
    public event PaintEventHandler Paint;

    // The raisers. Each is `protected virtual` and each calls its event, which
    // is C#'s arrangement and is forced here as well: an event may only be
    // raised by the class that declares it, so a derived class reaching its
    // base's event has to come through one of these. Overriding one and not
    // calling `base` is how a derived control suppresses an event entirely.

    protected virtual void OnClick() => Click(this);
    protected virtual void OnDoubleClick() => DoubleClick(this);
    protected virtual void OnResize() => Resize(this);
    protected virtual void OnMove() => Move(this);
    protected virtual void OnTextChanged() => TextChanged(this);
    protected virtual void OnFontChanged() => FontChanged(this);
    protected virtual void OnGotFocus() => GotFocus(this);
    protected virtual void OnLostFocus() => LostFocus(this);
    protected virtual void OnMouseEnter() => MouseEnter(this);
    protected virtual void OnMouseLeave() => MouseLeave(this);

    protected virtual void OnMouseDown(MouseEventArgs args) => MouseDown(this, args);
    protected virtual void OnMouseUp(MouseEventArgs args) => MouseUp(this, args);
    protected virtual void OnMouseMove(MouseEventArgs args) => MouseMove(this, args);
    protected virtual void OnMouseWheel(MouseEventArgs args) => MouseWheel(this, args);

    protected virtual void OnKeyDown(KeyEventArgs args) => KeyDown(this, args);
    protected virtual void OnKeyUp(KeyEventArgs args) => KeyUp(this, args);
    protected virtual void OnKeyPress(KeyPressEventArgs args) => KeyPress(this, args);

    protected virtual void OnPaint(PaintEventArgs args) => Paint(this, args);

    // ----------------------------------------------- what the platform says

    // `IControlNotify`, implemented once here for every control there will ever
    // be. Each method turns the platform's report into the raiser above it, so
    // a control that wants to react overrides `OnClick` and never sees any of
    // this. The `echoing` flag is set around the ones that would otherwise
    // cause a write back to the platform that reported them.

    public void OnPlatformPaint(Graphics surface)
    {
        OnPaint(PaintEventArgs.Of(surface, surface.ClipBounds));
    }

    public void OnPlatformResized(Size extent)
    {
        _echoing = true;
        _area = Rectangle.Of(_area.X, _area.Y, extent.Width, extent.Height);
        _echoing = false;
        OnResize();
        if (this is WindowedControl container)
            container.PerformLayout();
    }

    public void OnPlatformMoved(Point position)
    {
        // The platform measures from the parent widget's corner; `Bounds` is
        // measured from the corner of the area the parent gives its children.
        // Taking the offset off again is what makes a control's position read
        // back as the one it was given, under a group box as anywhere else.
        var placed = position;
        var parent = _owner;
        if (parent != null)
        {
            var origin = ((WindowedControl)parent).ClientOrigin;
            placed = Point.At(position.X - origin.X, position.Y - origin.Y);
        }
        _echoing = true;
        _area = Rectangle.Of(placed.X, placed.Y, _area.Width, _area.Height);
        _echoing = false;
        OnMove();
    }

    public virtual void OnPlatformMouseDown(MouseButton button, Point at, ModifierKeys modifiers)
    {
        OnMouseDown(MouseEventArgs.Of(button, at, modifiers, 0));
    }

    public virtual void OnPlatformMouseUp(MouseButton button, Point at, ModifierKeys modifiers)
    {
        OnMouseUp(MouseEventArgs.Of(button, at, modifiers, 0));
    }

    public virtual void OnPlatformMouseMove(Point at, ModifierKeys modifiers)
    {
        OnMouseMove(MouseEventArgs.Of(MouseButton.None, at, modifiers, 0));
    }

    public void OnPlatformMouseEnter() => OnMouseEnter();
    public virtual void OnPlatformMouseLeave() => OnMouseLeave();

    public void OnPlatformMouseWheel(int delta, Point at, ModifierKeys modifiers)
    {
        OnMouseWheel(MouseEventArgs.Of(MouseButton.None, at, modifiers, delta));
    }

    public void OnPlatformKeyDown(Key key, ModifierKeys modifiers)
    {
        OnKeyDown(KeyEventArgs.Of(key, modifiers));
    }

    public void OnPlatformKeyUp(Key key, ModifierKeys modifiers)
    {
        OnKeyUp(KeyEventArgs.Of(key, modifiers));
    }

    public void OnPlatformKeyPress(char typed)
    {
        OnKeyPress(KeyPressEventArgs.Of(typed));
    }

    public void OnPlatformGotFocus() => OnGotFocus();
    public void OnPlatformLostFocus() => OnLostFocus();
    public void OnPlatformActivated() => OnClick();

    /// The user changed the control's value. The base turns it into
    /// `OnTextChanged`, which is right for everything whose value is its text;
    /// a list overrides it and raises `SelectedIndexChanged` instead.
    public virtual void OnPlatformValueChanged() => OnTextChanged();

    /// A toolbar button was pressed. Meaningless for everything that is not a
    /// toolbar, which is why the base does nothing with it.
    public virtual void OnPlatformToolClicked(int index) { }

    /// Whether we are currently inside a platform notification, for a derived
    /// class whose setter must not answer one.
    protected bool IsEchoing => _echoing;
}
