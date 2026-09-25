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

// The controls a form can be given: pick one, then click on the form.
module Ide.Designing;

import Standard.Collections;
import Forms;

public closure void ToolChosenHandler(String typeName);

/// A list of the types the designer can make.
public class Toolbox : Panel
{
    private ListBox _types;
    private bool _clearing;

    public Toolbox(WindowedControl parent)
    {
        base(parent);
        _clearing = false;
        _types = new ListBox(this);
        _types.Dock = DockStyle.Fill;
        _types.Items = ListDesignableTypes();
        _types.SelectedIndexChanged += this.OnTypeChosen;
    }

    /// Raised when a type is picked; the next click on a form places one.
    public event ToolChosenHandler Chosen;

    /// Lets go of the pick, once it has been placed.
    public void ClearChoice()
    {
        _clearing = true;
        _types.SelectedIndex = -1;
        _clearing = false;
    }

    /// Picks a type as though it had been clicked. For a test: a list set by
    /// the program reports nothing, so this raises `Chosen` itself.
    public void ChooseType(String typeName)
    {
        var names = ListDesignableTypes();
        for (nuint i = 0u; i < names.Length; i++)
        {
            if (names[i] == typeName)
            {
                _types.SelectedIndex = (int)i;
                Chosen(typeName);
            }
        }
    }

    private void OnTypeChosen(Control sender)
    {
        if (_clearing || _types.SelectedIndex < 0)
            return;
        Chosen(_types.GetItemAt((nuint)_types.SelectedIndex));
    }
}
