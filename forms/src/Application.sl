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
import Standard.Threading;
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

    /// Set once the program has been asked to quit, and never cleared: the
    /// platform's quit message is consumed by whichever loop sees it first,
    /// and every later question MUST still get the same answer.
    static bool s_quitting = false;

    /// Counts window activations, so the register can tell which form the user
    /// was in most recently.
    static int s_activations = 0;

    /// Which thread `Initialize` ran on, and so which one owns every widget.
    static nuint s_uiThread = 0u;

    /// What another thread has asked the UI thread to run.
    ///
    /// A `Mutex` rather than a `ConcurrentQueue` because the drain wants the
    /// whole queue at once: taking the lot under one lock and running it
    /// outside means an action that posts another does not deadlock, and does
    /// not get run in the same turn either.
    static readonly Mutex<List<Action>> s_posted = new Mutex<List<Action>>(new List<Action>());

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
        s_uiThread = CurrentId();
        s_started = true;
    }

    /// Whether `Initialize` has run.
    public static bool IsInitialized => s_started;

    /// Which platform this program ended up on: `"Win32"`, `"GTK3"`.
    public static String PlatformName => WidgetSet.Current.Name;

    // ----------------------------------------------------------- the loop

    /// Runs until the last window closes. Returns at once if the program has
    /// already been asked to quit.
    public static void Run()
    {
        if (s_quitting)
            return;
        // Anything posted before the loop existed is run first rather than
        // waiting for the next wake, which may never come in a program that
        // does its setup on a thread and then shows a window.
        Drain();
        WidgetSet.Current.RunEventLoop();
    }

    /// Handles everything already queued and returns, for a program driving its
    /// own loop. False once the program has been asked to quit, and on every
    /// call after that.
    public static bool DoEvents()
    {
        Drain();
        if (!WidgetSet.Current.PumpEvents())
            s_quitting = true;
        return !s_quitting;
    }

    /// Makes `Run` return, whether or not any window is still open.
    public static void Quit()
    {
        s_quitting = true;
        WidgetSet.Current.QuitEventLoop();
    }

    /// Whether the program has been asked to quit.
    public static bool IsQuitting => s_quitting;

    // ------------------------------------------------------- the UI thread

    /// Whether the caller is the thread that owns the widgets.
    ///
    /// Every control belongs to the thread that created it -- a Win32 window
    /// procedure runs on the thread that made the window, and GTK wants its
    /// main context -- so touching one from anywhere else is a bug whatever it
    /// appears to do. `Post` is how another thread reaches them instead.
    public static bool OnUiThread => s_uiThread != 0u && CurrentId() == s_uiThread;

    /// Runs `work` on the UI thread and returns without waiting for it.
    ///
    ///     Application.Post(() => _status.Text = "done");
    ///
    /// Safe from any thread, and the only thing that is. `work` is a closure,
    /// so it carries what it captured by value and the controls it names are
    /// only ever touched on the thread that owns them -- which is the shape the
    /// sendability rule wants rather than one it tolerates.
    ///
    /// **Most programs should not call this.** `Background.Run` is the pair of
    /// closures you actually want, and this is what it is built on. Reach for
    /// it directly to report progress from inside a long job.
    public static void Post(Action work)
    {
        Enqueue(work);
        WidgetSet.Current.Wake();
    }

    /// Runs `work` on the UI thread and waits for it to finish.
    ///
    /// **From the UI thread it runs inline**, because posting and then waiting
    /// for a loop this call is itself blocking would wait forever. That is the
    /// classic deadlock in this shape of API, and answering it here is cheaper
    /// than documenting it.
    ///
    /// Prefer `Post` unless the answer is needed before this thread goes on.
    /// A worker that waits on the UI thread is a worker that has given up the
    /// thing it went to another thread for.
    ///
    /// **Before `Initialize` it also runs inline.** No thread owns the widgets
    /// yet, so there is no loop to wait for, and waiting would never end.
    public static void Send(Action work)
    {
        if (OnUiThread || s_uiThread == 0u)
        {
            work();
            return;
        }

        var done = new ManualResetEvent(false);
        Post(() =>
        {
            work();
            done.Set();
        });
        done.Wait();
    }

    /// Runs everything posted so far. Called by the backend when `Wake` has
    /// had its effect, and by `Run` and `DoEvents` so that work posted before
    /// a loop started is not left sitting.
    ///
    /// **The queue is taken whole and run outside the lock.** An action that
    /// posts another would otherwise deadlock on a lock this call still holds,
    /// and a queue drained in place could be appended to for as long as the
    /// actions kept posting -- which would turn one turn of the loop into an
    /// unbounded one.
    public static void Drain()
    {
        var taken = TakePosted();
        for (nuint i = 0u; i < taken.Count; i++)
            taken[i]();
    }

    static void Enqueue(Action work)
    {
        var guard = s_posted.Lock();
        guard.Value.Add(work);
    }                                   // ~Guard() unlocks before the wake

    static List<Action> TakePosted()
    {
        var taken = new List<Action>();
        var guard = s_posted.Lock();
        var pending = guard.Value;

        for (nuint i = 0u; i < pending.Count; i++)
            taken.Add(pending[i]);

        pending.Clear();
        return taken;
    }

    // -------------------------------------------------------- the register

    /// Called by `Form.Show`. Not public: a form registers itself.
    static void Register(Form form)
    {
        s_open.Add(form);
    }

    /// Called when a form has closed. The last one out stops the loop, which is
    /// what makes a one-window program need no `Quit` call at all.
    ///
    /// **A modal form is never the last one out.** It is a question asked on
    /// the way somewhere, and a login dialog closing before the main window
    /// opens MUST NOT end the program.
    static void Unregister(Form form, bool wasModal)
    {
        Remove(form);
        ReleaseLater(form);
        if (wasModal)
            return;
        foreach (var open in s_open)
        {
            if (!open.IsModal)
                return;
        }
        Quit();
    }

    /// Keeps a closed form alive until the loop's next turn.
    ///
    /// The register may hold its last reference, and the close is reported
    /// from inside the handlers of its own window. Freeing it there would
    /// destroy that window a second time while the platform is still
    /// destroying it.
    static void ReleaseLater(Form form)
    {
        Post(() => { Application.KeepUntilDrained(form); });
    }

    static void KeepUntilDrained(Form form) { }

    /// Called by a form that became the active window.
    static void NoteActivated(Form form)
    {
        s_activations++;
        form.MarkActivated(s_activations);
    }

    /// The form a modal dialog belongs to: the one the user was in most
    /// recently, or the main one, or null when nothing else is showing.
    static Form? OwnerFor(Form dialog)
    {
        Form? chosen = null;
        foreach (var form in s_open)
        {
            if (form == dialog || form.IsClosed || !form.Visible)
                continue;
            if (chosen == null || form.Activation > ((Form)chosen).Activation)
                chosen = form;
        }
        return chosen;
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

    /// The first window shown and still open, which is the one a program
    /// usually means by "the main window". A modal dialog is never it. Null
    /// before anything else has been shown.
    public static Form? MainForm
    {
        get
        {
            foreach (var form in s_open)
            {
                if (!form.IsModal)
                    return form;
            }
            return null;
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
