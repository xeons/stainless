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

// The toolbar's and the toolbox's icons: PNGs that travel inside the binary.
//
// **`[Embed]` rather than a resource script, and not for the reason that first
// suggests itself.** Resources are not Windows-only here: the compiler
// compiles a `.rc` for an ELF target too and carries the result as ordinary
// data, `Standard.Resources` walks it, and `Bitmap.FromResource` works on both
// backends. That argument -- "an ELF has no resource section, so this cannot
// work" -- is one this tree has already made and already corrected, in
// `forms/README.md` and in `GtkWidgetSet.LoadBitmapResource`. It was wrong
// about the conclusion both times. This program even compiles a `.rc`
// already: `samples/forms/forms.rc` is one of its sources.
//
// The reason is that the declaration is the whole of it. `[Embed]` names a
// path beside this file, and the compiler checks it when the program is built.
// The resource route wants an entry in a script and a numeric id, living in
// two files that nothing compares -- which is fine for the handful of things a
// program has one of, and is a bookkeeping job per icon here.
//
// `Bitmap.FromResource` and `ImageList.AddResource` also would not do: they
// read an `RT_BITMAP`, which is a `.bmp`, which has no alpha -- so these would
// be magenta-keyed with a hard edge on every curve. A PNG can go in a script
// as `RCDATA` and come back through `Resources.Bytes` and `Image.FromBytes`,
// but that is this file's job done the long way round.
//
// **They are ordinary PNGs** in `icons/16/`, editable in anything. Redrawing
// one is opening it, changing it and rebuilding -- there is no generator to
// run and no intermediate form to regenerate. `icons/24/` and `icons/32/` are
// the same pictures drawn larger, for a window drawn at more than 96 DPI;
// this one is not, so only the sixteens are embedded.
//
// The one thing this asks for is a decoder: `Image.FromBytes` needs GDI+ on
// Windows or libgd on Linux. Where neither is there, `BuildIcons` answers null
// and the toolbar is its captions, which is what it was before it had pictures.
module Ide.App;

import Standard.Collections;
import Forms;
import Forms.Drawing;

/// The toolbar's pictures, in the order its buttons want them.
///
/// `readonly`, so they land in the read-only section and no thread can be the
/// one that changed them.
public static class IconFiles
{
    [Embed("icons/16/new.png")]
    public static readonly byte[] New;

    [Embed("icons/16/open.png")]
    public static readonly byte[] Open;

    [Embed("icons/16/save.png")]
    public static readonly byte[] Save;

    [Embed("icons/16/build.png")]
    public static readonly byte[] Build;

    [Embed("icons/16/rebuild.png")]
    public static readonly byte[] Rebuild;

    [Embed("icons/16/clean.png")]
    public static readonly byte[] Clean;

    [Embed("icons/16/run.png")]
    public static readonly byte[] Run;

    [Embed("icons/16/stop.png")]
    public static readonly byte[] Stop;

    [Embed("icons/16/start.png")]
    public static readonly byte[] Start;

    [Embed("icons/16/pause.png")]
    public static readonly byte[] Pause;

    [Embed("icons/16/stopdebug.png")]
    public static readonly byte[] StopDebug;

    [Embed("icons/16/stepinto.png")]
    public static readonly byte[] StepInto;

    [Embed("icons/16/stepover.png")]
    public static readonly byte[] StepOver;

    [Embed("icons/16/stepout.png")]
    public static readonly byte[] StepOut;

    [Embed("icons/16/restart.png")]
    public static readonly byte[] Restart;
}

/// One picture per type the designer can make, named as the type is.
public static class ToolboxIconFiles
{
    [Embed("icons/16/button.png")]
    public static readonly byte[] Button;

    [Embed("icons/16/label.png")]
    public static readonly byte[] Label;

    [Embed("icons/16/textbox.png")]
    public static readonly byte[] TextBox;

    [Embed("icons/16/checkbox.png")]
    public static readonly byte[] CheckBox;

    [Embed("icons/16/radiobutton.png")]
    public static readonly byte[] RadioButton;

    [Embed("icons/16/togglebutton.png")]
    public static readonly byte[] ToggleButton;

    [Embed("icons/16/listbox.png")]
    public static readonly byte[] ListBox;

    [Embed("icons/16/combobox.png")]
    public static readonly byte[] ComboBox;

    [Embed("icons/16/checklistbox.png")]
    public static readonly byte[] CheckListBox;

    [Embed("icons/16/spinedit.png")]
    public static readonly byte[] SpinEdit;

    [Embed("icons/16/progressbar.png")]
    public static readonly byte[] ProgressBar;

    [Embed("icons/16/trackbar.png")]
    public static readonly byte[] TrackBar;

    [Embed("icons/16/treeview.png")]
    public static readonly byte[] TreeView;

    [Embed("icons/16/listview.png")]
    public static readonly byte[] ListView;

    [Embed("icons/16/panel.png")]
    public static readonly byte[] Panel;

    [Embed("icons/16/groupbox.png")]
    public static readonly byte[] GroupBox;

    [Embed("icons/16/tabcontrol.png")]
    public static readonly byte[] TabControl;

    [Embed("icons/16/tabpage.png")]
    public static readonly byte[] TabPage;

    [Embed("icons/16/image.png")]
    public static readonly byte[] Image;

    [Embed("icons/16/paintbox.png")]
    public static readonly byte[] PaintBox;

    [Embed("icons/16/shape.png")]
    public static readonly byte[] Shape;

    [Embed("icons/16/bevel.png")]
    public static readonly byte[] Bevel;

    [Embed("icons/16/toolbar.png")]
    public static readonly byte[] ToolBar;

    [Embed("icons/16/mainmenu.png")]
    public static readonly byte[] MainMenu;

    [Embed("icons/16/timer.png")]
    public static readonly byte[] Timer;

    [Embed("icons/16/commandlist.png")]
    public static readonly byte[] CommandList;

    [Embed("icons/16/scrollbox.png")]
    public static readonly byte[] ScrollBox;

    [Embed("icons/16/frame.png")]
    public static readonly byte[] Frame;
}

/// Every toolbar icon as one list, or null if they could not be decoded.
///
/// The order MUST match the `Icon*` constants in `Shell.sl`. A toolbar whose
/// pictures are off by one is a toolbar where Clean says Run.
///
/// Null rather than an error: a toolbar with no pictures is the toolbar there
/// was before, and a message about a missing imaging library belongs nowhere a
/// person would read it.
public ImageList? BuildIcons()
{
    var list = new ImageList(16, 16);
    if (!AddIcon(list, IconFiles.New)) return null;
    if (!AddIcon(list, IconFiles.Open)) return null;
    if (!AddIcon(list, IconFiles.Save)) return null;
    if (!AddIcon(list, IconFiles.Build)) return null;
    if (!AddIcon(list, IconFiles.Rebuild)) return null;
    if (!AddIcon(list, IconFiles.Clean)) return null;
    if (!AddIcon(list, IconFiles.Run)) return null;
    if (!AddIcon(list, IconFiles.Stop)) return null;
    if (!AddIcon(list, IconFiles.Start)) return null;
    if (!AddIcon(list, IconFiles.Pause)) return null;
    if (!AddIcon(list, IconFiles.StopDebug)) return null;
    if (!AddIcon(list, IconFiles.StepInto)) return null;
    if (!AddIcon(list, IconFiles.StepOver)) return null;
    if (!AddIcon(list, IconFiles.StepOut)) return null;
    if (!AddIcon(list, IconFiles.Restart)) return null;
    return list;
}

/// The toolbox's icons, one per type in `typeNames` and in its order, or
/// null if they could not be decoded. A type with no picture of its own gets
/// the button's, so the indices stay in step.
public ImageList? BuildToolboxIcons(String[] typeNames)
{
    var list = new ImageList(16, 16);
    foreach (var name in typeNames)
    {
        if (!AddIcon(list, FindToolboxIconFile(name)))
            return null;
    }
    return list;
}

byte[] FindToolboxIconFile(String typeName)
{
    switch (typeName)
    {
        case "Button": return ToolboxIconFiles.Button;
        case "Label": return ToolboxIconFiles.Label;
        case "TextBox": return ToolboxIconFiles.TextBox;
        case "CheckBox": return ToolboxIconFiles.CheckBox;
        case "RadioButton": return ToolboxIconFiles.RadioButton;
        case "ToggleButton": return ToolboxIconFiles.ToggleButton;
        case "ListBox": return ToolboxIconFiles.ListBox;
        case "ComboBox": return ToolboxIconFiles.ComboBox;
        case "CheckListBox": return ToolboxIconFiles.CheckListBox;
        case "SpinEdit": return ToolboxIconFiles.SpinEdit;
        case "ProgressBar": return ToolboxIconFiles.ProgressBar;
        case "TrackBar": return ToolboxIconFiles.TrackBar;
        case "TreeView": return ToolboxIconFiles.TreeView;
        case "ListView": return ToolboxIconFiles.ListView;
        case "Panel": return ToolboxIconFiles.Panel;
        case "GroupBox": return ToolboxIconFiles.GroupBox;
        case "TabControl": return ToolboxIconFiles.TabControl;
        case "TabPage": return ToolboxIconFiles.TabPage;
        case "Image": return ToolboxIconFiles.Image;
        case "PaintBox": return ToolboxIconFiles.PaintBox;
        case "Shape": return ToolboxIconFiles.Shape;
        case "Bevel": return ToolboxIconFiles.Bevel;
        case "ToolBar": return ToolboxIconFiles.ToolBar;
        case "MainMenu": return ToolboxIconFiles.MainMenu;
        case "Timer": return ToolboxIconFiles.Timer;
        case "CommandList": return ToolboxIconFiles.CommandList;
        case "ScrollBox": return ToolboxIconFiles.ScrollBox;
        case "Frame": return ToolboxIconFiles.Frame;
        default: return ToolboxIconFiles.Button;
    }
}

/// Decodes one embedded PNG and adds it.
///
/// The decoded image is let go of at the end of this, which frees it: it is
/// the crossing that matters, and `Bitmap.FromImage` copies, so what the
/// widget set holds afterwards owes nothing to the picture it came from.
bool AddIcon(ImageList list, byte[] file)
{
    var decoded = Standard.Drawing.Image.FromBytes(file);
    if (!decoded.Ok)
        return false;

    var made = Bitmap.FromImage(decoded.Value);
    if (!made.Ok)
        return false;
    return list.Add(made.Value) >= 0;
}
