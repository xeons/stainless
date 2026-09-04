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
// A convenience layer over `Win32.Kernel32`, which is where the console
// declarations live — they are kernel32 exports, whatever else they look like.
// Nothing here needs a `-l`.
//
// `Standard.Console` writes text and is what a program should use for that.
// This is for the things that are not writing text: turning on ANSI escape
// handling, moving the cursor, reading a key without waiting for a line, and
// asking how wide the window is.
//
// It is called `Terminal` rather than `Console` on purpose. A module is reached
// by its last name segment, so a `Win32.Console` would shadow
// `Standard.Console` in every file that imported it — and a program doing
// console work is exactly the program that also wants to print.
//
// **Every call here fails when the output is redirected**, because a pipe is
// not a console. That is the right answer rather than a problem to work around:
// a program writing colour codes into a file should not.
module Win32.Terminal;

#if WINDOWS

import Win32;
import Win32.Kernel32;

public void* Output() { return GetStdHandle(StdOutput); }
public void* Input()  { return GetStdHandle(StdInput); }
public void* Error()  { return GetStdHandle(StdError); }

/// Grey on black: what a console starts as, and what a program that changed the
/// colour should put back rather than leaving its own behind.
public const uint DefaultAttributes = 0x0007u;

// ===================================================================== modes

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

/// Turns off line editing and echo, so that `ReadKey` sees a key the moment it
/// is pressed. The previous mode is returned, to be put back.
public uint EnableRawInput() {
    void* handle = Input();
    uint mode = 0u;
    if (!Win32.Succeeded(GetConsoleMode(handle, &mode))) { return 0u; }

    SetConsoleMode(handle, mode & ~(EnableLineInput | EnableEchoInput));
    return mode;
}

/// Puts back a mode `EnableRawInput` returned.
public bool RestoreInput(uint mode) {
    return Win32.Succeeded(SetConsoleMode(Input(), mode));
}

// ============================================================= screen buffer

/// How big the window is, in characters — not how big the buffer is, which is
/// usually taller. Zero by zero when the output is not a console.
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
///
/// The attributes are `uint` although the field is a `ushort`, because `|` on
/// two narrow integers widens — `ForegroundRed | ForegroundIntense` would be an
/// `int` and every use would need a cast back. This narrows once, here.
public bool SetColour(uint attributes) {
    return Win32.Succeeded(SetConsoleTextAttribute(Output(), (ushort)attributes));
}

/// The colour a console starts with.
public bool ResetColour() { return SetColour(DefaultAttributes); }

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

/// The whole record for the next key press, for a caller that needs the virtual
/// key code or the modifier state rather than a character.
public KeyEvent ReadKeyEvent() {
    void* handle = Input();
    InputRecord record;
    uint read = 0u;

    while (true) {
        if (!Win32.Succeeded(ReadConsoleInputW(handle, &record, 1u, &read)) || read == 0u) {
            KeyEvent nothing;
            nothing.KeyDown = 0;
            nothing.RepeatCount = 0u;
            nothing.VirtualKeyCode = 0u;
            nothing.VirtualScanCode = 0u;
            nothing.Char.Unicode = 0u;
            nothing.ControlKeyState = 0u;
            return nothing;
        }
        if (record.EventType != KeyEventType) { continue; }
        if (record.Event.Key.KeyDown == 0) { continue; }
        return record.Event.Key;
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
