// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// Find and replace: a small window over whichever editor is in front.
//
// **Modeless, which is the whole design.** A modal find dialog cannot let you
// click in the text it just found, scroll to see the context, or fix the line
// while the box is open -- so every editor's is modeless, and this one is too.
// What that costs is that the dialog outlives any particular tab, and must
// therefore never hold one: it asks the shell for the editor in front *each
// time a button is pressed*, so switching tabs while it is open searches the
// tab you are now looking at, which is what someone would expect and what
// holding a reference would get wrong.
//
// **It owns no search logic.** Finding and replacing are methods on
// `CodeEditor`, because they are operations on a document rather than on a
// window -- which is also what makes them checkable by the self test, where
// there is no dialog and no mouse. This file is three text boxes, a tick and
// four buttons.
module Ide.App;

import Standard.Text;
import Forms;
import Forms.Drawing;
import Forms.Platform;
import Ide.Editor;

/// Asks the window which editor a button should act on.
///
/// A closure rather than a reference to the `Shell`, because `Shell` is what
/// creates this and a field pointing back would be a cycle -- and because "the
/// editor in front" is a question, not a thing: it changes as tabs change, and
/// the answer has to be asked for at the moment it is needed.
public closure CodeEditor? EditorSource();

/// The find and replace window.
public class FindDialog : Form
{
    Label _findLabel;
    TextBox _find;
    Label _replaceLabel;
    TextBox _replace;
    CheckBox _matchCase;
    Button _findNext;
    Button _replaceOne;
    Button _replaceAll;
    Button _close;
    Label _report;

    EditorSource _editorOf;

    public FindDialog(EditorSource source)
    {
        // `Tool` rather than `Fixed`: a thin caption and absent from the task
        // bar, which is what a utility window that belongs to another window
        // should be. Not sizable, because nothing in it would use the room.
        base(WindowBorder.Tool);
        _editorOf = source;
        Title = "Find and replace";
        // The outer frame, caption and borders included -- there is no
        // client-size setter -- so this is the 140 the controls need plus the
        // room a tool caption takes. Measured by looking: the first attempt
        // sized the frame to the content and cut the bottom row off.
        SetBounds(0, 0, 428, 186);

        _findLabel = new Label(this);
        _findLabel.Text = "Find:";
        _findLabel.SetBounds(12, 15, 60, 20);

        _find = new TextBox(this, false);
        _find.SetBounds(76, 12, 230, 24);
        _find.Anchors = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;

        _replaceLabel = new Label(this);
        _replaceLabel.Text = "Replace:";
        _replaceLabel.SetBounds(12, 47, 60, 20);

        _replace = new TextBox(this, false);
        _replace.SetBounds(76, 44, 230, 24);
        _replace.Anchors = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;

        _matchCase = new CheckBox(this);
        _matchCase.Text = "Match case";
        _matchCase.SetBounds(76, 76, 120, 22);

        _findNext = new Button(this);
        _findNext.Text = "Find next";
        _findNext.SetBounds(316, 12, 92, 26);
        _findNext.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        _findNext.Click += this.OnFindNext;

        _replaceOne = new Button(this);
        _replaceOne.Text = "Replace";
        _replaceOne.SetBounds(316, 44, 92, 26);
        _replaceOne.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        _replaceOne.Click += this.OnReplace;

        _replaceAll = new Button(this);
        _replaceAll.Text = "Replace all";
        _replaceAll.SetBounds(316, 76, 92, 26);
        _replaceAll.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        _replaceAll.Click += this.OnReplaceAll;

        _close = new Button(this);
        _close.Text = "Close";
        _close.SetBounds(316, 108, 92, 26);
        _close.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        _close.Click += this.OnCloseClicked;

        _report = new Label(this);
        _report.SetBounds(12, 112, 296, 20);
        _report.Anchors = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
    }

    /// What is being looked for, so that the shell can seed it from the
    /// selection when the dialog is opened.
    public String Needle
    {
        get => _find.Text;
        set => _find.Text = value;
    }

    /// Brings it up, puts the caret in the Find box and selects what is there,
    /// so that typing replaces the last search rather than appending to it.
    public void Present()
    {
        Show();
        _find.Focus();
        _find.SelectAll();
        Announce("");
    }

    void Announce(String what) => _report.Text = what;

    /// The editor to act on, or null when there is none -- which is a state the
    /// window can genuinely be in, since this dialog outlives any tab.
    CodeEditor? Target()
    {
        var editor = _editorOf();
        if (editor == null)
            Announce("Nothing to search.");
        return editor;
    }

    void OnFindNext(Control sender)
    {
        var editor = Target();
        if (editor == null)
            return;
        if (_find.Text == "")
        {
            Announce("Type something to find.");
            return;
        }

        if (((CodeEditor)editor).FindNext(_find.Text, _matchCase.Checked, true))
        {
            Announce("");
            // The match is selected in the editor and the editor is behind this
            // window, so the selection has to be visible without the focus
            // moving -- which it is, because `CodeEditor` draws its own
            // selection rather than relying on the platform's focus state.
        }
        else
        {
            Announce("No more matches for '" + _find.Text + "'.");
        }
    }

    void OnReplace(Control sender)
    {
        var editor = Target();
        if (editor == null || _find.Text == "")
            return;

        if (((CodeEditor)editor).ReplaceCurrent(_find.Text, _replace.Text,
                                                _matchCase.Checked))
        {
            Announce("Replaced one.");
        }
        else
        {
            Announce("");
        }
    }

    void OnReplaceAll(Control sender)
    {
        var editor = Target();
        if (editor == null || _find.Text == "")
            return;

        nuint done = ((CodeEditor)editor).ReplaceAll(_find.Text, _replace.Text,
                                                     _matchCase.Checked);
        Announce(done == 0u
            ? "Nothing to replace."
            : "Replaced " + Standard.Text.FromInteger(done)
              + (done == 1u ? " occurrence." : " occurrences."));
    }

    void OnCloseClicked(Control sender) => Hide();

    /// Closing the window hides it instead.
    ///
    /// **The dialog is made once and kept**, so that the last search and the
    /// Match case tick survive being closed and reopened -- which is what every
    /// editor does and what makes Find, close, look, Find again bearable.
    /// Destroying it would also destroy the only thing that remembers them.
    protected override void OnClosing(CancelEventArgs args)
    {
        base.OnClosing(args);
        args.Cancel = true;
        Hide();
    }
}
