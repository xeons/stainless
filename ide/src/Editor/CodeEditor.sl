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

// The editor: a `CustomControl` that draws a `Document` and edits it.
//
// **A fixed-width font is assumed, and that is a decision rather than a
// shortcut.** With one, a column is a multiplication and a click is a division,
// the caret needs no measuring at all, and painting a screen of text is one
// `DrawString` per token instead of one per token plus a measurement per token
// before it. With a proportional font every one of those becomes a measurement,
// and the measurement has to happen again for every line above the one being
// drawn. Every code editor in the world makes this trade, and the reason is
// this paragraph.
//
// What that leaves is a tab, which is not one cell wide. Tabs expand to the
// next multiple of `TabWidth`, and the two functions that know it -- `ColumnOf`
// and `OffsetOfColumn` -- are the only places in this file where a byte offset
// and a screen column are not the same number.
module Ide.Editor;

import Standard.Text;
import Standard.Collections;
import Forms;
import Forms.Drawing;
import Forms.Platform;
import Ide.Lang;

/// How far a tab reaches: to the next multiple of this.
const nuint TabWidth = 4u;

/// The column the right-hand rule is drawn at. 80, because that is what the
/// sources this is written to edit are wrapped to.
const nuint RightMargin = 80u;

/// A text editor with syntax highlighting.
public class CodeEditor : CustomControl {
    Document doc;
    Theme    palette;

    /// Where the caret is, and where a selection started.
    ///
    /// **A selection is two positions, not a flag and a range.** `anchor` is
    /// where the selection began and `caret` is where it has got to, so the two
    /// may be in either order -- which is what a drag upwards is -- and there
    /// is no selection exactly when they are equal. A range plus a direction
    /// flag says the same thing in a way that has to be kept consistent.
    Position caret;
    Position anchor;

    /// The column the caret would like to be in when it moves up or down.
    ///
    /// **Remembered across vertical movement, and reset by anything else.**
    /// Moving down from column 40 through a short line and on to a long one
    /// puts the caret back at 40, which is what every editor does and what
    /// nobody notices until it is missing.
    nuint wanted;
    bool  keepWanted;

    /// The first line shown, and the first column.
    nuint topLine;
    nuint leftColumn;

    ScrollBar down;
    ScrollBar across;

    /// The width of one character and the height of one line, measured once
    /// from the font. Zero until the first paint, which is the first time there
    /// is a `Graphics` to measure with.
    int cell;
    int lineHeight;
    /// The width of the line-number gutter, including the gap after it.
    int gutter;

    /// True while the mouse is down, so that moving it extends the selection.
    bool dragging;

    /// Whether the constructor has finished.
    ///
    /// **A control is live before it is built.** `CustomControl`'s constructor
    /// attaches the platform peer, attaching it pushes the bounds down, and the
    /// platform answers that with a resize -- which arrives at `OnResize` here
    /// while the fields below the `base(...)` call have not been assigned yet.
    /// The scroll bars in particular do not exist, and reaching one is a fault
    /// inside a window procedure, which Windows reports as a callback exception
    /// with no stack worth reading.
    ///
    /// So every handler that touches a field of this class checks this first.
    /// A `Control` cannot opt out of being notified before it is finished, and
    /// this is what a control does about it.
    bool ready;

    public CodeEditor(WindowedControl parent) {
        base(parent);
        doc = new Document();
        palette = Theme.Light();
        caret = Position.At(0u, 0u);
        anchor = caret;
        wanted = 0u;
        keepWanted = false;
        topLine = 0u;
        leftColumn = 0u;
        cell = 0;
        lineHeight = 0;
        gutter = 0;
        dragging = false;
        ready = false;

        Border = ControlBorder.Sunken;
        Font = new Font(MonospaceFamily(), 10);
        BackColor = palette.Background;
        Cursor = CursorKind.Text;

        down = new ScrollBar(this, true);
        down.ValueChanged += this.OnScrolledDown;
        across = new ScrollBar(this, false);
        across.ValueChanged += this.OnScrolledAcross;

        ready = true;
        Rescrolled();
    }

    /// The fixed-width font to use, by the name the platform knows it under.
    ///
    /// Consolas ships with Windows and DejaVu Sans Mono with essentially every
    /// desktop Linux; where neither is present the platform substitutes, and
    /// what it substitutes for a name it does not know is its default
    /// fixed-width face -- which is the right answer anyway.
    String MonospaceFamily() {
        #if WINDOWS
        return "Consolas";
        #else
        return "DejaVu Sans Mono";
        #endif
    }

    // ------------------------------------------------------------- the text

    /// The text being edited.
    ///
    /// Not `Text`: a `Control` already has one, meaning its caption, and a
    /// property that hid it would be two different things under one name in a
    /// type that has both.
    public Document Contents => doc;

    public Theme Palette {
        get => palette;
        set {
            palette = value;
            BackColor = palette.Background;
            Invalidate();
        }
    }

    /// Where the caret is.
    public Position CaretPosition => caret;

    /// Whether anything is selected.
    public bool HasSelection => !caret.SameAs(anchor);

    /// The selected text, or `""`.
    public String SelectedText {
        get {
            if (!HasSelection) { return ""; }
            return doc.TextBetween(anchor, caret);
        }
    }

    /// Replaces the document. The caret goes to the top and the view with it.
    public void SetDocument(Document replacement) {
        doc = replacement;
        caret = Position.At(0u, 0u);
        anchor = caret;
        topLine = 0u;
        leftColumn = 0u;
        Rescrolled();
        Invalidate();
        OnCaretMoved();
    }

    /// Puts the caret on a line, scrolls it into view, and selects nothing.
    ///
    /// What an error in the output pane does when it is double-clicked, and the
    /// reason this is public.
    public void GoTo(nuint row, nuint column) {
        nuint line = row >= doc.LineCount() ? doc.LineCount() - 1u : row;
        caret = Position.At(line, ClampColumn(line, column));
        anchor = caret;
        // Roughly a third of the way down, rather than at the very top: an
        // error is nearly always about the lines above it as well.
        nuint visible = (nuint)VisibleLines();
        topLine = line > visible / 3u ? line - visible / 3u : 0u;
        Rescrolled();
        ShowCaret();
        Invalidate();
        OnCaretMoved();
    }

    /// Raised whenever the caret moves, so a status bar can say where it is.
    public event EventHandler CaretMoved;
    protected virtual void OnCaretMoved() { CaretMoved(this); }

    /// Raised whenever the text changes.
    public event EventHandler Edited;
    protected virtual void OnEdited() { Edited(this); }

    // ----------------------------------------------------- columns and bytes

    /// The screen column a byte offset sits at, with tabs expanded.
    ///
    /// One of the two places in this file where a byte offset and a column
    /// differ. Walks the line, which is O(its length) -- and a line is short.
    public nuint ColumnOf(String line, nuint offset) {
        nuint column = 0u;
        nuint at = 0u;
        nuint size = line.ByteLength();
        while (at < offset && at < size) {
            if (line.ByteAt(at) == (byte)'\t') {
                column = column + (TabWidth - column % TabWidth);
                at += 1u;
            } else {
                column += 1u;
                at = line.NextCodePoint(at);
            }
        }
        return column;
    }

    /// The byte offset at a screen column: the other of the two.
    ///
    /// A column inside an expanded tab lands on the tab itself, and a column
    /// past the end of the line lands at the end of it, because a caret may not
    /// be somewhere there is no text.
    public nuint OffsetOfColumn(String line, nuint column) {
        nuint at = 0u;
        nuint seen = 0u;
        nuint size = line.ByteLength();
        while (at < size) {
            nuint next = seen;
            if (line.ByteAt(at) == (byte)'\t') {
                next = seen + (TabWidth - seen % TabWidth);
            } else {
                next = seen + 1u;
            }
            // A column that lands inside this character -- which a tab makes
            // possible, being several columns wide -- belongs to it.
            if (column < next) { return at; }
            seen = next;
            at = line.ByteAt(at) == (byte)'\t' ? at + 1u : line.NextCodePoint(at);
        }
        return size;
    }

    /// How wide a line is, in columns.
    nuint WidthOf(String line) { return ColumnOf(line, line.ByteLength()); }

    nuint ClampColumn(nuint row, nuint column) {
        nuint size = doc.LengthAt(row);
        return column > size ? size : column;
    }

    // --------------------------------------------------------------- layout

    /// How many whole lines fit.
    int VisibleLines() {
        if (lineHeight <= 0) { return 1; }
        int height = ClientBounds.Height - ScrollThickness();
        int fits = height / lineHeight;
        return fits < 1 ? 1 : fits;
    }

    /// How many whole columns fit beside the gutter.
    int VisibleColumns() {
        if (cell <= 0) { return 1; }
        int width = ClientBounds.Width - gutter - ScrollThickness();
        int fits = width / cell;
        return fits < 1 ? 1 : fits;
    }

    int ScrollThickness() { return 16; }

    /// Puts the scroll bars where they belong and tells them what they are
    /// scrolling. Called on every resize and after every edit.
    void Rescrolled() {
        if (!ready) { return; }
        var area = ClientBounds;
        int bar = ScrollThickness();

        down.SetBounds(area.Width - bar, 0, bar, area.Height - bar);
        across.SetBounds(0, area.Height - bar, area.Width - bar, bar);

        int lines = (int)doc.LineCount();
        int page = VisibleLines();
        down.Maximum = lines > page ? lines - 1 : 0;
        down.PageSize = page;
        down.Value = (int)topLine;

        // The widest line on screen, rather than in the file: scanning every
        // line of a large file on every keystroke to find the longest is the
        // one thing here that would be O(the file), and what it buys is a
        // horizontal thumb of exactly the right size.
        int widest = 0;
        nuint last = topLine + (nuint)page;
        if (last > doc.LineCount()) { last = doc.LineCount(); }
        for (nuint i = topLine; i < last; i += 1u) {
            int width = (int)WidthOf(doc.TextAt(i));
            if (width > widest) { widest = width; }
        }
        int columns = VisibleColumns();
        across.Maximum = widest > columns ? widest - 1 : 0;
        across.PageSize = columns;
        across.Value = (int)leftColumn;
    }

    protected override void OnResize() {
        if (ready) { Rescrolled(); }
        base.OnResize();
    }

    void OnScrolledDown(Control sender) {
        nuint to = (nuint)down.Value;
        if (to == topLine) { return; }
        topLine = to;
        Invalidate();
    }

    void OnScrolledAcross(Control sender) {
        nuint to = (nuint)across.Value;
        if (to == leftColumn) { return; }
        leftColumn = to;
        Invalidate();
    }

    /// Scrolls so the caret is on screen. Does nothing when it already is,
    /// which is the common case and the reason typing does not repaint the
    /// whole control.
    void ShowCaret() {
        nuint lines = (nuint)VisibleLines();
        if (caret.Row < topLine) { topLine = caret.Row; }
        else if (caret.Row >= topLine + lines) { topLine = caret.Row - lines + 1u; }

        nuint column = ColumnOf(doc.TextAt(caret.Row), caret.Column);
        nuint columns = (nuint)VisibleColumns();
        if (column < leftColumn) { leftColumn = column; }
        else if (column >= leftColumn + columns) { leftColumn = column - columns + 1u; }

        Rescrolled();
    }

    // -------------------------------------------------------------- drawing

    protected override void OnPaint(PaintEventArgs args) {
        if (!ready) { return; }
        var canvas = args.Graphics;

        // Measured once, from the font, the first time there is something to
        // measure with. `M` rather than a space: a space is the one character a
        // few fixed-width faces still report as narrower than the rest.
        if (cell <= 0) {
            var size = canvas.MeasureString("M", Font);
            cell = size.Width;
            lineHeight = size.Height;
            if (cell <= 0) { cell = 8; }
            if (lineHeight <= 0) { lineHeight = 14; }
            Rescrolled();
        }

        gutter = GutterWidth(canvas);

        var area = ClientBounds;
        canvas.Clear(palette.Background);
        canvas.FillRectangle(new Brush(palette.GutterBack),
                             Rectangle.Of(0, 0, gutter, area.Height));

        // The rule at column 80, drawn under the text rather than over it.
        int rule = gutter + (int)(RightMargin - leftColumn) * cell;
        if (rule > gutter && rule < area.Width) {
            canvas.DrawLine(new Pen(palette.Margin), rule, 0, rule, area.Height);
        }

        nuint lines = doc.LineCount();
        nuint last = topLine + (nuint)VisibleLines() + 1u;
        if (last > lines) { last = lines; }

        for (nuint row = topLine; row < last; row += 1u) {
            int y = (int)(row - topLine) * lineHeight;
            PaintLine(canvas, row, y, area.Width);
        }

        PlaceCaret();
    }

    /// How wide the gutter is: room for the largest line number, and a gap.
    int GutterWidth(Graphics canvas) {
        nuint count = doc.LineCount();
        int digits = 1;
        while (count >= 10u) { count = count / 10u; digits += 1; }
        if (digits < 3) { digits = 3; }
        return (digits + 2) * cell;
    }

    void PaintLine(Graphics canvas, nuint row, int y, int width) {
        var line = doc.LineAt(row);
        bool current = row == caret.Row;

        if (current && !HasSelection) {
            canvas.FillRectangle(new Brush(palette.CurrentLine),
                                 Rectangle.Of(gutter, y, width - gutter, lineHeight));
        }

        PaintSelection(canvas, row, y, width);

        // The number, right-aligned in the gutter.
        String number = Standard.Text.FromInteger(row + 1u);
        int numberX = gutter - cell - (int)number.ByteLength() * cell;
        canvas.DrawString(number, Font,
                          current ? palette.GutterCurrent : palette.GutterText,
                          numberX, y);

        // One `DrawString` per token, at the column its first byte sits in.
        // Nothing is measured: the column is a count and the x is a
        // multiplication, which is the whole reason for the fixed-width font.
        foreach (var token in line.Tokens) {
            if (token.Kind == TokenKind.Whitespace) { continue; }

            nuint column = ColumnOf(line.Text, token.Start);
            if (column + token.Length < leftColumn) { continue; }

            int x = gutter + (int)(column - leftColumn) * cell;
            if (x > width) { break; }

            String piece = line.Text.Substring(token.Start, token.Length);
            canvas.DrawString(piece, Font, palette.ColorFor(token.Kind), x, y);
        }
    }

    /// The highlight behind whatever of this line is selected.
    void PaintSelection(Graphics canvas, nuint row, int y, int width) {
        if (!HasSelection) { return; }

        var start = anchor;
        var end = caret;
        if (end.Before(start)) { start = caret; end = anchor; }
        if (row < start.Row || row > end.Row) { return; }

        String text = doc.TextAt(row);
        nuint from = row == start.Row ? ColumnOf(text, start.Column) : 0u;
        nuint to = row == end.Row ? ColumnOf(text, end.Column) : WidthOf(text) + 1u;

        // A line wholly inside the selection is highlighted one column past its
        // end, which is what shows that the line break is selected too.
        if (to <= from) { return; }
        if (from < leftColumn) { from = leftColumn; }

        int x = gutter + (int)(from - leftColumn) * cell;
        int span = (int)(to - from) * cell;
        if (x + span > width) { span = width - x; }
        if (span <= 0) { return; }

        canvas.FillRectangle(new Brush(palette.Selection),
                             Rectangle.Of(x, y, span, lineHeight));
    }

    /// Puts the platform's caret where the text caret is, or takes it away when
    /// it has scrolled off.
    void PlaceCaret() {
        if (caret.Row < topLine || caret.Row >= topLine + (nuint)VisibleLines() + 1u) {
            Caret = Rectangle.Empty;
            return;
        }
        nuint column = ColumnOf(doc.TextAt(caret.Row), caret.Column);
        if (column < leftColumn) {
            Caret = Rectangle.Empty;
            return;
        }
        int x = gutter + (int)(column - leftColumn) * cell;
        int y = (int)(caret.Row - topLine) * lineHeight;
        Caret = Rectangle.Of(x, y, 2, lineHeight);
    }

    // ------------------------------------------------------------ the mouse

    protected override void OnMouseDown(MouseEventArgs args) {
        if (!ready) { return; }
        Focus();
        var hit = PositionAt(args.X, args.Y);
        caret = hit;
        if (!args.Modifiers.HasFlag(ModifierKeys.Shift)) { anchor = hit; }
        dragging = true;
        CaptureMouse(true);
        keepWanted = false;
        ShowCaret();
        Invalidate();
        OnCaretMoved();
        base.OnMouseDown(args);
    }

    protected override void OnMouseMove(MouseEventArgs args) {
        if (!ready) { return; }
        if (dragging) {
            caret = PositionAt(args.X, args.Y);
            ShowCaret();
            Invalidate();
            OnCaretMoved();
        }
        base.OnMouseMove(args);
    }

    protected override void OnMouseUp(MouseEventArgs args) {
        if (!ready) { return; }
        if (dragging) {
            dragging = false;
            CaptureMouse(false);
        }
        base.OnMouseUp(args);
    }

    protected override void OnMouseWheel(MouseEventArgs args) {
        if (!ready) { return; }
        // Three lines a notch, as every platform's own setting defaults to.
        int notches = args.Delta / 120;
        if (notches == 0) { notches = args.Delta > 0 ? 1 : -1; }
        int to = (int)topLine - notches * 3;
        if (to < 0) { to = 0; }
        int highest = (int)doc.LineCount() - 1;
        if (to > highest) { to = highest; }
        if ((nuint)to == topLine) { return; }
        topLine = (nuint)to;
        Rescrolled();
        Invalidate();
        base.OnMouseWheel(args);
    }

    /// What position a point in the control is over.
    Position PositionAt(int x, int y) {
        if (lineHeight <= 0 || cell <= 0) { return Position.At(0u, 0u); }

        int row = y / lineHeight + (int)topLine;
        if (row < 0) { row = 0; }
        nuint highest = doc.LineCount() - 1u;
        nuint line = (nuint)row > highest ? highest : (nuint)row;

        int column = (x - gutter) / cell + (int)leftColumn;
        if (column < 0) { column = 0; }
        return Position.At(line, OffsetOfColumn(doc.TextAt(line), (nuint)column));
    }

    // --------------------------------------------------------- the keyboard

    protected override void OnKeyDown(KeyEventArgs args) {
        if (!ready) { return; }
        bool shift = args.Shift;
        bool control = args.Control;
        bool moved = true;

        if (args.Key == Key.Left)          { MoveLeft(shift, control); }
        else if (args.Key == Key.Right)    { MoveRight(shift, control); }
        else if (args.Key == Key.Up)       { MoveVertically(-1, shift); }
        else if (args.Key == Key.Down)     { MoveVertically(1, shift); }
        else if (args.Key == Key.PageUp)   { MoveVertically(-VisibleLines(), shift); }
        else if (args.Key == Key.PageDown) { MoveVertically(VisibleLines(), shift); }
        else if (args.Key == Key.Home)     { MoveHome(shift, control); }
        else if (args.Key == Key.End)      { MoveEnd(shift, control); }
        else if (args.Key == Key.A && control) {
            anchor = Position.At(0u, 0u);
            nuint end = doc.LineCount() - 1u;
            caret = Position.At(end, doc.LengthAt(end));
        }
        else if (args.Key == Key.Backspace) { DeleteBack(); moved = false; }
        else if (args.Key == Key.Delete)    { DeleteForward(); moved = false; }
        else if (args.Key == Key.Enter)     { Type("\n"); moved = false; }
        else if (args.Key == Key.Tab)       { Indent(shift); moved = false; }
        else { moved = false; base.OnKeyDown(args); return; }

        if (moved) {
            ShowCaret();
            Invalidate();
            OnCaretMoved();
        }
        base.OnKeyDown(args);
    }

    protected override void OnKeyPress(KeyPressEventArgs args) {
        if (!ready) { return; }
        // Everything below a space is a control code, and each one that means
        // something has already been dealt with as a key.
        if (args.KeyChar >= ' ') { Type(Standard.Text.FromChar((char32)args.KeyChar)); }
        base.OnKeyPress(args);
    }

    // ------------------------------------------------------------- movement

    /// Collapses the selection unless the shift key is holding it open.
    void Settle(bool shift) {
        if (!shift) { anchor = caret; }
        if (!keepWanted) { wanted = ColumnOf(doc.TextAt(caret.Row), caret.Column); }
        keepWanted = false;
    }

    void MoveLeft(bool shift, bool word) {
        // An unheld selection collapses to its near end rather than moving,
        // which is what every editor does and what makes Left after a drag
        // predictable.
        if (!shift && HasSelection) {
            caret = anchor.Before(caret) ? anchor : caret;
            anchor = caret;
            Settle(false);
            return;
        }

        if (caret.Column > 0u) {
            String line = doc.TextAt(caret.Row);
            caret = Position.At(caret.Row,
                                word ? WordLeft(line, caret.Column) : StepLeft(line, caret.Column));
        } else if (caret.Row > 0u) {
            caret = Position.At(caret.Row - 1u, doc.LengthAt(caret.Row - 1u));
        }
        Settle(shift);
    }

    void MoveRight(bool shift, bool word) {
        if (!shift && HasSelection) {
            caret = anchor.Before(caret) ? caret : anchor;
            anchor = caret;
            Settle(false);
            return;
        }

        String line = doc.TextAt(caret.Row);
        if (caret.Column < line.ByteLength()) {
            caret = Position.At(caret.Row,
                                word ? WordRight(line, caret.Column) : line.NextCodePoint(caret.Column));
        } else if (caret.Row + 1u < doc.LineCount()) {
            caret = Position.At(caret.Row + 1u, 0u);
        }
        Settle(shift);
    }

    void MoveVertically(int by, bool shift) {
        int row = (int)caret.Row + by;
        if (row < 0) { row = 0; }
        int highest = (int)doc.LineCount() - 1;
        if (row > highest) { row = highest; }

        // The column the caret would like to be in is remembered across a run
        // of vertical movements, so a short line in the middle does not drag it
        // permanently left.
        caret = Position.At((nuint)row, OffsetOfColumn(doc.TextAt((nuint)row), wanted));
        keepWanted = true;
        Settle(shift);
    }

    /// Home goes to the first non-blank of the line, and to column zero when it
    /// is already there. The one movement whose two meanings are both wanted.
    void MoveHome(bool shift, bool document) {
        if (document) { caret = Position.At(0u, 0u); Settle(shift); return; }

        String line = doc.TextAt(caret.Row);
        nuint first = 0u;
        while (first < line.ByteLength()) {
            byte c = line.ByteAt(first);
            if (c != (byte)' ' && c != (byte)'\t') { break; }
            first += 1u;
        }
        caret = Position.At(caret.Row, caret.Column == first ? 0u : first);
        Settle(shift);
    }

    void MoveEnd(bool shift, bool document) {
        if (document) {
            nuint end = doc.LineCount() - 1u;
            caret = Position.At(end, doc.LengthAt(end));
        } else {
            caret = Position.At(caret.Row, doc.LengthAt(caret.Row));
        }
        Settle(shift);
    }

    nuint StepLeft(String line, nuint offset) {
        nuint at = 0u;
        nuint last = 0u;
        while (at < offset) { last = at; at = line.NextCodePoint(at); }
        return last;
    }

    /// The start of the word to the left: past any run of spaces, then past the
    /// run of word bytes before that.
    nuint WordLeft(String line, nuint offset) {
        nuint at = StepLeft(line, offset);
        while (at > 0u && IsSpace(line.ByteAt(at))) { at = StepLeft(line, at); }
        if (at == 0u) { return 0u; }
        if (!IsWord(line.ByteAt(at))) { return at; }
        while (at > 0u) {
            nuint back = StepLeft(line, at);
            if (!IsWord(line.ByteAt(back))) { return at; }
            at = back;
        }
        return 0u;
    }

    nuint WordRight(String line, nuint offset) {
        nuint size = line.ByteLength();
        nuint at = offset;
        if (at < size && IsWord(line.ByteAt(at))) {
            while (at < size && IsWord(line.ByteAt(at))) { at = line.NextCodePoint(at); }
        } else if (at < size) {
            at = line.NextCodePoint(at);
        }
        while (at < size && IsSpace(line.ByteAt(at))) { at = line.NextCodePoint(at); }
        return at;
    }

    bool IsSpace(byte c) { return c == (byte)' ' || c == (byte)'\t'; }

    bool IsWord(byte c) {
        return (c >= (byte)'a' && c <= (byte)'z')
            || (c >= (byte)'A' && c <= (byte)'Z')
            || (c >= (byte)'0' && c <= (byte)'9')
            || c == (byte)'_' || c >= 0x80u;
    }

    // -------------------------------------------------------------- editing

    /// Puts text in, replacing the selection if there is one.
    public void Type(String text) {
        if (HasSelection) { caret = doc.Delete(anchor, caret); }
        caret = doc.Insert(caret, text);
        anchor = caret;
        AfterEdit();
    }

    void DeleteBack() {
        if (HasSelection) {
            caret = doc.Delete(anchor, caret);
        } else if (caret.Column > 0u) {
            nuint back = StepLeft(doc.TextAt(caret.Row), caret.Column);
            caret = doc.Delete(Position.At(caret.Row, back), caret);
        } else if (caret.Row > 0u) {
            var joinAt = Position.At(caret.Row - 1u, doc.LengthAt(caret.Row - 1u));
            caret = doc.Delete(joinAt, caret);
        } else {
            return;
        }
        anchor = caret;
        AfterEdit();
    }

    void DeleteForward() {
        if (HasSelection) {
            caret = doc.Delete(anchor, caret);
        } else if (caret.Column < doc.LengthAt(caret.Row)) {
            nuint next = doc.TextAt(caret.Row).NextCodePoint(caret.Column);
            caret = doc.Delete(caret, Position.At(caret.Row, next));
        } else if (caret.Row + 1u < doc.LineCount()) {
            caret = doc.Delete(caret, Position.At(caret.Row + 1u, 0u));
        } else {
            return;
        }
        anchor = caret;
        AfterEdit();
    }

    /// Tab, which means two different things and the selection says which.
    ///
    /// With nothing selected it inserts spaces to the next tab stop -- spaces
    /// rather than a tab, because that is what the sources this edits use, and
    /// an editor that inserted the other kind would make every file it touched
    /// inconsistent with itself.
    void Indent(bool back) {
        if (!HasSelection && !back) {
            nuint column = ColumnOf(doc.TextAt(caret.Row), caret.Column);
            nuint spaces = TabWidth - column % TabWidth;
            Type(" ".Repeat(spaces));
            return;
        }

        var start = anchor;
        var end = caret;
        if (end.Before(start)) { start = caret; end = anchor; }

        for (nuint row = start.Row; row <= end.Row; row += 1u) {
            String line = doc.TextAt(row);
            if (back) {
                nuint strip = 0u;
                while (strip < TabWidth && strip < line.ByteLength()
                       && line.ByteAt(strip) == (byte)' ') {
                    strip += 1u;
                }
                if (strip > 0u) {
                    doc.Delete(Position.At(row, 0u), Position.At(row, strip));
                }
            } else if (line.ByteLength() > 0u) {
                doc.Insert(Position.At(row, 0u), " ".Repeat(TabWidth));
            }
        }

        // The selection keeps covering the same lines, whole.
        anchor = Position.At(start.Row, 0u);
        caret = Position.At(end.Row, doc.LengthAt(end.Row));
        AfterEdit();
    }

    void AfterEdit() {
        keepWanted = false;
        wanted = ColumnOf(doc.TextAt(caret.Row), caret.Column);
        Rescrolled();
        ShowCaret();
        Invalidate();
        OnCaretMoved();
        OnEdited();
    }
}
