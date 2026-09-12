// SPDX-License-Identifier: 0BSD
//
// The common controls: a menu bar, a toolbar, a status bar, tabs, a tree, a
// list, a progress bar and a slider.
//
//   stainless run samples/forms/common.sl forms/src bindings/win32/api \
//       bindings/win32/Win32.sl -l user32 -l gdi32 -l comctl32
//
// `--selftest` builds the same window, checks what it can without a person in
// front of it, and quits.
module Common;

import Standard.Console;
import Standard.Text;
import Standard.Collections;
import Standard.Threading;
import Standard.Convert;
import Forms;
import Forms.Drawing;
import Forms.Platform;

public class CommonForm : Form {
    ToolBar     tools;
    StatusBar   status;
    TabControl  tabs;
    TabPage     treePage;
    TabPage     listPage;
    TabPage     gaugePage;
    TabPage     formPage;
    TreeView    tree;
    ListView    list;
    ProgressBar progress;
    TrackBar    slider;
    Label       readout;
    ImageList   icons;
    PopupMenu   context;

    public MenuItem WrapItem;
    public ToolButton BoldButton;
    public Bevel    Divider;
    public RadioGroup Priority;
    public CheckGroup Options;
    public LabeledEdit Named;
    public SpinEdit Quantity;
    public CheckListBox Chores;
    public HeaderControl Headings;
    public Shape    Blob;
    public PaintBox Canvas;
    public Timer    Clock;
    public int      Ticks;

    public CommonForm() {
        base(WindowBorder.Sizable);
        Text = "Common controls";
        SetBounds(0, 0, 820, 560);

        icons = new ImageList(16, 16);
        Ticks = 0;
        clicks = 0;

        BuildMenu();

        // A toolbar docked to the top, which takes its bite out of the client
        // area before anything else is laid out.
        tools = new ToolBar(this);
        tools.Dock = DockStyle.Top;
        tools.Height = 34;
        tools.Add("New").Click += this.OnNew;
        tools.Add("Open").Click += this.OnOpen;
        tools.AddSeparator();
        BoldButton = tools.AddToggle("Bold", -1);
        BoldButton.Click += this.OnBold;

        // And a status bar at the bottom, which docks itself.
        status = new StatusBar(this);
        status.AddPanel(160);
        status.AddPanel(120);
        status.AddPanel(-1);
        status.SetPanelText(0, "Ready.");
        status.SetPanelText(1, "");
        status.SetPanelText(2, "");

        // Everything else goes on the tabs, which fill what is left.
        tabs = new TabControl(this);
        tabs.Dock = DockStyle.Fill;
        tabs.SelectedIndexChanged += this.OnTabChanged;

        treePage = new TabPage(tabs, "Tree");
        tree = new TreeView(treePage);
        tree.Dock = DockStyle.Fill;
        tree.Images = icons;
        var shops = tree.Add("Shopping");
        shops.Add("Grocery").Add("Apples");
        shops.Add("Hardware");
        var trips = tree.Add("Trips");
        trips.Add("Hardware shop");
        shops.Expand();
        tree.SelectedNodeChanged += this.OnNodeChosen;

        listPage = new TabPage(tabs, "List");
        list = new ListView(listPage);
        list.Dock = DockStyle.Fill;
        list.AddColumn("Item", 220);
        list.AddColumn("Quantity", 90, HorizontalAlignment.Right);
        list.AddColumn("Where", 160);
        list.SetFullRowSelect(true, true);
        list.AddRow(["Apples", "6", "Grocery"]);
        list.AddRow(["Screws", "40", "Hardware"]);
        list.AddRow(["Notebook", "2", "Stationery"]);
        list.SelectedIndexChanged += this.OnRowChosen;

        gaugePage = new TabPage(tabs, "Gauges");
        progress = new ProgressBar(gaugePage);
        progress.SetBounds(16, 24, 360, 22);
        progress.Anchors = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        progress.Value = 40;

        slider = new TrackBar(gaugePage);
        slider.SetBounds(16, 60, 360, 36);
        slider.Anchors = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        slider.Maximum = 100;
        slider.Value = 40;
        slider.ValueChanged += this.OnSlide;

        readout = new Label(gaugePage);
        readout.SetBounds(16, 104, 360, 20);
        readout.Text = "40%";

        // The windowless half of the control split, which costs a `Control`
        // object each and no platform window at all.
        Divider = new Bevel(gaugePage);
        Divider.SetBounds(16, 132, 360, 2);
        Divider.Kind = BevelKind.TopLine;

        Blob = new Shape(gaugePage);
        Blob.SetBounds(16, 146, 60, 60);
        Blob.Kind = ShapeKind.Circle;
        Blob.FillColor = Colors.Teal;

        Canvas = new PaintBox(gaugePage);
        Canvas.SetBounds(90, 146, 286, 60);
        Canvas.Paint += this.OnDraw;
        Canvas.MouseDown += this.OnCanvasDown;

        Clock = new Timer(100);
        Clock.Tick += this.OnTick;

        // A fourth page, for the composites -- each of which is a container
        // that builds its own children rather than a platform widget.
        formPage = new TabPage(tabs, "Form");

        Priority = new RadioGroup(formPage);
        Priority.Text = "Priority";
        Priority.SetBounds(12, 12, 180, 96);
        Priority.Add("Low");
        Priority.Add("Normal");
        Priority.Add("High");
        Priority.SelectedIndex = 1;
        Priority.SelectedIndexChanged += this.OnPriority;

        Options = new CheckGroup(formPage);
        Options.Text = "Options";
        Options.SetBounds(204, 12, 180, 96);
        Options.Add("Urgent");
        Options.Add("Repeat");
        Options.Add("Notify");
        Options.SetChecked(0, true);

        Named = new LabeledEdit(formPage);
        Named.SetBounds(12, 120, 240, 44);
        Named.Caption = "Item name";
        Named.Value = "Apples";

        Quantity = new SpinEdit(formPage);
        Quantity.SetBounds(264, 138, 80, 26);
        Quantity.Minimum = 1;
        Quantity.Maximum = 99;
        Quantity.Value = 6;

        Chores = new CheckListBox(formPage);
        Chores.SetBounds(12, 176, 240, 110);
        Chores.Add("Buy milk");
        Chores.Add("Post letter");
        Chores.Add("Fix shelf");
        Chores.SetChecked(1, true);

        Headings = new HeaderControl(formPage);
        Headings.SetBounds(264, 176, 240, 24);
        Headings.Add("Name", 120);
        Headings.Add("Size", 80);

        // A context menu, built once and shown where the user asked for it.
        context = new PopupMenu();
        context.Add("Add a row").Click += this.OnAddRow;
        context.Add("Remove the row").Click += this.OnRemoveRow;
        context.Add(MenuItem.Separator());
        context.Add("Clear").Click += this.OnClearList;
        list.MouseUp += this.OnListMouseUp;
    }

    void BuildMenu() {
        var bar = new MainMenu();

        var file = bar.Add("&File");
        file.Add("&New").Click += this.OnNew;
        file.Add("&Open...").Click += this.OnOpen;
        file.Add(MenuItem.Separator());
        file.Add("E&xit").Click += this.OnExit;

        var view = bar.Add("&View");
        WrapItem = view.Add("&Wrap captions");
        WrapItem.Checked = true;
        WrapItem.Click += this.OnToggleWrap;

        var gauge = view.Add("&Progress");
        gauge.Add("&Empty").Click += this.OnEmpty;
        gauge.Add("&Half").Click += this.OnHalf;
        gauge.Add("&Full").Click += this.OnFull;

        Menu = bar;
    }

    // ------------------------------------------------------------- handlers

    void Say(String what) { status.SetPanelText(0, what); }

    /// Drawn by the parent during its own paint, in the box's own coordinates.
    void OnDraw(Control sender, PaintEventArgs args) {
        var surface = args.Graphics;
        surface.FillRectangle(new Brush(SystemColors.Window), args.ClipRectangle);
        var pen = new Pen(Colors.Navy, 2, PenStyle.Solid);
        // From the box's own corner, whatever the form has been resized to.
        surface.DrawLine(pen, 0, Canvas.Height, Canvas.Width, 0);
        surface.DrawString("PaintBox", Font, Colors.Maroon, 6, 6);
    }

    void OnTick(Timer sender) { Ticks = Ticks + 1; }

    void OnPriority(Control sender) {
        var chosen = Priority.SelectedText;
        if (chosen == null) { return; }
        Say("Priority: " + (String)chosen);
    }

    void OnCanvasDown(Control sender, MouseEventArgs args) { clicks = clicks + 1; }

    int clicks;

    void OnNew(Control sender)       { Say("New."); }
    void OnNew(MenuItem sender)      { Say("New, from the menu."); }
    void OnOpen(Control sender)      { Say("Open."); }
    void OnOpen(MenuItem sender)     { Say("Open, from the menu."); }
    void OnExit(MenuItem sender)     { Close(); }

    void OnBold(Control sender) {
        Say(BoldButton.Checked ? "Bold on." : "Bold off.");
    }

    void OnToggleWrap(MenuItem sender) {
        sender.Checked = !sender.Checked;
        tools.ShowText = sender.Checked;
        Say(sender.Checked ? "Captions shown." : "Captions hidden.");
    }

    void OnEmpty(MenuItem sender) { SetProgress(0); }
    void OnHalf(MenuItem sender)  { SetProgress(50); }
    void OnFull(MenuItem sender)  { SetProgress(100); }

    void SetProgress(int value) {
        progress.Value = value;
        slider.Value = value;
        readout.Text = Standard.Text.FromInteger((long)value) + "%";
    }

    void OnSlide(Control sender) {
        progress.Value = slider.Value;
        readout.Text = Standard.Text.FromInteger((long)slider.Value) + "%";
    }

    void OnTabChanged(Control sender) {
        status.SetPanelText(1, "Tab " + Standard.Text.FromInteger((long)tabs.SelectedIndex));
    }

    void OnNodeChosen(Control sender) {
        var node = tree.SelectedNode;
        if (node == null) { return; }
        Say("Node: " + ((TreeNode)node).Text);
    }

    void OnRowChosen(Control sender) {
        status.SetPanelText(2, "Row "
            + Standard.Text.FromInteger((long)list.SelectedIndex));
    }

    void OnListMouseUp(Control sender, MouseEventArgs args) {
        if (args.Button != MouseButton.Right) { return; }
        context.Show(list, args.Location);
    }

    void OnAddRow(MenuItem sender) {
        list.AddRow(["New item", "1", "Somewhere"]);
        Say("Added a row.");
    }

    void OnRemoveRow(MenuItem sender) {
        int at = list.SelectedIndex;
        if (at < 0) {
            Say("Nothing selected.");
            return;
        }
        list.RemoveRow(at);
        Say("Removed a row.");
    }

    void OnClearList(MenuItem sender) {
        list.Clear();
        Say("Cleared.");
    }

    /// Opens on a given tab, for a screenshot of one that is not the first.
    public void SelectTab(int which) {
        if (which < 0 || (nuint)which >= tabs.Pages.Count()) { return; }
        tabs.SelectedIndex = which;
    }

    // ------------------------------------------------------------ self test

    public bool SelfTest() {
        bool ok = true;

        ok = Check(ok, "toolbar has its buttons", tools.Buttons.Count() == 4u);
        ok = Check(ok, "status bar has its panels", status.PanelCount == 3u);
        ok = Check(ok, "status panel text round-trips",
                   status.PanelText(0) == "Ready.");

        ok = Check(ok, "tabs hold their pages", tabs.Pages.Count() == 4u);
        ok = Check(ok, "the platform has the tabs too", tabs.TabCount == 4);
        ok = Check(ok, "one page is showing at a time",
                   treePage.Visible && !listPage.Visible
                   && !gaugePage.Visible && !formPage.Visible);

        tabs.SelectedIndex = 1;
        for (int i = 0; i < 6; i += 1) { Application.DoEvents(); }
        ok = Check(ok, "choosing a tab shows only that page",
                   !treePage.Visible && listPage.Visible);
        ok = Check(ok, "a page fills the area under the tabs",
                   listPage.Width > 0 && listPage.Height > 0);

        ok = Check(ok, "tree holds its roots", tree.Nodes.Count() == 2u);
        ok = Check(ok, "a tree node reads back its text",
                   tree.Nodes.At(0u).Text == "Shopping");
        var under = tree.Nodes.At(0u).Nodes;
        ok = Check(ok, "a node holds its children", under.Count() == 2u);
        tree.SelectedNode = under.At(0u);
        for (int i = 0; i < 4; i += 1) { Application.DoEvents(); }
        var chosen = tree.SelectedNode;
        ok = Check(ok, "the tree reports the selected node",
                   chosen != null && ((TreeNode)chosen).Text == "Grocery");

        // **Counted *and* read back.** Sending a wide string to the ANSI form
        // of a message does not fail: the control takes it, reads the text as
        // ANSI and stops at the first character's zero high byte -- so the row
        // exists, the count is right, and the caption is a single letter. Only
        // reading the text finds that.
        ok = Check(ok, "list holds its rows", list.Count == 3);
        ok = Check(ok, "a list cell keeps its whole text",
                   list.CellText(0, 0) == "Apples");
        ok = Check(ok, "a list cell past the first does too",
                   list.CellText(1, 2) == "Hardware");
        list.SelectedIndex = 2;
        for (int i = 0; i < 4; i += 1) { Application.DoEvents(); }
        ok = Check(ok, "the list reports the selected row", list.SelectedIndex == 2);
        list.RemoveRow(0);
        ok = Check(ok, "a row can be removed", list.Count == 2);

        progress.Value = 75;
        ok = Check(ok, "progress round-trips through Windows", progress.Value == 75);
        slider.Value = 30;
        ok = Check(ok, "the slider round-trips too", slider.Value == 30);

        // The menu tree is real: every item became a platform item when the bar
        // was assigned, and the state set beforehand went down with it.
        ok = Check(ok, "the menu was built", Menu != null);
        ok = Check(ok, "a menu item keeps its tick", WrapItem.Checked);
        WrapItem.Checked = false;
        ok = Check(ok, "a tick can be changed after building", !WrapItem.Checked);

        // The toolbar button is really a toolbar button.
        BoldButton.Checked = true;
        ok = Check(ok, "a toggle button reads back from Windows", BoldButton.Checked);
        BoldButton.Checked = false;

        // **The windowless controls.** A `GraphicControl` has no platform
        // window, so nothing about it can be asked of Windows -- which is
        // exactly why it is worth checking that it exists, is laid out, and
        // gets the mouse the parent has to hand it.
        // There is no `Handle` to check: it is declared on `WindowedControl`,
        // so a graphic control does not have one to be zero -- the split is in
        // the type rather than in a flag.
        ok = Check(ok, "a graphic control is laid out",
                   Canvas.Width == 286 && Canvas.Height == 60);
        ok = Check(ok, "and is on the page",
                   Canvas.Parent != null && Canvas.FindForm() != null);

        // The parent hit-tests and forwards, since the pointer never crosses a
        // window boundary for a control that has no window.
        int wasClicked = clicks;
        gaugePage.OnPlatformMouseDown(MouseButton.Left,
                                      Point.At(Canvas.Left + 5, Canvas.Top + 5),
                                      ModifierKeys.None);
        ok = Check(ok, "the parent routes the mouse to a graphic child",
                   clicks == wasClicked + 1);

        // And a point outside it reaches no graphic child at all.
        gaugePage.OnPlatformMouseDown(MouseButton.Left, Point.At(2, 2),
                                      ModifierKeys.None);
        ok = Check(ok, "and not to one the pointer is not over",
                   clicks == wasClicked + 1);

        // **The timer needs real time, not just pumping.** `WM_TIMER` is a
        // low-priority message: Windows generates one only when the queue is
        // otherwise empty *and* the interval has elapsed, so a tight loop of
        // eighty pumps finishes in microseconds and sees nothing at all. The
        // sleep is what makes this a test of the timer rather than of the loop.
        Clock.Interval = 20;
        Clock.Start();
        for (int i = 0; i < 40; i += 1) {
            Standard.Threading.Sleep(10u);
            Application.DoEvents();
        }
        Clock.Stop();
        ok = Check(ok, "a timer ticks off the message queue", Ticks > 0);

        // **The composites.** Each builds its own children, so what is worth
        // checking is that they were built, laid out inside the parent, and
        // that reading a value goes to the child rather than to a field that
        // could disagree with it.
        ok = Check(ok, "a radio group built its buttons",
                   Priority.Count == 3u && Priority.Buttons.Count() == 3u);
        ok = Check(ok, "and reads its choice from them",
                   Priority.SelectedIndex == 1);
        Priority.SelectedIndex = 2;
        ok = Check(ok, "and follows a change",
                   Priority.SelectedIndex == 2
                   && Priority.Buttons.At(2u).Checked);
        ok = Check(ok, "and lays them inside itself",
                   Priority.Buttons.At(0u).Top == 0
                   && Priority.Buttons.At(1u).Top > 0);

        ok = Check(ok, "a check group holds several ticks",
                   Options.IsChecked(0) && !Options.IsChecked(1));
        Options.SetChecked(2, true);
        ok = Check(ok, "and reports which", Options.CheckedIndices.Length == 2u);

        ok = Check(ok, "a labelled edit keeps caption and value apart",
                   Named.Caption == "Item name" && Named.Value == "Apples");
        Named.Value = "Pears";
        ok = Check(ok, "and writes through to the box",
                   Named.Entry.Text == "Pears");

        ok = Check(ok, "a spin edit round-trips through Windows",
                   Quantity.Value == 6);
        Quantity.Value = 42;
        ok = Check(ok, "and follows a change", Quantity.Value == 42);

        ok = Check(ok, "a check list holds its items", Chores.Count == 3u);
        ok = Check(ok, "and its ticks",
                   Chores.IsChecked(1) && !Chores.IsChecked(0));
        Chores.SetChecked(2, true);
        ok = Check(ok, "and reports which", Chores.CheckedIndices.Length == 2u);

        ok = Check(ok, "a header holds its sections", Headings.Count == 2);
        ok = Check(ok, "and its widths", Headings.SectionWidth(0) == 120);

        // And loading a picture that is not there says so, rather than
        // answering a null nobody checks.
        var missing = Bitmap.FromFile("no-such-file.bmp");
        ok = Check(ok, "a missing picture is an error, not a null", !missing.Ok);

        return ok;
    }

    bool Check(bool running, String what, bool passed) {
        Console.WriteLine((passed ? "  ok   " : "  FAIL ") + what);
        return running && passed;
    }
}

int Main() {
    Application.Initialize();
    var form = new CommonForm();

    bool testing = false;
    var arguments = Standard.Env.Arguments();
    for (nuint i = 0u; i < arguments.Length; i += 1u) {
        if (arguments[i] == "--selftest") { testing = true; }
        // Which tab to open on, so that a screenshot can be taken of one that
        // is not the first.
        if (arguments[i] == "--tab" && i + 1u < arguments.Length) {
            var which = Standard.Convert.ToInt(arguments[i + 1u]);
            if (which.Ok) { form.SelectTab(which.Value); }
        }
    }

    if (testing) {
        Console.WriteLine("Forms for Stainless -- common controls");
        form.Show();
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
