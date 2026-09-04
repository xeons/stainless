// Every Win32 struct the bindings declare, measured against the size the
// Windows headers give it.
//
// This is the test that matters most for a binding: a struct one byte off is
// one Windows writes past the end of, and nothing else here would catch it.
// The numbers are read from `sizeof` in C on this target, not from memory.
module Win32Layout;

import Standard.Console;
import Win32.User;
import Win32.Kernel;
import Win32.Terminal;
import Win32.Time;
import Win32.Process;
import Win32.Shell;

void Check(String name, nuint measured, nuint wanted) {
    Console.WriteLine((measured == wanted ? "ok   " : "WRONG ") + name
        + " = " + Text.FromInteger(measured)
        + (measured == wanted ? "" : ", wanted " + Text.FromInteger(wanted)));
}

int Main() {
    Check("POINT", sizeof(Point), 8u);
    Check("SIZE", sizeof(Size), 8u);
    Check("RECT", sizeof(Rect), 16u);
    Check("MSG", sizeof(Msg), 48u);
    Check("WNDCLASSEXW", sizeof(WindowClass), 80u);
    Check("PAINTSTRUCT", sizeof(PaintStruct), 72u);

    Check("SECURITY_ATTRIBUTES", sizeof(SecurityAttributes), 24u);
    Check("SYSTEM_INFO", sizeof(SystemInfo), 48u);
    Check("MEMORYSTATUSEX", sizeof(MemoryStatus), 64u);

    Check("COORD", sizeof(Coord), 4u);
    Check("SMALL_RECT", sizeof(SmallRect), 8u);
    Check("CONSOLE_SCREEN_BUFFER_INFO", sizeof(ScreenBufferInfo), 22u);
    Check("CONSOLE_CURSOR_INFO", sizeof(CursorInfo), 8u);
    Check("KEY_EVENT_RECORD", sizeof(KeyEvent), 16u);
    Check("MOUSE_EVENT_RECORD", sizeof(MouseEvent), 16u);
    Check("INPUT_RECORD", sizeof(InputRecord), 20u);

    Check("SYSTEMTIME", sizeof(SystemTime), 16u);
    Check("FILETIME", sizeof(FileTime), 8u);

    Check("STARTUPINFOW", sizeof(StartupInfo), 104u);
    Check("PROCESS_INFORMATION", sizeof(ProcessInformation), 24u);
    Check("OPENFILENAMEW", sizeof(OpenFileName), 152u);

    // A delegate is one function pointer, which is what makes a WNDPROC an
    // ordinary Stainless value.
    Check("WNDPROC", sizeof(WindowProcedure), 8u);
    return 0;
}
