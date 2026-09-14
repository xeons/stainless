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

// The common dialogs, and the timer.
//
// **The file dialogs were already written.** `bindings/win32/Dialogs.sl` has
// open, save and folder by both routes -- the legacy `GetOpenFileNameW` and the
// `IFileDialog` COM interface Vista introduced -- so what is here is the
// translation between its answer and the seam's, and nothing else. The COM
// route is the one used: it is what every Windows program has shown since 2007,
// and the legacy one is a fallback for nothing in particular.
//
// The colour and font choosers have no such wrapper, so they are driven here
// from `comdlg32` directly.
module Forms.Platform.Win32;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;
#if WINDOWS
import Win32;
import Win32.Handles;
import Win32.Kernel32;
import Win32.User32;
import Win32.Gdi32;
import Win32.ComDlg32;
import Win32.Com;
import Win32.Dialogs;
import Standard.Path;

#pragma comment(lib, "comdlg32")

/// The window handle behind an optional owner.
HWND OwnerWindowOf(IWindowPeer? owner) {
    if (owner == null) { return null; }
    return (HWND)(void*)((IWindowPeer)owner).Handle();
}

/// A dialog error, as this layer reports it.
///
/// Everything `Win32.Dialogs` can fail with other than "the user said no" is
/// `Failed`: a program can do nothing different about a COM failure than about
/// a missing library, and the distinction belongs in a log rather than in a
/// type every caller has to match on.
DialogOutcome OutcomeOf(DialogError why) {
    if (why == DialogError.Cancelled) { return DialogOutcome.Cancelled; }
    return DialogOutcome.Failed;
}

public Result<String, DialogOutcome> OpenFileDialog(IWindowPeer? owner, String title,
                                                    String start, String[] filters) {
    // `ChooseFileIn` takes a folder to open in; `start` here is a whole path,
    // so the folder is what it sits in and the file name is the suggestion the
    // open dialog has no use for.
    var chosen = start.ByteLength() > 0u
        ? Dialogs.ChooseFileIn(OwnerWindowOf(owner), title, filters,
                               Standard.Path.DirectoryName(start))
        : Dialogs.ChooseFile(OwnerWindowOf(owner), title, filters);
    if (!chosen.Ok) { return Fail(OutcomeOf(chosen.Error)); }
    return Ok(chosen.Value);
}

public Result<String, DialogOutcome> SaveFileDialog(IWindowPeer? owner, String title,
                                                    String start, String[] filters) {
    var chosen = Dialogs.ChooseSaveFile(OwnerWindowOf(owner), title, filters,
                                        Standard.Path.FileName(start), "");
    if (!chosen.Ok) { return Fail(OutcomeOf(chosen.Error)); }
    return Ok(chosen.Value);
}

public Result<String, DialogOutcome> FolderDialogFor(IWindowPeer? owner, String title) {
    var chosen = Dialogs.ChooseFolder(OwnerWindowOf(owner), title);
    if (!chosen.Ok) { return Fail(OutcomeOf(chosen.Error)); }
    return Ok(chosen.Value);
}

// ================================================================ colour

/// Chooses a colour.
///
/// The custom colours are a sixteen-entry array the dialog reads *and writes*,
/// so that what a user mixed is still there the next time. Kept here, module
/// wide, because that is the whole point of it -- a fresh array each time would
/// give the user an empty palette on every showing.
static uint[] customColours = new uint[16];

public Result<Color, DialogOutcome> ColorDialogFor(IWindowPeer? owner, Color start) {
    ChooseColor choose;
    choose.Size = (uint)sizeof(ChooseColor);
    choose.Owner = OwnerWindowOf(owner);
    choose.Instance = null;
    choose.Result = ToColorRef(start);
    choose.CustomColors = &customColours[0u];
    // `CC_RGBINIT` is what makes `Result` the colour it opens on rather than
    // black; without it the field is write-only and the argument is ignored.
    choose.Flags = CcRgbInit | CcFullOpen | CcAnyColor;
    choose.CustomData = 0;
    choose.Hook = null;
    choose.TemplateName = null;

    if (ChooseColorW(&choose) == 0) {
        return Fail(CommDlgExtendedError() == 0u
            ? DialogOutcome.Cancelled : DialogOutcome.Failed);
    }
    return Ok(FromColorRef(choose.Result));
}

// ================================================================== font

public Result<Font, DialogOutcome> FontDialogFor(IWindowPeer? owner, Font start) {
    HDC screen = GetDC(null);
    int dpi = GetDeviceCaps(screen, DeviceCapsLogicalPixelsY);
    ReleaseDC(null, screen);
    if (dpi <= 0) { dpi = 96; }

    LogFont described;
    described.Height = -(start.Size * dpi / 72);
    described.Width = 0;
    described.Escapement = 0;
    described.Orientation = 0;
    described.Weight = start.Bold ? FontBold : FontNormal;
    described.Italic = (byte)(start.Italic ? 1 : 0);
    described.Underline = (byte)(start.Underline ? 1 : 0);
    described.StrikeOut = (byte)(start.Strikeout ? 1 : 0);
    described.CharSet = (byte)1;
    described.OutPrecision = (byte)0;
    described.ClipPrecision = (byte)0;
    described.Quality = (byte)0;
    described.PitchAndFamily = (byte)0;
    CopyFaceName(&described, start.Family);

    ChooseFont choose;
    choose.Size = (uint)sizeof(ChooseFont);
    choose.Owner = OwnerWindowOf(owner);
    choose.Dc = null;
    choose.LogFont = &described;
    choose.PointSize = start.Size * 10;
    choose.Flags = CfInitToLogFontStruct | CfScreenFonts | CfEffects;
    choose.Colors = 0u;
    choose.CustomData = 0;
    choose.Hook = null;
    choose.TemplateName = null;
    choose.Instance = null;
    choose.Style = null;
    choose.FontType = (ushort)0;
    choose.Reserved = (ushort)0;
    choose.SizeMin = 0;
    choose.SizeMax = 0;

    if (ChooseFontW(&choose) == 0) {
        return Fail(CommDlgExtendedError() == 0u
            ? DialogOutcome.Cancelled : DialogOutcome.Failed);
    }

    var style = FontStyle.Regular;
    if (described.Weight >= FontBold)  { style = style | FontStyle.Bold; }
    if (described.Italic != (byte)0)       { style = style | FontStyle.Italic; }
    if (described.Underline != (byte)0)    { style = style | FontStyle.Underline; }
    if (described.StrikeOut != (byte)0)    { style = style | FontStyle.Strikeout; }

    // `PointSize` is in tenths, which is the one place Windows measures a font
    // in something other than pixels.
    return Ok(new Font(FaceNameOf(&described), choose.PointSize / 10, style));
}

/// Writes a face name into a `LOGFONT`'s fixed 32-unit array.
///
/// Truncated rather than refused: a face name longer than 31 characters does
/// not exist, and a dialog is not the place to complain about one.
void CopyFaceName(LogFont* into, String face) {
    var wide = face.ToUtf16();
    nuint units = wide.UnitCount();
    if (units > 31u) { units = 31u; }
    char16* source = wide.ToPointer();
    for (nuint i = 0u; i < units; i += 1u) { into->FaceName[i] = source[i]; }
    into->FaceName[units] = (char16)0;
}

String FaceNameOf(LogFont* described) {
    return Text.FromNullTerminatedUtf16(&described->FaceName[0u]);
}

// ================================================================== timer

/// A Windows timer, which posts `WM_TIMER` to a window rather than calling
/// back.
///
/// **It needs a window, and a `Timer` has none.** Windows will run a timer with
/// no window -- `SetTimer(null, ...)` -- but the message then goes to the
/// thread's queue with no window to dispatch it to, and `DispatchMessage` drops
/// it. So this makes a message-only window: a real window that is never shown,
/// never laid out and never painted, whose whole job is to have an address the
/// timer can post to.
public class TimerPeer : ITimerPeer {
    HWND window;
    weak ITimerNotify? target;
    ulong id;
    bool running;

    public TimerPeer(ITimerNotify owner) {
        target = owner;
        id = 1u;
        running = false;
        EnsureFormClass();
        // `HWND_MESSAGE` as the parent is what makes it message-only.
        window = CreateWindowExW(0u, FormClassName.ToUtf16().ToPointer(),
                                 "".ToUtf16().ToPointer(), 0u, 0, 0, 0, 0,
                                 MessageOnlyParent(), null,
                                 GetModuleHandleW(null), null);
        BindTimer(window, this);
    }

    ~TimerPeer() {
        Stop();
        if (window != null) {
            UnbindPeer(window);
            DestroyWindow(window);
            window = null;
        }
    }

    public void Start(int milliseconds) {
        if (milliseconds <= 0) { return; }
        SetTimer(window, id, (uint)milliseconds, null);
        running = true;
    }

    public void Stop() {
        if (!running) { return; }
        KillTimer(window, id);
        running = false;
    }

    /// Called by the window procedure when `WM_TIMER` arrives.
    public void Fire() {
        ITimerNotify? held = target;
        if (held == null) { return; }
        ((ITimerNotify)held).OnPlatformTick();
    }
}

/// `HWND_MESSAGE`: a parent that makes a window exist without being on screen.
HWND MessageOnlyParent() { return (HWND)(void*)(nuint)(nint)(-3); }

#endif
