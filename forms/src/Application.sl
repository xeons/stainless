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

// The program: which platform it is on, which windows are open, and the loop.
//
// `TApplication` is a `TComponent` with sixty published properties, an
// exception handler, a hint timer, an action list and the whole of the LCL's
// keyboard routing. This is the part a program actually calls -- initialize,
// run, quit -- plus the register of open windows that keeps them alive.
//
// **It is a static class, not an object.** The LCL's `Application` is a global
// variable holding an instance, which buys the ability to subclass it and is
// used for that by almost nobody; what it costs is that every one of its
// members is reached through a mutable global that a program can reassign.
// Here there is one program, it is not a value, and the name says so.
module Forms;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;

/// The running program.
///
/// ```
/// int Main() {
///     Application.Initialize();
///     var form = new MainForm();
///     form.Show();
///     Application.Run();
///     return 0;
/// }
/// ```
public static class Application
{
    /// The windows that are open, which is what keeps them alive.
    ///
    /// A form shown from a local variable would otherwise be destroyed when the
    /// function returned: the platform holds a window, but nothing would hold
    /// the object that answers its messages, and the first click would arrive
    /// at a peer whose control had gone. Registering on `Show` and
    /// unregistering on close is the whole of the fix, and is why a program
    /// never has to keep a field for a form it only wanted to open.
    static List<Form> s_open = new List<Form>();

    static bool s_started = false;

    /// Chooses the platform and gets it ready.
    ///
    /// **Call it before making any control.** Every control asks the widget set
    /// for its peer as it is constructed, so one built before this has nothing
    /// to be built from -- which `WidgetSet.Current` says in as many words
    /// rather than failing on a null reference somewhere further in.
    ///
    /// Which backend it picks is decided at compile time by `#if`, so a program
    /// that only ever runs on Windows links no GTK and vice versa. A program
    /// that wants a different one -- a recording backend under test -- sets
    /// `WidgetSet.Current` itself and does not call this.
    public static void Initialize()
    {
        if (s_started)
            return;
        WidgetSet.Current = MakeWidgetSet();
        s_started = true;
    }

    /// Whether `Initialize` has run.
    public static bool IsInitialized => s_started;

    /// Which platform this program ended up on: `"Win32"`, `"GTK3"`.
    public static String PlatformName => WidgetSet.Current.Name;

    // ----------------------------------------------------------- the loop

    /// Runs until the last window closes.
    public static void Run()
    {
        WidgetSet.Current.RunEventLoop();
    }

    /// Handles everything already queued and returns, for a program driving its
    /// own loop. False once the program has been asked to quit.
    public static bool DoEvents()
    {
        return WidgetSet.Current.PumpEvents();
    }

    /// Makes `Run` return, whether or not any window is still open.
    public static void Quit()
    {
        WidgetSet.Current.QuitEventLoop();
    }

    // -------------------------------------------------------- the register

    /// Called by `Form.Show`. Not public: a form registers itself.
    static void Register(Form form)
    {
        s_open.Add(form);
    }

    /// Called when a form has closed. The last one out stops the loop, which is
    /// what makes a one-window program need no `Quit` call at all.
    static void Unregister(Form form)
    {
        Remove(form);
        if (s_open.IsEmpty())
            Quit();
    }

    /// Drops one form from the register, keeping the order of the rest.
    ///
    /// Written out rather than using a `Remove` on the list, because removal by
    /// value needs equality on `Form` and reference identity is what is meant.
    static void Remove(Form gone)
    {
        var kept = new List<Form>();
        foreach (var form in s_open)
        {
            if (form != gone)
                kept.Add(form);
        }
        s_open = kept;
    }

    /// The windows currently open.
    public static List<Form> OpenForms => s_open;

    /// The first window shown, which is the one a program usually means by
    /// "the main window". Null before anything has been shown.
    public static Form? MainForm
    {
        get
        {
            if (s_open.IsEmpty())
                return null;
            return s_open.At(0u);
        }
    }

    // -------------------------------------------------------- the messages

    /// A message box. The one dialog every program needs and nobody should
    /// have to build.
    public static DialogResult ShowMessage(String text, String caption,
                                           MessageButtons buttons, MessageIcon icon)
    {
        return WidgetSet.Current.ShowMessage(null, text, caption, buttons, icon);
    }

    /// Tells the user something.
    public static void Inform(String text, String caption)
    {
        ShowMessage(text, caption, MessageButtons.Ok, MessageIcon.Information);
    }

    /// Warns them.
    public static void Warn(String text, String caption)
    {
        ShowMessage(text, caption, MessageButtons.Ok, MessageIcon.Warning);
    }

    /// Reports a failure.
    public static void Complain(String text, String caption)
    {
        ShowMessage(text, caption, MessageButtons.Ok, MessageIcon.Error);
    }

    /// Asks a yes-or-no question. True for yes.
    public static bool Ask(String text, String caption)
    {
        return ShowMessage(text, caption, MessageButtons.YesNo, MessageIcon.Question)
            == DialogResult.Yes;
    }
}
