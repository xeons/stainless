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

// The controls with no window of their own: `PaintBox`, `Shape`, `Bevel` and
// `Splitter`.
//
// All four are `GraphicControl`s, which is the half of the LCL's control split
// that has not earned its keep until now. Each costs a `Control` object and
// nothing else -- no kernel window, no message queue slot, no z-order entry --
// and each is drawn by its parent during the parent's own `WM_PAINT`, in a
// layer that gives it its own coordinates and clips it to its bounds.
//
// `PaintBox` is the one that matters most: it is how a program draws anything
// at all, and everything else here is a worked example of it.
module Forms;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;

// ================================================================= paint box

/// A rectangle the program draws in.
///
/// ```
/// var canvas = new PaintBox(this);
/// canvas.SetBounds(10, 10, 200, 120);
/// canvas.Paint += this.OnDraw;
///
/// void OnDraw(Control sender, PaintEventArgs args) {
///     args.Graphics.FillRectangle(new Brush(Colors.White), args.ClipRectangle);
///     args.Graphics.DrawLine(new Pen(Colors.Navy), 0, 0, 200, 120);
/// }
/// ```
///
/// **The coordinates are the box's own.** (0, 0) is its top-left corner
/// wherever it sits on the form, and nothing drawn outside its bounds appears.
public class PaintBox : GraphicControl
{
    public PaintBox(WindowedControl parent) => base(parent);
}

// ===================================================================== shape

/// Which shape a `Shape` draws.
public enum ShapeKind { Rectangle, RoundRectangle, Ellipse, Circle, Square }

/// A geometric shape, drawn from a `Pen` and a `Brush`.
///
/// `TShape` with the same members under the same names, less `TBrushStyle` --
/// there is one brush here and it is solid.
public class Shape : GraphicControl
{
    ShapeKind _kind;
    Color _fillColor;
    Color _lineColor;
    int _lineWidth;

    public Shape(WindowedControl parent)
    {
        base(parent);
        _kind = ShapeKind.Rectangle;
        _fillColor = Colors.White;
        _lineColor = Colors.Black;
        _lineWidth = 1;
    }

    public ShapeKind Kind
    {
        get => _kind;
        set
        {
            _kind = value;
            Invalidate();
        }
    }

    public Color FillColor
    {
        get => _fillColor;
        set
        {
            _fillColor = value;
            Invalidate();
        }
    }

    public Color LineColor
    {
        get => _lineColor;
        set
        {
            _lineColor = value;
            Invalidate();
        }
    }

    public int LineWidth
    {
        get => _lineWidth;
        set
        {
            _lineWidth = value;
            Invalidate();
        }
    }

    protected override void OnPaint(PaintEventArgs args)
    {
        var surface = args.Graphics;
        var brush = new Brush(_fillColor);
        var pen = new Pen(_lineColor, _lineWidth, PenStyle.Solid);

        // A square and a circle are the same shapes fitted to the shorter side,
        // which is what makes them worth having as separate kinds rather than
        // leaving a caller to keep the bounds square by hand.
        var area = Rectangle.FromBounds(0, 0, Width, Height);
        if (_kind == ShapeKind.Circle || _kind == ShapeKind.Square)
        {
            int side = area.Width < area.Height ? area.Width : area.Height;
            area = Rectangle.FromBounds((area.Width - side) / 2, (area.Height - side) / 2,
                                side, side);
        }

        if (_kind == ShapeKind.Ellipse || _kind == ShapeKind.Circle)
        {
            surface.FillEllipse(brush, area);
            surface.DrawEllipse(pen, area);
        }
        else
        {
            surface.FillRectangle(brush, area);
            surface.DrawRectangle(pen, area);
        }

        base.OnPaint(args);
    }
}

// ===================================================================== bevel

/// What a `Bevel` draws.
public enum BevelKind { Box, Frame, TopLine, BottomLine, LeftLine, RightLine }

/// Whether a bevel stands out or is cut in.
public enum BevelStyle { Lowered, Raised }

/// A line or a frame, for dividing a form up.
///
/// Two lines of contrasting colour, which is the whole of what a bevel is and
/// what `TBevel` does with `clBtnShadow` and `clBtnHighlight`.
public class Bevel : GraphicControl
{
    BevelKind _kind;
    BevelStyle _style;

    public Bevel(WindowedControl parent)
    {
        base(parent);
        _kind = BevelKind.Box;
        _style = BevelStyle.Lowered;
    }

    public BevelKind Kind
    {
        get => _kind;
        set
        {
            _kind = value;
            Invalidate();
        }
    }

    public BevelStyle Style
    {
        get => _style;
        set
        {
            _style = value;
            Invalidate();
        }
    }

    protected override void OnPaint(PaintEventArgs args)
    {
        var surface = args.Graphics;
        // Lowered means the shadow is on top and the highlight below; raised is
        // the same two lines the other way round. That is the only difference
        // between the two, and it is why there is no third case.
        var first = new Pen(_style == BevelStyle.Lowered
            ? SystemColors.ControlDark : SystemColors.ControlLight);
        var second = new Pen(_style == BevelStyle.Lowered
            ? SystemColors.ControlLight : SystemColors.ControlDark);

        int right = Width - 1;
        int bottom = Height - 1;

        if (_kind == BevelKind.TopLine)
        {
            surface.DrawLine(first, 0, 0, right, 0);
            surface.DrawLine(second, 0, 1, right, 1);
        }
        else if (_kind == BevelKind.BottomLine)
        {
            surface.DrawLine(first, 0, bottom - 1, right, bottom - 1);
            surface.DrawLine(second, 0, bottom, right, bottom);
        }
        else if (_kind == BevelKind.LeftLine)
        {
            surface.DrawLine(first, 0, 0, 0, bottom);
            surface.DrawLine(second, 1, 0, 1, bottom);
        }
        else if (_kind == BevelKind.RightLine)
        {
            surface.DrawLine(first, right - 1, 0, right - 1, bottom);
            surface.DrawLine(second, right, 0, right, bottom);
        }
        else
        {
            surface.DrawLine(first, 0, 0, right, 0);
            surface.DrawLine(first, 0, 0, 0, bottom);
            surface.DrawLine(second, 0, bottom, right, bottom);
            surface.DrawLine(second, right, 0, right, bottom);
        }

        base.OnPaint(args);
    }
}

// ================================================================== splitter

/// A bar the user drags to resize the control beside it.
///
/// **It moves its neighbour, not itself.** A splitter is docked to an edge like
/// anything else; what it resizes is whichever docked control sits on the side
/// it was docked to, which is the one the layout pass gave the space to just
/// before the splitter took its own. That is `TSplitter`'s rule, and it is why
/// a splitter is placed *after* the control it splits.
///
/// ```
/// var tree = new TreeView(this);  tree.Dock = DockStyle.Left;  tree.Width = 200;
/// var bar  = new Splitter(this);  bar.Dock  = DockStyle.Left;
/// var page = new TextBox(this);   page.Dock = DockStyle.Fill;
/// ```
public class Splitter : GraphicControl
{
    bool _dragging;
    Point _grabbed;
    int _startedAt;
    int _minimumSize;

    public Splitter(WindowedControl parent)
    {
        base(parent);
        _dragging = false;
        _grabbed = Point.Empty;
        _startedAt = 0;
        _minimumSize = 40;
        Dock = DockStyle.Left;
        Width = 5;
        Height = 5;
        ChooseCursor();
    }

    /// The smallest the neighbour may be dragged to.
    public int MinimumSize
    {
        get => _minimumSize;
        set => _minimumSize = value;
    }

    /// Which control this splitter resizes: the visible one docked to the same
    /// edge immediately before it.
    Control? FindNeighbor()
    {
        var parent = Parent;
        if (parent == null)
            return null;
        var siblings = ((WindowedControl)parent).Controls;
        Control? previous = null;
        foreach (var child in siblings)
        {
            if (child == this)
                return previous;
            if (child.Dock == Dock && child.Visible)
                previous = child;
        }
        return null;
    }

    bool IsHorizontal => Dock == DockStyle.Left || Dock == DockStyle.Right;

    /// The largest the neighbour may be dragged to: the parent's extent less
    /// every other visible control docked on the same axis, this one included.
    /// Beyond it the neighbour would push the splitter out of the parent.
    int GetLargestSizeFor(Control beside)
    {
        var parent = Parent;
        if (parent == null)
            return _minimumSize;
        var holder = (WindowedControl)parent;
        var room = holder.ClientBounds;
        int most = IsHorizontal ? room.Width : room.Height;
        foreach (var child in holder.Controls)
        {
            if (child == beside || !child.Visible)
                continue;
            var edge = child.Dock;
            if (IsHorizontal && (edge == DockStyle.Left || edge == DockStyle.Right))
                most -= child.Width;
            if (!IsHorizontal && (edge == DockStyle.Top || edge == DockStyle.Bottom))
                most -= child.Height;
        }
        return most;
    }

    /// The cursor follows the axis, which follows `Dock`. Asked on a resize
    /// and when the pointer arrives: `Dock` tells nothing it changed, and
    /// changing it need not change this control's size.
    void ChooseCursor()
    {
        var wanted = IsHorizontal ? CursorKind.SizeWestEast : CursorKind.SizeNorthSouth;
        if (Cursor != wanted)
            Cursor = wanted;
    }

    protected override void OnResize()
    {
        base.OnResize();
        ChooseCursor();
    }

    protected override void OnMouseEnter()
    {
        ChooseCursor();
        base.OnMouseEnter();
    }

    protected override void OnMouseDown(MouseEventArgs args)
    {
        base.OnMouseDown(args);
        if (args.Button != MouseButton.Left)
            return;
        var beside = FindNeighbor();
        if (beside == null)
            return;
        _dragging = true;
        // In the *parent's* coordinates, because that is the space the drag is
        // measured in and the splitter itself is about to move underneath it.
        _grabbed = Point.FromXY(Left + args.X, Top + args.Y);
        _startedAt = IsHorizontal ? ((Control)beside).Width : ((Control)beside).Height;
        CaptureMouse(true);
    }

    protected override void OnMouseMove(MouseEventArgs args)
    {
        base.OnMouseMove(args);
        if (!_dragging)
            return;
        var beside = FindNeighbor();
        if (beside == null)
            return;

        var now = Point.FromXY(Left + args.X, Top + args.Y);
        int moved = IsHorizontal ? now.X - _grabbed.X : now.Y - _grabbed.Y;
        // Dragging a right- or bottom-docked splitter grows its neighbour the
        // other way, since the neighbour's far edge is the one that is fixed.
        if (Dock == DockStyle.Right || Dock == DockStyle.Bottom)
            moved = -moved;

        var control = (Control)beside;
        int wanted = _startedAt + moved;
        int most = GetLargestSizeFor(control);
        if (wanted > most)
            wanted = most;
        if (wanted < _minimumSize)
            wanted = _minimumSize;

        if (IsHorizontal)
        {
            control.Width = wanted;
        }
        else
        {
            control.Height = wanted;
        }

        var parent = Parent;
        if (parent != null)
            ((WindowedControl)parent).PerformLayout();
    }

    protected override void OnMouseUp(MouseEventArgs args)
    {
        base.OnMouseUp(args);
        if (!_dragging)
            return;
        _dragging = false;
        CaptureMouse(false);
    }

    protected override void OnPaint(PaintEventArgs args)
    {
        // Nothing of its own: the parent's background shows through, which is
        // what a splitter looks like on every platform. The cursor is what says
        // it can be dragged.
        base.OnPaint(args);
    }
}
