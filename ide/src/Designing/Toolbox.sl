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
import Forms.Platform;

public closure void ToolChosenHandler(String typeName);

/// A list of the types the designer can make, each beside its picture.
public class Toolbox : Panel
{
    private late ListView _types;
    private String[] _names;
    private bool _clearing;

    public Toolbox(WindowedControl parent)
    {
        _clearing = false;
        _names = ListDesignableTypes();
        base(parent);
        _types = new ListView(this);
        _types.Dock = DockStyle.Fill;
        _types.View = ListViewStyle.List;
        for (nuint i = 0u; i < _names.Length; i++)
            _types.AddRow(_names[i], (int)i);
        _types.SelectedIndexChanged += this.OnTypeChosen;
    }

    /// One picture per type, in the order `ListDesignableTypes` names them.
    public ImageList? Images
    {
        get => _types.Images;
        set => _types.Images = value;
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
        for (nuint i = 0u; i < _names.Length; i++)
        {
            if (_names[i] == typeName)
            {
                _types.SelectedIndex = (int)i;
                Chosen(typeName);
            }
        }
    }

    private void OnTypeChosen(Control sender)
    {
        int at = _types.SelectedIndex;
        if (_clearing || at < 0 || (nuint)at >= _names.Length)
            return;
        Chosen(_names[(nuint)at]);
    }
}
