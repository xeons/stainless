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
#endif
#if UNIX
import Gtk.Api;
#endif

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
        args.Graphics.FillRectangle(new Brush(ForeColor), Rectangle.FromBounds(0, 0, Width, Height));
        base.OnPaint(args);
    }
}

/// A panel that counts its paints and the colours pushed at it.
public class Host : Panel
{
    public int Paints;
    public int BackColours;

    public Host(WindowedControl parent)
    {
        base(parent);
        Paints = 0;
        BackColours = 0;
    }

    protected override void OnPaint(PaintEventArgs args)
    {
        Paints++;
        base.OnPaint(args);
    }

    protected override void ApplyBackColor()
    {
        BackColours++;
        base.ApplyBackColor();
    }
}

/// Something that watches an object without keeping it.
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
    Panel _header;
    Panel _below;
    Button _corner;
    Button _stretch;
    Button _centre;
    Host _host;
    Button _inner;
    Spot _spot;
    GroupBox _group;
    Spot _framed;
    Panel _probe;
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

        _centre = new Button(this);
        _centre.Text = "Centre";
        _centre.SetBounds(200, 150, 80, 24);
        _centre.Anchors = AnchorStyles.None;

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
        all[4u] = _centre.Bounds;
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

        int centred = _centre.Left;
        for (int i = 1; i <= 10; i++)
            SetBounds(frame.X, frame.Y, frame.Width + i, frame.Height);
        ok = Check(ok, "a centred control follows a form grown a pixel at a time",
                   _centre.Left == centred + 5);
        for (int i = 9; i >= 0; i--)
            SetBounds(frame.X, frame.Y, frame.Width + i, frame.Height);
        ok = Check(ok, "and comes back to where it was", _centre.Left == centred);
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

        int pushed = _host.BackColours;
        BackColor = Colors.LightGray;
        ok = Check(ok, "a form's colour reaches a child that inherits it",
                   _host.BackColours > pushed);

        var origin = _group.ClientOrigin;
        var framedAt = Drawing.Point.FromXY(origin.X + _framed.Left + 5, origin.Y + _framed.Top + 5);
        _group.OnPlatformMouseDown(MouseButton.Left, framedAt, ModifierKeys.None);
        _group.OnPlatformMouseUp(MouseButton.Left, framedAt, ModifierKeys.None);
        ok = Check(ok, "a click in a group box reaches the graphic control under it",
                   _framed.Presses == 1);
        ok = Check(ok, "at its own coordinates",
                   _framed.LastPress.X == 5 && _framed.LastPress.Y == 5);
        var groupCorner = ToScreen(_group, Drawing.Point.Empty);
        var framedCorner = ToScreen(_framed, Drawing.Point.Empty);
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

        var squeezed = Rectangle.FromBounds(0, 0, 10, 10).Deflate(6);
        ok = Check(ok, "deflating past nothing gives an empty rectangle",
                   squeezed.Width == 0 && squeezed.Height == 0);
        return ok;
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
        return ok;
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
#endif
#if UNIX
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
#endif
#if UNIX
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
        Application.Post(() => { Application.Quit(); });
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
    ok = form.SelfTest() && ok;
    ok = form.QuitChecks(ok);
    Console.WriteLine(ok ? "all checks passed" : "checks FAILED");
    return ok ? 0 : 1;
}
