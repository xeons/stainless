// SPDX-License-Identifier: 0BSD
//
// Forms on AppKit: a press and a typed key, sent to the window as AppKit's own
// events, reach a drawn control in its own coordinates. The press gives it
// the keyboard, as a click on a focusable control does, and the window need
// not be in front for either.
module AppKitInput;

import Standard.Console;
import Standard.ObjC;
import Forms;
import Forms.Drawing;
import Forms.Platform;
import Forms.Platform.AppKit;
import MacOS.Foundation;
import MacOS.AppKit;

class InputForm : Form
{
    public String Seen;
    late CustomControl _canvas;
    Timer _clock;
    int _ticks;

    public InputForm()
    {
        Seen = "";
        _clock = new Timer(100);
        base();
        Text = "AppKit input";
        SetBounds(140, 140, 420, 260);
        _ticks = 0;

        _canvas = new CustomControl(this);
        _canvas.SetBounds(16, 56, 388, 180);
        _canvas.MouseDown += (sender, args) =>
            this.Note("down " + Standard.Text.FromInteger(args.X) + "," + Standard.Text.FromInteger(args.Y));
        _canvas.KeyPress += (sender, args) => this.Note("typed " + Standard.Text.FromChar(args.KeyChar));
        _canvas.GotFocus += (sender) => this.Note("focus");

        _clock.Tick += this.OnTick;
        _clock.Start();
    }

    public void Note(String what) => Seen = Seen + what + "; ";

    void OnTick(Timer sender)
    {
        _ticks++;
        if (_ticks == 2)
            SendInput();
        if (_ticks == 3)
            Close();
    }

    /// A press 10 across and 20 down the canvas, and the key 'q'. AppKit's
    /// window coordinates run up from the bottom of the content.
    void SendInput()
    {
        var window = ((AppKitWindowPeer)WindowPeer).Window;
        NSPoint at;
        at.x = 16.0 + 10.0;
        at.y = 260.0 - (56.0 + 20.0);
        var number = window.WindowNumber;
        var down = NSEvent.MouseEventWithTypeLocationModifierFlagsTimestampWindowNumberContextEventNumberClickCountPressure(
            NSEventType.LeftMouseDown, at, (NSEventModifierFlags)0u, 0.0, number, null, 0, 1, 1.0f);
        var up = NSEvent.MouseEventWithTypeLocationModifierFlagsTimestampWindowNumberContextEventNumberClickCountPressure(
            NSEventType.LeftMouseUp, at, (NSEventModifierFlags)0u, 0.0, number, null, 0, 1, 1.0f);
        window.SendEvent(down!);
        window.SendEvent(up!);

        var q = NSString.StringWithUTF8String("q".ToPointer())!;
        var key = NSEvent.KeyEventWithTypeLocationModifierFlagsTimestampWindowNumberContextCharactersCharactersIgnoringModifiersIsARepeatKeyCode(
            NSEventType.KeyDown, at, (NSEventModifierFlags)0u, 0.0, number, null, q, q, false, (ushort)12);
        window.SendEvent(key!);
    }
}

int Main()
{
    Application.Initialize();
    var form = new InputForm();
    form.Show();
    Application.Run();
    Console.WriteLine(form.Seen);
    return 0;
}
