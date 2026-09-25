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

// The controls you choose from: `ListBox` and `ComboBox`.
//
// C# calls their shared base `ListControl`, and so does this. The LCL has no
// equivalent -- `TCustomListBox` and `TCustomComboBox` both descend straight
// from `TWinControl` and each declares its own `Items: TStrings`, `ItemIndex`
// and `OnSelectionChange` -- so the duplication the LCL carries is removed here
// rather than translated.
//
// **Items are kept on both sides, and the list here is the one that is right.**
// The platform holds the strings it is showing and would be the single source
// of truth, except that reading one back out of a Win32 list box is a length
// query, a buffer and a second message per item. So the items live here, the
// platform is told about each change, and nothing is ever read back.
module Forms;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;
#if FORMS_REFLECT
import Standard.Reflection;
#endif

// ============================================================== list control

/// What a list box and a combo box have in common: items, and one of them
/// chosen.
public abstract class ListControl : WindowedControl
{
    List<String> _items;

    protected ListControl(WindowedControl parent)
    {
        base(parent);
        _items = new List<String>();
    }

    /// The platform's side of the list, which the derived class made.
    protected abstract IListPeer List { get; }

    /// A list is something you read and choose from, so it takes the window
    /// colour rather than its parent's -- the same rule as a text box.
    protected override Color DefaultBackColor => SystemColors.Window;
    protected override Color DefaultForeColor => SystemColors.WindowText;

    /// How many items there are.
    public nuint Count => _items.Count;

    /// One item, by position.
    public String GetItemAt(nuint index) => _items[index];

    /// Every item, as an array. A copy, so a caller may keep it.
    public String[] Items
    {
        get
        {
            var all = new String[_items.Count];
            for (nuint i = 0u; i < _items.Count; i++)
                all[i] = _items[i];
            return all;
        }
        set
        {
            Clear();
            for (nuint i = 0u; i < value.Length; i++)
                Add(value[i]);
        }
    }

    /// Adds an item to the end.
    public void Add(String text)
    {
        List.InsertItem((int)_items.Count, text);
        _items.Add(text);
    }

    /// Puts one in at a position, moving the rest along.
    ///
    /// The list here goes first: it is the one that checks the index.
    public void Insert(nuint index, String text)
    {
        _items.Insert(index, text);
        List.InsertItem((int)index, text);
    }

    /// Removes one.
    public void RemoveAt(nuint index)
    {
        _items.RemoveAt(index);
        List.RemoveItem((int)index);
    }

    /// Removes them all.
    public void Clear()
    {
        List.ClearItems();
        _items.Clear();
    }

    /// Which item is chosen, or -1 for none.
    ///
    /// **-1 rather than an `Optional<nuint>`**, because that is what the two
    /// platforms report and what every caller compares against; wrapping it
    /// would mean unwrapping it at every use to get back to the same test.
    public int SelectedIndex
    {
        get => List.GetSelectedIndex();
        set => List.SetSelectedIndex(value);
    }

    /// The chosen item's text, or null when nothing is chosen.
    public String? SelectedItem
    {
        get
        {
            int at = SelectedIndex;
            if (at < 0 || (nuint)at >= _items.Count)
                return null;
            return _items[(nuint)at];
        }
    }

    /// The user changed the choice. Setting `SelectedIndex` raises nothing, as
    /// the seam's `OnPlatformValueChanged` says.
    public event EventHandler SelectedIndexChanged;

    protected virtual void OnSelectedIndexChanged() => SelectedIndexChanged(this);

    /// For a list, a change of value is a change of selection -- not of the
    /// control's text, which is what the base would have raised.
    public override void OnPlatformValueChanged() => OnSelectedIndexChanged();
}

// ================================================================= list box

/// A list of items, all of them visible.
#if FORMS_REFLECT
[Reflect]
#endif
public class ListBox : ListControl
{
    IListPeer _native;

    public ListBox(WindowedControl parent)
    {
        base(parent);
        _native = WidgetSet.Current.CreateList(this, ParentPeer);
        AttachPeer(_native);
    }

    protected override IListPeer List => _native;
}

// ================================================================ combo box

/// A list that drops down from one line.
#if FORMS_REFLECT
[Reflect]
#endif
public class ComboBox : ListControl
{
    IComboPeer _native;

    public ComboBox(WindowedControl parent)
    {
        base(parent);
        _native = WidgetSet.Current.CreateCombo(this, ParentPeer);
        AttachPeer(_native);
    }

    protected override IListPeer List => _native;

    /// Whether the text can be typed as well as chosen. A creation-time style
    /// on Windows, so this records the wish and the platform may decline it;
    /// see the note on `ComboPeer`.
    public bool Editable
    {
        get => _editable;
        set
        {
            _editable = value;
            _native.SetEditable(value);
        }
    }

    bool _editable;
}
