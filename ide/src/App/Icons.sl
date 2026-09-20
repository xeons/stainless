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

// The toolbar's icons: PNGs that travel inside the binary.
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
// **They are ordinary PNGs** in `icons/`, editable in anything. Redrawing one
// is opening it, changing it and rebuilding -- there is no generator to run
// and no intermediate form to regenerate.
//
// The one thing this asks for is a decoder: `Image.FromBytes` needs GDI+ on
// Windows or libgd on Linux. Where neither is there, `BuildIcons` answers null
// and the toolbar is its captions, which is what it was before it had pictures.
module Ide.App;

import Standard.Collections;
import Forms;
import Forms.Drawing;

/// The files themselves, in the order the toolbar's buttons want them.
///
/// `readonly`, so they land in the read-only section and no thread can be the
/// one that changed them.
public static class IconFiles
{
    [Embed("icons/build.png")]
    public static readonly byte[] Build;

    [Embed("icons/rebuild.png")]
    public static readonly byte[] Rebuild;

    [Embed("icons/clean.png")]
    public static readonly byte[] Clean;

    [Embed("icons/run.png")]
    public static readonly byte[] Run;

    [Embed("icons/stop.png")]
    public static readonly byte[] Stop;

    [Embed("icons/start.png")]
    public static readonly byte[] Start;

    [Embed("icons/pause.png")]
    public static readonly byte[] Pause;

    [Embed("icons/stopdebug.png")]
    public static readonly byte[] StopDebug;

    [Embed("icons/stepinto.png")]
    public static readonly byte[] StepInto;

    [Embed("icons/stepover.png")]
    public static readonly byte[] StepOver;

    [Embed("icons/stepout.png")]
    public static readonly byte[] StepOut;

    [Embed("icons/restart.png")]
    public static readonly byte[] Restart;
}

/// Every icon as one list, or null if they could not be decoded.
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

    if (!AddIcon(list, IconFiles.Build))     return null;
    if (!AddIcon(list, IconFiles.Rebuild))   return null;
    if (!AddIcon(list, IconFiles.Clean))     return null;
    if (!AddIcon(list, IconFiles.Run))       return null;
    if (!AddIcon(list, IconFiles.Stop))      return null;
    if (!AddIcon(list, IconFiles.Start))     return null;
    if (!AddIcon(list, IconFiles.Pause))     return null;
    if (!AddIcon(list, IconFiles.StopDebug)) return null;
    if (!AddIcon(list, IconFiles.StepInto))  return null;
    if (!AddIcon(list, IconFiles.StepOver))  return null;
    if (!AddIcon(list, IconFiles.StepOut))   return null;
    if (!AddIcon(list, IconFiles.Restart))   return null;

    return list;
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
