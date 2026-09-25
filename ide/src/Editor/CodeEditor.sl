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
// next multiple of `TabWidth`, and the two functions that know it --
// `GetColumnOfOffset` and `GetOffsetOfColumn` -- are the only places in this
// file where a byte offset and a screen column are not the same number.
module Ide.Editor;

import Standard.Text;
import Standard.Collections;
import Forms;
import Forms.Drawing;
import Forms.Platform;
import Ide.Lang;

/// How far a tab reaches: to the next multiple of this.
const nuint TabWidth = 4u;

/// How wide the breakpoint margin is, in character cells.
///
/// Cells rather than pixels, so it scales with the text size.
const int MarginCells = 2;

/// What the margin draws beside one line.
public enum LineMark
{
    None,
    /// A breakpoint with code behind it.
    Breakpoint,
    /// One the build found no code for. Drawn hollow.
    BreakpointUnbound,
    /// One that is switched off. Drawn hollow.
    BreakpointDisabled,
}

/// Asked what to draw beside a line, while the editor is painting.
///
/// `row` counts from zero. Implementations MUST be cheap: this is called once
/// per visible line per paint.
public closure LineMark MarkAsker(nuint row);

/// Which line something happened on. Rows count from zero.
public class RowEventArgs
{
    public nuint Row;

    public RowEventArgs(nuint row) => Row = row;
}

public closure void RowEventHandler(Control sender, RowEventArgs args);

/// Told which word the pointer came to rest over, or "" when it left one.
public closure void HoverHandler(String word);

/// The column the right-hand rule is drawn at. 80, because that is what the
/// sources this is written to edit are wrapped to.
const nuint RightMargin = 80u;

/// How small and how large the text may be made, in points. Small enough to
/// fit a wide file on a small screen, large enough to read across a room, and
/// bounded at all because a size of zero is a division by it.
const int SmallestFont = 6;
const int LargestFont = 32;

/// The size the text starts at, and what "reset" goes back to.
public const int DefaultTextSize = 10;

/// A text editor with syntax highlighting.
public class CodeEditor : CustomControl
{
    Document _contents;
    Theme _palette;

    /// Where the caret is, and where a selection started.
    ///
    /// **A selection is two positions, not a flag and a range.** `_anchor` is
    /// where the selection began and `_caretPosition` is where it has got to,
    /// so the two may be in either order -- which is what a drag upwards is --
    /// and there is no selection exactly when they are equal. A range plus a
    /// direction flag says the same thing in a way that has to be kept
    /// consistent.
    Position _caretPosition;
    Position _anchor;

    /// The column the caret would like to be in when it moves up or down.
    ///
    /// **Remembered across vertical movement, and reset by anything else.**
    /// Moving down from column 40 through a short line and on to a long one
    /// puts the caret back at 40, which is what every editor does and what
    /// nobody notices until it is missing.
    nuint _wantedColumn;
    bool _keepsWantedColumn;

    /// The first line shown, and the first column.
    nuint _topLine;
    nuint _leftColumn;

    /// Set when the caret was placed before the editor could measure itself,
    /// so the first paint places it again with real sizes.
    bool _isPlacingCaretOnPaint;

    ScrollBar _verticalScroll;
    ScrollBar _horizontalScroll;

    /// The width of one character and the height of one line, measured once
    /// from the font. Zero until the first paint, which is the first time there
    /// is a `Graphics` to measure with.
    int _cellWidth;
    int _lineHeight;
    /// The width of the line-number gutter, including the breakpoint margin
    /// before it and the gap after it.
    int _gutterWidth;

    /// The breakpoint margin's width. Zero when nothing has asked for one.
    int _marginWidth;

    /// Who to ask what a line is marked with.
    ///
    /// A closure is a value and cannot be null, so `_isMarginShown` is what
    /// says whether anyone has asked. Until then this answers `None`.
    MarkAsker _markAsker;
    bool _isMarginShown;

    /// The line the program is stopped on, and whether there is one.
    nuint _statementRow;
    bool _hasStatement;

    /// False when the statement belongs to a frame further up the stack than
    /// the one the program is in.
    bool _statementIsTop;

    /// True while the mouse is down, so that moving it extends the selection.
    bool _isDragging;

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
    bool _isReady;

    public CodeEditor(WindowedControl parent)
    {
        base(parent);
        _contents = new Document();
        _palette = Theme.CreateLight();
        _caretPosition = Position.Create(0u, 0u);
        _anchor = _caretPosition;
        _wantedColumn = 0u;
        _keepsWantedColumn = false;
        _topLine = 0u;
        _leftColumn = 0u;
        _isPlacingCaretOnPaint = false;
        _cellWidth = 0;
        _lineHeight = 0;
        _gutterWidth = 0;
        _marginWidth = 0;
        _markAsker = (row) => LineMark.None;
        _isMarginShown = false;
        _statementRow = 0u;
        _hasStatement = false;
        _statementIsTop = true;
        _isDragging = false;
        _hoveredWord = "";
        _isReady = false;

        Border = ControlBorder.Sunken;
        Font = new Font(MonospaceFamily, DefaultTextSize);
        BackColor = _palette.Background;
        Cursor = CursorKind.Text;

        _verticalScroll = new ScrollBar(this, true);
        _verticalScroll.ValueChanged += this.OnScrolledDown;
        _horizontalScroll = new ScrollBar(this, false);
        _horizontalScroll.ValueChanged += this.OnScrolledAcross;

        _isReady = true;
        UpdateScrollBars();
    }

    /// The size of the text, in points.
    ///
    /// Changing it throws the measured metrics away rather than scaling them:
    /// a font is not linear -- hinting moves a stem by a whole pixel at a time
    /// -- so the width of a cell at 11 points is not the width at 10 times
    /// eleven tenths, and a column worked out that way drifts across the line.
    public int FontSize
    {
        get => Font.Size;
        set
        {
            if (value < SmallestFont || value > LargestFont)
                return;
            if (value == Font.Size)
                return;
            Font = Font.WithSize(value);
        }
    }

    /// Makes the text one point bigger or smaller, within the range above.
    /// What Ctrl+`+` and Ctrl+`-` do, and what a menu item calls.
    public void ResizeFont(int by) => FontSize = Font.Size + by;

    /// The font changed, so nothing measured from the old one is true.
    ///
    /// **`_cellWidth` back to zero rather than a remeasure here.** There is no
    /// `Graphics` outside a paint, and the next paint begins by measuring
    /// whenever `_cellWidth` is zero -- so this says "unknown" and the one
    /// place that knows how to find out does the work.
    protected override void OnFontChanged()
    {
        _cellWidth = 0;
        _lineHeight = 0;
        Invalidate();
        base.OnFontChanged();
    }

    /// The fixed-width font to use, by the name the platform knows it under.
    ///
    /// Consolas ships with Windows and DejaVu Sans Mono with essentially every
    /// desktop Linux; where neither is present the platform substitutes, and
    /// what it substitutes for a name it does not know is its default
    /// fixed-width face -- which is the right answer anyway.
    String MonospaceFamily
    {
        get
        {
            #if WINDOWS
            return "Consolas";
            #else
            return "DejaVu Sans Mono";
            #endif
        }
    }

    // ------------------------------------------------------------- the text

    /// The text being edited.
    ///
    /// Not `Text`: a `Control` already has one, meaning its caption, and a
    /// property that hid it would be two different things under one name in a
    /// type that has both.
    public Document Contents => _contents;

    // --------------------------------------------------------- the margin

    /// Shows the breakpoint margin, and says who to ask about each line.
    ///
    /// The asker is called for visible lines only, so the cost is the height
    /// of the control rather than the length of the file.
    public void ShowMarginMarks(MarkAsker asker)
    {
        _markAsker = asker;
        _isMarginShown = true;
        Invalidate();
    }

    /// The margin was clicked. Carries the row.
    public event RowEventHandler MarginClicked;

    /// Puts the current-statement highlight on a line, and scrolls to it.
    ///
    /// `top` is false for a stack frame the program is not in. That gets a
    /// paler highlight, because it is not where execution resumes.
    public void ShowStatementAt(nuint row, bool top)
    {
        _statementRow = row;
        _hasStatement = true;
        _statementIsTop = top;
        MoveCaretTo(row, 0u);
        Invalidate();
    }

    public void ClearStatement()
    {
        if (!_hasStatement)
            return;
        _hasStatement = false;
        Invalidate();
    }

    public bool HasStatement => _hasStatement;
    public nuint StatementRow => _statementRow;

    public Theme Palette
    {
        get => _palette;
        set
        {
            _palette = value;
            BackColor = _palette.Background;
            Invalidate();
        }
    }

    /// Where the caret is.
    public Position CaretPosition => _caretPosition;

    /// The first line showing, counting from zero.
    public nuint TopLine => _topLine;

    /// How many whole lines fit in the control as it is now.
    public int VisibleLineCount => VisibleLines;

    /// Whether anything is selected.
    public bool HasSelection => !_caretPosition.IsSameAs(_anchor);

    /// The selected text, or `""`.
    public String SelectedText
    {
        get
        {
            if (!HasSelection)
                return "";
            return _contents.GetTextBetween(_anchor, _caretPosition);
        }
    }

    /// Replaces the document. The caret goes to the top and the view with it.
    public void SetDocument(Document replacement)
    {
        _contents = replacement;
        _caretPosition = Position.Create(0u, 0u);
        _anchor = _caretPosition;
        _topLine = 0u;
        _leftColumn = 0u;
        UpdateScrollBars();
        Invalidate();
        OnCaretMoved();
    }

    /// Puts the caret on a line, scrolls it into view, and selects nothing.
    ///
    /// What an error in the output pane does when it is double-clicked, and the
    /// reason this is public.
    public void MoveCaretTo(nuint row, nuint column)
    {
        nuint line = row >= _contents.LineCount ? _contents.LineCount - 1u : row;
        _caretPosition = Position.Create(line, ClampColumn(line, column));
        _anchor = _caretPosition;
        PlaceCaretLine();
        _isPlacingCaretOnPaint = _lineHeight <= 0;
        Invalidate();
        OnCaretMoved();
    }

    /// Roughly a third of the way down, rather than at the very top: an error
    /// is nearly always about the lines above it as well.
    void PlaceCaretLine()
    {
        nuint visible = (nuint)VisibleLines;
        nuint line = _caretPosition.Row;
        _topLine = line > visible / 3u ? line - visible / 3u : 0u;
        UpdateScrollBars();
        ScrollToCaret();
    }

    /// Raised whenever the caret moves, so a status bar can say where it is.
    public event EventHandler CaretMoved;

    /// The pointer came to rest over a word, or left the one it was over.
    ///
    /// The word itself rather than a position, because what wants it is a
    /// debugger asking what that name is worth, and an empty one is the
    /// pointer leaving.
    public event HoverHandler Hovered;

    /// The word the pointer was last over, so that moving inside one asks
    /// nothing. A value is read out of a stopped process; asking per pixel
    /// would read it a hundred times across one identifier.
    String _hoveredWord;
    protected virtual void OnCaretMoved() => CaretMoved(this);

    /// Raised whenever the text changes.
    public event EventHandler Edited;
    protected virtual void OnEdited() => Edited(this);

    // ----------------------------------------------------- columns and bytes

    /// The screen column a byte offset sits at, with tabs expanded.
    ///
    /// One of the two places in this file where a byte offset and a column
    /// differ. Walks the line, which is O(its length) -- and a line is short.
    public nuint GetColumnOfOffset(String line, nuint offset)
    {
        nuint column = 0u;
        nuint at = 0u;
        nuint size = line.ByteLength();
        while (at < offset && at < size)
        {
            if (line.GetByteAt(at) == (byte)'\t')
            {
                column = column + (TabWidth - column % TabWidth);
                at++;
            }
            else
            {
                column++;
                at = line.SkipCodePoint(at);
            }
        }
        return column;
    }

    /// The byte offset at a screen column: the other of the two.
    ///
    /// A column inside an expanded tab lands on the tab itself, and a column
    /// past the end of the line lands at the end of it, because a caret may not
    /// be somewhere there is no text.
    public nuint GetOffsetOfColumn(String line, nuint column)
    {
        nuint at = 0u;
        nuint seen = 0u;
        nuint size = line.ByteLength();
        while (at < size)
        {
            nuint next = seen;
            if (line.GetByteAt(at) == (byte)'\t')
            {
                next = seen + (TabWidth - seen % TabWidth);
            }
            else
            {
                next = seen + 1u;
            }
            // A column that lands inside this character -- which a tab makes
            // possible, being several columns wide -- belongs to it.
            if (column < next)
                return at;
            seen = next;
            at = line.GetByteAt(at) == (byte)'\t' ? at + 1u : line.SkipCodePoint(at);
        }
        return size;
    }

    /// The screen column the caret is in.
    nuint MeasureCaretColumn()
        => GetColumnOfOffset(_contents.GetLineText(_caretPosition.Row),
                             _caretPosition.Column);

    /// How wide a line is, in columns.
    nuint GetLineWidth(String line) => GetColumnOfOffset(line, line.ByteLength());

    nuint ClampColumn(nuint row, nuint column)
    {
        nuint size = _contents.GetLineLength(row);
        return column > size ? size : column;
    }

    // --------------------------------------------------------------- layout

    /// How many whole lines fit.
    int VisibleLines
    {
        get
        {
            if (_lineHeight <= 0)
                return 1;
            int height = ClientBounds.Height - ScrollThickness;
            int fits = height / _lineHeight;
            return fits < 1 ? 1 : fits;
        }
    }

    /// How many whole columns fit beside the gutter.
    int VisibleColumns
    {
        get
        {
            if (_cellWidth <= 0)
                return 1;
            int width = ClientBounds.Width - _gutterWidth - ScrollThickness;
            int fits = width / _cellWidth;
            return fits < 1 ? 1 : fits;
        }
    }

    int ScrollThickness => 16;

    /// Puts the scroll bars where they belong and tells them what they are
    /// scrolling. Called on every resize and after every edit.
    void UpdateScrollBars()
    {
        if (!_isReady)
            return;
        var area = ClientBounds;
        int bar = ScrollThickness;

        _verticalScroll.SetBounds(area.Width - bar, 0, bar, area.Height - bar);
        _horizontalScroll.SetBounds(0, area.Height - bar, area.Width - bar, bar);

        int lines = (int)_contents.LineCount;
        int page = VisibleLines;
        _verticalScroll.Maximum = lines > page ? lines - 1 : 0;
        _verticalScroll.PageSize = page;
        _verticalScroll.Value = (int)_topLine;

        // The widest line on screen, rather than in the file: scanning every
        // line of a large file on every keystroke to find the longest is the
        // one thing here that would be O(the file), and what it buys is a
        // horizontal thumb of exactly the right size.
        int widest = 0;
        nuint last = _topLine + (nuint)page;
        if (last > _contents.LineCount)
            last = _contents.LineCount;
        for (nuint i = _topLine; i < last; i++)
        {
            int width = (int)GetLineWidth(_contents.GetLineText(i));
            if (width > widest)
                widest = width;
        }
        int columns = VisibleColumns;
        _horizontalScroll.Maximum = widest > columns ? widest - 1 : 0;
        _horizontalScroll.PageSize = columns;
        _horizontalScroll.Value = (int)_leftColumn;
    }

    protected override void OnResize()
    {
        if (_isReady)
            UpdateScrollBars();
        base.OnResize();
    }

    void OnScrolledDown(Control sender)
    {
        nuint to = (nuint)_verticalScroll.Value;
        if (to == _topLine)
            return;
        _topLine = to;
        Invalidate();
    }

    void OnScrolledAcross(Control sender)
    {
        nuint to = (nuint)_horizontalScroll.Value;
        if (to == _leftColumn)
            return;
        _leftColumn = to;
        Invalidate();
    }

    /// Scrolls so the caret is on screen. Does nothing when it already is,
    /// which is the common case and the reason typing does not repaint the
    /// whole control.
    void ScrollToCaret()
    {
        nuint lines = (nuint)VisibleLines;
        if (_caretPosition.Row < _topLine)
        {
            _topLine = _caretPosition.Row;
        }
        else if (_caretPosition.Row >= _topLine + lines)
        {
            _topLine = _caretPosition.Row - lines + 1u;
        }

        // Before its first paint a control has no cell width, and before its
        // layout no width at all; `VisibleColumns` then answers 1, and any
        // caret past column 0 would scroll the text sideways before anyone had
        // seen it. A tab opened and moved in one step is exactly that.
        if (_cellWidth <= 0 || ClientBounds.Width <= _gutterWidth + ScrollThickness)
        {
            UpdateScrollBars();
            return;
        }

        nuint column = MeasureCaretColumn();
        nuint columns = (nuint)VisibleColumns;
        if (column < _leftColumn)
        {
            _leftColumn = column;
        }
        else if (column >= _leftColumn + columns)
        {
            _leftColumn = column - columns + 1u;
        }

        UpdateScrollBars();
    }

    // -------------------------------------------------------------- drawing

    protected override void OnPaint(PaintEventArgs args)
    {
        if (!_isReady)
            return;
        var canvas = args.Graphics;

        // Measured once, from the font, the first time there is something to
        // measure with. `M` rather than a space: a space is the one character a
        // few fixed-width faces still report as narrower than the rest.
        if (_cellWidth <= 0)
        {
            var size = canvas.MeasureString("M", Font);
            _cellWidth = size.Width;
            _lineHeight = size.Height;
            if (_cellWidth <= 0)
                _cellWidth = 8;
            if (_lineHeight <= 0)
                _lineHeight = 14;
            UpdateScrollBars();
        }
        if (_isPlacingCaretOnPaint)
        {
            _isPlacingCaretOnPaint = false;
            PlaceCaretLine();
        }

        _marginWidth = _isMarginShown ? MarginCells * _cellWidth : 0;
        _gutterWidth = MeasureGutterWidth(canvas);

        var area = ClientBounds;
        canvas.Clear(_palette.Background);
        canvas.FillRectangle(new Brush(_palette.GutterBack),
                             Rectangle.FromBounds(0, 0, _gutterWidth, area.Height));

        // The rule at column 80, drawn under the text rather than over it.
        int rule = _gutterWidth + (int)(RightMargin - _leftColumn) * _cellWidth;
        if (rule > _gutterWidth && rule < area.Width)
        {
            canvas.DrawLine(new Pen(_palette.Margin), rule, 0, rule, area.Height);
        }

        nuint lines = _contents.LineCount;
        nuint last = _topLine + (nuint)VisibleLines + 1u;
        if (last > lines)
            last = lines;

        for (nuint row = _topLine; row < last; row++)
        {
            int y = (int)(row - _topLine) * _lineHeight;
            PaintLine(canvas, row, y, area.Width);
        }

        PlaceCaret();
    }

    /// How wide the gutter is: room for the largest line number, and a gap.
    int MeasureGutterWidth(Graphics canvas)
    {
        nuint count = _contents.LineCount;
        int digits = 1;
        while (count >= 10u)
        {
            count = count / 10u;
            digits++;
        }
        if (digits < 3)
            digits = 3;
        return _marginWidth + (digits + 2) * _cellWidth;
    }

    void PaintLine(Graphics canvas, nuint row, int y, int width)
    {
        var line = _contents.GetLine(row);
        bool current = row == _caretPosition.Row;

        // The statement highlight wins over the caret line's. Both would paint
        // the same rectangle, and the stopped line must stay visible under the
        // caret.
        bool stopped = _hasStatement && row == _statementRow;
        if (stopped)
        {
            canvas.FillRectangle(new Brush(_statementIsTop
                                           ? _palette.CurrentStatement
                                           : _palette.CalledFrom),
                                 Rectangle.FromBounds(_gutterWidth, y, width - _gutterWidth,
                                              _lineHeight));
        }
        else if (current && !HasSelection)
        {
            canvas.FillRectangle(new Brush(_palette.CurrentLine),
                                 Rectangle.FromBounds(_gutterWidth, y, width - _gutterWidth, _lineHeight));
        }

        PaintSelection(canvas, row, y, width);
        PaintMargin(canvas, row, y, stopped);

        // The number, right-aligned in the gutter.
        String number = Standard.Text.FromInteger(row + 1u);
        int numberX = _gutterWidth - _cellWidth - (int)number.ByteLength() * _cellWidth;
        canvas.DrawString(number, Font,
                          current ? _palette.GutterCurrent : _palette.GutterText,
                          numberX, y);

        // One `DrawString` per token, at the column its first byte sits in.
        // Nothing is measured: the column is a count and the x is a
        // multiplication, which is the whole reason for the fixed-width font.
        foreach (var token in line.Tokens)
        {
            if (token.Kind == TokenKind.Whitespace)
                continue;

            nuint column = GetColumnOfOffset(line.Text, token.Start);
            if (column + token.Length < _leftColumn)
                continue;

            int x = _gutterWidth + (int)(column - _leftColumn) * _cellWidth;
            if (x > width)
                break;

            String piece = line.Text.Substring(token.Start, token.Length);
            canvas.DrawString(piece, Font, _palette.GetColorFor(token.Kind), x, y);
        }
    }

    /// The breakpoint disc and the current-statement arrow.
    ///
    /// Drawn rather than loaded, for the reason `Icons.sl` gives: two shapes
    /// at any text size is less to carry than a bitmap per size.
    void PaintMargin(Graphics canvas, nuint row, int y, bool stopped)
    {
        if (_marginWidth <= 0)
            return;

        // Arrow first, disc over it. A breakpoint on the stopped line is still
        // a breakpoint.
        if (stopped && _statementIsTop)
            PaintStatementArrow(canvas, y);

        var mark = _markAsker(row);
        if (mark == LineMark.None)
            return;

        // A fifth of a cell of clearance above and below, at every text size.
        int inset = _lineHeight / 5;
        int size = _lineHeight - inset * 2;
        if (size < 4)
            size = 4;
        var disc = Rectangle.FromBounds((_marginWidth - size) / 2, y + inset, size, size);

        switch (mark)
        {
            case LineMark.Breakpoint:
                canvas.FillEllipse(new Brush(_palette.BreakpointFill), disc);
                canvas.DrawEllipse(new Pen(_palette.BreakpointEdge), disc);
                break;

            default:
                // Unbound or disabled. Hollow rather than absent: an absent
                // glyph reads as a breakpoint that was never set.
                canvas.DrawEllipse(new Pen(_palette.BreakpointHollow), disc);
                break;
        }
    }

    /// The arrow beside the line the program is stopped on.
    void PaintStatementArrow(Graphics canvas, int y)
    {
        int middle = y + _lineHeight / 2;
        int high = _lineHeight / 4;
        int left = _cellWidth / 3;
        int right = _marginWidth - _cellWidth / 3;
        int stem = left + (right - left) / 2;

        var arrow = new Point[7];
        arrow[0u] = Point.FromXY(left, middle - high / 2);
        arrow[1u] = Point.FromXY(stem, middle - high / 2);
        arrow[2u] = Point.FromXY(stem, middle - high);
        arrow[3u] = Point.FromXY(right, middle);
        arrow[4u] = Point.FromXY(stem, middle + high);
        arrow[5u] = Point.FromXY(stem, middle + high / 2);
        arrow[6u] = Point.FromXY(left, middle + high / 2);

        canvas.FillPolygon(new Brush(_palette.CurrentStatementArrow), arrow);
    }

    /// The highlight behind whatever of this line is selected.
    void PaintSelection(Graphics canvas, nuint row, int y, int width)
    {
        if (!HasSelection)
            return;

        var start = _anchor;
        var end = _caretPosition;
        if (end.IsBefore(start))
        {
            start = _caretPosition;
            end = _anchor;
        }
        if (row < start.Row || row > end.Row)
            return;

        String text = _contents.GetLineText(row);
        nuint from = row == start.Row ? GetColumnOfOffset(text, start.Column) : 0u;
        nuint to = row == end.Row ? GetColumnOfOffset(text, end.Column) : GetLineWidth(text) + 1u;

        // A line wholly inside the selection is highlighted one column past its
        // end, which is what shows that the line break is selected too.
        if (to <= from)
            return;
        if (from < _leftColumn)
            from = _leftColumn;

        int x = _gutterWidth + (int)(from - _leftColumn) * _cellWidth;
        int span = (int)(to - from) * _cellWidth;
        if (x + span > width)
            span = width - x;
        if (span <= 0)
            return;

        canvas.FillRectangle(new Brush(_palette.Selection),
                             Rectangle.FromBounds(x, y, span, _lineHeight));
    }

    /// Puts the platform's caret where the text caret is, or takes it away when
    /// it has scrolled off.
    void PlaceCaret()
    {
        if (_caretPosition.Row < _topLine
            || _caretPosition.Row >= _topLine + (nuint)VisibleLines + 1u)
        {
            Caret = Rectangle.Empty;
            return;
        }
        nuint column = MeasureCaretColumn();
        if (column < _leftColumn)
        {
            Caret = Rectangle.Empty;
            return;
        }
        int x = _gutterWidth + (int)(column - _leftColumn) * _cellWidth;
        int y = (int)(_caretPosition.Row - _topLine) * _lineHeight;
        Caret = Rectangle.FromBounds(x, y, 2, _lineHeight);
    }

    // --------------------------------------------------------- find, replace

    /// Finds `needle` after the caret and selects it. True when it found one.
    ///
    /// **Searched line by line, not over one big string.** The document is a
    /// list of lines, and joining it to search would allocate the whole file on
    /// every keystroke of an incremental find. The cost is that a needle
    /// containing a newline is never found, which is stated here rather than
    /// discovered: the find bar is a line-oriented tool, and a multi-line search
    /// wants a different interface anyway.
    ///
    /// **From the end of the selection, not from the caret.** After a match is
    /// found and selected, the caret is at its end and the anchor at its start;
    /// searching again from the lower of those would find the same match
    /// forever. Taking the higher is what makes Find Next advance.
    ///
    /// `wrap` decides what happens at the end of the file: true starts again at
    /// the top, which is what a Find Next button does, and false stops, which is
    /// what Replace All wants so that it terminates.
    public bool FindNext(String needle, bool matchCase, bool wrap)
    {
        if (!_isReady || needle.ByteLength() == 0u || _contents.LineCount == 0u)
            return false;

        var from = _caretPosition.IsBefore(_anchor) ? _anchor : _caretPosition;
        String wanted = matchCase ? needle : needle.ToLowerAscii();

        // The line the caret is on, from the caret; then every line after it;
        // then, if wrapping, from the top back to and including this one -- so
        // a match earlier on the caret's own line is found last rather than
        // skipped, which is the off-by-one this shape exists to avoid.
        nuint rows = _contents.LineCount;
        for (nuint step = 0u; step <= rows; step++)
        {
            nuint row = from.Row + step;
            bool wrapped = row >= rows;
            if (wrapped)
            {
                if (!wrap)
                    return false;
                row = row - rows;
            }

            String line = _contents.GetLineText(row);
            String hay = matchCase ? line : line.ToLowerAscii();

            // Only the first line of the sweep starts part-way in.
            nuint start = (step == 0u) ? from.Column : 0u;
            if (start > hay.ByteLength())
                continue;

            long at = hay.IndexOf(wanted, start);
            if (at < 0)
                continue;

            // The last step is the caret's own line come round again, and a
            // match at or after where we began is one already reported.
            if (wrapped && row == from.Row && (nuint)at >= from.Column)
                return false;

            SelectRange(row, (nuint)at, (nuint)at + needle.ByteLength());
            return true;
        }

        return false;
    }

    /// Replaces the selection when it is already the thing being looked for,
    /// then finds the next one. True when anything was replaced.
    ///
    /// **Replace does not replace what is not selected.** A Replace button
    /// pressed when the selection is something else finds the next match and
    /// changes nothing, which is what every editor does -- the first press
    /// selects, the second replaces. Doing both at once means a stray click
    /// silently edits a place nobody looked at.
    public bool ReplaceCurrent(String needle, String with, bool matchCase)
    {
        if (!_isReady || needle.ByteLength() == 0u)
            return false;

        String chosen = SelectedText;
        bool matches = matchCase
            ? chosen == needle
            : chosen.ToLowerAscii() == needle.ToLowerAscii();

        if (!matches)
        {
            FindNext(needle, matchCase, true);
            return false;
        }

        var start = _caretPosition.IsBefore(_anchor) ? _caretPosition : _anchor;
        var end = _caretPosition.IsBefore(_anchor) ? _anchor : _caretPosition;

        _contents.DeleteText(start, end);
        var landed = _contents.InsertText(start, with);
        _caretPosition = landed;
        _anchor = landed;
        _keepsWantedColumn = false;

        ScrollToCaret();
        Invalidate();
        OnCaretMoved();
        OnEdited();

        FindNext(needle, matchCase, true);
        return true;
    }

    /// Replaces every occurrence and answers how many.
    ///
    /// **From the very top, and never wrapping**, which is what makes it
    /// terminate. Wrapping would find the replacements again whenever the
    /// replacement contains the needle -- `x` to `xx` is the case that never
    /// ends -- and starting where the caret happens to be would quietly miss
    /// everything above it.
    public nuint ReplaceAll(String needle, String with, bool matchCase)
    {
        if (!_isReady || needle.ByteLength() == 0u)
            return 0u;

        _caretPosition = Position.Create(0u, 0u);
        _anchor = _caretPosition;

        nuint done = 0u;
        while (FindNext(needle, matchCase, false))
        {
            var start = _caretPosition.IsBefore(_anchor) ? _caretPosition : _anchor;
            var end = _caretPosition.IsBefore(_anchor) ? _anchor : _caretPosition;

            _contents.DeleteText(start, end);
            var landed = _contents.InsertText(start, with);
            _caretPosition = landed;
            _anchor = landed;
            done++;
        }

        _keepsWantedColumn = false;
        ScrollToCaret();
        Invalidate();
        OnCaretMoved();
        if (done > 0u)
            OnEdited();
        return done;
    }

    /// Selects a run on one line and scrolls it into view.
    void SelectRange(nuint row, nuint from, nuint to)
    {
        _anchor = Position.Create(row, from);
        _caretPosition = Position.Create(row, to);
        _keepsWantedColumn = false;

        // Into view the way `MoveCaretTo` does it, rather than only far
        // enough: a match found at the bottom of the file should not sit on the
        // last visible line with no context under it.
        nuint visible = (nuint)VisibleLines;
        if (row < _topLine || row >= _topLine + visible)
            _topLine = row > visible / 3u ? row - visible / 3u : 0u;

        UpdateScrollBars();
        ScrollToCaret();
        Invalidate();
        OnCaretMoved();
    }

    // ------------------------------------------------------------ the mouse

    protected override void OnMouseDown(MouseEventArgs args)
    {
        if (!_isReady)
            return;
        Focus();

        // A margin click MUST NOT move the caret. Setting several breakpoints
        // in a row would otherwise lose the caret's place each time.
        if (_marginWidth > 0 && args.X < _marginWidth)
        {
            MarginClicked(this, new RowEventArgs(GetRowAt(args.Y)));
            return;
        }

        var hit = GetPositionAt(args.X, args.Y);
        _caretPosition = hit;
        if (!args.Modifiers.HasFlag(ModifierKeys.Shift))
            _anchor = hit;
        _isDragging = true;
        CaptureMouse(true);
        _keepsWantedColumn = false;
        ScrollToCaret();
        Invalidate();
        OnCaretMoved();
        base.OnMouseDown(args);
    }

    /// Double-clicking selects the word under the pointer.
    ///
    /// The caret is already where the second click landed -- the backend raises
    /// the press *and* the double, in that order, precisely so a control that
    /// tracks presses sees both -- so this only has to widen the selection out
    /// to the word's edges from where it already is.
    ///
    /// **Both edges are found by scanning from the caret**, rather than by
    /// reusing `FindPreviousWordStart` and `FindNextWordStart`. Those two are
    /// keyboard movement: they cross runs of spaces, because Ctrl+Left from
    /// the start of a word must reach the previous one. A double-click on a
    /// space should select that run of spaces and stop, and a double-click
    /// inside a word should take the word and not the gap after it.
    protected override void OnDoubleClick()
    {
        base.OnDoubleClick();
        SelectWord();
    }

    /// Selects the run the caret is in: a word, a run of spaces, or a run of
    /// punctuation. What a double-click does, separated from the gesture so
    /// that it can be asked for by a menu, by a keystroke, and by a test that
    /// has no mouse.
    public void SelectWord()
    {
        if (!_isReady)
            return;

        String line = _contents.GetLineText(_caretPosition.Row);
        nuint size = line.ByteLength();
        if (size == 0u)
            return;

        nuint at = _caretPosition.Column;
        if (at >= size)
            at = FindPreviousCharacter(line, size);

        // Which run the byte under the pointer belongs to. A word, a run of
        // spaces, or a run of punctuation -- three cases rather than two, so
        // that double-clicking `=>` takes both characters instead of one.
        byte here = line.GetByteAt(at);
        bool wordly = IsWordByte(here);
        bool spacey = IsSpaceByte(here);

        nuint start = at;
        while (start > 0u)
        {
            nuint back = FindPreviousCharacter(line, start);
            if (!IsInSameRun(line.GetByteAt(back), wordly, spacey))
                break;
            start = back;
        }

        nuint end = at;
        while (end < size && IsInSameRun(line.GetByteAt(end), wordly, spacey))
            end = line.SkipCodePoint(end);

        _anchor = Position.Create(_caretPosition.Row, start);
        _caretPosition = Position.Create(_caretPosition.Row, end);
        _keepsWantedColumn = false;
        ScrollToCaret();
        Invalidate();
        OnCaretMoved();
    }

    /// Whether a byte belongs to the same run as the one double-clicked.
    bool IsInSameRun(byte c, bool wordly, bool spacey)
    {
        if (wordly)
            return IsWordByte(c);
        if (spacey)
            return IsSpaceByte(c);
        return !IsWordByte(c) && !IsSpaceByte(c);
    }

    protected override void OnMouseMove(MouseEventArgs args)
    {
        if (!_isReady)
            return;
        if (_isDragging)
        {
            _caretPosition = GetPositionAt(args.X, args.Y);
            ScrollToCaret();
            Invalidate();
            OnCaretMoved();
        }
        else
        {
            ReportHover(args.X, args.Y);
        }
        base.OnMouseMove(args);
    }

    /// Says which word the pointer is over, when it changes.
    ///
    /// Only over the text: the gutter is line numbers and breakpoint glyphs,
    /// and a number there is not a name.
    void ReportHover(int x, int y)
    {
        String word = x < _gutterWidth ? "" : GetWordAt(GetPositionAt(x, y));
        if (word == _hoveredWord)
            return;

        _hoveredWord = word;
        Hovered(word);
    }

    /// The word a position is inside, or "".
    ///
    /// A word and nothing else: a run of spaces or of punctuation is not a
    /// name, and answering one would have a debugger evaluating `=>`.
    public String GetWordAt(Position where)
    {
        if (where.Row >= _contents.LineCount)
            return "";

        String line = _contents.GetLineText(where.Row);
        nuint size = line.ByteLength();
        if (size == 0u || where.Column >= size)
            return "";

        if (!IsWordByte(line.GetByteAt(where.Column)))
            return "";

        nuint start = where.Column;
        while (start > 0u)
        {
            nuint back = FindPreviousCharacter(line, start);
            if (!IsWordByte(line.GetByteAt(back)))
                break;
            start = back;
        }

        nuint end = where.Column;
        while (end < size && IsWordByte(line.GetByteAt(end)))
            end = line.SkipCodePoint(end);

        return line.Substring(start, end - start);
    }

    protected override void OnMouseUp(MouseEventArgs args)
    {
        if (!_isReady)
            return;
        if (_isDragging)
        {
            _isDragging = false;
            CaptureMouse(false);
        }
        base.OnMouseUp(args);
    }

    protected override void OnMouseWheel(MouseEventArgs args)
    {
        if (!_isReady)
            return;
        // Three lines a notch, as every platform's own setting defaults to.
        int notches = args.Delta / 120;
        if (notches == 0)
            notches = args.Delta > 0 ? 1 : -1;

        // Ctrl and the wheel resizes the text, which is what every editor does
        // with that gesture. It is also the only way to resize it from the
        // keyboard-and-mouse: `+` and `-` are OEM virtual keys, and Forms'
        // `Key` enum does not name them yet.
        if (args.Modifiers.HasFlag(ModifierKeys.Control))
        {
            ResizeFont(notches > 0 ? 1 : -1);
            base.OnMouseWheel(args);
            return;
        }
        int to = (int)_topLine - notches * 3;
        if (to < 0)
            to = 0;
        int highest = (int)_contents.LineCount - 1;
        if (to > highest)
            to = highest;
        if ((nuint)to == _topLine)
            return;
        _topLine = (nuint)to;
        UpdateScrollBars();
        Invalidate();
        base.OnMouseWheel(args);
    }

    /// Which row a y coordinate is over, clamped to the document.
    nuint GetRowAt(int y)
    {
        if (_lineHeight <= 0)
            return 0u;
        int row = y / _lineHeight + (int)_topLine;
        if (row < 0)
            row = 0;
        nuint highest = _contents.LineCount - 1u;
        return (nuint)row > highest ? highest : (nuint)row;
    }

    /// What position a point in the control is over.
    Position GetPositionAt(int x, int y)
    {
        if (_lineHeight <= 0 || _cellWidth <= 0)
            return Position.Create(0u, 0u);

        nuint line = GetRowAt(y);

        int column = (x - _gutterWidth) / _cellWidth + (int)_leftColumn;
        if (column < 0)
            column = 0;
        return Position.Create(line, GetOffsetOfColumn(_contents.GetLineText(line), (nuint)column));
    }

    // --------------------------------------------------------- the keyboard

    protected override void OnKeyDown(KeyEventArgs args)
    {
        if (!_isReady)
            return;
        bool shift = args.Shift;
        bool control = args.Control;
        bool moved = true;

        if (args.Key == Key.Left)
        {
            MoveCaretLeft(shift, control);
        }
        else if (args.Key == Key.Right)
        {
            MoveCaretRight(shift, control);
        }
        else if (args.Key == Key.Up)
        {
            MoveCaretVertically(-1, shift);
        }
        else if (args.Key == Key.Down)
        {
            MoveCaretVertically(1, shift);
        }
        else if (args.Key == Key.PageUp)
        {
            MoveCaretVertically(-VisibleLines, shift);
        }
        else if (args.Key == Key.PageDown)
        {
            MoveCaretVertically(VisibleLines, shift);
        }
        else if (args.Key == Key.Home)
        {
            MoveCaretHome(shift, control);
        }
        else if (args.Key == Key.End)
        {
            MoveCaretEnd(shift, control);
        }
        else if (args.Key == Key.C && control)
        {
            Copy();
            moved = false;
        }
        else if (args.Key == Key.X && control)
        {
            Cut();
            moved = false;
        }
        else if (args.Key == Key.V && control)
        {
            Paste();
            moved = false;
        }
        else if (args.Key == Key.Insert && control)
        {
            Copy();
            moved = false;
        }
        else if (args.Key == Key.Insert && shift)
        {
            Paste();
            moved = false;
        }
        else if (args.Key == Key.A && control)
        {
            SelectAll();
        }
        else if (args.Key == Key.Z && control && !shift)
        {
            Undo();
            moved = false;
        }
        else if (args.Key == Key.Y && control)
        {
            Redo();
            moved = false;
        }
        else if (args.Key == Key.Z && control && shift)
        {
            // Ctrl+Shift+Z as well as Ctrl+Y, because both are in people's
            // fingers and neither is used for anything else here.
            Redo();
            moved = false;
        }
        else if (args.Key == Key.Backspace)
        {
            DeleteBackward();
            moved = false;
        }
        else if (args.Key == Key.Delete)
        {
            DeleteForward();
            moved = false;
        }
        else if (args.Key == Key.Enter)
        {
            TypeText("\n");
            moved = false;
        }
        else if (args.Key == Key.Tab)
        {
            IndentSelection(shift);
            moved = false;
        }
        else
        {
            moved = false;
            base.OnKeyDown(args);
            return;
        }

        if (moved)
        {
            ScrollToCaret();
            Invalidate();
            OnCaretMoved();
        }
        base.OnKeyDown(args);
    }

    protected override void OnKeyPress(KeyPressEventArgs args)
    {
        if (!_isReady)
            return;
        // Everything below a space is a control code, and each one that means
        // something has already been dealt with as a key. Ctrl+V arrives here a
        // second time as character 22, which is exactly why that test is a
        // range and not a list of the ones we happen to have thought of. DEL
        // is one too, and is what Ctrl+Backspace types on Windows.
        if (args.KeyChar >= ' ' && args.KeyChar != '\x7F')
            TypeText(Standard.Text.FromChar(args.KeyChar));
        base.OnKeyPress(args);
    }

    // ------------------------------------------------------------- movement

    /// Collapses the selection unless the shift key is holding it open.
    void CollapseSelection(bool shift)
    {
        if (!shift)
            _anchor = _caretPosition;
        if (!_keepsWantedColumn)
            _wantedColumn = MeasureCaretColumn();
        _keepsWantedColumn = false;
    }

    void MoveCaretLeft(bool shift, bool word)
    {
        // An unheld selection collapses to its near end rather than moving,
        // which is what every editor does and what makes Left after a drag
        // predictable.
        if (!shift && HasSelection)
        {
            _caretPosition = _anchor.IsBefore(_caretPosition) ? _anchor : _caretPosition;
            _anchor = _caretPosition;
            CollapseSelection(false);
            return;
        }

        if (_caretPosition.Column > 0u)
        {
            String line = _contents.GetLineText(_caretPosition.Row);
            _caretPosition = Position.Create(_caretPosition.Row,
                word ? FindPreviousWordStart(line, _caretPosition.Column)
                     : FindPreviousCharacter(line, _caretPosition.Column));
        }
        else if (_caretPosition.Row > 0u)
        {
            nuint above = _caretPosition.Row - 1u;
            _caretPosition = Position.Create(above, _contents.GetLineLength(above));
        }
        CollapseSelection(shift);
    }

    void MoveCaretRight(bool shift, bool word)
    {
        if (!shift && HasSelection)
        {
            _caretPosition = _anchor.IsBefore(_caretPosition) ? _caretPosition : _anchor;
            _anchor = _caretPosition;
            CollapseSelection(false);
            return;
        }

        String line = _contents.GetLineText(_caretPosition.Row);
        if (_caretPosition.Column < line.ByteLength())
        {
            _caretPosition = Position.Create(_caretPosition.Row,
                word ? FindNextWordStart(line, _caretPosition.Column)
                     : line.SkipCodePoint(_caretPosition.Column));
        }
        else if (_caretPosition.Row + 1u < _contents.LineCount)
        {
            _caretPosition = Position.Create(_caretPosition.Row + 1u, 0u);
        }
        CollapseSelection(shift);
    }

    void MoveCaretVertically(int by, bool shift)
    {
        int row = (int)_caretPosition.Row + by;
        if (row < 0)
            row = 0;
        int highest = (int)_contents.LineCount - 1;
        if (row > highest)
            row = highest;

        // The column the caret would like to be in is remembered across a run
        // of vertical movements, so a short line in the middle does not drag it
        // permanently left.
        String text = _contents.GetLineText((nuint)row);
        _caretPosition = Position.Create((nuint)row, GetOffsetOfColumn(text, _wantedColumn));
        _keepsWantedColumn = true;
        CollapseSelection(shift);
    }

    /// Home goes to the first non-blank of the line, and to column zero when it
    /// is already there. The one movement whose two meanings are both wanted.
    void MoveCaretHome(bool shift, bool document)
    {
        if (document)
        {
            _caretPosition = Position.Create(0u, 0u);
            CollapseSelection(shift);
            return;
        }

        String line = _contents.GetLineText(_caretPosition.Row);
        nuint first = 0u;
        while (first < line.ByteLength())
        {
            byte c = line.GetByteAt(first);
            if (c != (byte)' ' && c != (byte)'\t')
                break;
            first++;
        }
        nuint column = _caretPosition.Column == first ? 0u : first;
        _caretPosition = Position.Create(_caretPosition.Row, column);
        CollapseSelection(shift);
    }

    void MoveCaretEnd(bool shift, bool document)
    {
        if (document)
        {
            nuint end = _contents.LineCount - 1u;
            _caretPosition = Position.Create(end, _contents.GetLineLength(end));
        }
        else
        {
            nuint row = _caretPosition.Row;
            _caretPosition = Position.Create(row, _contents.GetLineLength(row));
        }
        CollapseSelection(shift);
    }

    nuint FindPreviousCharacter(String line, nuint offset)
    {
        nuint at = 0u;
        nuint last = 0u;
        while (at < offset)
        {
            last = at;
            at = line.SkipCodePoint(at);
        }
        return last;
    }

    /// The start of the word to the left: past any run of spaces, then past the
    /// run of word bytes before that.
    nuint FindPreviousWordStart(String line, nuint offset)
    {
        nuint at = FindPreviousCharacter(line, offset);
        while (at > 0u && IsSpaceByte(line.GetByteAt(at)))
            at = FindPreviousCharacter(line, at);
        if (at == 0u)
            return 0u;
        if (!IsWordByte(line.GetByteAt(at)))
            return at;
        while (at > 0u)
        {
            nuint back = FindPreviousCharacter(line, at);
            if (!IsWordByte(line.GetByteAt(back)))
                return at;
            at = back;
        }
        return 0u;
    }

    nuint FindNextWordStart(String line, nuint offset)
    {
        nuint size = line.ByteLength();
        nuint at = offset;
        if (at < size && IsWordByte(line.GetByteAt(at)))
        {
            while (at < size && IsWordByte(line.GetByteAt(at)))
            {
                at = line.SkipCodePoint(at);
            }
        }
        else if (at < size)
        {
            at = line.SkipCodePoint(at);
        }
        while (at < size && IsSpaceByte(line.GetByteAt(at)))
            at = line.SkipCodePoint(at);
        return at;
    }

    bool IsSpaceByte(byte c) => c == (byte)' ' || c == (byte)'\t';

    bool IsWordByte(byte c)
    {
        return (c >= (byte)'a' && c <= (byte)'z')
            || (c >= (byte)'A' && c <= (byte)'Z')
            || (c >= (byte)'0' && c <= (byte)'9')
            || c == (byte)'_' || c >= 0x80u;
    }

    // -------------------------------------------------------------- editing

    /// Puts the last edit back and goes to where it was.
    ///
    /// The selection is dropped rather than restored. What was selected before
    /// an edit is not what the edit left behind, and an undo that reinstated a
    /// stale selection would put the next keystroke somewhere surprising.
    public bool Undo()
    {
        if (_contents.Undo() is Some at)
        {
            _caretPosition = at.Value;
            _anchor = _caretPosition;
            FinishEdit();
            return true;
        }
        return false;
    }

    /// Does the last undone edit again.
    public bool Redo()
    {
        if (_contents.Redo() is Some at)
        {
            _caretPosition = at.Value;
            _anchor = _caretPosition;
            FinishEdit();
            return true;
        }
        return false;
    }

    public bool CanUndo => _contents.CanUndo;
    public bool CanRedo => _contents.CanRedo;

    /// Selects the whole file.
    public void SelectAll()
    {
        _anchor = Position.Create(0u, 0u);
        nuint end = _contents.LineCount - 1u;
        _caretPosition = Position.Create(end, _contents.GetLineLength(end));
        _keepsWantedColumn = false;
        Invalidate();
        OnCaretMoved();
    }

    /// Copies the selection, and answers whether there was one.
    ///
    /// **A copy with nothing selected does nothing** rather than copying the
    /// line. Some editors do copy the line, and it is a genuinely useful
    /// shortcut -- but it is also the one that silently replaces what somebody
    /// carefully put on the clipboard a moment ago, and a clipboard is shared
    /// with every other program on the desktop.
    public bool Copy()
    {
        if (!HasSelection)
            return false;
        Clipboard.SetText(SelectedText);
        return true;
    }

    /// Copies the selection and takes it out.
    public bool Cut()
    {
        if (!Copy())
            return false;
        _caretPosition = _contents.DeleteText(_anchor, _caretPosition);
        _anchor = _caretPosition;
        FinishEdit();
        return true;
    }

    /// Puts the clipboard's text in, replacing the selection.
    public bool Paste()
    {
        if (!Clipboard.HasText)
            return false;
        String text = Clipboard.GetText();
        if (text.ByteLength() == 0u)
            return false;
        TypeText(text);
        return true;
    }

    /// Puts text in, replacing the selection if there is one.
    public void TypeText(String text)
    {
        if (HasSelection)
            _caretPosition = _contents.DeleteText(_anchor, _caretPosition);
        _caretPosition = _contents.InsertText(_caretPosition, text);
        _anchor = _caretPosition;
        FinishEdit();
    }

    void DeleteBackward()
    {
        if (HasSelection)
        {
            _caretPosition = _contents.DeleteText(_anchor, _caretPosition);
        }
        else if (_caretPosition.Column > 0u)
        {
            nuint row = _caretPosition.Row;
            nuint back = FindPreviousCharacter(_contents.GetLineText(row), _caretPosition.Column);
            _caretPosition = _contents.DeleteText(Position.Create(row, back), _caretPosition);
        }
        else if (_caretPosition.Row > 0u)
        {
            nuint above = _caretPosition.Row - 1u;
            var joinAt = Position.Create(above, _contents.GetLineLength(above));
            _caretPosition = _contents.DeleteText(joinAt, _caretPosition);
        }
        else
        {
            return;
        }
        _anchor = _caretPosition;
        FinishEdit();
    }

    void DeleteForward()
    {
        if (HasSelection)
        {
            _caretPosition = _contents.DeleteText(_anchor, _caretPosition);
        }
        else if (_caretPosition.Column < _contents.GetLineLength(_caretPosition.Row))
        {
            nuint row = _caretPosition.Row;
            nuint next = _contents.GetLineText(row).SkipCodePoint(_caretPosition.Column);
            _caretPosition = _contents.DeleteText(_caretPosition, Position.Create(row, next));
        }
        else if (_caretPosition.Row + 1u < _contents.LineCount)
        {
            var below = Position.Create(_caretPosition.Row + 1u, 0u);
            _caretPosition = _contents.DeleteText(_caretPosition, below);
        }
        else
        {
            return;
        }
        _anchor = _caretPosition;
        FinishEdit();
    }

    /// Tab, which means two different things and the selection says which.
    ///
    /// With nothing selected it inserts spaces to the next tab stop -- spaces
    /// rather than a tab, because that is what the sources this edits use, and
    /// an editor that inserted the other kind would make every file it touched
    /// inconsistent with itself.
    void IndentSelection(bool back)
    {
        if (!HasSelection && !back)
        {
            nuint column = MeasureCaretColumn();
            nuint spaces = TabWidth - column % TabWidth;
            TypeText(" ".Repeat(spaces));
            return;
        }

        var start = _anchor;
        var end = _caretPosition;
        if (end.IsBefore(start))
        {
            start = _caretPosition;
            end = _anchor;
        }

        for (nuint row = start.Row; row <= end.Row; row++)
        {
            String line = _contents.GetLineText(row);
            if (back)
            {
                nuint strip = 0u;
                while (strip < TabWidth && strip < line.ByteLength()
                       && line.GetByteAt(strip) == (byte)' ')
                {
                    strip++;
                }
                if (strip > 0u)
                {
                    _contents.DeleteText(Position.Create(row, 0u), Position.Create(row, strip));
                }
            }
            else if (line.ByteLength() > 0u)
            {
                _contents.InsertText(Position.Create(row, 0u), " ".Repeat(TabWidth));
            }
        }

        // The selection keeps covering the same lines, whole.
        _anchor = Position.Create(start.Row, 0u);
        _caretPosition = Position.Create(end.Row, _contents.GetLineLength(end.Row));
        FinishEdit();
    }

    void FinishEdit()
    {
        _keepsWantedColumn = false;
        _wantedColumn = MeasureCaretColumn();
        UpdateScrollBars();
        ScrollToCaret();
        Invalidate();
        OnCaretMoved();
        OnEdited();
    }
}
