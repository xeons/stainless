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

// The window a menu's items and a toolbar's buttons are edited in.
//
// Lazarus's menu editor, kept small: a tree of the items, and buttons that add,
// order and remove them. What an item says and does is edited in the
// Properties grid, which shows the item chosen here, so there is one place an
// item's properties and its `Click` are set.
module Ide.Designing;

import Standard.Collections;
import Forms;
import Forms.Platform;
import Ide.Designer;

public class ItemsEditor : Form
{
    private DesignSurface? _surface;
    private String _owner;

    private late TreeView _tree;
    private late Button _addItem;
    private late Button _addChild;
    private late Button _addSeparator;
    private late Button _addToggle;
    private late Button _moveUp;
    private late Button _moveDown;
    private late Button _delete;
    private late Button _close;

    /// Each node, and the component it stands for, in the order listed.
    private List<TreeNode> _nodes;
    private List<String> _names;

    /// Set while the tree is being filled, when its selection changing is not
    /// a person choosing an item.
    private bool _filling;

    public ItemsEditor()
    {
        _surface = null;
        _owner = "";
        _nodes = new List<TreeNode>();
        _names = new List<String>();
        _filling = false;
        base(WindowBorder.Tool);
        Title = "Items";
        SetBounds(0, 0, 360, 380);

        _tree = new TreeView(this);
        _tree.SetBounds(12, 12, 210, 318);
        _tree.Anchors = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom;
        _tree.SelectedNodeChanged += this.OnNodeChosen;

        _addItem = CreateEditorButton("Add item", 0, this.OnAddItem);
        _addChild = CreateEditorButton("Add sub-item", 1, this.OnAddChild);
        _addToggle = CreateEditorButton("Add toggle", 1, this.OnAddToggle);
        _addSeparator = CreateEditorButton("Add separator", 2, this.OnAddSeparator);
        _moveUp = CreateEditorButton("Move up", 3, this.OnMoveUp);
        _moveDown = CreateEditorButton("Move down", 4, this.OnMoveDown);
        _delete = CreateEditorButton("Delete", 5, this.OnDelete);
        _close = CreateEditorButton("Close", 7, this.OnCloseClicked);
    }

    /// The surface whose items are shown, or null before any are.
    public DesignSurface? Surface => _surface;

    /// The menu or toolbar whose items are shown.
    public String OwnerName => _owner;

    /// How many items are listed, at any depth.
    public nuint ItemCount => _names.Count;

    private Button CreateEditorButton(String text, int row, EventHandler handler)
    {
        var made = new Button(this);
        made.Text = text;
        made.SetBounds(232, 12 + row * 34, 104, 28);
        made.Anchors = AnchorStyles.Top | AnchorStyles.Right;
        made.Click += handler;
        return made;
    }

    /// Shows the items of a menu or a toolbar, and brings the window up. The
    /// first item is chosen when none of these is, so the Properties grid
    /// shows an item at once.
    public void EditItems(DesignSurface surface, String owner)
    {
        _surface = surface;
        _owner = owner;
        RefreshItems();
        Show();
        if (SelectedItemName == "" && !_names.IsEmpty)
            SelectItem(_names[0u]);
    }

    /// Lists the items again from the document, keeping the item the surface
    /// has selected. A menu or toolbar that is no longer there hides the
    /// window.
    public void RefreshItems()
    {
        var surface = _surface;
        if (surface == null)
            return;
        var designer = (DesignSurface)surface;
        FormComponent? found = designer.FindComponent(_owner);
        if (found == null || FindItemTypeOf(((FormComponent)found).TypeName) == "")
        {
            Hide();
            return;
        }
        var owner = (FormComponent)found;
        bool isMenu = owner.TypeName != "ToolBar";
        Title = (isMenu ? "Menu items -- " : "Toolbar buttons -- ") + _owner;

        _filling = true;
        _tree.Clear();
        _nodes.Clear();
        _names.Clear();
        AddItemNodes(designer, owner, null);

        FormComponent? chosen = designer.SelectedComponent;
        for (nuint i = 0u; chosen != null && i < _names.Count; i++)
        {
            if (_names[i] == ((FormComponent)chosen).Name)
                _tree.SelectedNode = _nodes[i];
        }
        _filling = false;

        _addChild.Visible = isMenu;
        _addToggle.Visible = !isMenu;
        UpdateButtons();
    }

    private void AddItemNodes(DesignSurface designer, FormComponent within, TreeNode? under)
    {
        foreach (var child in within.ListChildren())
        {
            String text = designer.DescribeItemText(child);
            if (text == "")
                text = child.Name;
            var node = under == null ? _tree.Add(text) : ((TreeNode)under).Add(text);
            _nodes.Add(node);
            _names.Add(child.Name);
            AddItemNodes(designer, child, node);
            node.Expand();
        }
    }

    /// The component the chosen node stands for, or "".
    public String SelectedItemName
    {
        get
        {
            TreeNode? chosen = _tree.SelectedNode;
            for (nuint i = 0u; chosen != null && i < _nodes.Count; i++)
            {
                if (_nodes[i] == chosen)
                    return _names[i];
            }
            return "";
        }
    }

    /// Chooses the node of the item the surface has selected, without choosing
    /// it on the surface again. Nothing changes for a selection that is not
    /// one of these items.
    public void FollowSelection()
    {
        var surface = _surface;
        if (surface == null)
            return;
        FormComponent? chosen = ((DesignSurface)surface).SelectedComponent;
        for (nuint i = 0u; chosen != null && i < _names.Count; i++)
        {
            if (_names[i] == ((FormComponent)chosen).Name && _tree.SelectedNode != _nodes[i])
            {
                _filling = true;
                _tree.SelectedNode = _nodes[i];
                _filling = false;
            }
        }
        UpdateButtons();
    }

    /// Chooses an item by name, as clicking its node does.
    public void SelectItem(String name)
    {
        for (nuint i = 0u; i < _names.Count; i++)
        {
            if (_names[i] == name)
                _tree.SelectedNode = _nodes[i];
        }
        ShowChosenItem();
    }

    private void UpdateButtons()
    {
        String chosen = SelectedItemName;
        _moveUp.Enabled = chosen != "";
        _moveDown.Enabled = chosen != "";
        _delete.Enabled = chosen != "";

        // A sub-item goes under an item that is not a gap.
        bool heading = false;
        var surface = _surface;
        if (surface != null && chosen != "")
        {
            FormComponent? item = ((DesignSurface)surface).FindComponent(chosen);
            heading = item != null && !IsSeparatorInitializer(((FormComponent)item).Initializer);
        }
        _addChild.Enabled = heading;
    }

    private void OnNodeChosen(Control sender)
    {
        if (_filling)
            return;
        ShowChosenItem();
    }

    /// Selects the chosen item on the surface, which shows it in the
    /// Properties grid.
    private void ShowChosenItem()
    {
        UpdateButtons();
        var surface = _surface;
        String chosen = SelectedItemName;
        if (surface != null && chosen != "")
            ((DesignSurface)surface).SelectComponent(chosen);
    }

    /// Adds an item after the chosen one's siblings, or under the owner when
    /// nothing is chosen. `under` puts it inside the chosen item instead.
    private void AddDesignedItemHere(DesignedItemKind kind, bool under)
    {
        var surface = _surface;
        if (surface == null)
            return;
        var designer = (DesignSurface)surface;

        String into = _owner;
        String chosen = SelectedItemName;
        if (chosen != "")
        {
            if (under)
            {
                into = chosen;
            }
            else
            {
                var parent = designer.FindParentComponent(chosen);
                if (parent != null)
                    into = ((FormComponent)parent).Name;
            }
        }

        String made = designer.AddDesignedItem(into, kind);
        RefreshItems();
        if (made != "")
            SelectItem(made);
    }

    private void OnAddItem(Control sender) => AddDesignedItemHere(DesignedItemKind.Item, false);
    private void OnAddChild(Control sender) => AddDesignedItemHere(DesignedItemKind.Item, true);
    private void OnAddToggle(Control sender) => AddDesignedItemHere(DesignedItemKind.Toggle, false);
    private void OnAddSeparator(Control sender) => AddDesignedItemHere(DesignedItemKind.Separator, false);

    private void MoveChosenItem(bool earlier)
    {
        var surface = _surface;
        String chosen = SelectedItemName;
        if (surface == null || chosen == "")
            return;
        ((DesignSurface)surface).MoveDesignedItem(chosen, earlier);
        RefreshItems();
        SelectItem(chosen);
    }

    private void OnMoveUp(Control sender) => MoveChosenItem(true);
    private void OnMoveDown(Control sender) => MoveChosenItem(false);

    private void OnDelete(Control sender)
    {
        var surface = _surface;
        String chosen = SelectedItemName;
        if (surface == null || chosen == "")
            return;
        var designer = (DesignSurface)surface;
        designer.SelectComponent(chosen);
        designer.DeleteSelectedComponent();
        RefreshItems();
    }

    private void OnCloseClicked(Control sender) => Hide();

    /// Closing the window hides it, as the find window's does: it is made once
    /// and pointed at whichever menu is double-clicked next.
    protected override void OnClosing(CancelEventArgs args)
    {
        base.OnClosing(args);
        args.Cancel = true;
        Hide();
    }
}
