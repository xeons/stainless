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
// A type is made by name through a table, because reflection cannot make an
// instance of a `Type`. Properties are applied from a short list until the
// Properties grid reads them through reflection; one that is not on it is kept
// in the file and simply not shown.
module Ide.Designing;

import Standard.Collections;
import Standard.Convert;
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

/// Applies what the designer knows how to show, and answers whether it did.
public bool ApplyDesignedProperty(Control control, FormProperty property)
{
    var items = property.Value.Items;
    switch (property.Name)
    {
        case "Text":
            control.Text = UnquoteFormText(items[0u]);
            return true;

        case "Bounds":
        {
            if (items.Count != 4u)
                return false;
            control.SetBounds(ReadDesignedInteger(items[0u]), ReadDesignedInteger(items[1u]),
                              ReadDesignedInteger(items[2u]), ReadDesignedInteger(items[3u]));
            return true;
        }

        case "Width":
            control.Width = ReadDesignedInteger(items[0u]);
            return true;

        case "Height":
            control.Height = ReadDesignedInteger(items[0u]);
            return true;

        case "Enabled":
            control.Enabled = items[0u] == "true";
            return true;

        case "Dock":
            control.Dock = ReadDesignedDock(items[0u]);
            return true;

        default:
            return false;
    }
}

/// An item as an integer, and zero for one that is not.
public int ReadDesignedInteger(String item)
{
    var read = Convert.ToInt(item);
    return read.Ok ? read.Value : 0;
}

DockStyle ReadDesignedDock(String item)
{
    switch (item)
    {
        case "DockStyle.Top": return DockStyle.Top;
        case "DockStyle.Bottom": return DockStyle.Bottom;
        case "DockStyle.Left": return DockStyle.Left;
        case "DockStyle.Right": return DockStyle.Right;
        case "DockStyle.Fill": return DockStyle.Fill;
        default: return DockStyle.None;
    }
}
