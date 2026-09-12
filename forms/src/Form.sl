// Stainless - an experimental systems language.
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
public class Form : WindowedControl, IWindowNotify {
    IWindowPeer  window;
    WindowBorder framing;
    bool         closing;
    bool         registered;

    /// Builds a form with the given frame.
    ///
    /// The window is made here rather than lazily, so every property set
    /// afterwards goes straight through and nothing needs replaying. A form
    /// that must choose its border at run time chooses it here, since changing
    /// it later costs the window on Windows.
    public Form(WindowBorder border) {
        base(null);
        framing = border;
        closing = false;
        registered = false;
        window = WidgetSet.Current.CreateWindow(this, border);
        AttachContainerPeer(window);
        SetBounds(0, 0, 640, 480);
    }

    /// The ordinary resizable window.
    public Form() { this(WindowBorder.Sizable); }

    /// The window's title. The same storage as `Text`, because on every
    /// platform a window's caption *is* its text, and the LCL keeping
    /// `Caption` and `Text` as separate published properties on `TCustomForm`
    /// only ever meant keeping the two in step.
    public String Title {
        get => Text;
        set { Text = value; }
    }

    /// How the window is framed. Read-only after construction; see the note on
    /// the constructor.
    public WindowBorder Border => framing;

    /// Normal, minimised or maximised. Read from the platform, because the user
    /// changes it without asking.
    public WindowState State {
        get => window.GetState();
        set { window.SetState(value); }
    }

    /// Centres the window on the work area of the screen it is on.
    public void CenterOnScreen() { window.CenterOnScreen(); }

    /// Shows the window and registers it with the `Application`.
    public override void Show() {
        if (!registered) {
            Application.Register(this);
            registered = true;
        }
        Visible = true;
        window.Activate();
    }

    /// Shows it and does not return until it is closed.
    ///
    /// **Answers nothing.** C#'s `ShowDialog` returns a `DialogResult`, which
    /// works because every C# dialog sets one; here a form that has an answer
    /// carries it as a property of its own, typed as whatever the answer
    /// actually is, and the caller reads that after this returns. A dialog
    /// whose answer is genuinely one of ok/cancel gives itself a
    /// `DialogResult` property and loses nothing.
    public void ShowModal() {
        if (!registered) {
            Application.Register(this);
            registered = true;
        }
        Visible = true;
        window.ShowModal();
    }

    /// Asks the window to close, running `OnClosing` first so a handler may
    /// refuse -- exactly as though the user had clicked the close box.
    public void Close() {
        if (closing) { return; }
        var asked = new CancelEventArgs();
        OnClosing(asked);
        if (asked.Cancel) { return; }
        closing = true;
        window.Close();
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
    /// Raised once, after the window exists and before the user sees it. Where
    /// a form does work that needs its final size.
    public event EventHandler Shown;

    protected virtual void OnClosing(CancelEventArgs args) { Closing(this, args); }
    protected virtual void OnClosed()      { Closed(this); }
    protected virtual void OnActivated()   { Activated(this); }
    protected virtual void OnDeactivated() { Deactivated(this); }
    protected virtual void OnShown()       { Shown(this); }

    // --------------------------------------------- what the platform says

    /// The user asked to close the window. True lets it go.
    ///
    /// The one notification that is a question rather than a report, which is
    /// why `IWindowNotify` exists at all and why it is the only method on it
    /// that returns anything.
    public bool OnPlatformClosing() {
        var asked = new CancelEventArgs();
        OnClosing(asked);
        return !asked.Cancel;
    }

    public void OnPlatformClosed() {
        closing = true;
        OnClosed();
        if (registered) {
            Application.Unregister(this);
            registered = false;
        }
    }

    public void OnPlatformActivatedWindow() { OnActivated(); }
    public void OnPlatformDeactivated()     { OnDeactivated(); }
}

// ================================================================== screen

/// What the display looks like. `TScreen`, without the monitor list, the form
/// list, the cursor stack or the font enumeration.
public static class Screen {
    /// The whole display, in pixels.
    public static Size Bounds => WidgetSet.Current.ScreenSize();

    /// The part not covered by a task bar or dock, which is what a window
    /// should be centred in and what "maximised" actually means.
    public static Rectangle WorkArea => WidgetSet.Current.WorkArea();
}
