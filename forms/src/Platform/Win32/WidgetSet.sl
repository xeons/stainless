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

// The top-level window, and the factory that makes everything.
//
// `WindowPeer` is the one peer with a window class of its own, so it is the one
// whose procedure is not a subclass of anything. It is also where the messages
// that only a top-level window sees are handled: closing, activation, painting,
// and the scroll notifications its children's scroll bars send up to it.
module Forms.Platform.Win32;

import Standard.Collections;
import Forms.Drawing;
import Forms;
import Forms.Platform;
#if WINDOWS
import Win32;
import Win32.Handles;
import Win32.Kernel32;
import Win32.User32;
import Win32.Gdi32;
import Win32.ComCtl32;
import Win32.Resources;

/// The window class every form of this library is an instance of. Registered
/// once, on the first form, because `RegisterClassExW` fails the second time
/// and the failure is indistinguishable from a real one.
static readonly String FormClassName = "StainlessFormsWindow";
static bool formClassRegistered = false;

void EnsureFormClass()
{
    if (formClassRegistered)
        return;

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

// ------------------------------------------------------------ the wake window

/// The window `Wake` posts to, so that the loop turns and the queue is drained.
///
/// **A window rather than `PostThreadMessageW`**, which is the obvious answer
/// and the wrong one. A thread message has no window to be routed to, so any
/// modal loop Windows runs on this thread -- a message box, a tracking menu, a
/// drag -- discards it; work posted while a message box was open would simply
/// be lost. Lazarus's Win32 widget set posts to a window for exactly this
/// reason, and `lcl/interfaces/win32/` is the reference here as elsewhere.
///
/// **Message-only**, parented to `HWND_MESSAGE`, so it is never shown, never
/// enumerated, never in the task bar and never a candidate for the focus. It
/// exists to have a message queue and nothing else.
static readonly String WakeClassName = "StainlessFormsWake";

static HWND s_wake = null;
static bool wakeClassRegistered = false;

/// Drains the queue, and answers anything else the way a window with no
/// opinions should.
nint WakeProc(HWND window, uint message, nuint wParam, nint lParam)
{
    if (message == WmApp)
    {
        Application.Drain();
        return 0;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

void EnsureWakeWindow()
{
    if (s_wake != null)
        return;

    if (!wakeClassRegistered)
    {
        var name = WakeClassName.ToUtf16();
        WindowClass windowClass;
        windowClass.Size = (uint)sizeof(WindowClass);
        windowClass.Style = 0u;
        windowClass.Procedure = WakeProc;
        windowClass.ClassExtra = 0;
        windowClass.WindowExtra = 0;
        windowClass.Instance = GetModuleHandleW(null);
        windowClass.Icon = null;
        windowClass.Cursor = null;
        windowClass.Background = null;
        windowClass.MenuName = null;
        windowClass.ClassName = name.ToPointer();
        windowClass.SmallIcon = null;

        RegisterClassExW(&windowClass);
        wakeClassRegistered = true;
    }

    s_wake = CreateWindowExW(0u, WakeClassName.ToUtf16().ToPointer(), null,
                             0u, 0, 0, 0, 0,
                             MessageOnlyParent(), null, GetModuleHandleW(null), null);
}

/// The window class a `CustomControl` is an instance of, registered on the
/// same terms as the form's and for the same reason.
///
/// **A separate class rather than the form's**, because the two disagree about
/// the one thing a class settles: `CS_DBLCLKS` they share, but a form is a
/// top-level window with an icon and an arrow cursor, and a drawn control wants
/// neither. Both leave `Background` null so that `WM_ERASEBKGND` decides -- for
/// a form, the back colour it was given; for this, nothing at all, because it
/// draws into a buffer and copies the buffer over every pixel it owns.
static readonly String CustomClassName = "StainlessFormsCustom";
static bool customClassRegistered = false;

void EnsureCustomClass()
{
    if (customClassRegistered)
        return;

    var name = CustomClassName.ToUtf16();
    WindowClass windowClass;
    windowClass.Size = (uint)sizeof(WindowClass);
    // Redrawing on both axes: a drawn control's contents almost never survive a
    // resize unchanged, and one that lays text out to its own width never does.
    windowClass.Style = ClassStyleHorizontalRedraw | ClassStyleVerticalRedraw
                      | ClassStyleDoubleClicks;
    windowClass.Procedure = StainlessProc;
    windowClass.ClassExtra = 0;
    windowClass.WindowExtra = 0;
    windowClass.Instance = GetModuleHandleW(null);
    windowClass.Icon = null;
    // Null, so that `WM_SETCURSOR` reaches the peer and `SetCursor` on the
    // control decides. A class cursor here would win over it on every move.
    windowClass.Cursor = null;
    windowClass.Background = null;
    windowClass.MenuName = null;
    windowClass.ClassName = name.ToPointer();
    windowClass.SmallIcon = null;

    RegisterClassExW(&windowClass);
    customClassRegistered = true;
}

/// The window class a `Panel` is an instance of.
///
/// **A container is not a system control**, and making one out of `STATIC` was
/// the shape of a bug worth remembering: a static control answers
/// `HTTRANSPARENT` to a hit test unless it carries `SS_NOTIFY`, so Windows
/// hands every mouse message over it to the *parent* -- and a windowless child
/// of the panel, which is reached by hit-testing the panel's own messages, is
/// unreachable. Lazarus registers one class of its own and uses it for every
/// `TWinControl` that is not a system control; `lcl/interfaces/win32/` is the
/// reference here as elsewhere.
///
/// **No `CS_HREDRAW` or `CS_VREDRAW`**, which is where this differs from the
/// form's class and the custom control's. Those invalidate the whole window on
/// every resize, and a container's pixels are its children -- which repaint
/// themselves. Asking for the lot is a flicker on every drag of a splitter.
/// The LCL's class has neither, for the same reason.
///
/// Null cursor, so `WM_SETCURSOR` reaches the peer and a windowless child's
/// cursor can win; null background, so `WM_ERASEBKGND` reaches it and the
/// panel's own back colour decides.
static readonly String PanelClassName = "StainlessFormsPanel";
static bool panelClassRegistered = false;

void EnsurePanelClass()
{
    if (panelClassRegistered)
        return;

    var name = PanelClassName.ToUtf16();
    WindowClass windowClass;
    windowClass.Size = (uint)sizeof(WindowClass);
    windowClass.Style = ClassStyleDoubleClicks;
    windowClass.Procedure = StainlessProc;
    windowClass.ClassExtra = 0;
    windowClass.WindowExtra = 0;
    windowClass.Instance = GetModuleHandleW(null);
    windowClass.Icon = null;
    windowClass.Cursor = null;
    windowClass.Background = null;
    windowClass.MenuName = null;
    windowClass.ClassName = name.ToPointer();
    windowClass.SmallIcon = null;

    RegisterClassExW(&windowClass);
    panelClassRegistered = true;
}

/// `SPI_GETWORKAREA`: the screen minus the task bar.
const uint SpiGetWorkArea = 0x0030u;

/// The style bits for each way a window can be framed.
uint StyleForBorder(WindowBorder border)
{
    if (border == WindowBorder.None)
        return WsPopup;
    if (border == WindowBorder.Fixed)
    {
        return WsOverlapped | WsCaption | WsSystemMenu | WsMinimizeBox;
    }
    if (border == WindowBorder.Tool)
    {
        return WsOverlapped | WsCaption | WsSystemMenu;
    }
    return WsOverlappedWindow;
}

uint ExtendedStyleForBorder(WindowBorder border)
{
    if (border == WindowBorder.Tool)
        return WsExToolWindow;
    return 0u;
}

// ============================================================ the top window

/// A top-level window.
/// Whether the keyboard did something to a window rather than to a control.
///
/// At module level rather than on the widget set because **two** loops need it
/// and only one had it: the application's loop called it and `ShowModal`'s did
/// not, so a modal dialog had no Tab between its controls, no arrows within a
/// radio group and no Escape to cancel -- the three things that make a dialog
/// feel like a dialog. The widget set keeps a method of the old name that
/// forwards here, since that is where the reasoning is documented.
bool DialogKey(Msg* message)
{
    if (message->Message < WmKeyFirst || message->Message > WmKeyLast)
        return false;
    HWND top = GetAncestor(message->Window, GaRoot);
    if (top == null)
        return false;
    // Only windows of this library's own class, so a message bound for a
    // dialog Windows is running -- a message box, a file chooser -- is left
    // entirely alone.
    if (PeerOf(top) == null)
        return false;
    return IsDialogMessageW(top, message) != 0;
}

/// `EnumWindows`' callback for `WindowPeer.ShowModal`. `parameter` is the
/// dialog's peer, borrowed for the length of the enumeration.
int NoteWindowForModal(HWND window, nint parameter)
{
    var dialog = (WindowPeer)(void*)(nuint)parameter;
    dialog.Consider(window);
    return 1;
}

/// Whether the keyboard is in a combo box whose list is showing: its edit, or
/// the combo itself. `CB_GETDROPPEDSTATE` is below `WM_USER`, so no window but
/// a combo box answers it with anything but zero.
bool ComboIsDropped(HWND focused)
{
    if (SendMessageW(focused, CbGetDroppedState, 0u, 0) != 0)
        return true;
    HWND parent = GetParent(focused);
    if (parent == null)
        return false;
    return SendMessageW(parent, CbGetDroppedState, 0u, 0) != 0;
}

public class WindowPeer : ControlPeer, IWindowPeer
{
    weak IWindowNotify? owningWindow;
    bool _running;
    bool _quitOnClose;
    /// The windows `ShowModal` disabled, as handles, to be enabled again when
    /// it ends. Empty when nothing is modal.
    List<nuint> _disabled;
    /// Held, not merely handed to Windows: a menu command names an id, and this
    /// is what turns one back into the item that was chosen.
    IMenuPeer? _menuBar;

    public WindowPeer(IWindowNotify owner, WindowBorder border)
    {
        base(MakeTopLevel(border), owner, false);
        owningWindow = owner;
        _running = false;
        _quitOnClose = false;
        _disabled = new List<nuint>();
        _menuBar = null;
    }

    /// Made before `base(...)` can run, because the base constructor needs the
    /// window to bind its peer to.
    static HWND MakeTopLevel(WindowBorder border)
    {
        EnsureFormClass();
        return CreateWindowExW(ExtendedStyleForBorder(border),
                               FormClassName.ToUtf16().ToPointer(),
                               "".ToUtf16().ToPointer(),
                               StyleForBorder(border) | WsClipChildren,
                               UseDefault, UseDefault, 640, 480,
                               null, null, GetModuleHandleW(null), null);
    }

    public override long Dispatch(uint message, ulong wParam, long lParam)
    {
        IWindowNotify? held = owningWindow;

        if (message == WmClose)
        {
            if (held != null)
            {
                // The one message that is a question. False keeps the window
                // open, and swallowing the message is how that is said.
                if (!((IWindowNotify)held).OnPlatformClosing())
                    return 0;
            }
            // Before the window goes, or Windows activates whatever window of
            // any program is next in line rather than the owner.
            EnableOthers();
            DestroyWindow(window);
            return 0;
        }

        if (message == WmDestroy)
        {
            if (held != null)
                ((IWindowNotify)held).OnPlatformClosed();

            // A modal window runs its own loop, and clearing the flag is the
            // whole of what ends it.
            //
            // **It must not post a quit**, which is what this did and what made
            // closing any modal dialog exit the whole program. `PostQuitMessage`
            // puts `WM_QUIT` on the *thread's* queue, not a window's: the modal
            // loop leaves on the flag without ever dequeuing it, so the message
            // sits there until the application's own loop picks it up and takes
            // the program down with it. Nothing about the dialog is wrong by
            // then, which is what makes it hard to see.
            //
            // No wake-up is needed in its place. `WM_DESTROY` arrives inside the
            // modal loop's own `DispatchMessageW`, so the `while` re-reads the
            // flag the moment that returns; there is no blocked `GetMessageW`
            // to rescue.
            _running = false;
            return 0;
        }

        // A menu command arrives with `lParam` null, where a control would have
        // put its handle -- that is the whole of how the two are told apart.
        // The id is resolved by asking this window's own menu to find it, which
        // is why no table of ids exists anywhere.
        if (message == WmCommand && lParam == 0)
        {
            var bar = _menuBar;
            if (bar != null)
            {
                if (bar is MenuPeer tree)
                {
                    var item = tree.Find((int)(wParam & 0xFFFFu));
                    if (item != null)
                    {
                        ((MenuItemPeer)item).Raise();
                        return 0;
                    }
                }
            }
        }

        // ------------------------------------------------- owner drawing
        //
        // Both arrive at the *window* that owns the menu rather than at the
        // menu, and name an item by its command id alone -- so the window
        // turns the id back into an item and asks it. Neither is raised at all
        // unless something asked for `SetOwnerDrawn(true)`.

        if (message == WmMeasureItem)
        {
            MeasureItemStruct* asked = (MeasureItemStruct*)(void*)(nuint)lParam;
            if (asked->ControlType != OdtMenu)
                return Inherited(message, wParam, lParam);

            var item = MenuItemFor((int)asked->ItemData);
            if (item == null)
                return Inherited(message, wParam, lParam);

            // The menu's own device context, for measuring in the font the
            // menu will draw with. `null` as the window is what asks for the
            // screen's, which is what a menu is drawn against.
            HDC screen = GetDC(null);
            var surface = new Graphics(new GraphicsBackend(screen, Area(0, 0, 0, 0)));
            var wanted = ((IMenuItemNotify)item).OnPlatformMeasureItem(surface);
            ReleaseDC(null, screen);

            asked->ItemWidth = (uint)(wanted.Width < 0 ? 0 : wanted.Width);
            asked->ItemHeight = (uint)(wanted.Height < 0 ? 0 : wanted.Height);
            return 1;
        }

        if (message == WmDrawItem)
        {
            DrawItemStruct* asked = (DrawItemStruct*)(void*)(nuint)lParam;
            if (asked->ControlType != OdtMenu)
                return Inherited(message, wParam, lParam);

            var item = MenuItemFor((int)asked->ItemData);
            if (item == null)
                return Inherited(message, wParam, lParam);

            // The context is the menu's and is already set up, so the wrapper
            // owns nothing and releases nothing.
            var surface = new Graphics(new GraphicsBackend(asked->Dc, FromRect(asked->Item)));
            ((IMenuItemNotify)item).OnPlatformDrawItem(
                surface, FromRect(asked->Item), StateOf(asked->ItemState));
            return 1;
        }

        if (message == WmActivate)
        {
            if (held != null)
            {
                // Zero is deactivation; anything else is one of the two ways of
                // becoming active, and neither is worth telling apart here.
                if ((wParam & 0xFFFFu) == 0u)
                {
                    ((IWindowNotify)held).OnPlatformDeactivated();
                }
                else
                {
                    ((IWindowNotify)held).OnPlatformActivatedWindow();
                }
            }
            return Inherited(message, wParam, lParam);
        }

        if (message == WmPaint)
        {
            PaintStruct paint;
            HDC dc = BeginPaint(window, &paint);
            var owner = Owner;
            if (owner != null)
            {
                var surface = new GraphicsBackend(dc, FromRect(paint.Paint));
                ((IControlNotify)owner).OnPlatformPaint(new Graphics(surface));
            }
            EndPaint(window, &paint);
            return 0;
        }

        return base.Dispatch(message, wParam, lParam);
    }

    // ------------------------------------------------------- IWindowPeer

    public void SetTitle(String title) => SetText(title);

    /// Puts an icon on the window, in both the sizes Windows asks for.
    ///
    /// `WM_SETICON` twice rather than once, because the large icon is what the
    /// task switcher shows and the small one is what the title bar draws, and a
    /// window given only the large one gets a downscaled blur in the corner.
    /// `LoadImageW` is asked for each size separately so the resource's own
    /// 16- and 32-pixel images are used rather than one of them resampled.
    public bool SetIconResource(int id)
    {
        HINSTANCE self = (HINSTANCE)GetModuleHandleW(null);

        var large = LoadImageW(self, Resources.Id(id), ImageIcon,
                               GetSystemMetrics(SmIconWidth),
                               GetSystemMetrics(SmIconHeight), LrDefaultColor);
        var small = LoadImageW(self, Resources.Id(id), ImageIcon,
                               GetSystemMetrics(SmSmallIconWidth),
                               GetSystemMetrics(SmSmallIconHeight), LrDefaultColor);

        if (large == null && small == null)
            return false;

        if (large != null)
            SendMessageW(window, WmSetIcon, IconBigSize, (long)(nuint)large);
        if (small != null)
            SendMessageW(window, WmSetIcon, IconSmallSize, (long)(nuint)small);
        return true;
    }

    /// The menu that is popped up over this window, for as long as it is.
    ///
    /// Set by `MenuPeer.ShowPopup` and cleared when it returns. A popup
    /// belongs to no menu bar, so without this its items could not be found
    /// from an id -- see the note there.
    IMenuPeer? _poppedUp;

    public void PoppedUp(IMenuPeer? menu) => _poppedUp = menu;

    /// The item a command id names, looked for in the bar and then in whatever
    /// is popped up over it.
    ///
    /// Ids come from one counter for the whole program, so the two cannot
    /// disagree about which item a number means.
    IMenuItemNotify? MenuItemFor(int id)
    {
        var bar = _menuBar;
        if (bar is MenuPeer tree)
        {
            var found = tree.FindAny(id);
            if (found != null)
                return ((MenuItemPeer)found).Notify;
        }

        var over = _poppedUp;
        if (over is MenuPeer popup)
        {
            var found = popup.FindAny(id);
            if (found != null)
                return ((MenuItemPeer)found).Notify;
        }
        return null;
    }

    /// What Windows says about an item, as the seam spells it.
    ///
    /// `ODS_GRAYED` and `ODS_DISABLED` both mean unusable and a menu sets the
    /// first, so both map to the one flag rather than the seam carrying a
    /// distinction only one platform makes.
    static MenuItemState StateOf(uint reported)
    {
        var state = MenuItemState.None;
        if ((reported & OdsSelected) != 0u)
            state = state | MenuItemState.Selected;
        if ((reported & (OdsGrayed | OdsDisabled)) != 0u)
            state = state | MenuItemState.Disabled;
        if ((reported & OdsChecked) != 0u)
            state = state | MenuItemState.Checked;
        if ((reported & OdsDefault) != 0u)
            state = state | MenuItemState.Default;

        // `ODS_NOACCEL` is Windows answering the question for us. The
        // alternative is `WM_QUERYUISTATE` on the window the menu belongs to,
        // which is the same answer reached by asking somebody who was already
        // telling us.
        if ((reported & OdsNoAccel) != 0u)
            state = state | MenuItemState.NoAccelerators;
        return state;
    }

    public void SetMenu(IMenuPeer? menu)
    {
        _menuBar = menu;
        if (menu == null)
        {
            Win32.User32.SetMenu(window, null);
        }
        else
        {
            IMenuPeer given = (IMenuPeer)menu;
            if (given is MenuPeer bar)
            {
                // The window frees the menu it holds, so the menu must stop
                // freeing itself.
                bar.OwnedByParent();
                Win32.User32.SetMenu(window, bar.Native);
            }
        }
        DrawMenuBar(window);
        // The bar takes a row out of the client area, so everything laid out
        // against it has moved. The report is of the window's own size, which
        // is what `Bounds` holds; the layout reads the client area itself.
        var owner = Owner;
        if (owner != null)
        {
            ((IControlNotify)owner).OnPlatformResized(BoundsInParent.Extent);
        }
    }

    /// Changing a border after the window exists means changing style bits and
    /// telling Windows the frame moved. Not every bit takes effect -- a window
    /// created `WS_POPUP` will not grow a caption -- which is why the control
    /// layer makes this read-only and this is here for a backend that can.
    public void SetBorder(WindowBorder border)
    {
        Win32.User32.SetWindowLongPtrW(window, GwlStyle,
                          (long)(StyleForBorder(border) | WsClipChildren));
        SetWindowPos(window, null, 0, 0, 0, 0,
                     SwpNoMove | SwpNoSize | SwpNoZOrder | SwpFrameChanged);
    }

    public void SetState(WindowState state)
    {
        if (state == WindowState.Minimized)
        {
            ShowWindow(window, SwShowMinimized);
        }
        else if (state == WindowState.Maximized)
        {
            ShowWindow(window, SwShowMaximized);
        }
        else
        {
            ShowWindow(window, SwRestore);
        }
    }

    public WindowState GetState()
    {
        if (IsIconic(window) != 0)
            return WindowState.Minimized;
        if (IsZoomed(window) != 0)
            return WindowState.Maximized;
        return WindowState.Normal;
    }

    public void Activate()
    {
        ShowWindow(window, SwShow);
        SetForegroundWindow(window);
        UpdateWindow(window);
    }

    public void Close() => SendMessageW(window, WmClose, 0u, 0);

    public void CenterOnScreen()
    {
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
    /// **Every other window of the program is disabled for the duration**,
    /// which is the whole of what makes a dialog modal on Windows: there is no
    /// modal flag, only the fact that everything else refuses input. The LCL's
    /// `Screen.DisableForms` does the same. Re-enabling them before the window
    /// is destroyed is what stops another program's window coming to the front
    /// at the end; `WM_CLOSE` does that.
    ///
    /// **Owned**, so the dialog stays in front of its owner and Windows gives
    /// the owner the activation back when the dialog goes.
    public void ShowModal(IWindowPeer? owner)
    {
        if (owner != null)
        {
            Win32.User32.SetWindowLongPtrW(window, GwlpHwndParent,
                                           (long)((IWindowPeer)owner).Handle);
        }
        DisableOthers();

        Activate();
        _running = true;

        Msg message;
        while (_running)
        {
            int got = GetMessageW(&message, null, 0u, 0u);
            if (got < 0)
                break;
            // The quit was for the program, not for this loop: put it back for
            // the loop outside.
            if (got == 0)
            {
                PostQuitMessage((int)message.WParam);
                break;
            }
            // **Escape closes a modal window**, which nothing else would do.
            // `IsDialogMessageW` turns Escape into a `WM_COMMAND` carrying
            // `IDCANCEL`, and that only means anything to a real dialog box
            // with a control of that id -- these are ordinary windows, so it
            // arrives as a command nobody claims and Escape does nothing.
            // Handled here rather than by claiming id 2 in `WM_COMMAND`, where
            // it could not be told apart from a menu item numbered 2.
            //
            // Through `WM_CLOSE` rather than `DestroyWindow`, so that a window
            // which refuses to close still refuses when asked this way.
            //
            // Not while a combo box's list is dropped: Escape closes the list.
            if (message.Message == WmKeyDown && (int)message.WParam == VkEscape
                && GetAncestor(message.Window, GaRoot) == window
                && !ComboIsDropped(message.Window))
            {
                SendMessageW(window, WmClose, 0u, 0);
                continue;
            }

            // The same pre-processing the application's loop does, which this
            // loop did not -- so Tab and the arrows move between the controls
            // of a dialog instead of being dispatched raw at whatever happens
            // to have the focus.
            if (DialogKey(&message))
                continue;
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }

        // Already done by `WM_CLOSE` when the dialog closed; this is for the
        // loop that ended on a quit.
        EnableOthers();
    }

    /// Disables every visible, enabled top-level window this library made on
    /// this thread, other than this one, and remembers which.
    void DisableOthers()
    {
        _disabled.Clear();
        EnumWindows(NoteWindowForModal, (nint)(void*)this);
        foreach (var handle in _disabled)
            EnableWindow((HWND)(void*)handle, 0);
    }

    /// One window `EnumWindows` found, considered for disabling.
    void Consider(HWND other)
    {
        if (other == window)
            return;
        if (GetWindowThreadProcessId(other, null) != GetCurrentThreadId())
            return;
        if (PeerOf(other) == null)
            return;
        if (IsWindowVisible(other) == 0 || IsWindowEnabled(other) == 0)
            return;
        _disabled.Add((nuint)(void*)other);
    }

    void EnableOthers()
    {
        foreach (var handle in _disabled)
            EnableWindow((HWND)(void*)handle, 1);
        _disabled.Clear();
    }

    // --------------------------------------------------- IContainerPeer

    public void AddChild(IControlPeer child)
    {
        SetParent((HWND)(void*)child.Handle, window);
    }

    public void RemoveChild(IControlPeer child)
    {
        SetParent((HWND)(void*)child.Handle, null);
    }
}

// =============================================================== the factory

/// The Windows backend.
///
/// One object, made once by `Application.Initialize`, holding nothing. Every
/// method is a call into Windows, which is why there is no state here and why
/// the LCL's equivalent -- `TWin32WidgetSet`, a `TWidgetSet` descendant with
/// forty fields -- is mostly the bookkeeping that peers now do for themselves.
public class Win32WidgetSet : IWidgetSet
{
    Font? _defaultFont;

    public Win32WidgetSet()
    {
        _defaultFont = null;

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

        // **Here, and not lazily in `Wake`.** A window belongs to the thread
        // that created it: one made on a worker has its messages queued to that
        // worker, where nothing ever dispatches them, so the post is accepted
        // and silently never arrives. This constructor runs inside
        // `Application.Initialize`, which is the UI thread by definition -- it
        // is the one that defines it.
        //
        // The self test did not catch this and could not have: it pumps with
        // `DoEvents`, which drains the queue itself, so the whole wake path was
        // bypassed. A screenshot caught it.
        EnsureWakeWindow();
    }

    public String Name => "Win32";

    public IWindowPeer CreateWindow(IWindowNotify owner, WindowBorder border)
    {
        return new WindowPeer(owner, border);
    }

    public IPushButtonPeer CreateButton(IControlNotify owner, IContainerPeer parent)
    {
        return new ButtonPeer(owner, parent);
    }

    public ICheckPeer CreateCheck(IControlNotify owner, IContainerPeer parent,
                                  CheckKind kind)
    {
        return new CheckPeer(owner, parent, kind);
    }

    public ILabelPeer CreateLabel(IControlNotify owner, IContainerPeer parent)
    {
        return new LabelPeer(owner, parent);
    }

    public ITextEntryPeer CreateTextEntry(IControlNotify owner, IContainerPeer parent,
                                          bool multiline)
    {
        return new TextEntryPeer(owner, parent, multiline);
    }

    public IListPeer CreateList(IControlNotify owner, IContainerPeer parent)
    {
        return new ListPeer(owner, parent);
    }

    public IComboPeer CreateCombo(IControlNotify owner, IContainerPeer parent)
    {
        return new ComboPeer(owner, parent);
    }

    public IGroupPeer CreateGroup(IControlNotify owner, IContainerPeer parent)
    {
        return new GroupPeer(owner, parent);
    }

    public IPanelPeer CreatePanel(IControlNotify owner, IContainerPeer parent)
    {
        return new PanelPeer(owner, parent);
    }

    public ICustomPeer CreateCustom(IControlNotify owner, IContainerPeer parent)
    {
        return new CustomPeer(owner, parent);
    }

    public IScrollBarPeer CreateScrollBar(IControlNotify owner, IContainerPeer parent,
                                          bool vertical)
    {
        return new ScrollBarPeer(owner, parent, vertical);
    }

    public IToolBarPeer CreateToolBar(IControlNotify owner, IContainerPeer parent)
    {
        return new ToolBarPeer(owner, parent);
    }

    public IStatusBarPeer CreateStatusBar(IControlNotify owner, IContainerPeer parent)
    {
        return new StatusBarPeer(owner, parent);
    }

    public IProgressPeer CreateProgress(IControlNotify owner, IContainerPeer parent)
    {
        return new ProgressPeer(owner, parent);
    }

    public ITrackBarPeer CreateTrackBar(IControlNotify owner, IContainerPeer parent,
                                        bool vertical)
    {
        return new TrackBarPeer(owner, parent, vertical);
    }

    public ITabControlPeer CreateTabControl(IControlNotify owner, IContainerPeer parent)
    {
        return new TabControlPeer(owner, parent);
    }

    public ITreeViewPeer CreateTreeView(IControlNotify owner, IContainerPeer parent)
    {
        return new TreeViewPeer(owner, parent);
    }

    public IListViewPeer CreateListView(IControlNotify owner, IContainerPeer parent)
    {
        return new ListViewPeer(owner, parent);
    }

    public ISpinPeer CreateSpin(IControlNotify owner, IContainerPeer parent)
    {
        return new SpinPeer(owner, parent);
    }

    public ICheckListPeer CreateCheckList(IControlNotify owner, IContainerPeer parent)
    {
        return new CheckListPeer(owner, parent);
    }

    public IHeaderPeer CreateHeader(IControlNotify owner, IContainerPeer parent)
    {
        return new HeaderPeer(owner, parent);
    }

    public IMenuPeer CreateMenu() => new MenuPeer(false);

    /// A menu bar, which Windows makes with a different call from a popup and
    /// will not exchange afterwards.
    public IMenuPeer CreateMenuBar() => new MenuPeer(true);

    public Result<IBitmapBackend, String> LoadBitmap(String path)
    {
        return LoadBitmapFile(path);
    }

    public Result<IBitmapBackend, String> LoadBitmapResource(int id)
    {
        return LoadResourceBitmap(id);
    }

    public Result<IBitmapBackend, String> CreateBitmap(int width, int height, byte[] pixels)
    {
        return CreateBitmapFromPixels(width, height, pixels);
    }

    public IImageListBackend CreateImageList(FSize imageSize)
    {
        return new ImageListBackend(imageSize);
    }

    public ITimerPeer CreateTimer(ITimerNotify owner) => new TimerPeer(owner);

    // ------------------------------------------------------------ clipboard
    //
    // The work is in `Clipboard.sl` beside this file.

    public void SetClipboard(ClipboardContent content) => WriteClipboard(content);

    public String GetClipboardText() => ReadClipboardText();

    public String GetClipboardHtml() => DecodeHtmlFormat(ReadClipboardFormat(HtmlFormat()));

    public ClipboardImage? GetClipboardImage() => ReadClipboardImage();

    public String[] GetClipboardFiles() => ReadClipboardFiles();

    public byte[] GetClipboardFormat(String name)
    {
        return ReadClipboardFormat(RegisterFormatNamed(name));
    }

    /// `CF_UNICODETEXT` alone stands for text because Windows synthesises it
    /// from `CF_TEXT` and `CF_OEMTEXT`; the DIBs likewise from `CF_BITMAP`.
    public bool ClipboardHas(ClipboardKind kind)
    {
        switch (kind)
        {
            case ClipboardKind.Text:
                return ClipboardOffers(ClipboardUnicodeText);
            case ClipboardKind.Html:
                return ClipboardOffers(HtmlFormat());
            case ClipboardKind.Image:
                return ClipboardOffers(ClipboardDib) || ClipboardOffers(ClipboardDibV5)
                    || ClipboardOffers(PngFormat());
            case ClipboardKind.Files:
                return ClipboardOffers(ClipboardHDrop);
        }
        return false;
    }

    public bool ClipboardHasFormat(String name) => ClipboardOffers(RegisterFormatNamed(name));

    public String[] ClipboardFormatNames() => ReadClipboardFormatNames();

    public IClipboardWatchPeer CreateClipboardWatch(IClipboardNotify owner)
    {
        return new ClipboardWatchPeer(owner);
    }

    public Result<String, DialogOutcome> ChooseFileToOpen(IWindowPeer? owner, String title,
                                                          String start, String[] filters)
    {
        return OpenFileDialog(owner, title, start, filters);
    }

    public Result<String, DialogOutcome> ChooseFileToSave(IWindowPeer? owner, String title,
                                                          String start, String[] filters)
    {
        return SaveFileDialog(owner, title, start, filters);
    }

    public Result<String, DialogOutcome> ChooseFolder(IWindowPeer? owner, String title)
    {
        return FolderDialogFor(owner, title);
    }

    public Result<Color, DialogOutcome> ChooseColor(IWindowPeer? owner, Color start)
    {
        return ColorDialogFor(owner, start);
    }

    public Result<Font, DialogOutcome> ChooseFont(IWindowPeer? owner, Font start)
    {
        return FontDialogFor(owner, start);
    }

    public IFontBackend CreateFont(Font font) => new FontBackend(font);

    public Color SystemColor(SystemColorId which)
    {
        return FromColorRef(GetSysColor(IndexOfColor(which)));
    }

    int IndexOfColor(SystemColorId which)
    {
        if (which == SystemColorId.Control)
            return ColorBtnFace;
        if (which == SystemColorId.ControlText)
            return ColorBtnText;
        if (which == SystemColorId.ControlDark)
            return ColorBtnShadow;
        if (which == SystemColorId.ControlLight)
            return ColorBtnHighlight;
        if (which == SystemColorId.Window)
            return ColorWindow;
        if (which == SystemColorId.WindowText)
            return ColorWindowText;
        if (which == SystemColorId.Highlight)
            return ColorHighlight;
        if (which == SystemColorId.HighlightText)
            return ColorHighlightText;
        return ColorGrayText;
    }

    /// The font Windows dresses its own dialogs in, read from the theme rather
    /// than guessed. Cached, because it costs a `SystemParametersInfoW` and a
    /// `NONCLIENTMETRICS` the size of a small struct, and because every control
    /// asks for it.
    public Font DefaultFont()
    {
        var held = _defaultFont;
        if (held != null)
            return (Font)held;

        // `SPI_GETNONCLIENTMETRICS` would give the exact face and size; until
        // the `NONCLIENTMETRICSW` layout is bound, Segoe UI at 9pt is what
        // every Windows version since Vista actually uses.
        var made = new Font("Segoe UI", 9);
        _defaultFont = made;
        return made;
    }

    public FSize ScreenSize
    {
        get
        {
            return Extent(GetSystemMetrics(SmScreenWidth), GetSystemMetrics(SmScreenHeight));
        }
    }

    public FRect WorkArea
    {
        get
        {
            Rect work;
            SystemParametersInfoW(SpiGetWorkArea, 0u, (void*)&work, 0u);
            return FromRect(work);
        }
    }

    // -------------------------------------------------------------- loop

    public void RunEventLoop()
    {
        Msg message;
        while (true)
        {
            int got = GetMessageW(&message, null, 0u, 0u);
            // Zero is WM_QUIT and -1 is a real failure; the two must not be
            // tested together, which is the bug `Win32.Succeeded` would cause
            // here and the reason it is not used.
            if (got == 0)
                return;
            if (got < 0)
                return;
            if (Navigated(&message))
                continue;
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }

    public bool PumpEvents()
    {
        Msg message;
        while (PeekMessageW(&message, null, 0u, 0u, PeekRemove) != 0)
        {
            if (message.Message == WmQuit)
                return false;
            if (Navigated(&message))
                continue;
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        return true;
    }

    /// Whether the keyboard did something to the window rather than to a
    /// control: Tab and Shift-Tab between controls, the arrow keys between
    /// radio buttons in a group, Enter for the default button, Escape for
    /// cancel, and a menu's underlined letter.
    ///
    /// **None of that is built into a window.** It is what `IsDialogMessage`
    /// does to a message on the way past, and a loop that does not call it has
    /// none of it -- `WS_TABSTOP` set on every control and Tab doing nothing at
    /// all, which is exactly where this library was.
    ///
    /// The message is given to the *top-level* window the keyboard is in, since
    /// that is what owns the group a control belongs to. Answering true means
    /// the message was handled and must not be dispatched again; dispatching it
    /// anyway is what makes Tab type a tab character into the text box it just
    /// left.
    /// **The body is `DialogKey`, at module level**, because `ShowModal` runs a
    /// loop of its own and needs the same pre-processing -- and it is not a
    /// method of this class.
    bool Navigated(Msg* message) => DialogKey(message);

    public void QuitEventLoop() => PostQuitMessage(0);

    /// Posts to the message-only window, which drains the queue when the
    /// message is dispatched.
    ///
    /// `PostMessageW` is safe from any thread -- it appends to the owning
    /// thread's queue and returns rather than waiting for it -- which is the
    /// whole reason this is the Win32 answer. The window is made in the
    /// constructor, on the UI thread, for the reason recorded there.
    public void Wake()
    {
        if (s_wake != null)
            PostMessageW(s_wake, WmApp, 0u, 0);
    }

    // ------------------------------------------------------------ dialogs

    public DialogResult ShowMessage(IWindowPeer? owner, String text, String caption,
                                    MessageButtons buttons, MessageIcon icon)
    {
        HWND parent = null;
        if (owner != null)
            parent = (HWND)(void*)((IWindowPeer)owner).Handle;

        uint style = ButtonsOf(buttons) | IconOf(icon);
        int answer = MessageBoxW(parent, text.ToUtf16().ToPointer(),
                                 caption.ToUtf16().ToPointer(), style);
        return ResultOf(answer);
    }

    uint ButtonsOf(MessageButtons buttons)
    {
        if (buttons == MessageButtons.OkCancel)
            return MbOkCancel;
        if (buttons == MessageButtons.YesNo)
            return MbYesNo;
        if (buttons == MessageButtons.YesNoCancel)
            return MbYesNoCancel;
        if (buttons == MessageButtons.RetryCancel)
            return MbRetryCancel;
        return MbOk;
    }

    uint IconOf(MessageIcon icon)
    {
        if (icon == MessageIcon.Information)
            return MbIconInformation;
        if (icon == MessageIcon.Warning)
            return MbIconWarning;
        if (icon == MessageIcon.Error)
            return MbIconError;
        if (icon == MessageIcon.Question)
            return MbIconQuestion;
        return 0u;
    }

    DialogResult ResultOf(int answer)
    {
        if (answer == IdOk)
            return DialogResult.Ok;
        if (answer == IdCancel)
            return DialogResult.Cancel;
        if (answer == IdYes)
            return DialogResult.Yes;
        if (answer == IdNo)
            return DialogResult.No;
        if (answer == IdAbort)
            return DialogResult.Abort;
        if (answer == IdRetry)
            return DialogResult.Retry;
        if (answer == IdIgnore)
            return DialogResult.Ignore;
        return DialogResult.None;
    }
}

#endif
