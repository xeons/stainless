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

// The composites: controls made of other controls rather than of a widget.
//
// `RadioGroup`, `CheckGroup`, `LabeledEdit` and `Image` are all the same idea --
// a thing a program wants often enough that building it by hand every time is
// noise. None of them is a platform widget and none needs a peer: each is a
// container that makes its own children, which is exactly what `TRadioGroup`
// and `TLabeledEdit` are in the LCL too.
//
// **Which is why they belong in a library rather than in a program.** The
// arithmetic that lays out six radio buttons in two columns is the same
// arithmetic every time, and getting it slightly wrong is the sort of thing
// nobody notices until the captions are long.
module Forms;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;

// ============================================================== radio group

/// A group box holding radio buttons, of which one is chosen.
///
/// ```
/// var priority = new RadioGroup(this);
/// priority.Text = "Priority";
/// priority.SetBounds(10, 10, 200, 90);
/// priority.Add("Low");
/// priority.Add("High");
/// priority.SelectedIndex = 0;
/// priority.SelectedIndexChanged += this.OnPriority;
/// ```
///
/// **Grouping is by parent, and this *is* the parent.** Radio buttons form one
/// group per containing window on every platform, so putting them in a group
/// box is not decoration -- it is what stops two sets of choices on one form
/// behaving as a single set.
public class RadioGroup : GroupBox
{
    List<RadioButton> _buttons;
    /// Ticked to untick every choice, as `TCustomRadioGroup.FHiddenButton`
    /// is. GTK will not untick the last radio of a group, and a group always
    /// has one ticked; this is the one ticked when nothing is chosen.
    RadioButton _none;
    /// The index `SelectedIndexChanged` last reported, or the program last
    /// set.
    int _reported;
    int _columns;
    bool _ready;

    public RadioGroup(WindowedControl parent)
    {
        base(parent);
        _buttons = new List<RadioButton>();
        _none = new RadioButton(this);
        _none.Visible = false;
        _none.Checked = true;
        _reported = -1;
        _columns = 1;
        _ready = true;
    }

    /// How many across. Changing it re-lays out what is already there.
    public int Columns
    {
        get => _columns;
        set
        {
            if (value < 1)
                return;
            _columns = value;
            ArrangeButtons();
        }
    }

    /// Adds a choice and answers its index.
    public int Add(String caption)
    {
        var made = new RadioButton(this);
        made.Text = caption;
        made.CheckedChanged += this.OnChildChecked;
        _buttons.Add(made);
        ArrangeButtons();
        return (int)_buttons.Count - 1;
    }

    public List<RadioButton> Buttons => _buttons;
    public nuint Count => _buttons.Count;

    /// Which choice is ticked, or -1.
    ///
    /// Read from the buttons rather than remembered, because the platform ticks
    /// and unticks them itself when one is clicked -- a field here would be a
    /// second answer to a question that already has one.
    ///
    /// Setting it to -1 unticks every choice; any other index naming no choice
    /// is ignored. Setting it raises no `SelectedIndexChanged`, as setting
    /// `CheckBox.Checked` raises no `CheckedChanged`.
    public int SelectedIndex
    {
        get
        {
            for (nuint i = 0u; i < _buttons.Count; i++)
            {
                if (_buttons[i].Checked)
                    return (int)i;
            }
            return -1;
        }
        set
        {
            if (value < -1 || value >= (int)_buttons.Count)
                return;
            _reported = value;
            var ticked = value < 0 ? _none : _buttons[(nuint)value];
            ticked.Checked = true;
        }
    }

    /// The caption of the chosen item, or null.
    public String? SelectedText
    {
        get
        {
            int at = SelectedIndex;
            if (at < 0)
                return null;
            return _buttons[(nuint)at].Text;
        }
    }

    /// The user chose a different choice.
    public event EventHandler SelectedIndexChanged;

    protected virtual void OnSelectedIndexChanged() => SelectedIndexChanged(this);

    /// Reports once per choice. A click moves two ticks on GTK, which reports
    /// both, and Win32 reports a click on the choice already ticked -- so only
    /// the button now ticked counts, and only when it is a different choice.
    void OnChildChecked(Control sender)
    {
        if (sender is RadioButton button)
        {
            if (!button.Checked)
                return;
        }
        int now = SelectedIndex;
        if (now == _reported)
            return;
        _reported = now;
        OnSelectedIndexChanged();
    }

    /// Lays the buttons out in `Columns` columns, filling the client area.
    ///
    /// Called on every addition, which is O(n) per add and O(n²) to build a
    /// group -- which for a group small enough to be usable is a few dozen
    /// `MoveWindow` calls and not worth the bookkeeping to avoid.
    /// **Nothing before the constructor has finished.** `OnResize` is overridden
    /// here and the base constructor resizes: the platform window is made,
    /// given its bounds, and reports them back -- all before this class's own
    /// fields exist. Arranging then reads a list that has not been made yet.
    ///
    /// The same trap C# has with a virtual call from a base constructor, and
    /// the same answer: a flag that is false until there is something to
    /// arrange.
    void ArrangeButtons()
    {
        if (!_ready || _buttons.IsEmpty)
            return;
        var area = ClientBounds;
        if (area.Width <= 0 || area.Height <= 0)
            return;

        nuint total = _buttons.Count;
        int perColumn = ((int)total + _columns - 1) / _columns;
        if (perColumn < 1)
            perColumn = 1;

        int width = area.Width / _columns;
        int height = area.Height / perColumn;
        if (height < 20)
            height = 20;

        for (nuint i = 0u; i < total; i++)
        {
            int column = (int)i / perColumn;
            int row = (int)i % perColumn;
            _buttons[i].SetBounds(column * width, row * height, width, height);
        }
    }

    /// A resize moves every button, since each is a fraction of the client area.
    protected override void OnResize()
    {
        base.OnResize();
        ArrangeButtons();
    }
}

// ============================================================== check group

/// The same, with check boxes: any number chosen rather than exactly one.
public class CheckGroup : GroupBox
{
    List<CheckBox> _boxes;
    int _columns;
    bool _ready;

    public CheckGroup(WindowedControl parent)
    {
        base(parent);
        _boxes = new List<CheckBox>();
        _columns = 1;
        _ready = true;
    }

    public int Columns
    {
        get => _columns;
        set
        {
            if (value < 1)
                return;
            _columns = value;
            ArrangeBoxes();
        }
    }

    public int Add(String caption)
    {
        var made = new CheckBox(this);
        made.Text = caption;
        made.CheckedChanged += this.OnChildChanged;
        _boxes.Add(made);
        ArrangeBoxes();
        return (int)_boxes.Count - 1;
    }

    public List<CheckBox> Boxes => _boxes;
    public nuint Count => _boxes.Count;

    public bool GetItemChecked(int index)
    {
        if (index < 0 || (nuint)index >= _boxes.Count)
            return false;
        return _boxes[(nuint)index].Checked;
    }

    public void SetItemChecked(int index, bool ticked)
    {
        if (index < 0 || (nuint)index >= _boxes.Count)
            return;
        _boxes[(nuint)index].Checked = ticked;
    }

    /// The indices that are ticked, in order.
    public int[] CheckedIndices
    {
        get
        {
            nuint ticked = 0u;
            for (nuint i = 0u; i < _boxes.Count; i++)
            {
                if (_boxes[i].Checked)
                    ticked++;
            }
            var found = new int[ticked];
            nuint at = 0u;
            for (nuint i = 0u; i < _boxes.Count; i++)
            {
                if (_boxes[i].Checked)
                {
                    found[at] = (int)i;
                    at++;
                }
            }
            return found;
        }
    }

    /// One of the boxes was ticked or unticked.
    public event EventHandler CheckedChanged;

    protected virtual void OnCheckedChanged() => CheckedChanged(this);

    void OnChildChanged(Control sender) => OnCheckedChanged();

    /// See the note on `RadioGroup.ArrangeButtons`.
    void ArrangeBoxes()
    {
        if (!_ready || _boxes.IsEmpty)
            return;
        var area = ClientBounds;
        if (area.Width <= 0 || area.Height <= 0)
            return;

        nuint total = _boxes.Count;
        int perColumn = ((int)total + _columns - 1) / _columns;
        if (perColumn < 1)
            perColumn = 1;

        int width = area.Width / _columns;
        int height = area.Height / perColumn;
        if (height < 20)
            height = 20;

        for (nuint i = 0u; i < total; i++)
        {
            int column = (int)i / perColumn;
            int row = (int)i % perColumn;
            _boxes[i].SetBounds(column * width, row * height, width, height);
        }
    }

    protected override void OnResize()
    {
        base.OnResize();
        ArrangeBoxes();
    }
}

// ============================================================= labeled edit

/// A text box with a caption above it, which is what a form is mostly made of.
///
/// **A `Panel`, not an `Edit` with a label bolted on.** `TLabeledEdit` is a
/// `TCustomEdit` that owns a `TBoundLabel` positioned relative to itself, so
/// the label is outside the control's own bounds and a layout that moves the
/// edit has to know to expect it. Here the pair is one control whose bounds
/// contain both, and docking or anchoring it does the obvious thing.
public class LabeledEdit : Panel
{
    Label _captionLabel;
    TextBox _entry;
    int _above;
    bool _ready;

    public LabeledEdit(WindowedControl parent)
    {
        base(parent);
        _above = 18;

        _captionLabel = new Label(this);
        _entry = new TextBox(this);
        _entry.UserTextChanged += this.OnEntryChanged;

        _ready = true;
        ArrangeChildren();
    }

    /// The caption above the box.
    public String Caption
    {
        get => _captionLabel.Text;
        set => _captionLabel.Text = value;
    }

    /// What is in the box. `Text` itself is the panel's, which nothing shows.
    public String Value
    {
        get => _entry.Text;
        set => _entry.Text = value;
    }

    /// The box, for the things a caller may want to set on it directly --
    /// `PasswordChar`, `MaxLength`, `ReadOnly`.
    public TextBox Entry => _entry;
    public Label CaptionLabel => _captionLabel;

    /// How tall the caption is. The box takes what is left.
    public int CaptionHeight
    {
        get => _above;
        set
        {
            _above = value;
            ArrangeChildren();
        }
    }

    /// The user typed.
    public event EventHandler ValueChanged;

    protected virtual void OnValueChanged() => ValueChanged(this);

    void OnEntryChanged(Control sender) => OnValueChanged();

    /// See the note on `RadioGroup.ArrangeButtons`.
    void ArrangeChildren()
    {
        if (!_ready)
            return;
        var area = ClientBounds;
        if (area.Width <= 0)
            return;
        _captionLabel.SetBounds(0, 0, area.Width, _above);
        int rest = area.Height - _above;
        if (rest < 0)
            rest = 0;
        _entry.SetBounds(0, _above, area.Width, rest);
    }

    protected override void OnResize()
    {
        base.OnResize();
        ArrangeChildren();
    }
}

// ==================================================================== image

/// A picture on a form.
///
/// The `GraphicControl` counterpart of everything else here: no window, no
/// peer, just a `Bitmap` drawn in the parent's paint.
///
/// **Four properties decide where the picture goes**, and they are the LCL's
/// and C#'s, which agree: `Stretch` fills the control, `Proportional` keeps
/// the shape while doing it, `Center` puts a picture smaller than the control
/// in the middle rather than the corner, and `AutoSize` moves the *control* to
/// the picture instead. `Stretch` and `AutoSize` together are a contradiction
/// -- one resizes the picture to the control and the other the control to the
/// picture -- and `AutoSize` wins, because it is the one that says what the
/// control is for.
public class Image : GraphicControl
{
    Bitmap? _picture;
    bool _stretch;
    bool _proportional;
    bool _center;
    bool _autoSize;

    public Image(WindowedControl parent)
    {
        base(parent);
        _picture = null;
        _stretch = false;
        _proportional = false;
        _center = false;
        _autoSize = false;
    }

    /// What is shown, or null for nothing.
    public Bitmap? Picture
    {
        get => _picture;
        set
        {
            _picture = value;
            FitToPicture();
            Invalidate();
        }
    }

    /// Whether the picture is scaled to keep its shape when it is stretched.
    ///
    /// Nothing on its own: without `Stretch` there is no scaling for this to
    /// constrain, which is the LCL's rule and is why it is not a three-valued
    /// `Scaling` property.
    public bool Proportional
    {
        get => _proportional;
        set
        {
            _proportional = value;
            Invalidate();
        }
    }

    /// Whether a picture smaller than the control sits in the middle of it.
    public bool Center
    {
        get => _center;
        set
        {
            _center = value;
            Invalidate();
        }
    }

    /// Whether the control takes the picture's size when one is given to it.
    public bool AutoSize
    {
        get => _autoSize;
        set
        {
            _autoSize = value;
            FitToPicture();
        }
    }

    void FitToPicture()
    {
        if (!_autoSize)
            return;

        var held = _picture;
        if (held == null)
            return;

        var shown = (Bitmap)held;
        SetBounds(Left, Top, shown.Width, shown.Height);
    }

    /// Loads a picture from a file and shows it.
    public Result<bool, String> Load(String path)
    {
        var loaded = Bitmap.FromFile(path);
        if (!loaded.Ok)
            return Fail(loaded.Error);
        Picture = loaded.Value;
        return Ok(true);
    }

    /// Whether the picture is scaled to the control, or drawn at its own size
    /// in the top-left corner.
    public bool Stretch
    {
        get => _stretch;
        set
        {
            _stretch = value;
            Invalidate();
        }
    }

    protected override void OnPaint(PaintEventArgs args)
    {
        var held = _picture;
        if (held != null)
        {
            var shown = (Bitmap)held;
            args.Graphics.DrawBitmap(shown, ComputePlacement(shown));
        }
        base.OnPaint(args);
    }

    /// Where the picture goes, which is the whole of what the four properties
    /// decide. One function rather than four cases in `OnPaint`, because they
    /// interact: proportional stretching is a scale *and* a centring, and
    /// getting that as two independent branches is how a picture ends up
    /// correctly sized in the wrong corner.
    Rectangle ComputePlacement(Bitmap shown)
    {
        int wide = shown.Width;
        int high = shown.Height;

        if (wide <= 0 || high <= 0)
            return Rectangle.FromBounds(0, 0, Width, Height);

        if (!_stretch)
        {
            if (!_center)
                return Rectangle.FromBounds(0, 0, wide, high);
            return Rectangle.FromBounds((Width - wide) / 2, (Height - high) / 2, wide, high);
        }

        if (!_proportional)
            return Rectangle.FromBounds(0, 0, Width, Height);

        // The smaller of the two ratios is the one that fits, and it is
        // computed in whole numbers rather than as a double: a control and a
        // picture are both counted in pixels, and multiplying before dividing
        // keeps the answer exact without going near floating point.
        int fitted = Width * high;
        int other = Height * wide;

        int shownWide = fitted <= other ? Width : (wide * Height) / high;
        int shownHigh = fitted <= other ? (high * Width) / wide : Height;

        // Proportional stretching centres what is left over. Filling from the
        // corner instead would put a wide picture against the top of a tall
        // control, which is never what was meant.
        return Rectangle.FromBounds((Width - shownWide) / 2, (Height - shownHigh) / 2,
                            shownWide, shownHigh);
    }
}

// ================================================================ spin edit

/// A number with arrows beside it.
///
/// **One control, two windows.** Windows has no spin control: it has an
/// up-down, which is a pair of arrows that drives a *buddy* window, so a spin
/// edit is an `EDIT` with one docked inside its right-hand edge. The pair moves
/// and hides together, which is the whole of the illusion.
public class SpinEdit : WindowedControl
{
    ISpinPeer _native;
    int _minimum;
    int _maximum;

    public SpinEdit(WindowedControl parent)
    {
        base(parent);
        _minimum = 0;
        _maximum = 100;
        _native = WidgetSet.Current.CreateSpin(this, ParentPeer);
        AttachPeer(_native);
    }

    /// Raises `Maximum` when set above it.
    public int Minimum
    {
        get => _minimum;
        set
        {
            _minimum = value;
            if (_maximum < value)
                _maximum = value;
            ApplyRange();
        }
    }

    /// Lowers `Minimum` when set below it.
    public int Maximum
    {
        get => _maximum;
        set
        {
            _maximum = value;
            if (_minimum > value)
                _minimum = value;
            ApplyRange();
        }
    }

    /// Kept inside the range.
    public int Value
    {
        get => _native.GetValue();
        set => _native.SetValue(ClampToRange(value, _minimum, _maximum));
    }

    void ApplyRange()
    {
        _native.SetRange(_minimum, _maximum);
        int now = _native.GetValue();
        int kept = ClampToRange(now, _minimum, _maximum);
        if (kept != now)
            _native.SetValue(kept);
    }

    /// The user changed the number, by the arrows or by typing. Setting
    /// `Value` raises nothing.
    public event EventHandler ValueChanged;

    protected virtual void OnValueChanged() => ValueChanged(this);

    public override void OnPlatformValueChanged() => OnValueChanged();
}

// =========================================================== check list box

/// A list whose items each have a tick.
///
/// The one control here that is a different widget from the one its name
/// suggests: a report-mode list view with check boxes, because Windows has no
/// checked list box and that is what every program that shows one uses.
public class CheckListBox : ListControl
{
    ICheckListPeer _native;

    public CheckListBox(WindowedControl parent)
    {
        base(parent);
        _native = WidgetSet.Current.CreateCheckList(this, ParentPeer);
        AttachPeer(_native);
    }

    protected override IListPeer List => _native;

    /// Whether an item is ticked.
    public bool GetItemChecked(int index) => _native.GetItemChecked(index);

    public void SetItemChecked(int index, bool ticked)
    {
        _native.SetItemChecked(index, ticked);
    }

    /// The indices that are ticked, in order.
    public int[] CheckedIndices
    {
        get
        {
            int total = (int)Count;
            nuint ticked = 0u;
            for (int i = 0; i < total; i++)
            {
                if (_native.GetItemChecked(i))
                    ticked++;
            }
            var found = new int[ticked];
            nuint at = 0u;
            for (int i = 0; i < total; i++)
            {
                if (_native.GetItemChecked(i))
                {
                    found[at] = i;
                    at++;
                }
            }
            return found;
        }
    }
}

// ================================================================== header

/// A row of column headings that can be dragged wider.
///
/// Standing alone, rather than the one a `ListView` already has: what it is for
/// is putting headings over something this library does not draw -- a grid a
/// program owns, most likely.
public class HeaderControl : WindowedControl
{
    IHeaderPeer _native;

    public HeaderControl(WindowedControl parent)
    {
        base(parent);
        _native = WidgetSet.Current.CreateHeader(this, ParentPeer);
        AttachPeer(_native);
    }

    /// Adds a heading and answers its index.
    public int Add(String text, int width) => _native.AddSection(text, width);

    public int Count => _native.SectionCount;

    public int GetSectionWidth(int index) => _native.GetSectionWidth(index);

    public void SetSectionWidth(int index, int width)
    {
        _native.SetSectionWidth(index, width);
    }

    /// A heading was dragged.
    public event EventHandler SectionResized;

    protected virtual void OnSectionResized() => SectionResized(this);

    public override void OnPlatformValueChanged() => OnSectionResized();
}

// ============================================================= button panel

/// Which of a `ButtonPanel`'s four buttons are showing. Bits, so they combine.
[Flags]
public enum PanelButtons
{
    None   = 0,
    Ok     = 1,
    Cancel = 2,
    Close  = 4,
    Help   = 8,
}

/// The order a `ButtonPanel` puts its buttons in, left to right.
///
/// The names say the order and the order is the whole content, so they read as
/// the answer rather than as a code for one -- `TButtonOrder`'s
/// `boCloseCancelOK` with the capitals put back. `Default` is the one that is
/// not an order: it is whichever of the two the platform in use prefers.
public enum ButtonOrder { Default, CloseCancelOk, CloseOkCancel }

/// The strip of buttons a dialog ends with.
///
/// **The affirmative button goes on the right on Windows and on the right on
/// GNOME, and the two disagree about which button that is.** Windows puts OK
/// before Cancel; the GNOME guidelines put Cancel before OK. That single
/// difference is the reason this control exists rather than four buttons placed
/// by hand -- a dialog laid out by hand is laid out for one desktop, and looks
/// subtly wrong on the other to everybody who uses it every day.
///
/// `Default` asks the widget set which desktop this is. It is the one place in
/// the portable tier that reads `IWidgetSet.Name`, and it is asked once at
/// construction rather than compiled in, so a program that chose its backend at
/// run time gets the right answer too.
///
/// **Help is always in the far corner**, on both, which is why the layout is
/// not simply "pack them against the right".
///
/// ```
/// var buttons = new ButtonPanel(this);
/// buttons.ShowButtons = PanelButtons.Ok | PanelButtons.Cancel;
/// buttons.OkButton.Click += this.OnAccept;
/// buttons.CancelButton.Click += this.OnDismiss;
/// ```
///
/// **All four buttons exist from the start, and `ShowButtons` hides them.**
/// `TCustomButtonPanel` creates and frees them as the set changes, which here
/// would mean a handler attached to Cancel disappearing because a program
/// turned Help on. A control's lifetime is its parent's, and `TabControl`
/// already hides a removed page rather than destroying it, so this is the rule
/// that was already in force.
///
/// **No stock glyphs.** `TButtonPanel.ShowGlyphs` puts a tick on OK and a cross
/// on Cancel out of the widgetset's stock icon set, which is a thing neither
/// backend here has. A program that wants pictures sets `Image` on the buttons,
/// which is a property every `Button` now has.
public class ButtonPanel : Panel
{
    Button? _ok;
    Button? _cancel;
    Button? _close;
    Button? _help;
    Bevel? _bevelLine;

    PanelButtons _showButtons;
    ButtonOrder _order;
    ButtonOrder _resolved;
    int _spacing;
    bool _showBevel;
    PanelButtons _defaultButton;
    bool _ready;

    public ButtonPanel(WindowedControl parent)
    {
        base(parent);
        _showButtons = PanelButtons.Ok | PanelButtons.Cancel | PanelButtons.Help;
        _order = ButtonOrder.Default;
        _spacing = 6;
        _showBevel = true;
        _defaultButton = PanelButtons.Ok;
        _ready = false;

        // **Asked once, here.** `IWidgetSet.Name` is the only thing in this
        // library that names a platform as a string, and this is its only
        // caller outside a backend: what differs between the two desktops is a
        // convention rather than a capability, so there is nothing in the seam
        // to ask instead.
        _resolved = WidgetSet.Current.Name == "Win32"
                 ? ButtonOrder.CloseOkCancel : ButtonOrder.CloseCancelOk;

        var line = new Bevel(this);
        line.Kind = BevelKind.TopLine;
        _bevelLine = line;

        _ok     = CreateButton("OK");
        _cancel = CreateButton("Cancel");
        _close  = CreateButton("Close");
        _help   = CreateButton("Help");

        Dock = DockStyle.Bottom;
        Height = 42;

        _ready = true;
        ApplyShowButtons();
        ApplyDefaultButton();
        ArrangeButtons();
    }

    Button CreateButton(String caption)
    {
        var made = new Button(this);
        made.Text = caption;
        return made;
    }

    /// The OK button. Always here; `ShowButtons` decides whether it is visible.
    public Button OkButton => (Button)_ok;
    public Button CancelButton => (Button)_cancel;
    public Button CloseButton => (Button)_close;
    public Button HelpButton => (Button)_help;

    /// The line across the top that separates the strip from the dialog.
    public Bevel BevelLine => (Bevel)_bevelLine;

    /// Which buttons are showing. The default is OK, Cancel and Help, which is
    /// what a dialog usually wants -- `TButtonPanel` shows Close as well, and a
    /// strip with both Cancel and Close in it is a strip nobody designed.
    public PanelButtons ShowButtons
    {
        get => _showButtons;
        set
        {
            _showButtons = value;
            ApplyShowButtons();
            ApplyDefaultButton();
            ArrangeButtons();
        }
    }

    /// Left to right, and `Default` means whichever the platform prefers.
    public ButtonOrder Order
    {
        get => _order;
        set
        {
            _order = value;
            ArrangeButtons();
        }
    }

    /// Which order `Default` turned out to mean here. What a test asks, and the
    /// only way to see the decision from outside.
    public ButtonOrder EffectiveOrder => _order == ButtonOrder.Default ? _resolved : _order;

    /// Pixels between the buttons, and between them and the edges.
    public int Spacing
    {
        get => _spacing;
        set
        {
            _spacing = value;
            ArrangeButtons();
        }
    }

    /// Whether the line across the top is drawn.
    public bool ShowBevel
    {
        get => _showBevel;
        set
        {
            _showBevel = value;
            ArrangeButtons();
        }
    }

    /// Which button Enter presses. `PanelButtons.None` for none, and a button
    /// that is not showing is never made the default whatever this says.
    public PanelButtons DefaultButton
    {
        get => _defaultButton;
        set
        {
            _defaultButton = value;
            ApplyDefaultButton();
        }
    }

    void ApplyShowButtons()
    {
        OkButton.Visible     = _showButtons.HasFlag(PanelButtons.Ok);
        CancelButton.Visible = _showButtons.HasFlag(PanelButtons.Cancel);
        CloseButton.Visible  = _showButtons.HasFlag(PanelButtons.Close);
        HelpButton.Visible   = _showButtons.HasFlag(PanelButtons.Help);
    }

    void ApplyDefaultButton()
    {
        SetDefaultOn(OkButton,     PanelButtons.Ok);
        SetDefaultOn(CancelButton, PanelButtons.Cancel);
        SetDefaultOn(CloseButton,  PanelButtons.Close);
        SetDefaultOn(HelpButton,   PanelButtons.Help);
    }

    void SetDefaultOn(Button button, PanelButtons which)
    {
        button.IsDefault = which == _defaultButton && _showButtons.HasFlag(which);
    }

    /// Lays the buttons out: Help against the left edge, the rest packed
    /// against the right in the chosen order, and the bevel across the top.
    ///
    /// **Packed from the right, so the order is read backwards.** The rightmost
    /// button is the one the eye goes to and the one the order names last, and
    /// placing right to left is what keeps the gaps even when a button in the
    /// middle of the list is not showing.
    ///
    /// The buttons are placed rather than docked because docking has no notion
    /// of "against the right, in this order, with a gap": `DockStyle.Right`
    /// four times would work, and would put them in the order they were built
    /// and give each the full height.
    void ArrangeButtons()
    {
        if (!_ready)
            return;
        var area = ClientBounds;
        if (area.Width <= 0 || area.Height <= 0)
            return;

        var line = BevelLine;
        line.Visible = _showBevel;
        line.SetBounds(0, 0, area.Width, 2);

        int top = _showBevel ? _spacing : _spacing / 2;
        int height = area.Height - top - _spacing / 2;
        if (height < 1)
            height = 1;

        if (HelpButton.Visible)
        {
            HelpButton.SetBounds(_spacing, top, MeasureButtonWidth(HelpButton), height);
        }

        int right = area.Width - _spacing;
        var packed = GetButtonsInOrder();
        for (nuint i = packed.Length; i > 0u; i--)
        {
            var button = packed[i - 1u];
            int width = MeasureButtonWidth(button);
            button.SetBounds(right - width, top, width, height);
            right = right - width - _spacing;
        }
    }

    /// The buttons that pack against the right edge, left to right. Help is not
    /// among them: it has its own corner.
    Button[] GetButtonsInOrder()
    {
        var first = CloseButton;
        var second = EffectiveOrder == ButtonOrder.CloseOkCancel ? OkButton : CancelButton;
        var third = EffectiveOrder == ButtonOrder.CloseOkCancel ? CancelButton : OkButton;

        nuint present = 0u;
        if (first.Visible)
            present++;
        if (second.Visible)
            present++;
        if (third.Visible)
            present++;

        var packed = new Button[present];
        nuint at = 0u;
        if (first.Visible)
        {
            packed[at] = first;
            at++;
        }
        if (second.Visible)
        {
            packed[at] = second;
            at++;
        }
        if (third.Visible)
        {
            packed[at] = third;
            at++;
        }
        return packed;
    }

    /// How wide one button should be: what it asks for, never below the 75
    /// pixels every dialog button on every desktop has been since Windows 3.
    int MeasureButtonWidth(Button button)
    {
        int wanted = button.PreferredSize.Width;
        if (wanted < 75)
            wanted = 75;
        return wanted;
    }

    /// How tall the strip has to be for the buttons in it.
    ///
    /// The width is zero and means nothing: a button strip is docked to the
    /// bottom and takes whatever width the dialog has, so the only figure a
    /// caller could want is the height.
    public override Size PreferredSize
    {
        get
        {
            int tallest = 23;
            tallest = ChooseTallerHeight(tallest, _ok);
            tallest = ChooseTallerHeight(tallest, _cancel);
            tallest = ChooseTallerHeight(tallest, _close);
            tallest = ChooseTallerHeight(tallest, _help);
            return Size.FromDimensions(0, tallest + _spacing + _spacing / 2 + (_showBevel ? 2 : 0));
        }
    }

    int ChooseTallerHeight(int best, Button? button)
    {
        if (button == null)
            return best;
        int wanted = ((Button)button).PreferredSize.Height;
        return wanted > best ? wanted : best;
    }

    /// See the note on `RadioGroup.ArrangeButtons`: the base constructor
    /// resizes, and this override runs before this class's own fields exist.
    protected override void OnResize()
    {
        base.OnResize();
        ArrangeButtons();
    }
}
