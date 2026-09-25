// SPDX-License-Identifier: 0BSD
//
// A form with the standard controls on it, laid out by docking and anchoring.
//
//   stainless run samples/forms/demo.sl forms/src bindings/win32/api \
//       bindings/win32/Win32.sl -l user32 -l gdi32
//
// Pass `--selftest` and it builds the same form, pumps the queue a few times,
// checks what it can check without a person in front of it, and quits -- which
// is what makes this sample something a build can run.
module Demo;

import Standard.Console;
import Standard.Text;
import Standard.Collections;
import Forms;
import Forms.Drawing;
import Forms.Platform;

/// The window itself. A class deriving from `Form`, with its controls as
/// fields and its handlers as methods -- which is what `save.Click += this.OnSave`
/// needs, since a closure is a method and the object it belongs to.
public class DemoForm : Form
{
    Panel _header;
    Label _title;
    Label _status;
    TextBox _entry;
    TextBox _notes;
    Button _add;
    Button _clear;
    ListBox _items;
    CheckBox _urgent;
    GroupBox _choices;
    RadioButton _low;
    RadioButton _high;
    ComboBox _kind;

    public DemoForm()
    {
        base(WindowBorder.Sizable);

        Text = "Forms for Stainless";
        SetBounds(0, 0, 720, 480);

        // A strip across the top, which every other control's layout is
        // measured against because it takes its bite out of the client area
        // first.
        _header = new Panel(this);
        _header.Dock = DockStyle.Top;
        _header.Height = 44;
        _header.BackColor = SystemColors.ControlLight;

        _title = new Label(_header);
        _title.Text = "Shopping list";
        _title.Font = new Font("Segoe UI", 14, FontStyle.Bold);
        _title.SetBounds(12, 10, 300, 26);

        // The status line, docked to the bottom, so what is left in the middle
        // is what everything else shares.
        _status = new Label(this);
        _status.Dock = DockStyle.Bottom;
        _status.Height = 22;
        _status.Text = "Ready.";

        // The entry row. Anchored left and right, so it stretches with the
        // form; the buttons anchor to the right only, so they move instead.
        _entry = new TextBox(this);
        _entry.SetBounds(12, 56, 400, 26);
        _entry.Anchors = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;

        _add = new Button(this);
        _add.Text = "Add";
        _add.SetBounds(424, 56, 90, 26);
        _add.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        _add.IsDefault = true;
        _add.Click += this.OnAdd;

        _clear = new Button(this);
        _clear.Text = "Clear";
        _clear.SetBounds(522, 56, 90, 26);
        _clear.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        _clear.Click += this.OnClear;

        // The list grows in both directions.
        _items = new ListBox(this);
        _items.SetBounds(12, 94, 400, 220);
        _items.Anchors = AnchorStyles.Top | AnchorStyles.Left
                      | AnchorStyles.Right | AnchorStyles.Bottom;
        _items.SelectedIndexChanged += this.OnChosen;

        _urgent = new CheckBox(this);
        _urgent.Text = "Urgent";
        _urgent.SetBounds(424, 94, 120, 22);
        _urgent.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        _urgent.CheckedChanged += this.OnUrgentChanged;

        // Two radio buttons inside a group box, which is what makes them one
        // group: grouping is by parent on every platform.
        _choices = new GroupBox(this);
        _choices.Text = "Priority";
        _choices.SetBounds(424, 124, 180, 80);
        _choices.Anchors = AnchorStyles.Top | AnchorStyles.Right;

        _low = new RadioButton(_choices);
        _low.Text = "Low";
        _low.SetBounds(0, 0, 120, 22);
        _low.Checked = true;

        _high = new RadioButton(_choices);
        _high.Text = "High";
        _high.SetBounds(0, 26, 120, 22);

        _kind = new ComboBox(this);
        _kind.SetBounds(424, 214, 180, 200);
        _kind.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        _kind.Items = ["Grocery", "Hardware", "Stationery"];
        _kind.SelectedIndex = 0;

        _notes = new TextBox(this, true);
        _notes.SetBounds(424, 250, 180, 64);
        _notes.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        _notes.Text = "Notes";

        Closing += this.OnClosingAsked;
    }

    void OnAdd(Control sender)
    {
        var what = _entry.Text;
        if (what.ByteLength() == 0u)
        {
            _status.Text = "Nothing to add.";
            return;
        }
        var line = what;
        if (_urgent.Checked)
            line = "! " + line;
        if (_high.Checked)
            line = line + "  (high)";
        _items.Add(line);
        _entry.Text = "";
        _status.Text = "Added. " + Standard.Text.FromInteger((long)_items.Count) + " item(s).";
    }

    void OnClear(Control sender)
    {
        _items.Clear();
        _status.Text = "Cleared.";
    }

    void OnChosen(Control sender)
    {
        var picked = _items.SelectedItem;
        if (picked == null)
            return;
        _status.Text = "Chose: " + (String)picked;
    }

    void OnUrgentChanged(Control sender)
    {
        _status.Text = _urgent.Checked ? "Urgent items will be marked."
                                     : "Urgent marking off.";
    }

    /// A handler that can refuse. Writing `args.Cancel = true` keeps the
    /// window open, which is the one event in the library that asks rather
    /// than reports.
    void OnClosingAsked(Control sender, CancelEventArgs args)
    {
        if (_items.Count > 0u)
        {
            args.Cancel = !Application.AskYesNo("There are items in the list. Close anyway?",
                                           "Forms for Stainless");
        }
    }

    // ------------------------------------------------------------ self test

    /// What can be checked without a person in front of it.
    public bool SelfTest()
    {
        bool ok = true;

        // Which backend, rather than that it is a particular one: this
        // sample is the same source on both, and the name is the one place
        // anything in `forms/` says a platform out loud.
        var platform = Application.PlatformName;
        ok = Check(ok, "widget set is " + platform,
                   platform == "Win32" || platform == "GTK3");

        // Docking: the header took the top of the client area and the status
        // line the bottom, each across the full width.
        var client = ClientBounds;
        ok = Check(ok, "header docked to the top",
                   _header.Top == 0 && _header.Width == client.Width);
        ok = Check(ok, "status docked to the bottom",
                   _status.Bottom == client.Height && _status.Width == client.Width);

        // The list is really a platform list, and it counts what it was given.
        _items.Clear();
        _items.Add("alpha");
        _items.Add("beta");
        ok = Check(ok, "list holds what it was given", _items.Count == 2u);
        _items.SelectedIndex = 1;
        var chosen = _items.SelectedItem;
        ok = Check(ok, "list reports the selection",
                   chosen != null && (String)chosen == "beta");

        // Text really round-trips through the native control.
        _entry.Text = "hello";
        ok = Check(ok, "text box round-trips through the platform", _entry.Text == "hello");

        // The check box's state comes from the platform, not a field.
        _urgent.Checked = true;
        ok = Check(ok, "check box reads back from the platform", _urgent.Checked);
        _urgent.Checked = false;

        // A combo box holds its items too.
        ok = Check(ok, "combo box holds its items", _kind.Count == 3u);

        // Handles are real.
        ok = Check(ok, "controls have native handles",
                   Handle != 0u && _add.Handle != 0u && _items.Handle != 0u);

        // A button asks Windows how big it wants to be.
        var wanted = _add.PreferredSize;
        ok = Check(ok, "button has a preferred size from the theme",
                   wanted.Width >= 75 && wanted.Height >= 23);

        // Fonts are inherited until set.
        ok = Check(ok, "font is inherited from the form",
                   _entry.Font.Family == Font.Family);
        ok = Check(ok, "a set font is not inherited", _title.Font.Bold);

        // **A resize must not quietly resize anything.** Reporting WM_SIZE's
        // client extent as a control's bounds shrank every bordered control by
        // its frame on each resize -- 4 pixels a time, compounding, while the
        // borderless button beside it stayed put. Nothing showed it but a
        // measurement, which is why it is measured here.
        var wasEntry = _entry.Bounds;
        var wasAdd = _add.Bounds;
        var startedAt = Bounds;
        SetBounds(startedAt.X, startedAt.Y, 900, 600);
        for (int i = 0; i < 6; i++)
            Application.DoEvents();
        SetBounds(startedAt.X, startedAt.Y, 700, 460);
        for (int i = 0; i < 6; i++)
            Application.DoEvents();

        ok = Check(ok, "a resize keeps a bordered control its size",
                   _entry.Height == wasEntry.Height);
        ok = Check(ok, "a resize keeps a plain control its size",
                   _add.Width == wasAdd.Width && _add.Height == wasAdd.Height);
        // **A window's size means different things on the two platforms**,
        // and neither is wrong: a Win32 window's bounds include its frame, so
        // the client area is narrower, while a GTK window's size *is* its
        // content. What is portable is that the form reports what it was set
        // to and that the client area is no larger than that.
        ok = Check(ok, "the form reports the size it was set to",
                   Width == 700 && Height == 460 && ClientBounds.Width <= 700);

        // A group box's frame and caption eat into where its children go, and
        // a child placed at the origin must land inside them rather than on
        // them -- so what it reports back has to be the position it was given.
        ok = Check(ok, "a group box insets its children",
                   _choices.ClientOrigin.Y > 0);
        ok = Check(ok, "a child reads back the position it was given",
                   _low.Top == 0 && _high.Top == 26);

        // **A field you type into is the window colour, not its parent's.**
        // Pushing the inherited colour at every control made every text box,
        // list and combo the form's grey, overriding what Windows would have
        // drawn. Inheritance is still right for the things that are not fields,
        // which is the other half of this check.
        ok = Check(ok, "a text box is the window colour",
                   _entry.BackColor.Equals(SystemColors.Window));
        ok = Check(ok, "a list is the window colour",
                   _items.BackColor.Equals(SystemColors.Window));
        ok = Check(ok, "a label still inherits its parent colour",
                   _title.BackColor.Equals(_header.BackColor));

        // Clicking the button runs the handler, through the real event path.
        _items.Clear();
        _entry.Text = "from a synthesised click";
        _add.PerformClick();
        ok = Check(ok, "a click reaches the handler", _items.Count == 1u);

        // Tab follows the order the controls were made, which is not the
        // stacking order on Windows: there the last made is in front.
        _entry.Focus();
        Application.DoEvents();
        SelectNextControl(true);
        Application.DoEvents();
        ok = Check(ok, "Tab goes from the entry to the button made after it", _add.Focused);
        SelectNextControl(false);
        Application.DoEvents();
        ok = Check(ok, "Shift+Tab comes back", _entry.Focused);
        _notes.Focus();
        Application.DoEvents();
        SelectNextControl(true);
        Application.DoEvents();
        ok = Check(ok, "Tab from the last control wraps to the first", _entry.Focused);

        // The arrows among radio buttons move the tick with the focus.
        _low.Checked = true;
        _low.Focus();
        Application.DoEvents();
        OnPlatformNavigate(Key.Down, false);
        Application.DoEvents();
        ok = Check(ok, "Down moves the tick to the next radio button",
                   _high.Checked && !_low.Checked && _high.Focused);
        OnPlatformNavigate(Key.Down, false);
        Application.DoEvents();
        ok = Check(ok, "and wraps within its group", _low.Checked && _low.Focused);

        return ok;
    }

    bool Check(bool running, String what, bool passed)
    {
        Console.WriteLine((passed ? "  ok   " : "  FAIL ") + what);
        return running && passed;
    }
}

int Main()
{
    Application.Initialize();

    var form = new DemoForm();

    bool testing = false;
    var arguments = Standard.Env.GetArguments();
    for (nuint i = 0u; i < arguments.Length; i++)
    {
        if (arguments[i] == "--selftest")
            testing = true;
    }

    if (testing)
    {
        Console.WriteLine("Forms for Stainless -- self test");
        form.Show();

        // Let the queue drain, so every control is really created and laid out
        // before anything is measured.
        for (int i = 0; i < 20; i++)
            Application.DoEvents();

        bool ok = form.SelfTest();
        Console.WriteLine(ok ? "all checks passed" : "checks FAILED");
        return ok ? 0 : 1;
    }

    form.CenterOnScreen();
    form.Show();
    Application.Run();
    return 0;
}
