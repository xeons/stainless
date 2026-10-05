// SPDX-License-Identifier: 0BSD
//
// The bars on AppKit: a toolbar's buttons and toggle answer a click, a tab
// control changes page when its tab is clicked, and a status bar shows what
// it is given.
module AppKitBars;

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

class BarsForm : Form
{
    public String Seen;
    late ToolBar _tools;
    late ToolButton _open;
    late ToolButton _bold;
    late StatusBar _status;
    late TabControl _tabs;
    late TabPage _first;
    late TabPage _second;
    late Label _inside;
    Timer _clock;
    int _ticks;

    public BarsForm()
    {
        Seen = "";
        _ticks = 0;
        _clock = new Timer(100);
        base();
        Text = "AppKit bars";
        SetBounds(160, 160, 480, 320);

        _tools = new ToolBar(this);
        _tools.Dock = DockStyle.Top;
        _tools.ShowText = true;
        _open = _tools.Add("Open");
        _open.Click += (sender) => this.Note("clicked Open");
        _tools.AddSeparator();
        _bold = _tools.AddToggle("Bold", -1);
        _bold.Click += (sender) => this.Note("Bold is " + (this.IsBold ? "on" : "off"));

        _status = new StatusBar(this);
        _status.Dock = DockStyle.Bottom;
        _status.AddPanel(160);
        _status.AddPanel(-1);
        _status.SetPanelText(0, "Ready");
        _status.SetPanelText(1, "no file");

        _tabs = new TabControl(this);
        _tabs.Dock = DockStyle.Fill;
        _first = new TabPage(_tabs, "First");
        _second = new TabPage(_tabs, "Second");
        _inside = new Label(_second);
        _inside.Text = "on the second page";
        _inside.SetBounds(8, 8, 160, 20);
        _tabs.SelectedIndexChanged += (sender) => this.Note("tab " + Standard.Text.FromInteger(this.TabIndex));

        _clock.Tick += this.OnTick;
        _clock.Start();
    }

    public bool IsBold => _bold.Checked;
    public int TabIndex => _tabs.SelectedIndex;

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

    /// The tab view in the form, depth first.
    NSTabView? FindTabView(NSView view)
    {
        if (view is NSTabView tabs)
            return tabs;
        var children = view.Subviews;
        for (nuint i = 0u; i < children.Count; i++)
        {
            if (FindTabView((NSView)children.ObjectAtIndex(i)) is NSTabView found)
                return found;
        }
        return null;
    }

    NSTabView FindTabs() => FindTabView(FindWindow().ContentView!)!;

    /// The button captioned `title` in the form, depth first.
    NSButton? FindButtonView(NSView view, String title)
    {
        if (view is NSButton button && FromNSString(button.Title) == title)
            return button;
        var children = view.Subviews;
        for (nuint i = 0u; i < children.Count; i++)
        {
            if (FindButtonView((NSView)children.ObjectAtIndex(i), title) is NSButton found)
                return found;
        }
        return null;
    }

    /// The middle of the button captioned `title`, in the window.
    NSPoint FindButton(String title)
    {
        var button = FindButtonView(FindWindow().ContentView!, title)!;
        var bounds = button.Bounds;
        NSPoint middle;
        middle.x = bounds.size.width / 2.0;
        middle.y = bounds.size.height / 2.0;
        return button.ConvertPointToView(middle, null);
    }

    /// A point on the tab of page `index`, found by asking the tab view what
    /// is under each point of its tab strip.
    NSPoint FindTab(int index)
    {
        var tabs = FindTabs();
        var wanted = tabs.TabViewItemAtIndex((NSInteger)index);
        var bounds = tabs.Bounds;
        for (double y = 0.0; y < bounds.size.height; y += 2.0)
        {
            for (double x = 0.0; x < bounds.size.width; x += 4.0)
            {
                NSPoint at;
                at.x = x;
                at.y = y;
                var hit = tabs.TabViewItemAtPoint(at);
                if (hit != null && (NSTabViewItem)hit == wanted)
                    return tabs.ConvertPointToView(at, null);
            }
        }
        NSPoint none;
        none.x = -1.0;
        none.y = -1.0;
        return none;
    }

    void Click(NSPoint at)
    {
        var window = FindWindow();
        var down = NSEvent.MouseEventWithTypeLocationModifierFlagsTimestampWindowNumberContextEventNumberClickCountPressure(
            NSEventType.LeftMouseDown, at, (NSEventModifierFlags)0u, 0.0, window.WindowNumber, null, 0, 1, 1.0f);
        var up = NSEvent.MouseEventWithTypeLocationModifierFlagsTimestampWindowNumberContextEventNumberClickCountPressure(
            NSEventType.LeftMouseUp, at, (NSEventModifierFlags)0u, 0.0, window.WindowNumber, null, 0, 1, 1.0f);
        // A control tracks the press in a loop of its own until the release,
        // so the release is queued first for that loop to find.
        NSApplication.SharedApplication.PostEventAtStart(up!, true);
        window.SendEvent(down!);
    }

    void SendInput()
    {
        Click(FindButton("Open"));
        Click(FindButton("Bold"));
        Click(FindTab(1));
    }

    void ReadBack()
    {
        Note("status: " + _status.GetPanelText(0) + ", " + _status.GetPanelText(1));
        Note("toolbar " + (_tools.Bounds.Height > 0 && _tools.Bounds.Y == 0 ? "docked at the top" : "misplaced")
             + ", status bar " + (_status.Bounds.Y + _status.Bounds.Height == ClientBounds.Height ? "at the bottom" : "misplaced"));
        Note("page " + Standard.Text.FromInteger(_tabs.SelectedIndex) + " of "
             + Standard.Text.FromInteger(_tabs.TabCount) + ", label "
             + (_second.Visible && !_first.Visible ? "showing" : "hidden"));
        _tabs.SelectedIndex = 0;
        Note("back to page " + Standard.Text.FromInteger(_tabs.SelectedIndex));
    }
}

int Main()
{
    Application.Initialize();
    var form = new BarsForm();
    form.Show();
    Application.Run();
    Console.Write(form.Seen);
    return 0;
}
