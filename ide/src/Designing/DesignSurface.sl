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

// The form designer's surface: the form's real controls, and a transparent
// overlay over them that takes the pointer and draws the selection.
//
// Lazarus's arrangement. The controls are the ones the program will make, so
// what is shown is what will run; the overlay is `CustomControl.IsTransparent`,
// its designer DC.
module Ide.Designing;

import Standard.Collections;
import Standard.Math;
import Standard.Text;
import Forms;
import Forms.Drawing;
import Forms.Platform;
import Ide.Designer;

/// A component in the file, and the control made for it.
public class DesignedItem
{
    public FormComponent Component;

    /// The control, or for a component with no window its entry in the tray.
    public Control Live;

    /// A component with no window, made for the Properties grid to read and
    /// write. A `Timer` is the one kind today.
    public Timer? Held;

    public DesignedItem(FormComponent component, Control live)
    {
        Component = component;
        Live = live;
        Held = null;
    }

    public bool IsNonVisual => Held != null;

    /// What reflection reads and writes: the control, or the component.
    public byte* Target
    {
        get
        {
            var held = Held;
            return held == null ? (byte*)Live : (byte*)((Timer)held);
        }
    }
}

public closure void DesignChangedHandler();
public closure void DesignMessageHandler(String message);

/// What a drag is doing: moving the selection, sizing the one control
/// selected, or drawing a band to select what it touches.
enum DesignDrag { None, Moving, Sizing, Band }

/// A form, shown for editing.
///
/// Every change is made to the document first and the controls follow it, so
/// the document is always what would be saved. `Changed` is raised after each
/// one.
public class DesignSurface : Panel
{
    /// The grid positions snap to, in pixels.
    public const int GridStep = 8;

    /// How far the pointer moves before a press becomes a drag.
    const int DragThreshold = 4;

    /// The side of a grab handle, in pixels.
    const int HandleSize = 6;

    /// The nominal frame a form has around its client area, drawn here and
    /// taken off the form's `Bounds` to size the client.
    const int FrameSide = 8;
    const int FrameTop = 31;

    /// The tray's entries, one to a component with no window.
    const int TrayEntryWidth = 128;
    const int TrayHeight = 28;

    private FormDocument _document;
    private late Panel _frame;
    /// Below the form, the components with no window: Visual Studio's tray.
    private late Panel _tray;
    private late Label _caption;
    private late Panel _client;
    private late CustomControl _overlay;
    private List<DesignedItem> _items;

    /// What is selected, in the order it was chosen, and empty when the form
    /// itself is. The first is the one the Properties grid shows.
    private List<DesignedItem> _selection;

    private DesignDrag _drag;
    /// Whether the pointer has gone far enough for a press to be a drag.
    private bool _dragStarted;
    /// Which handle a resize is holding, 0 to 7 clockwise from the top left.
    private int _handle;
    private Point _dragFrom;
    /// Where each selected control was when the drag began, in the
    /// selection's order.
    private List<Rectangle> _boundsAtDrag;
    /// Where the drag last put each, as asked rather than as settled.
    private List<Rectangle> _draggedTo;
    /// The band being drawn, in the overlay's coordinates.
    private Rectangle _band;

    public DesignSurface(WindowedControl parent)
    {
        _items = new List<DesignedItem>();
        _selection = new List<DesignedItem>();
        PendingType = "";
        _boundsAtDrag = new List<Rectangle>();
        _draggedTo = new List<Rectangle>();
        _document = new FormDocument("", "", "Form");
        BaseDirectory = "";
        base(parent);
        BackColor = SystemColors.ControlDark;
        _drag = DesignDrag.None;
        _dragStarted = false;
        _handle = 0;
        _dragFrom = Point.Empty;
        _band = Rectangle.Empty;

        _frame = new Panel(this);
        _frame.BackColor = SystemColors.Highlight;
        _caption = new Label(_frame);
        _caption.ForeColor = SystemColors.HighlightText;
        _caption.BackColor = SystemColors.Highlight;
        _client = new Panel(_frame);
        _client.BackColor = SystemColors.Control;

        // The form is designed too, as in Lazarus: it paints under the
        // overlay like any of its controls.
        _client.IsDesigning = true;
        _client.Paint += this.OnLiveControlPaint;
        _overlay = CreateOverlay();

        _tray = new Panel(this);
        _tray.BackColor = SystemColors.Window;
        _tray.Visible = false;
    }

    /// Something a person asked for that the surface could not do, for the
    /// status line.
    public event DesignMessageHandler Message;

    /// The form file's directory, which a picture it names is relative to.
    public String BaseDirectory;

    /// Raised after every change to the document.
    public event DesignChangedHandler Changed;

    /// Raised when a different component is selected, or the form.
    public event DesignChangedHandler SelectionChanged;

    /// The type the next click on the form places, as the Toolbox names it,
    /// or empty for a click that selects.
    public String PendingType;

    /// A key the surface has no use for, passed on -- F12, F5 -- as the
    /// editor passes on the ones it has none for.
    public event KeyEventHandler KeyNotHandled;

    /// Gives the surface the keyboard, which is where Delete and the arrows
    /// act on the selection.
    public void FocusSurface() => _overlay.Focus();

    public FormDocument Document => _document;

    /// The first selected component, or null for the form.
    public FormComponent? SelectedComponent
    {
        get
        {
            var chosen = Primary;
            return chosen == null ? null : ((DesignedItem)chosen).Component;
        }
    }

    /// The live control of the first selected component, or null for the form
    /// and for a component with no window.
    public Control? SelectedLive
    {
        get
        {
            var chosen = Primary;
            if (chosen == null || ((DesignedItem)chosen).IsNonVisual)
                return null;
            return ((DesignedItem)chosen).Live;
        }
    }

    /// What the Properties grid reads and writes for the first selected
    /// component: its control, or the component; null for the form.
    public byte* SelectedTarget
    {
        get
        {
            var chosen = Primary;
            return chosen == null ? null : ((DesignedItem)chosen).Target;
        }
    }

    /// How many components are selected; none when the form is.
    public nuint SelectedCount => _selection.Count;

    /// Whether a component is one of those selected.
    public bool IsComponentSelected(String name)
    {
        foreach (var item in _selection)
        {
            if (item.Component.Name == name)
                return true;
        }
        return false;
    }

    private DesignedItem? Primary => _selection.IsEmpty ? null : _selection[0u];

    private bool IsSelected(DesignedItem item)
    {
        foreach (var each in _selection)
        {
            if (each == item)
                return true;
        }
        return false;
    }

    /// Whether something that contains an item is selected too, which moves
    /// and deletes the item with it.
    private bool IsInsideSelection(DesignedItem item)
    {
        foreach (var each in _selection)
        {
            if (each != item && IsInside(item.Live, each.Live))
                return true;
        }
        return false;
    }

    /// The live control made for a component, or null.
    public Control? FindLiveControl(String name)
    {
        foreach (var item in _items)
        {
            if (item.Component.Name == name)
                return item.Live;
        }
        return null;
    }

    public nuint ItemCount => _items.Count;

    // ------------------------------------------------------------ loading

    /// Shows a document, replacing whatever was shown. Answers the names of
    /// the controls whose type the designer cannot make, which are kept in
    /// the file and not shown.
    public List<String> LoadDocument(FormDocument document)
    {
        _document = document;
        _selection.Clear();
        foreach (var item in _items)
        {
            var parent = item.Live.Parent;
            if (parent != null)
                ((WindowedControl)parent).RemoveControl(item.Live);
        }
        _items.Clear();

        // The overlay is made again rather than raised: a control is only in
        // front of the siblings made before it, on either platform, and GTK
        // restacks a raised one by taking it out and putting it back.
        _client.RemoveControl(_overlay);

        var unknown = new List<String>();
        ApplyFormProperties();
        CreateDesignedChildren(document.Form, _client, unknown);
        _overlay = CreateOverlay();
        LayOutTray();
        return unknown;
    }

    /// The entries of the components with no window, in the file's order,
    /// along a strip under the form; hidden when there are none.
    private void LayOutTray()
    {
        int x = 4;
        foreach (var item in _items)
        {
            if (!item.IsNonVisual)
                continue;
            item.Live.SetBounds(x, 4, TrayEntryWidth, TrayHeight - 8);
            x += TrayEntryWidth + 4;
        }
        _tray.Visible = x > 4;
        Rectangle frame = _frame.Bounds;
        _tray.SetBounds(frame.X, frame.Bottom + GridStep, Math.Max(frame.Width, x), TrayHeight);
    }

    /// A tray entry: the component's name and type, highlighted when it is
    /// selected. A click selects it as a click on a control does.
    private WindowedControl CreateTrayEntry()
    {
        var entry = new CustomControl(_tray);
        entry.Paint += this.OnTrayEntryPaint;
        entry.MouseDown += this.OnTrayEntryMouseDown;
        return entry;
    }

    private DesignedItem? FindTrayItem(Control entry)
    {
        foreach (var item in _items)
        {
            if (item.Live == entry)
                return item;
        }
        return null;
    }

    private void OnTrayEntryPaint(Control sender, PaintEventArgs args)
    {
        var found = FindTrayItem(sender);
        if (found == null)
            return;
        var item = (DesignedItem)found;
        bool chosen = IsSelected(item);
        args.Graphics.FillRectangle(new Brush(chosen ? SystemColors.Highlight : SystemColors.Control),
                                    Rectangle.FromBounds(0, 0, sender.Bounds.Width, sender.Bounds.Height));
        args.Graphics.DrawString(item.Component.Name + " : " + item.Component.TypeName, sender.Font,
                                 chosen ? SystemColors.HighlightText : SystemColors.ControlText, 6, 2);
    }

    private void OnTrayEntryMouseDown(Control sender, MouseEventArgs args)
    {
        var found = FindTrayItem(sender);
        if (found == null)
            return;
        var item = (DesignedItem)found;
        _overlay.Focus();
        bool adding = args.Modifiers.HasFlag(ModifierKeys.Shift) || args.Modifiers.HasFlag(ModifierKeys.Control);
        if (!adding)
            _selection.Clear();
        if (IsSelected(item))
            _selection.RemoveAll((each) => each == item);
        else
            _selection.Add(item);
        RefreshSelection();
    }

    /// Shows a change of selection: the handles, the tray, the page a
    /// selected control is on, and the Properties grid.
    private void RefreshSelection()
    {
        ShowSelectedPage();
        _overlay.Invalidate();
        foreach (var item in _items)
        {
            if (item.IsNonVisual)
                item.Live.Invalidate();
        }
        SelectionChanged();
    }

    /// Brings forward every page the first selected control is on, so a
    /// control on a page behind another can be seen once it is chosen.
    private void ShowSelectedPage()
    {
        var chosen = Primary;
        if (chosen == null || ((DesignedItem)chosen).IsNonVisual)
            return;
        Control? walk = ((DesignedItem)chosen).Live;
        while (walk != null && walk != _client)
        {
            if (walk is TabPage page && page.Parent is TabControl tabs && tabs.SelectedIndex != page.Index)
                tabs.SelectedIndex = page.Index;
            walk = ((Control)walk).Parent;
        }
    }

    /// Whether a control can be seen: it and everything it is inside are
    /// visible, which a page behind another is not.
    private bool IsShown(DesignedItem item)
    {
        if (item.IsNonVisual)
            return false;
        Control? walk = item.Live;
        while (walk != null && walk != _client)
        {
            if (!((Control)walk).Visible)
                return false;
            walk = ((Control)walk).Parent;
        }
        return true;
    }

    private CustomControl CreateOverlay()
    {
        // Bounds and anchors rather than `Dock.Fill`, which would give it only
        // what the form's own docked controls leave.
        var overlay = new CustomControl(_client);
        overlay.IsTransparent = true;
        Rectangle area = _client.ClientBounds;
        overlay.SetBounds(0, 0, area.Width, area.Height);
        overlay.Anchors = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom;
        overlay.Paint += this.OnOverlayPaint;
        overlay.MouseDown += this.OnOverlayMouseDown;
        overlay.MouseMove += this.OnOverlayMouseMove;
        overlay.MouseUp += this.OnOverlayMouseUp;
        overlay.KeyDown += this.OnOverlayKeyDown;
        overlay.BringToFront();
        return overlay;
    }

    /// Shows the form's own properties again from the document: its title
    /// and its size, which are all a surface shows of a form.
    public void ApplyFormProperties()
    {
        FormComponent form = _document.Form;
        int width = 320;
        int height = 240;
        String title = form.Name;

        FormProperty? bounds = form.FindProperty("Bounds");
        if (bounds != null && ((FormProperty)bounds).Value.Items.Count == 4u)
        {
            var items = ((FormProperty)bounds).Value.Items;
            width = ReadDesignedInteger(items[2u]);
            height = ReadDesignedInteger(items[3u]);
        }
        FormProperty? text = form.FindProperty("Text");
        if (text != null)
            title = UnquoteFormText(((FormProperty)text).Value.Items[0u]);

        _frame.SetBounds(GridStep * 2, GridStep * 2, width, height);
        _caption.Text = title;
        _caption.SetBounds(FrameSide, 7, width - FrameSide * 2, FrameTop - 12);
        _client.SetBounds(FrameSide, FrameTop, width - FrameSide * 2,
                          height - FrameTop - FrameSide);
        LayOutTray();
    }

    private void CreateDesignedChildren(FormComponent component, WindowedControl parent,
                                        List<String> unknown)
    {
        foreach (var child in component.ListChildren())
        {
            if (IsNonVisualType(child.TypeName))
            {
                CreateNonVisualItem(child);
                continue;
            }

            Control? made = CreateDesignedControl(child.TypeName, parent);
            if (made == null)
            {
                unknown.Add(child.Name);
                continue;
            }

            var live = (Control)made;
            live.IsDesigning = true;
            live.Paint += this.OnLiveControlPaint;
            var type = FindDesignedType(child.TypeName);
            for (nuint i = 0u; i < child.Members.Count; i++)
            {
                if (child.Members[i] is FormProperty property)
                    ApplyDesignedProperty(live, type, property, BaseDirectory);
            }
            _items.Add(new DesignedItem(child, live));
            if (live is WindowedControl container)
                CreateDesignedChildren(child, container, unknown);
        }
    }

    /// A component with no window: the object itself, which never starts,
    /// and its entry in the tray.
    private void CreateNonVisualItem(FormComponent component)
    {
        var item = new DesignedItem(component, CreateTrayEntry());
        item.Held = new Timer();

        var type = FindDesignedType(component.TypeName);
        for (nuint i = 0u; i < component.Members.Count; i++)
        {
            if (component.Members[i] is FormProperty property)
                ApplyReflectedProperty(item.Target, type, property, BaseDirectory);
        }
        _items.Add(item);
    }

    // ------------------------------------------------------------ geometry

    /// Where a control is in the client's coordinates, which are the
    /// overlay's.
    private Rectangle FindClientBounds(Control live)
    {
        int x = live.Bounds.X;
        int y = live.Bounds.Y;
        Control? walk = live.Parent;
        while (walk != null && walk != _client)
        {
            var here = (Control)walk;
            if (here is WindowedControl container)
            {
                x += container.ClientOrigin.X;
                y += container.ClientOrigin.Y;
            }
            x += here.Bounds.X;
            y += here.Bounds.Y;
            walk = here.Parent;
        }
        if (walk is WindowedControl client)
        {
            x += client.ClientOrigin.X;
            y += client.ClientOrigin.Y;
        }
        return Rectangle.FromBounds(x, y, live.Bounds.Width, live.Bounds.Height);
    }

    /// The front-most item under a point: the last made, since a later
    /// sibling and a child are both drawn over what came before.
    private DesignedItem? FindItemAt(Point at)
    {
        for (nuint i = _items.Count; i > 0u; i--)
        {
            var item = _items[i - 1u];
            if (IsShown(item) && FindClientBounds(item.Live).Contains(at))
                return item;
        }
        return null;
    }

    /// The eight grab handles around a rectangle, clockwise from the top left.
    private Rectangle[] ListHandles(Rectangle around)
    {
        int half = HandleSize / 2;
        int left = around.Left - half;
        int middleX = around.Left + around.Width / 2 - half;
        int right = around.Right - half;
        int top = around.Top - half;
        int middleY = around.Top + around.Height / 2 - half;
        int bottom = around.Bottom - half;
        return [
            Rectangle.FromBounds(left, top, HandleSize, HandleSize),
            Rectangle.FromBounds(middleX, top, HandleSize, HandleSize),
            Rectangle.FromBounds(right, top, HandleSize, HandleSize),
            Rectangle.FromBounds(right, middleY, HandleSize, HandleSize),
            Rectangle.FromBounds(right, bottom, HandleSize, HandleSize),
            Rectangle.FromBounds(middleX, bottom, HandleSize, HandleSize),
            Rectangle.FromBounds(left, bottom, HandleSize, HandleSize),
            Rectangle.FromBounds(left, middleY, HandleSize, HandleSize),
        ];
    }

    private static int SnapToGrid(int value)
    {
        int below = value >= 0 ? value / GridStep : (value - GridStep + 1) / GridStep;
        int snapped = below * GridStep;
        return value - snapped >= GridStep / 2 ? snapped + GridStep : snapped;
    }

    // ------------------------------------------------------------ painting

    /// A control beneath has painted itself, perhaps over the handles.
    /// Lazarus's `TDesigner.PaintControl` and the redraw after it.
    private void OnLiveControlPaint(Control sender, PaintEventArgs args) => _overlay.RedrawOver();

    /// One control selected has its eight handles; several have their corners
    /// marked in grey, as Lazarus marks them, since only one can be sized.
    private void OnOverlayPaint(Control sender, PaintEventArgs args)
    {
        var outline = new Pen(SystemColors.Highlight);
        var fill = new Brush(SystemColors.Highlight);
        var several = new Brush(SystemColors.GrayText);
        foreach (var item in _selection)
        {
            if (!IsShown(item))
                continue;
            Rectangle around = FindClientBounds(item.Live);
            args.Graphics.DrawRectangle(outline, Rectangle.FromBounds(
                around.X - 1, around.Y - 1, around.Width + 1, around.Height + 1));
            var handles = ListHandles(around);
            for (nuint i = 0u; i < handles.Length; i++)
            {
                if (_selection.Count == 1u)
                    args.Graphics.FillRectangle(fill, handles[i]);
                else if (i % 2u == 0u)
                    args.Graphics.FillRectangle(several, handles[i]);
            }
        }

        if (_drag == DesignDrag.Band && !_band.IsEmpty)
            args.Graphics.DrawRectangle(new Pen(SystemColors.ControlText, 1, PenStyle.Dot), _band);
    }

    // ------------------------------------------------------------ the pointer

    private void OnOverlayMouseDown(Control sender, MouseEventArgs args)
    {
        _overlay.Focus();
        if (args.Button != MouseButton.Left)
            return;

        // A handle of a lone selection wins over whatever is under it.
        var chosen = Primary;
        if (chosen != null && _selection.Count == 1u && IsShown((DesignedItem)chosen))
        {
            Rectangle around = FindClientBounds(((DesignedItem)chosen).Live);
            var handles = ListHandles(around);
            for (nuint i = 0u; i < handles.Length; i++)
            {
                if (handles[i].Contains(args.Location))
                {
                    BeginDesignDrag(DesignDrag.Sizing, (int)i, args.Location);
                    return;
                }
            }
        }

        if (PendingType != "")
        {
            PlaceComponent(PendingType, args.Location);
            PendingType = "";
            return;
        }

        // Shift or Ctrl adds to the selection or takes away from it, and
        // starts nothing: the next plain press is what drags.
        bool adding = args.Modifiers.HasFlag(ModifierKeys.Shift) || args.Modifiers.HasFlag(ModifierKeys.Control);
        var hit = FindItemAt(args.Location);
        if (hit == null)
        {
            if (!adding && !_selection.IsEmpty)
            {
                _selection.Clear();
                RefreshSelection();
            }
            _overlay.Invalidate();
            BeginDesignDrag(DesignDrag.Band, 0, args.Location);
            return;
        }

        var item = (DesignedItem)hit;
        if (adding)
        {
            if (IsSelected(item))
                _selection.RemoveAll((each) => each == item);
            else
                _selection.Add(item);
            RefreshSelection();
            return;
        }

        // A press on one of several keeps them all, so they move together.
        if (!IsSelected(item))
        {
            _selection.Clear();
            _selection.Add(item);
            RefreshSelection();
        }
        BeginDesignDrag(DesignDrag.Moving, 0, args.Location);
    }

    private void BeginDesignDrag(DesignDrag kind, int handle, Point from)
    {
        _drag = kind;
        _dragStarted = false;
        _handle = handle;
        _dragFrom = from;
        _band = Rectangle.Empty;
        _boundsAtDrag.Clear();
        _draggedTo.Clear();
        foreach (var item in _selection)
        {
            Rectangle at = ReadDesignedBounds(item.Component);
            _boundsAtDrag.Add(at);
            _draggedTo.Add(at);
        }
        _overlay.CaptureMouse(true);
    }

    private void OnOverlayMouseMove(Control sender, MouseEventArgs args)
    {
        if (_drag == DesignDrag.None)
            return;

        int dx = args.X - _dragFrom.X;
        int dy = args.Y - _dragFrom.Y;

        // A click is not a move: a control off the grid would otherwise snap
        // to it just for being selected.
        if (!_dragStarted && Math.Abs(dx) < DragThreshold && Math.Abs(dy) < DragThreshold)
            return;
        _dragStarted = true;

        if (_drag == DesignDrag.Band)
        {
            _band = Rectangle.FromEdges(Math.Min(_dragFrom.X, args.X), Math.Min(_dragFrom.Y, args.Y),
                                        Math.Max(_dragFrom.X, args.X), Math.Max(_dragFrom.Y, args.Y));
            _overlay.Invalidate();
            return;
        }

        if (_drag == DesignDrag.Moving)
        {
            for (nuint i = 0u; i < _selection.Count; i++)
            {
                if (IsInsideSelection(_selection[i]) || _selection[i].IsNonVisual)
                    continue;
                Rectangle at = _boundsAtDrag[i];
                _draggedTo[i] = Rectangle.FromBounds(SnapToGrid(at.X + dx), SnapToGrid(at.Y + dy),
                                                     at.Width, at.Height);
                _selection[i].Live.Bounds = _draggedTo[i];
            }
        }
        else
        {
            Rectangle was = _boundsAtDrag[0u];
            var live = _selection[0u].Live;
            int left = was.Left;
            int top = was.Top;
            int right = was.Right;
            int bottom = was.Bottom;
            if (_handle == 0 || _handle == 6 || _handle == 7)
                left = SnapToGrid(left + dx);
            if (_handle == 2 || _handle == 3 || _handle == 4)
                right = SnapToGrid(right + dx);
            if (_handle == 0 || _handle == 1 || _handle == 2)
                top = SnapToGrid(top + dy);
            if (_handle == 4 || _handle == 5 || _handle == 6)
                bottom = SnapToGrid(bottom + dy);
            if (right - left < GridStep)
                right = left + GridStep;
            if (bottom - top < GridStep)
                bottom = top + GridStep;
            _draggedTo[0u] = Rectangle.FromBounds(left, top, right - left, bottom - top);
            live.Bounds = _draggedTo[0u];
        }
        _overlay.Invalidate();
    }

    private void OnOverlayMouseUp(Control sender, MouseEventArgs args)
    {
        if (_drag == DesignDrag.None)
            return;
        var drag = _drag;
        _drag = DesignDrag.None;
        _overlay.CaptureMouse(false);

        if (drag == DesignDrag.Band)
        {
            if (_dragStarted)
                SelectWithin(_band);
            _band = Rectangle.Empty;
            _overlay.Invalidate();
            return;
        }

        if (!_dragStarted)
            return;
        bool moved = false;
        for (nuint i = 0u; i < _selection.Count; i++)
        {
            if (!_draggedTo[i].Equals(_boundsAtDrag[i]))
            {
                WriteDesignedBounds(_selection[i], _draggedTo[i]);
                moved = true;
            }
        }
        if (moved)
            AnnounceChange();
    }

    /// Selects the form's own controls that a rectangle touches, in the
    /// overlay's coordinates; nothing touched selects the form. Controls
    /// inside a container are reached by selecting it, or with Shift.
    public void SelectWithin(Rectangle band)
    {
        _selection.Clear();
        foreach (var item in _items)
        {
            if (item.Live.Parent == _client && !FindClientBounds(item.Live).Intersect(band).IsEmpty)
                _selection.Add(item);
        }
        RefreshSelection();
    }

    /// Adds a component to the selection, as Shift and a click do.
    public void AddToSelection(String name)
    {
        foreach (var item in _items)
        {
            if (item.Component.Name == name && !IsSelected(item))
                _selection.Add(item);
        }
        RefreshSelection();
    }

    // ------------------------------------------------------------ the keyboard

    /// Delete removes the selection; the arrows move it a pixel, or size it
    /// with Shift, which is Lazarus's pair.
    private void OnOverlayKeyDown(Control sender, KeyEventArgs args)
    {
        bool moves = args.Key == Key.Delete || args.Key == Key.Escape || args.Key == Key.Left
                     || args.Key == Key.Right || args.Key == Key.Up || args.Key == Key.Down;
        if (!moves)
        {
            KeyNotHandled(this, args);
            return;
        }
        if (_selection.IsEmpty)
            return;

        int dx = 0;
        int dy = 0;
        switch (args.Key)
        {
            case Key.Delete:
                DeleteSelectedComponent();
                return;
            case Key.Escape:
                SelectParentComponent();
                return;
            case Key.Left: dx = -1; break;
            case Key.Right: dx = 1; break;
            case Key.Up: dy = -1; break;
            case Key.Down: dy = 1; break;
            default: return;
        }

        NudgeSelection(dx, dy, args.Shift);
    }

    /// Moves every selected control by a step, or sizes each with `sizing`.
    /// What the arrows do; public for a test.
    public void NudgeSelection(int dx, int dy, bool sizing)
    {
        foreach (var item in _selection)
        {
            if ((!sizing && IsInsideSelection(item)) || item.IsNonVisual)
                continue;
            Rectangle was = ReadDesignedBounds(item.Component);
            Rectangle now = sizing
                ? Rectangle.FromBounds(was.X, was.Y, Math.Max(1, was.Width + dx), Math.Max(1, was.Height + dy))
                : Rectangle.FromBounds(was.X + dx, was.Y + dy, was.Width, was.Height);
            item.Live.Bounds = now;
            WriteDesignedBounds(item, now);
        }
        AnnounceChange();
    }

    // ------------------------------------------------------------ changes

    /// Selects a component by name, alone, or the form for a name that is not
    /// one.
    public void SelectComponent(String name)
    {
        _selection.Clear();
        foreach (var item in _items)
        {
            if (item.Component.Name == name)
                _selection.Add(item);
        }
        RefreshSelection();
    }

    /// Selects what contains the first of the selection, or the form.
    public void SelectParentComponent()
    {
        var chosen = Primary;
        if (chosen == null)
            return;
        var parent = ((DesignedItem)chosen).Live.Parent;
        _selection.Clear();
        foreach (var item in _items)
        {
            if (item.Live == parent)
                _selection.Add(item);
        }
        RefreshSelection();
    }

    /// Removes the selected components, and everything inside them, from the
    /// document and from the surface.
    public void DeleteSelectedComponent()
    {
        if (_selection.IsEmpty)
            return;

        var removed = new List<DesignedItem>();
        foreach (var item in _selection)
        {
            if (IsInsideSelection(item))
                continue;
            _document.Form.RemoveComponent(item.Component.Name);
            var parent = item.Live.Parent;
            if (parent != null)
                ((WindowedControl)parent).RemoveControl(item.Live);
            removed.Add(item);
        }

        var kept = new List<DesignedItem>();
        foreach (var each in _items)
        {
            bool gone = false;
            foreach (var item in removed)
            {
                if (each == item || IsInside(each.Live, item.Live))
                    gone = true;
            }
            if (!gone)
                kept.Add(each);
        }
        _items = kept;
        _selection.Clear();
        LayOutTray();
        Changed();
        RefreshSelection();
    }

    private bool IsInside(Control inner, Control outer)
    {
        Control? walk = inner.Parent;
        while (walk != null)
        {
            if (walk == outer)
                return true;
            walk = ((Control)walk).Parent;
        }
        return false;
    }

    /// Moves an item's control to a rectangle, as a program would. For a test
    /// and for a Properties grid; the pointer goes through the same path.
    public void MoveComponent(String name, int x, int y, int width, int height)
    {
        foreach (var item in _items)
        {
            if (item.Component.Name == name)
            {
                var wanted = Rectangle.FromBounds(x, y, width, height);
                item.Live.Bounds = wanted;
                StoreDesignedBounds(item, wanted);
                return;
            }
        }
    }

    // ------------------------------------------------------------ editing

    /// Sets a property of a component in the document. The caller has set it
    /// on the live control already, or for the form nothing is live and the
    /// surface applies what it shows of one.
    public void StoreComponentProperty(FormComponent component, String name, FormValue value)
    {
        component.SetProperty(name, value);
        if (component == _document.Form)
            ApplyFormProperties();
        Changed();
        _overlay.Invalidate();
    }

    /// Adds a module to what the generated half imports, for a value that
    /// names one of its types. The next change writes it.
    public void RequireImport(String moduleName)
    {
        foreach (var each in _document.Imports)
        {
            if (each == moduleName)
                return;
        }
        _document.Imports.Add(moduleName);
    }

    /// Takes a property out of a component in the document, which leaves it
    /// at whatever its control starts with.
    public void RemoveComponentProperty(FormComponent component, String name)
    {
        if (component.RemoveProperty(name))
            AnnounceChange();
    }

    /// Wires an event of a component to a method, or unwires it for an empty
    /// name.
    public void StoreComponentHandler(FormComponent component, String eventName, String method)
    {
        component.SetHandler(eventName, method);
        Changed();
    }

    /// Gives a component a new name, which is its field's. False when the
    /// name is taken or is not a name.
    public bool RenameComponent(FormComponent component, String name)
    {
        if (name == "" || _document.Form.FindComponent(name) != null || !IsDesignName(name))
            return false;
        component.Name = name;
        Changed();
        return true;
    }

    private static bool IsDesignName(String name)
    {
        nuint size = name.ByteLength();
        for (nuint i = 0u; i < size; i++)
        {
            byte c = name.GetByteAt(i);
            bool letter = (c >= (byte)'a' && c <= (byte)'z') || (c >= (byte)'A' && c <= (byte)'Z')
                          || c == (byte)'_';
            bool digit = c >= (byte)'0' && c <= (byte)'9';
            if (!letter && !(digit && i > 0u))
                return false;
        }
        return true;
    }

    /// A new component of a Toolbox type, where the pointer is: inside the
    /// container under it, or on the form. Named `_button1` and so on.
    ///
    /// A page goes on the `TabControl` under the pointer, and is refused
    /// anywhere else; a component with no window goes in the tray, wherever
    /// the click was. A new `TabControl` comes with a page, as Visual
    /// Studio's does, so there is somewhere to put a control at once.
    public void PlaceComponent(String typeName, Point at)
    {
        FormComponent parent = _document.Form;
        String name = CreateComponentName(typeName);
        var made = new FormComponent(typeName, name);
        made.HasBlankLineBefore = true;
        if (TakesDesignedText(typeName))
            made.SetProperty("Text", FormValue.FromText(name.Substring(1u)));

        if (IsNonVisualType(typeName))
        {
            made.Initializer = "new " + typeName + "()";
        }
        else if (typeName == "TabPage")
        {
            var tabs = FindTabControlAt(at);
            if (tabs == null)
            {
                Message("A TabPage goes on a TabControl; click on one to add a page to it.");
                return;
            }
            parent = ((DesignedItem)tabs).Component;
        }
        else
        {
            int x = at.X;
            int y = at.Y;
            var under = FindItemAt(at);
            if (under != null && IsDesignableContainer(((DesignedItem)under).Component.TypeName))
            {
                var container = (DesignedItem)under;
                Rectangle outer = FindClientBounds(container.Live);
                x = at.X - outer.X - ((WindowedControl)container.Live).ClientOrigin.X;
                y = at.Y - outer.Y - ((WindowedControl)container.Live).ClientOrigin.Y;
                parent = container.Component;
            }
            Size extent = FindDefaultExtent(typeName);
            made.SetProperty("Bounds", FormValue.FromRectangle(SnapToGrid(x), SnapToGrid(y),
                                                                extent.Width, extent.Height));
        }
        parent.Members.Add(made);

        if (typeName == "TabControl")
        {
            String page = CreateComponentName("TabPage");
            var first = new FormComponent("TabPage", page);
            first.SetProperty("Text", FormValue.FromText(page.Substring(1u)));
            made.Members.Add(first);
        }

        LoadDocument(_document);
        SelectComponent(name);
        Changed();
    }

    /// The `TabControl` under a point, or the one a page or a control under
    /// it is on; null for none.
    private DesignedItem? FindTabControlAt(Point at)
    {
        var under = FindItemAt(at);
        if (under == null)
            return null;
        Control? walk = ((DesignedItem)under).Live;
        while (walk != null && walk != _client)
        {
            if (walk is TabControl)
            {
                foreach (var item in _items)
                {
                    if (item.Live == walk)
                        return item;
                }
            }
            walk = ((Control)walk).Parent;
        }
        return null;
    }

    /// `_button1`, `_button2`: the type's name, lowered, and the first number
    /// no component has yet.
    private String CreateComponentName(String typeName)
    {
        String stem = "_" + typeName.Substring(0u, 1u).ToLowerAscii() + typeName.Substring(1u);
        for (int n = 1; ; n++)
        {
            String candidate = stem + Standard.Text.FromInteger(n);
            if (_document.Form.FindComponent(candidate) == null)
                return candidate;
        }
    }

    private static bool TakesDesignedText(String typeName)
    {
        switch (typeName)
        {
            case "Button":
            case "Label":
            case "CheckBox":
            case "RadioButton":
            case "ToggleButton":
            case "GroupBox":
            case "TabPage":
                return true;
            default:
                return false;
        }
    }

    /// The size a new control is made at, in whole grid steps.
    private static Size FindDefaultExtent(String typeName)
    {
        switch (typeName)
        {
            case "Label": return Size.FromDimensions(80, 16);
            case "TextBox":
            case "ComboBox": return Size.FromDimensions(120, 24);
            case "CheckBox":
            case "RadioButton": return Size.FromDimensions(104, 24);
            case "ListBox":
            case "CheckListBox": return Size.FromDimensions(120, 96);
            case "ProgressBar": return Size.FromDimensions(160, 24);
            case "TrackBar": return Size.FromDimensions(160, 32);
            case "TreeView":
            case "ListView": return Size.FromDimensions(160, 120);
            case "Panel":
            case "GroupBox": return Size.FromDimensions(160, 96);
            case "TabControl": return Size.FromDimensions(200, 128);
            case "Image":
            case "Shape": return Size.FromDimensions(64, 64);
            case "PaintBox": return Size.FromDimensions(104, 104);
            case "Bevel": return Size.FromDimensions(160, 48);
            default: return Size.FromDimensions(80, 24);
        }
    }

    /// Where the file puts a component: its `Bounds`, which is what was asked
    /// for. A platform MAY settle a control larger -- a GTK button will not go
    /// below its minimum -- and the file is not the place for that.
    public Rectangle ReadDesignedBounds(FormComponent component)
    {
        FormProperty? bounds = component.FindProperty("Bounds");
        if (bounds != null && ((FormProperty)bounds).Value.Items.Count == 4u)
        {
            var items = ((FormProperty)bounds).Value.Items;
            return Rectangle.FromBounds(ReadDesignedInteger(items[0u]), ReadDesignedInteger(items[1u]),
                                        ReadDesignedInteger(items[2u]), ReadDesignedInteger(items[3u]));
        }
        Control? live = FindLiveControl(component.Name);
        return live == null ? Rectangle.Empty : ((Control)live).Bounds;
    }

    /// Moves a component in the file and on the surface, by the rectangle
    /// asked for.
    public void SetDesignedBounds(FormComponent component, Rectangle wanted)
    {
        foreach (var item in _items)
        {
            if (item.Component == component)
            {
                item.Live.Bounds = wanted;
                StoreDesignedBounds(item, wanted);
                return;
            }
        }
    }

    private void StoreDesignedBounds(DesignedItem item, Rectangle now)
    {
        WriteDesignedBounds(item, now);
        AnnounceChange();
    }

    private static void WriteDesignedBounds(DesignedItem item, Rectangle now) =>
        item.Component.SetProperty("Bounds", FormValue.FromRectangle(now.X, now.Y, now.Width, now.Height));

    /// After the change is written back: that repaints the tab, and the
    /// overlay has to be the last thing drawn.
    private void AnnounceChange()
    {
        Changed();
        _overlay.Invalidate();
    }
}
