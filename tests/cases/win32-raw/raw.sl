// The raw layer costs nothing.
//
// This case compiles every `Win32.<Dll>` module — about 300 entry points across
// six libraries — plus the handle types they are declared in terms of, and
// links **without a single `-l`**. That is the property the
// two-layer split exists for: a declaration nothing calls is not a reference,
// so importing the whole Windows API is free, while compiling a wrapper that
// calls one is what makes its library necessary.
//
// It is also a check that the raw modules are raw. If a body crept into one and
// called a user32 or gdi32 entry point, this case would stop linking.
module Win32Raw;

import Standard.Console;
import Win32.Handles;
import Win32.Kernel32;
import Win32.User32;
import Win32.Gdi32;
import Win32.AdvApi32;
import Win32.Shell32;
import Win32.ComDlg32;

int Main() {
    // Constants from all six, so nothing is dead before the linker sees it.
    Console.WriteLine("kernel32: " + Text.FromInteger((long)GenericRead));
    Console.WriteLine("user32:   " + Text.FromInteger((long)WsOverlappedWindow));
    Console.WriteLine("gdi32:    " + Text.FromInteger((long)SrcCopy));
    Console.WriteLine("advapi32: " + Text.FromInteger((long)KeyRead));
    Console.WriteLine("shell32:  " + Text.FromInteger((long)FolderAppData));
    Console.WriteLine("comdlg32: " + Text.FromInteger((long)OfnExplorer));

    // The pointer-shaped constants, which are functions because Stainless has
    // no `const` pointer. Calling one is not a call into Windows.
    Console.WriteLine("HKLM is not null:      "
        + Text.FromBool(LocalMachine() != null));
    Console.WriteLine("IDC_ARROW is not null: "
        + Text.FromBool(CursorArrow() != null));
    Console.WriteLine("INVALID_HANDLE is -1:  "
        + Text.FromBool((nuint)InvalidHandle() == 0xFFFFFFFFFFFFFFFFu));

    // The handle types are told apart, and none of them is anything at run
    // time: what these hold is the same pointer `void*` held before.
    HWND   window = null;
    HDC    device = null;
    HANDLE file   = InvalidHandle();

    Console.WriteLine("a handle is one pointer: "
        + Text.FromBool(sizeof(HWND) == 8u && sizeof(HDC) == sizeof(HANDLE)));
    Console.WriteLine("and they start null:     "
        + Text.FromBool(window == null && device == null && file != null));

    // A kernel32 call, to show the difference: this one is a real reference,
    // and it resolves because the C runtime already links kernel32.
    Console.WriteLine("a real call works:     "
        + Text.FromBool(GetCurrentProcessId() != 0u));
    return 0;
}
