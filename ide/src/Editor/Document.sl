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
public class Document
{
    List<Line> _lines;
    Scanner _scanner;
    String _location;
    bool _edited;
    LineEnding _endings;

    public Document()
    {
        _lines = new List<Line>();
        _scanner = new Scanner();
        _location = "";
        _edited = false;
        _endings = LineEnding.Lf;
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
    public bool Edited => _edited;

    public LineEnding Endings => _endings;

    /// Says it has been saved, without writing anything. For a caller that did
    /// the writing itself.
    public void MarkSaved() => _edited = false;

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
            return Position.At(row, column + parts[0].ByteLength());
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
        return Position.At(landed, parts[parts.Length - 1u].ByteLength());
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

        String head = _lines[firstRow].Text.Substring(0u, firstColumn);
        String tail = _lines[lastRow].Text.Substring(lastColumn);

        // The lines strictly between the two go, and so does the last one --
        // whose remainder has just been joined on to the first.
        for (nuint i = lastRow; i > firstRow; i--)
            _lines.RemoveAt(i);
        Replace(firstRow, head + tail);

        Rescan(firstRow);
        _edited = true;
        return Position.At(firstRow, firstColumn);
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
