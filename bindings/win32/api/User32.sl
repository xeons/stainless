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

// user32.dll, declared and nothing else.
//
// Declarations cost nothing, so this module needs no library on its own; a
// program that *calls* one of them wants `-l user32`, or `Win32.Ui`, which
// names it with a pragma.
//
// `POINT`, `SIZE` and `RECT` live here rather than in a module of their own.
// They are windef.h types, but user32 is where they appear in every signature,
// and a separate module would mean a second import to name a rectangle.
//
// The window procedure is the interesting part. `WNDPROC` is a plain C function
// pointer, which is exactly what a Stainless `delegate` is, so a window
// procedure is an ordinary module-level function and Windows calls it directly
// with no thunk in between. A delegate captures nothing, so per-window state
// goes where Win32 has always put it: `SetWindowLongPtrW` with `GwlpUserData`.
module Win32.User32;

import Win32.Handles;

#if WINDOWS

// ================================================================= geometry

public struct Point {
    public int X;
    public int Y;
}

public struct Size {
    public int Width;
    public int Height;
}

/// `RECT`, whose `Right` and `Bottom` are *exclusive*. A rectangle from 0,0 to
/// 100,50 is 100 wide and 50 tall and does not include column 100.
public struct Rect {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}

// ================================================================= messages

/// `MSG`. `sizeof` is 48, as it is in C.
public struct Msg {
    public HWND  Window;
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
public delegate long WindowProcedure(HWND window, uint message, ulong wParam, long lParam);

/// `WNDENUMPROC`: return zero to stop the walk, non-zero to continue.
public delegate int WindowEnumerator(HWND window, long parameter);

/// `TIMERPROC`, for a `SetTimer` that calls back rather than posting `WM_TIMER`.
public delegate void TimerProcedure(HWND window, uint message, ulong id, uint ticks);

public const uint WmNull             = 0x0000u;
public const uint WmCreate           = 0x0001u;
public const uint WmDestroy          = 0x0002u;
public const uint WmMove             = 0x0003u;
public const uint WmSize             = 0x0005u;
public const uint WmActivate         = 0x0006u;
public const uint WmSetFocus         = 0x0007u;
public const uint WmKillFocus        = 0x0008u;
public const uint WmEnable           = 0x000Au;
public const uint WmSetText          = 0x000Cu;
public const uint WmGetText          = 0x000Du;
public const uint WmPaint            = 0x000Fu;
public const uint WmClose            = 0x0010u;
public const uint WmQuit             = 0x0012u;
public const uint WmEraseBackground  = 0x0014u;
public const uint WmShowWindow       = 0x0018u;
public const uint WmActivateApp      = 0x001Cu;
public const uint WmSetCursor        = 0x0020u;
public const uint WmGetMinMaxInfo    = 0x0024u;
public const uint WmWindowPosChanged = 0x0047u;
public const uint WmDisplayChange    = 0x007Eu;
public const uint WmNcDestroy        = 0x0082u;
public const uint WmKeyDown          = 0x0100u;
public const uint WmKeyUp            = 0x0101u;
public const uint WmChar             = 0x0102u;
public const uint WmSysKeyDown       = 0x0104u;
public const uint WmSysKeyUp         = 0x0105u;
public const uint WmCommand          = 0x0111u;
public const uint WmSysCommand       = 0x0112u;
public const uint WmTimer            = 0x0113u;
public const uint WmMouseMove        = 0x0200u;
public const uint WmLeftButtonDown   = 0x0201u;
public const uint WmLeftButtonUp     = 0x0202u;
public const uint WmLeftDoubleClick  = 0x0203u;
public const uint WmRightButtonDown  = 0x0204u;
public const uint WmRightButtonUp    = 0x0205u;
public const uint WmMiddleButtonDown = 0x0207u;
public const uint WmMiddleButtonUp   = 0x0208u;
public const uint WmMouseWheel       = 0x020Au;
public const uint WmDropFiles        = 0x0233u;
public const uint WmUser             = 0x0400u;
public const uint WmApp              = 0x8000u;

/// `PeekMessageW`'s last argument.
public const uint PeekNoRemove = 0x0000u;
public const uint PeekRemove   = 0x0001u;

public extern "C" {
    int  GetMessageW(Msg* message, HWND window, uint first, uint last);
    int  PeekMessageW(Msg* message, HWND window, uint first, uint last, uint remove);
    int  TranslateMessage(Msg* message);
    long DispatchMessageW(Msg* message);
    void PostQuitMessage(int code);
    long DefWindowProcW(HWND window, uint message, ulong wParam, long lParam);
    long SendMessageW(HWND window, uint message, ulong wParam, long lParam);
    int  PostMessageW(HWND window, uint message, ulong wParam, long lParam);
    int  PostThreadMessageW(uint thread, uint message, ulong wParam, long lParam);
    int  MessageBeep(uint kind);
}

// ============================================================ window classes

/// `WNDCLASSEXW`. `sizeof` is 80, and `Size` must be set to it before
/// registering.
public struct WindowClass {
    public uint            Size;
    public uint            Style;
    public WindowProcedure Procedure;
    public int             ClassExtra;
    public int             WindowExtra;
    public HINSTANCE       Instance;
    public HICON           Icon;
    public HCURSOR         Cursor;
    public HBRUSH          Background;
    public char16*         MenuName;
    public char16*         ClassName;
    public HICON           SmallIcon;
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
    int    UnregisterClassW(char16* name, HINSTANCE instance);
    int    GetClassInfoExW(HINSTANCE instance, char16* name, WindowClass* windowClass);
}

// ================================================================== windows

public extern "C" {
    HWND CreateWindowExW(uint extendedStyle, char16* className, char16* windowName,
                         uint style, int x, int y, int width, int height,
                         HWND parent, HMENU menu, HINSTANCE instance, void* parameter);
    int  DestroyWindow(HWND window);
    int  ShowWindow(HWND window, int command);
    int  UpdateWindow(HWND window);
    int  MoveWindow(HWND window, int x, int y, int width, int height, int repaint);
    int  SetWindowPos(HWND window, HWND insertAfter, int x, int y,
                      int width, int height, uint flags);
    int  GetClientRect(HWND window, Rect* rectangle);
    int  GetWindowRect(HWND window, Rect* rectangle);
    int  AdjustWindowRectEx(Rect* rectangle, uint style, int hasMenu, uint extendedStyle);
    HWND GetParent(HWND window);
    HWND SetParent(HWND child, HWND parent);
    HWND FindWindowW(char16* className, char16* windowName);
    HWND GetForegroundWindow();
    int  SetForegroundWindow(HWND window);
    HWND GetFocus();
    HWND SetFocus(HWND window);
    HWND GetDesktopWindow();
    int  IsWindow(HWND window);
    int  IsWindowVisible(HWND window);
    int  IsIconic(HWND window);
    int  IsZoomed(HWND window);
    int  EnumWindows(WindowEnumerator callback, long parameter);
    int  EnumChildWindows(HWND parent, WindowEnumerator callback, long parameter);
    long GetWindowLongPtrW(HWND window, int index);
    long SetWindowLongPtrW(HWND window, int index, long value);
    uint GetWindowThreadProcessId(HWND window, uint* processId);

    int  SetWindowTextW(HWND window, char16* text);
    int  GetWindowTextW(HWND window, char16* buffer, int size);
    int  GetWindowTextLengthW(HWND window);

    int  InvalidateRect(HWND window, Rect* rectangle, int erase);
    int  ValidateRect(HWND window, Rect* rectangle);
}

public const uint WsOverlapped       = 0x00000000u;
public const uint WsPopup            = 0x80000000u;
public const uint WsChild            = 0x40000000u;
public const uint WsMinimize         = 0x20000000u;
public const uint WsVisible          = 0x10000000u;
public const uint WsDisabled         = 0x08000000u;
public const uint WsClipSiblings     = 0x04000000u;
public const uint WsClipChildren     = 0x02000000u;
public const uint WsMaximize         = 0x01000000u;
public const uint WsCaption          = 0x00C00000u;
public const uint WsBorder           = 0x00800000u;
public const uint WsDialogFrame      = 0x00400000u;
public const uint WsVerticalScroll   = 0x00200000u;
public const uint WsHorizontalScroll = 0x00100000u;
public const uint WsSystemMenu       = 0x00080000u;
public const uint WsThickFrame       = 0x00040000u;
public const uint WsGroup            = 0x00020000u;
public const uint WsTabStop          = 0x00010000u;
public const uint WsMinimizeBox      = 0x00020000u;
public const uint WsMaximizeBox      = 0x00010000u;

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

public const uint SwpNoSize       = 0x0001u;
public const uint SwpNoMove       = 0x0002u;
public const uint SwpNoZOrder     = 0x0004u;
public const uint SwpNoRedraw     = 0x0008u;
public const uint SwpNoActivate   = 0x0010u;
public const uint SwpFrameChanged = 0x0020u;
public const uint SwpShowWindow   = 0x0040u;
public const uint SwpHideWindow   = 0x0080u;

/// `GetWindowLongPtrW` and `SetWindowLongPtrW` indices. `GwlpUserData` is where
/// per-window state belongs, since a window procedure is a bare function
/// pointer and cannot capture any.
public const int GwlpUserData     = -21;
public const int GwlpWindowProc   = -4;
public const int GwlpInstance     = -6;
public const int GwlpId           = -12;
public const int GwlStyle         = -16;
public const int GwlExtendedStyle = -20;

// ================================================================= painting

/// `PAINTSTRUCT`. Its `rgbReserved[32]` is eight `uint` fields here, because
/// Stainless has no inline fixed-size array field; the size, 72, and every
/// offset before it are the ones C computes. Nothing should read them — they
/// are reserved to Windows.
public struct PaintStruct {
    public HDC  Dc;
    public int  Erase;
    public Rect Paint;
    public int  Restore;
    public int  IncrementalUpdate;
    public uint Reserved0;
    public uint Reserved1;
    public uint Reserved2;
    public uint Reserved3;
    public uint Reserved4;
    public uint Reserved5;
    public uint Reserved6;
    public uint Reserved7;
}

public extern "C" {
    HDC BeginPaint(HWND window, PaintStruct* paint);
    int EndPaint(HWND window, PaintStruct* paint);
    HDC GetDC(HWND window);
    HDC GetWindowDC(HWND window);
    int ReleaseDC(HWND window, HDC dc);
    int FillRect(HDC dc, Rect* rectangle, HBRUSH brush);
    int FrameRect(HDC dc, Rect* rectangle, HBRUSH brush);
    int InvertRect(HDC dc, Rect* rectangle);
    int DrawTextW(HDC dc, char16* text, int length, Rect* rectangle, uint format);
}

public const uint DtLeft           = 0x00000000u;
public const uint DtCenter         = 0x00000001u;
public const uint DtRight          = 0x00000002u;
public const uint DtVerticalCenter = 0x00000004u;
public const uint DtBottom         = 0x00000008u;
public const uint DtWordBreak      = 0x00000010u;
public const uint DtSingleLine     = 0x00000020u;
public const uint DtNoClip         = 0x00000100u;
public const uint DtCalculateOnly  = 0x00000400u;

// ============================================================== message box

public extern "C" {
    int MessageBoxW(HWND owner, char16* text, char16* caption, uint style);
}

public const uint MbOk               = 0x00000000u;
public const uint MbOkCancel         = 0x00000001u;
public const uint MbAbortRetryIgnore = 0x00000002u;
public const uint MbYesNoCancel      = 0x00000003u;
public const uint MbYesNo            = 0x00000004u;
public const uint MbRetryCancel      = 0x00000005u;

public const uint MbIconError       = 0x00000010u;
public const uint MbIconQuestion    = 0x00000020u;
public const uint MbIconWarning     = 0x00000030u;
public const uint MbIconInformation = 0x00000040u;

public const uint MbDefaultButton1 = 0x00000000u;
public const uint MbDefaultButton2 = 0x00000100u;
public const uint MbDefaultButton3 = 0x00000200u;

public const uint MbApplicationModal = 0x00000000u;
public const uint MbSystemModal      = 0x00001000u;
public const uint MbTaskModal        = 0x00002000u;
public const uint MbSetForeground    = 0x00010000u;
public const uint MbTopMost          = 0x00040000u;

/// Which button was pressed.
public const int IdOk     = 1;
public const int IdCancel = 2;
public const int IdAbort  = 3;
public const int IdRetry  = 4;
public const int IdIgnore = 5;
public const int IdYes    = 6;
public const int IdNo     = 7;

// =================================================================== cursor

public extern "C" {
    int     GetCursorPos(Point* point);
    int     SetCursorPos(int x, int y);
    HCURSOR LoadCursorW(HINSTANCE instance, char16* name);
    HCURSOR SetCursor(HCURSOR cursor);
    int     ShowCursor(int show);
    int     ScreenToClient(HWND window, Point* point);
    int     ClientToScreen(HWND window, Point* point);
    HWND    SetCapture(HWND window);
    int     ReleaseCapture();
}

/// The standard cursors, passed to `LoadCursorW` with a null instance. They are
/// integers pretending to be strings — `MAKEINTRESOURCE` — which is why these
/// are functions rather than constants: Stainless has no `const char16*`.
public char16* CursorArrow()   { return (char16*)(nuint)32512u; }
public char16* CursorIBeam()   { return (char16*)(nuint)32513u; }
public char16* CursorWait()    { return (char16*)(nuint)32514u; }
public char16* CursorCross()   { return (char16*)(nuint)32515u; }
public char16* CursorSizeAll() { return (char16*)(nuint)32646u; }
public char16* CursorHand()    { return (char16*)(nuint)32649u; }
public char16* CursorSizeNS()  { return (char16*)(nuint)32645u; }
public char16* CursorSizeWE()  { return (char16*)(nuint)32644u; }
public char16* CursorNo()      { return (char16*)(nuint)32648u; }

/// `WM_SETCURSOR`'s low word: where on the window the pointer is. A control
/// answers only for its own client area and leaves the frame to Windows.
public const long HtClient = 1;

// ================================================================= keyboard

public extern "C" {
    short GetAsyncKeyState(int key);
    short GetKeyState(int key);
    int   GetKeyboardState(byte* state);
    uint  MapVirtualKeyW(uint code, uint mapping);
    int   GetKeyNameTextW(long lParam, char16* buffer, int size);
    short VkKeyScanW(ushort character);
}

public const int VkBack     = 0x08;
public const int VkTab      = 0x09;
public const int VkReturn   = 0x0D;
public const int VkShift    = 0x10;
public const int VkControl  = 0x11;
public const int VkMenu     = 0x12;    // Alt
public const int VkPause    = 0x13;
public const int VkCapital  = 0x14;
public const int VkEscape   = 0x1B;
public const int VkSpace    = 0x20;
public const int VkPageUp   = 0x21;
public const int VkPageDown = 0x22;
public const int VkEnd      = 0x23;
public const int VkHome     = 0x24;
public const int VkLeft     = 0x25;
public const int VkUp       = 0x26;
public const int VkRight    = 0x27;
public const int VkDown     = 0x28;
public const int VkInsert   = 0x2D;
public const int VkDelete   = 0x2E;
public const int VkF1       = 0x70;
public const int VkF2       = 0x71;
public const int VkF3       = 0x72;
public const int VkF4       = 0x73;
public const int VkF5       = 0x74;
public const int VkF6       = 0x75;
public const int VkF7       = 0x76;
public const int VkF8       = 0x77;
public const int VkF9       = 0x78;
public const int VkF10      = 0x79;
public const int VkF11      = 0x7A;
public const int VkF12      = 0x7B;
public const int VkLeftShift    = 0xA0;
public const int VkRightShift   = 0xA1;
public const int VkLeftControl  = 0xA2;
public const int VkRightControl = 0xA3;

// ================================================================ clipboard

public extern "C" {
    int    OpenClipboard(HWND owner);
    int    CloseClipboard();
    int    EmptyClipboard();
    HANDLE GetClipboardData(uint format);
    HANDLE SetClipboardData(uint format, HANDLE handle);
    int    IsClipboardFormatAvailable(uint format);
}

public const uint ClipboardText        = 1u;
public const uint ClipboardBitmap      = 2u;
public const uint ClipboardUnicodeText = 13u;
public const uint ClipboardHDrop       = 15u;

// =================================================================== timers

public extern "C" {
    ulong SetTimer(HWND window, ulong id, uint milliseconds, TimerProcedure callback);
    int   KillTimer(HWND window, ulong id);
}

// ================================================================== metrics

public extern "C" {
    int   GetSystemMetrics(int index);
    int   SystemParametersInfoW(uint action, uint parameter, void* value, uint winIni);
    HICON LoadIconW(HINSTANCE instance, char16* name);
    int   SetProcessDPIAware();
    uint  GetDpiForWindow(HWND window);
}

public const int SmScreenWidth            = 0;
public const int SmScreenHeight           = 1;
public const int SmVerticalScrollWidth    = 2;
public const int SmHorizontalScrollHeight = 3;
public const int SmCaptionHeight          = 4;
public const int SmBorderWidth            = 5;
public const int SmBorderHeight           = 6;
public const int SmIconWidth              = 11;
public const int SmIconHeight             = 12;
/// `SM_CXSMICON`/`SM_CYSMICON`: the small icon, which is what goes in a title
/// bar and in a list view's small-icon view. Not half the large one -- the
/// theme decides, and on a scaled display it is neither 16 nor 32.
public const int SmSmallIconWidth         = 49;
public const int SmSmallIconHeight        = 50;
public const int SmCursorWidth            = 13;
public const int SmCursorHeight           = 14;
public const int SmMenuHeight             = 15;
public const int SmMouseButtons           = 43;
public const int SmVirtualScreenX         = 76;
public const int SmVirtualScreenY         = 77;
public const int SmVirtualScreenWidth     = 78;
public const int SmVirtualScreenHeight    = 79;
public const int SmMonitorCount           = 80;
public const int SmRemoteSession          = 0x1000;

/// The standard icons, passed to `LoadIconW` with a null instance. Also
/// `MAKEINTRESOURCE` integers, and so also functions.
public char16* IconApplication() { return (char16*)(nuint)32512u; }
public char16* IconError()       { return (char16*)(nuint)32513u; }
public char16* IconQuestion()    { return (char16*)(nuint)32514u; }
public char16* IconWarning()     { return (char16*)(nuint)32515u; }
public char16* IconInformation() { return (char16*)(nuint)32516u; }

// ============================================ window properties and subclassing
//
// What a widget layer needs beyond the raw window calls above: somewhere to
// keep a pointer beside an `HWND`, and a way to put a window procedure in front
// of a system control's own.

public extern "C" {
    /// Attaches a value to a window under a name. The way to associate data
    /// with an `HWND` that works on a window this program did not create --
    /// unlike `GWLP_USERDATA`, which a system control may already be using for
    /// its own purposes and which there is exactly one of.
    int   SetPropW(HWND window, char16* name, void* value);
    void* GetPropW(HWND window, char16* name);
    void* RemovePropW(HWND window, char16* name);

    /// Calls a window procedure directly. What a subclassed control calls to
    /// reach the procedure it replaced, in place of `DefWindowProcW`.
    long  CallWindowProcW(WindowProcedure previous, HWND window, uint message,
                          ulong wParam, long lParam);

    int   EnableWindow(HWND window, int enable);
    int   IsWindowEnabled(HWND window);

    /// The theme's colour for one role, as a COLORREF. Read each time rather
    /// than cached, so a theme change between two calls is seen.
    uint  GetSysColor(int index);
    /// The same colour as a brush the system owns -- not to be deleted.
    HBRUSH GetSysColorBrush(int index);

    /// Translates points from one window's coordinates to another's. Either
    /// may be null, meaning the screen.
    int   MapWindowPoints(HWND from, HWND to, Point* points, uint count);

    int   GetDlgCtrlID(HWND window);
    HWND  GetDlgItem(HWND window, int id);
    HWND  GetWindow(HWND window, uint relationship);
    int   GetScrollInfo(HWND window, int bar, ScrollInfo* info);
    int   SetScrollInfo(HWND window, int bar, ScrollInfo* info, int redraw);
    int   GetClassNameW(HWND window, char16* buffer, int size);
}

/// `GetWindow` relationships.
public const uint GwHwndFirst = 0u;
public const uint GwHwndLast  = 1u;
public const uint GwHwndNext  = 2u;
public const uint GwHwndPrev  = 3u;
public const uint GwOwner     = 4u;
public const uint GwChild     = 5u;

/// The system colour indices `GetSysColor` takes.
public const int ColorScrollBar      = 0;
public const int ColorBackground     = 1;
public const int ColorActiveCaption  = 2;
public const int ColorMenu           = 4;
public const int ColorWindow         = 5;
public const int ColorWindowFrame    = 6;
public const int ColorMenuText       = 7;
public const int ColorWindowText     = 8;
public const int ColorCaptionText    = 9;
public const int ColorActiveBorder   = 10;
public const int ColorAppWorkspace   = 12;
public const int ColorHighlight      = 13;
public const int ColorHighlightText  = 14;
public const int ColorBtnFace        = 15;
public const int ColorBtnShadow      = 16;
public const int ColorGrayText       = 17;
public const int ColorBtnText        = 18;
public const int ColorBtnHighlight   = 20;
public const int Color3DDarkShadow   = 21;
public const int Color3DLight        = 22;
public const int ColorInfoText       = 23;
public const int ColorInfoBackground = 24;
public const int ColorHotLight       = 26;

/// `SCROLLINFO`, for a scroll bar's range and position in one call.
public struct ScrollInfo {
    public uint Size;
    public uint Mask;
    public int  Minimum;
    public int  Maximum;
    public uint Page;
    public int  Position;
    public int  TrackPosition;
}

public const uint SifRange           = 0x0001u;
public const uint SifPage            = 0x0002u;
public const uint SifPosition        = 0x0004u;
public const uint SifDisableNoScroll = 0x0008u;
public const uint SifTrackPosition   = 0x0010u;
public const uint SifAll             = 0x0017u;

public const int ScrollBarHorizontal = 0;
public const int ScrollBarVertical   = 1;
public const int ScrollBarControl    = 2;

// ================================================= messages the controls speak
//
// A system control is driven by sending it messages rather than by calling
// functions, so these constants are its API. Grouped by which control answers
// them, because `BM_GETCHECK` and `CB_GETCOUNT` share a numeric range and only
// the recipient tells them apart.

/// Messages every control answers.
public const uint WmSetFont            = 0x0030u;
public const uint WmGetFont            = 0x0031u;
public const uint WmNotify             = 0x004Eu;
public const uint WmContextMenu        = 0x007Bu;
public const uint WmCtlColorEdit       = 0x0133u;
public const uint WmCtlColorListBox    = 0x0134u;
public const uint WmCtlColorButton     = 0x0135u;
public const uint WmCtlColorStatic     = 0x0138u;
public const uint WmHorizontalScroll   = 0x0114u;
public const uint WmVerticalScroll     = 0x0115u;
public const uint WmMouseLeave         = 0x02A3u;
public const uint WmSetRedraw          = 0x000Bu;
public const uint WmGetFontHeight      = 0x0000u;

/// The notification codes a control sends back in the high word of `WPARAM`
/// with `WM_COMMAND`.
public const uint BnClicked          = 0u;
public const uint BnDoubleClicked    = 5u;
public const uint EnChange           = 0x0300u;
public const uint EnUpdate           = 0x0400u;
public const uint EnSetFocus         = 0x0100u;
public const uint EnKillFocus        = 0x0200u;
public const uint LbnSelChange       = 1u;
public const uint LbnDoubleClick     = 2u;
public const uint CbnSelChange       = 1u;
public const uint CbnEditChange      = 5u;
public const uint CbnDropDown        = 7u;

/// Button messages.
public const uint BmGetCheck = 0x00F0u;
public const uint BmSetCheck = 0x00F1u;
public const uint BmSetStyle = 0x00F4u;
public const uint BstUnchecked = 0u;
public const uint BstChecked   = 1u;

/// Button styles, which decide whether a `BUTTON` is a push button, a check
/// box, a radio button or a group box -- all four are the same window class.
public const uint BsPushButton      = 0x0000u;
public const uint BsDefPushButton   = 0x0001u;
public const uint BsCheckBox        = 0x0002u;
public const uint BsAutoCheckBox    = 0x0003u;
public const uint BsRadioButton     = 0x0004u;
public const uint Bs3State          = 0x0005u;
public const uint BsAutoRadioButton = 0x0009u;
public const uint BsGroupBox        = 0x0007u;
public const uint BsOwnerDraw       = 0x000Bu;
public const uint BsLeftText        = 0x0020u;
public const uint BsMultiline       = 0x2000u;

/// Edit messages and styles.
public const uint EmGetSel       = 0x00B0u;
public const uint EmSetSel       = 0x00B1u;
public const uint EmGetLineCount = 0x00BAu;
public const uint EmLineIndex    = 0x00BBu;
public const uint EmLineLength   = 0x00C1u;
public const uint EmReplaceSel   = 0x00C2u;
public const uint EmGetLine      = 0x00C4u;
public const uint EmSetReadOnly  = 0x00CFu;
public const uint EmSetLimitText = 0x00C5u;
public const uint EmSetPasswordChar = 0x00CCu;
public const uint EmScrollCaret  = 0x00B7u;

public const uint EsLeft        = 0x0000u;
public const uint EsCenter      = 0x0001u;
public const uint EsRight       = 0x0002u;
public const uint EsMultiline   = 0x0004u;
public const uint EsUpperCase   = 0x0008u;
public const uint EsLowerCase   = 0x0010u;
public const uint EsPassword    = 0x0020u;
public const uint EsAutoVScroll = 0x0040u;
public const uint EsAutoHScroll = 0x0080u;
public const uint EsNoHideSel   = 0x0100u;
public const uint EsReadOnly    = 0x0800u;
public const uint EsWantReturn  = 0x1000u;

/// List box messages and styles.
public const uint LbAddString     = 0x0180u;
public const uint LbInsertString  = 0x0181u;
public const uint LbDeleteString  = 0x0182u;
public const uint LbResetContent  = 0x0184u;
public const uint LbSetSel        = 0x0185u;
public const uint LbSetCurSel     = 0x0186u;
public const uint LbGetCurSel     = 0x0188u;
public const uint LbGetText       = 0x0189u;
public const uint LbGetTextLen    = 0x018Au;
public const uint LbGetCount      = 0x018Bu;

public const uint LbsNotify         = 0x0001u;
public const uint LbsSort           = 0x0002u;
public const uint LbsMultipleSel    = 0x0008u;
public const uint LbsHasStrings     = 0x0040u;
public const uint LbsDisableNoScroll = 0x1000u;

/// Combo box messages and styles.
public const uint CbGetEditSel    = 0x0140u;
public const uint CbSetEditSel    = 0x0142u;
public const uint CbAddString     = 0x0143u;
public const uint CbDeleteString  = 0x0144u;
public const uint CbGetCount      = 0x0146u;
public const uint CbGetCurSel     = 0x0147u;
public const uint CbGetLbText     = 0x0148u;
public const uint CbGetLbTextLen  = 0x0149u;
public const uint CbInsertString  = 0x014Au;
public const uint CbResetContent  = 0x014Bu;
public const uint CbSetCurSel     = 0x014Eu;

public const uint CbsSimple         = 0x0001u;
public const uint CbsDropDown       = 0x0002u;
public const uint CbsDropDownList   = 0x0003u;
public const uint CbsAutoHScroll    = 0x0040u;
public const uint CbsSort           = 0x0100u;
public const uint CbsHasStrings     = 0x0200u;

/// Static (label) styles.
public const uint SsLeft        = 0x0000u;
public const uint SsCenter      = 0x0001u;
public const uint SsRight       = 0x0002u;
public const uint SsLeftNoWordWrap = 0x000Cu;
public const uint SsNoPrefix    = 0x0080u;
public const uint SsNotify      = 0x0100u;
public const uint SsSunken      = 0x1000u;

/// Scroll bar styles.
public const uint SbsHorizontal = 0x0000u;
public const uint SbsVertical   = 0x0001u;

/// The scroll bar notification codes that arrive in `WM_VSCROLL`'s low word.
public const uint SbLineUp        = 0u;
public const uint SbLineDown      = 1u;
public const uint SbPageUp        = 2u;
public const uint SbPageDown      = 3u;
public const uint SbThumbPosition = 4u;
public const uint SbThumbTrack    = 5u;
public const uint SbTop           = 6u;
public const uint SbBottom        = 7u;
public const uint SbEndScroll     = 8u;

// ======================================================= tracking the mouse
//
// Win32 reports a mouse entering a window only by the moves it sends, and
// reports it leaving not at all -- unless asked, once, per window, per leave.

public struct TrackMouseEvent {
    public uint Size;
    public uint Flags;
    public HWND Window;
    public uint HoverTime;
}

public const uint TmeLeave  = 0x00000002u;
public const uint TmeHover  = 0x00000001u;
public const uint TmeCancel = 0x80000000u;

public extern "C" {
    int TrackMouseEvent(TrackMouseEvent* track);
}

// No helper here that *calls* one of these, deliberately: this layer is
// declarations, and a declaration nothing calls needs no library. A function
// with a body would emit a reference and make `bindings/win32/api` need
// `-l user32` to link, which is exactly what `tests/cases/win32-raw` exists to
// prevent. The convenience belongs where the other conveniences are.

// ======================================================================= menus
//
// A menu is not a window. It is a handle with items in it, identified by a
// command id that comes back through the parent's `WM_COMMAND` -- the same
// message a button's click arrives on, which is why the two have to share a
// numbering.

public struct MenuItemInfo {
    public uint    Size;
    public uint    Mask;
    public uint    Type;
    public uint    State;
    public uint    Id;
    public HMENU   SubMenu;
    public HBITMAP Checked;
    public HBITMAP Unchecked;
    public nuint   ItemData;
    public char16* TypeData;
    public uint    TypeDataLength;
    public HBITMAP Item;
}

public extern "C" {
    HMENU CreateMenu();
    HMENU CreatePopupMenu();
    int   DestroyMenu(HMENU menu);
    int   SetMenu(HWND window, HMENU menu);
    HMENU GetMenu(HWND window);
    int   DrawMenuBar(HWND window);

    int   AppendMenuW(HMENU menu, uint flags, nuint item, char16* text);
    int   InsertMenuItemW(HMENU menu, uint item, int byPosition, MenuItemInfo* info);
    int   SetMenuItemInfoW(HMENU menu, uint item, int byPosition, MenuItemInfo* info);
    int   GetMenuItemInfoW(HMENU menu, uint item, int byPosition, MenuItemInfo* info);
    int   DeleteMenu(HMENU menu, uint item, uint flags);
    int   GetMenuItemCount(HMENU menu);

    int   EnableMenuItem(HMENU menu, uint item, uint enable);
    int   CheckMenuItem(HMENU menu, uint item, uint check);
    int   CheckMenuRadioItem(HMENU menu, uint first, uint last, uint check, uint flags);

    /// Shows a popup and does not return until the user has chosen or
    /// dismissed it. With `TPM_RETURNCMD` it answers the command id rather
    /// than posting `WM_COMMAND`, which is the form that needs no id routing.
    int   TrackPopupMenu(HMENU menu, uint flags, int x, int y, int reserved,
                         HWND owner, Rect* area);
}

/// `AppendMenuW` flags.
public const uint MfString     = 0x00000000u;
public const uint MfBitmap     = 0x00000004u;
public const uint MfOwnerDraw  = 0x00000100u;
public const uint MfPopup      = 0x00000010u;
public const uint MfSeparator  = 0x00000800u;
public const uint MfEnabled    = 0x00000000u;
public const uint MfGrayed     = 0x00000001u;
public const uint MfDisabled   = 0x00000002u;
public const uint MfUnchecked  = 0x00000000u;
public const uint MfChecked    = 0x00000008u;
public const uint MfByCommand  = 0x00000000u;
public const uint MfByPosition = 0x00000400u;

/// `MENUITEMINFO` masks.
public const uint MiimState      = 0x00000001u;
public const uint MiimId         = 0x00000002u;
public const uint MiimSubMenu    = 0x00000004u;
public const uint MiimCheckMarks = 0x00000008u;
public const uint MiimType       = 0x00000010u;
public const uint MiimData       = 0x00000020u;
public const uint MiimString     = 0x00000040u;
public const uint MiimBitmap     = 0x00000080u;
public const uint MiimFType      = 0x00000100u;

public const uint MfsEnabled  = 0x00000000u;
public const uint MfsGrayed   = 0x00000003u;
public const uint MfsChecked  = 0x00000008u;
public const uint MfsDefault  = 0x00001000u;

public const uint MftString    = 0x00000000u;
public const uint MftSeparator = 0x00000800u;
public const uint MftRadioCheck = 0x00000200u;

/// `TrackPopupMenu` flags.
public const uint TpmLeftAlign  = 0x0000u;
public const uint TpmCenterAlign = 0x0004u;
public const uint TpmRightAlign = 0x0008u;
public const uint TpmTopAlign   = 0x0000u;
public const uint TpmLeftButton = 0x0000u;
public const uint TpmRightButton = 0x0002u;
public const uint TpmReturnCmd  = 0x0100u;
public const uint TpmNonNotify  = 0x0080u;

/// Sent to the owner before a menu drops down, which is when a program that
/// enables items according to what is selected wants to be asked.
public const uint WmInitMenuPopup = 0x0117u;
public const uint WmMenuSelect    = 0x011Fu;

// ============================================== images, from a file or a resource
//
// Enough to put a picture on a button or in a tree. `LoadImageW` reads a `.bmp`
// and nothing else, which is the format Windows has always been able to read
// without a decoder -- either from disk with `LrLoadFromFile`, or out of the
// binary's own resources with an `HINSTANCE` and a `MAKEINTRESOURCE` name.

public extern "C" {
    HANDLE LoadImageW(HINSTANCE instance, char16* name, uint kind,
                      int width, int height, uint flags);
    HICON  CreateIconFromResourceEx(byte* bits, uint size, int isIcon, uint version,
                                    int width, int height, uint flags);
    int    DestroyIcon(HICON icon);
}

public const uint ImageBitmap = 0u;
public const uint ImageIcon   = 1u;
public const uint ImageCursor = 2u;

public const uint LrDefaultColor  = 0x0000u;
public const uint LrLoadFromFile  = 0x0010u;
public const uint LrDefaultSize   = 0x0040u;
public const uint LrCreateDibSection = 0x2000u;
public const uint LrShared        = 0x8000u;

// ========================================================= resource types
//
// The `RT_` values from `winuser.h`: what a resource *is*, which together with
// its name is how one is found. They are `MAKEINTRESOURCE` integers rather
// than strings -- the same trick `IconApplication` and `CursorArrow` above
// play -- so they are functions here, because Stainless has no `const char16*`.
//
// A type not in this list is a custom one, named by an ordinary wide string.
// `RT_RCDATA` is the type to use for arbitrary bytes rather than inventing one,
// because every resource editor already knows how to show it.

public char16* RtCursor()       { return (char16*)(nuint)1u; }
public char16* RtBitmap()       { return (char16*)(nuint)2u; }
public char16* RtIcon()         { return (char16*)(nuint)3u; }
public char16* RtMenu()         { return (char16*)(nuint)4u; }
public char16* RtDialog()       { return (char16*)(nuint)5u; }
public char16* RtString()       { return (char16*)(nuint)6u; }
public char16* RtFontDir()      { return (char16*)(nuint)7u; }
public char16* RtFont()         { return (char16*)(nuint)8u; }
public char16* RtAccelerator()  { return (char16*)(nuint)9u; }
public char16* RtRcData()       { return (char16*)(nuint)10u; }
public char16* RtMessageTable() { return (char16*)(nuint)11u; }
public char16* RtGroupCursor()  { return (char16*)(nuint)12u; }
public char16* RtGroupIcon()    { return (char16*)(nuint)14u; }
public char16* RtVersion()      { return (char16*)(nuint)16u; }
public char16* RtDlgInclude()   { return (char16*)(nuint)17u; }
public char16* RtPlugPlay()     { return (char16*)(nuint)19u; }
public char16* RtVxd()          { return (char16*)(nuint)20u; }
public char16* RtAniCursor()    { return (char16*)(nuint)21u; }
public char16* RtAniIcon()      { return (char16*)(nuint)22u; }
public char16* RtHtml()         { return (char16*)(nuint)23u; }
public char16* RtManifest()     { return (char16*)(nuint)24u; }

/// `WM_SETICON`: gives a window its icon. `wParam` says which of the two
/// sizes, and `lParam` is the `HICON`.
///
/// Both want setting. The large one is what the task switcher shows and the
/// small one is what the title bar draws, and a window given only the large
/// one gets a downscaled blur in its corner.
public const uint WmSetIcon = 0x0080u;
public const ulong IconSmallSize = 0u;
public const ulong IconBigSize   = 1u;

/// The name Windows expects an executable's manifest to be filed under.
/// `CREATEPROCESS_MANIFEST_RESOURCE_ID`: it is the loader that reads this one,
/// before any code in the program runs, so nothing here ever asks for it.
public const int ManifestResourceId = 1;

// ================================== menus, dialogs and accelerators from a resource
//
// The three resource types that are not data but *description*. A dialog
// template is a compiled layout that `CreateDialogParamW` turns into a window
// full of controls; a menu template is a tree of items; an accelerator table
// maps a key to a command id. Nothing outside Windows has an equivalent --
// these are a declarative UI format that the OS itself knows how to read,
// rather than embedded files a program interprets for itself.
//
// The `name` arguments are resource names, so an integer id has to go through
// `MAKEINTRESOURCE`. `Win32.Resources` is the comfortable way to say that.

public extern "C" {
    /// Builds a menu from an `RT_MENU` template. The caller owns it until it
    /// is attached to a window, which is what `SetMenu` above does.
    HMENU LoadMenuW(HINSTANCE instance, char16* name);

    /// The same from a template already in memory, which is what a program
    /// that built one itself has.
    HMENU LoadMenuIndirectW(void* template);

    /// Reads an `RT_ACCELERATOR` table. The handle is shared and is not
    /// destroyed, which is why there is no matching free here.
    HACCEL LoadAcceleratorsW(HINSTANCE instance, char16* name);

    /// Turns a key message into a `WM_COMMAND` for the window, and answers
    /// non-zero when it did -- in which case the loop must *not* dispatch the
    /// message, exactly as with `IsDialogMessageW`.
    int    TranslateAcceleratorW(HWND window, HACCEL table, Msg* message);

    /// A modeless dialog from an `RT_DIALOG` template: it is returned, and the
    /// program's own message loop drives it.
    HWND   CreateDialogParamW(HINSTANCE instance, char16* name, HWND parent,
                              DialogProcedure procedure, long parameter);

    /// A modal one. This does not return until the dialog ends itself with
    /// `EndDialog`, because it runs a message loop of its own.
    nint   DialogBoxParamW(HINSTANCE instance, char16* name, HWND parent,
                           DialogProcedure procedure, long parameter);

    /// Ends a modal dialog, and decides what `DialogBoxParamW` answers.
    int    EndDialog(HWND dialog, nint result);

    /// Reads and writes a dialog control's text by id rather than by `HWND`,
    /// which is how a template's controls are usually reached -- the template
    /// named them, so nothing here has to hold a handle. `GetDlgItem` under
    /// windows above is the one that hands back the `HWND` itself.
    uint   GetDlgItemTextW(HWND dialog, int id, char16* buffer, int size);
    int    SetDlgItemTextW(HWND dialog, int id, char16* text);
}

/// What a dialog procedure is. It answers true when it handled the message,
/// which is the opposite convention to a window procedure -- a window
/// procedure passes on what it did not want, and a dialog procedure says so.
public delegate nint DialogProcedure(HWND dialog, uint message, ulong wParam, long lParam);

/// Sent to a dialog procedure once, before it is shown, with `wParam` holding
/// the control that would get the keyboard. Answering true takes the default.
public const uint WmInitDialog = 0x0110u;

// ==================================================== strings from a resource

public extern "C" {
    /// Copies a string out of an `RT_STRING` table, and answers how many
    /// characters it wrote -- zero when there is no string with that id.
    ///
    /// A string table is stored in blocks of sixteen, which is why an id is a
    /// plain integer here rather than a resource name: `LoadStringW` works out
    /// which block to read and where in it to look.
    ///
    /// Passing a zero `size` makes it write a pointer to the string's own
    /// characters into `buffer` instead of copying, and answer the length.
    /// Those characters are not null-terminated, being a slice of the block.
    int LoadStringW(HINSTANCE instance, uint id, char16* buffer, int size);
}

// ================================================== keyboard navigation
//
// Tab, the arrow keys between radio buttons, Enter for the default button and
// Escape for cancel are not built into a window: they are what
// `IsDialogMessage` does to a message before it is dispatched, and a window
// whose loop does not call it simply has none of them.

public extern "C" {
    /// Handles a navigation key for a window and its children. Answers true
    /// when it took the message, which the loop must then *not* dispatch.
    int  IsDialogMessageW(HWND window, Msg* message);
    HWND GetNextDlgTabItem(HWND window, HWND from, int previous);
    HWND GetNextDlgGroupItem(HWND window, HWND from, int previous);
    /// Which control a dialog would give the keyboard to first.
    int  MapDialogRect(HWND window, Rect* rectangle);

    /// Walks up an ownership chain: the top-level window a control is on.
    HWND GetAncestor(HWND window, uint what);
}

public const uint GaParent    = 1u;
public const uint GaRoot      = 2u;
public const uint GaRootOwner = 3u;

/// The range of messages that carry a key. `IsDialogMessage` is only worth
/// asking about these, and asking about the rest costs a call per mouse move.
public const uint WmKeyFirst = 0x0100u;
public const uint WmKeyLast  = 0x0109u;

#endif
