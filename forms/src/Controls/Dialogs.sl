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

// The dialogs the platform already has: open, save, choose a folder, choose a
// colour, choose a font.
//
// **Not `TComponent`s that are dropped on a form.** `TOpenDialog` is a
// component with twenty published properties because the LCL's designer needs
// something to show in the object inspector; what a program does with one is
// set two of those and call `Execute`. These are plain objects with the two
// settings that matter and a method that answers.
//
// **And they answer a `Result`, not a bool.** `TOpenDialog.Execute` returns
// false both when the user pressed Cancel and when the dialog could not open at
// all, leaving `FileName` as whatever it was -- so a caller that forgets the
// test reads a stale path. Here the choice is *in* the answer, and there is
// nothing to read if there was no choice.
module Forms;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;

// ================================================================ file dialogs

/// What a file dialog filters by: a description and the patterns it covers.
///
/// ```
/// var filters = [FileFilter.FromPatterns("Text files", "*.txt;*.md"),
///                FileFilter.FromPatterns("All files", "*.*")];
/// ```
public struct FileFilter
{
    public String Description;
    public String Patterns;

    public static FileFilter FromPatterns(String description, String patterns)
    {
        FileFilter filter;
        filter.Description = description;
        filter.Patterns = patterns;
        return filter;
    }
}

/// What a file dialog has in common.
public abstract class FileDialog
{
    protected List<FileFilter> _filters;

    protected FileDialog()
    {
        _filters = new List<FileFilter>();
        Title = "";
        FileName = "";
    }

    /// The caption. Empty leaves the platform's own, which is translated and
    /// usually better than anything a program would write.
    public String Title { get; set; }

    /// What the dialog opens showing, and what it last answered.
    public String FileName { get; set; }

    /// Adds a kind of file the dialog offers to filter by.
    public FileDialog AddFilter(String description, String patterns)
    {
        _filters.Add(FileFilter.FromPatterns(description, patterns));
        return this;
    }

    /// The filters flattened the way the platform wants them, description and
    /// pattern alternating.
    protected String[] BuildFilterPairs()
    {
        var flat = new String[_filters.Count * 2u];
        for (nuint i = 0u; i < _filters.Count; i++)
        {
            flat[i * 2u] = _filters[i].Description;
            flat[i * 2u + 1u] = _filters[i].Patterns;
        }
        return flat;
    }

    /// The window the dialog should sit over, or null for none.
    protected IWindowPeer? FindOwnerWindow(Control? owner)
    {
        if (owner == null)
            return null;
        var form = ((Control)owner).FindForm();
        if (form == null)
            return null;
        return ((Form)form).WindowPeer;
    }
}

/// Choose a file to open.
public class OpenDialog : FileDialog
{
    public OpenDialog() => base();

    /// Shows it, and answers what was chosen.
    ///
    /// `FileName` is also set, for a caller that would rather read it there --
    /// but only when there was an answer, so it is never a stale path.
    public Result<String, DialogOutcome> ShowDialog(Control? owner)
    {
        var chosen = WidgetSet.Current.ChooseFileToOpen(
            FindOwnerWindow(owner), Title, FileName, BuildFilterPairs());
        if (chosen.Ok)
            FileName = chosen.Value;
        return chosen;
    }
}

/// Choose where to save.
public class SaveDialog : FileDialog
{
    public SaveDialog() => base();

    public Result<String, DialogOutcome> ShowDialog(Control? owner)
    {
        var chosen = WidgetSet.Current.ChooseFileToSave(
            FindOwnerWindow(owner), Title, FileName, BuildFilterPairs());
        if (chosen.Ok)
            FileName = chosen.Value;
        return chosen;
    }
}

/// Choose a folder.
public class FolderDialog : FileDialog
{
    public FolderDialog() => base();

    public Result<String, DialogOutcome> ShowDialog(Control? owner)
    {
        var chosen = WidgetSet.Current.ChooseFolder(FindOwnerWindow(owner), Title);
        if (chosen.Ok)
            FileName = chosen.Value;
        return chosen;
    }
}

// =============================================================== colour dialog

/// Choose a colour.
public class ColorDialog
{
    public ColorDialog() => Color = Colors.White;

    /// What the dialog opens on, and what it last answered.
    public Color Color { get; set; }

    public Result<Color, DialogOutcome> ShowDialog(Control? owner)
    {
        var chosen = WidgetSet.Current.ChooseColor(FindOwnerWindow(owner), Color);
        if (chosen.Ok)
            Color = chosen.Value;
        return chosen;
    }

    IWindowPeer? FindOwnerWindow(Control? owner)
    {
        if (owner == null)
            return null;
        var form = ((Control)owner).FindForm();
        if (form == null)
            return null;
        return ((Form)form).WindowPeer;
    }
}

// ================================================================= font dialog

/// Choose a font.
public class FontDialog
{
    Font _font;

    public FontDialog() => _font = WidgetSet.Current.GetDefaultFont();

    /// What the dialog opens on, and what it last answered.
    public Font Font
    {
        get => _font;
        set => _font = value;
    }

    public Result<Font, DialogOutcome> ShowDialog(Control? owner)
    {
        var answer = WidgetSet.Current.ChooseFont(FindOwnerWindow(owner), _font);
        if (answer.Ok)
            _font = answer.Value;
        return answer;
    }

    IWindowPeer? FindOwnerWindow(Control? owner)
    {
        if (owner == null)
            return null;
        var form = ((Control)owner).FindForm();
        if (form == null)
            return null;
        return ((Form)form).WindowPeer;
    }
}

// ======================================================================= timer

/// Something to do every so often.
///
/// **Not a `Control`.** `TTimer` is a `TComponent` so the designer can hold one;
/// it has no position, no parent and nothing to draw, so here it is an object
/// that owns a platform timer and stops it when it is collected.
///
/// ```
/// var clock = new Timer(1000);
/// clock.Tick += this.OnSecond;
/// clock.Start();
/// ```
public class Timer : ITimerNotify
{
    ITimerPeer _native;
    int _interval;
    bool _enabled;

    /// A timer that has not started, ticking every `milliseconds` when it does.
    public Timer(int milliseconds)
    {
        _interval = milliseconds;
        _enabled = false;
        _native = WidgetSet.Current.CreateTimer(this);
    }

    public Timer() => this(1000);

    /// How long between ticks. Changing it while running restarts the interval,
    /// which is the only thing a platform timer can do.
    public int Interval
    {
        get => _interval;
        set
        {
            _interval = value;
            if (_enabled)
            {
                _native.Stop();
                _native.Start(_interval);
            }
        }
    }

    public bool Enabled
    {
        get => _enabled;
        set
        {
            if (value)
            {
                Start();
            }
            else
            {
                Stop();
            }
        }
    }

    public void Start()
    {
        if (_enabled)
            return;
        _enabled = true;
        _native.Start(_interval);
    }

    public void Stop()
    {
        if (!_enabled)
            return;
        _enabled = false;
        _native.Stop();
    }

    /// The interval elapsed.
    public event TimerHandler Tick;

    protected virtual void OnTick() => Tick(this);

    /// What the platform calls.
    public void OnPlatformTick() => OnTick();
}

/// What a timer's handler is given. Not `EventHandler`, because a timer is not
/// a `Control`.
public closure void TimerHandler(Timer sender);

// ============================================================= asking for text

/// A one-line question: a prompt, a box, OK and Cancel.
///
/// **The one dialog in this file the platform does not supply**, which is why
/// it is a `Form` made of three controls rather than a seam method with two
/// backends. Windows has no input box in its API at all -- `InputBox` is
/// Visual Basic's runtime, not `user32` -- and GTK's is a `GtkDialog` the
/// program assembles itself. A widget set asked to implement this would be
/// implementing exactly what is written here, twice.
///
/// It answers an `Optional<String>` for the reason the file dialogs answer a
/// `Result`: Cancel is *no answer*, and a caller that forgets to check should
/// find nothing to read rather than a stale string left over from last time.
///
/// ```
/// var name = InputDialog.PromptForText("Rename", "New name:", "old.sl");
/// if (name is Some given)
///     Rename(given.Value);
/// ```
public class InputDialog : Form
{
    Label _prompt;
    TextBox _entry;
    Button _ok;
    Button _cancel;

    /// What was typed, taken **inside** the OK handler.
    ///
    /// A `TextBox`'s text lives in the native control and goes with the
    /// window, so reading it after `ShowModal` returns answers the empty
    /// string. That is not a subtlety to be careful of; it is a bug that has
    /// already been written once in this tree, and it wrote an empty project
    /// file over a good one.
    String _answer;
    bool _accepted;

    /// Made by `PromptForText` alone: a dialog whose answer is read through a
    /// field should not be one a caller can hold and read at the wrong moment.
    InputDialog(String caption, String question, String initial)
    {
        base(WindowBorder.Fixed);
        Title = caption;
        SetBounds(0, 0, 380, 148);
        _answer = "";
        _accepted = false;

        _prompt = new Label(this);
        _prompt.Text = question;
        _prompt.SetBounds(12, 14, 352, 20);

        _entry = new TextBox(this, false);
        _entry.Text = initial;
        _entry.SetBounds(12, 38, 352, 24);
        _entry.Anchors = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        _entry.KeyDown += this.OnEntryKeyDown;

        _ok = new Button(this);
        _ok.Text = "OK";
        _ok.SetBounds(182, 78, 88, 28);
        _ok.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        _ok.Click += this.OnOkClick;

        _cancel = new Button(this);
        _cancel.Text = "Cancel";
        _cancel.SetBounds(276, 78, 88, 28);
        _cancel.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        _cancel.Click += this.OnCancelClick;
    }

    /// Enter accepts, because a one-line box is a form someone types into and
    /// presses Enter on. There is no default-button mechanism to hang this on:
    /// `IsDialogMessageW` gives a modal window Tab between its controls, but a
    /// default button needs a real dialog box with a `DEFPUSHBUTTON`, which
    /// these are not. Escape is handled by the modal loop already.
    void OnEntryKeyDown(Control sender, KeyEventArgs args)
    {
        if (args.Key == Key.Enter)
            OnOkClick(sender);
    }

    void OnOkClick(Control sender)
    {
        _answer = _entry.Text;
        _accepted = true;
        Close();
    }

    void OnCancelClick(Control sender)
    {
        _accepted = false;
        Close();
    }

    /// Asks, and answers what was typed -- or nothing, if it was not.
    ///
    /// `initial` is what the box starts with, which is the old name for a
    /// rename and the empty string for a new one.
    public static Optional<String> PromptForText(String caption, String question, String initial)
    {
        var dialog = new InputDialog(caption, question, initial);
        dialog.ShowModal();

        if (!dialog._accepted)
            return None;
        return Some(dialog._answer);
    }
}

