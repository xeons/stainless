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

// The bars on AppKit: a tab control, a toolbar and a status bar.
//
// **Only the tab control is one AppKit control.** `NSToolbar` belongs to a
// window's title bar and cannot be docked inside a form, and AppKit has no
// status bar at all; the LCL's Cocoa widgetset draws both. Here each is a
// flipped view holding native parts -- buttons for a toolbar, labels for a
// status bar -- laid out by the peer.
module Forms.Platform.AppKit;

import Standard.Collections;
import Standard.Text;
import Forms;
import Forms.Drawing;
import Forms.Platform;
#if MACOS && FORMS_APPKIT
import Standard.ObjC;
import MacOS.System;
import MacOS.CoreFoundation;
import MacOS.CoreGraphics;
import MacOS.Foundation;
import MacOS.AppKit;

// ================================================================ tab control

/// What a tab view tells its peer: the user chose a tab.
public objc class FormsTabDelegate : NSObject, NSTabViewDelegate
{
    public weak AppKitTabControlPeer? Peer;

    public void TabViewDidSelectTabViewItem(NSTabView tabView, NSTabViewItem? tabViewItem)
    {
        AppKitTabControlPeer? peer = Peer;
        if (peer != null)
            ((AppKitTabControlPeer)peer).ReportSelection();
    }
}

/// An `NSTabView`, with a flipped view behind each tab that the page's
/// controls go in.
///
/// **A page's panel arrives before its tab.** `TabPage` makes its panel --
/// which is what reaches `AddChild` -- and only then registers the tab, so the
/// panel waits here for `AddTab` to make the view it goes in, as on GTK.
public class AppKitTabControlPeer : AppKitContainerPeer, ITabControlPeer
{
    NSTabView _tabs;
    List<FormsView> _pages;
    FormsTabDelegate _delegate;
    AppKitPeer? _waiting;
    bool _quiet;

    public AppKitTabControlPeer(IControlNotify owner)
    {
        _tabs = NSTabView.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 200.0, 150.0));
        _pages = new List<FormsView>();
        _delegate = FormsTabDelegate.Alloc().Init()!;
        _waiting = null;
        _quiet = false;
        base(_tabs, owner);
        _delegate.Peer = this;
        _tabs.Delegate = _delegate;
    }

    protected override void ForgetReporters()
    {
        base.ForgetReporters();
        _delegate.Peer = null;
    }

    /// The page showing, where a child added now belongs.
    protected override NSView Content
    {
        get
        {
            int at = GetSelectedTab();
            return at >= 0 && (nuint)at < _pages.Count ? _pages[(nuint)at] : View;
        }
    }

    public void ReportSelection()
    {
        var owner = Owner;
        if (!_quiet && owner != null)
            ((IControlNotify)owner).OnPlatformValueChanged();
    }

    void RunQuietly(Action change)
    {
        bool was = _quiet;
        _quiet = true;
        change();
        _quiet = was;
    }

    /// Holds the child until `AddTab` has a page to put it on.
    public override void AddChild(IControlPeer child)
    {
        var added = (AppKitPeer)child;
        added.View.RemoveFromSuperview();
        _waiting = added;
    }

    public int AddTab(String text, int image)
    {
        var page = CreateFormsView();
        var item = NSTabViewItem.Alloc().InitWithIdentifier(null);
        item.Label = ToNSString(text);
        item.View = page;
        int index = (int)_pages.Count;
        _pages.Add(page);
        RunQuietly(() => { _tabs.AddTabViewItem(item); });

        if (_waiting is AppKitPeer held)
        {
            page.AddSubview(held.View);
            _waiting = null;
        }
        return index;
    }

    public void RemoveTab(int index)
    {
        if (index < 0 || index >= TabCount)
            return;
        var item = _tabs.TabViewItemAtIndex((NSInteger)index);
        RunQuietly(() => { _tabs.RemoveTabViewItem(item); });
        _pages.RemoveAt((nuint)index);
    }

    public void SetTabText(int index, String text)
    {
        if (index >= 0 && index < TabCount)
            _tabs.TabViewItemAtIndex((NSInteger)index).Label = ToNSString(text);
    }

    public void SetSelectedTab(int index)
    {
        if (index >= 0 && index < TabCount)
            RunQuietly(() => { _tabs.SelectTabViewItemAtIndex((NSInteger)index); });
    }

    public int GetSelectedTab()
    {
        var chosen = _tabs.SelectedTabViewItem;
        if (chosen == null)
            return -1;
        return (int)_tabs.IndexOfTabViewItem((NSTabViewItem)chosen);
    }

    public int TabCount => (int)_tabs.NumberOfTabViewItems;

    /// The room inside the tabs and the frame. A page's view is that size, so
    /// a page's controls are placed from its corner.
    public FRect PageArea
    {
        get
        {
            var inside = _tabs.ContentRect;
            return CreateRectangle(0, 0, RoundToInt(inside.size.width), RoundToInt(inside.size.height));
        }
    }

    /// A tab shows its caption only, as on GTK.
    public void SetImages(IImageListBackend? images) { }

    public override void SetFont(Forms.Drawing.Font font) => _tabs.Font = ((AppKitFontBackend)font.Resource).Font;

    public override void SetBackColor(Color color) { }

    public override bool AcceptsTabFocus => false;
}

// ================================================================ status bar

/// A row of panels along the bottom of a form: a label in each, with a line
/// between them.
public class AppKitStatusBarPeer : AppKitPeer, IStatusBarPeer
{
    List<NSTextField> _labels;
    List<NSBox> _lines;
    int[] _edges;
    NSFont _font;

    public AppKitStatusBarPeer(IControlNotify owner)
    {
        _labels = new List<NSTextField>();
        _lines = new List<NSBox>();
        _edges = new int[0u];
        _font = NSFont.SystemFontOfSize(NSFont.SmallSystemFontSize);
        base(CreateFormsView(), owner);
    }

    public void SetPanels(int[] edges)
    {
        foreach (var label in _labels)
            label.RemoveFromSuperview();
        foreach (var line in _lines)
            line.RemoveFromSuperview();
        _labels.Clear();
        _lines.Clear();
        _edges = edges;

        for (nuint i = 0u; i < edges.Length; i++)
        {
            var label = NSTextField.LabelWithString(ToNSString(""));
            label.Font = _font;
            label.LineBreakMode = NSLineBreakMode.TruncatingTail;
            View.AddSubview(label);
            _labels.Add(label);

            if (i + 1u < edges.Length)
            {
                var line = NSBox.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 1.0, 10.0));
                line.BoxType = NSBoxType.Separator;
                View.AddSubview(line);
                _lines.Add(line);
            }
        }
        ArrangePanels();
    }

    public void SetPanelText(int index, String text)
    {
        if (index >= 0 && (nuint)index < _labels.Count)
            _labels[(nuint)index].StringValue = ToNSString(text);
    }

    /// Each panel from the edge before it to its own, the last to the end
    /// when its edge is -1, with its text centred in the bar's height.
    void ArrangePanels()
    {
        double height = (double)LastBounds.Height;
        double width = (double)LastBounds.Width;
        double left = 0.0;
        for (nuint i = 0u; i < _labels.Count; i++)
        {
            double edge = _edges[i] < 0 ? width : (double)_edges[i];
            if (edge > width)
                edge = width;
            var label = _labels[i];
            double tall = label.FittingSize.height;
            double room = edge - left - 8.0;
            label.Frame = MakeNSRect(left + 4.0, (height - tall) / 2.0, room < 0.0 ? 0.0 : room, tall);
            if (i < _lines.Count)
                _lines[i].Frame = MakeNSRect(edge, 3.0, 1.0, height - 6.0 < 0.0 ? 0.0 : height - 6.0);
            left = edge + 1.0;
        }
    }

    public override void SetBounds(FRect bounds)
    {
        base.SetBounds(bounds);
        ArrangePanels();
    }

    public override void SetFont(Forms.Drawing.Font font)
    {
        _font = ((AppKitFontBackend)font.Resource).Font;
        foreach (var label in _labels)
            label.Font = _font;
        ArrangePanels();
    }

    public override void SetForeColor(Color color)
    {
        foreach (var label in _labels)
            label.TextColor = ToNSColor(color);
    }

    /// As tall as a line of the small font with room around it.
    public override FSize PreferredSize =>
        CreateSize(LastBounds.Width, FloorToInt(_font.Ascender - _font.Descender + _font.Leading) + 8);

    public override bool AcceptsTabFocus => false;
}

// ================================================================ toolbar

/// The target of every button on a toolbar, which says which by its tag.
public objc class FormsToolTarget : NSObject
{
    public weak AppKitToolBarPeer? Peer;

    [Selector("tool:")]
    public void Tool(AnyObject? sender)
    {
        AppKitToolBarPeer? peer = Peer;
        if (peer != null && sender is NSButton button)
            ((AppKitToolBarPeer)peer).ReportTool((int)button.Tag);
    }
}

/// A row of buttons that show their border only under the pointer, as the
/// buttons of a bar inside a Mac window do, with a line for a separator.
///
/// **AppKit sends no action for a state the program set**, so a toggle set by
/// `SetButtonChecked` reports nothing, which is the seam's rule as it stands.
public class AppKitToolBarPeer : AppKitPeer, IToolBarPeer
{
    /// Each item: a button, or a separator's line.
    List<NSView> _items;
    List<ToolButtonKind> _kinds;
    List<String> _texts;
    List<int> _pictures;
    FormsToolTarget _target;
    AppKitImageListBackend? _images;
    bool _showText;
    NSFont? _font;

    public AppKitToolBarPeer(IControlNotify owner)
    {
        _items = new List<NSView>();
        _kinds = new List<ToolButtonKind>();
        _texts = new List<String>();
        _pictures = new List<int>();
        _target = FormsToolTarget.Alloc().Init()!;
        _images = null;
        _showText = false;
        _font = null;
        base(CreateFormsView(), owner);
        _target.Peer = this;
    }

    protected override void ForgetReporters()
    {
        base.ForgetReporters();
        _target.Peer = null;
    }

    public void ReportTool(int index)
    {
        var owner = Owner;
        if (owner != null)
            ((IControlNotify)owner).OnPlatformToolClicked(index);
    }

    public int AddButton(String text, int image, ToolButtonKind kind)
    {
        int index = (int)_items.Count;
        if (kind == ToolButtonKind.Separator)
        {
            var line = NSBox.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 1.0, 16.0));
            line.BoxType = NSBoxType.Separator;
            _items.Add(line);
            View.AddSubview(line);
        }
        else
        {
            var button = NSButton.Alloc().InitWithFrame(MakeNSRect(0.0, 0.0, 32.0, 28.0));
            button.SetButtonType(kind == ToolButtonKind.Toggle ? NSButtonType.PushOnPushOff
                                                               : NSButtonType.MomentaryPushIn);
            button.BezelStyle = NSBezelStyle.Recessed;
            button.ShowsBorderOnlyWhileMouseInside = true;
            button.Tag = (NSInteger)index;
            button.Target = _target;
            button.Action = Selector.Named("tool:");
            var font = _font;
            if (font != null)
                button.Font = (NSFont)font;
            _items.Add(button);
            View.AddSubview(button);
        }
        _kinds.Add(kind);
        _texts.Add(text);
        _pictures.Add(image);
        ApplyFace(index);
        ArrangeItems();
        return index;
    }

    /// One button's picture and caption: the caption under the picture when
    /// text is shown, the caption alone with no picture, and otherwise the
    /// picture alone with the caption as its tooltip.
    void ApplyFace(int index)
    {
        if (!(_items[(nuint)index] is NSButton button))
            return;
        String text = _texts[(nuint)index];
        var picture = FindListPicture(_images, _pictures[(nuint)index]);
        button.Image = picture;
        bool captioned = _showText || picture == null;
        button.Title = ToNSString(captioned ? text : "");
        button.ToolTip = captioned || text == "" ? null : ToNSString(text);
        button.ImagePosition = picture == null ? NSCellImagePosition.NoImage
                               : _showText ? NSCellImagePosition.ImageAbove
                               : NSCellImagePosition.ImageOnly;
    }

    /// The items left to right from the bar's corner, each its own width and
    /// centred in the bar's height.
    void ArrangeItems()
    {
        double height = (double)LastBounds.Height;
        double x = 4.0;
        foreach (var item in _items)
        {
            if (item is NSButton button)
            {
                var fitting = button.FittingSize;
                double wide = fitting.width < 28.0 ? 28.0 : fitting.width;
                button.Frame = MakeNSRect(x, (height - fitting.height) / 2.0, wide, fitting.height);
                x += wide + 2.0;
            }
            else
            {
                item.Frame = MakeNSRect(x + 3.0, 4.0, 1.0, height - 8.0 < 0.0 ? 0.0 : height - 8.0);
                x += 8.0;
            }
        }
    }

    public nuint GetButtonId(int index)
    {
        if (index < 0 || (nuint)index >= _items.Count)
            return 0u;
        return (nuint)(byte*)_items[(nuint)index];
    }

    public void SetButtonEnabled(int index, bool enabled)
    {
        if (index >= 0 && (nuint)index < _items.Count && _items[(nuint)index] is NSButton button)
            button.Enabled = enabled;
    }

    public void SetButtonChecked(int index, bool checked)
    {
        if (index < 0 || (nuint)index >= _items.Count || _kinds[(nuint)index] != ToolButtonKind.Toggle)
            return;
        if (_items[(nuint)index] is NSButton button)
            button.State = checked ? 1 : 0;
    }

    public bool GetButtonChecked(int index)
    {
        if (index < 0 || (nuint)index >= _items.Count || _kinds[(nuint)index] != ToolButtonKind.Toggle)
            return false;
        return _items[(nuint)index] is NSButton button && button.State == 1;
    }

    public void SetImages(IImageListBackend? images)
    {
        _images = images == null ? null : (AppKitImageListBackend)images;
        for (int i = 0; i < (int)_items.Count; i++)
            ApplyFace(i);
        ArrangeItems();
    }

    public void SetTextVisible(bool visible)
    {
        _showText = visible;
        for (int i = 0; i < (int)_items.Count; i++)
            ApplyFace(i);
        ArrangeItems();
    }

    /// The bar's height is its tallest button's; the control layer reads it
    /// back through `PreferredSize`.
    public void ResizeToFit() => ArrangeItems();

    /// A native button draws itself, so the program does not.
    public bool SetOwnerDrawn(bool drawn) => false;

    public override FSize PreferredSize
    {
        get
        {
            double tallest = 24.0;
            double wide = 4.0;
            foreach (var item in _items)
            {
                if (item is NSButton button)
                {
                    var fitting = button.FittingSize;
                    if (fitting.height > tallest)
                        tallest = fitting.height;
                    wide += (fitting.width < 28.0 ? 28.0 : fitting.width) + 2.0;
                }
                else
                {
                    wide += 8.0;
                }
            }
            return CreateSize(RoundToInt(wide), RoundToInt(tallest) + 6);
        }
    }

    public override void SetBounds(FRect bounds)
    {
        base.SetBounds(bounds);
        ArrangeItems();
    }

    public override void SetFont(Forms.Drawing.Font font)
    {
        var shown = ((AppKitFontBackend)font.Resource).Font;
        _font = shown;
        foreach (var item in _items)
        {
            if (item is NSButton button)
                button.Font = shown;
        }
        ArrangeItems();
    }

    public override bool AcceptsTabFocus => false;
}

#endif
