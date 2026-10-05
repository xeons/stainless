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

// The AppKit widget set: the application, its loop, and the factory.
//
// **`NSApplication` is the loop.** It is made, told it is an ordinary
// application with a Dock icon, and finished launching here, so a program
// that never calls `Run` still has windows that draw and take input through
// `PumpEvents`.
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

[DoesNotReturn]
extern "C" void sl_fail(byte* message);

/// What a later phase of this backend adds, refused by name meanwhile.
T RefuseAppKitControl<T>(String what)
{
    sl_fail(("the AppKit backend has no " + what + " yet; build with FORMS_GTK to use GTK").ToPointer());
}

/// The directory `STAINLESS_FORMS_SHOT` names, or null for none.
public String? FindScreenshotDirectory() => Standard.Env.GetEnvironmentVariable("STAINLESS_FORMS_SHOT");

/// A form's content as AppKit draws it, written as a PNG named after its title
/// into `directory`.
///
/// **What a screenshot is for when there is no screen to grab.** Over ssh a
/// program cannot read the display without Screen Recording permission;
/// `cacheDisplayInRect:` asks the view to draw itself into a bitmap, which
/// needs none -- the same as `forms/screenshot.ps1`'s `PrintWindow`. Taken
/// after every `PumpEvents` and as the program closes a form.
public void WriteWindowScreenshot(NSWindow window, String directory)
{
    var content = window.ContentView;
    if (!window.Visible || content == null || !((NSView)content is FormsView))
        return;
    var view = (NSView)content;
    var bitmap = view.BitmapImageRepForCachingDisplayInRect(view.Bounds);
    if (bitmap == null)
        return;
    view.CacheDisplayInRectToBitmapImageRep(view.Bounds, (NSBitmapImageRep)bitmap);
    var png = ((NSBitmapImageRep)bitmap).RepresentationUsingTypeProperties(NSBitmapImageFileType.PNG,
                                                                          NSDictionary.Dictionary());
    String title = FromNSString(window.Title).Replace("/", "-");
    if (png != null)
        ((NSData)png).WriteToFileAtomically(ToNSString(directory + "/" + (title == "" ? "window" : title) + ".png"), true);
}

/// What another thread asks the main thread to do: run what it posted.
public objc class FormsWaker : NSObject
{
    [Selector("wake")]
    public void Wake() => Application.RunPostedWork();
}

/// A timer, as an `NSTimer` on the main run loop in every mode -- so it still
/// ticks while a modal window or a menu is tracking.
public class AppKitTimerPeer : ITimerPeer
{
    weak ITimerNotify? _owner;
    NSTimer? _timer;

    public AppKitTimerPeer(ITimerNotify owner)
    {
        _owner = owner;
        _timer = null;
    }

    ~AppKitTimerPeer() { Stop(); }

    public void Start(int milliseconds)
    {
        Stop();
        var relay = new TimerRelay(this);
        var timer = NSTimer.TimerWithTimeIntervalRepeatsBlock((double)milliseconds / 1000.0, true,
                                                              (fired) => relay.Tick());
        NSRunLoop.MainRunLoop.AddTimerForMode(timer, NSRunLoopCommonModes);
        _timer = timer;
    }

    public void Stop()
    {
        var timer = _timer;
        if (timer == null)
            return;
        ((NSTimer)timer).Invalidate();
        _timer = null;
    }

    public void ReportTick()
    {
        ITimerNotify? owner = _owner;
        if (owner != null)
            ((ITimerNotify)owner).OnPlatformTick();
    }
}

/// What a timer's block holds instead of the peer, so a running timer does
/// not keep its peer alive.
class TimerRelay
{
    weak AppKitTimerPeer? _peer;

    public TimerRelay(AppKitTimerPeer peer) => _peer = peer;

    public void Tick()
    {
        AppKitTimerPeer? peer = _peer;
        if (peer != null)
            ((AppKitTimerPeer)peer).ReportTick();
    }
}

public class AppKitWidgetSet : IWidgetSet
{
    NSApplication _application;
    FormsWaker _waker;
    Forms.Drawing.Font? _defaultFont;
    bool _quitting;
    String? _shots;

    public AppKitWidgetSet()
    {
        _application = NSApplication.SharedApplication;
        _application.SetActivationPolicy(NSApplicationActivationPolicy.Regular);
        _application.FinishLaunching();
        _waker = FormsWaker.Alloc().Init()!;
        _defaultFont = null;
        _quitting = false;
        _shots = FindScreenshotDirectory();
    }

    /// Each visible form, as `WriteWindowScreenshot` writes one, after every
    /// turn of the loop a program drives itself.
    void WriteScreenshots(String directory)
    {
        var windows = _application.Windows;
        for (nuint i = 0u; i < windows.Count; i++)
            WriteWindowScreenshot((NSWindow)windows.ObjectAtIndex(i), directory);
    }

    public String Name => "AppKit";


    // ------------------------------------------------------------ controls

    public IWindowPeer CreateWindow(IWindowNotify owner, WindowBorder border) => new AppKitWindowPeer(owner, border);
    public IPanelPeer CreatePanel(IControlNotify owner, IContainerPeer parent) => Adopt(parent, new AppKitPanelPeer(owner));
    public ICustomPeer CreateCustom(IControlNotify owner, IContainerPeer parent) => Adopt(parent, new AppKitCustomPeer(owner));

    static T Adopt<T>(IContainerPeer parent, T made) where T : IControlPeer
    {
        parent.AddChild(made);
        return made;
    }

    public IPushButtonPeer CreateButton(IControlNotify owner, IContainerPeer parent) =>
        Adopt(parent, new AppKitButtonPeer(owner));
    public ICheckPeer CreateCheck(IControlNotify owner, IContainerPeer parent, CheckKind kind) =>
        Adopt(parent, new AppKitCheckPeer(owner, kind));
    public ILabelPeer CreateLabel(IControlNotify owner, IContainerPeer parent) => Adopt(parent, new AppKitLabelPeer(owner));
    public ITextEntryPeer CreateTextEntry(IControlNotify owner, IContainerPeer parent, bool multiline) =>
        Adopt(parent, new AppKitTextEntryPeer(owner, multiline));
    public IListPeer CreateList(IControlNotify owner, IContainerPeer parent) => Adopt(parent, new AppKitListPeer(owner, false));
    public IComboPeer CreateCombo(IControlNotify owner, IContainerPeer parent) => Adopt(parent, new AppKitComboPeer(owner));
    public IGroupPeer CreateGroup(IControlNotify owner, IContainerPeer parent) => Adopt(parent, new AppKitGroupPeer(owner));
    public IScrollBarPeer CreateScrollBar(IControlNotify owner, IContainerPeer parent, bool vertical) =>
        Adopt(parent, new AppKitScrollBarPeer(owner, vertical));
    public ISpinPeer CreateSpin(IControlNotify owner, IContainerPeer parent) => Adopt(parent, new AppKitSpinPeer(owner));
    public ICheckListPeer CreateCheckList(IControlNotify owner, IContainerPeer parent) =>
        Adopt(parent, new AppKitCheckListPeer(owner));
    public IHeaderPeer CreateHeader(IControlNotify owner, IContainerPeer parent) => Adopt(parent, new AppKitHeaderPeer(owner));
    public IToolBarPeer CreateToolBar(IControlNotify owner, IContainerPeer parent) =>
        Adopt(parent, new AppKitToolBarPeer(owner));
    public IStatusBarPeer CreateStatusBar(IControlNotify owner, IContainerPeer parent) =>
        Adopt(parent, new AppKitStatusBarPeer(owner));
    public IProgressPeer CreateProgress(IControlNotify owner, IContainerPeer parent) =>
        Adopt(parent, new AppKitProgressPeer(owner));
    public ITrackBarPeer CreateTrackBar(IControlNotify owner, IContainerPeer parent, bool vertical) =>
        Adopt(parent, new AppKitTrackBarPeer(owner, vertical));
    public ITabControlPeer CreateTabControl(IControlNotify owner, IContainerPeer parent) =>
        Adopt(parent, new AppKitTabControlPeer(owner));
    public ITreeViewPeer CreateTreeView(IControlNotify owner, IContainerPeer parent) =>
        Adopt(parent, new AppKitTreePeer(owner));
    public IListViewPeer CreateListView(IControlNotify owner, IContainerPeer parent) =>
        Adopt(parent, new AppKitListViewPeer(owner));
    public IMenuPeer CreateMenu() => RefuseAppKitControl<IMenuPeer>("menu");
    public IMenuPeer CreateMenuBar() => RefuseAppKitControl<IMenuPeer>("menu bar");

    public ITimerPeer CreateTimer(ITimerNotify owner) => new AppKitTimerPeer(owner);

    // ------------------------------------------------------------ clipboard

    public void SetClipboard(ClipboardContent content) { }
    public String GetClipboardText() => "";
    public String GetClipboardHtml() => "";
    public ClipboardImage? GetClipboardImage() => null;
    public String[] GetClipboardFiles() => new String[0u];
    public byte[] GetClipboardFormat(String name) => new byte[0u];
    public bool ContainsClipboardKind(ClipboardKind kind) => false;
    public bool ContainsClipboardFormat(String name) => false;
    public String[] GetClipboardFormatNames() => new String[0u];
    public IClipboardWatchPeer CreateClipboardWatch(IClipboardNotify owner) =>
        RefuseAppKitControl<IClipboardWatchPeer>("clipboard watch");

    // ------------------------------------------------------------ dialogs

    public Result<String, DialogOutcome> ChooseFileToOpen(IWindowPeer? owner, String title, String start, String[] filters) =>
        Fail(DialogOutcome.Failed);
    public Result<String, DialogOutcome> ChooseFileToSave(IWindowPeer? owner, String title, String start, String[] filters) =>
        Fail(DialogOutcome.Failed);
    public Result<String, DialogOutcome> ChooseFolder(IWindowPeer? owner, String title) => Fail(DialogOutcome.Failed);
    public Result<Color, DialogOutcome> ChooseColor(IWindowPeer? owner, Color start) => Fail(DialogOutcome.Failed);
    public Result<Forms.Drawing.Font, DialogOutcome> ChooseFont(IWindowPeer? owner, Forms.Drawing.Font start) =>
        Fail(DialogOutcome.Failed);

    // ------------------------------------------------------------ drawing

    public IFontBackend CreateFont(Forms.Drawing.Font font) => new AppKitFontBackend(font);

    public Result<IBitmapBackend, String> LoadBitmap(String path) =>
        CreateDecodedBitmap(NSImage.Alloc().InitWithContentsOfFile(ToNSString(path)), "'" + path + "'");

    public Result<IBitmapBackend, String> CreateBitmap(int width, int height, byte[] pixels) =>
        CreatePixelBitmap(width, height, pixels);

    public Result<IBitmapBackend, String> LoadBitmapResource(int id) =>
        Fail("a Mac program has no resource section; embed the picture with [Embed] instead");

    public Result<IBitmapBackend, String> DecodeBitmap(byte[] encoded)
    {
        if (encoded.Length == 0u)
            return Fail("there are no bytes to decode");
        var data = NSData.DataWithBytesLength(&encoded[0u], encoded.Length);
        return CreateDecodedBitmap(NSImage.Alloc().InitWithData(data), "the picture");
    }

    public IImageListBackend CreateImageList(FSize imageSize) => new AppKitImageListBackend(imageSize);

    /// The theme's colours, read under the appearance in force now, so a
    /// switch to Dark Mode between two calls is seen.
    public Color GetSystemColor(SystemColorId which)
    {
        switch (which)
        {
            case SystemColorId.Control: return FromNSColor(NSColor.WindowBackgroundColor);
            case SystemColorId.ControlText: return FromNSColor(NSColor.ControlTextColor);
            case SystemColorId.ControlDark: return FromNSColor(NSColor.SeparatorColor);
            case SystemColorId.ControlLight: return FromNSColor(NSColor.ControlBackgroundColor);
            case SystemColorId.Window: return FromNSColor(NSColor.TextBackgroundColor);
            case SystemColorId.WindowText: return FromNSColor(NSColor.TextColor);
            case SystemColorId.Highlight: return FromNSColor(NSColor.SelectedContentBackgroundColor);
            case SystemColorId.HighlightText: return FromNSColor(NSColor.AlternateSelectedControlTextColor);
            default: return FromNSColor(NSColor.DisabledControlTextColor);
        }
    }

    /// The system's font at the size its own controls use, in this library's
    /// points; see `ScaleFontSize`.
    public Forms.Drawing.Font GetDefaultFont()
    {
        var held = _defaultFont;
        if (held != null)
            return (Forms.Drawing.Font)held;
        var system = NSFont.SystemFontOfSize(NSFont.SystemFontSize);
        var made = new Forms.Drawing.Font(FromNSString(system.FamilyName), RoundToInt(system.PointSize * 72.0 / 96.0));
        _defaultFont = made;
        return made;
    }

    public FSize ScreenSize
    {
        get
        {
            var screen = NSScreen.MainScreen;
            if (screen == null)
                return CreateSize(0, 0);
            var frame = ((NSScreen)screen).Frame;
            return CreateSize(RoundToInt(frame.size.width), RoundToInt(frame.size.height));
        }
    }

    /// The screen less the menu bar and the Dock, measured down from the top.
    public FRect WorkArea
    {
        get
        {
            var screen = NSScreen.MainScreen;
            if (screen == null)
                return CreateRectangle(0, 0, 0, 0);
            var frame = ((NSScreen)screen).Frame;
            var visible = ((NSScreen)screen).VisibleFrame;
            double top = frame.origin.y + frame.size.height - (visible.origin.y + visible.size.height);
            return CreateRectangle(RoundToInt(visible.origin.x), RoundToInt(top),
                                   RoundToInt(visible.size.width), RoundToInt(visible.size.height));
        }
    }

    // ------------------------------------------------------------ the loop

    public void RunEventLoop()
    {
        _quitting = false;
        _application.Run();
    }

    /// Stops the loop. `stop:` takes effect after the next event, so one is
    /// posted for it to take effect after.
    public void QuitEventLoop()
    {
        _quitting = true;
        _application.Stop(null);
        CGPoint origin;
        origin.x = 0.0;
        origin.y = 0.0;
        var nudge = NSEvent.OtherEventWithTypeLocationModifierFlagsTimestampWindowNumberContextSubtypeData1Data2(
            NSEventType.ApplicationDefined, origin, (NSEventModifierFlags)0u, 0.0, 0, null, (short)0, 0, 0);
        if (nudge != null)
            _application.PostEventAtStart((NSEvent)nudge, true);
    }

    public bool PumpEvents()
    {
        while (true)
        {
            var event = _application.NextEventMatchingMaskUntilDateInModeDequeue(
                NSEventMask.Any, NSDate.DistantPast, NSDefaultRunLoopMode, true);
            if (event == null)
                break;
            _application.SendEvent((NSEvent)event);
        }
        _application.UpdateWindows();
        var shots = _shots;
        if (shots != null)
            WriteScreenshots((String)shots);
        return !_quitting;
    }

    /// From any thread: the waker's method runs on the main one, in every mode,
    /// so posted work runs under a modal window too.
    public void WakeEventLoop()
    {
        _waker.PerformSelectorOnMainThreadWithObjectWaitUntilDoneModes(
            Selector.Named("wake"), null, false, NSArray.ArrayWithObject(NSRunLoopCommonModes));
    }

    // ------------------------------------------------------------ the common

    public DialogResult ShowMessage(IWindowPeer? owner, String text, String caption,
                                    MessageButtons buttons, MessageIcon icon)
    {
        var alert = NSAlert.Alloc().Init()!;
        alert.MessageText = ToNSString(caption);
        alert.InformativeText = ToNSString(text);
        alert.AlertStyle = icon == MessageIcon.Warning || icon == MessageIcon.Error
                         ? NSAlertStyle.Warning : NSAlertStyle.Informational;

        DialogResult[] answers;
        switch (buttons)
        {
            case MessageButtons.OkCancel: answers = [DialogResult.Ok, DialogResult.Cancel]; break;
            case MessageButtons.YesNo: answers = [DialogResult.Yes, DialogResult.No]; break;
            case MessageButtons.YesNoCancel: answers = [DialogResult.Yes, DialogResult.No, DialogResult.Cancel]; break;
            case MessageButtons.RetryCancel: answers = [DialogResult.Retry, DialogResult.Cancel]; break;
            default: answers = [DialogResult.Ok]; break;
        }
        foreach (var answer in answers)
            alert.AddButtonWithTitle(ToNSString(DescribeAnswer(answer)));

        long chosen = (long)alert.RunModal() - 1000;
        return chosen >= 0 && (nuint)chosen < answers.Length ? answers[(nuint)chosen] : DialogResult.Cancel;
    }

    static String DescribeAnswer(DialogResult answer)
    {
        switch (answer)
        {
            case DialogResult.Cancel: return "Cancel";
            case DialogResult.Yes: return "Yes";
            case DialogResult.No: return "No";
            case DialogResult.Retry: return "Retry";
            default: return "OK";
        }
    }
}

#endif
