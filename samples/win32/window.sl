// SPDX-License-Identifier: 0BSD
//
// A real Win32 window: a class, a window procedure, a message loop, and
// double-buffered GDI painting.
//
//   stainless run samples/win32/window.sl \
//       bindings/win32/api/Kernel32.sl bindings/win32/api/User32.sl \
//       bindings/win32/api/Gdi32.sl bindings/win32/Win32.sl \
//       bindings/win32/Ui.sl bindings/win32/Drawing.sl -l user32 -l gdi32
//
// Naming the modules it uses rather than the whole `bindings/win32` directory,
// because compiling a binding is what makes its library necessary: the
// directory would want '-l advapi32 -l shell32 -l comdlg32' as well.
//
// `Win32.User32` and `Win32.Gdi32` are the declarations, spelled as Windows
// spells them. `Win32.Ui` and `Win32.Drawing` are the conveniences on top: the
// message loop, the client rectangle, the off-screen buffer.
//
// The window procedure is in neither, because there is nothing to wrap. It is
// an ordinary module-level function that Windows calls directly, since a
// Stainless `delegate` is a C function pointer and nothing more — no thunk, no
// marshalling and no registration step.
//
// A delegate captures nothing, so per-window state lives where Win32 has always
// kept it: a block whose address is stored in the window with
// `SetWindowLongPtrW(GwlpUserData)`. That is the pattern this sample is really
// about.
module Window;

import Standard.Console;
import Win32;
import Win32.User32;
import Win32.Ui;
import Win32.Gdi32;
import Win32.Drawing;
import Win32.Handles;
import Win32.Kernel32;

extern "C" {
    void* malloc(nuint size);
    void  free(void* block);
}

/// Everything this window remembers between messages.
public struct State {
    public int  Clicks;
    public int  CursorX;
    public int  CursorY;
    public bool Tracking;
}

// ------------------------------------------------------------ the procedure

long Procedure(HWND window, uint message, ulong wParam, long lParam) {
    State* state = (State*)(nuint)GetWindowLongPtrW(window, GwlpUserData);

    if (message == WmDestroy) {
        PostQuitMessage(0);
        return 0;
    }

    if (message == WmPaint) {
        Paint(window, state);
        return 0;
    }

    // The background is painted as part of WM_PAINT, into the off-screen
    // buffer. Saying so here is what stops Windows erasing it first and
    // flickering once per frame.
    if (message == WmEraseBackground) { return 1; }

    if (message == WmMouseMove && state != null) {
        // Both coordinates are packed into one LPARAM, low word first, and both
        // are signed: a drag can leave the window to the left.
        Point at = PointOf(lParam);
        (*state).CursorX = at.X;
        (*state).CursorY = at.Y;
        (*state).Tracking = true;
        Invalidate(window, false);
        return 0;
    }

    if (message == WmLeftButtonDown && state != null) {
        (*state).Clicks = (*state).Clicks + 1;
        Invalidate(window, false);
        return 0;
    }

    if (message == WmKeyDown) {
        if ((int)wParam == VkEscape) { DestroyWindow(window); }
        return 0;
    }

    return DefWindowProcW(window, message, wParam, lParam);
}

// --------------------------------------------------------------- the drawing

void Paint(HWND window, State* state) {
    PaintStruct paint;
    HDC dc = BeginPaint(window, &paint);

    Rect client = ClientRect(window);

    // Everything is drawn into an off-screen bitmap and copied over in one go,
    // so the window never shows a half-finished frame.
    var buffer = CreateOffScreen(dc, Width(client), Height(client));

    Fill(buffer.Dc, &client, Colour(24u, 26u, 32u));

    DrawCrosshair(buffer.Dc, client, state);
    DrawLabels(buffer.Dc, state);

    BitBlt(dc, 0, 0, Width(client), Height(client), buffer.Dc, 0, 0, SrcCopy);
    DestroyOffScreen(buffer);

    EndPaint(window, &paint);
}

void DrawCrosshair(HDC dc, Rect client, State* state) {
    if (state == null || !(*state).Tracking) { return; }

    HPEN pen = CreatePen(PenSolid, 1, Colour(60u, 70u, 90u));
    HGDIOBJ previousPen = SelectObject(dc, pen);

    MoveToEx(dc, 0, (*state).CursorY, null);
    LineTo(dc, Width(client), (*state).CursorY);
    MoveToEx(dc, (*state).CursorX, 0, null);
    LineTo(dc, (*state).CursorX, Height(client));

    SelectObject(dc, previousPen);
    DeleteObject(pen);

    // A circle that grows with the click count, so a click is visible.
    int radius = 12 + (*state).Clicks * 3;
    HBRUSH brush = CreateSolidBrush(Colour(90u, 160u, 240u));
    HGDIOBJ previousBrush = SelectObject(dc, brush);

    Ellipse(dc, (*state).CursorX - radius, (*state).CursorY - radius,
                (*state).CursorX + radius, (*state).CursorY + radius);

    SelectObject(dc, previousBrush);
    DeleteObject(brush);
}

void DrawLabels(HDC dc, State* state) {
    HFONT font = CreateFont("Segoe UI", 18, FontNormal, false);
    HGDIOBJ previousFont = SelectObject(dc, font);

    SetBkMode(dc, TransparentBackground);
    SetTextColor(dc, Colour(220u, 224u, 232u));

    DrawTextAt(dc, 16, 14, "Move the mouse. Click. Escape closes.");

    if (state != null) {
        DrawTextAt(dc, 16, 40,
            "clicks: " + Text.FromInteger((long)(*state).Clicks)
            + "    at " + Text.FromInteger((long)(*state).CursorX)
            + ", " + Text.FromInteger((long)(*state).CursorY));
    }

    SelectObject(dc, previousFont);
    DeleteObject(font);
}

// ------------------------------------------------------------------- startup

int Main() {
    HMODULE instance = GetModuleHandleW(null);

    var windowClass = NewWindowClass();
    windowClass.Style = ClassStyleHorizontalRedraw | ClassStyleVerticalRedraw;
    windowClass.Procedure = Procedure;
    windowClass.Instance = instance;
    windowClass.Cursor = LoadCursorW(null, CursorArrow());
    windowClass.ClassName = "StainlessWindow".ToUtf16().ToPointer();

    if (RegisterClassExW(&windowClass) == 0u) {
        Console.WriteError("could not register the class: " + Win32.LastErrorMessage());
        return 1;
    }

    // Ask for a client area of exactly 640x400 by growing it into the window
    // size that would contain it. Otherwise the frame eats into the drawing.
    Rect wanted = Rectangle(0, 0, 640, 400);
    Rect outer = AdjustForFrame(wanted, WsOverlappedWindow, 0u);

    HWND window = CreateWindow("StainlessWindow", "Stainless on Win32",
                                WsOverlappedWindow, UseDefault, UseDefault,
                                Width(outer), Height(outer), instance);
    if (window == null) {
        Console.WriteError("could not create the window: " + Win32.LastErrorMessage());
        return 1;
    }

    State* state = (State*)malloc(sizeof(State));
    (*state).Clicks = 0;
    (*state).CursorX = 0;
    (*state).CursorY = 0;
    (*state).Tracking = false;
    SetWindowLongPtrW(window, GwlpUserData, (long)(nuint)state);

    ShowWindow(window, SwShowNormal);
    UpdateWindow(window);

    int code = RunMessageLoop();
    free((void*)state);
    return code;
}
