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

// The text being edited: a list of lines, each with the tokens it lexed to.
//
// **A list of lines, and not a gap buffer or a rope.** The classic argument for
// either is that inserting into the middle of one enormous string is O(n), and
// it is -- but a *line* is not enormous. Editing a line rebuilds that line,
// which is a few dozen bytes copied, and inserting a line moves pointers in a
// list rather than text. What that costs is a file kept as many small strings
// rather than one big one, and what it buys is that every position in this file
// is a row and a column, with no translation anywhere and no structure to keep
// in step with the text. A rope earns its keep when a single line can be
// megabytes; source code is not that, and the day it is, this is the file to
// change and nothing above it.
//
// **Each line remembers what it lexed to**, so painting never lexes. An edit
// rescans from the line that changed and stops at the first line whose incoming
// state is what it already was -- which for anything but opening a block
// comment is the very next line.
module Ide.Editor;

import Standard.Text;
import Standard.Collections;
import Standard.IO;
import Standard.File;
import Ide.Lang;

// ==================================================================== a line

/// One line of the file, and what it lexed to.
public class Line
{
    /// The text, with no line ending on it. Line endings belong to the file
    /// rather than to a line, and are put back on when it is saved.
    public String Text;
    /// What `Text` lexed to, covering every byte of it exactly.
    public List<Token> Tokens;
    /// What this line leaves open for the next one.
    public ScanState After;

    /// Whether it has ever been lexed.
    ///
    /// **What stops `Rescan` from stopping too early.** Its rule is that an
    /// unchanged outgoing state means nothing below has changed -- which is
    /// true only of a line that already had a state. A line that has just been
    /// inserted has `Normal` because it was born with it, not because anything
    /// lexed it, and a rescan that took that for agreement would leave every
    /// line of a pasted block with no tokens at all.
    public bool Scanned;

    public Line(String text)
    {
        Text = text;
        Tokens = new List<Token>();
        After = ScanState.Normal;
        Scanned = false;
    }
}

/// A place in the file: which line, and how many bytes into it.
///
/// **Bytes, not characters**, because that is what a `String` position is here
/// and converting at every use would be the bug that never stops arriving. The
/// editor turns one of these into a column for drawing and back again for a
/// click, and those two functions are the only places the difference exists.
public struct Position
{
    public nuint Row;
    public nuint Column;

    public static Position At(nuint row, nuint column)
    {
        Position p;
        p.Row = row;
        p.Column = column;
        return p;
    }

    public bool Before(Position other)
    {
        if (Row != other.Row)
            return Row < other.Row;
        return Column < other.Column;
    }

    public bool SameAs(Position other)
    {
        return Row == other.Row && Column == other.Column;
    }
}

/// Which line endings the file had, so that saving it writes back what was
/// read rather than imposing a house style on somebody else's file.
public enum LineEnding
{
    /// `\n`, and what a new file gets.
    Lf,
    /// `\r\n`.
    CrLf,
}

// ================================================================= document

/// The lines, the lexer, and what has changed.
/// One edit, and what it would take to put it back.
///
/// **Both directions from one record.** An insertion knows where it began,
/// where it ended and what went in -- which is enough to take it out again --
/// and a deletion knows the same three things, which is enough to put it back.
/// So undo and redo are the same structure read two ways rather than two
/// stacks of different things.
public struct Edit
{
    /// True for an insertion, false for a deletion.
    public bool Inserted;

    /// Where it began, and where it ended. For a deletion these are the two
    /// ends of what was taken out, measured before it went.
    public Position From;
    public Position To;

    /// What was put in or taken out.
    public String Text;

    /// Where the caret was before the edit, so undoing puts it back where the
    /// person was rather than where the machine finished.
    public Position Caret;
}

public class Document
{
    List<Line> _lines;
    Scanner _scanner;
    String _location;
    bool _edited;
    LineEnding _endings;

    /// What has been done, and what has been undone.
    ///
    /// Both hold `Edit`s; which list one is in says which way it is about to be
    /// read. Redo is cleared by any new edit, which is what every editor does
    /// and what stops a redo applying to text it was never recorded against.
    List<Edit> _done;
    List<Edit> _undone;

    /// Set while an undo or a redo is being applied, so the edit it makes is
    /// not itself recorded. Without it the first undo pushes its own inverse
    /// and the second undoes the undo, for ever.
    bool _applying;

    /// How many edits had been done when the file was last read or written.
    ///
    /// **`_edited` is derived from this rather than latched**, so undoing back
    /// to the last save clears the asterisk -- which is what a person means by
    /// "I put it back". A latched flag says a file is modified after it has
    /// been returned to exactly what is on disk.
    ///
    /// -1 when the saved state is no longer reachable: a save, then an undo
    /// past it, then a new edit throws away the redo that led back.
    long _savedAt;

    public Document()
    {
        _lines = new List<Line>();
        _scanner = new Scanner();
        _location = "";
        _edited = false;
        _endings = LineEnding.Lf;
        _done = new List<Edit>();
        _undone = new List<Edit>();
        _applying = false;
        _savedAt = 0;
        _lines.Add(new Line(""));
        Rescan(0u);
    }

    /// How many lines there are. Never zero: a file with nothing in it is one
    /// empty line, because a caret has to be somewhere.
    public nuint LineCount => _lines.Count;

    public Line LineAt(nuint row) => _lines[row];

    public String TextAt(nuint row) => _lines[row].Text;

    public nuint LengthAt(nuint row) => _lines[row].Text.ByteLength();

    /// Where the file came from, or `""` for one that has never been saved.
    public String Location
    {
        get => _location;
        set => _location = value;
    }

    /// Whether it has been changed since it was last read or written.
    ///
    /// Answered from the undo stack rather than from a flag, so undoing back to
    /// the last save says the file is unmodified again.
    public bool Edited => _savedAt < 0 || (nuint)_savedAt != _done.Count;

    /// Whether there is anything to undo, or to redo.
    public bool CanUndo => !_done.IsEmpty();
    public bool CanRedo => !_undone.IsEmpty();

    public LineEnding Endings => _endings;

    /// Says it has been saved, without writing anything. For a caller that did
    /// the writing itself.
    public void MarkSaved()
    {
        _edited = false;
        _savedAt = (long)_done.Count;
    }

    // ----------------------------------------------------------- the file

    /// Replaces everything with `text`, split into lines.
    ///
    /// The line endings are noticed rather than normalised: a file that arrives
    /// with `\r\n` is written back with `\r\n`, because an editor that quietly
    /// rewrote every line ending of every file it opened would make a one-line
    /// change look like a whole-file change to everything downstream of it.
    public void SetText(String text)
    {
        _lines.Clear();
        _endings = text.Contains("\r\n") ? LineEnding.CrLf : LineEnding.Lf;

        var parts = text.Replace("\r\n", "\n").Split("\n");
        foreach (var part in parts)
            _lines.Add(new Line(part));
        if (_lines.Count == 0u)
            _lines.Add(new Line(""));

        Rescan(0u);
        _edited = false;
    }

    /// Everything, as one string, with the line endings it came with.
    public String GetText()
    {
        String separator = _endings == LineEnding.CrLf ? "\r\n" : "\n";
        var builder = new StringBuilder();
        for (nuint i = 0u; i < _lines.Count; i++)
        {
            if (i > 0u)
                builder.Append(separator);
            builder.Append(_lines[i].Text);
        }
        return builder.ToText();
    }

    /// Reads a file in. False when it could not be read, and the document is
    /// left alone.
    public bool Load(String path)
    {
        var read = File.ReadAllText(path);
        if (!read.Ok)
            return false;
        SetText(read.Value);
        _location = path;
        return true;
    }

    /// Writes it out. False when it could not be written, and the document
    /// still counts as edited.
    public bool Save(String path)
    {
        var error = File.WriteAllText(path, GetText());
        if (error != IOError.None)
            return false;
        _location = path;
        _edited = false;
        return true;
    }

    // ------------------------------------------------------------- editing

    /// Puts `text` in at `at`, and answers where the caret ends up.
    ///
    /// `text` may contain newlines, which is what makes this the whole of
    /// insertion: typing a character, pasting a paragraph and pressing Return
    /// are all this call with a different string.
    public Position Insert(Position at, String text)
    {
        nuint row = Clamp(at.Row, _lines.Count - 1u);
        nuint column = Clamp(at.Column, _lines[row].Text.ByteLength());

        String existing = _lines[row].Text;
        String before = existing.Substring(0u, column);
        String after = existing.Substring(column);

        var parts = text.Replace("\r\n", "\n").Split("\n");
        if (parts.Length == 1u)
        {
            Replace(row, before + parts[0] + after);
            Rescan(row);
            _edited = true;

            var landedHere = Position.At(row, column + parts[0].ByteLength());
            Record(true, Position.At(row, column), landedHere, text);
            return landedHere;
        }

        // Several lines: the first joins what was before the caret, the last
        // joins what was after it, and the rest go in between.
        Replace(row, before + parts[0]);
        nuint landed = row;
        for (nuint i = 1u; i < parts.Length; i++)
        {
            landed = row + i;
            String piece = parts[i];
            if (i == parts.Length - 1u)
                piece = piece + after;
            _lines.Insert(landed, new Line(piece));
        }

        Rescan(row);
        _edited = true;

        var ended = Position.At(landed, parts[parts.Length - 1u].ByteLength());
        Record(true, Position.At(row, column), ended, text);
        return ended;
    }

    /// Takes out everything between two positions, and answers where the caret
    /// ends up -- which is always the earlier of the two.
    public Position Delete(Position from, Position to)
    {
        var start = from;
        var end = to;
        if (end.Before(start))
        {
            start = to;
            end = from;
        }

        nuint firstRow = Clamp(start.Row, _lines.Count - 1u);
        nuint lastRow = Clamp(end.Row, _lines.Count - 1u);
        nuint firstColumn = Clamp(start.Column, _lines[firstRow].Text.ByteLength());
        nuint lastColumn = Clamp(end.Column, _lines[lastRow].Text.ByteLength());

        // Read before anything is removed: this is what an undo puts back, and
        // afterwards there is nothing left to read it from.
        var startAt = Position.At(firstRow, firstColumn);
        var endAt = Position.At(lastRow, lastColumn);
        String removed = _applying ? "" : TextBetween(startAt, endAt);

        String head = _lines[firstRow].Text.Substring(0u, firstColumn);
        String tail = _lines[lastRow].Text.Substring(lastColumn);

        // The lines strictly between the two go, and so does the last one --
        // whose remainder has just been joined on to the first.
        for (nuint i = lastRow; i > firstRow; i--)
            _lines.RemoveAt(i);
        Replace(firstRow, head + tail);

        Rescan(firstRow);
        _edited = true;

        Record(false, startAt, endAt, removed);
        return Position.At(firstRow, firstColumn);
    }

    // ------------------------------------------------------------ undoing

    /// Remembers an edit, merging it into the one before where that reads as
    /// one action.
    ///
    /// **Typing a word is one undo, not seven.** Every character is its own
    /// call to `Insert`, and an undo stack that kept them apart would make
    /// undo useless for the thing it is used for most. Two insertions merge
    /// when the second starts exactly where the first ended and neither
    /// carries a newline -- so typing runs together, and pressing Return,
    /// clicking elsewhere or pasting a paragraph each start a new one.
    ///
    /// Backspacing runs together the same way, by the opposite test: the
    /// second deletion ends exactly where the first began.
    void Record(bool inserted, Position from, Position to, String text)
    {
        if (_applying)
            return;

        // Any new edit makes a redo meaningless: what was undone was recorded
        // against text that no longer exists.
        _undone.Clear();

        // A save the undo stack can no longer reach: the file was saved, undone
        // past that point, and then edited, so the path back is gone.
        if (_savedAt > (long)_done.Count)
            _savedAt = -1;

        if (Merge(inserted, from, to, text))
            return;

        Edit made;
        made.Inserted = inserted;
        made.From = from;
        made.To = to;
        made.Text = text;
        made.Caret = from;
        _done.Add(made);
    }

    /// Extends the last edit rather than adding one, where the two read as a
    /// single action. False when they do not.
    bool Merge(bool inserted, Position from, Position to, String text)
    {
        if (_done.IsEmpty() || text.Contains("\n") || text.Contains("\r"))
            return false;

        var last = _done[_done.Count - 1u];
        if (last.Inserted != inserted || last.Text.Contains("\n"))
            return false;

        if (inserted)
        {
            // Typed on: this insertion begins where the last one ended.
            if (!last.To.SameAs(from))
                return false;

            last.Text = last.Text + text;
            last.To = to;
            _done[_done.Count - 1u] = last;
            return true;
        }

        // Backspaced on: this deletion ends where the last one began, so the
        // text belongs in front of what is already recorded.
        if (!last.From.SameAs(to))
            return false;

        last.Text = text + last.Text;
        last.From = from;
        _done[_done.Count - 1u] = last;
        return true;
    }

    /// Puts the last edit back, and answers where the caret goes.
    ///
    /// Nothing when there is nothing to undo, which is what a caller checks
    /// rather than `CanUndo` and then this -- the answer says both.
    public Optional<Position> Undo()
    {
        if (_done.IsEmpty())
            return None;

        var last = _done[_done.Count - 1u];
        _done.RemoveAt(_done.Count - 1u);
        _undone.Add(last);

        return Apply(!last.Inserted, last);
    }

    /// Does the last undone edit again.
    public Optional<Position> Redo()
    {
        if (_undone.IsEmpty())
            return None;

        var last = _undone[_undone.Count - 1u];
        _undone.RemoveAt(_undone.Count - 1u);
        _done.Add(last);

        return Apply(last.Inserted, last);
    }

    /// Applies an edit in one direction or the other.
    ///
    /// `_applying` is what keeps this from recording itself: `Insert` and
    /// `Delete` are the only way to change the text, and they are the same two
    /// calls whether a person or an undo is asking.
    Optional<Position> Apply(bool insert, Edit edit)
    {
        _applying = true;

        Position caret;
        if (insert)
            caret = Insert(edit.From, edit.Text);
        else
            caret = Delete(edit.From, edit.To);

        _applying = false;
        return Some(caret);
    }

    /// Everything between two positions, as a string.
    public String TextBetween(Position from, Position to)
    {
        var start = from;
        var end = to;
        if (end.Before(start))
        {
            start = to;
            end = from;
        }

        nuint firstRow = Clamp(start.Row, _lines.Count - 1u);
        nuint lastRow = Clamp(end.Row, _lines.Count - 1u);
        nuint firstColumn = Clamp(start.Column, _lines[firstRow].Text.ByteLength());
        nuint lastColumn = Clamp(end.Column, _lines[lastRow].Text.ByteLength());

        if (firstRow == lastRow)
        {
            return _lines[firstRow].Text.Substring(firstColumn, lastColumn - firstColumn);
        }

        String separator = _endings == LineEnding.CrLf ? "\r\n" : "\n";
        var builder = new StringBuilder();
        builder.Append(_lines[firstRow].Text.Substring(firstColumn));
        for (nuint i = firstRow + 1u; i < lastRow; i++)
        {
            builder.Append(separator);
            builder.Append(_lines[i].Text);
        }
        builder.Append(separator);
        builder.Append(_lines[lastRow].Text.Substring(0u, lastColumn));
        return builder.ToText();
    }

    /// Changes a line's text, and says its tokens no longer describe it.
    ///
    /// Every caller rescans immediately afterwards; clearing the flag here as
    /// well is what makes that a rule the type keeps rather than one every
    /// caller has to remember.
    void Replace(nuint row, String text)
    {
        var line = _lines[row];
        line.Text = text;
        line.Scanned = false;
    }

    // ------------------------------------------------------------ scanning

    /// Lexes from `row` down, and stops at the first line whose incoming state
    /// is what it already was.
    ///
    /// **Which is nearly always the next one.** The state between two lines is
    /// whether a block comment is open, so an ordinary edit rescans exactly one
    /// line. Typing `/*` at the top of a file rescans all of it, once, and
    /// typing the `*/` rescans it back -- which is the worst case and is the
    /// one people notice least, because they are looking at what they typed.
    public void Rescan(nuint row)
    {
        nuint from = Clamp(row, _lines.Count - 1u);
        var state = from == 0u ? ScanState.Normal : _lines[from - 1u].After;

        for (nuint i = from; i < _lines.Count; i++)
        {
            var line = _lines[i];
            var was = line.After;
            bool knew = line.Scanned;
            line.After = _scanner.ScanLine(line.Text, state, line.Tokens);
            line.Scanned = true;

            // The line below this one is affected only through the state, so an
            // unchanged state means nothing below has changed. Not on the line
            // the edit was on, which has to be rescanned whatever its state,
            // and not on a line that had no state to be unchanged from.
            if (i > from && knew && line.After == was)
                return;
            state = line.After;
        }
    }

    nuint Clamp(nuint value, nuint highest)
    {
        return value > highest ? highest : value;
    }
}
