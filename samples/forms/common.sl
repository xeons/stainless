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
    TreeView    tree;
    ListView    list;
    ProgressBar progress;
    TrackBar    slider;
    Label       readout;
    ImageList   icons;
    PopupMenu   context;

    public MenuItem WrapItem;
    public ToolButton BoldButton;

    public CommonForm() {
        base(WindowBorder.Sizable);
        Text = "Common controls";
        SetBounds(0, 0, 820, 560);

        icons = new ImageList(16, 16);

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

    // ------------------------------------------------------------ self test

    public bool SelfTest() {
        bool ok = true;

        ok = Check(ok, "toolbar has its buttons", tools.Buttons.Count() == 4u);
        ok = Check(ok, "status bar has its panels", status.PanelCount == 3u);
        ok = Check(ok, "status panel text round-trips",
                   status.PanelText(0) == "Ready.");

        ok = Check(ok, "tabs hold their pages", tabs.Pages.Count() == 3u);
        ok = Check(ok, "the platform has the tabs too", tabs.TabCount == 3);
        ok = Check(ok, "one page is showing at a time",
                   treePage.Visible && !listPage.Visible && !gaugePage.Visible);

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
