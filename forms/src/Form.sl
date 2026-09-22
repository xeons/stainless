// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// A top-level window, and the program that runs them.
//
// This is the LCL's `forms.pp` reduced to the two things it is really about --
// `TCustomForm` and `TApplication` -- with `TScreen` folded into `Screen` and
// the rest (frames, docking forms, hint windows, the designer hooks, monitor
// enumeration, window magnetism) left out.
//
// **A form is a `WindowedControl` with no parent.** Everything about position,
// size, docking, fonts and events it inherits; what it adds is a title, a
// border style, a window state, the close protocol and the ability to be run
// modally. That is the same shape `TCustomForm` has and a much shorter list,
// because the LCL's form carries the application's keyboard handling, its
// action list and its scroll bars as well.
module Forms;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;

// ===================================================================== form

/// Why a form closed, for a handler that cares which.
public enum CloseReason { User, Program, ApplicationExit }

/// A top-level window.
///
/// ```
/// public class MainForm : Form {
///     Button save;
///
///     public MainForm() {
///         base(WindowBorder.Sizable);
///         Text = "Notes";
///         SetBounds(0, 0, 480, 320);
///
///         save = new Button(this);
///         save.Text = "Save";
///         save.SetBounds(380, 280, 80, 26);
///         save.Anchors = AnchorStyles.Bottom | AnchorStyles.Right;
///         save.Click += this.OnSave;
///     }
///
///     void OnSave(Control sender) { /* ... */ }
/// }
/// ```
///
/// **A form is kept alive by the `Application`, not by the program.** Showing
/// one registers it; closing one unregisters it. That is what stops a form
/// built in a local and shown being destroyed the moment the function returns,
/// which under ARC it otherwise would be -- the platform holds a window, but
/// nothing here would hold the object that answers for it.
///
/// **A form is hidden until `Show` or `ShowModal`**, so everything its
/// constructor sets up is in place before anyone sees it.
///
/// **A closed form stays closed.** Its window is gone, and showing it again
/// is a mistake that stops the program; make a new one instead.
public class Form : WindowedControl, IWindowNotify
{
    IWindowPeer _window;
    MainMenu? _bar;
    WindowBorder _framing;
    /// Set while `Closing` is being raised, so a handler calling `Close` does
    /// not ask the question a second time inside the first.
    bool _asking;
    bool _closed;
    bool _registered;
    bool _modal;
    bool _everShown;
    /// When this form last became active, in `Application`'s count; zero for
    /// never.
    int _activation;

    /// Builds a form with the given frame.
    ///
    /// The window is made here rather than lazily, so every property set
    /// afterwards goes straight through and nothing needs replaying. A form
    /// that must choose its border at run time chooses it here, since changing
    /// it later costs the window on Windows.
    public Form(WindowBorder border)
    {
        base(null);
        _framing = border;
        _bar = null;
        _asking = false;
        _closed = false;
        _registered = false;
        _modal = false;
        _everShown = false;
        _activation = 0;
        Visible = false;
        _window = WidgetSet.Current.CreateWindow(this, border);
        AttachContainerPeer(_window);
        SetBounds(0, 0, 640, 480);
    }

    /// The ordinary resizable window.
    public Form() => this(WindowBorder.Sizable);

    /// The window's title. The same storage as `Text`, because on every
    /// platform a window's caption *is* its text, and the LCL keeping
    /// `Caption` and `Text` as separate published properties on `TCustomForm`
    /// only ever meant keeping the two in step.
    public String Title
    {
        get => Text;
        set => Text = value;
    }

    /// Gives the window the icon with this id in the program's resources, and
    /// answers whether there was one.
    ///
    /// A method rather than a property because it can fail, and a property that
    /// silently does nothing is the worst of both: an icon that did not appear
    /// is exactly the kind of mistake that survives to a release, since the
    /// window looks fine with the default one.
    ///
    /// **Windows only**, and false everywhere else. An icon in the binary is a
    /// resource, and only a PE has those; a GTK program takes its icon from the
    /// desktop's icon theme, keyed by the name in its `.desktop` file.
    public bool UseIconResource(int id) => _window.SetIconResource(id);

    /// How the window is framed. Read-only after construction; see the note on
    /// the constructor.
    public WindowBorder Border => _framing;

    /// Normal, minimised or maximised. Read from the platform, because the user
    /// changes it without asking.
    public WindowState State
    {
        get => _window.GetState();
        set => _window.SetState(value);
    }

    /// A minimised window's size and position are its icon's, and a form that
    /// took them would lay itself out for nothing and forget where it was.
    protected override bool IsMinimizedWindow => !_closed && State == WindowState.Minimized;

    /// Whether `ShowModal` is showing this form and has not yet returned.
    public bool IsModal => _modal;

    /// Whether the window has closed. A closed form cannot be shown again.
    public bool IsClosed => _closed;

    int Activation => _activation;
    void MarkActivated(int count) => _activation = count;

    /// Centres the window on the work area of the screen it is on.
    public void CenterOnScreen() => _window.CenterOnScreen();

    /// The bar across the top of the window, or null for none.
    ///
    /// Assigning one builds it: every item in the tree becomes a platform menu
    /// item at this moment and not before, which is what lets the tree be
    /// assembled in any order. Assigning a second one replaces the first.
    public MainMenu? Menu
    {
        get => _bar;
        set
        {
            _bar = value;
            if (value == null)
            {
                _window.SetMenu(null);
            }
            else
            {
                _window.SetMenu(((MainMenu)value).Build(this));
            }
            PerformLayout();
        }
    }

    /// This form's window, for the things that need one -- a popup menu, and a
    /// modal dialog's owner.
    public IWindowPeer WindowPeer() => _window;

    /// A point in a control's own coordinates, in the screen's.
    ///
    /// What a popup menu needs, since every platform places one in screen
    /// coordinates and every handler has the point in the control's.
    public Point ToScreen(Control from, Point at)
    {
        int x = at.X;
        int y = at.Y;
        Control? walk = from;
        while (walk != null)
        {
            var here = (Control)walk;
            if (here is Form)
                break;
            x = x + here.Left;
            y = y + here.Top;
            walk = here.Parent;
            // A parent's children start at its client origin, which is not its
            // corner under a group box.
            if (walk != null)
            {
                var origin = ((WindowedControl)walk).ClientOrigin;
                x = x + origin.X;
                y = y + origin.Y;
            }
        }
        var frame = Bounds;
        var client = ClientBounds;
        // The client area starts inside the frame, and the difference is what
        // the border and caption cost -- which only the two rectangles know.
        return Point.At(frame.X + (frame.Width - client.Width) / 2 + x,
                        frame.Y + (frame.Height - client.Height) - 
                        (frame.Width - client.Width) / 2 + y);
    }

    /// Shows the window and registers it with the `Application`.
    public override void Show()
    {
        RequireOpen();
        if (!_registered)
        {
            Application.Register(this);
            _registered = true;
        }
        Visible = true;
        _window.Activate();
        RaiseShownOnce();
    }

    /// Shows it and does not return until it is closed.
    ///
    /// **Every other window of the program refuses input meanwhile**, which is
    /// what modal means. The dialog is owned by the window the user was in --
    /// the active form, or else the main one -- so it stays in front of it.
    ///
    /// **Closing a modal form never ends the program**, even when it is the
    /// only one open: a login dialog shown before the main window needs that.
    ///
    /// **Answers nothing.** C#'s `ShowDialog` returns a `DialogResult`, which
    /// works because every C# dialog sets one; here a form that has an answer
    /// carries it as a property of its own, typed as whatever the answer
    /// actually is, and the caller reads that after this returns. A dialog
    /// whose answer is genuinely one of ok/cancel gives itself a
    /// `DialogResult` property and loses nothing.
    public void ShowModal()
    {
        RequireOpen();
        var owner = Application.OwnerFor(this);
        _modal = true;
        if (!_registered)
        {
            Application.Register(this);
            _registered = true;
        }
        Visible = true;
        RaiseShownOnce();

        if (owner == null)
        {
            _window.ShowModal(null);
        }
        else
        {
            _window.ShowModal(((Form)owner).WindowPeer());
        }
        _modal = false;
    }

    /// Asks the window to close, exactly as though the user had clicked the
    /// close box: `Closing` is raised once, and a handler may refuse.
    public void Close()
    {
        if (_closed || _asking)
            return;
        _window.Close();
    }

    void RequireOpen()
    {
        if (_closed)
        {
            sl_fail("this form has closed and cannot be shown again; make a new one".ToPointer());
        }
    }

    void RaiseShownOnce()
    {
        if (_everShown)
            return;
        _everShown = true;
        OnShown();
    }

    // ------------------------------------------------------------- events

    /// The window is about to close and a handler may stop it.
    public event CancelEventHandler Closing;
    /// It has closed and cannot be stopped.
    public event EventHandler Closed;
    /// It became the active window.
    public event EventHandler Activated;
    /// It stopped being the active window.
    public event EventHandler Deactivated;
    /// Raised once, the first time the window is shown. Where a form does work
    /// that needs its final size.
    public event EventHandler Shown;

    protected virtual void OnClosing(CancelEventArgs args) => Closing(this, args);
    protected virtual void OnClosed() => Closed(this);
    protected virtual void OnActivated() => Activated(this);
    protected virtual void OnDeactivated() => Deactivated(this);
    protected virtual void OnShown() => Shown(this);

    // --------------------------------------------- what the platform says

    /// The user asked to close the window. True lets it go.
    ///
    /// The one notification that is a question rather than a report, which is
    /// why `IWindowNotify` exists at all and why it is the only method on it
    /// that returns anything.
    public bool OnPlatformClosing()
    {
        if (_closed)
            return true;
        var asked = new CancelEventArgs();
        _asking = true;
        OnClosing(asked);
        _asking = false;
        return !asked.Cancel;
    }

    public void OnPlatformClosed()
    {
        if (_closed)
            return;
        _closed = true;
        ForgetShown();
        OnClosed();
        if (_registered)
        {
            _registered = false;
            Application.Unregister(this, _modal);
        }
    }

    public void OnPlatformActivatedWindow()
    {
        Application.NoteActivated(this);
        OnActivated();
    }
    public void OnPlatformDeactivated() => OnDeactivated();
}

// ================================================================== screen

/// What the display looks like. `TScreen`, without the monitor list, the form
/// list, the cursor stack or the font enumeration.
public static class Screen
{
    /// The whole display, in pixels.
    public static Size Bounds => WidgetSet.Current.ScreenSize;

    /// The part not covered by a task bar or dock, which is what a window
    /// should be centred in and what "maximised" actually means.
    public static Rectangle WorkArea => WidgetSet.Current.WorkArea;
}
