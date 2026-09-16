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
    Document _doc;
    Theme _palette;

    /// Where the caret is, and where a selection started.
    ///
    /// **A selection is two positions, not a flag and a range.** `anchor` is
    /// where the selection began and `caret` is where it has got to, so the two
    /// may be in either order -- which is what a drag upwards is -- and there
    /// is no selection exactly when they are equal. A range plus a direction
    /// flag says the same thing in a way that has to be kept consistent.
    Position _caret;
    Position _anchor;

    /// The column the caret would like to be in when it moves up or down.
    ///
    /// **Remembered across vertical movement, and reset by anything else.**
    /// Moving down from column 40 through a short line and on to a long one
    /// puts the caret back at 40, which is what every editor does and what
    /// nobody notices until it is missing.
    nuint _wanted;
    bool _keepWanted;

    /// The first line shown, and the first column.
    nuint _topLine;
    nuint _leftColumn;

    ScrollBar _down;
    ScrollBar _across;

    /// The width of one character and the height of one line, measured once
    /// from the font. Zero until the first paint, which is the first time there
    /// is a `Graphics` to measure with.
    int _cell;
    int _lineHeight;
    /// The width of the line-number gutter, including the gap after it.
    int _gutter;

    /// True while the mouse is down, so that moving it extends the selection.
    bool _dragging;

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
    bool _ready;

    public CodeEditor(WindowedControl parent)
    {
        base(parent);
        _doc = new Document();
        _palette = Theme.Light();
        _caret = Position.At(0u, 0u);
        _anchor = _caret;
        _wanted = 0u;
        _keepWanted = false;
        _topLine = 0u;
        _leftColumn = 0u;
        _cell = 0;
        _lineHeight = 0;
        _gutter = 0;
        _dragging = false;
        _ready = false;

        Border = ControlBorder.Sunken;
        Font = new Font(MonospaceFamily, DefaultTextSize);
        BackColor = _palette.Background;
        Cursor = CursorKind.Text;

        _down = new ScrollBar(this, true);
        _down.ValueChanged += this.OnScrolledDown;
        _across = new ScrollBar(this, false);
        _across.ValueChanged += this.OnScrolledAcross;

        _ready = true;
        Rescrolled();
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
    /// **`cell` back to zero rather than a remeasure here.** There is no
    /// `Graphics` outside a paint, and the next paint begins by measuring
    /// whenever `cell` is zero -- so this says "unknown" and the one place that
    /// knows how to find out does the work.
    protected override void OnFontChanged()
    {
        _cell = 0;
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
    public Document Contents => _doc;

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
    public Position CaretPosition => _caret;

    /// The first line showing, counting from zero.
    public nuint TopLine => _topLine;

    /// How many whole lines fit in the control as it is now.
    public int VisibleLineCount => VisibleLines;

    /// Whether anything is selected.
    public bool HasSelection => !_caret.SameAs(_anchor);

    /// The selected text, or `""`.
    public String SelectedText
    {
        get
        {
            if (!HasSelection)
                return "";
            return _doc.TextBetween(_anchor, _caret);
        }
    }

    /// Replaces the document. The caret goes to the top and the view with it.
    public void SetDocument(Document replacement)
    {
        _doc = replacement;
        _caret = Position.At(0u, 0u);
        _anchor = _caret;
        _topLine = 0u;
        _leftColumn = 0u;
        Rescrolled();
        Invalidate();
        OnCaretMoved();
    }

    /// Puts the caret on a line, scrolls it into view, and selects nothing.
    ///
    /// What an error in the output pane does when it is double-clicked, and the
    /// reason this is public.
    public void GoTo(nuint row, nuint column)
    {
        nuint line = row >= _doc.LineCount ? _doc.LineCount - 1u : row;
        _caret = Position.At(line, ClampColumn(line, column));
        _anchor = _caret;
        // Roughly a third of the way down, rather than at the very top: an
        // error is nearly always about the lines above it as well.
        nuint visible = (nuint)VisibleLines;
        _topLine = line > visible / 3u ? line - visible / 3u : 0u;
        Rescrolled();
        ShowCaret();
        Invalidate();
        OnCaretMoved();
    }

    /// Raised whenever the caret moves, so a status bar can say where it is.
    public event EventHandler CaretMoved;
    protected virtual void OnCaretMoved() => CaretMoved(this);

    /// Raised whenever the text changes.
    public event EventHandler Edited;
    protected virtual void OnEdited() => Edited(this);

    // ----------------------------------------------------- columns and bytes

    /// The screen column a byte offset sits at, with tabs expanded.
    ///
    /// One of the two places in this file where a byte offset and a column
    /// differ. Walks the line, which is O(its length) -- and a line is short.
    public nuint ColumnOf(String line, nuint offset)
    {
        nuint column = 0u;
        nuint at = 0u;
        nuint size = line.ByteLength();
        while (at < offset && at < size)
        {
            if (line.ByteAt(at) == (byte)'\t')
            {
                column = column + (TabWidth - column % TabWidth);
                at++;
            }
            else
            {
                column++;
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
    public nuint OffsetOfColumn(String line, nuint column)
    {
        nuint at = 0u;
        nuint seen = 0u;
        nuint size = line.ByteLength();
        while (at < size)
        {
            nuint next = seen;
            if (line.ByteAt(at) == (byte)'\t')
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
            at = line.ByteAt(at) == (byte)'\t' ? at + 1u : line.NextCodePoint(at);
        }
        return size;
    }

    /// How wide a line is, in columns.
    nuint WidthOf(String line) => ColumnOf(line, line.ByteLength());

    nuint ClampColumn(nuint row, nuint column)
    {
        nuint size = _doc.LengthAt(row);
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
            if (_cell <= 0)
                return 1;
            int width = ClientBounds.Width - _gutter - ScrollThickness;
            int fits = width / _cell;
            return fits < 1 ? 1 : fits;
        }
    }

    int ScrollThickness => 16;

    /// Puts the scroll bars where they belong and tells them what they are
    /// scrolling. Called on every resize and after every edit.
    void Rescrolled()
    {
        if (!_ready)
            return;
        var area = ClientBounds;
        int bar = ScrollThickness;

        _down.SetBounds(area.Width - bar, 0, bar, area.Height - bar);
        _across.SetBounds(0, area.Height - bar, area.Width - bar, bar);

        int lines = (int)_doc.LineCount;
        int page = VisibleLines;
        _down.Maximum = lines > page ? lines - 1 : 0;
        _down.PageSize = page;
        _down.Value = (int)_topLine;

        // The widest line on screen, rather than in the file: scanning every
        // line of a large file on every keystroke to find the longest is the
        // one thing here that would be O(the file), and what it buys is a
        // horizontal thumb of exactly the right size.
        int widest = 0;
        nuint last = _topLine + (nuint)page;
        if (last > _doc.LineCount)
            last = _doc.LineCount;
        for (nuint i = _topLine; i < last; i++)
        {
            int width = (int)WidthOf(_doc.TextAt(i));
            if (width > widest)
                widest = width;
        }
        int columns = VisibleColumns;
        _across.Maximum = widest > columns ? widest - 1 : 0;
        _across.PageSize = columns;
        _across.Value = (int)_leftColumn;
    }

    protected override void OnResize()
    {
        if (_ready)
            Rescrolled();
        base.OnResize();
    }

    void OnScrolledDown(Control sender)
    {
        nuint to = (nuint)_down.Value;
        if (to == _topLine)
            return;
        _topLine = to;
        Invalidate();
    }

    void OnScrolledAcross(Control sender)
    {
        nuint to = (nuint)_across.Value;
        if (to == _leftColumn)
            return;
        _leftColumn = to;
        Invalidate();
    }

    /// Scrolls so the caret is on screen. Does nothing when it already is,
    /// which is the common case and the reason typing does not repaint the
    /// whole control.
    void ShowCaret()
    {
        nuint lines = (nuint)VisibleLines;
        if (_caret.Row < _topLine)
        {
            _topLine = _caret.Row;
        }
        else if (_caret.Row >= _topLine + lines)
        {
            _topLine = _caret.Row - lines + 1u;
        }

        nuint column = ColumnOf(_doc.TextAt(_caret.Row), _caret.Column);
        nuint columns = (nuint)VisibleColumns;
        if (column < _leftColumn)
        {
            _leftColumn = column;
        }
        else if (column >= _leftColumn + columns)
        {
            _leftColumn = column - columns + 1u;
        }

        Rescrolled();
    }

    // -------------------------------------------------------------- drawing

    protected override void OnPaint(PaintEventArgs args)
    {
        if (!_ready)
            return;
        var canvas = args.Graphics;

        // Measured once, from the font, the first time there is something to
        // measure with. `M` rather than a space: a space is the one character a
        // few fixed-width faces still report as narrower than the rest.
        if (_cell <= 0)
        {
            var size = canvas.MeasureString("M", Font);
            _cell = size.Width;
            _lineHeight = size.Height;
            if (_cell <= 0)
                _cell = 8;
            if (_lineHeight <= 0)
                _lineHeight = 14;
            Rescrolled();
        }

        _gutter = GutterWidth(canvas);

        var area = ClientBounds;
        canvas.Clear(_palette.Background);
        canvas.FillRectangle(new Brush(_palette.GutterBack),
                             Rectangle.Of(0, 0, _gutter, area.Height));

        // The rule at column 80, drawn under the text rather than over it.
        int rule = _gutter + (int)(RightMargin - _leftColumn) * _cell;
        if (rule > _gutter && rule < area.Width)
        {
            canvas.DrawLine(new Pen(_palette.Margin), rule, 0, rule, area.Height);
        }

        nuint lines = _doc.LineCount;
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
    int GutterWidth(Graphics canvas)
    {
        nuint count = _doc.LineCount;
        int digits = 1;
        while (count >= 10u)
        {
            count = count / 10u;
            digits++;
        }
        if (digits < 3)
            digits = 3;
        return (digits + 2) * _cell;
    }

    void PaintLine(Graphics canvas, nuint row, int y, int width)
    {
        var line = _doc.LineAt(row);
        bool current = row == _caret.Row;

        if (current && !HasSelection)
        {
            canvas.FillRectangle(new Brush(_palette.CurrentLine),
                                 Rectangle.Of(_gutter, y, width - _gutter, _lineHeight));
        }

        PaintSelection(canvas, row, y, width);

        // The number, right-aligned in the gutter.
        String number = Standard.Text.FromInteger(row + 1u);
        int numberX = _gutter - _cell - (int)number.ByteLength() * _cell;
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

            nuint column = ColumnOf(line.Text, token.Start);
            if (column + token.Length < _leftColumn)
                continue;

            int x = _gutter + (int)(column - _leftColumn) * _cell;
            if (x > width)
                break;

            String piece = line.Text.Substring(token.Start, token.Length);
            canvas.DrawString(piece, Font, _palette.ColorFor(token.Kind), x, y);
        }
    }

    /// The highlight behind whatever of this line is selected.
    void PaintSelection(Graphics canvas, nuint row, int y, int width)
    {
        if (!HasSelection)
            return;

        var start = _anchor;
        var end = _caret;
        if (end.Before(start))
        {
            start = _caret;
            end = _anchor;
        }
        if (row < start.Row || row > end.Row)
            return;

        String text = _doc.TextAt(row);
        nuint from = row == start.Row ? ColumnOf(text, start.Column) : 0u;
        nuint to = row == end.Row ? ColumnOf(text, end.Column) : WidthOf(text) + 1u;

        // A line wholly inside the selection is highlighted one column past its
        // end, which is what shows that the line break is selected too.
        if (to <= from)
            return;
        if (from < _leftColumn)
            from = _leftColumn;

        int x = _gutter + (int)(from - _leftColumn) * _cell;
        int span = (int)(to - from) * _cell;
        if (x + span > width)
            span = width - x;
        if (span <= 0)
            return;

        canvas.FillRectangle(new Brush(_palette.Selection),
                             Rectangle.Of(x, y, span, _lineHeight));
    }

    /// Puts the platform's caret where the text caret is, or takes it away when
    /// it has scrolled off.
    void PlaceCaret()
    {
        if (_caret.Row < _topLine || _caret.Row >= _topLine + (nuint)VisibleLines + 1u)
        {
            Caret = Rectangle.Empty;
            return;
        }
        nuint column = ColumnOf(_doc.TextAt(_caret.Row), _caret.Column);
        if (column < _leftColumn)
        {
            Caret = Rectangle.Empty;
            return;
        }
        int x = _gutter + (int)(column - _leftColumn) * _cell;
        int y = (int)(_caret.Row - _topLine) * _lineHeight;
        Caret = Rectangle.Of(x, y, 2, _lineHeight);
    }

    // ------------------------------------------------------------ the mouse

    protected override void OnMouseDown(MouseEventArgs args)
    {
        if (!_ready)
            return;
        Focus();
        var hit = PositionAt(args.X, args.Y);
        _caret = hit;
        if (!args.Modifiers.HasFlag(ModifierKeys.Shift))
            _anchor = hit;
        _dragging = true;
        CaptureMouse(true);
        _keepWanted = false;
        ShowCaret();
        Invalidate();
        OnCaretMoved();
        base.OnMouseDown(args);
    }

    protected override void OnMouseMove(MouseEventArgs args)
    {
        if (!_ready)
            return;
        if (_dragging)
        {
            _caret = PositionAt(args.X, args.Y);
            ShowCaret();
            Invalidate();
            OnCaretMoved();
        }
        base.OnMouseMove(args);
    }

    protected override void OnMouseUp(MouseEventArgs args)
    {
        if (!_ready)
            return;
        if (_dragging)
        {
            _dragging = false;
            CaptureMouse(false);
        }
        base.OnMouseUp(args);
    }

    protected override void OnMouseWheel(MouseEventArgs args)
    {
        if (!_ready)
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
        int highest = (int)_doc.LineCount - 1;
        if (to > highest)
            to = highest;
        if ((nuint)to == _topLine)
            return;
        _topLine = (nuint)to;
        Rescrolled();
        Invalidate();
        base.OnMouseWheel(args);
    }

    /// What position a point in the control is over.
    Position PositionAt(int x, int y)
    {
        if (_lineHeight <= 0 || _cell <= 0)
            return Position.At(0u, 0u);

        int row = y / _lineHeight + (int)_topLine;
        if (row < 0)
            row = 0;
        nuint highest = _doc.LineCount - 1u;
        nuint line = (nuint)row > highest ? highest : (nuint)row;

        int column = (x - _gutter) / _cell + (int)_leftColumn;
        if (column < 0)
            column = 0;
        return Position.At(line, OffsetOfColumn(_doc.TextAt(line), (nuint)column));
    }

    // --------------------------------------------------------- the keyboard

    protected override void OnKeyDown(KeyEventArgs args)
    {
        if (!_ready)
            return;
        bool shift = args.Shift;
        bool control = args.Control;
        bool moved = true;

        if (args.Key == Key.Left)
        {
            MoveLeft(shift, control);
        }
        else if (args.Key == Key.Right)
        {
            MoveRight(shift, control);
        }
        else if (args.Key == Key.Up)
        {
            MoveVertically(-1, shift);
        }
        else if (args.Key == Key.Down)
        {
            MoveVertically(1, shift);
        }
        else if (args.Key == Key.PageUp)
        {
            MoveVertically(-VisibleLines, shift);
        }
        else if (args.Key == Key.PageDown)
        {
            MoveVertically(VisibleLines, shift);
        }
        else if (args.Key == Key.Home)
        {
            MoveHome(shift, control);
        }
        else if (args.Key == Key.End)
        {
            MoveEnd(shift, control);
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
        else if (args.Key == Key.Backspace)
        {
            DeleteBack();
            moved = false;
        }
        else if (args.Key == Key.Delete)
        {
            DeleteForward();
            moved = false;
        }
        else if (args.Key == Key.Enter)
        {
            Type("\n");
            moved = false;
        }
        else if (args.Key == Key.Tab)
        {
            Indent(shift);
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
            ShowCaret();
            Invalidate();
            OnCaretMoved();
        }
        base.OnKeyDown(args);
    }

    protected override void OnKeyPress(KeyPressEventArgs args)
    {
        if (!_ready)
            return;
        // Everything below a space is a control code, and each one that means
        // something has already been dealt with as a key. Ctrl+V arrives here a
        // second time as character 22, which is exactly why that test is a
        // range and not a list of the ones we happen to have thought of.
        if (args.KeyChar >= ' ')
            Type(Standard.Text.FromChar((char32)args.KeyChar));
        base.OnKeyPress(args);
    }

    // ------------------------------------------------------------- movement

    /// Collapses the selection unless the shift key is holding it open.
    void Settle(bool shift)
    {
        if (!shift)
            _anchor = _caret;
        if (!_keepWanted)
            _wanted = ColumnOf(_doc.TextAt(_caret.Row), _caret.Column);
        _keepWanted = false;
    }

    void MoveLeft(bool shift, bool word)
    {
        // An unheld selection collapses to its near end rather than moving,
        // which is what every editor does and what makes Left after a drag
        // predictable.
        if (!shift && HasSelection)
        {
            _caret = _anchor.Before(_caret) ? _anchor : _caret;
            _anchor = _caret;
            Settle(false);
            return;
        }

        if (_caret.Column > 0u)
        {
            String line = _doc.TextAt(_caret.Row);
            _caret = Position.At(_caret.Row,
                                word ? WordLeft(line, _caret.Column) : StepLeft(line, _caret.Column));
        }
        else if (_caret.Row > 0u)
        {
            _caret = Position.At(_caret.Row - 1u, _doc.LengthAt(_caret.Row - 1u));
        }
        Settle(shift);
    }

    void MoveRight(bool shift, bool word)
    {
        if (!shift && HasSelection)
        {
            _caret = _anchor.Before(_caret) ? _caret : _anchor;
            _anchor = _caret;
            Settle(false);
            return;
        }

        String line = _doc.TextAt(_caret.Row);
        if (_caret.Column < line.ByteLength())
        {
            _caret = Position.At(_caret.Row,
                                word ? WordRight(line, _caret.Column) : line.NextCodePoint(_caret.Column));
        }
        else if (_caret.Row + 1u < _doc.LineCount)
        {
            _caret = Position.At(_caret.Row + 1u, 0u);
        }
        Settle(shift);
    }

    void MoveVertically(int by, bool shift)
    {
        int row = (int)_caret.Row + by;
        if (row < 0)
            row = 0;
        int highest = (int)_doc.LineCount - 1;
        if (row > highest)
            row = highest;

        // The column the caret would like to be in is remembered across a run
        // of vertical movements, so a short line in the middle does not drag it
        // permanently left.
        _caret = Position.At((nuint)row, OffsetOfColumn(_doc.TextAt((nuint)row), _wanted));
        _keepWanted = true;
        Settle(shift);
    }

    /// Home goes to the first non-blank of the line, and to column zero when it
    /// is already there. The one movement whose two meanings are both wanted.
    void MoveHome(bool shift, bool document)
    {
        if (document)
        {
            _caret = Position.At(0u, 0u);
            Settle(shift);
            return;
        }

        String line = _doc.TextAt(_caret.Row);
        nuint first = 0u;
        while (first < line.ByteLength())
        {
            byte c = line.ByteAt(first);
            if (c != (byte)' ' && c != (byte)'\t')
                break;
            first++;
        }
        _caret = Position.At(_caret.Row, _caret.Column == first ? 0u : first);
        Settle(shift);
    }

    void MoveEnd(bool shift, bool document)
    {
        if (document)
        {
            nuint end = _doc.LineCount - 1u;
            _caret = Position.At(end, _doc.LengthAt(end));
        }
        else
        {
            _caret = Position.At(_caret.Row, _doc.LengthAt(_caret.Row));
        }
        Settle(shift);
    }

    nuint StepLeft(String line, nuint offset)
    {
        nuint at = 0u;
        nuint last = 0u;
        while (at < offset)
        {
            last = at;
            at = line.NextCodePoint(at);
        }
        return last;
    }

    /// The start of the word to the left: past any run of spaces, then past the
    /// run of word bytes before that.
    nuint WordLeft(String line, nuint offset)
    {
        nuint at = StepLeft(line, offset);
        while (at > 0u && IsSpace(line.ByteAt(at)))
            at = StepLeft(line, at);
        if (at == 0u)
            return 0u;
        if (!IsWord(line.ByteAt(at)))
            return at;
        while (at > 0u)
        {
            nuint back = StepLeft(line, at);
            if (!IsWord(line.ByteAt(back)))
                return at;
            at = back;
        }
        return 0u;
    }

    nuint WordRight(String line, nuint offset)
    {
        nuint size = line.ByteLength();
        nuint at = offset;
        if (at < size && IsWord(line.ByteAt(at)))
        {
            while (at < size && IsWord(line.ByteAt(at)))
            {
                at = line.NextCodePoint(at);
            }
        }
        else if (at < size)
        {
            at = line.NextCodePoint(at);
        }
        while (at < size && IsSpace(line.ByteAt(at)))
            at = line.NextCodePoint(at);
        return at;
    }

    bool IsSpace(byte c) => c == (byte)' ' || c == (byte)'\t';

    bool IsWord(byte c)
    {
        return (c >= (byte)'a' && c <= (byte)'z')
            || (c >= (byte)'A' && c <= (byte)'Z')
            || (c >= (byte)'0' && c <= (byte)'9')
            || c == (byte)'_' || c >= 0x80u;
    }

    // -------------------------------------------------------------- editing

    /// Selects the whole file.
    public void SelectAll()
    {
        _anchor = Position.At(0u, 0u);
        nuint end = _doc.LineCount - 1u;
        _caret = Position.At(end, _doc.LengthAt(end));
        _keepWanted = false;
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
        _caret = _doc.Delete(_anchor, _caret);
        _anchor = _caret;
        AfterEdit();
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
        Type(text);
        return true;
    }

    /// Puts text in, replacing the selection if there is one.
    public void Type(String text)
    {
        if (HasSelection)
            _caret = _doc.Delete(_anchor, _caret);
        _caret = _doc.Insert(_caret, text);
        _anchor = _caret;
        AfterEdit();
    }

    void DeleteBack()
    {
        if (HasSelection)
        {
            _caret = _doc.Delete(_anchor, _caret);
        }
        else if (_caret.Column > 0u)
        {
            nuint back = StepLeft(_doc.TextAt(_caret.Row), _caret.Column);
            _caret = _doc.Delete(Position.At(_caret.Row, back), _caret);
        }
        else if (_caret.Row > 0u)
        {
            var joinAt = Position.At(_caret.Row - 1u, _doc.LengthAt(_caret.Row - 1u));
            _caret = _doc.Delete(joinAt, _caret);
        }
        else
        {
            return;
        }
        _anchor = _caret;
        AfterEdit();
    }

    void DeleteForward()
    {
        if (HasSelection)
        {
            _caret = _doc.Delete(_anchor, _caret);
        }
        else if (_caret.Column < _doc.LengthAt(_caret.Row))
        {
            nuint next = _doc.TextAt(_caret.Row).NextCodePoint(_caret.Column);
            _caret = _doc.Delete(_caret, Position.At(_caret.Row, next));
        }
        else if (_caret.Row + 1u < _doc.LineCount)
        {
            _caret = _doc.Delete(_caret, Position.At(_caret.Row + 1u, 0u));
        }
        else
        {
            return;
        }
        _anchor = _caret;
        AfterEdit();
    }

    /// Tab, which means two different things and the selection says which.
    ///
    /// With nothing selected it inserts spaces to the next tab stop -- spaces
    /// rather than a tab, because that is what the sources this edits use, and
    /// an editor that inserted the other kind would make every file it touched
    /// inconsistent with itself.
    void Indent(bool back)
    {
        if (!HasSelection && !back)
        {
            nuint column = ColumnOf(_doc.TextAt(_caret.Row), _caret.Column);
            nuint spaces = TabWidth - column % TabWidth;
            Type(" ".Repeat(spaces));
            return;
        }

        var start = _anchor;
        var end = _caret;
        if (end.Before(start))
        {
            start = _caret;
            end = _anchor;
        }

        for (nuint row = start.Row; row <= end.Row; row++)
        {
            String line = _doc.TextAt(row);
            if (back)
            {
                nuint strip = 0u;
                while (strip < TabWidth && strip < line.ByteLength()
                       && line.ByteAt(strip) == (byte)' ')
                {
                    strip++;
                }
                if (strip > 0u)
                {
                    _doc.Delete(Position.At(row, 0u), Position.At(row, strip));
                }
            }
            else if (line.ByteLength() > 0u)
            {
                _doc.Insert(Position.At(row, 0u), " ".Repeat(TabWidth));
            }
        }

        // The selection keeps covering the same lines, whole.
        _anchor = Position.At(start.Row, 0u);
        _caret = Position.At(end.Row, _doc.LengthAt(end.Row));
        AfterEdit();
    }

    void AfterEdit()
    {
        _keepWanted = false;
        _wanted = ColumnOf(_doc.TextAt(_caret.Row), _caret.Column);
        Rescrolled();
        ShowCaret();
        Invalidate();
        OnCaretMoved();
        OnEdited();
    }
}
