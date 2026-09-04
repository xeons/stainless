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

// The Windows console: colours, the cursor, the screen buffer and raw input.
//
// This is kernel32, so it needs no `-l`.
//
// `Standard.Console` writes text and is what a program should use for that.
// This module is for the things that are not writing text: turning on ANSI
// escape handling, moving the cursor, reading a key without waiting for a line,
// and asking how wide the window is.
//
// It is called `Terminal` rather than `Console` on purpose. A module is reached
// by its last name segment, so a `Win32.Console` would shadow `Standard.Console`
// in every file that imported it — and a program doing console work is exactly
// the program that also wants to print.
module Win32.Terminal;

#if WINDOWS

import Win32;

// ================================================================== handles

public extern "C" {
    void* GetStdHandle(uint which);
    int   SetStdHandle(uint which, void* handle);
    int   GetConsoleMode(void* handle, uint* mode);
    int   SetConsoleMode(void* handle, uint mode);
    uint  GetConsoleOutputCP();
    int   SetConsoleOutputCP(uint codePage);
    int   SetConsoleCP(uint codePage);
    int   AllocConsole();
    int   FreeConsole();
    int   AttachConsole(uint processId);
    void* GetConsoleWindow();
}

/// `GetStdHandle`'s argument. They are negative numbers cast to `uint`, which
/// is how the header defines them.
public const uint StdInput  = 0xFFFFFFF6u;   // -10
public const uint StdOutput = 0xFFFFFFF5u;   // -11
public const uint StdError  = 0xFFFFFFF4u;   // -12

/// Input modes.
public const uint EnableProcessedInput   = 0x0001u;
public const uint EnableLineInput        = 0x0002u;
public const uint EnableEchoInput        = 0x0004u;
public const uint EnableWindowInput      = 0x0008u;
public const uint EnableMouseInput       = 0x0010u;
public const uint EnableInsertMode       = 0x0020u;
public const uint EnableQuickEditMode    = 0x0040u;
public const uint EnableVirtualTerminalInput = 0x0200u;

/// Output modes. `EnableVirtualTerminalProcessing` is the one that makes ANSI
/// escape sequences work, and it is off by default on a fresh console.
public const uint EnableProcessedOutput  = 0x0001u;
public const uint EnableWrapAtEol        = 0x0002u;
public const uint EnableVirtualTerminalProcessing = 0x0004u;
public const uint DisableNewlineAutoReturn = 0x0008u;

/// UTF-8, which is what a Stainless `String` already is.
public const uint CodePageUtf8 = 65001u;

public void* Output() { return GetStdHandle(StdOutput); }
public void* Input()  { return GetStdHandle(StdInput); }
public void* Error()  { return GetStdHandle(StdError); }

/// Turns on ANSI escape handling for the console's output, and answers whether
/// it took. It is off by default, and a program that writes colour codes
/// without asking for this prints them as text.
public bool EnableAnsi() {
    void* handle = Output();
    uint mode = 0u;
    if (!Win32.Succeeded(GetConsoleMode(handle, &mode))) { return false; }
    return Win32.Succeeded(
        SetConsoleMode(handle, mode | EnableVirtualTerminalProcessing));
}

/// Tells the console its output is UTF-8, which matters for a program that
/// writes bytes rather than going through `Standard.Console`.
public bool UseUtf8() {
    return Win32.Succeeded(SetConsoleOutputCP(CodePageUtf8))
        && Win32.Succeeded(SetConsoleCP(CodePageUtf8));
}

// =========================================================== screen buffer

/// `COORD`: two `short`s, and the reason the console cannot address a buffer
/// wider than 32767.
public struct Coord {
    public short X;
    public short Y;
}

/// `SMALL_RECT`, whose edges are *inclusive*, unlike a `RECT`.
public struct SmallRect {
    public short Left;
    public short Top;
    public short Right;
    public short Bottom;
}

/// `CONSOLE_SCREEN_BUFFER_INFO`. `sizeof` is 22.
public struct ScreenBufferInfo {
    public Coord     Size;
    public Coord     CursorPosition;
    public ushort    Attributes;
    public SmallRect Window;
    public Coord     MaximumWindowSize;
}

/// `CONSOLE_CURSOR_INFO`.
public struct CursorInfo {
    public uint Size;
    public int  Visible;
}

public extern "C" {
    int GetConsoleScreenBufferInfo(void* handle, ScreenBufferInfo* info);
    int SetConsoleCursorPosition(void* handle, Coord position);
    int SetConsoleTextAttribute(void* handle, ushort attributes);
    int SetConsoleTitleW(ushort* title);
    uint GetConsoleTitleW(ushort* buffer, uint size);
    int GetConsoleCursorInfo(void* handle, CursorInfo* info);
    int SetConsoleCursorInfo(void* handle, CursorInfo* info);
    int FillConsoleOutputCharacterW(void* handle, ushort character, uint length,
                                    Coord at, uint* written);
    int FillConsoleOutputAttribute(void* handle, ushort attributes, uint length,
                                   Coord at, uint* written);
    int WriteConsoleW(void* handle, ushort* text, uint units, uint* written, void* reserved);
    int ReadConsoleW(void* handle, ushort* buffer, uint units, uint* read, void* control);
    int SetConsoleScreenBufferSize(void* handle, Coord size);
    int SetConsoleWindowInfo(void* handle, int absolute, SmallRect* window);
}

/// Character attributes. Foreground and background are each three bits and an
/// intensity, so a colour is an `or` of up to four of these.
///
/// They are `uint` although the field is a `ushort`, because `|` on two narrow
/// integers widens — `ForegroundRed | ForegroundIntense` would be an `int` and
/// every use would need a cast back. `SetColour` narrows once, here.
public const uint ForegroundBlue      = 0x0001u;
public const uint ForegroundGreen     = 0x0002u;
public const uint ForegroundRed       = 0x0004u;
public const uint ForegroundIntense   = 0x0008u;
public const uint BackgroundBlue      = 0x0010u;
public const uint BackgroundGreen     = 0x0020u;
public const uint BackgroundRed       = 0x0040u;
public const uint BackgroundIntense   = 0x0080u;
public const uint ReverseVideo        = 0x4000u;
public const uint Underscore          = 0x8000u;

/// Grey on black: what a console starts as, and what a program that changed the
/// colour should put back rather than leaving its own behind.
public const uint DefaultAttributes = 0x0007u;

/// How big the window is, in characters — not how big the buffer is, which is
/// usually taller.
public Coord WindowSize() {
    ScreenBufferInfo info;
    Coord size;
    size.X = 0;
    size.Y = 0;
    if (!Win32.Succeeded(GetConsoleScreenBufferInfo(Output(), &info))) { return size; }

    // The window rectangle's edges are inclusive, so the width is the
    // difference plus one.
    size.X = (short)(info.Window.Right - info.Window.Left + 1);
    size.Y = (short)(info.Window.Bottom - info.Window.Top + 1);
    return size;
}

/// Where the cursor is.
public Coord CursorPosition() {
    ScreenBufferInfo info;
    Coord position;
    position.X = 0;
    position.Y = 0;
    if (Win32.Succeeded(GetConsoleScreenBufferInfo(Output(), &info))) {
        position = info.CursorPosition;
    }
    return position;
}

public bool SetCursorPosition(short x, short y) {
    Coord position;
    position.X = x;
    position.Y = y;
    return Win32.Succeeded(SetConsoleCursorPosition(Output(), position));
}

/// Sets the colour of everything written after this point.
public bool SetColour(uint attributes) {
    return Win32.Succeeded(SetConsoleTextAttribute(Output(), (ushort)attributes));
}

public bool SetTitle(String title) {
    return Win32.Succeeded(SetConsoleTitleW(title.ToUtf16().ToPointer()));
}

public String Title() {
    var buffer = new WideBuffer(1024u);
    uint units = GetConsoleTitleW(buffer.Pointer(), buffer.Capacity());
    if (units == 0u) { return ""; }
    return buffer.Text(units);
}

/// Shows or hides the cursor, keeping whatever size it had.
public bool ShowCursor(bool visible) {
    void* handle = Output();
    CursorInfo info;
    if (!Win32.Succeeded(GetConsoleCursorInfo(handle, &info))) { return false; }
    info.Visible = visible ? 1 : 0;
    return Win32.Succeeded(SetConsoleCursorInfo(handle, &info));
}

/// Blanks the whole buffer and puts the cursor back at the top left, which is
/// what `cls` does and what no single API call does.
public bool Clear() {
    void* handle = Output();
    ScreenBufferInfo info;
    if (!Win32.Succeeded(GetConsoleScreenBufferInfo(handle, &info))) { return false; }

    uint cells = (uint)((int)info.Size.X * (int)info.Size.Y);
    Coord origin;
    origin.X = 0;
    origin.Y = 0;

    uint written = 0u;
    FillConsoleOutputCharacterW(handle, 32u, cells, origin, &written);
    FillConsoleOutputAttribute(handle, info.Attributes, cells, origin, &written);
    return Win32.Succeeded(SetConsoleCursorPosition(handle, origin));
}

// ================================================================ raw input

/// `KEY_EVENT_RECORD`'s character, which the header makes a union of a wide and
/// an ANSI character. Only the wide half is ever read here.
public union Character {
    public ushort Unicode;
    public byte   Ansi;
}

/// `KEY_EVENT_RECORD`.
public struct KeyEvent {
    public int    KeyDown;
    public ushort RepeatCount;
    public ushort VirtualKeyCode;
    public ushort VirtualScanCode;
    public Character Char;
    public uint   ControlKeyState;
}

/// `MOUSE_EVENT_RECORD`.
public struct MouseEvent {
    public Coord Position;
    public uint  ButtonState;
    public uint  ControlKeyState;
    public uint  Flags;
}

/// The `INPUT_RECORD` payload, which the `EventType` says how to read. This is
/// a `union` and not a `variant` for exactly the reason unions exist: the tag
/// lives outside it, in the record.
public union InputEvent {
    public KeyEvent   Key;
    public MouseEvent Mouse;
    public Coord      BufferSize;
}

/// `INPUT_RECORD`. `sizeof` is 20.
public struct InputRecord {
    public ushort     EventType;
    public InputEvent Event;
}

public const ushort KeyEventType         = 0x0001u;
public const ushort MouseEventType       = 0x0002u;
public const ushort WindowBufferSizeEvent = 0x0004u;
public const ushort MenuEventType        = 0x0008u;
public const ushort FocusEventType       = 0x0010u;

/// `ControlKeyState` bits.
public const uint RightAltPressed  = 0x0001u;
public const uint LeftAltPressed   = 0x0002u;
public const uint RightCtrlPressed = 0x0004u;
public const uint LeftCtrlPressed  = 0x0008u;
public const uint ShiftPressed     = 0x0010u;
public const uint NumLockOn        = 0x0020u;
public const uint ScrollLockOn     = 0x0040u;
public const uint CapsLockOn       = 0x0080u;

public extern "C" {
    int ReadConsoleInputW(void* handle, InputRecord* records, uint count, uint* read);
    int PeekConsoleInputW(void* handle, InputRecord* records, uint count, uint* read);
    int GetNumberOfConsoleInputEvents(void* handle, uint* count);
    int FlushConsoleInputBuffer(void* handle);
}

/// Waits for one key press and returns its character, with no line editing and
/// no echo. Key *releases* are skipped, so this returns once per press.
///
/// Returns 0 for a key that produces no character — an arrow, a function key —
/// and the caller that cares reads the whole record instead.
public ushort ReadKey() {
    void* handle = Input();
    InputRecord record;
    uint read = 0u;

    while (true) {
        if (!Win32.Succeeded(ReadConsoleInputW(handle, &record, 1u, &read))) { return 0u; }
        if (read == 0u) { return 0u; }
        if (record.EventType != KeyEventType) { continue; }
        if (record.Event.Key.KeyDown == 0) { continue; }
        return record.Event.Key.Char.Unicode;
    }
}

/// True when a key is waiting, so a loop can do something else instead of
/// blocking in `ReadKey`.
///
/// The queue holds releases, resizes and focus changes as well as presses, so
/// the count on its own would answer yes for a window someone had merely
/// resized. Anything that is not a press is dropped until a press is at the
/// front or the queue is empty.
public bool KeyAvailable() {
    void* handle = Input();
    InputRecord record;

    while (true) {
        uint count = 0u;
        if (!Win32.Succeeded(GetNumberOfConsoleInputEvents(handle, &count))) { return false; }
        if (count == 0u) { return false; }

        uint read = 0u;
        if (!Win32.Succeeded(PeekConsoleInputW(handle, &record, 1u, &read))) { return false; }
        if (read == 0u) { return false; }

        if (record.EventType == KeyEventType && record.Event.Key.KeyDown != 0) { return true; }

        // Not a press: take it off so the next look sees the one behind it.
        if (!Win32.Succeeded(ReadConsoleInputW(handle, &record, 1u, &read))) { return false; }
    }
}

#endif
