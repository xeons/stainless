// The mix-ups the handle types exist to catch.
//
// Every one of these was a `void*` passed to a `void*` before, and compiled.
// None of them costs anything at run time: what these hold is the same pointer
// it always was, and no `HWND__` or `HDC__` is laid out, emitted, or present in
// the binary at all.
module ErrWin32Handles;

import Win32.Handles;
import Win32.User32;
import Win32.Gdi32;
import Win32.Kernel32;
import Win32.AdvApi32;

int Main() {
    HWND   window = null;
    HDC    device = null;
    HANDLE file   = InvalidHandle();
    HKEY   key     = LocalMachine();

    // A device context is not a window.
    ShowWindow(device, 1);                          // SL0262

    // Nor is a window a device context.
    LineTo(window, 10, 10);                         // SL0262

    // A kernel handle is not a window, however much both are pointers.
    SetWindowTextW(file, null);                     // SL0262

    // A registry key is not a file.
    CloseHandle(key);                               // SL0262

    // And a window is not a registry key.
    RegCloseKey(window);                            // SL0262

    // An untyped pointer is not a handle either: the direction that matters is
    // the one that would let anything through.
    void* anything = null;
    DestroyWindow(anything);                        // SL0262

    // `DeleteObject(window)` is *not* here, and compiles. `HGDIOBJ` takes any
    // pointer, because Windows spells it `void*` so that every pen, brush, font
    // and bitmap reaches `SelectObject` without a cast. C accepts the same
    // mistake for the same reason; the three functions typed that way are the
    // ones these handles do not help with.

    return 0;
}
