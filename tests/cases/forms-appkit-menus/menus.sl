// SPDX-License-Identifier: 0BSD
//
// Menus and the common dialogs on AppKit: a form's bar goes across the top of
// the screen behind the application menu, its items answer AppKit's choice and
// show the program's ticks, a popup returns once dismissed, and each dialog
// returns its answer when its panel closes.
module AppKitMenus;

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

class MenusForm : Form
{
    public String Seen;
    late MenuItem _tick;
    late MenuItem _exit;
    late PopupMenu _popup;
    Timer _clock;
    Timer _closer;
    int _ticks;
    int _closing;

    public MenusForm()
    {
        Seen = "";
        _ticks = 0;
        _closing = 0;
        _clock = new Timer(100);
        _closer = new Timer(150);
        base();
        Text = "AppKit menus";
        SetBounds(160, 160, 320, 200);

        var file = new MenuItem("&File");
        file.Add("&Open").Click += (sender) => this.Note("chose " + sender.Text);
        file.Add(MenuItem.CreateSeparator());
        _exit = file.Add("E&xit");
        var edit = new MenuItem("&Edit");
        _tick = edit.Add("&Ticked && done");
        var bar = new MainMenu();
        bar.Add(file);
        bar.Add(edit);
        Menu = bar;

        _popup = new PopupMenu();
        _popup.Add("Copy");

        _closer.Tick += this.OnCloser;
        _clock.Tick += this.OnTick;
        _clock.Start();
    }

    public void Note(String what) => Seen = Seen + what + "\n";

    void OnTick(Timer sender)
    {
        _ticks++;
        if (_ticks == 2)
        {
            _clock.Stop();
            CheckBar();
            CheckPopup();
            CheckDialogs();
            Close();
        }
    }

    /// The menu's captions from `first` on, a separator as `-`.
    static String DescribeTitles(NSMenu menu, int first)
    {
        String text = "";
        for (NSInteger i = (NSInteger)first; i < menu.NumberOfItems; i++)
        {
            var item = menu.ItemAtIndex(i)!;
            text = text + (text == "" ? "" : ", ") + (item.SeparatorItem ? "-" : FromNSString(item.Title));
        }
        return text;
    }

    void CheckBar()
    {
        var bar = NSApplication.SharedApplication.MainMenu!;
        Note("bar: " + DescribeTitles(bar, 1));
        var file = bar.ItemAtIndex((NSInteger)1)!.Submenu!;
        Note("File: " + DescribeTitles(file, 0));
        Note("application menu ends with " + FromNSString(bar.ItemAtIndex((NSInteger)0)!.Submenu!.ItemAtIndex((NSInteger)4)!.Title)
             .Substring(0u, 4u));

        file.PerformActionForItemAtIndex((NSInteger)0);

        _tick.Checked = true;
        _exit.Enabled = false;
        // AppKit adds its own items to a menu titled Edit, after the program's.
        var edit = bar.ItemAtIndex((NSInteger)2)!.Submenu!;
        Note("Edit: " + FromNSString(edit.ItemAtIndex((NSInteger)0)!.Title) + ", ticked " + (edit.ItemAtIndex((NSInteger)0)!.State == 1 ? "yes" : "no")
             + ", Exit enabled " + (file.ItemAtIndex((NSInteger)2)!.Enabled ? "yes" : "no"));
    }

    /// Closes whatever is modal now: Escape for a popup, which reads keys
    /// while it tracks, and each panel by its own means.
    void OnCloser(Timer sender)
    {
        _closer.Stop();
        var app = NSApplication.SharedApplication;
        switch (_closing)
        {
            case 1:
            {
                var escape = NSString.StringWithUTF8String("\u001b".ToPointer())!;
                NSPoint origin;
                origin.x = 0.0;
                origin.y = 0.0;
                var key = NSEvent.KeyEventWithTypeLocationModifierFlagsTimestampWindowNumberContextCharactersCharactersIgnoringModifiersIsARepeatKeyCode(
                    NSEventType.KeyDown, origin, (NSEventModifierFlags)0u, 0.0, 0, null, escape, escape, false, (ushort)53);
                app.PostEventAtStart(key!, true);
                break;
            }
            case 2:
            {
                var panel = NSColorPanel.SharedColorPanel;
                panel.Color = NSColor.ColorWithSRGBRedGreenBlueAlpha(1.0, 0.0, 0.0, 1.0);
                panel.Close();
                break;
            }
            default:
            {
                // `abortModal` ends the run by raising an exception, which
                // must not cross this timer's block; the panel's own Cancel
                // ends it as a click would.
                if (app.ModalWindow is NSSavePanel panel)
                    panel.Cancel(null);
                break;
            }
        }
    }

    void CheckPopup()
    {
        _closing = 1;
        _closer.Start();
        _popup.Show(this, CreatePoint(20, 20));
        Note("the popup returned");
    }

    void CheckDialogs()
    {
        _closing = 2;
        _closer.Start();
        var colors = new ColorDialog();
        var chosen = colors.ShowDialog(this);
        Note("colour: " + (chosen.Ok ? Standard.Text.FromInteger((int)chosen.Value.R) + " "
                                        + Standard.Text.FromInteger((int)chosen.Value.G) : "none"));

        _closing = 3;
        _closer.Start();
        var opener = new OpenDialog();
        var path = opener.ShowDialog(this);
        Note("open: " + (path.Ok ? path.Value : path.Error == DialogOutcome.Canceled ? "canceled" : "failed"));
    }
}

int Main()
{
    Application.Initialize();
    var form = new MenusForm();
    form.Show();
    Application.Run();
    Console.Write(form.Seen);
    return 0;
}
