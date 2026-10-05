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

// The common dialogs on AppKit: open and save panels, and the colour and font
// panels run as modal windows.
//
// **A Mac panel has no list of filters to choose between.** The seam's
// filters become the file types the panel lets be chosen, every pattern of
// every filter at once; one that allows everything -- `*` or `*.*` -- lifts
// the restriction.
//
// **The colour and font panels have no Cancel.** They are AppKit's shared
// floating panels, which apply what is chosen as it is chosen; run modally
// here, closing one is the answer, and what it shows then is what was chosen.
module Forms.Platform.AppKit;

import Standard.Collections;
import Standard.Text;
import Forms.Drawing;
import Forms.Platform;
#if MACOS && FORMS_APPKIT
import Standard.ObjC;
import MacOS.System;
import MacOS.CoreFoundation;
import MacOS.CoreGraphics;
import MacOS.Foundation;
import MacOS.AppKit;
import MacOS.UniformTypeIdentifiers;

/// `NSModalResponseOK`.
const NSModalResponse ModalAnswerOk = 1;

/// The file types `filters` allow, or none for any: the extension of each
/// pattern, from descriptions and patterns alternating. AppKit takes an empty
/// list as any type, and refuses no list at all.
NSArray FindAllowedTypes(String[] filters)
{
    var types = NSMutableArray.Array();
    for (nuint i = 1u; i < filters.Length; i += 2u)
    {
        var patterns = filters[i].Split(';');
        for (nuint p = 0u; p < patterns.Length; p++)
        {
            var one = patterns[p].Trim();
            if (one == "*" || one == "*.*")
                return NSArray.Array();
            long dot = one.LastIndexOf(".");
            if (dot >= 0)
            {
                var type = UTType.TypeWithFilenameExtension(ToNSString(one.Substring((nuint)dot + 1u)));
                if (type != null)
                    types.AddObject((UTType)type);
            }
        }
    }
    return types;
}

/// Points a panel at where `start` names: a folder, or a file in one, whose
/// name a save panel offers.
void ApplyStartPlace(NSSavePanel panel, String start, bool naming)
{
    if (start == "")
        return;
    var manager = NSFileManager.DefaultManager;
    bool folder = false;
    if (manager.FileExistsAtPathIsDirectory(ToNSString(start), &folder) && folder)
    {
        panel.DirectoryURL = NSURL.FileURLWithPath(ToNSString(start));
        return;
    }
    long slash = start.LastIndexOf("/");
    if (slash >= 0)
    {
        panel.DirectoryURL = NSURL.FileURLWithPath(ToNSString(start.Substring(0u, (nuint)slash)));
        if (naming)
            panel.NameFieldStringValue = ToNSString(start.Substring((nuint)slash + 1u));
    }
    else if (naming)
    {
        panel.NameFieldStringValue = ToNSString(start);
    }
}

/// The path a panel chose, or why there is none.
Result<String, DialogOutcome> FindChosenPath(NSSavePanel panel, NSModalResponse answer)
{
    if (answer != ModalAnswerOk)
        return Fail(DialogOutcome.Canceled);
    var url = panel.URL;
    var path = url == null ? null : ((NSURL)url).Path;
    if (path == null)
        return Fail(DialogOutcome.Failed);
    return Ok(FromNSString((NSString)path));
}

Result<String, DialogOutcome> ShowOpenPanel(String title, String start, String[] filters, bool folders)
{
    var panel = NSOpenPanel.OpenPanel();
    panel.Message = ToNSString(title);
    panel.CanChooseFiles = !folders;
    panel.CanChooseDirectories = folders;
    panel.AllowsMultipleSelection = false;
    if (!folders)
        panel.AllowedContentTypes = FindAllowedTypes(filters);
    ApplyStartPlace(panel, start, false);
    return FindChosenPath(panel, panel.RunModal());
}

Result<String, DialogOutcome> ShowSavePanel(String title, String start, String[] filters)
{
    var panel = NSSavePanel.SavePanel();
    panel.Message = ToNSString(title);
    panel.AllowedContentTypes = FindAllowedTypes(filters);
    ApplyStartPlace(panel, start, true);
    return FindChosenPath(panel, panel.RunModal());
}

/// Ends the modal run of the panel it is the delegate of when it closes.
public objc class FormsPanelCloser : NSObject, NSWindowDelegate
{
    public void WindowWillClose(NSNotification notification) => NSApplication.SharedApplication.StopModal();
}

/// Runs a shared panel modally until it is closed.
void RunPanelModally(NSPanel panel)
{
    var closer = FormsPanelCloser.Alloc().Init()!;
    var was = panel.Delegate;
    panel.Delegate = closer;
    panel.Center();
    NSApplication.SharedApplication.RunModalForWindow(panel);
    panel.Delegate = was;
}

Result<Color, DialogOutcome> ShowColorPanel(Color start)
{
    var panel = NSColorPanel.SharedColorPanel;
    panel.ShowsAlpha = false;
    panel.Color = ToNSColor(start);
    RunPanelModally(panel);
    return Ok(FromNSColor(panel.Color));
}

/// The font the panel shows, read back as the seam's: its family, its size in
/// this library's points, and whether it is bold and italic.
Result<Forms.Drawing.Font, DialogOutcome> ShowFontPanel(Forms.Drawing.Font start)
{
    var manager = NSFontManager.SharedFontManager;
    var original = ((AppKitFontBackend)start.Resource).Font;
    manager.SetSelectedFontIsMultiple(original, false);
    RunPanelModally(NSFontPanel.SharedFontPanel);

    var chosen = manager.ConvertFont(original);
    var traits = manager.TraitsOfFont(chosen);
    var style = FontStyle.Regular;
    if (traits.HasFlag(NSFontTraitMask.BoldFontMask))
        style = style | FontStyle.Bold;
    if (traits.HasFlag(NSFontTraitMask.ItalicFontMask))
        style = style | FontStyle.Italic;
    var family = chosen.FamilyName;
    return Ok(new Forms.Drawing.Font(family == null ? start.Family : FromNSString((NSString)family),
                                     RoundToInt(chosen.PointSize * 72.0 / 96.0), style));
}

#endif
