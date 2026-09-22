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

// Text: the `Label` that shows it and the `TextBox` that takes it.
//
// **`TEdit` and `TMemo` are one control here, as they are in C#.** The LCL
// keeps them apart because `TCustomMemo` adds a `TStrings` and a scroll bar,
// and a `TStrings` is a class with thirty members that exists mostly because
// Object Pascal has no array of strings worth using. Stainless has `String[]`,
// so what is left of the difference is one style bit -- which is what
// `Multiline` is.
module Forms;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;

// ===================================================================== label

/// Text the user reads and cannot edit.
///
/// **A `WindowedControl`, not a `GraphicControl`.** The LCL's `TLabel` is
/// handle-less and painted by its parent, which is the right trade when a form
/// has two hundred of them. It is not the right trade *first*: a platform label
/// gets the theme's font smoothing, its ellipsis behaviour and its right-to-left
/// handling for nothing, and a painted one gets none of those until each is
/// written. `GraphicControl` is there for when the count matters.
public class Label : WindowedControl
{
    ILabelPeer _native;
    HorizontalAlignment _aligned;
    bool _wrapping;

    public Label(WindowedControl parent)
    {
        base(parent);
        _aligned = HorizontalAlignment.Left;
        _wrapping = false;
        _native = WidgetSet.Current.CreateLabel(this, ParentPeer());
        AttachPeer(_native);
    }

    /// Where the text sits across the label's width.
    public HorizontalAlignment TextAlign
    {
        get => _aligned;
        set
        {
            _aligned = value;
            _native.SetAlignment(value);
        }
    }

    /// Whether a line too long for the label wraps rather than being cut.
    public bool WordWrap
    {
        get => _wrapping;
        set
        {
            _wrapping = value;
            _native.SetWordWrap(value);
        }
    }

    public override Size PreferredSize => _native.PreferredSize;

    /// Sizes the label to its text. What a label almost always wants, and the
    /// reason this is a method here rather than an `AutoSize` flag that has to
    /// be re-applied every time the text changes.
    protected override void OnTextChanged()
    {
        base.OnTextChanged();
        Invalidate();
    }
}

// ================================================================ text box

/// What every control the user types into has in common.
public abstract class TextBoxBase : WindowedControl
{
    protected TextBoxBase(WindowedControl parent) => base(parent);

    /// The entry's platform side, which the derived class made.
    protected abstract ITextEntryPeer Entry { get; }

    /// White under a light theme, rather than the form's grey. A field you type
    /// into is the window colour on every platform, and taking the parent's
    /// would make it look disabled.
    protected override Color DefaultBackColor => SystemColors.Window;
    protected override Color DefaultForeColor => SystemColors.WindowText;

    /// Whether the text can be changed by the user. The program may still set
    /// `Text`, which is the difference between this and `Enabled`.
    public bool ReadOnly
    {
        get => _readOnly;
        set
        {
            _readOnly = value;
            Entry.SetReadOnly(value);
        }
    }

    /// The most characters the user may type, or zero for no limit.
    public int MaxLength
    {
        get => _maxLength;
        set
        {
            _maxLength = value;
            Entry.SetMaxLength(value);
        }
    }

    /// Where the selection starts, in characters.
    public int SelectionStart
    {
        get
        {
            var (start, length) = Entry.GetSelection();
            return start;
        }
        set => Entry.SetSelection(value, SelectionLength);
    }

    /// How many characters are selected.
    public int SelectionLength
    {
        get
        {
            var (start, length) = Entry.GetSelection();
            return length;
        }
        set => Entry.SetSelection(SelectionStart, value);
    }

    /// Selects everything, which is what a field being focused for replacement
    /// wants.
    ///
    /// Twice the byte count bounds the length on both platforms: a UTF-16 unit
    /// is never fewer bytes than one, and a line break Windows counts as two
    /// is one byte here. Both platforms clamp a selection to the text.
    public void SelectAll() => Entry.SetSelection(0, (int)Text.ByteLength() * 2);

    /// Moves the selection to the clipboard, as Ctrl+X does. Nothing happens
    /// when nothing is selected or the box is read-only.
    public void CutToClipboard() => Entry.CutToClipboard();

    /// Copies the selection to the clipboard, as Ctrl+C does.
    public void CopyToClipboard() => Entry.CopyToClipboard();

    /// Replaces the selection with the clipboard's text, as Ctrl+V does.
    ///
    /// `UserTextChanged` is raised, since this is the user's paste performed
    /// on their behalf. On GTK the text arrives from the main loop rather than
    /// before this returns, because the clipboard may belong to another
    /// process that has to be asked for it.
    public void PasteFromClipboard() => Entry.PasteFromClipboard();

    /// The text the platform holds, rather than the last value set -- the user
    /// has been typing, and the field would be stale.
    protected override String GetTextValue()
    {
        var peer = Peer;
        if (peer == null)
            return StoredText;
        return ((IControlPeer)peer).GetText();
    }

    /// Compared against the text the platform holds, for the reason the getter
    /// reads it: the stored text is the last the program set, and the user or
    /// `Lines` may have replaced it since.
    protected override void SetTextValue(String value)
    {
        if (GetTextValue() == value)
            return;
        StoredText = value;
        ApplyText();
        OnTextChanged();
    }

    /// The text changed because the user typed. Distinct from `TextChanged`
    /// only in that the program setting `Text` does not raise it.
    public event EventHandler UserTextChanged;

    protected virtual void OnUserTextChanged() => UserTextChanged(this);

    public override void OnPlatformValueChanged()
    {
        OnUserTextChanged();
        base.OnPlatformValueChanged();
    }

    bool _readOnly;
    int _maxLength;
}

/// A box the user types into, on one line or several.
///
/// ```
/// var name = new TextBox(this);
/// name.SetBounds(10, 10, 200, 24);
/// name.Text = "Ada";
/// name.UserTextChanged += this.OnNameEdited;
/// ```
public class TextBox : TextBoxBase
{
    ITextEntryPeer _native;
    bool _multiline;

    /// **Multiline is chosen here and cannot change.** It is a creation-time
    /// style on Windows, so a box that changed its mind would have to be
    /// rebuilt -- which is a thing a program can do by making another one, and
    /// is not a thing a property should hide.
    public TextBox(WindowedControl parent, bool multiline)
    {
        base(parent);
        this._multiline = multiline;
        _native = WidgetSet.Current.CreateTextEntry(this, ParentPeer(), multiline);
        AttachPeer(_native);
    }

    /// A single-line box.
    public TextBox(WindowedControl parent) => this(parent, false);

    protected override ITextEntryPeer Entry => _native;

    /// Whether this box holds several lines.
    public bool Multiline => _multiline;

    /// The text split into lines, with the platform's line endings already
    /// normalised away.
    public String[] Lines
    {
        get => _native.GetLines();
        set => _native.SetLines(value);
    }

    /// What is shown instead of each character, for a password field. The
    /// NUL character means "show the text", which is what every platform means
    /// by it.
    public char PasswordChar
    {
        get => _mask;
        set
        {
            _mask = value;
            _native.SetPasswordChar(value);
        }
    }

    public override Size PreferredSize => _native.PreferredSize;

    char _mask;
}
