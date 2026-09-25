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
    public WindowedControl Live;

    public DesignedItem(FormComponent component, WindowedControl live)
    {
        Component = component;
        Live = live;
    }
}

public closure void DesignChangedHandler();

/// What a drag is doing.
enum DesignDrag { None, Moving, Sizing }

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

    private FormDocument _document;
    private Panel _frame;
    private Label _caption;
    private Panel _client;
    private CustomControl _overlay;
    private List<DesignedItem> _items;

    /// The selected component, or null when the form itself is.
    private DesignedItem? _selected;

    private DesignDrag _drag;
    /// Whether the pointer has gone far enough for a press to be a drag.
    private bool _dragStarted;
    /// Which handle a resize is holding, 0 to 7 clockwise from the top left.
    private int _handle;
    private Point _dragFrom;
    private Rectangle _boundsAtDrag;

    public DesignSurface(WindowedControl parent)
    {
        base(parent);
        BackColor = SystemColors.ControlDark;
        _items = new List<DesignedItem>();
        _selected = null;
        PendingType = "";
        _drag = DesignDrag.None;
        _dragStarted = false;
        _handle = 0;
        _dragFrom = Point.Empty;
        _boundsAtDrag = Rectangle.Empty;
        _document = new FormDocument("", "", "Form");

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
    }

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

    /// The selected component, or null for the form.
    public FormComponent? SelectedComponent
    {
        get
        {
            var chosen = _selected;
            return chosen == null ? null : ((DesignedItem)chosen).Component;
        }
    }

    /// The live control of the selected component, or null for the form.
    public WindowedControl? SelectedLive
    {
        get
        {
            var chosen = _selected;
            return chosen == null ? null : ((DesignedItem)chosen).Live;
        }
    }

    /// The live control made for a component, or null.
    public WindowedControl? FindLiveControl(String name)
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
        _selected = null;
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
        return unknown;
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
    }

    private void CreateDesignedChildren(FormComponent component, WindowedControl parent,
                                        List<String> unknown)
    {
        foreach (var child in component.ListChildren())
        {
            WindowedControl? made = CreateDesignedControl(child.TypeName, parent);
            if (made == null)
            {
                unknown.Add(child.Name);
                continue;
            }

            var live = (WindowedControl)made;
            live.IsDesigning = true;
            live.Paint += this.OnLiveControlPaint;
            var type = FindDesignedType(child.TypeName);
            for (nuint i = 0u; i < child.Members.Count; i++)
            {
                if (child.Members[i] is FormProperty property)
                    ApplyDesignedProperty(live, type, property);
            }
            _items.Add(new DesignedItem(child, live));
            CreateDesignedChildren(child, live, unknown);
        }
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
            if (FindClientBounds(item.Live).Contains(at))
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

    private void OnOverlayPaint(Control sender, PaintEventArgs args)
    {
        var chosen = _selected;
        if (chosen == null)
            return;

        Rectangle around = FindClientBounds(((DesignedItem)chosen).Live);
        var outline = new Pen(SystemColors.Highlight);
        var fill = new Brush(SystemColors.Highlight);
        args.Graphics.DrawRectangle(outline, Rectangle.FromBounds(
            around.X - 1, around.Y - 1, around.Width + 1, around.Height + 1));
        foreach (var handle in ListHandles(around))
            args.Graphics.FillRectangle(fill, handle);
    }

    // ------------------------------------------------------------ the pointer

    private void OnOverlayMouseDown(Control sender, MouseEventArgs args)
    {
        _overlay.Focus();
        if (args.Button != MouseButton.Left)
            return;

        // A handle of the selection wins over whatever is under it.
        var chosen = _selected;
        if (chosen != null)
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

        var was = _selected;
        _selected = FindItemAt(args.Location);
        _overlay.Invalidate();
        if (_selected != was)
            SelectionChanged();
        if (_selected != null)
            BeginDesignDrag(DesignDrag.Moving, 0, args.Location);
    }

    private void BeginDesignDrag(DesignDrag kind, int handle, Point from)
    {
        _drag = kind;
        _dragStarted = false;
        _handle = handle;
        _dragFrom = from;
        _boundsAtDrag = ((DesignedItem)_selected).Live.Bounds;
        _overlay.CaptureMouse(true);
    }

    private void OnOverlayMouseMove(Control sender, MouseEventArgs args)
    {
        var chosen = _selected;
        if (_drag == DesignDrag.None || chosen == null)
            return;

        int dx = args.X - _dragFrom.X;
        int dy = args.Y - _dragFrom.Y;

        // A click is not a move: a control off the grid would otherwise snap
        // to it just for being selected.
        if (!_dragStarted && Math.Abs(dx) < DragThreshold && Math.Abs(dy) < DragThreshold)
            return;
        _dragStarted = true;
        Rectangle was = _boundsAtDrag;
        var live = ((DesignedItem)chosen).Live;

        if (_drag == DesignDrag.Moving)
        {
            live.SetBounds(SnapToGrid(was.X + dx), SnapToGrid(was.Y + dy), was.Width, was.Height);
        }
        else
        {
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
            live.SetBounds(left, top, right - left, bottom - top);
        }
        _overlay.Invalidate();
    }

    private void OnOverlayMouseUp(Control sender, MouseEventArgs args)
    {
        if (_drag == DesignDrag.None)
            return;
        _drag = DesignDrag.None;
        _overlay.CaptureMouse(false);

        var chosen = _selected;
        if (chosen != null && !((DesignedItem)chosen).Live.Bounds.Equals(_boundsAtDrag))
            StoreDesignedBounds((DesignedItem)chosen);
    }

    // ------------------------------------------------------------ the keyboard

    /// Delete removes the selection; the arrows move it a pixel, or size it
    /// with Shift, which is Lazarus's pair.
    private void OnOverlayKeyDown(Control sender, KeyEventArgs args)
    {
        var chosen = _selected;
        bool moves = args.Key == Key.Delete || args.Key == Key.Escape || args.Key == Key.Left
                     || args.Key == Key.Right || args.Key == Key.Up || args.Key == Key.Down;
        if (!moves)
        {
            KeyNotHandled(this, args);
            return;
        }
        if (chosen == null)
            return;
        var item = (DesignedItem)chosen;

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

        Rectangle was = item.Live.Bounds;
        if (args.Shift)
            item.Live.SetBounds(was.X, was.Y, Math.Max(1, was.Width + dx), Math.Max(1, was.Height + dy));
        else
            item.Live.SetBounds(was.X + dx, was.Y + dy, was.Width, was.Height);
        StoreDesignedBounds(item);
    }

    // ------------------------------------------------------------ changes

    /// Selects a component by name, or the form for a name that is not one.
    public void SelectComponent(String name)
    {
        _selected = null;
        foreach (var item in _items)
        {
            if (item.Component.Name == name)
                _selected = item;
        }
        _overlay.Invalidate();
        SelectionChanged();
    }

    /// Selects what contains the selection, or the form.
    public void SelectParentComponent()
    {
        var chosen = _selected;
        if (chosen == null)
            return;
        var parent = ((DesignedItem)chosen).Live.Parent;
        _selected = null;
        foreach (var item in _items)
        {
            if (item.Live == parent)
                _selected = item;
        }
        _overlay.Invalidate();
        SelectionChanged();
    }

    /// Removes the selected component, and everything inside it, from the
    /// document and from the surface.
    public void DeleteSelectedComponent()
    {
        var chosen = _selected;
        if (chosen == null)
            return;
        var item = (DesignedItem)chosen;

        _document.Form.RemoveComponent(item.Component.Name);
        var parent = item.Live.Parent;
        if (parent != null)
            ((WindowedControl)parent).RemoveControl(item.Live);

        var kept = new List<DesignedItem>();
        foreach (var each in _items)
        {
            if (each != item && !IsInside(each.Live, item.Live))
                kept.Add(each);
        }
        _items = kept;
        _selected = null;
        Changed();
        _overlay.Invalidate();
        SelectionChanged();
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
                item.Live.SetBounds(x, y, width, height);
                StoreDesignedBounds(item);
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

    /// A new control of a Toolbox type, where the pointer is: inside the
    /// container under it, or on the form. Named `_button1` and so on.
    public void PlaceComponent(String typeName, Point at)
    {
        FormComponent parent = _document.Form;
        int x = at.X;
        int y = at.Y;

        var under = FindItemAt(at);
        if (under != null && IsDesignableContainer(((DesignedItem)under).Component.TypeName))
        {
            var container = (DesignedItem)under;
            Rectangle outer = FindClientBounds(container.Live);
            x = at.X - outer.X - container.Live.ClientOrigin.X;
            y = at.Y - outer.Y - container.Live.ClientOrigin.Y;
            parent = container.Component;
        }

        String name = CreateComponentName(typeName);
        var made = new FormComponent(typeName, name);
        made.HasBlankLineBefore = true;
        if (TakesDesignedText(typeName))
            made.SetProperty("Text", FormValue.FromText(name.Substring(1u)));
        Size extent = FindDefaultExtent(typeName);
        made.SetProperty("Bounds", FormValue.FromRectangle(SnapToGrid(x), SnapToGrid(y),
                                                            extent.Width, extent.Height));
        parent.Members.Add(made);

        LoadDocument(_document);
        SelectComponent(name);
        Changed();
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
            default: return Size.FromDimensions(80, 24);
        }
    }

    private void StoreDesignedBounds(DesignedItem item)
    {
        Rectangle now = item.Live.Bounds;
        item.Component.SetProperty("Bounds",
            FormValue.FromRectangle(now.X, now.Y, now.Width, now.Height));

        // After the change is written back: that repaints the tab, and the
        // overlay has to be the last thing drawn.
        Changed();
        _overlay.Invalidate();
    }
}
