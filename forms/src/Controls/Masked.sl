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

// A text box that takes text in a fixed shape -- a telephone number, a date,
// a part number -- one position at a time: the LCL's TMaskEdit.
module Forms;

import Standard.Collections;
import Standard.Text;
import Forms.Platform;
#if FORMS_REFLECT
import Standard.Reflection;
#endif

/// What one position of a mask takes.
public enum MaskClass
{
    /// Fixed text, shown in the box and stepped over when typing.
    Literal,
    /// `0` and `9`: a digit.
    Digit,
    /// `#`: a digit, `+` or `-`.
    DigitOrSign,
    /// `L` and `l`: an ASCII letter.
    Letter,
    /// `A` and `a`: an ASCII letter or digit.
    LetterOrDigit,
    /// `C` and `c`: any character.
    Any,
    /// `H` and `h`: a hexadecimal digit.
    Hex,
    /// `B` and `b`: `0` or `1`.
    Binary,
    /// `[abc]` or `[a-z]`: one of the set.
    InSet,
    /// `[!abc]`: anything but one of the set.
    NotInSet,
}

/// The case a position turns what is typed into, after `>` or `<`.
public enum MaskCase
{
    AsTyped,
    Upper,
    Lower,
}

/// One position of a parsed mask.
public struct MaskSlot
{
    public MaskClass Class;
    public MaskCase Case;

    /// Whether the position MUST be filled for the text to be complete: the
    /// capital form of each class, and a set not marked optional with `|`.
    public bool Required;

    /// The character itself, for a literal.
    public char32 Literal;

    /// The members of a set, as two halves of a 128-bit map of ASCII.
    public ulong SetLow;
    public ulong SetHigh;
}

/// An edit mask, parsed: what each position takes, and how text goes in and
/// comes out.
///
/// The syntax is the LCL's, which is Delphi's with sets and hex added:
///
/// | | |
/// |---|---|
/// | `0` `9` | a digit, required or optional |
/// | `#` | a digit, `+` or `-`, optional |
/// | `L` `l` | a letter |
/// | `A` `a` | a letter or a digit |
/// | `C` `c` | any character |
/// | `H` `h` | a hexadecimal digit |
/// | `B` `b` | `0` or `1` |
/// | `[a-z]` `[!abc]` `[\|xyz]` | one of a set, none of it, or one of it or blank |
/// | `>` `<` `<>` | upper case from here, lower case, as typed |
/// | `\` | the next character is a literal |
/// | `!` | trim leading blanks rather than trailing ones from `Text` |
///
/// Anything else is a literal. `:` and `/` are literals as written, not the
/// locale's separators as they are in the LCL.
///
/// Two optional fields follow the mask, after `;`: whether `Text` keeps the
/// literals (`0` says no, anything else yes, the default), and the character
/// shown in an empty position (`_` by default). `(999) 000-0000;0;_` is a
/// telephone number whose `Text` is its ten digits.
public class MaskPattern
{
    List<MaskSlot> _slots;
    bool _savesLiterals;
    char32 _blank;
    bool _trimsLeading;

    MaskPattern()
    {
        _slots = new List<MaskSlot>();
        _savesLiterals = true;
        _blank = (char32)'_';
        _trimsLeading = false;
    }

    /// How many positions the mask has, which is how long `EditText` is.
    public nuint Length => _slots.Count;

    /// Whether `Text` keeps the literals.
    public bool SavesLiterals => _savesLiterals;

    /// What an empty position shows.
    public char32 Blank => _blank;

    /// Whether `Text` loses its leading blanks rather than its trailing ones.
    public bool TrimsLeading => _trimsLeading;

    public MaskSlot GetSlot(nuint at) => _slots[at];

    public bool IsLiteral(nuint at) => _slots[at].Class == MaskClass.Literal;

    /// What position `at` shows when nothing has been typed there.
    public char32 GetClearChar(nuint at)
    {
        var slot = _slots[at];
        return slot.Class == MaskClass.Literal ? slot.Literal : _blank;
    }

    /// The edit text of an empty box: the literals, and a blank everywhere
    /// else.
    public String BlankText
    {
        get
        {
            var made = new StringBuilder();
            for (nuint i = 0u; i < Length; i++)
                made.AppendCodePoint(GetClearChar(i));
            return made.ToText();
        }
    }

    /// Parses `editMask`. Never fails: a set with no closing `]` is taken as
    /// a literal `[`, and so is anything else that is not a mask character.
    public static MaskPattern Parse(String editMask)
    {
        var made = new MaskPattern();
        var all = MaskCodePoints(editMask);

        // The two trailing fields, separated by `;` that no `\` escapes.
        var fields = new List<List<char32>>();
        var field = new List<char32>();
        for (nuint i = 0u; i < all.Count; i++)
        {
            if (all[i] == (char32)'\\' && i + 1u < all.Count)
            {
                field.Add(all[i]);
                field.Add(all[i + 1u]);
                i++;
                continue;
            }
            if (all[i] == (char32)';' && fields.Count < 2u)
            {
                fields.Add(field);
                field = new List<char32>();
                continue;
            }
            field.Add(all[i]);
        }
        fields.Add(field);

        if (fields.Count > 1u && fields[1u].Count > 0u)
            made._savesLiterals = fields[1u][0u] != (char32)'0';
        if (fields.Count > 2u && fields[2u].Count > 0u)
            made._blank = fields[2u][0u];

        made.ParseSlots(fields[0u]);
        return made;
    }

    void ParseSlots(List<char32> mask)
    {
        var shift = MaskCase.AsTyped;
        for (nuint i = 0u; i < mask.Count; i++)
        {
            char32 c = mask[i];
            switch (c)
            {
                case (char32)'\\':
                    if (i + 1u < mask.Count)
                    {
                        i++;
                        AddLiteral(mask[i]);
                    }
                    break;
                case (char32)'!':
                    _trimsLeading = true;
                    break;
                case (char32)'>':
                    // `<>` turns case conversion off.
                    shift = i > 0u && mask[i - 1u] == (char32)'<' ? MaskCase.AsTyped : MaskCase.Upper;
                    break;
                case (char32)'<':
                    shift = MaskCase.Lower;
                    break;
                case (char32)'[':
                    i = ParseSet(mask, i, shift);
                    break;
                default:
                    AddClass(c, shift);
                    break;
            }
        }
    }

    void AddLiteral(char32 literal)
    {
        MaskSlot slot;
        slot.Class = MaskClass.Literal;
        slot.Case = MaskCase.AsTyped;
        slot.Required = false;
        slot.Literal = literal;
        slot.SetLow = 0u;
        slot.SetHigh = 0u;
        _slots.Add(slot);
    }

    void AddClass(char32 c, MaskCase shift)
    {
        MaskClass kind;
        bool required;
        switch (c)
        {
            case (char32)'0': kind = MaskClass.Digit; required = true; break;
            case (char32)'9': kind = MaskClass.Digit; required = false; break;
            case (char32)'#': kind = MaskClass.DigitOrSign; required = false; break;
            case (char32)'L': kind = MaskClass.Letter; required = true; break;
            case (char32)'l': kind = MaskClass.Letter; required = false; break;
            case (char32)'A': kind = MaskClass.LetterOrDigit; required = true; break;
            case (char32)'a': kind = MaskClass.LetterOrDigit; required = false; break;
            case (char32)'C': kind = MaskClass.Any; required = true; break;
            case (char32)'c': kind = MaskClass.Any; required = false; break;
            case (char32)'H': kind = MaskClass.Hex; required = true; break;
            case (char32)'h': kind = MaskClass.Hex; required = false; break;
            case (char32)'B': kind = MaskClass.Binary; required = true; break;
            case (char32)'b': kind = MaskClass.Binary; required = false; break;
            default:
                AddLiteral(c);
                return;
        }

        MaskSlot slot;
        slot.Class = kind;
        slot.Case = shift;
        slot.Required = required;
        slot.Literal = (char32)0;
        slot.SetLow = 0u;
        slot.SetHigh = 0u;
        _slots.Add(slot);
    }

    /// A set from `[` at `open`, answering the index of its `]`. Without one
    /// the `[` is a literal and parsing goes on after it.
    nuint ParseSet(List<char32> mask, nuint open, MaskCase shift)
    {
        nuint close = open + 1u;
        while (close < mask.Count && mask[close] != (char32)']')
            close++;
        if (close >= mask.Count)
        {
            AddLiteral((char32)'[');
            return open;
        }

        nuint at = open + 1u;
        bool negated = false;
        bool optional = false;
        if (at < close && mask[at] == (char32)'!')
        {
            negated = true;
            at++;
        }
        else if (at < close && mask[at] == (char32)'|')
        {
            optional = true;
            at++;
        }

        MaskSlot slot;
        slot.Class = negated ? MaskClass.NotInSet : MaskClass.InSet;
        slot.Case = shift;
        slot.Required = !optional;
        slot.Literal = (char32)0;
        slot.SetLow = 0u;
        slot.SetHigh = 0u;

        while (at < close)
        {
            char32 first = mask[at];
            char32 last = first;
            if (at + 2u < close && mask[at + 1u] == (char32)'-')
            {
                last = mask[at + 2u];
                at = at + 2u;
            }
            for (uint c = (uint)first; c <= (uint)last && c < 128u; c++)
            {
                if (c < 64u)
                    slot.SetLow = slot.SetLow | (1ul << (int)c);
                else
                    slot.SetHigh = slot.SetHigh | (1ul << (int)(c - 64u));
            }
            at++;
        }

        _slots.Add(slot);
        return close;
    }

    /// What position `at` makes of `typed`, converted to its case, or nothing
    /// when the position does not take it. A literal takes nothing.
    public Optional<char32> Accept(nuint at, char32 typed)
    {
        var slot = _slots[at];
        if (slot.Class == MaskClass.Literal)
            return None;

        // A space or the blank clears a position that may be left empty.
        if (typed == (char32)' ' || typed == _blank)
            return slot.Required ? None : Some(_blank);

        char32 c = typed;
        if (slot.Case == MaskCase.Upper)
            c = MaskToUpper(c);
        else if (slot.Case == MaskCase.Lower)
            c = MaskToLower(c);

        bool digit = c >= (char32)'0' && c <= (char32)'9';
        bool letter = (c >= (char32)'a' && c <= (char32)'z') || (c >= (char32)'A' && c <= (char32)'Z');
        bool taken;
        switch (slot.Class)
        {
            case MaskClass.Digit: taken = digit; break;
            case MaskClass.DigitOrSign: taken = digit || c == (char32)'+' || c == (char32)'-'; break;
            case MaskClass.Letter: taken = letter; break;
            case MaskClass.LetterOrDigit: taken = letter || digit; break;
            case MaskClass.Any: taken = true; break;
            case MaskClass.Hex:
                taken = digit || (c >= (char32)'a' && c <= (char32)'f') || (c >= (char32)'A' && c <= (char32)'F');
                break;
            case MaskClass.Binary: taken = c == (char32)'0' || c == (char32)'1'; break;
            case MaskClass.InSet: taken = SetHolds(slot, c); break;
            case MaskClass.NotInSet: taken = !SetHolds(slot, c); break;
            default: taken = false; break;
        }
        return taken ? Some(c) : None;
    }

    /// Whether `shown` is a correct character for position `at` in complete
    /// text: its literal, a character the position takes, or a blank where
    /// one is allowed.
    public bool Matches(nuint at, char32 shown)
    {
        var slot = _slots[at];
        if (slot.Class == MaskClass.Literal)
            return shown == slot.Literal;
        if (shown == _blank)
            return !slot.Required;
        return Accept(at, shown) is Some taken && taken.Value == shown;
    }

    /// The first position of `editText` that is wrong, or `Length` when it is
    /// complete. Text of the wrong length is wrong at its end.
    public nuint FindFirstMismatch(String editText)
    {
        var shown = MaskCodePoints(editText);
        for (nuint i = 0u; i < Length; i++)
        {
            if (i >= shown.Count || !Matches(i, shown[i]))
                return i;
        }
        return shown.Count == Length ? Length : shown.Count;
    }

    /// Whether `editText` fills the mask: every required position filled and
    /// every character one its position takes.
    public bool IsComplete(String editText) => FindFirstMismatch(editText) == Length;

    /// `text`, laid into the mask: what a program setting `Text` shows.
    ///
    /// When `text` has the mask's literals, each run between two of them
    /// fills the positions between the mask's matching two, so `1-2` in
    /// `cc-cc` shows as `1_-2_`. Otherwise its characters fill the open
    /// positions in order, so `5551234567` in `(999) 000-0000` shows as
    /// `(555) 123-4567`. Either way they are filled from the left, or
    /// from the right after `!`. Nothing is checked: text that does not fit
    /// shows as it is, and `IsValid` says so.
    public String Fit(String text)
    {
        var shown = MaskCodePoints(BlankText);
        var value = MaskCodePoints(text);

        if (HoldsALiteral(value))
        {
            nuint start = 0u;
            nuint from = 0u;
            for (nuint m = 0u; m <= Length; m++)
            {
                if (m < Length && !IsLiteral(m))
                    continue;

                nuint to = value.Count;
                if (m < Length)
                {
                    nuint found = from;
                    while (found < value.Count && value[found] != _slots[m].Literal)
                        found++;
                    to = found;
                }

                FillRun(shown, start, m, value, from, to);
                from = to < value.Count ? to + 1u : to;
                start = m + 1u;
            }
            return MaskJoin(shown);
        }

        var open = new List<nuint>();
        for (nuint i = 0u; i < Length; i++)
        {
            if (!IsLiteral(i))
                open.Add(i);
        }
        var characters = value;

        nuint count = characters.Count < open.Count ? characters.Count : open.Count;
        for (nuint i = 0u; i < count; i++)
        {
            nuint into = _trimsLeading ? open[open.Count - count + i] : open[i];
            nuint taken = _trimsLeading ? characters.Count - count + i : i;
            shown[into] = characters[taken] == (char32)' ' ? _blank : characters[taken];
        }
        return MaskJoin(shown);
    }

    bool HoldsALiteral(List<char32> value)
    {
        for (nuint i = 0u; i < Length; i++)
        {
            if (!IsLiteral(i))
                continue;
            for (nuint j = 0u; j < value.Count; j++)
            {
                if (value[j] == _slots[i].Literal)
                    return true;
            }
        }
        return false;
    }

    /// Fills positions `[low, high)` of `shown` from `value[from, to)`, from
    /// the left or, after `!`, from the right. A space becomes the blank.
    void FillRun(List<char32> shown, nuint low, nuint high, List<char32> value, nuint from, nuint to)
    {
        nuint room = high - low;
        nuint have = to - from;
        nuint count = have < room ? have : room;
        for (nuint i = 0u; i < count; i++)
        {
            nuint into = _trimsLeading ? high - count + i : low + i;
            nuint taken = _trimsLeading ? to - count + i : from + i;
            shown[into] = value[taken] == (char32)' ' ? _blank : value[taken];
        }
    }

    /// What `Text` answers for `editText`: blanks as spaces, and when the mask
    /// does not save its literals, without them and trimmed.
    public String Strip(String editText)
    {
        var shown = MaskCodePoints(editText);
        var kept = new List<char32>();
        for (nuint i = 0u; i < shown.Count; i++)
        {
            bool literal = i < Length && IsLiteral(i);
            if (literal && !_savesLiterals)
                continue;
            if (!literal && shown[i] == _blank)
                kept.Add((char32)' ');
            else
                kept.Add(shown[i]);
        }

        if (!_savesLiterals)
        {
            if (_trimsLeading)
            {
                while (kept.Count > 0u && kept[0u] == (char32)' ')
                    kept.RemoveAt(0u);
            }
            else
            {
                while (kept.Count > 0u && kept[kept.Count - 1u] == (char32)' ')
                    kept.RemoveAt(kept.Count - 1u);
            }
        }
        return MaskJoin(kept);
    }

    /// `editText` made the mask's length, with every literal back in its
    /// place: what is shown when a program sets `EditText` directly.
    public String Restore(String editText)
    {
        var given = MaskCodePoints(editText);
        var shown = new List<char32>();
        for (nuint i = 0u; i < Length; i++)
        {
            if (IsLiteral(i) || i >= given.Count)
                shown.Add(GetClearChar(i));
            else
                shown.Add(given[i]);
        }
        return MaskJoin(shown);
    }

    static bool SetHolds(MaskSlot slot, char32 c)
    {
        uint value = (uint)c;
        if (value >= 128u)
            return false;
        if (value < 64u)
            return (slot.SetLow & (1ul << (int)value)) != 0u;
        return (slot.SetHigh & (1ul << (int)(value - 64u))) != 0u;
    }
}

/// The code points of `text`, one per entry.
List<char32> MaskCodePoints(String text)
{
    var all = new List<char32>();
    for (nuint at = 0u; at < text.ByteLength(); at = text.SkipCodePoint(at))
        all.Add(text.GetCodePointAt(at));
    return all;
}

/// `characters` as a String.
String MaskJoin(List<char32> characters)
{
    var made = new StringBuilder();
    for (nuint i = 0u; i < characters.Count; i++)
        made.AppendCodePoint(characters[i]);
    return made.ToText();
}

/// ASCII upper case; anything else as it is.
char32 MaskToUpper(char32 c) => c >= (char32)'a' && c <= (char32)'z' ? (char32)((uint)c - 32u) : c;

/// ASCII lower case; anything else as it is.
char32 MaskToLower(char32 c) => c >= (char32)'A' && c <= (char32)'Z' ? (char32)((uint)c + 32u) : c;

/// A text box whose text has a fixed shape, typed one position at a time.
///
/// ```
/// var phone = new MaskEdit(this);
/// phone.EditMask = "(999) 000-0000;0;_";
/// phone.Text = "5551234567";     // shows (555) 123-4567
/// if (!phone.IsValid) { ... }
/// ```
///
/// **Typing overwrites.** A character goes in the position at the caret, or
/// the next one that takes it, stepping over literals; the caret then moves
/// past it. Backspace and Delete put the blank back rather than closing the
/// gap, so nothing after the caret moves. A paste, a cut or anything else the
/// platform did to the text is taken as what it removed and what it put in,
/// and the put-in text is typed from where it went.
///
/// With no `EditMask` it is an ordinary text box.
#if FORMS_REFLECT
[Reflect]
#endif
public class MaskEdit : TextBox
{
    String _editMask;
    MaskPattern? _pattern;

    /// What the box showed last, for telling what the platform changed.
    String _shown;

    public MaskEdit(WindowedControl parent)
    {
        _editMask = "";
        _pattern = null;
        _shown = "";
        base(parent);
    }

    /// The mask, in the LCL's syntax; see `MaskPattern`. Empty for no mask.
    ///
    /// The text already there is laid into the new mask, as setting `Text`
    /// would lay it, so a form that sets `Text` before `EditMask` keeps it.
    /// The LCL empties the box instead.
    public String EditMask
    {
        get => _editMask;
        set
        {
            String kept = GetTextValue();
            _editMask = value;
            _pattern = value.IsEmpty ? null : MaskPattern.Parse(value);
            var pattern = _pattern;
            if (pattern != null)
                Show(pattern.Fit(kept), 0u);
            else
                base.SetTextValue(kept);
        }
    }

    /// The parsed mask, or null when there is none.
    public MaskPattern? Pattern => _pattern;

    public bool IsMasked => _pattern != null;

    /// What the box shows, blanks and literals and all. Setting it keeps the
    /// mask's shape: it is cut or padded to the mask's length, and every
    /// literal is put back.
    public String EditText
    {
        get => base.GetTextValue();
        set
        {
            var pattern = _pattern;
            if (pattern == null)
                base.SetTextValue(value);
            else
                Show(pattern.Restore(value), 0u);
        }
    }

    /// Whether the text fills the mask. True with no mask.
    public bool IsValid
    {
        get
        {
            var pattern = _pattern;
            return pattern == null || pattern.IsComplete(EditText);
        }
    }

    /// Answers whether the text fills the mask, and when it does not, puts
    /// the caret on the first position that is wrong.
    public bool ValidateEdit()
    {
        var pattern = _pattern;
        if (pattern == null)
            return true;
        nuint wrong = pattern.FindFirstMismatch(EditText);
        if (wrong == pattern.Length)
            return true;
        Entry.SetSelection((int)wrong, 1);
        return false;
    }

    /// With a mask, the text without blanks, and without the literals when
    /// the mask does not save them.
    protected override String GetTextValue()
    {
        var pattern = _pattern;
        String shown = base.GetTextValue();
        return pattern == null ? shown : pattern.Strip(shown);
    }

    /// With a mask, the text is laid into it; see `MaskPattern.Fit`.
    protected override void SetTextValue(String value)
    {
        var pattern = _pattern;
        if (pattern == null)
            base.SetTextValue(value);
        else
            Show(pattern.Fit(value), 0u);
    }

    /// Puts `edit` in the box with the caret at `caret`. A change the program
    /// made, so the platform does not report it back.
    void Show(String edit, nuint caret)
    {
        bool changed = base.GetTextValue() != edit;
        _shown = edit;
        StoredText = edit;
        if (changed)
            Entry.SetText(edit);
        Entry.SetSelection((int)caret, 0);
        if (changed)
            OnTextChanged();
    }

    /// Shows what the user's keystroke made, and reports it as theirs.
    void ShowTyped(String edit, nuint caret)
    {
        bool changed = base.GetTextValue() != edit;
        _shown = edit;
        StoredText = edit;
        if (changed)
            Entry.SetText(edit);
        Entry.SetSelection((int)caret, 0);
        if (changed)
            base.OnPlatformValueChanged();
    }

    protected override void OnKeyDown(KeyEventArgs args)
    {
        base.OnKeyDown(args);
        var pattern = _pattern;
        if (args.Handled || pattern == null)
            return;
        if (args.Key != Key.Backspace && args.Key != Key.Delete)
            return;

        args.Handled = true;
        if (ReadOnly)
            return;

        var shown = MaskCodePoints(EditText);
        var (start, length) = Entry.GetSelection();
        nuint from = ClampToMask(pattern, start);
        nuint caret = from;

        if (length > 0)
        {
            ClearRange(pattern, shown, from, ClampToMask(pattern, start + length));
        }
        else if (args.Key == Key.Backspace)
        {
            while (caret > 0u)
            {
                caret--;
                if (!pattern.IsLiteral(caret))
                {
                    shown[caret] = pattern.Blank;
                    break;
                }
            }
        }
        else
        {
            while (caret < pattern.Length && pattern.IsLiteral(caret))
                caret++;
            if (caret < pattern.Length)
                shown[caret] = pattern.Blank;
        }
        ShowTyped(MaskJoin(shown), caret);
    }

    protected override void OnKeyPress(KeyPressEventArgs args)
    {
        base.OnKeyPress(args);
        var pattern = _pattern;
        if (args.Handled || pattern == null)
            return;

        // Backspace, which Windows types as well as pressing; OnKeyDown has
        // done what it does.
        if (args.KeyChar == (char32)8)
        {
            args.Handled = true;
            return;
        }
        if (args.KeyChar < (char32)32 || args.KeyChar == (char32)127)
            return;

        args.Handled = true;
        if (ReadOnly)
            return;

        var shown = MaskCodePoints(EditText);
        var (start, length) = Entry.GetSelection();
        nuint from = ClampToMask(pattern, start);
        if (length > 0)
            ClearRange(pattern, shown, from, ClampToMask(pattern, start + length));

        var typed = new List<char32>();
        typed.Add(args.KeyChar);
        nuint caret = TypeInto(pattern, shown, from, typed);
        ShowTyped(MaskJoin(shown), caret);
    }

    /// The platform changed the text itself: a paste, a cut, a dropped
    /// string. What it removed is cleared and what it put in is typed from
    /// where it went, so the text keeps the mask's shape.
    public override void OnPlatformValueChanged()
    {
        var pattern = _pattern;
        if (pattern == null)
        {
            base.OnPlatformValueChanged();
            return;
        }

        String now = base.GetTextValue();
        if (now == _shown)
            return;

        var before = MaskCodePoints(_shown);
        var after = MaskCodePoints(now);
        if (before.Count != pattern.Length)
            before = MaskCodePoints(pattern.Restore(_shown));

        nuint prefix = 0u;
        while (prefix < before.Count && prefix < after.Count && before[prefix] == after[prefix])
            prefix++;
        nuint suffix = 0u;
        while (suffix < before.Count - prefix && suffix < after.Count - prefix &&
               before[before.Count - 1u - suffix] == after[after.Count - 1u - suffix])
            suffix++;

        var shown = before;
        ClearRange(pattern, shown, prefix, before.Count - suffix);

        var inserted = new List<char32>();
        for (nuint i = prefix; i < after.Count - suffix; i++)
            inserted.Add(after[i]);

        nuint caret = TypeInto(pattern, shown, prefix, inserted);
        ShowTyped(MaskJoin(shown), caret);
    }

    static nuint ClampToMask(MaskPattern pattern, int position)
    {
        if (position < 0)
            return 0u;
        return (nuint)position > pattern.Length ? pattern.Length : (nuint)position;
    }

    /// Puts the blank back in every open position of `[from, to)`.
    static void ClearRange(MaskPattern pattern, List<char32> shown, nuint from, nuint to)
    {
        for (nuint i = from; i < to && i < shown.Count; i++)
            shown[i] = pattern.GetClearChar(i);
    }

    /// Types `characters` into `shown` from `at`, and answers where the caret
    /// goes. Each goes in the first position from there that takes it,
    /// stepping over literals; one that matches the literal it meets steps
    /// over that literal instead, so pasting `(555) 123-4567` lands as typed.
    /// One no position takes is dropped.
    static nuint TypeInto(MaskPattern pattern, List<char32> shown, nuint at, List<char32> characters)
    {
        nuint position = at;
        for (nuint i = 0u; i < characters.Count; i++)
        {
            char32 c = characters[i];
            bool steppedOver = false;
            while (position < pattern.Length && pattern.IsLiteral(position))
            {
                if (pattern.GetSlot(position).Literal == c)
                {
                    position++;
                    steppedOver = true;
                    break;
                }
                position++;
            }
            if (steppedOver)
                continue;
            if (position >= pattern.Length)
                break;
            if (pattern.Accept(position, c) is Some taken)
            {
                shown[position] = taken.Value;
                position++;
            }
        }

        while (position < pattern.Length && pattern.IsLiteral(position))
            position++;
        return position;
    }
}
