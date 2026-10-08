// SPDX-License-Identifier: 0BSD
//
// What every control does, whatever it is: where it goes when its parent
// changes size, what it raises and how often, how long it lives, and how a
// window closes and blocks the others.
//
//   stainless run samples/forms/core.sl forms/src bindings/win32 \
//       -l user32 -l gdi32 -l comctl32
//
// The window is a docked header over a handful of anchored buttons. Minimise
// it and restore it, or squeeze it to nothing and let it go: everything comes
// back where it was.
//
// Pass `--selftest` and it drives the layer through the notification interface
// and the platform, checks what it can with nobody in front of it, and quits.
module Core;

import Standard.Console;
import Standard.Text;
import Standard.Collections;
import Forms;
import Forms.Drawing;
import Forms.Platform;
#if WINDOWS
import Win32.Handles;
import Win32.User32;
#elif MACOS && !FORMS_GTK
import Forms.Platform.AppKit;
import MacOS.AppKit;
import MacOS.CoreFoundation;
#elif UNIX
import Gtk.Api;
#endif

#if MACOS && !FORMS_GTK
/// Queues a key going down in `window`, behind whatever is queued already.
void PostKeyToWindow(NSWindow window, String typed, ushort code, NSEventModifierFlags flags)
{
    var text = ToNSString(typed);
    CGPoint origin;
    origin.x = 0.0;
    origin.y = 0.0;
    var down = NSEvent.KeyEventWithTypeLocationModifierFlagsTimestampWindowNumberContextCharactersCharactersIgnoringModifiersIsARepeatKeyCode(
        NSEventType.KeyDown, origin, flags, 0.0, window.WindowNumber, null, text, text, false, code);
    if (down != null)
        NSApplication.SharedApplication.PostEventAtStart((NSEvent)down, false);
}
#endif

/// What the keyboard checks counted.
public class KeyLog
{
    public int Saves;
    public int Refreshes;
    public int BoxKeys;
    public bool Idled;

    public KeyLog()
    {
        Saves = 0;
        Refreshes = 0;
        BoxKeys = 0;
        Idled = false;
    }
}

/// What the command checks counted.
public class CommandLog
{
    public int Runs;
    public bool Allowed;

    public CommandLog()
    {
        Runs = 0;
        Allowed = true;
    }
}

/// A graphic control that counts what reached it.
public class Spot : GraphicControl
{
    public int Presses;
    public int DoubleClicks;
    public int Wheels;
    public int Menus;
    public Drawing.Point LastPress;

    public Spot(WindowedControl parent)
    {
        base(parent);
        Presses = 0;
        DoubleClicks = 0;
        Wheels = 0;
        Menus = 0;
        LastPress = Drawing.Point.Empty;
    }

    protected override void OnMouseDown(MouseEventArgs args)
    {
        Presses++;
        LastPress = args.Location;
        base.OnMouseDown(args);
    }

    protected override void OnDoubleClick()
    {
        DoubleClicks++;
        base.OnDoubleClick();
    }

    protected override void OnMouseWheel(MouseEventArgs args)
    {
        Wheels++;
        base.OnMouseWheel(args);
    }

    protected override void OnContextMenu(ContextMenuEventArgs args)
    {
        Menus++;
        args.Handled = true;
        base.OnContextMenu(args);
    }

    protected override void OnPaint(PaintEventArgs args)
    {
        args.Graphics.FillRectangle(new Brush(ForeColor),
                                    Rectangle.FromBounds(0, 0, Width, Height));
        base.OnPaint(args);
    }
}

/// A panel that counts its paints and the colours pushed at it.
public class Host : Panel
{
    public int Paints;
    public int BackColors;

    public Host(WindowedControl parent)
    {
        base(parent);
        Paints = 0;
        BackColors = 0;
    }

    protected override void OnPaint(PaintEventArgs args)
    {
        Paints++;
        base.OnPaint(args);
    }

    protected override void ApplyBackColor()
    {
        BackColors++;
        base.ApplyBackColor();
    }
}

/// Something that watches an object without keeping it.
/// A form that subscribes to its own button, by method and by lambda: the
/// shape of every form, and a cycle unless the subscriptions are weak.
public class HandledForm : Form
{
    late Button _save;
    int _presses;

    public HandledForm()
    {
        base(WindowBorder.Sizable);
        _presses = 0;
        _save = new Button(this);
        _save.Click += this.OnSaveClick;
        _save.Click += (sender) => { this._presses++; };
    }

    void OnSaveClick(Control sender) => _presses++;
}

public class Watch
{
    public weak Control? Target;

    public Watch() => Target = null;

    public bool IsGone
    {
        get
        {
            Control? held = Target;
            return held == null;
        }
    }
}

public class CoreForm : Form
{
    late Panel _header;
    late Panel _below;
    late Button _corner;
    late Button _stretch;
    late Button _center;
    late Host _host;
    late Button _inner;
    late Spot _spot;
    late GroupBox _group;
    late Spot _framed;
    late Panel _probe;
    int _resizes;
    int _moves;

    public CoreForm()
    {
        base(WindowBorder.Sizable);
        Text = "Forms core";
        SetBounds(0, 0, 640, 480);

        _header = new Panel(this);
        _header.Border = ControlBorder.Single;
        _header.Height = 80;
        _header.Dock = DockStyle.Top;

        _below = new Panel(this);
        _below.Border = ControlBorder.Single;
        _below.Height = 30;
        _below.Dock = DockStyle.Top;

        _corner = new Button(this);
        _corner.Text = "Corner";
        _corner.SetBounds(300, 300, 80, 24);
        _corner.Anchors = AnchorStyles.Right | AnchorStyles.Bottom;

        _stretch = new Button(this);
        _stretch.Text = "Stretch";
        _stretch.SetBounds(20, 200, 300, 24);
        _stretch.Anchors = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top;

        _center = new Button(this);
        _center.Text = "Centre";
        _center.SetBounds(200, 150, 80, 24);
        _center.Anchors = AnchorStyles.None;

        _host = new Host(this);
        _host.SetBounds(20, 340, 120, 60);
        _spot = new Spot(_host);
        _spot.SetBounds(10, 10, 40, 20);
        _spot.ForeColor = Colors.Blue;
        _inner = new Button(_host);
        _inner.Text = "In";
        _inner.SetBounds(60, 10, 50, 24);

        _group = new GroupBox(this);
        _group.Text = "Group";
        _group.SetBounds(400, 120, 160, 100);
        _framed = new Spot(_group);
        _framed.SetBounds(10, 10, 40, 20);
        _framed.ForeColor = Colors.Red;

        _probe = new Panel(this);
        _probe.SetBounds(160, 340, 60, 40);
        _probe.Resize += this.OnProbeResized;
        _probe.Move += this.OnProbeMoved;
        _resizes = 0;
        _moves = 0;
    }

    void OnProbeResized(Control sender) => _resizes++;
    void OnProbeMoved(Control sender) => _moves++;

    public static bool Check(bool ok, String what, bool passed)
    {
        Console.WriteLine((passed ? "  ok   " : "  FAIL ") + what);
        return ok && passed;
    }

    static String Describe(Rectangle r)
    {
        return "(" + Standard.Text.FromInteger((long)r.X)
            + "," + Standard.Text.FromInteger((long)r.Y)
            + " " + Standard.Text.FromInteger((long)r.Width)
            + "x" + Standard.Text.FromInteger((long)r.Height) + ")";
    }

    static void Settle()
    {
        for (int i = 0; i < 10; i++)
            Application.DoEvents();
    }

    /// Everything anchored or docked, in one list, so two moments can be
    /// compared.
    Rectangle[] Snapshot()
    {
        var all = new Rectangle[5u];
        all[0u] = _header.Bounds;
        all[1u] = _below.Bounds;
        all[2u] = _corner.Bounds;
        all[3u] = _stretch.Bounds;
        all[4u] = _center.Bounds;
        return all;
    }

    static bool Same(Rectangle[] was, Rectangle[] now)
    {
        bool same = true;
        for (nuint i = 0u; i < was.Length; i++)
        {
            if (!was[i].Equals(now[i]))
            {
                Console.WriteLine("       " + Describe(was[i]) + " became " + Describe(now[i]));
                same = false;
            }
        }
        return same;
    }

    public bool SelfTest()
    {
        bool ok = true;
        var frame = Bounds;

        // ------------------------------------------------------------ layout

        var before = Snapshot();
        State = WindowState.Minimized;
        Settle();
        State = WindowState.Normal;
        Settle();
        ok = Check(ok, "minimising and restoring leaves every control where it was",
                   Same(before, Snapshot()));

        SetBounds(frame.X, frame.Y, 200, 60);
        Settle();
        SetBounds(frame.X, frame.Y, frame.Width, frame.Height);
        Settle();
        ok = Check(ok, "squeezing the form and growing it back does too",
                   Same(before, Snapshot()));

        int centered = _center.Left;
        for (int i = 1; i <= 10; i++)
            SetBounds(frame.X, frame.Y, frame.Width + i, frame.Height);
        ok = Check(ok, "a centred control follows a form grown a pixel at a time",
                   _center.Left == centered + 5);
        for (int i = 9; i >= 0; i--)
            SetBounds(frame.X, frame.Y, frame.Width + i, frame.Height);
        ok = Check(ok, "and comes back to where it was", _center.Left == centered);
        Settle();

        _header.Height = 120;
        ok = Check(ok, "a docked control's new size moves the docked one after it",
                   _below.Top == _header.Bottom);
        _header.Height = 80;
        ok = Check(ok, "and moves it back", _below.Top == _header.Bottom);

        _resizes = 0;
        _moves = 0;
        _probe.SetBounds(_probe.Left + 5, _probe.Top + 5, _probe.Width + 5, _probe.Height + 5);
        ok = Check(ok, "moving and sizing a control raises Resize once",
                   _resizes == 1);
        ok = Check(ok, "and Move once", _moves == 1);

        // ------------------------------------------------- graphic controls

        var onSpot = Drawing.Point.FromXY(_spot.Left + 5, _spot.Top + 5);
        _host.OnPlatformMouseDown(MouseButton.Left, onSpot, ModifierKeys.None);
        _host.OnPlatformMouseUp(MouseButton.Left, onSpot, ModifierKeys.None);
        _host.OnPlatformDoubleClick();
        ok = Check(ok, "a graphic control gets its double-click", _spot.DoubleClicks == 1);
        _host.OnPlatformMouseWheel(120, onSpot, ModifierKeys.None);
        ok = Check(ok, "and the wheel", _spot.Wheels == 1);
        _host.OnPlatformContextMenu(onSpot, false);
        ok = Check(ok, "and a context menu", _spot.Menus == 1);

        _host.Update();
        Settle();
        int painted = _host.Paints;
        _spot.Visible = false;
        _host.Update();
        Settle();
        ok = Check(ok, "hiding a graphic control repaints its parent", _host.Paints > painted);
        _spot.Visible = true;
        _host.Update();
        Settle();
        painted = _host.Paints;
        _spot.ForeColor = Colors.Green;
        _host.Update();
        Settle();
        ok = Check(ok, "and so does recolouring it", _host.Paints > painted);
        painted = _host.Paints;
        _spot.Text = "changed";
        _host.Update();
        Settle();
        ok = Check(ok, "and changing its text", _host.Paints > painted);

        int pushed = _host.BackColors;
        BackColor = Colors.LightGray;
        ok = Check(ok, "a form's colour reaches a child that inherits it",
                   _host.BackColors > pushed);

        var origin = _group.ClientOrigin;
        var framedAt = Drawing.Point.FromXY(origin.X + _framed.Left + 5,
                                            origin.Y + _framed.Top + 5);
        _group.OnPlatformMouseDown(MouseButton.Left, framedAt, ModifierKeys.None);
        _group.OnPlatformMouseUp(MouseButton.Left, framedAt, ModifierKeys.None);
        ok = Check(ok, "a click in a group box reaches the graphic control under it",
                   _framed.Presses == 1);
        ok = Check(ok, "at its own coordinates",
                   _framed.LastPress.X == 5 && _framed.LastPress.Y == 5);
        var groupCorner = PointToScreen(_group, Drawing.Point.Empty);
        var framedCorner = PointToScreen(_framed, Drawing.Point.Empty);
        ok = Check(ok, "and the screen agrees where it is",
                   framedCorner.X - groupCorner.X == origin.X + _framed.Left
                   && framedCorner.Y - groupCorner.Y == origin.Y + _framed.Top);

        _host.Enabled = false;
        ok = Check(ok, "a control inside a disabled one is disabled", !_spot.IsEnabled);
#if WINDOWS
        ok = Check(ok, "and the platform greys a windowed child with it",
                   IsWindowEnabled((HWND)(void*)_inner.Handle) == 0);
#endif
        _host.Enabled = true;
        ok = Check(ok, "and enables it again with its parent", _inner.IsEnabled);
#if WINDOWS
        ok = Check(ok, "on the platform too", IsWindowEnabled((HWND)(void*)_inner.Handle) != 0);
#endif

        // --------------------------------------------------------- lifetime

        ok = LifetimeChecks(ok);
        ok = WindowChecks(ok);
        ok = ModalChecks(ok);
        ok = KeyboardChecks(ok);
        ok = CommandChecks(ok);
        ok = ScrollBoxChecks(ok);
        ok = MaskChecks(ok);

        var squeezed = Rectangle.FromBounds(0, 0, 10, 10).DeflateBy(6);
        ok = Check(ok, "deflating past nothing gives an empty rectangle",
                   squeezed.Width == 0 && squeezed.Height == 0);
        return ok;
    }

    /// Shortcuts, a handled key, and the loop going idle.
    bool KeyboardChecks(bool ok)
    {
        var parsed = Shortcut.Parse("ctrl+shift+s");
        ok = Check(ok, "a shortcut is read from its text",
                   parsed.Some && parsed.Value.Equals(
                       Shortcut.FromKey(Key.S, ModifierKeys.Control | ModifierKeys.Shift)));
        var function = Shortcut.Parse("F5");
        ok = Check(ok, "and so is a function key", function.Some && function.Value.Key == Key.F5);
        ok = Check(ok, "text with no key, or an unknown modifier, is refused",
                   !Shortcut.Parse("Ctrl+").HasValue && !Shortcut.Parse("Hyper+S").HasValue);
#if !MACOS
        ok = Check(ok, "and it is written back as a menu shows it",
                   parsed.Some && parsed.Value.ToText() == "Ctrl+Shift+S");
#endif

        var log = new KeyLog();
        var keys = new Form(WindowBorder.Sizable);
        keys.Text = "Keys";
        keys.SetBounds(0, 0, 320, 160);
        var bar = new MainMenu();
        var file = bar.Add("&File");
        var save = file.Add("&Save");
        save.Shortcut = Shortcut.FromKey(Key.S, ModifierKeys.Control);
        save.Click += (sender) => { log.Saves++; };
        var refresh = file.Add("&Refresh");
        refresh.Shortcut = Shortcut.FromKey(Key.F5, ModifierKeys.None);
        refresh.Click += (sender) => { log.Refreshes++; };
        var view = bar.Add("&View");
        var zoom = view.Add("&Zoom");
        zoom.Shortcut = Shortcut.FromKey(Key.Z, ModifierKeys.Control);
        view.Enabled = false;
        keys.Menu = bar;

        var box = new TextBox(keys);
        box.SetBounds(10, 10, 200, 24);
        box.KeyDown += (sender, args) =>
        {
            log.BoxKeys++;
            if (args.Key == Key.Left)
                args.Handled = true;
        };
        box.KeyPress += (sender, args) =>
        {
            if (args.KeyChar == (char32)'x')
                args.Handled = true;
        };
        keys.Show();
        Settle();
        box.Focus();
        Settle();

        var notify = (IWindowNotify)keys;
        ok = Check(ok, "a menu item's shortcut reaches it through the form",
                   notify.OnPlatformShortcut(Key.S, ModifierKeys.Control) && log.Saves == 1);
        ok = Check(ok, "but not with other modifiers held",
                   !notify.OnPlatformShortcut(Key.S, ModifierKeys.Control | ModifierKeys.Shift)
                   && log.Saves == 1);
        save.Enabled = false;
        ok = Check(ok, "nor while the item is disabled",
                   !notify.OnPlatformShortcut(Key.S, ModifierKeys.Control) && log.Saves == 1);
        save.Enabled = true;
        ok = Check(ok, "nor under a disabled heading",
                   !notify.OnPlatformShortcut(Key.Z, ModifierKeys.Control));

#if WINDOWS
        HWND edit = (HWND)(void*)box.Handle;
        log.BoxKeys = 0;
        PostMessageW(edit, WmKeyDown, (ulong)VkF5, 0);
        Settle();
        ok = Check(ok, "a shortcut pressed in a text box goes to the menu", log.Refreshes == 1);
        ok = Check(ok, "and the text box never hears it", log.BoxKeys == 0);

        box.Text = "abc";
        box.SelectionStart = 3;
        SendMessageW(edit, WmChar, (ulong)'x', 0);
        SendMessageW(edit, WmChar, (ulong)'y', 0);
        ok = Check(ok, "a handled character is not typed", box.Text == "abcy");
        SendMessageW(edit, WmKeyDown, (ulong)VkLeft, 0);
        SendMessageW(edit, WmChar, (ulong)'z', 0);
        ok = Check(ok, "and a handled key does not move the caret", box.Text == "abcyz");
#elif MACOS && !FORMS_GTK
        // Through the application's own queue, so each key meets the monitor
        // and then the field editor exactly as a typed one would.
        var window = ((AppKitWindowPeer)keys.WindowPeer).Window;
        log.BoxKeys = 0;
        PostKeyToWindow(window, "s", (ushort)1, NSEventModifierFlags.Command);
        Settle();
        ok = Check(ok, "a shortcut pressed in a text box goes to the menu", log.Saves == 2);
        ok = Check(ok, "and the text box never hears it", log.BoxKeys == 0);

        box.Text = "abc";
        box.Focus();
        Settle();
        box.SelectionStart = 3;
        PostKeyToWindow(window, "x", (ushort)7, (NSEventModifierFlags)0u);
        PostKeyToWindow(window, "y", (ushort)16, (NSEventModifierFlags)0u);
        Settle();
        ok = Check(ok, "a handled character is not typed", box.Text == "abcy");
#else
        ok = Check(ok, "a handled character is reported as handled",
                   box.OnPlatformKeyPress((char32)'x'));
        ok = Check(ok, "and an unhandled one is not", !box.OnPlatformKeyPress((char32)'y'));
        ok = Check(ok, "a handled key is reported as handled",
                   box.OnPlatformKeyDown(Key.Left, ModifierKeys.None));
#endif

        // The dialog closes itself the first time its loop goes idle. The
        // timer is there so that a loop that never does fails rather than
        // hangs.
        var waiting = new Form(WindowBorder.Fixed);
        waiting.SetBounds(0, 0, 200, 100);
        waiting.Idle += (sender) =>
        {
            log.Idled = true;
            ((Form)sender).Close();
        };
        var giveUp = new Timer();
        giveUp.Interval = 3000;
        giveUp.Tick += (sender) => { waiting.Close(); };
        giveUp.Start();
        waiting.ShowModal();
        giveUp.Stop();
        ok = Check(ok, "a modal loop raises Idle once it has caught up", log.Idled);

        keys.Close();
        Settle();
        return ok;
    }

    /// One command behind a menu item, a button and a toolbar button.
    bool CommandChecks(bool ok)
    {
        var log = new CommandLog();
        var host = new Form(WindowBorder.Sizable);
        host.Text = "Commands";
        host.SetBounds(0, 0, 360, 200);
        var commands = new CommandList(host);
        var save = commands.Add("&Save");
        save.Shortcut = Shortcut.FromKey(Key.S, ModifierKeys.Control);
        save.Hint = "Write it to disk";
        save.Execute += (sender) => { log.Runs++; };
        save.Update += (sender) => { sender.Enabled = log.Allowed; };

        var bar = new MainMenu();
        var item = bar.Add("&File").Add(new MenuItem());
        item.Command = save;
        host.Menu = bar;
        var tools = new ToolBar(host);
        var tool = tools.Add(new ToolButton());
        tool.Command = save;
        var button = new Button(host);
        button.SetBounds(10, 40, 100, 28);
        button.Command = save;
        host.Show();
        Settle();

        ok = Check(ok, "a command's caption reaches every client",
                   item.Text == "&Save" && tool.Text == "Save" && button.Text == "&Save");
        ok = Check(ok, "and its shortcut the menu item", item.Shortcut.Equals(save.Shortcut));
        ok = Check(ok, "and its hint the button's tool tip", button.ToolTip == "Write it to disk");

        var notify = (IWindowNotify)host;
        ok = Check(ok, "its shortcut carries it out",
                   notify.OnPlatformShortcut(Key.S, ModifierKeys.Control) && log.Runs == 1);
        item.PerformClick();
        ok = Check(ok, "and so does its menu item", log.Runs == 2);
        ((IControlNotify)button).OnPlatformActivated();
        ok = Check(ok, "and its button", log.Runs == 3);
        tool.RaiseClick(tools);
        ok = Check(ok, "and its toolbar button", log.Runs == 4);

        log.Allowed = false;
        Application.RaiseIdle();
        ok = Check(ok, "going idle runs its Update",
                   !save.Enabled && !item.Enabled && !button.Enabled && !tool.Enabled);
        ok = Check(ok, "and a disabled command's shortcut does nothing",
                   !notify.OnPlatformShortcut(Key.S, ModifierKeys.Control) && log.Runs == 4);
        log.Allowed = true;
        Application.RaiseIdle();
        ok = Check(ok, "nor does it stay disabled", button.Enabled && item.Enabled);

        var left = commands.Add("Left");
        var right = commands.Add("Right");
        left.AutoCheck = true;
        right.AutoCheck = true;
        left.GroupIndex = 1;
        right.GroupIndex = 1;
        var leftItem = bar.Items[0u].Add(new MenuItem());
        leftItem.Command = left;
        left.PerformExecute();
        right.PerformExecute();
        ok = Check(ok, "commands in a group are checked one at a time",
                   right.Checked && !left.Checked && !leftItem.Checked);

        var watch = new Watch();
        MakeCommandedButton(host, save, watch);
        Settle();
        ok = Check(ok, "a command does not keep a removed button alive", watch.IsGone);
        save.Text = "Save &All";
        ok = Check(ok, "and goes on telling the clients it still has", button.Text == "Save &All");

        host.Close();
        Settle();
        return ok;
    }

    /// A box larger inside than out: what it measures, where it scrolls, and
    /// where the platform puts what is in it.
    bool ScrollBoxChecks(bool ok)
    {
        var log = new CommandLog();
        var host = new Form(WindowBorder.Sizable);
        host.Text = "Scroll box";
        host.SetBounds(0, 0, 320, 260);
        var box = new ScrollBox(host);
        box.SetBounds(10, 10, 200, 150);
        box.Scroll += (sender) => { log.Runs++; };
        var top = new Button(box);
        top.SetBounds(8, 8, 80, 24);
        var far = new Button(box);
        far.SetBounds(300, 600, 80, 24);
        var docked = new Panel(box);
        docked.Height = 20;
        docked.Dock = DockStyle.Top;
        host.Show();
        Settle();

        ok = Check(ok, "a scroll box is as large as its children reach",
                   box.ContentSize.Width == 380 && box.ContentSize.Height == 624);
        var view = box.ClientBounds.Extent;
        ok = Check(ok, "and its bars take room from what shows",
                   view.Width < 200 && view.Height < 150 && view.Width > 0);

        box.ScrollPosition = Drawing.Point.FromXY(0, 5000);
        // At least the end: GTK keeps a child at its own minimum height, so
        // the area can reach a little past what was asked for.
        int scrolledTo = box.ScrollPosition.Y;
        ok = Check(ok, "a position past the end shows the end",
                   scrolledTo >= 624 - view.Height && scrolledTo < 624 && box.ScrollPosition.X == 0);
        ok = Check(ok, "and scrolling from the program raises nothing", log.Runs == 0);

        box.ScrollPosition = Drawing.Point.Empty;
        box.ScrollIntoView(far);
        var at = box.ScrollPosition;
        ok = Check(ok, "ScrollIntoView shows the child whole",
                   at.X <= far.Left && at.Y <= far.Top
                   && far.Bounds.Right <= at.X + view.Width && far.Bounds.Bottom <= at.Y + view.Height);
        ok = Check(ok, "and no child moved", far.Left == 300 && far.Top == 600 && top.Top == 8);

        top.Top = 900;
        Settle();
        ok = Check(ok, "moving a child measures the area again", box.ContentSize.Height == 924);
        ok = Check(ok, "a docked child is laid out against what shows",
                   docked.Width == view.Width && docked.Top == 0);

#if WINDOWS
        // Where Windows put the far button, against where the form says.
        HWND button = (HWND)(void*)far.Handle;
        Win32.User32.Rect actual;
        GetWindowRect(button, &actual);
        var computed = host.PointToScreen(far, Drawing.Point.Empty);
        ok = Check(ok, "the platform puts a scrolled child where the form says",
                   actual.Left == computed.X && actual.Top == computed.Y);

        // The bar of the frame the content window sits in, pressed once.
        HWND frame = GetParent((HWND)(void*)box.Handle);
        box.ScrollPosition = Drawing.Point.Empty;
        SendMessageW(frame, WmVerticalScroll, (ulong)SbLineDown, 0);
        ok = Check(ok, "the user scrolling is reported",
                   log.Runs == 1 && box.ScrollPosition.Y > 0);
#endif

        host.Close();
        Settle();
        return ok;
    }

    /// One mask laid over one text, against what LCL's documentation says it
    /// shows and what `Text` then answers.
    bool CheckFit(bool ok, String mask, String text, String shown, String answer)
    {
        var pattern = MaskPattern.Parse(mask);
        String fitted = pattern.Fit(text);
        String stripped = pattern.Strip(fitted);
        bool right = fitted == shown && stripped == answer;
        if (!right)
            Console.WriteLine($"     {mask} with '{text}' showed '{fitted}' as '{stripped}'");
        return Check(ok, $"'{text}' in {mask} shows '{shown}'", right);
    }

    /// The mask language on its own, then a box typed into as the user would.
    bool MaskChecks(bool ok)
    {
        var phone = MaskPattern.Parse("(999) 000-0000;0;_");
        ok = Check(ok, "a mask is as long as its positions",
                   phone.Length == 14u && phone.IsLiteral(0u) && !phone.IsLiteral(1u));
        ok = Check(ok, "and reads its two trailing fields",
                   !phone.SavesLiterals && phone.Blank == (char32)'_');
        ok = Check(ok, "an empty one shows its literals", phone.BlankText == "(___) ___-____");

        ok = CheckFit(ok, "99", "1", "1_", "1 ");
        ok = CheckFit(ok, "!99", "1", "_1", " 1");
        ok = CheckFit(ok, "cc-cc", "1-2", "1_-2_", "1 -2 ");
        ok = CheckFit(ok, "!cc-cc", "1-2", "_1-_2", " 1- 2");
        ok = CheckFit(ok, "cc-cc@cc", "1-2@3", "1_-2_@3_", "1 -2 @3 ");
        ok = CheckFit(ok, "cc-cc@cc", "123-456@789", "12-45@78", "12-45@78");
        ok = CheckFit(ok, "!cc-cc@cc", "123-456@789", "23-56@89", "23-56@89");
        ok = CheckFit(ok, "(999) 000-0000;0;_", "5551234567", "(555) 123-4567", "5551234567");
        ok = CheckFit(ok, "(999) 000-0000;0;_", "(555) 123-4567", "(555) 123-4567", "5551234567");
        ok = CheckFit(ok, "00:00;1;*", "12", "12:**", "12:  ");

        var upper = MaskPattern.Parse(">LL<ll");
        ok = Check(ok, "> and < turn what is typed into their case",
                   upper.Accept(0u, (char32)'q') is Some big && big.Value == (char32)'Q'
                   && upper.Accept(2u, (char32)'Q') is Some small && small.Value == (char32)'q');
        var hex = MaskPattern.Parse("[a-c]\\[[!x]H");
        ok = Check(ok, "a set takes its members, a range included",
                   hex.Accept(0u, (char32)'b').HasValue && !hex.Accept(0u, (char32)'d').HasValue);
        ok = Check(ok, "a backslash makes the next character literal",
                   hex.IsLiteral(1u) && hex.GetSlot(1u).Literal == (char32)'[');
        ok = Check(ok, "a negated set takes everything else",
                   hex.Accept(2u, (char32)'y').HasValue && !hex.Accept(2u, (char32)'x').HasValue);
        ok = Check(ok, "a required position refuses a blank, an optional one takes it",
                   !hex.Accept(3u, (char32)' ').HasValue
                   && MaskPattern.Parse("9").Accept(0u, (char32)' ').HasValue);
        ok = Check(ok, "a mask is complete when every required position is filled",
                   phone.IsComplete("(___) 123-4567") && !phone.IsComplete("(555) 123-45_7"));

        var host = new Form(WindowBorder.Sizable);
        host.Text = "Masked";
        host.SetBounds(0, 0, 320, 160);
        var box = new MaskEdit(host);
        box.SetBounds(10, 10, 200, 24);
        var edits = new CommandLog();
        box.UserTextChanged += (sender) => { edits.Runs++; };
        box.EditMask = "(999) 000-0000;0;_";
        host.Show();
        Settle();
        box.Focus();
        Settle();

        ok = Check(ok, "a mask edit starts empty, showing its literals",
                   box.EditText == "(___) ___-____" && box.Text == "");

        var notify = (IControlNotify)box;
        box.SelectionStart = 0;
        box.SelectionLength = 0;
        foreach (var typed in ["5", "5", "x", "5", "1", "2"])
        {
            if (!notify.OnPlatformKeyPress(typed.GetCodePointAt(0u)))
                ok = Check(ok, $"typing '{typed}' is the mask's to place", false);
        }
        ok = Check(ok, "typing fills positions in turn, stepping over literals and refusing letters",
                   box.EditText == "(555) 12_-____");
        ok = Check(ok, "and leaves the caret after what it typed",
                   box.SelectionStart == 8 && box.SelectionLength == 0);
        ok = Check(ok, "each keystroke is the user's change", edits.Runs == 5);

        notify.OnPlatformKeyDown(Key.Backspace, ModifierKeys.None);
        ok = Check(ok, "backspace blanks the position before the caret",
                   box.EditText == "(555) 1__-____" && box.SelectionStart == 7);
        box.SelectionStart = 5;
        notify.OnPlatformKeyDown(Key.Backspace, ModifierKeys.None);
        ok = Check(ok, "stepping back over a literal",
                   box.EditText == "(55_) 1__-____" && box.SelectionStart == 3);

#if WINDOWS
        // The messages a keyboard sends, rather than the notifications they
        // become: Windows types a backspace as well as pressing it.
        HWND edit = (HWND)(void*)box.Handle;
        box.EditText = "";
        box.SelectionStart = 0;
        SendMessageW(edit, WmChar, (ulong)'4', 0);
        SendMessageW(edit, WmChar, (ulong)'2', 0);
        ok = Check(ok, "the platform's own keystrokes are placed the same way",
                   box.EditText == "(42_) ___-____");
        SendMessageW(edit, WmKeyDown, (ulong)VkBack, 0);
        SendMessageW(edit, WmChar, 8u, 0);
        ok = Check(ok, "and so is its backspace, once", box.EditText == "(4__) ___-____");
#endif

        box.Text = "5551234567";
        ok = Check(ok, "setting Text lays it into the mask",
                   box.EditText == "(555) 123-4567" && box.Text == "5551234567" && box.IsValid);
        box.EditText = "(12";
        ok = Check(ok, "setting EditText keeps the mask's shape",
                   box.EditText == "(12_) ___-____" && !box.IsValid);
        ok = Check(ok, "and ValidateEdit puts the caret on what is missing",
                   !box.ValidateEdit() && box.SelectionStart == 6);

        box.SelectionStart = 1;
        box.SelectionLength = 13;
        Clipboard.SetText("555-867-5309");
        box.PasteFromClipboard();
        Settle();
        ok = Check(ok, "a paste is typed in from where it went, literals and all",
                   box.EditText == "(555) 867-5309");

        var late = new MaskEdit(host);
        late.SetBounds(10, 50, 200, 24);
        late.Text = "5551234567";
        late.EditMask = "(999) 000-0000;0;_";
        ok = Check(ok, "text set before the mask is laid into it",
                   late.EditText == "(555) 123-4567");

        host.Close();
        Settle();
        return ok;
    }

    static void MakeCommandedButton(Form host, Command command, Watch watch)
    {
        var made = new Button(host);
        made.Command = command;
        watch.Target = (Control)made;
        host.RemoveControl(made);
    }

    bool LifetimeChecks(bool ok)
    {
        var watch = new Watch();
        var pageWatch = new Watch();
        var tabs = new TabControl(this);
        tabs.SetBounds(240, 380, 200, 80);
        var first = new TabPage(tabs, "One");
        var second = new TabPage(tabs, "Two");
        new Button(second);
        pageWatch.Target = (Control)second;
        tabs.RemovePage(second);
        bool gone = second.Parent == null;
        foreach (var child in tabs.Controls)
        {
            if (child == second)
                gone = false;
        }
        ok = Check(ok, "a removed tab page leaves its control", gone);
        second = first;
        Settle();
        ok = Check(ok, "and is freed when the program lets go of it", pageWatch.IsGone);

        var book = new Notebook(this);
        book.SetBounds(460, 380, 100, 60);
        var kept = new NotebookPage(book, "Kept");
        var dropped = new NotebookPage(book, "Dropped");
        pageWatch.Target = (Control)dropped;
        book.RemovePage(dropped);
        dropped = kept;
        Settle();
        ok = Check(ok, "so is a removed notebook page", pageWatch.IsGone);

        ShowAndClose(watch);
        Settle();
        ok = Check(ok, "a closed form with controls on it is freed", watch.IsGone);

        var handledWatch = new Watch();
        ShowAndCloseHandled(handledWatch);
        Settle();
        ok = Check(ok, "and so is one subscribed to its own button", handledWatch.IsGone);
        return ok;
    }

    static void ShowAndCloseHandled(Watch watch)
    {
        var passing = new HandledForm();
        watch.Target = (Control)passing;
        passing.Show();
        Settle();
        passing.Close();
    }

    /// A form this method alone ever holds, so nothing but the library can
    /// keep it alive once it has closed.
    static void ShowAndClose(Watch watch)
    {
        var passing = new Form();
        new Button(passing);
        new Label(passing);
        watch.Target = (Control)passing;
        passing.Show();
        Settle();
        passing.Close();
    }

    int _shown;
    int _asked;
    int _closed;
    bool _refuseSecond;

    void OnSpareShown(Control sender) => _shown++;
    void OnSpareClosed(Control sender) => _closed++;

    void OnSpareClosing(Control sender, CancelEventArgs args)
    {
        _asked++;
        if (_refuseSecond && _asked == 2)
            args.Cancel = true;
    }

    bool WindowChecks(bool ok)
    {
        var spare = new Form();
        ok = Check(ok, "a form is hidden until it is shown", !spare.Visible);
#if WINDOWS
        ok = Check(ok, "and so is its window", IsWindowVisible((HWND)(void*)spare.Handle) == 0);
#elif MACOS && !FORMS_GTK
        ok = Check(ok, "and so is its window", !((AppKitWindowPeer)spare.WindowPeer).Window.Visible);
#elif UNIX
        ok = Check(ok, "and so is its window",
                   gtk_widget_get_visible((GtkWidget*)(void*)spare.Handle) == 0);
#endif

        _shown = 0;
        _asked = 0;
        _closed = 0;
        _refuseSecond = true;
        spare.Shown += this.OnSpareShown;
        spare.Closing += this.OnSpareClosing;
        spare.Closed += this.OnSpareClosed;
        spare.Show();
        Settle();
        spare.Show();
        ok = Check(ok, "Shown is raised once", _shown == 1);

        spare.Close();
        Settle();
        ok = Check(ok, "Close asks once", _asked == 1);
        ok = Check(ok, "and closes when nobody refuses", _closed == 1);
        ok = Check(ok, "and a closed form reads as hidden", !spare.Visible);

        spare.Shown -= this.OnSpareShown;
        spare.Closing -= this.OnSpareClosing;
        spare.Closed -= this.OnSpareClosed;
        return ok;
    }

    Form? _dialog;
    bool _mainBlocked;
    bool _dialogModal;

    void CloseDialog()
    {
        var dialog = _dialog;
        if (dialog == null)
            return;
        var shown = (Form)dialog;
        _dialogModal = shown.IsModal;
#if WINDOWS
        _mainBlocked = IsWindowEnabled((HWND)(void*)Handle) == 0;
#elif MACOS && !FORMS_GTK
        var modal = NSApplication.SharedApplication.ModalWindow;
        _mainBlocked = modal != null && (NSWindow)modal == ((AppKitWindowPeer)shown.WindowPeer).Window;
#elif UNIX
        _mainBlocked = gtk_window_get_modal((GtkWidget*)(void*)shown.Handle) != 0
            && (nuint)(void*)gtk_window_get_transient_for((GtkWidget*)(void*)shown.Handle)
               == Handle;
#endif
        shown.Close();
    }

    bool ModalChecks(bool ok)
    {
        var dialog = new Form(WindowBorder.Fixed);
        dialog.SetBounds(0, 0, 240, 120);
        _dialog = dialog;
        _mainBlocked = false;
        _dialogModal = false;
        Application.Post(() => { CloseDialog(); });
        dialog.ShowModal();
        _dialog = null;

        ok = Check(ok, "a modal dialog knows it is one", _dialogModal);
        ok = Check(ok, "and blocks the window it was opened over", _mainBlocked);
#if WINDOWS
        ok = Check(ok, "which takes input again when it closes",
                   IsWindowEnabled((HWND)(void*)Handle) != 0);
#endif
        ok = Check(ok, "and the program goes on", Application.DoEvents());
#if WINDOWS
        ok = EscapeChecks(ok);
#endif
        return ok;
    }

#if WINDOWS
    ComboBox? _choice;
    bool _survivedEscape;

    /// Drops the list, and presses Escape at it through the modal loop.
    void DropAndEscape()
    {
        var choice = _choice;
        if (choice == null)
            return;
        HWND combo = (HWND)(void*)((ComboBox)choice).Handle;
        SendMessageW(combo, CbShowDropDown, 1u, 0);
        PostMessageW(combo, WmKeyDown, (ulong)VkEscape, 0);
        Application.Post(() => { AfterEscape(); });
    }

    void AfterEscape()
    {
        var dialog = _dialog;
        if (dialog == null)
            return;
        _survivedEscape = !((Form)dialog).IsClosed;
        ((Form)dialog).Close();
    }

    bool EscapeChecks(bool ok)
    {
        var dialog = new Form(WindowBorder.Fixed);
        dialog.SetBounds(0, 0, 240, 120);
        var choice = new ComboBox(dialog);
        choice.SetBounds(12, 12, 200, 24);
        choice.Add("one");
        choice.Add("two");
        _choice = choice;
        _dialog = dialog;
        _survivedEscape = false;
        Application.Post(() => { DropAndEscape(); });
        dialog.ShowModal();
        _dialog = null;
        _choice = null;
        ok = Check(ok, "Escape closes a combo box's list rather than the dialog",
                   _survivedEscape);
        return ok;
    }
#endif

    /// Last, because it asks the program to quit.
    public bool QuitChecks(bool ok)
    {
        var dialog = new Form(WindowBorder.Fixed);
        dialog.SetBounds(0, 0, 240, 120);
        Application.Post(() => { Application.Exit(); });
        dialog.ShowModal();
        ok = Check(ok, "a quit asked for inside a modal dialog ends the program",
                   !Application.DoEvents());
        ok = Check(ok, "and stays asked for", !Application.DoEvents());
        return ok;
    }
}

/// The login pattern: a dialog shown before any other window, which MUST NOT
/// end the program when it closes.
public class Login : Form
{
    public bool MainFormWasNone;

    public Login()
    {
        base(WindowBorder.Fixed);
        Text = "Sign in";
        SetBounds(0, 0, 260, 120);
        MainFormWasNone = false;
    }

    public void Answer()
    {
        MainFormWasNone = Application.MainForm == null;
        Close();
    }
}

int Main()
{
    Application.Initialize();

    bool testing = false;
    var arguments = Standard.Env.GetArguments();
    for (nuint i = 0u; i < arguments.Length; i++)
    {
        if (arguments[i] == "--selftest")
            testing = true;
    }

    if (!testing)
    {
        var shown = new CoreForm();
        shown.CenterOnScreen();
        shown.Show();
        Application.Run();
        return 0;
    }

    Console.WriteLine("Forms core -- self test");
    bool ok = true;

    var login = new Login();
    Application.Post(() => { login.Answer(); });
    login.ShowModal();
    ok = CoreForm.Check(ok, "a modal dialog is never the main form", login.MainFormWasNone);
    ok = CoreForm.Check(ok, "closing a dialog shown before any window does not quit",
                        Application.DoEvents());

    var form = new CoreForm();
    form.Show();
    for (int i = 0; i < 20; i++)
        Application.DoEvents();
    for (int i = 0; i < 200 && !form.HasBeenActivated; i++)
    {
        Standard.Threading.Sleep(10u);
        Application.DoEvents();
    }
    ok = form.SelfTest() && ok;
    ok = form.QuitChecks(ok);
    Console.WriteLine(ok ? "all checks passed" : "checks FAILED");
    return ok ? 0 : 1;
}
