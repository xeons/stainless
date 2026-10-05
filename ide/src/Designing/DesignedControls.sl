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
import Forms.Drawing;
import Ide.Designer;

/// The types the designer can make, in the order a Toolbox lists them.
public String[] ListDesignableTypes() =>
    ["Button", "Label", "TextBox", "CheckBox", "RadioButton", "ToggleButton",
     "ListBox", "ComboBox", "CheckListBox", "SpinEdit", "ProgressBar", "TrackBar",
     "TreeView", "ListView", "Panel", "GroupBox", "TabControl", "TabPage", "Image", "PaintBox",
     "Shape", "Bevel", "Timer"];

/// Whether controls may be put inside one of these. A `TabControl` holds
/// pages and nothing else, so it is not one.
public bool IsDesignableContainer(String typeName) =>
    typeName == "Panel" || typeName == "GroupBox" || typeName == "TabPage";

/// Whether a type has no window, and so is shown in the tray under the form
/// and made by the expression its declaration gives, `new Timer()`.
public bool IsNonVisualType(String typeName) => typeName == "Timer";

/// A control of the named type inside `parent`, or null for a name the
/// designer does not know. An `Image` has no window and is drawn by its
/// parent; it is designed all the same, as the LCL designs any `TControl`.
public Control? CreateDesignedControl(String typeName, WindowedControl parent)
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
        case "TabControl": return new TabControl(parent);
        case "TabPage": return parent is TabControl tabs ? new TabPage(tabs) : null;
        case "Image": return new Image(parent);
        case "PaintBox": return new PaintBox(parent);
        case "Shape": return new Shape(parent);
        case "Bevel": return new Bevel(parent);
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
/// `Bounds` is several values and goes to `SetBounds`. A property that would
/// make the designer behave as the program does is not applied; see
/// `IsDesignInert`.
public bool ApplyDesignedProperty(Control control, Type type, FormProperty property,
                                  String baseDirectory)
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
    return ApplyReflectedProperty((byte*)control, type, property, baseDirectory);
}

/// What the file says and the designer does not do: a hidden control stays
/// in the designer, which is where a person would otherwise lose it, and an
/// enabled timer does not tick there. The file is what says either.
public bool IsDesignInert(Type type, String propertyName) =>
    propertyName == "Visible" || (propertyName == "Enabled" && type.Exists && type.Name == "Forms.Timer");

/// The same for any object reflection describes: a control, or a component
/// with no window. A picture is read from beside the form file, which is
/// where the generated half embeds it from.
public bool ApplyReflectedProperty(byte* raw, Type type, FormProperty property, String baseDirectory)
{
    var items = property.Value.Items;
    if (items.Count != 1u || !type.Exists || IsDesignInert(type, property.Name))
        return false;

    var target = type.FindProperty(property.Name);
    if (!target.Exists || !target.IsPublic || !target.CanWrite)
        return false;

    String item = items[0u];
    Type enumeration = target.PropertyType;
    if (enumeration.Exists && enumeration.IsEnum)
    {
        SetInteger(raw, target, ReadDesignedEnum(enumeration, item));
        return true;
    }

    int kind = target.Kind;
    if (kind == KindStruct && enumeration.Exists && enumeration.Name == DesignedColorType)
    {
        var colour = ReadDesignedColour(item);
        if (!colour.Ok)
            return false;
        Color value = colour.Value;
        SetStruct(raw, target, (byte*)&value);
        return true;
    }
    if (kind == KindClass && enumeration.Exists && enumeration.Name == DesignedFontType)
    {
        var font = ReadDesignedFont(item);
        if (font.Ok)
            SetAggregate(raw, target, (byte*)font.Value);
        return font.Ok;
    }
    if (kind == KindClass && enumeration.Exists && enumeration.Name == DesignedBitmapType)
    {
        var path = ReadDesignedPicturePath(item);
        if (!path.Ok)
            return false;
        var picture = Bitmap.FromFile(FindDesignedPicture(baseDirectory, path.Value));
        if (picture.Ok)
            SetAggregate(raw, target, (byte*)picture.Value);
        return picture.Ok;
    }
    if (kind == KindArray && target.ElementKind == KindString)
    {
        var lines = ReadDesignedTextArray(item);
        if (lines.Ok)
            SetAggregate(raw, target, (byte*)lines.Value);
        return lines.Ok;
    }
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
