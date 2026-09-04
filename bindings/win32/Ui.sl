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

// Windows, messages, input and the clipboard.
//
// A convenience layer over `Win32.User32`, which is where the declarations are.
// It names user32 itself with a pragma, so a program compiling it needs no
// `-l`.
//
// The window procedure stays in the raw layer, because there is nothing to
// wrap: `WNDPROC` is a plain C function pointer, which is exactly what a
// Stainless `delegate` is, so a window procedure is an ordinary module-level
// function that Windows calls directly.
module Win32.Ui;

#if WINDOWS

// The library this module needs, so that a program compiling it does not
// have to repeat the name on its own command line.
#pragma comment(lib, "user32")

import Win32;
import Win32.User32;
import Win32.Kernel32;
import Win32.Handles;

// ================================================================= geometry

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

public Point At(int x, int y) {
    Point point;
    point.X = x;
    point.Y = y;
    return point;
}

// ============================================================= message loop

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

/// The low and high words of an `LPARAM` that carries a point, both signed —
/// a drag can leave the window to the left, and an unsigned read would make
/// that a very large positive number.
public Point PointOf(long lParam) {
    return At((int)(short)(lParam & 0xFFFF), (int)(short)((lParam >> 16) & 0xFFFF));
}

// ============================================================ window classes

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

/// Creates an ordinary top-level window. The declaration is right there when a
/// caller needs an extended style, a parent or a menu.
public HWND CreateWindow(String className, String title, uint style,
                          int x, int y, int width, int height, HINSTANCE instance) {
    return CreateWindowExW(0u, className.ToUtf16().ToPointer(), title.ToUtf16().ToPointer(),
                           style, x, y, width, height, null, null, instance, null);
}

/// The window's title, or a control's text.
public String WindowText(HWND window) {
    int length = GetWindowTextLengthW(window);
    if (length <= 0) { return ""; }

    var buffer = new WideBuffer((uint)length);
    int units = GetWindowTextW(window, buffer.Pointer(), length + 1);
    if (units <= 0) { return ""; }
    return buffer.Text((uint)units);
}

public bool SetWindowText(HWND window, String text) {
    return Win32.Succeeded(SetWindowTextW(window, text.ToUtf16().ToPointer()));
}

/// The client area, whose left and top are always zero — it is a size wearing
/// the shape of a rectangle.
public Rect ClientRect(HWND window) {
    Rect rectangle;
    GetClientRect(window, &rectangle);
    return rectangle;
}

/// The window's outer rectangle in screen coordinates, frame included.
public Rect WindowRect(HWND window) {
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
public bool Invalidate(HWND window, bool erase) {
    return Win32.Succeeded(InvalidateRect(window, null, erase ? 1 : 0));
}

/// Draws text into a rectangle. `-1` for the length means "up to the NUL",
/// which is what a Stainless string widened for the call always has.
public int DrawText(HDC dc, String text, Rect* rectangle, uint format) {
    return DrawTextW(dc, text.ToUtf16().ToPointer(), -1, rectangle, format);
}

// ============================================================== message box

/// Shows a message box and returns the `Id...` of the button pressed.
public int MessageBox(HWND owner, String text, String caption, uint style) {
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

// ==================================================================== input

/// Where the mouse is, in screen coordinates.
public Point CursorPosition() {
    Point point;
    GetCursorPos(&point);
    return point;
}

/// True while the key is physically down, asked of the hardware rather than of
/// the message queue. The high bit is the one that means "down".
public bool KeyDown(int key) {
    return (GetAsyncKeyState(key) & 0x8000) != 0;
}

/// True when a toggle key — Caps Lock, Num Lock — is currently on.
public bool KeyToggled(int key) {
    return (GetKeyState(key) & 0x0001) != 0;
}

// ================================================================ clipboard

/// True when the clipboard currently holds Unicode text.
public bool IsClipboardAvailable() {
    return Win32.Succeeded(IsClipboardFormatAvailable(ClipboardUnicodeText));
}

/// What is on the clipboard as text, or an empty string when there is none.
public String ClipboardString() {
    if (!IsClipboardAvailable()) { return ""; }
    if (!Win32.Succeeded(OpenClipboard(null))) { return ""; }

    HANDLE handle = GetClipboardData(ClipboardUnicodeText);
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

/// Puts text on the clipboard.
///
/// The clipboard takes ownership of the block, so it is deliberately not freed
/// here on the success path — freeing it would be the bug, not the leak.
public bool SetClipboardString(String text) {
    var wide = text.ToUtf16();
    nuint bytes = (wide.UnitCount() + 1u) * 2u;

    HGLOBAL block = GlobalAlloc(GlobalMoveable, bytes);
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

// ================================================================== metrics

/// The primary monitor's size in pixels.
public Size ScreenSize() {
    Size size;
    size.Width = GetSystemMetrics(SmScreenWidth);
    size.Height = GetSystemMetrics(SmScreenHeight);
    return size;
}

/// The whole virtual desktop, which is what a multi-monitor program wants.
public Rect VirtualScreen() {
    int x = GetSystemMetrics(SmVirtualScreenX);
    int y = GetSystemMetrics(SmVirtualScreenY);
    return Rectangle(x, y,
                     x + GetSystemMetrics(SmVirtualScreenWidth),
                     y + GetSystemMetrics(SmVirtualScreenHeight));
}

#endif
