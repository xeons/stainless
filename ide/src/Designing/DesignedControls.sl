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

// The controls a form file names, made for real so the designer can show them.
//
// A type is made by name through a table: reflection can allocate an instance
// of a `Type` but not run a constructor that takes a parent. Properties are
// applied through reflection, each by its own setter.
module Ide.Designing;

import Standard.Collections;
import Standard.Convert;
import Standard.Reflection;
import Standard.Text;
import Forms;
import Ide.Designer;

/// The control types the designer can make, in the order a Toolbox lists them.
public String[] ListDesignableTypes() =>
    ["Button", "Label", "TextBox", "CheckBox", "RadioButton", "ToggleButton",
     "ListBox", "ComboBox", "CheckListBox", "SpinEdit", "ProgressBar", "TrackBar",
     "TreeView", "ListView", "Panel", "GroupBox"];

/// Whether controls may be put inside one of these.
public bool IsDesignableContainer(String typeName) =>
    typeName == "Panel" || typeName == "GroupBox";

/// A control of the named type inside `parent`, or null for a name the
/// designer does not know.
public WindowedControl? CreateDesignedControl(String typeName, WindowedControl parent)
{
    switch (typeName)
    {
        case "Button": return new Button(parent);
        case "Label": return new Label(parent);
        case "TextBox": return new TextBox(parent);
        case "CheckBox": return new CheckBox(parent);
        case "RadioButton": return new RadioButton(parent);
        case "ToggleButton": return new ToggleButton(parent);
        case "ListBox": return new ListBox(parent);
        case "ComboBox": return new ComboBox(parent);
        case "CheckListBox": return new CheckListBox(parent);
        case "SpinEdit": return new SpinEdit(parent);
        case "ProgressBar": return new ProgressBar(parent);
        case "TrackBar": return new TrackBar(parent);
        case "TreeView": return new TreeView(parent);
        case "ListView": return new ListView(parent);
        case "Panel": return new Panel(parent);
        case "GroupBox": return new GroupBox(parent);
        default: return null;
    }
}

/// The Forms type a component's type name means: `Button` is `Forms.Button`.
/// It exists only in a build that reflects Forms, which the IDE's is.
public Type FindDesignedType(String typeName) =>
    FindType(typeName.Contains(".") ? typeName : "Forms." + typeName);

/// Applies a property from the file to its live control through the
/// property's own setter, and answers whether it could.
///
/// `Bounds` is several values and goes to `SetBounds`. `Visible` is not
/// applied: a hidden control stays in the designer, which is where a person
/// would otherwise lose it, and the file is what says it is hidden.
public bool ApplyDesignedProperty(WindowedControl control, Type type, FormProperty property)
{
    var items = property.Value.Items;
    if (property.Name == "Bounds")
    {
        if (items.Count != 4u)
            return false;
        control.SetBounds(ReadDesignedInteger(items[0u]), ReadDesignedInteger(items[1u]),
                          ReadDesignedInteger(items[2u]), ReadDesignedInteger(items[3u]));
        return true;
    }
    if (property.Name == "Visible" || items.Count != 1u || !type.Exists)
        return false;

    var target = type.FindProperty(property.Name);
    if (!target.Exists || !target.IsPublic || !target.CanWrite)
        return false;

    byte* raw = (byte*)control;
    String item = items[0u];
    Type enumeration = target.PropertyType;
    if (enumeration.Exists && enumeration.IsEnum)
    {
        SetInteger(raw, target, ReadDesignedEnum(enumeration, item));
        return true;
    }

    int kind = target.Kind;
    if (kind == KindString)
    {
        SetText(raw, target, UnquoteFormText(item));
        return true;
    }
    if (kind == KindBool)
    {
        SetBool(raw, target, item == "true");
        return true;
    }
    if (target.IsInteger)
    {
        SetInteger(raw, target, (long)ReadDesignedInteger(item));
        return true;
    }
    if (target.IsFloating)
    {
        var read = Convert.ToDouble(item);
        if (read.Ok)
            SetDouble(raw, target, read.Value);
        return read.Ok;
    }
    return false;
}

/// An enum item as the file writes it -- `DockStyle.Fill`, or several joined
/// by `|` for flags -- as the value its members add up to.
long ReadDesignedEnum(Type enumeration, String item)
{
    long value = 0;
    foreach (var part in item.Split("|"))
    {
        String name = part.Trim();
        long dot = name.LastIndexOf(".");
        if (dot >= 0)
            name = name.Substring((nuint)dot + 1u);
        for (nuint i = 0u; i < enumeration.EnumMemberCount; i++)
        {
            if (enumeration.GetEnumMemberName(i) == name)
                value = value | enumeration.GetEnumMemberValue(i);
        }
    }
    return value;
}

/// An item as an integer, and zero for one that is not.
public int ReadDesignedInteger(String item)
{
    var read = Convert.ToInt(item);
    return read.Ok ? read.Value : 0;
}
