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
public class DemoForm : Form {
    Panel    header;
    Label    title;
    Label    status;
    TextBox  entry;
    TextBox  notes;
    Button   add;
    Button   clear;
    ListBox  items;
    CheckBox urgent;
    GroupBox choices;
    RadioButton low;
    RadioButton high;
    ComboBox kind;

    public DemoForm() {
        base(WindowBorder.Sizable);

        Text = "Forms for Stainless";
        SetBounds(0, 0, 720, 480);

        // A strip across the top, which every other control's layout is
        // measured against because it takes its bite out of the client area
        // first.
        header = new Panel(this);
        header.Dock = DockStyle.Top;
        header.Height = 44;
        header.BackColor = SystemColors.ControlLight;

        title = new Label(header);
        title.Text = "Shopping list";
        title.Font = new Font("Segoe UI", 14, FontStyle.Bold);
        title.SetBounds(12, 10, 300, 26);

        // The status line, docked to the bottom, so what is left in the middle
        // is what everything else shares.
        status = new Label(this);
        status.Dock = DockStyle.Bottom;
        status.Height = 22;
        status.Text = "Ready.";

        // The entry row. Anchored left and right, so it stretches with the
        // form; the buttons anchor to the right only, so they move instead.
        entry = new TextBox(this);
        entry.SetBounds(12, 56, 400, 26);
        entry.Anchors = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;

        add = new Button(this);
        add.Text = "Add";
        add.SetBounds(424, 56, 90, 26);
        add.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        add.IsDefault = true;
        add.Click += this.OnAdd;

        clear = new Button(this);
        clear.Text = "Clear";
        clear.SetBounds(522, 56, 90, 26);
        clear.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        clear.Click += this.OnClear;

        // The list grows in both directions.
        items = new ListBox(this);
        items.SetBounds(12, 94, 400, 220);
        items.Anchors = AnchorStyles.Top | AnchorStyles.Left
                      | AnchorStyles.Right | AnchorStyles.Bottom;
        items.SelectedIndexChanged += this.OnChosen;

        urgent = new CheckBox(this);
        urgent.Text = "Urgent";
        urgent.SetBounds(424, 94, 120, 22);
        urgent.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        urgent.CheckedChanged += this.OnUrgentChanged;

        // Two radio buttons inside a group box, which is what makes them one
        // group: grouping is by parent on every platform.
        choices = new GroupBox(this);
        choices.Text = "Priority";
        choices.SetBounds(424, 124, 180, 80);
        choices.Anchors = AnchorStyles.Top | AnchorStyles.Right;

        low = new RadioButton(choices);
        low.Text = "Low";
        low.SetBounds(0, 0, 120, 22);
        low.Checked = true;

        high = new RadioButton(choices);
        high.Text = "High";
        high.SetBounds(0, 26, 120, 22);

        kind = new ComboBox(this);
        kind.SetBounds(424, 214, 180, 200);
        kind.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        kind.Items = ["Grocery", "Hardware", "Stationery"];
        kind.SelectedIndex = 0;

        notes = new TextBox(this, true);
        notes.SetBounds(424, 250, 180, 64);
        notes.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        notes.Text = "Notes";

        Closing += this.OnClosingAsked;
    }

    void OnAdd(Control sender) {
        var what = entry.Text;
        if (what.ByteLength() == 0u) {
            status.Text = "Nothing to add.";
            return;
        }
        var line = what;
        if (urgent.Checked) { line = "! " + line; }
        if (high.Checked)   { line = line + "  (high)"; }
        items.Add(line);
        entry.Text = "";
        status.Text = "Added. " + Standard.Text.FromInteger((long)items.Count) + " item(s).";
    }

    void OnClear(Control sender) {
        items.Clear();
        status.Text = "Cleared.";
    }

    void OnChosen(Control sender) {
        var picked = items.SelectedItem;
        if (picked == null) { return; }
        status.Text = "Chose: " + (String)picked;
    }

    void OnUrgentChanged(Control sender) {
        status.Text = urgent.Checked ? "Urgent items will be marked."
                                     : "Urgent marking off.";
    }

    /// A handler that can refuse. Writing `args.Cancel = true` keeps the
    /// window open, which is the one event in the library that asks rather
    /// than reports.
    void OnClosingAsked(Control sender, CancelEventArgs args) {
        if (items.Count > 0u) {
            args.Cancel = !Application.Ask("There are items in the list. Close anyway?",
                                           "Forms for Stainless");
        }
    }

    // ------------------------------------------------------------ self test

    /// What can be checked without a person in front of it.
    public bool SelfTest() {
        bool ok = true;

        ok = Check(ok, "widget set is Win32", Application.PlatformName == "Win32");

        // Docking: the header took the top of the client area and the status
        // line the bottom, each across the full width.
        var client = ClientBounds;
        ok = Check(ok, "header docked to the top",
                   header.Top == 0 && header.Width == client.Width);
        ok = Check(ok, "status docked to the bottom",
                   status.Bottom == client.Height && status.Width == client.Width);

        // The list is really a platform list, and it counts what it was given.
        items.Clear();
        items.Add("alpha");
        items.Add("beta");
        ok = Check(ok, "list holds what it was given", items.Count == 2u);
        items.SelectedIndex = 1;
        var chosen = items.SelectedItem;
        ok = Check(ok, "list reports the selection",
                   chosen != null && (String)chosen == "beta");

        // Text really round-trips through the native control.
        entry.Text = "hello";
        ok = Check(ok, "text box round-trips through Windows", entry.Text == "hello");

        // The check box's state comes from the platform, not a field.
        urgent.Checked = true;
        ok = Check(ok, "check box reads back from Windows", urgent.Checked);
        urgent.Checked = false;

        // A combo box holds its items too.
        ok = Check(ok, "combo box holds its items", kind.Count == 3u);

        // Handles are real.
        ok = Check(ok, "controls have native handles",
                   Handle != 0u && add.Handle != 0u && items.Handle != 0u);

        // A button asks Windows how big it wants to be.
        var wanted = add.PreferredSize;
        ok = Check(ok, "button has a preferred size from the theme",
                   wanted.Width >= 75 && wanted.Height >= 23);

        // Fonts are inherited until set.
        ok = Check(ok, "font is inherited from the form",
                   entry.Font.Family == Font.Family);
        ok = Check(ok, "a set font is not inherited", title.Font.Bold);

        // **A resize must not quietly resize anything.** Reporting WM_SIZE's
        // client extent as a control's bounds shrank every bordered control by
        // its frame on each resize -- 4 pixels a time, compounding, while the
        // borderless button beside it stayed put. Nothing showed it but a
        // measurement, which is why it is measured here.
        var wasEntry = entry.Bounds;
        var wasAdd = add.Bounds;
        var startedAt = Bounds;
        SetBounds(startedAt.X, startedAt.Y, 900, 600);
        for (int i = 0; i < 6; i += 1) { Application.DoEvents(); }
        SetBounds(startedAt.X, startedAt.Y, 700, 460);
        for (int i = 0; i < 6; i += 1) { Application.DoEvents(); }

        ok = Check(ok, "a resize keeps a bordered control its size",
                   entry.Height == wasEntry.Height);
        ok = Check(ok, "a resize keeps a plain control its size",
                   add.Width == wasAdd.Width && add.Height == wasAdd.Height);
        ok = Check(ok, "the form reports its window size, not its client size",
                   Width == 700 && Height == 460 && ClientBounds.Width < 700);

        // A group box's frame and caption eat into where its children go, and
        // a child placed at the origin must land inside them rather than on
        // them -- so what it reports back has to be the position it was given.
        ok = Check(ok, "a group box insets its children",
                   choices.ClientOrigin.Y > 0);
        ok = Check(ok, "a child reads back the position it was given",
                   low.Top == 0 && high.Top == 26);

        // **A field you type into is the window colour, not its parent's.**
        // Pushing the inherited colour at every control made every text box,
        // list and combo the form's grey, overriding what Windows would have
        // drawn. Inheritance is still right for the things that are not fields,
        // which is the other half of this check.
        ok = Check(ok, "a text box is the window colour",
                   entry.BackColor.Equals(SystemColors.Window));
        ok = Check(ok, "a list is the window colour",
                   items.BackColor.Equals(SystemColors.Window));
        ok = Check(ok, "a label still inherits its parent colour",
                   title.BackColor.Equals(header.BackColor));

        // Clicking the button runs the handler, through the real event path.
        items.Clear();
        entry.Text = "from a synthesised click";
        add.PerformClick();
        ok = Check(ok, "a click reaches the handler", items.Count == 1u);

        return ok;
    }

    bool Check(bool running, String what, bool passed) {
        Console.WriteLine((passed ? "  ok   " : "  FAIL ") + what);
        return running && passed;
    }
}

int Main() {
    Application.Initialize();

    var form = new DemoForm();

    bool testing = false;
    var arguments = Standard.Env.Arguments();
    for (nuint i = 0u; i < arguments.Length; i += 1u) {
        if (arguments[i] == "--selftest") { testing = true; }
    }

    if (testing) {
        Console.WriteLine("Forms for Stainless -- self test");
        form.Show();

        // Let the queue drain, so every control is really created and laid out
        // before anything is measured.
        for (int i = 0; i < 20; i += 1) { Application.DoEvents(); }

        bool ok = form.SelfTest();
        Console.WriteLine(ok ? "all checks passed" : "checks FAILED");
        return ok ? 0 : 1;
    }

    form.CenterOnScreen();
    form.Show();
    Application.Run();
    return 0;
}
