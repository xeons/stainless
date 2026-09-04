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

// user32: windows, messages, input and the clipboard.
//
// **Link with `-l user32`.** Unlike kernel32, this library is not already there
// because the C runtime needs it, so a program that calls anything in this
// module has to name it.
//
// The window procedure is the interesting part. `WNDPROC` is a plain C function
// pointer, which is exactly what a Stainless `delegate` is, so a window
// procedure is an ordinary module-level function and Windows calls it directly
// with no thunk in between:
//
// ```csharp
// long Procedure(void* window, uint message, ulong wParam, long lParam) {
//     if (message == WmDestroy) { PostQuitMessage(0); return 0; }
//     return DefWindowProcW(window, message, wParam, lParam);
// }
//
// WindowProcedure procedure = Procedure;      // one pointer, nothing captured
// ```
//
// A capturing lambda cannot become a delegate — there would be nowhere to keep
// what it captured — so per-window state goes where Win32 has always put it:
// `SetWindowLongPtrW` with `GwlpUserData`.
module Win32.User;

#if WINDOWS

import Win32;

// ================================================================ geometry

public struct Point {
    public int X;
    public int Y;
}

public struct Size {
    public int Width;
    public int Height;
}

/// Win32's `RECT`, whose edges are `Right` and `Bottom` *exclusive*. A rectangle
/// from 0,0 to 100,50 is 100 wide and 50 tall and does not include column 100.
public struct Rect {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}

public int Width(Rect rectangle) { return rectangle.Right - rectangle.Left; }
public int Height(Rect rectangle) { return rectangle.Bottom - rectangle.Top; }

public Rect Rectangle(int left, int top, int right, int bottom) {
    Rect rectangle;
    rectangle.Left = left;
    rectangle.Top = top;
    rectangle.Right = right;
    rectangle.Bottom = bottom;
    return rectangle;
}

// ================================================================= messages

/// `MSG`. `sizeof` is 48, as it is in C.
public struct Msg {
    public void* Window;
    public uint  Message;
    public ulong WParam;
    public long  LParam;
    public uint  Time;
    public Point Cursor;
}

/// `WNDPROC`: what Windows calls for every message a window receives.
///
/// `LRESULT` and `LPARAM` are signed pointer-width, `WPARAM` unsigned
/// pointer-width. They are written `long` and `ulong` here because Windows is
/// 64-bit; a 32-bit target would want `nint` and `nuint`.
public delegate long WindowProcedure(void* window, uint message, ulong wParam, long lParam);

/// `WNDENUMPROC`: return zero to stop the walk, non-zero to continue.
public delegate int WindowEnumerator(void* window, long parameter);

/// `TIMERPROC`, for a `SetTimer` that calls back rather than posting `WM_TIMER`.
public delegate void TimerProcedure(void* window, uint message, ulong id, uint ticks);

public const uint WmNull            = 0x0000u;
public const uint WmCreate          = 0x0001u;
public const uint WmDestroy         = 0x0002u;
public const uint WmMove            = 0x0003u;
public const uint WmSize            = 0x0005u;
public const uint WmActivate        = 0x0006u;
public const uint WmSetFocus        = 0x0007u;
public const uint WmKillFocus       = 0x0008u;
public const uint WmEnable          = 0x000Au;
public const uint WmSetText         = 0x000Cu;
public const uint WmGetText         = 0x000Du;
public const uint WmPaint           = 0x000Fu;
public const uint WmClose           = 0x0010u;
public const uint WmQuit            = 0x0012u;
public const uint WmEraseBackground = 0x0014u;
public const uint WmShowWindow      = 0x0018u;
public const uint WmActivateApp     = 0x001Cu;
public const uint WmSetCursor       = 0x0020u;
public const uint WmGetMinMaxInfo   = 0x0024u;
public const uint WmWindowPosChanged = 0x0047u;
public const uint WmDisplayChange   = 0x007Eu;
public const uint WmNcDestroy       = 0x0082u;
public const uint WmKeyDown         = 0x0100u;
public const uint WmKeyUp           = 0x0101u;
public const uint WmChar            = 0x0102u;
public const uint WmSysKeyDown      = 0x0104u;
public const uint WmSysKeyUp        = 0x0105u;
public const uint WmCommand         = 0x0111u;
public const uint WmSysCommand      = 0x0112u;
public const uint WmTimer           = 0x0113u;
public const uint WmMouseMove       = 0x0200u;
public const uint WmLeftButtonDown  = 0x0201u;
public const uint WmLeftButtonUp    = 0x0202u;
public const uint WmLeftDoubleClick = 0x0203u;
public const uint WmRightButtonDown = 0x0204u;
public const uint WmRightButtonUp   = 0x0205u;
public const uint WmMiddleButtonDown = 0x0207u;
public const uint WmMiddleButtonUp  = 0x0208u;
public const uint WmMouseWheel      = 0x020Au;
public const uint WmDropFiles       = 0x0233u;
public const uint WmUser            = 0x0400u;
public const uint WmApp             = 0x8000u;

/// `PeekMessageW`'s last argument.
public const uint PeekNoRemove = 0x0000u;
public const uint PeekRemove   = 0x0001u;

public extern "C" {
    int   GetMessageW(Msg* message, void* window, uint first, uint last);
    int   PeekMessageW(Msg* message, void* window, uint first, uint last, uint remove);
    int   TranslateMessage(Msg* message);
    long  DispatchMessageW(Msg* message);
    void  PostQuitMessage(int code);
    long  DefWindowProcW(void* window, uint message, ulong wParam, long lParam);
    long  SendMessageW(void* window, uint message, ulong wParam, long lParam);
    int   PostMessageW(void* window, uint message, ulong wParam, long lParam);
    int   PostThreadMessageW(uint thread, uint message, ulong wParam, long lParam);
    int   MessageBeep(uint kind);
}

/// The standard message loop, which is the same in every program that has one.
///
/// `GetMessageW` is the call `Win32.Succeeded` must not be used on: it returns
/// 0 for `WM_QUIT` and **-1** for an error, so the loop tests for greater than
/// zero and the caller gets the quit code back.
public int RunMessageLoop() {
    Msg message;
    while (true) {
        int result = GetMessageW(&message, null, 0u, 0u);
        if (result == 0) { return (int)message.WParam; }   // WM_QUIT
        if (result < 0)  { return -1; }                    // a real failure

        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
}

/// Handles everything already queued and returns, without blocking. A game or
/// an animation pumps this once per frame instead of blocking in `GetMessageW`.
///
/// Returns false once `WM_QUIT` has been seen, which is the signal to stop.
public bool PumpMessages() {
    Msg message;
    while (Win32.Succeeded(PeekMessageW(&message, null, 0u, 0u, PeekRemove))) {
        if (message.Message == WmQuit) { return false; }
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    return true;
}

// ============================================================ window classes

/// `WNDCLASSEXW`. `sizeof` is 80, and `Size` must be set to it before
/// registering — `WindowClass()` does that.
public struct WindowClass {
    public uint  Size;
    public uint  Style;
    public WindowProcedure Procedure;
    public int   ClassExtra;
    public int   WindowExtra;
    public void* Instance;
    public void* Icon;
    public void* Cursor;
    public void* Background;
    public ushort* MenuName;
    public ushort* ClassName;
    public void* SmallIcon;
}

public const uint ClassStyleVerticalRedraw   = 0x0001u;
public const uint ClassStyleHorizontalRedraw = 0x0002u;
public const uint ClassStyleDoubleClicks     = 0x0008u;
public const uint ClassStyleOwnDc            = 0x0020u;
public const uint ClassStyleClassDc          = 0x0040u;
public const uint ClassStyleParentDc         = 0x0080u;
public const uint ClassStyleNoClose          = 0x0200u;
public const uint ClassStyleSaveBits         = 0x0800u;
public const uint ClassStyleDropShadow       = 0x00020000u;

public extern "C" {
    ushort RegisterClassExW(WindowClass* windowClass);
    int    UnregisterClassW(ushort* name, void* instance);
    int    GetClassInfoExW(void* instance, ushort* name, WindowClass* windowClass);
}

/// A `WNDCLASSEXW` with `cbSize` filled in and everything else zeroed, so the
/// caller sets only what it cares about.
public WindowClass NewWindowClass() {
    WindowClass windowClass;
    windowClass.Size = (uint)sizeof(WindowClass);
    windowClass.Style = 0u;
    windowClass.Procedure = null;
    windowClass.ClassExtra = 0;
    windowClass.WindowExtra = 0;
    windowClass.Instance = null;
    windowClass.Icon = null;
    windowClass.Cursor = null;
    windowClass.Background = null;
    windowClass.MenuName = null;
    windowClass.ClassName = null;
    windowClass.SmallIcon = null;
    return windowClass;
}

// ================================================================== windows

public extern "C" {
    void* CreateWindowExW(uint extendedStyle, ushort* className, ushort* windowName,
                          uint style, int x, int y, int width, int height,
                          void* parent, void* menu, void* instance, void* parameter);
    int   DestroyWindow(void* window);
    int   ShowWindow(void* window, int command);
    int   UpdateWindow(void* window);
    int   MoveWindow(void* window, int x, int y, int width, int height, int repaint);
    int   SetWindowPos(void* window, void* insertAfter, int x, int y,
                       int width, int height, uint flags);
    int   GetClientRect(void* window, Rect* rectangle);
    int   GetWindowRect(void* window, Rect* rectangle);
    int   AdjustWindowRectEx(Rect* rectangle, uint style, int hasMenu, uint extendedStyle);
    void* GetParent(void* window);
    void* SetParent(void* child, void* parent);
    void* FindWindowW(ushort* className, ushort* windowName);
    void* GetForegroundWindow();
    int   SetForegroundWindow(void* window);
    void* GetFocus();
    void* SetFocus(void* window);
    void* GetDesktopWindow();
    int   IsWindow(void* window);
    int   IsWindowVisible(void* window);
    int   IsIconic(void* window);
    int   IsZoomed(void* window);
    int   EnumWindows(WindowEnumerator callback, long parameter);
    int   EnumChildWindows(void* parent, WindowEnumerator callback, long parameter);
    long  GetWindowLongPtrW(void* window, int index);
    long  SetWindowLongPtrW(void* window, int index, long value);
    uint  GetWindowThreadProcessId(void* window, uint* processId);

    int   SetWindowTextW(void* window, ushort* text);
    int   GetWindowTextW(void* window, ushort* buffer, int size);
    int   GetWindowTextLengthW(void* window);

    int   InvalidateRect(void* window, Rect* rectangle, int erase);
    int   ValidateRect(void* window, Rect* rectangle);
}

public const uint WsOverlapped   = 0x00000000u;
public const uint WsPopup        = 0x80000000u;
public const uint WsChild        = 0x40000000u;
public const uint WsMinimize     = 0x20000000u;
public const uint WsVisible      = 0x10000000u;
public const uint WsDisabled     = 0x08000000u;
public const uint WsClipSiblings = 0x04000000u;
public const uint WsClipChildren = 0x02000000u;
public const uint WsMaximize     = 0x01000000u;
public const uint WsCaption      = 0x00C00000u;
public const uint WsBorder       = 0x00800000u;
public const uint WsDialogFrame  = 0x00400000u;
public const uint WsVerticalScroll   = 0x00200000u;
public const uint WsHorizontalScroll = 0x00100000u;
public const uint WsSystemMenu   = 0x00080000u;
public const uint WsThickFrame   = 0x00040000u;
public const uint WsGroup        = 0x00020000u;
public const uint WsTabStop      = 0x00010000u;
public const uint WsMinimizeBox  = 0x00020000u;
public const uint WsMaximizeBox  = 0x00010000u;

/// `WS_OVERLAPPEDWINDOW`: the ordinary top-level window with a caption, a
/// system menu, a resizable frame and both boxes.
public const uint WsOverlappedWindow = 0x00CF0000u;

/// `WS_POPUPWINDOW`.
public const uint WsPopupWindow = 0x80880000u;

public const uint WsExDialogModalFrame = 0x00000001u;
public const uint WsExTopMost          = 0x00000008u;
public const uint WsExAcceptFiles      = 0x00000010u;
public const uint WsExTransparent      = 0x00000020u;
public const uint WsExToolWindow       = 0x00000080u;
public const uint WsExWindowEdge       = 0x00000100u;
public const uint WsExClientEdge       = 0x00000200u;
public const uint WsExAppWindow        = 0x00040000u;
public const uint WsExLayered          = 0x00080000u;
public const uint WsExNoActivate       = 0x08000000u;

/// `ShowWindow`'s command.
public const int SwHide            = 0;
public const int SwShowNormal      = 1;
public const int SwShowMinimized   = 2;
public const int SwShowMaximized   = 3;
public const int SwShowNoActivate  = 4;
public const int SwShow            = 5;
public const int SwMinimize        = 6;
public const int SwShowMinNoActive = 7;
public const int SwShowNa          = 8;
public const int SwRestore         = 9;
public const int SwShowDefault     = 10;

/// `CW_USEDEFAULT`: let Windows choose the position or the size.
public const int UseDefault = -2147483648;

/// `SetWindowPos` flags.
public const uint SwpNoSize     = 0x0001u;
public const uint SwpNoMove     = 0x0002u;
public const uint SwpNoZOrder   = 0x0004u;
public const uint SwpNoRedraw   = 0x0008u;
public const uint SwpNoActivate = 0x0010u;
public const uint SwpFrameChanged = 0x0020u;
public const uint SwpShowWindow = 0x0040u;
public const uint SwpHideWindow = 0x0080u;

/// `GetWindowLongPtrW` and `SetWindowLongPtrW` indices. `GwlpUserData` is where
/// per-window state belongs, since a window procedure is a bare function
/// pointer and cannot capture any.
public const int GwlpUserData     = -21;
public const int GwlpWindowProc   = -4;
public const int GwlpInstance     = -6;
public const int GwlpId           = -12;
public const int GwlStyle         = -16;
public const int GwlExtendedStyle = -20;

/// Creates an ordinary top-level window. The long form is right there when a
/// caller needs an extended style, a parent or a menu.
public void* CreateWindow(String className, String title, uint style,
                          int x, int y, int width, int height, void* instance) {
    return CreateWindowExW(0u, className.ToUtf16().ToPointer(), title.ToUtf16().ToPointer(),
                           style, x, y, width, height, null, null, instance, null);
}

/// The window's title, or a control's text.
public String WindowText(void* window) {
    int length = GetWindowTextLengthW(window);
    if (length <= 0) { return ""; }

    var buffer = new WideBuffer((uint)length);
    int units = GetWindowTextW(window, buffer.Pointer(), length + 1);
    if (units <= 0) { return ""; }
    return buffer.Text((uint)units);
}

public bool SetWindowText(void* window, String text) {
    return Win32.Succeeded(SetWindowTextW(window, text.ToUtf16().ToPointer()));
}

/// The client area, whose left and top are always zero — it is a size wearing
/// the shape of a rectangle.
public Rect ClientRect(void* window) {
    Rect rectangle;
    GetClientRect(window, &rectangle);
    return rectangle;
}

/// The window's outer rectangle in screen coordinates, frame included.
public Rect WindowRect(void* window) {
    Rect rectangle;
    GetWindowRect(window, &rectangle);
    return rectangle;
}

/// Grows a wanted *client* rectangle into the window rectangle that would
/// contain it, which is how a window ends up the size the caller asked for.
public Rect AdjustForFrame(Rect client, uint style, uint extendedStyle) {
    Rect rectangle = client;
    AdjustWindowRectEx(&rectangle, style, 0, extendedStyle);
    return rectangle;
}

/// Marks the whole window as needing repainting, which produces a `WM_PAINT`.
public bool Invalidate(void* window, bool erase) {
    return Win32.Succeeded(InvalidateRect(window, null, erase ? 1 : 0));
}

// ================================================================= painting

/// `PAINTSTRUCT`. Its `rgbReserved[32]` is eight `uint` fields here, because
/// Stainless has no inline fixed-size array field; the size, 72, and every
/// offset before it are the ones C computes. Nothing should read them — they
/// are reserved to Windows.
public struct PaintStruct {
    public void* Dc;
    public int   Erase;
    public Rect  Paint;
    public int   Restore;
    public int   IncrementalUpdate;
    public uint  Reserved0;
    public uint  Reserved1;
    public uint  Reserved2;
    public uint  Reserved3;
    public uint  Reserved4;
    public uint  Reserved5;
    public uint  Reserved6;
    public uint  Reserved7;
}

public extern "C" {
    void* BeginPaint(void* window, PaintStruct* paint);
    int   EndPaint(void* window, PaintStruct* paint);
    void* GetDC(void* window);
    void* GetWindowDC(void* window);
    int   ReleaseDC(void* window, void* dc);
    int   FillRect(void* dc, Rect* rectangle, void* brush);
    int   FrameRect(void* dc, Rect* rectangle, void* brush);
    int   InvertRect(void* dc, Rect* rectangle);
    int   DrawTextW(void* dc, ushort* text, int length, Rect* rectangle, uint format);
}

/// `DrawTextW`'s format.
public const uint DtLeft      = 0x00000000u;
public const uint DtCenter    = 0x00000001u;
public const uint DtRight     = 0x00000002u;
public const uint DtVerticalCenter = 0x00000004u;
public const uint DtBottom    = 0x00000008u;
public const uint DtWordBreak = 0x00000010u;
public const uint DtSingleLine = 0x00000020u;
public const uint DtCalculateOnly = 0x00000400u;
public const uint DtNoClip    = 0x00000100u;

/// Draws text into a rectangle. `-1` for the length means "up to the NUL",
/// which is what a Stainless string widened for the call always has.
public int DrawText(void* dc, String text, Rect* rectangle, uint format) {
    return DrawTextW(dc, text.ToUtf16().ToPointer(), -1, rectangle, format);
}

// ============================================================== message box

public extern "C" {
    int MessageBoxW(void* owner, ushort* text, ushort* caption, uint style);
}

public const uint MbOk               = 0x00000000u;
public const uint MbOkCancel         = 0x00000001u;
public const uint MbAbortRetryIgnore = 0x00000002u;
public const uint MbYesNoCancel      = 0x00000003u;
public const uint MbYesNo            = 0x00000004u;
public const uint MbRetryCancel      = 0x00000005u;

public const uint MbIconError    = 0x00000010u;
public const uint MbIconQuestion = 0x00000020u;
public const uint MbIconWarning  = 0x00000030u;
public const uint MbIconInformation = 0x00000040u;

public const uint MbDefaultButton1 = 0x00000000u;
public const uint MbDefaultButton2 = 0x00000100u;
public const uint MbDefaultButton3 = 0x00000200u;

public const uint MbApplicationModal = 0x00000000u;
public const uint MbSystemModal      = 0x00001000u;
public const uint MbTaskModal        = 0x00002000u;
public const uint MbTopMost          = 0x00040000u;
public const uint MbSetForeground    = 0x00010000u;

/// Which button was pressed.
public const int IdOk     = 1;
public const int IdCancel = 2;
public const int IdAbort  = 3;
public const int IdRetry  = 4;
public const int IdIgnore = 5;
public const int IdYes    = 6;
public const int IdNo     = 7;

/// Shows a message box and returns the `Id...` of the button pressed.
public int MessageBox(void* owner, String text, String caption, uint style) {
    return MessageBoxW(owner, text.ToUtf16().ToPointer(),
                       caption.ToUtf16().ToPointer(), style);
}

/// A message box with one OK button, for a program that just needs to say
/// something. Returns nothing worth reading.
public void Say(String text, String caption) {
    MessageBoxW(null, text.ToUtf16().ToPointer(), caption.ToUtf16().ToPointer(),
                MbOk | MbIconInformation);
}

/// Yes or no, as a `bool`.
public bool Ask(String text, String caption) {
    return MessageBoxW(null, text.ToUtf16().ToPointer(), caption.ToUtf16().ToPointer(),
                       MbYesNo | MbIconQuestion) == IdYes;
}

// =================================================================== cursor

public extern "C" {
    int   GetCursorPos(Point* point);
    int   SetCursorPos(int x, int y);
    void* LoadCursorW(void* instance, ushort* name);
    void* SetCursor(void* cursor);
    int   ShowCursor(int show);
    int   ScreenToClient(void* window, Point* point);
    int   ClientToScreen(void* window, Point* point);
    void* SetCapture(void* window);
    int   ReleaseCapture();
}

/// The standard cursors, passed to `LoadCursorW` with a null instance. They are
/// integers pretending to be strings — `MAKEINTRESOURCE` — which is why these
/// are cast rather than named.
public ushort* CursorArrow()    { return (ushort*)(nuint)32512u; }
public ushort* CursorIBeam()    { return (ushort*)(nuint)32513u; }
public ushort* CursorWait()     { return (ushort*)(nuint)32514u; }
public ushort* CursorCross()    { return (ushort*)(nuint)32515u; }
public ushort* CursorSizeAll()  { return (ushort*)(nuint)32646u; }
public ushort* CursorHand()     { return (ushort*)(nuint)32649u; }

/// Where the mouse is, in screen coordinates.
public Point CursorPosition() {
    Point point;
    GetCursorPos(&point);
    return point;
}

// ================================================================== keyboard

public extern "C" {
    short GetAsyncKeyState(int key);
    short GetKeyState(int key);
    int   GetKeyboardState(byte* state);
    uint  MapVirtualKeyW(uint code, uint mapping);
    int   GetKeyNameTextW(long lParam, ushort* buffer, int size);
    short VkKeyScanW(ushort character);
}

public const int VkBack    = 0x08;
public const int VkTab     = 0x09;
public const int VkReturn  = 0x0D;
public const int VkShift   = 0x10;
public const int VkControl = 0x11;
public const int VkMenu    = 0x12;    // Alt
public const int VkPause   = 0x13;
public const int VkCapital = 0x14;
public const int VkEscape  = 0x1B;
public const int VkSpace   = 0x20;
public const int VkPageUp  = 0x21;
public const int VkPageDown = 0x22;
public const int VkEnd     = 0x23;
public const int VkHome    = 0x24;
public const int VkLeft    = 0x25;
public const int VkUp      = 0x26;
public const int VkRight   = 0x27;
public const int VkDown    = 0x28;
public const int VkInsert  = 0x2D;
public const int VkDelete  = 0x2E;
public const int VkF1      = 0x70;
public const int VkF2      = 0x71;
public const int VkF3      = 0x72;
public const int VkF4      = 0x73;
public const int VkF5      = 0x74;
public const int VkF6      = 0x75;
public const int VkF7      = 0x76;
public const int VkF8      = 0x77;
public const int VkF9      = 0x78;
public const int VkF10     = 0x79;
public const int VkF11     = 0x7A;
public const int VkF12     = 0x7B;
public const int VkLeftShift    = 0xA0;
public const int VkRightShift   = 0xA1;
public const int VkLeftControl  = 0xA2;
public const int VkRightControl = 0xA3;

/// True while the key is physically down, asked of the hardware rather than of
/// the message queue. The high bit is the one that means "down".
public bool KeyDown(int key) {
    return (GetAsyncKeyState(key) & 0x8000) != 0;
}

/// True when a toggle key — Caps Lock, Num Lock — is currently on.
public bool KeyToggled(int key) {
    return (GetKeyState(key) & 0x0001) != 0;
}

// ================================================================= clipboard

public extern "C" {
    int   OpenClipboard(void* owner);
    int   CloseClipboard();
    int   EmptyClipboard();
    void* GetClipboardData(uint format);
    void* SetClipboardData(uint format, void* handle);
    int   IsClipboardFormatAvailable(uint format);

    void* GlobalAlloc(uint flags, nuint size);
    void* GlobalLock(void* block);
    int   GlobalUnlock(void* block);
    void* GlobalFree(void* block);
}

public const uint ClipboardText        = 1u;
public const uint ClipboardBitmap      = 2u;
public const uint ClipboardUnicodeText = 13u;
public const uint ClipboardHDrop       = 15u;

/// What is on the clipboard as text, or an empty string when there is none.
public String ClipboardString() {
    if (!IsClipboardAvailable()) { return ""; }
    if (!Win32.Succeeded(OpenClipboard(null))) { return ""; }

    void* handle = GetClipboardData(ClipboardUnicodeText);
    if (handle == null) {
        CloseClipboard();
        return "";
    }

    void* locked = GlobalLock(handle);
    String text = locked == null ? "" : Text.FromNullTerminatedUtf16((ushort*)locked);
    GlobalUnlock(handle);
    CloseClipboard();
    return text;
}

/// True when the clipboard currently holds Unicode text.
public bool IsClipboardAvailable() {
    return Win32.Succeeded(IsClipboardFormatAvailable(ClipboardUnicodeText));
}

/// Puts text on the clipboard.
///
/// The clipboard takes ownership of the block, so it is deliberately not freed
/// here on the success path — freeing it would be the bug, not the leak.
public bool SetClipboardString(String text) {
    var wide = text.ToUtf16();
    nuint bytes = (wide.UnitCount() + 1u) * 2u;

    void* block = GlobalAlloc(0x0002u, bytes);         // GMEM_MOVEABLE
    if (block == null) { return false; }

    void* locked = GlobalLock(block);
    if (locked == null) {
        GlobalFree(block);
        return false;
    }

    ushort* target = (ushort*)locked;
    ushort* source = wide.ToPointer();
    for (nuint i = 0u; i < wide.UnitCount(); i = i + 1u) { target[i] = source[i]; }
    target[wide.UnitCount()] = 0u;
    GlobalUnlock(block);

    if (!Win32.Succeeded(OpenClipboard(null))) {
        GlobalFree(block);
        return false;
    }

    EmptyClipboard();
    bool placed = SetClipboardData(ClipboardUnicodeText, block) != null;
    CloseClipboard();

    if (!placed) { GlobalFree(block); }
    return placed;
}

// ==================================================================== timers

public extern "C" {
    ulong SetTimer(void* window, ulong id, uint milliseconds, TimerProcedure callback);
    int   KillTimer(void* window, ulong id);
}

// =================================================================== metrics

public extern "C" {
    int  GetSystemMetrics(int index);
    int  SystemParametersInfoW(uint action, uint parameter, void* value, uint winIni);
    void* LoadIconW(void* instance, ushort* name);
    int  SetProcessDPIAware();
    uint GetDpiForWindow(void* window);
}

public const int SmScreenWidth     = 0;
public const int SmScreenHeight    = 1;
public const int SmVerticalScrollWidth = 2;
public const int SmHorizontalScrollHeight = 3;
public const int SmCaptionHeight   = 4;
public const int SmBorderWidth     = 5;
public const int SmBorderHeight    = 6;
public const int SmCursorWidth     = 13;
public const int SmCursorHeight    = 14;
public const int SmIconWidth       = 11;
public const int SmIconHeight      = 12;
public const int SmMenuHeight      = 15;
public const int SmMouseButtons    = 43;
public const int SmMonitorCount    = 80;
public const int SmVirtualScreenX  = 76;
public const int SmVirtualScreenY  = 77;
public const int SmVirtualScreenWidth  = 78;
public const int SmVirtualScreenHeight = 79;
public const int SmRemoteSession   = 0x1000;

/// The primary monitor's size in pixels.
public Size ScreenSize() {
    Size size;
    size.Width = GetSystemMetrics(SmScreenWidth);
    size.Height = GetSystemMetrics(SmScreenHeight);
    return size;
}

/// The standard application icon, passed to `LoadIconW` with a null instance.
public ushort* IconApplication() { return (ushort*)(nuint)32512u; }
public ushort* IconError()       { return (ushort*)(nuint)32513u; }
public ushort* IconQuestion()    { return (ushort*)(nuint)32514u; }
public ushort* IconWarning()     { return (ushort*)(nuint)32515u; }
public ushort* IconInformation() { return (ushort*)(nuint)32516u; }

#endif
