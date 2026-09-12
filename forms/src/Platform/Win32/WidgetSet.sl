// Stainless - an experimental systems language.
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

// The top-level window, and the factory that makes everything.
//
// `WindowPeer` is the one peer with a window class of its own, so it is the one
// whose procedure is not a subclass of anything. It is also where the messages
// that only a top-level window sees are handled: closing, activation, painting,
// and the scroll notifications its children's scroll bars send up to it.
module Forms.Platform.Win32;

import Standard.Collections;
import Forms.Drawing;
import Forms.Platform;
import Win32;
import Win32.Handles;
import Win32.Kernel32;
import Win32.User32;
import Win32.Gdi32;
import Win32.ComCtl32;

#if WINDOWS

/// The window class every form of this library is an instance of. Registered
/// once, on the first form, because `RegisterClassExW` fails the second time
/// and the failure is indistinguishable from a real one.
static readonly String FormClassName = "StainlessFormsWindow";
static bool formClassRegistered = false;

void EnsureFormClass() {
    if (formClassRegistered) { return; }

    var name = FormClassName.ToUtf16();
    WindowClass windowClass;
    windowClass.Size = (uint)sizeof(WindowClass);
    // Redrawing on both axes is what makes a resize repaint rather than
    // stretch what was there; a form that paints anything needs it.
    windowClass.Style = ClassStyleHorizontalRedraw | ClassStyleVerticalRedraw
                      | ClassStyleDoubleClicks;
    windowClass.Procedure = StainlessProc;
    windowClass.ClassExtra = 0;
    windowClass.WindowExtra = 0;
    windowClass.Instance = GetModuleHandleW(null);
    windowClass.Icon = LoadIconW(null, IconApplication());
    windowClass.Cursor = LoadCursorW(null, CursorArrow());
    // Null, so `WM_ERASEBKGND` reaches the peer and the form's own back colour
    // decides. A class brush here would paint over it before anyone was asked.
    windowClass.Background = null;
    windowClass.MenuName = null;
    windowClass.ClassName = name.ToPointer();
    windowClass.SmallIcon = null;

    RegisterClassExW(&windowClass);
    formClassRegistered = true;
}

/// `SPI_GETWORKAREA`: the screen minus the task bar.
const uint SpiGetWorkArea = 0x0030u;

/// The style bits for each way a window can be framed.
uint StyleForBorder(WindowBorder border) {
    if (border == WindowBorder.None)  { return WsPopup; }
    if (border == WindowBorder.Fixed) {
        return WsOverlapped | WsCaption | WsSystemMenu | WsMinimizeBox;
    }
    if (border == WindowBorder.Tool)  {
        return WsOverlapped | WsCaption | WsSystemMenu;
    }
    return WsOverlappedWindow;
}

uint ExtendedStyleForBorder(WindowBorder border) {
    if (border == WindowBorder.Tool) { return WsExToolWindow; }
    return 0u;
}

// ============================================================ the top window

/// A top-level window.
public class WindowPeer : ControlPeer, IWindowPeer {
    weak IWindowNotify? owningWindow;
    bool running;
    bool quitOnClose;
    /// Held, not merely handed to Windows: a menu command names an id, and this
    /// is what turns one back into the item that was chosen.
    IMenuPeer? menuBar;

    public WindowPeer(IWindowNotify owner, WindowBorder border) {
        base(MakeTopLevel(border), owner, false);
        owningWindow = owner;
        running = false;
        quitOnClose = false;
        menuBar = null;
    }

    /// Made before `base(...)` can run, because the base constructor needs the
    /// window to bind its peer to.
    static HWND MakeTopLevel(WindowBorder border) {
        EnsureFormClass();
        return CreateWindowExW(ExtendedStyleForBorder(border),
                               FormClassName.ToUtf16().ToPointer(),
                               "".ToUtf16().ToPointer(),
                               StyleForBorder(border) | WsClipChildren,
                               UseDefault, UseDefault, 640, 480,
                               null, null, GetModuleHandleW(null), null);
    }

    public override long Dispatch(uint message, ulong wParam, long lParam) {
        IWindowNotify? held = owningWindow;

        if (message == WmClose) {
            if (held != null) {
                // The one message that is a question. False keeps the window
                // open, and swallowing the message is how that is said.
                if (!((IWindowNotify)held).OnPlatformClosing()) { return 0; }
            }
            DestroyWindow(window);
            return 0;
        }

        if (message == WmDestroy) {
            if (held != null) { ((IWindowNotify)held).OnPlatformClosed(); }
            if (running) {
                running = false;
                // A modal window runs its own loop; this is what ends it.
                PostQuitMessage(0);
            }
            return 0;
        }

        // A menu command arrives with `lParam` null, where a control would have
        // put its handle -- that is the whole of how the two are told apart.
        // The id is resolved by asking this window's own menu to find it, which
        // is why no table of ids exists anywhere.
        if (message == WmCommand && lParam == 0) {
            var bar = menuBar;
            if (bar != null) {
                if (bar is MenuPeer tree) {
                    var item = tree.Find((int)(wParam & 0xFFFFu));
                    if (item != null) {
                        ((MenuItemPeer)item).Raise();
                        return 0;
                    }
                }
            }
        }

        if (message == WmActivate) {
            if (held != null) {
                // Zero is deactivation; anything else is one of the two ways of
                // becoming active, and neither is worth telling apart here.
                if ((wParam & 0xFFFFu) == 0u) { ((IWindowNotify)held).OnPlatformDeactivated(); }
                else { ((IWindowNotify)held).OnPlatformActivatedWindow(); }
            }
            return Inherited(message, wParam, lParam);
        }

        if (message == WmPaint) {
            PaintStruct paint;
            HDC dc = BeginPaint(window, &paint);
            var owner = Owner();
            if (owner != null) {
                var surface = new GraphicsBackend(dc, FromRect(paint.Paint));
                ((IControlNotify)owner).OnPlatformPaint(new Graphics(surface));
            }
            EndPaint(window, &paint);
            return 0;
        }

        // A child scroll bar's movement arrives here, not at the scroll bar.
        if (message == WmVerticalScroll || message == WmHorizontalScroll) {
            var bar = PeerOf((HWND)(void*)(nuint)lParam);
            if (bar != null) {
                // The binding form of `is` has to be the whole condition, so
                // the null test above is a statement of its own rather than
                // the left half of an `&&`.
                if (bar is ScrollBarPeer scroller) {
                    scroller.Scrolled((uint)(wParam & 0xFFFFu),
                                      (int)((wParam >> 16) & 0xFFFFu));
                    return 0;
                }
                // A slider reports the same way, and says nothing about how far
                // it moved -- the position is asked of it afterwards.
                if (bar is TrackBarPeer slider) {
                    slider.Scrolled();
                    return 0;
                }
            }
        }

        return base.Dispatch(message, wParam, lParam);
    }

    // ------------------------------------------------------- IWindowPeer

    public void SetTitle(String title) { SetText(title); }

    public void SetMenu(IMenuPeer? menu) {
        menuBar = menu;
        if (menu == null) {
            Win32.User32.SetMenu(window, null);
        } else {
            IMenuPeer given = (IMenuPeer)menu;
            if (given is MenuPeer bar) {
                // The window frees the menu it holds, so the menu must stop
                // freeing itself.
                bar.OwnedByParent();
                Win32.User32.SetMenu(window, bar.Native());
            }
        }
        DrawMenuBar(window);
        // The bar takes a row out of the client area, so everything laid out
        // against it has moved.
        var owner = Owner();
        if (owner != null) {
            ((IControlNotify)owner).OnPlatformResized(ClientBounds().Extent);
        }
    }

    /// Changing a border after the window exists means changing style bits and
    /// telling Windows the frame moved. Not every bit takes effect -- a window
    /// created `WS_POPUP` will not grow a caption -- which is why the control
    /// layer makes this read-only and this is here for a backend that can.
    public void SetBorder(WindowBorder border) {
        Win32.User32.SetWindowLongPtrW(window, GwlStyle,
                          (long)(StyleForBorder(border) | WsClipChildren));
        SetWindowPos(window, null, 0, 0, 0, 0,
                     SwpNoMove | SwpNoSize | SwpNoZOrder | SwpFrameChanged);
    }

    public void SetState(WindowState state) {
        if (state == WindowState.Minimized)      { ShowWindow(window, SwShowMinimized); }
        else if (state == WindowState.Maximized) { ShowWindow(window, SwShowMaximized); }
        else                                     { ShowWindow(window, SwRestore); }
    }

    public WindowState GetState() {
        if (IsIconic(window) != 0) { return WindowState.Minimized; }
        if (IsZoomed(window) != 0) { return WindowState.Maximized; }
        return WindowState.Normal;
    }

    public void Activate() {
        ShowWindow(window, SwShow);
        SetForegroundWindow(window);
        UpdateWindow(window);
    }

    public void Close() { SendMessageW(window, WmClose, 0u, 0); }

    public void CenterOnScreen() {
        Rect frame;
        GetWindowRect(window, &frame);
        int width = frame.Right - frame.Left;
        int height = frame.Bottom - frame.Top;

        Rect work;
        SystemParametersInfoW(SpiGetWorkArea, 0u, (void*)&work, 0u);
        int x = work.Left + ((work.Right - work.Left) - width) / 2;
        int y = work.Top + ((work.Bottom - work.Top) - height) / 2;

        SetWindowPos(window, null, x, y, 0, 0, SwpNoSize | SwpNoZOrder);
    }

    /// A loop of its own, which is what modal means.
    ///
    /// **The owner is disabled for the duration**, which is the whole of what
    /// makes a dialog modal on Windows: there is no modal flag, only the fact
    /// that everything else refuses input. Re-enabling it before the window is
    /// destroyed is what stops another window coming to the front at the end.
    public void ShowModal() {
        HWND owner = GetWindow(window, GwOwner);
        if (owner != null) { EnableWindow(owner, 0); }

        Activate();
        running = true;

        Msg message;
        while (running) {
            int got = GetMessageW(&message, null, 0u, 0u);
            if (got <= 0) { break; }
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }

        if (owner != null) {
            EnableWindow(owner, 1);
            SetForegroundWindow(owner);
        }
    }

    // --------------------------------------------------- IContainerPeer

    public void AddChild(IControlPeer child) {
        SetParent((HWND)(void*)child.Handle(), window);
    }

    public void RemoveChild(IControlPeer child) {
        SetParent((HWND)(void*)child.Handle(), null);
    }
}

// =============================================================== the factory

/// The Windows backend.
///
/// One object, made once by `Application.Initialize`, holding nothing. Every
/// method is a call into Windows, which is why there is no state here and why
/// the LCL's equivalent -- `TWin32WidgetSet`, a `TWidgetSet` descendant with
/// forty fields -- is mostly the bookkeeping that peers now do for themselves.
public class Win32WidgetSet : IWidgetSet {
    Font? defaultFont;

    public Win32WidgetSet() {
        defaultFont = null;

        // Registers the window classes the common controls live in. Without it
        // `CreateWindowExW` is handed a class name Windows has never heard of,
        // fails, and the control simply does not appear -- which looks like a
        // layout bug rather than a missing call.
        InitCommonControlsInfo wanted;
        wanted.Size = (uint)sizeof(InitCommonControlsInfo);
        wanted.Classes = IccBarClasses | IccTabClasses | IccTreeViewClasses
                       | IccListViewClasses | IccProgressClass | IccUpDownClass
                       | IccStandardClasses;
        InitCommonControlsEx(&wanted);
    }

    public String Name => "Win32";

    public IWindowPeer CreateWindow(IWindowNotify owner, WindowBorder border) {
        return new WindowPeer(owner, border);
    }

    public IButtonPeer CreateButton(IControlNotify owner, IContainerPeer parent) {
        return new ButtonPeer(owner, parent);
    }

    public ICheckPeer CreateCheck(IControlNotify owner, IContainerPeer parent, bool radio) {
        return new CheckPeer(owner, parent, radio);
    }

    public ILabelPeer CreateLabel(IControlNotify owner, IContainerPeer parent) {
        return new LabelPeer(owner, parent);
    }

    public ITextEntryPeer CreateTextEntry(IControlNotify owner, IContainerPeer parent,
                                          bool multiline) {
        return new TextEntryPeer(owner, parent, multiline);
    }

    public IListPeer CreateList(IControlNotify owner, IContainerPeer parent) {
        return new ListPeer(owner, parent);
    }

    public IComboPeer CreateCombo(IControlNotify owner, IContainerPeer parent) {
        return new ComboPeer(owner, parent);
    }

    public IGroupPeer CreateGroup(IControlNotify owner, IContainerPeer parent) {
        return new GroupPeer(owner, parent);
    }

    public IPanelPeer CreatePanel(IControlNotify owner, IContainerPeer parent) {
        return new PanelPeer(owner, parent);
    }

    public IScrollBarPeer CreateScrollBar(IControlNotify owner, IContainerPeer parent,
                                          bool vertical) {
        return new ScrollBarPeer(owner, parent, vertical);
    }

    public IToolBarPeer CreateToolBar(IControlNotify owner, IContainerPeer parent) {
        return new ToolBarPeer(owner, parent);
    }

    public IStatusBarPeer CreateStatusBar(IControlNotify owner, IContainerPeer parent) {
        return new StatusBarPeer(owner, parent);
    }

    public IProgressPeer CreateProgress(IControlNotify owner, IContainerPeer parent) {
        return new ProgressPeer(owner, parent);
    }

    public ITrackBarPeer CreateTrackBar(IControlNotify owner, IContainerPeer parent,
                                        bool vertical) {
        return new TrackBarPeer(owner, parent, vertical);
    }

    public ITabControlPeer CreateTabControl(IControlNotify owner, IContainerPeer parent) {
        return new TabControlPeer(owner, parent);
    }

    public ITreeViewPeer CreateTreeView(IControlNotify owner, IContainerPeer parent) {
        return new TreeViewPeer(owner, parent);
    }

    public IListViewPeer CreateListView(IControlNotify owner, IContainerPeer parent) {
        return new ListViewPeer(owner, parent);
    }

    public IMenuPeer CreateMenu() { return new MenuPeer(false); }

    /// A menu bar, which Windows makes with a different call from a popup and
    /// will not exchange afterwards.
    public IMenuPeer CreateMenuBar() { return new MenuPeer(true); }

    public Result<IBitmapBackend, String> LoadBitmap(String path) {
        return LoadBitmapFile(path);
    }

    public IImageListBackend CreateImageList(FSize imageSize) {
        return new ImageListBackend(imageSize);
    }

    public IFontBackend CreateFont(Font font) { return new FontBackend(font); }

    public Color SystemColor(SystemColorId which) {
        return FromColorRef(GetSysColor(IndexOfColor(which)));
    }

    int IndexOfColor(SystemColorId which) {
        if (which == SystemColorId.Control)       { return ColorBtnFace; }
        if (which == SystemColorId.ControlText)   { return ColorBtnText; }
        if (which == SystemColorId.ControlDark)   { return ColorBtnShadow; }
        if (which == SystemColorId.ControlLight)  { return ColorBtnHighlight; }
        if (which == SystemColorId.Window)        { return ColorWindow; }
        if (which == SystemColorId.WindowText)    { return ColorWindowText; }
        if (which == SystemColorId.Highlight)     { return ColorHighlight; }
        if (which == SystemColorId.HighlightText) { return ColorHighlightText; }
        return ColorGrayText;
    }

    /// The font Windows dresses its own dialogs in, read from the theme rather
    /// than guessed. Cached, because it costs a `SystemParametersInfoW` and a
    /// `NONCLIENTMETRICS` the size of a small struct, and because every control
    /// asks for it.
    public Font DefaultFont() {
        var held = defaultFont;
        if (held != null) { return (Font)held; }

        // `SPI_GETNONCLIENTMETRICS` would give the exact face and size; until
        // the `NONCLIENTMETRICSW` layout is bound, Segoe UI at 9pt is what
        // every Windows version since Vista actually uses.
        var made = new Font("Segoe UI", 9);
        defaultFont = made;
        return made;
    }

    public FSize ScreenSize() {
        return Extent(GetSystemMetrics(SmScreenWidth), GetSystemMetrics(SmScreenHeight));
    }

    public FRect WorkArea() {
        Rect work;
        SystemParametersInfoW(SpiGetWorkArea, 0u, (void*)&work, 0u);
        return FromRect(work);
    }

    // -------------------------------------------------------------- loop

    public void RunEventLoop() {
        Msg message;
        while (true) {
            int got = GetMessageW(&message, null, 0u, 0u);
            // Zero is WM_QUIT and -1 is a real failure; the two must not be
            // tested together, which is the bug `Win32.Succeeded` would cause
            // here and the reason it is not used.
            if (got == 0) { return; }
            if (got < 0)  { return; }
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }

    public bool PumpEvents() {
        Msg message;
        while (PeekMessageW(&message, null, 0u, 0u, PeekRemove) != 0) {
            if (message.Message == WmQuit) { return false; }
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        return true;
    }

    public void QuitEventLoop() { PostQuitMessage(0); }

    // ------------------------------------------------------------ dialogs

    public DialogResult ShowMessage(IWindowPeer? owner, String text, String caption,
                                    MessageButtons buttons, MessageIcon icon) {
        HWND parent = null;
        if (owner != null) { parent = (HWND)(void*)((IWindowPeer)owner).Handle(); }

        uint style = ButtonsOf(buttons) | IconOf(icon);
        int answer = MessageBoxW(parent, text.ToUtf16().ToPointer(),
                                 caption.ToUtf16().ToPointer(), style);
        return ResultOf(answer);
    }

    uint ButtonsOf(MessageButtons buttons) {
        if (buttons == MessageButtons.OkCancel)    { return MbOkCancel; }
        if (buttons == MessageButtons.YesNo)       { return MbYesNo; }
        if (buttons == MessageButtons.YesNoCancel) { return MbYesNoCancel; }
        if (buttons == MessageButtons.RetryCancel) { return MbRetryCancel; }
        return MbOk;
    }

    uint IconOf(MessageIcon icon) {
        if (icon == MessageIcon.Information) { return MbIconInformation; }
        if (icon == MessageIcon.Warning)     { return MbIconWarning; }
        if (icon == MessageIcon.Error)       { return MbIconError; }
        if (icon == MessageIcon.Question)    { return MbIconQuestion; }
        return 0u;
    }

    DialogResult ResultOf(int answer) {
        if (answer == IdOk)     { return DialogResult.Ok; }
        if (answer == IdCancel) { return DialogResult.Cancel; }
        if (answer == IdYes)    { return DialogResult.Yes; }
        if (answer == IdNo)     { return DialogResult.No; }
        if (answer == IdAbort)  { return DialogResult.Abort; }
        if (answer == IdRetry)  { return DialogResult.Retry; }
        if (answer == IdIgnore) { return DialogResult.Ignore; }
        return DialogResult.None;
    }
}

#endif
