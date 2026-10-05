// SPDX-License-Identifier: 0BSD
//
// The standard controls on AppKit, each a native control: what the program
// sets reads back, and AppKit's own events -- a click, typing, Return --
// reach the control they would reach on screen, as the user's doing.
module AppKitControls;

import Standard.Console;
import Standard.Text;
import Standard.ObjC;
import Forms;
import Forms.Drawing;
import Forms.Platform;
import Forms.Platform.AppKit;
import MacOS.Foundation;
import MacOS.AppKit;

class ControlsForm : Form
{
    public String Seen;
    Button _ok;
    CheckBox _check;
    TextBox _name;
    Label _label;
    GroupBox _group;
    Label _inside;
    TrackBar _track;
    SpinEdit _spin;
    ProgressBar _progress;
    ScrollBar _scroll;
    Timer _clock;
    int _ticks;

    public ControlsForm()
    {
        base();
        Text = "AppKit controls";
        SetBounds(160, 160, 480, 320);
        Seen = "";
        _ticks = 0;

        _ok = new Button(this);
        _ok.Text = "OK";
        _ok.SetBounds(16, 16, 96, 24);
        _ok.Click += (sender) => this.Note("clicked " + sender.Text);

        _check = new CheckBox(this);
        _check.Text = "Remember";
        _check.SetBounds(128, 16, 120, 24);
        _check.CheckedChanged += (sender) => this.Note("checked " + (this.IsChecked ? "on" : "off"));

        _name = new TextBox(this);
        _name.SetBounds(16, 56, 200, 24);
        _name.UserTextChanged += (sender) => this.Note("typed '" + sender.Text + "'");
        _name.KeyDown += (sender, args) => this.NoteKey(args.Key);

        _label = new Label(this);
        _label.Text = "A label";
        _label.SetBounds(232, 60, 120, 20);

        _group = new GroupBox(this);
        _group.Text = "Group";
        _group.SetBounds(16, 96, 200, 80);
        _inside = new Label(_group);
        _inside.Text = "inside";
        _inside.SetBounds(8, 8, 80, 20);

        _track = new TrackBar(this);
        _track.SetBounds(232, 96, 200, 32);
        _track.Minimum = 0;
        _track.Maximum = 20;
        _track.Value = 7;

        _spin = new SpinEdit(this);
        _spin.SetBounds(232, 140, 96, 24);
        _spin.Minimum = 1;
        _spin.Maximum = 9;
        _spin.Value = 12;

        _progress = new ProgressBar(this);
        _progress.SetBounds(16, 192, 200, 20);
        _progress.Value = 40;

        _scroll = new ScrollBar(this, false);
        _scroll.SetBounds(232, 192, 200, 16);
        _scroll.Minimum = 0;
        _scroll.Maximum = 99;
        _scroll.PageSize = 10;
        _scroll.Value = 95;

        _clock = new Timer(100);
        _clock.Tick += this.OnTick;
        _clock.Start();
    }

    public bool IsChecked => _check.Checked;

    public void Note(String what) => Seen = Seen + what + "\n";

    public void NoteKey(Key key)
    {
        if (key == Key.Enter)
            Note("key Enter");
    }

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

    /// A point in the form's client area as AppKit's window measures it: up
    /// from the bottom of the content.
    NSPoint ToWindow(int x, int y)
    {
        NSPoint at;
        at.x = (double)x;
        at.y = 320.0 - (double)y;
        return at;
    }

    void Click(int x, int y)
    {
        var window = FindWindow();
        var at = ToWindow(x, y);
        var down = NSEvent.MouseEventWithTypeLocationModifierFlagsTimestampWindowNumberContextEventNumberClickCountPressure(
            NSEventType.LeftMouseDown, at, (NSEventModifierFlags)0u, 0.0, window.WindowNumber, null, 0, 1, 1.0f);
        var up = NSEvent.MouseEventWithTypeLocationModifierFlagsTimestampWindowNumberContextEventNumberClickCountPressure(
            NSEventType.LeftMouseUp, at, (NSEventModifierFlags)0u, 0.0, window.WindowNumber, null, 0, 1, 1.0f);
        // A button tracks the press in a loop of its own until the release,
        // so the release is queued first for that loop to find.
        NSApplication.SharedApplication.PostEventAtStart(up!, true);
        window.SendEvent(down!);
    }

    void Type(String characters, ushort code)
    {
        var window = FindWindow();
        var typed = NSString.StringWithUTF8String(characters.ToPointer())!;
        var key = NSEvent.KeyEventWithTypeLocationModifierFlagsTimestampWindowNumberContextCharactersCharactersIgnoringModifiersIsARepeatKeyCode(
            NSEventType.KeyDown, ToWindow(0, 0), (NSEventModifierFlags)0u, 0.0, window.WindowNumber, null,
            typed, typed, false, code);
        window.SendEvent(key!);
    }

    void SendInput()
    {
        Click(64, 28);
        Click(140, 28);
        Click(100, 68);
        Type("h", (ushort)4);
        Type("i", (ushort)34);
        Type("\r", (ushort)36);
    }

    void ReadBack()
    {
        Note("text '" + _name.Text + "', label '" + _label.Text + "'");
        Note("inside the group: " + (_inside.Bounds.X == 8 && _inside.Bounds.Y == 8 ? "yes" : "no")
             + ", room " + (_group.ClientBounds.Height < 80 ? "under the caption" : "none"));
        Note("track " + Standard.Text.FromInteger(_track.Value) + ", spin " + Standard.Text.FromInteger(_spin.Value)
             + ", progress " + Standard.Text.FromInteger(_progress.Value)
             + ", scroll " + Standard.Text.FromInteger(_scroll.Value));
    }
}

int Main()
{
    Application.Initialize();
    var form = new ControlsForm();
    form.Show();
    Application.Run();
    Console.Write(form.Seen);
    return 0;
}
