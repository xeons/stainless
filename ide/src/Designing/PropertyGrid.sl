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

// The Properties window: what the selected control is set to, and which of the
// form's methods handle its events.
//
// Driven by reflection. The IDE builds Forms with `FORMS_REFLECT`, which marks
// the control classes `[Reflect]`, so a control's properties are found by
// name, read through their getters and written through their setters -- the
// setter being what re-lays the control out. An enum property offers its
// members, a `[Flags]` one a box per member. What reflection cannot say is
// which properties a person should see; `IsHiddenProperty` is that list.
module Ide.Designing;

import Standard.Collections;
import Standard.Convert;
import Standard.Reflection;
import Standard.Text;
import Forms;
import Forms.Drawing;
import Forms.Platform;
import Ide.Designer;

public closure void HandlerChosenHandler(String method, String handlerType);
public closure void GridMessageHandler(String message);

enum GridRowKind { Name, Text, Boolean, Integer, Floating, Choice, Flags }

class GridRow
{
    public String Name;
    public GridRowKind Kind;
    public Property Reflected;
    public Type Enumeration;

    public GridRow(String name, GridRowKind kind, Property reflected, Type enumeration)
    {
        Name = name;
        Kind = kind;
        Reflected = reflected;
        Enumeration = enumeration;
    }
}

/// The Properties window.
public class PropertyGrid : Panel
{
    private Label _heading;
    private TabControl _tabs;
    private ListView _properties;
    private ListView _events;
    private Panel _editor;
    private Label _editing;
    private TextBox _text;
    private ComboBox _choice;
    private Panel _flags;
    private List<CheckBox> _flagBoxes;
    private TextBox _handler;

    private DesignSurface? _surface;
    private FormComponent? _component;
    private List<GridRow> _rows;
    private List<String> _eventNames;
    private List<String> _eventTypes;
    private Type _type;
    /// True while the grid fills itself, so the editors' own events are not
    /// taken for a person's edits.
    private bool _filling;

    public PropertyGrid(WindowedControl parent)
    {
        base(parent);
        _rows = new List<GridRow>();
        _eventNames = new List<String>();
        _eventTypes = new List<String>();
        _flagBoxes = new List<CheckBox>();
        _surface = null;
        _component = null;
        _filling = false;
        _type = FindType("");

        _heading = new Label(this);
        _heading.Dock = DockStyle.Top;
        _heading.Height = 22;

        _tabs = new TabControl(this);
        _tabs.Dock = DockStyle.Fill;
        var propertiesPage = new TabPage(_tabs, "Properties");
        var eventsPage = new TabPage(_tabs, "Events");

        _editor = new Panel(propertiesPage);
        _editor.Dock = DockStyle.Bottom;
        _editor.Height = 132;
        _editing = new Label(_editor);
        _editing.Dock = DockStyle.Top;
        _editing.Height = 20;
        _text = new TextBox(_editor);
        _text.Dock = DockStyle.Top;
        _text.Height = 24;
        _text.KeyDown += this.OnTextKey;
        _choice = new ComboBox(_editor);
        _choice.Dock = DockStyle.Top;
        _choice.Height = 200;
        _choice.SelectedIndexChanged += this.OnChoiceChanged;
        _flags = new Panel(_editor);
        _flags.Dock = DockStyle.Fill;

        _properties = new ListView(propertiesPage);
        _properties.Dock = DockStyle.Fill;
        _properties.View = ListViewStyle.Details;
        _properties.SetFullRowSelect(true, true);
        _properties.AddColumn("Property", 110);
        _properties.AddColumn("Value", 150);
        _properties.SelectedIndexChanged += this.OnPropertyChosen;

        _handler = new TextBox(eventsPage);
        _handler.Dock = DockStyle.Bottom;
        _handler.Height = 24;
        _handler.KeyDown += this.OnHandlerKey;

        _events = new ListView(eventsPage);
        _events.Dock = DockStyle.Fill;
        _events.View = ListViewStyle.Details;
        _events.SetFullRowSelect(true, true);
        _events.AddColumn("Event", 110);
        _events.AddColumn("Handler", 150);
        _events.SelectedIndexChanged += this.OnEventChosen;
        _events.DoubleClick += this.OnEventDoubleClicked;

        ShowSurface(null);
    }

    /// Raised when a handler is wired by double-clicking an event, with the
    /// method's name and the delegate it has to match, so the method can be
    /// written if it is not there.
    public event HandlerChosenHandler HandlerChosen;

    /// Something the grid could not do, for the status line.
    public event GridMessageHandler Message;

    public nuint RowCount => _rows.Count;

    // ------------------------------------------------------------ filling

    /// Shows the selection of a surface, or nothing for none.
    public void ShowSurface(DesignSurface? surface)
    {
        _surface = surface;
        int kept = _properties.SelectedIndex;
        _filling = true;
        _properties.Clear();
        _events.Clear();
        _rows.Clear();
        _eventNames.Clear();
        _eventTypes.Clear();
        _component = null;

        if (surface == null)
        {
            _heading.Text = "";
            ShowEditorFor(-1);
            _filling = false;
            return;
        }

        var designer = (DesignSurface)surface;
        FormComponent? chosen = designer.SelectedComponent;
        var component = chosen == null ? designer.Document.Form : (FormComponent)chosen;
        _component = component;
        _type = FindDesignedType(component.TypeName);
        _heading.Text = " " + component.Name + "   " + component.TypeName;

        CollectRows(chosen == null);
        foreach (var row in _rows)
            _properties.AddRow([row.Name == "" ? "(Name)" : row.Name, ReadRowValue(row)]);

        if (_type.Exists)
        {
            for (nuint i = 0u; i < _type.EventCount; i++)
            {
                var each = _type.GetEventAt(i);
                String name = each.Name;
                _eventNames.Add(name);
                _eventTypes.Add(each.HandlerTypeName);
                FormHandler? wired = component.FindHandler(name);
                _events.AddRow([name, wired == null ? "" : ((FormHandler)wired).MethodName]);
            }
        }

        if (kept >= 0 && (nuint)kept < _rows.Count)
            _properties.SelectedIndex = kept;
        ShowEditorFor(_properties.SelectedIndex);
        _filling = false;
    }

    private void CollectRows(bool isForm)
    {
        Property none;
        none.Handle = null;
        Type noType = FindType("");

        if (!isForm)
            _rows.Add(new GridRow("", GridRowKind.Name, none, noType));

        if (isForm || !_type.Exists)
        {
            // Nothing live stands for the form, so it offers what the surface
            // shows of one: its title and its size.
            _rows.Add(new GridRow("Text", GridRowKind.Text, none, noType));
            _rows.Add(new GridRow("Width", GridRowKind.Integer, none, noType));
            _rows.Add(new GridRow("Height", GridRowKind.Integer, none, noType));
            return;
        }

        var found = new List<GridRow>();
        for (nuint i = 0u; i < _type.PropertyCount; i++)
        {
            var property = _type.GetPropertyAt(i);
            if (!property.IsPublic || !property.CanRead || !property.CanWrite
                || IsHiddenProperty(property.Name))
                continue;

            int kind = property.Kind;
            Type enumeration = property.PropertyType;
            GridRowKind shown;
            if (enumeration.Exists && enumeration.IsEnum)
                shown = enumeration.HasAttribute("Flags") ? GridRowKind.Flags : GridRowKind.Choice;
            else if (kind == KindString)
                shown = GridRowKind.Text;
            else if (kind == KindBool)
                shown = GridRowKind.Boolean;
            else if (property.IsInteger)
                shown = GridRowKind.Integer;
            else if (property.IsFloating)
                shown = GridRowKind.Floating;
            else
                continue;
            found.Add(new GridRow(property.Name, shown, property, enumeration));
        }

        // Alphabetical, as Lazarus's inspector and Visual Studio's grid both are.
        while (!found.IsEmpty)
        {
            nuint least = 0u;
            for (nuint i = 1u; i < found.Count; i++)
            {
                if (found[i].Name.CompareTo(found[least].Name) < 0)
                    least = i;
            }
            _rows.Add(found[least]);
            found.RemoveAt(least);
        }
    }

    /// What a person should not be offered: the name, which is the `(Name)`
    /// row; a designer's own switch; state that only a running program has;
    /// and the second spelling of `Text`.
    private static bool IsHiddenProperty(String name)
    {
        switch (name)
        {
            case "Name":
            case "IsDesigning":
            case "SelectionStart":
            case "SelectionLength":
            case "Caption":
            case "Title":
                return true;
            default:
                return false;
        }
    }

    // ------------------------------------------------------------ values

    private String ReadRowValue(GridRow row)
    {
        var component = (FormComponent)_component;
        if (row.Kind == GridRowKind.Name)
            return component.Name;

        WindowedControl? live = FindLive();
        if (live == null)
            return ReadDocumentValue(component, row.Name);

        byte* raw = (byte*)((WindowedControl)live);
        switch (row.Kind)
        {
            case GridRowKind.Text:
                return GetText(raw, row.Reflected);
            case GridRowKind.Boolean:
                return GetBool(raw, row.Reflected) ? "true" : "false";
            case GridRowKind.Integer:
                return Standard.Text.FromInteger(GetInteger(raw, row.Reflected));
            case GridRowKind.Floating:
                return Standard.Text.FromDouble(GetDouble(raw, row.Reflected));
            case GridRowKind.Choice:
                return FindMemberName(row.Enumeration, GetInteger(raw, row.Reflected));
            case GridRowKind.Flags:
                return DescribeFlags(row.Enumeration, GetInteger(raw, row.Reflected), false);
            default:
                return "";
        }
    }

    /// The form's properties, from the file, since nothing live holds them.
    private static String ReadDocumentValue(FormComponent component, String name)
    {
        if (name == "Text")
        {
            FormProperty? text = component.FindProperty("Text");
            return text == null ? "" : UnquoteFormText(((FormProperty)text).Value.Items[0u]);
        }

        FormProperty? bounds = component.FindProperty("Bounds");
        if (bounds == null || ((FormProperty)bounds).Value.Items.Count != 4u)
            return "";
        var items = ((FormProperty)bounds).Value.Items;
        switch (name)
        {
            case "Left": return items[0u];
            case "Top": return items[1u];
            case "Width": return items[2u];
            case "Height": return items[3u];
            default: return "";
        }
    }

    private WindowedControl? FindLive()
    {
        var surface = _surface;
        if (surface == null)
            return null;
        return ((DesignSurface)surface).SelectedLive;
    }

    private static String FindMemberName(Type enumeration, long value)
    {
        for (nuint i = 0u; i < enumeration.EnumMemberCount; i++)
        {
            if (enumeration.GetEnumMemberValue(i) == value)
                return enumeration.GetEnumMemberName(i);
        }
        return Standard.Text.FromInteger(value);
    }

    /// The members whose bits are all set, joined by `|`; qualified for the
    /// file, bare for the grid.
    private static String DescribeFlags(Type enumeration, long value, bool qualified)
    {
        String prefix = qualified ? SpellEnumType(enumeration) + "." : "";
        var text = new StringBuilder();
        String zero = "";
        for (nuint i = 0u; i < enumeration.EnumMemberCount; i++)
        {
            long bits = enumeration.GetEnumMemberValue(i);
            if (bits == 0)
            {
                zero = prefix + enumeration.GetEnumMemberName(i);
                continue;
            }
            if ((value & bits) != bits)
                continue;
            if (text.HasContent)
                text.Append(" | ");
            text.Append(prefix + enumeration.GetEnumMemberName(i));
        }
        if (text.HasContent)
            return text.ToText();
        return zero != "" ? zero : "0";
    }

    /// How the generated half names an enum type. It imports `Forms` and
    /// nothing under it, so anything else is written in full.
    private static String SpellEnumType(Type enumeration)
    {
        String name = enumeration.Name;
        if (name.StartsWith("Forms.") && !name.Substring(6u).Contains("."))
            return name.Substring(6u);
        return name;
    }

    // ------------------------------------------------------------ editing

    private void OnPropertyChosen(Control sender)
    {
        if (!_filling)
            ShowEditorFor(_properties.SelectedIndex);
    }

    /// Puts the editor that suits a row below the list.
    private void ShowEditorFor(int index)
    {
        bool filling = _filling;
        _filling = true;
        _text.Visible = false;
        _choice.Visible = false;
        _flags.Visible = false;
        foreach (var box in _flagBoxes)
            _flags.RemoveControl(box);
        _flagBoxes.Clear();

        if (index < 0 || (nuint)index >= _rows.Count)
        {
            _editing.Text = "";
            _filling = filling;
            return;
        }

        var row = _rows[(nuint)index];
        _editing.Text = " " + (row.Name == "" ? "(Name)" : row.Name);
        String value = ReadRowValue(row);

        switch (row.Kind)
        {
            case GridRowKind.Boolean:
                _choice.Items = ["false", "true"];
                _choice.SelectedIndex = value == "true" ? 1 : 0;
                _choice.Visible = true;
                break;

            case GridRowKind.Choice:
            {
                var names = new List<String>();
                int at = -1;
                for (nuint i = 0u; i < row.Enumeration.EnumMemberCount; i++)
                {
                    String member = row.Enumeration.GetEnumMemberName(i);
                    if (member == value)
                        at = (int)i;
                    names.Add(member);
                }
                _choice.Items = names.ToArray();
                _choice.SelectedIndex = at;
                _choice.Visible = true;
                break;
            }

            case GridRowKind.Flags:
            {
                WindowedControl? live = FindLive();
                long bits = live == null ? 0 : GetInteger((byte*)((WindowedControl)live), row.Reflected);
                int y = 0;
                for (nuint i = 0u; i < row.Enumeration.EnumMemberCount; i++)
                {
                    long member = row.Enumeration.GetEnumMemberValue(i);
                    if (member == 0)
                        continue;
                    var box = new CheckBox(_flags);
                    box.Text = row.Enumeration.GetEnumMemberName(i);
                    box.SetBounds(8, y, 140, 22);
                    box.Checked = (bits & member) == member;
                    box.CheckedChanged += this.OnFlagChanged;
                    _flagBoxes.Add(box);
                    y += 22;
                }
                _flags.Visible = true;
                break;
            }

            default:
                _text.Text = value;
                _text.Visible = true;
                break;
        }
        _filling = filling;
    }

    private void OnTextKey(Control sender, KeyEventArgs args)
    {
        if (args.Key == Key.Enter)
            ApplyText(_text.Text);
    }

    private void OnChoiceChanged(Control sender)
    {
        if (_filling || _choice.SelectedIndex < 0)
            return;
        ApplyText(_choice.GetItemAt((nuint)_choice.SelectedIndex));
    }

    private void OnFlagChanged(Control sender)
    {
        if (_filling)
            return;
        var row = CurrentRow();
        if (row == null)
            return;
        var flags = (GridRow)row;
        long bits = 0;
        nuint box = 0u;
        for (nuint i = 0u; i < flags.Enumeration.EnumMemberCount; i++)
        {
            long member = flags.Enumeration.GetEnumMemberValue(i);
            if (member == 0)
                continue;
            if (_flagBoxes[box].Checked)
                bits = bits | member;
            box++;
        }
        ApplyInteger(flags, bits);
    }

    private GridRow? CurrentRow()
    {
        int index = _properties.SelectedIndex;
        if (index < 0 || (nuint)index >= _rows.Count)
            return null;
        return _rows[(nuint)index];
    }

    /// Sets the selected row from what a person typed or chose.
    public void ApplyText(String typed)
    {
        var chosen = CurrentRow();
        var surface = _surface;
        var held = _component;
        if (chosen == null || surface == null || held == null)
            return;
        var row = (GridRow)chosen;
        var designer = (DesignSurface)surface;
        var component = (FormComponent)held;

        switch (row.Kind)
        {
            case GridRowKind.Name:
                if (!designer.RenameComponent(component, typed))
                    Message("'" + typed + "' is not a name, or another control has it.");
                break;

            case GridRowKind.Text:
                if (FindLive() != null)
                    SetText((byte*)((WindowedControl)FindLive()), row.Reflected, typed);
                designer.StoreComponentProperty(component, row.Name, FormValue.FromText(typed));
                break;

            case GridRowKind.Boolean:
                ApplyBoolean(row, typed == "true");
                break;

            case GridRowKind.Integer:
            {
                var read = Convert.ToInt(typed.Trim());
                if (!read.Ok)
                {
                    Message("'" + typed + "' is not a whole number.");
                    break;
                }
                ApplyInteger(row, read.Value);
                break;
            }

            case GridRowKind.Floating:
            {
                var read = Convert.ToDouble(typed.Trim());
                if (!read.Ok)
                {
                    Message("'" + typed + "' is not a number.");
                    break;
                }
                SetDouble((byte*)((WindowedControl)FindLive()), row.Reflected, read.Value);
                designer.StoreComponentProperty(component, row.Name, FormValue.FromName(typed.Trim()));
                break;
            }

            case GridRowKind.Choice:
                for (nuint i = 0u; i < row.Enumeration.EnumMemberCount; i++)
                {
                    if (row.Enumeration.GetEnumMemberName(i) == typed)
                        ApplyInteger(row, row.Enumeration.GetEnumMemberValue(i));
                }
                break;

            default:
                break;
        }
        ShowSurface(_surface);
    }

    private void ApplyBoolean(GridRow row, bool truth)
    {
        var designer = (DesignSurface)_surface;
        var component = (FormComponent)_component;

        // A hidden control stays in the designer, which is where a person
        // would otherwise lose it; only the file says it is hidden.
        WindowedControl? live = FindLive();
        if (live != null && row.Name != "Visible")
            SetBool((byte*)((WindowedControl)live), row.Reflected, truth);
        designer.StoreComponentProperty(component, row.Name, FormValue.FromBoolean(truth));
    }

    private void ApplyInteger(GridRow row, long value)
    {
        var designer = (DesignSurface)_surface;
        var component = (FormComponent)_component;
        WindowedControl? live = FindLive();

        if (live == null)
        {
            // The form: its size is its `Bounds`.
            FormProperty? bounds = component.FindProperty("Bounds");
            int x = 0;
            int y = 0;
            int width = 320;
            int height = 240;
            if (bounds != null && ((FormProperty)bounds).Value.Items.Count == 4u)
            {
                var items = ((FormProperty)bounds).Value.Items;
                x = ReadDesignedInteger(items[0u]);
                y = ReadDesignedInteger(items[1u]);
                width = ReadDesignedInteger(items[2u]);
                height = ReadDesignedInteger(items[3u]);
            }
            if (row.Name == "Width")
                width = (int)value;
            if (row.Name == "Height")
                height = (int)value;
            designer.StoreComponentProperty(component, "Bounds",
                                            FormValue.FromRectangle(x, y, width, height));
            return;
        }

        var control = (WindowedControl)live;
        SetInteger((byte*)control, row.Reflected, value);

        switch (row.Kind)
        {
            case GridRowKind.Choice:
                designer.StoreComponentProperty(component, row.Name, FormValue.FromName(
                    SpellEnumType(row.Enumeration) + "." + FindMemberName(row.Enumeration, value)));
                return;
            case GridRowKind.Flags:
                designer.StoreComponentProperty(component, row.Name,
                    FormValue.FromName(DescribeFlags(row.Enumeration, value, true)));
                return;
            default:
                break;
        }

        // Where a control is and how big is one `Bounds` in the file.
        switch (row.Name)
        {
            case "Left":
            case "Top":
            case "Width":
            case "Height":
            {
                Rectangle now = control.Bounds;
                designer.StoreComponentProperty(component, "Bounds",
                    FormValue.FromRectangle(now.X, now.Y, now.Width, now.Height));
                return;
            }
            default:
                designer.StoreComponentProperty(component, row.Name, FormValue.FromInteger(value));
                return;
        }
    }

    // ------------------------------------------------------------ events

    private void OnEventChosen(Control sender)
    {
        int at = _events.SelectedIndex;
        if (at < 0)
            return;
        _handler.Text = _events.GetCellText(at, 1);
    }

    private void OnHandlerKey(Control sender, KeyEventArgs args)
    {
        if (args.Key != Key.Enter)
            return;
        int at = _events.SelectedIndex;
        if (at < 0)
            return;
        WireEventHandler((nuint)at, _handler.Text.Trim());
    }

    /// Double-clicking an event wires it to a method named after the control
    /// and the event, as Visual Studio and Lazarus both do, and asks for the
    /// method to be written.
    private void OnEventDoubleClicked(Control sender)
    {
        int at = _events.SelectedIndex;
        if (at < 0)
            return;
        String method = _events.GetCellText(at, 1);
        if (method == "")
            method = CreateHandlerName(_eventNames[(nuint)at]);
        WireEventHandler((nuint)at, method);
        HandlerChosen(method, _eventTypes[(nuint)at]);
    }

    /// Wires an event, by its position in the Events list, to a method. For
    /// the list and for a test.
    public void WireEventHandler(nuint index, String method)
    {
        var surface = _surface;
        var held = _component;
        if (surface == null || held == null || index >= _eventNames.Count)
            return;
        ((DesignSurface)surface).StoreComponentHandler((FormComponent)held, _eventNames[index], method);
        ShowSurface(_surface);
    }

    /// `OnGreetClick` for `_greet`'s `Click`, and `OnShown` for the form's.
    public String CreateHandlerName(String eventName)
    {
        var component = (FormComponent)_component;
        var surface = (DesignSurface)_surface;
        if (component == surface.Document.Form)
            return "On" + eventName;

        String name = component.Name;
        while (name.StartsWith("_"))
            name = name.Substring(1u);
        if (name == "")
            return "On" + eventName;
        return "On" + name.Substring(0u, 1u).ToUpperAscii() + name.Substring(1u) + eventName;
    }

    /// The position of an event in the Events list, for a test.
    public long FindEventIndex(String name)
    {
        for (nuint i = 0u; i < _eventNames.Count; i++)
        {
            if (_eventNames[i] == name)
                return (long)i;
        }
        return -1;
    }

    /// Selects a row by the property it shows, for a test.
    public bool SelectProperty(String name)
    {
        for (nuint i = 0u; i < _rows.Count; i++)
        {
            if (_rows[i].Name == name)
            {
                _properties.SelectedIndex = (int)i;
                ShowEditorFor((int)i);
                return true;
            }
        }
        return false;
    }

    /// The value a row shows, for a test.
    public String ReadPropertyValue(String name)
    {
        for (nuint i = 0u; i < _rows.Count; i++)
        {
            if (_rows[i].Name == name)
                return ReadRowValue(_rows[i]);
        }
        return "";
    }
}
