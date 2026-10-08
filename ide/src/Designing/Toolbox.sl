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
    /// The project's frames, listed after the types, each with the picture
    /// after the types'.
    private String[] _frames;
    private bool _clearing;

    public Toolbox(WindowedControl parent)
    {
        _clearing = false;
        _names = ListDesignableTypes();
        _frames = [];
        base(parent);
        _types = new ListView(this);
        _types.Dock = DockStyle.Fill;
        _types.View = ListViewStyle.List;
        FillRows();
        _types.SelectedIndexChanged += this.OnTypeChosen;
    }

    private void FillRows()
    {
        _clearing = true;
        _types.Clear();
        for (nuint i = 0u; i < _names.Length; i++)
            _types.AddRow(_names[i], (int)i);
        foreach (var frame in _frames)
            _types.AddRow(frame, (int)_names.Length);
        _clearing = false;
    }

    /// The project's frames, each placed by its class name. Listed again
    /// only when they have changed.
    public void SetFrameTypes(String[] frames)
    {
        bool same = frames.Length == _frames.Length;
        for (nuint i = 0u; same && i < frames.Length; i++)
            same = frames[i] == _frames[i];
        if (same)
            return;
        _frames = frames;
        FillRows();
    }

    /// One picture per type, in the order `ListDesignableTypes` names them,
    /// and one more that every frame shows.
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
        for (nuint i = 0u; i < _names.Length + _frames.Length; i++)
        {
            if (NameAt(i) == typeName)
            {
                _types.SelectedIndex = (int)i;
                Chosen(typeName);
            }
        }
    }

    private String NameAt(nuint row) =>
        row < _names.Length ? _names[row] : _frames[row - _names.Length];

    private void OnTypeChosen(Control sender)
    {
        int at = _types.SelectedIndex;
        if (_clearing || at < 0 || (nuint)at >= _names.Length + _frames.Length)
            return;
        Chosen(NameAt((nuint)at));
    }
}
