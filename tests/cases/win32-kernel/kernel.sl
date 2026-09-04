// kernel32 through the bindings: text crossing as UTF-16 in both directions,
// a directory walk, and the failure conventions.
//
// Everything printed is either something this program just set or a shape
// rather than a value, so the expected output does not depend on the machine.
module Win32Kernel;

import Standard.Console;
import Standard.Collections;
import Win32;
import Win32.Kernel;

int Main() {
    // --- text out and back ------------------------------------------------
    //
    // Set a variable to something no ANSI code page could carry, then read it
    // back: the value goes out as UTF-16 and returns as UTF-8, so a mistake in
    // either direction shows up here.
    String wanted = "héllo 日本 🌍";
    Console.WriteLine("set: " + Text.FromBool(Kernel.SetEnvironment("STAINLESS_TEST", wanted)));
    String read = Kernel.Environment("STAINLESS_TEST");
    Console.WriteLine("read back identical: " + Text.FromBool(read == wanted));
    Console.WriteLine("value: " + read);

    Console.WriteLine("expanded: " + Kernel.Expand("[%STAINLESS_TEST%]"));

    Console.WriteLine("cleared: " + Text.FromBool(Kernel.ClearEnvironment("STAINLESS_TEST")));
    Console.WriteLine("gone: " + Text.FromBool(Kernel.Environment("STAINLESS_TEST").IsEmpty()));

    // --- errors -------------------------------------------------------------
    Console.WriteLine("code 2: " + Win32.Describe(2u));
    Console.WriteLine("code 5: " + Win32.Describe(5u));
    Console.WriteLine("an impossible code has no message: "
        + Text.FromBool(Win32.Describe(0xFFFFFFFEu).IsEmpty()));

    Console.WriteLine("0 is failure: " + Text.FromBool(Win32.Failed(0)));
    Console.WriteLine("1 is success: " + Text.FromBool(Win32.Succeeded(1)));
    Console.WriteLine("null is invalid: " + Text.FromBool(Win32.IsInvalid(null)));
    Console.WriteLine("-1 is invalid: " + Text.FromBool(Win32.IsInvalid(Win32.InvalidHandle())));

    // --- paths ---------------------------------------------------------------
    Console.WriteLine("the exe exists: " + Text.FromBool(Kernel.Exists(Kernel.ExecutablePath())));
    Console.WriteLine("the exe is not a directory: "
        + Text.FromBool(!Kernel.IsDirectory(Kernel.ExecutablePath())));
    Console.WriteLine("nothing is at C:\\no\\such\\place: "
        + Text.FromBool(!Kernel.Exists("C:\\no\\such\\place")));
    Console.WriteLine("the system directory is one: "
        + Text.FromBool(Kernel.IsDirectory(Kernel.SystemDirectory())));

    // GetFullPathNameW is textual: it resolves .. without asking the
    // filesystem, so this works for a path that is not there.
    Console.WriteLine("normalised: " + Kernel.FullPath("C:\\one\\two\\..\\three\\.\\four.txt"));

    String temp = Kernel.TempPath();
    Console.WriteLine("the temp path ends in a separator: "
        + Text.FromBool(temp.Substring(temp.ByteLength() - 1u, 1u) == "\\"));

    // --- a directory walk ----------------------------------------------------
    String directory = Kernel.TempPath() + "stainless-win32-case";
    RemoveTree(directory);
    Console.WriteLine("made: " + Text.FromBool(
        Win32.Succeeded(CreateDirectoryW(directory.ToUtf16().ToPointer(), null))));

    Touch(directory + "\\alpha.txt");
    Touch(directory + "\\béta.txt");
    Touch(directory + "\\日本.txt");

    var names = Kernel.Entries(directory);
    Sort(names);
    Console.WriteLine("found " + Text.FromInteger((long)names.Count()) + ":");
    foreach (String name in names) { Console.WriteLine("  " + name); }

    // The walk skips . and .., so the count is the number of files.
    var data = new FindData();
    void* find = Kernel.FindFirst(directory + "\\alpha.txt", data);
    Console.WriteLine("alpha found: " + Text.FromBool(!Win32.IsInvalid(find)));
    Console.WriteLine("  name: " + data.Name());
    Console.WriteLine("  size: " + Text.FromInteger((long)data.Size()));
    Console.WriteLine("  is a directory: " + Text.FromBool(data.IsDirectory()));
    Console.WriteLine("  written after 1601: " + Text.FromBool(data.Written() > 0u));
    FindClose(find);

    // A pattern nothing matches is InvalidHandle with ERROR_FILE_NOT_FOUND
    // rather than an empty walk.
    void* missing = Kernel.FindFirst(directory + "\\*.nothing", data);
    Console.WriteLine("no match is invalid: " + Text.FromBool(Win32.IsInvalid(missing)));
    Console.WriteLine("  because: " + Text.FromBool(Win32.LastError() == ErrorFileNotFound));

    RemoveTree(directory);
    Console.WriteLine("removed: " + Text.FromBool(!Kernel.Exists(directory)));

    // --- the system -----------------------------------------------------------
    var info = Kernel.System();
    Console.WriteLine("at least one processor: " + Text.FromBool(info.ProcessorCount >= 1u));
    Console.WriteLine("pages are 4K: " + Text.FromBool(info.PageSize == 4096u));
    Console.WriteLine("the union reads both ways: "
        + Text.FromBool((info.Processor.Whole & 0xFFFFu)
                        == (uint)info.Processor.Split.Architecture));

    var memory = Kernel.Memory();
    Console.WriteLine("some memory is free: " + Text.FromBool(memory.AvailablePhysical > 0u));
    Console.WriteLine("load is a percentage: " + Text.FromBool(memory.MemoryLoad <= 100u));

    // --- pages ----------------------------------------------------------------
    void* pages = Kernel.AllocatePages(65536u);
    Console.WriteLine("allocated: " + Text.FromBool(pages != null));
    byte* bytes = (byte*)pages;
    bytes[0] = 42u;
    bytes[65535u] = 24u;
    Console.WriteLine("readable: " + Text.FromBool(bytes[0] == 42u && bytes[65535u] == 24u));
    Console.WriteLine("released: " + Text.FromBool(Kernel.ReleasePages(pages)));
    return 0;
}

/// Creates an empty file, through the binding rather than through Standard.File,
/// so that CreateFileW and CloseHandle are what is being tested.
void Touch(String path) {
    void* file = Kernel.OpenFile(path, GenericWrite, 0u, CreateAlways);
    if (!Win32.IsInvalid(file)) { CloseHandle(file); }
}

/// Deletes the directory and everything directly in it. One level deep is all
/// this case makes.
void RemoveTree(String directory) {
    foreach (String name in Kernel.Entries(directory)) {
        DeleteFileW((directory + "\\" + name).ToUtf16().ToPointer());
    }
    RemoveDirectoryW(directory.ToUtf16().ToPointer());
}
