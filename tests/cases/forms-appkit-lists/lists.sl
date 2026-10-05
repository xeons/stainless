// SPDX-License-Identifier: 0BSD
//
// The lists on AppKit: a click on a row of each table reaches the control as
// the user's choice, and what the program changes reads back without being
// reported as one.
module AppKitLists;

import Standard.Collections;
import Standard.Console;
import Standard.Text;
import Standard.ObjC;
import Forms;
import Forms.Drawing;
import Forms.Platform;
import Forms.Platform.AppKit;
import MacOS.System;
import MacOS.Foundation;
import MacOS.AppKit;

class ListsForm : Form
{
    public String Seen;
    late ListBox _list;
    late CheckListBox _checks;
    late ComboBox _combo;
    late HeaderControl _header;
    late TreeView _tree;
    late TreeNode _root;
    late ListView _view;
    Timer _clock;
    int _ticks;

    public ListsForm()
    {
        Seen = "";
        _clock = new Timer(100);
        base();
        Text = "AppKit lists";
        SetBounds(160, 160, 640, 360);
        _ticks = 0;

        _list = new ListBox(this);
        _list.SetBounds(16, 16, 140, 120);
        _list.Items = ["a", "b", "c"];
        _list.SelectedIndexChanged += (sender) => this.Note("list chose " + Standard.Text.FromInteger(this.ListIndex));

        _checks = new CheckListBox(this);
        _checks.SetBounds(172, 16, 140, 120);
        _checks.Items = ["one", "two", "three"];
        _checks.SelectedIndexChanged += (sender) => this.Note("checks " + this.DescribeChecks());

        _combo = new ComboBox(this);
        _combo.SetBounds(328, 16, 140, 26);
        _combo.Items = ["red", "green", "blue"];
        _combo.SelectedIndexChanged += (sender) => this.Note("combo changed by the program");

        _header = new HeaderControl(this);
        _header.SetBounds(328, 60, 280, 28);
        _header.Add("Name", 120);
        _header.Add("Size", 60);
        _header.SectionResized += (sender) => this.Note("header resized");

        _tree = new TreeView(this);
        _tree.SetBounds(16, 152, 200, 180);
        _root = _tree.Add("Root");
        _root.Add("Leaf A");
        _root.Add("Leaf B");
        _root.Expand();
        _tree.SelectedNodeChanged += (sender) => this.Note("tree chose " + this.TreeChoice);

        _view = new ListView(this);
        _view.SetBounds(232, 152, 380, 180);
        _view.AddColumn("Name", 160);
        _view.AddColumn("Size", 80, HorizontalAlignment.Right);
        _view.AddRow(["readme", "1 KB"]);
        _view.AddRow(["picture", "2 KB"]);
        _view.SelectedIndexChanged += (sender) => this.Note("view chose " + Standard.Text.FromInteger(this.ViewIndex));

        _clock.Tick += this.OnTick;
        _clock.Start();
    }

    public int ListIndex => _list.SelectedIndex;
    public int ViewIndex => _view.SelectedIndex;

    public String TreeChoice
    {
        get
        {
            var chosen = _tree.SelectedNode;
            return chosen == null ? "nothing" : ((TreeNode)chosen).Text;
        }
    }

    public String DescribeChecks()
    {
        String text = "";
        foreach (var index in _checks.CheckedIndices)
            text = text + (text == "" ? "" : " ") + Standard.Text.FromInteger(index);
        return text == "" ? "none" : text;
    }

    String DescribeChoice()
    {
        var chosen = _combo.SelectedItem;
        return chosen == null ? "nothing" : (String)chosen;
    }

    public void Note(String what) => Seen = Seen + what + "\n";

    void OnTick(Timer sender)
    {
        _ticks++;
        if (_ticks == 2)
            SendInput();
        if (_ticks == 3)
        {
            ReadBack();
            Close();
        }
    }

    NSWindow FindWindow() => ((AppKitWindowPeer)WindowPeer).Window;

    /// Every table in the form, in the order they were made.
    void FindTables(NSView view, List<NSTableView> into)
    {
        if (view is NSTableView table)
        {
            into.Add(table);
            return;
        }
        var children = view.Subviews;
        for (nuint i = 0u; i < children.Count; i++)
            FindTables((NSView)children.ObjectAtIndex(i), into);
    }

    NSTableView FindTable(int which)
    {
        var tables = new List<NSTableView>();
        FindTables(FindWindow().ContentView!, tables);
        return tables[(nuint)which];
    }

    /// The middle of a row, or `x` across it, in the table's own coordinates.
    NSPoint FindRowPoint(NSTableView table, int row, double x)
    {
        var rect = table.RectOfRow((NSInteger)row);
        NSPoint at;
        at.x = x < 0.0 ? rect.origin.x + rect.size.width / 2.0 : rect.origin.x + x;
        at.y = rect.origin.y + rect.size.height / 2.0;
        return at;
    }

    void Click(NSTableView table, int row, double x)
    {
        var window = FindWindow();
        var at = table.ConvertPointToView(FindRowPoint(table, row, x), null);
        var down = NSEvent.MouseEventWithTypeLocationModifierFlagsTimestampWindowNumberContextEventNumberClickCountPressure(
            NSEventType.LeftMouseDown, at, (NSEventModifierFlags)0u, 0.0, window.WindowNumber, null, 0, 1, 1.0f);
        var up = NSEvent.MouseEventWithTypeLocationModifierFlagsTimestampWindowNumberContextEventNumberClickCountPressure(
            NSEventType.LeftMouseUp, at, (NSEventModifierFlags)0u, 0.0, window.WindowNumber, null, 0, 1, 1.0f);
        // A table tracks the press in a loop of its own until the release, so
        // the release is queued first for that loop to find.
        NSApplication.SharedApplication.PostEventAtStart(up!, true);
        window.SendEvent(down!);
    }

    void SendInput()
    {
        Click(FindTable(0), 1, -1.0);
        Click(FindTable(1), 2, 11.0);
        Click(FindTable(3), 2, -1.0);
        Click(FindTable(4), 1, -1.0);
    }

    void ReadBack()
    {
        _list.SelectedIndex = 2;
        _list.Insert(0u, "z");
        int moved = _list.SelectedIndex;
        _list.RemoveAt(3u);
        Note("list: " + Standard.Text.FromInteger(moved) + " then " + Standard.Text.FromInteger(_list.SelectedIndex)
             + ", " + Standard.Text.FromInteger((int)_list.Count) + " items");

        _checks.SetItemChecked(0, true);
        Note("checks: " + DescribeChecks());

        _combo.SelectedIndex = 1;
        String shown = DescribeChoice();
        _combo.Editable = true;
        String typed = DescribeChoice();
        _combo.SelectedIndex = 2;
        _combo.Insert(0u, "cyan");
        Note("combo: " + shown + ", editable " + typed + ", moved to " + DescribeChoice());

        _header.SetSectionWidth(1, 80);
        Note("header: " + Standard.Text.FromInteger(_header.Count) + " sections, "
             + Standard.Text.FromInteger(_header.GetSectionWidth(0)) + " and "
             + Standard.Text.FromInteger(_header.GetSectionWidth(1)));

        var middle = FindRowPoint(FindTable(3), 1, -1.0);
        var under = _tree.GetNodeAt(CreatePoint((int)middle.x, (int)middle.y));
        Note("tree: under row 1 is " + (under == null ? "nothing" : ((TreeNode)under).Text)
             + ", " + Standard.Text.FromInteger((int)_root.Nodes.Count) + " leaves");

        Note("view: cell " + _view.GetCellText(1, 1));
        _view.RemoveRow(0);
        Note("view: " + Standard.Text.FromInteger(_view.SelectedIndex) + " chosen of "
             + Standard.Text.FromInteger(_view.Count));
    }
}

int Main()
{
    Application.Initialize();
    var form = new ListsForm();
    form.Show();
    Application.Run();
    Console.Write(form.Seen);
    return 0;
}
