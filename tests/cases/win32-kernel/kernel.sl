// kernel32 through the bindings: text crossing as UTF-16 in both directions,
// a directory walk, and the failure conventions.
//
// Everything printed is either something this program just set or a shape
// rather than a value, so the expected output does not depend on the machine.
module Win32Kernel;

import Standard.Console;
import Standard.Collections;
import Win32;
import Win32.Kernel32;
import Win32.Handles;
import Win32.Environment;
import Win32.Files;
import Win32.Machine;
import Win32.Clock;

int Main()
{
    // --- text out and back ------------------------------------------------
    //
    // Set a variable to something no ANSI code page could carry, then read it
    // back: the value goes out as UTF-16 and returns as UTF-8, so a mistake in
    // either direction shows up here.
    String wanted = "héllo 日本 🌍";
    Console.WriteLine("set: "
        + Text.FromBool(Environment.SetEnvironmentVariable("STAINLESS_TEST", wanted)));
    String read = Environment.GetEnvironmentVariable("STAINLESS_TEST");
    Console.WriteLine("read back identical: " + Text.FromBool(read == wanted));
    Console.WriteLine("value: " + read);

    Console.WriteLine("expanded: " + Environment.ExpandEnvironmentVariables("[%STAINLESS_TEST%]"));

    Console.WriteLine("cleared: "
        + Text.FromBool(Environment.ClearEnvironmentVariable("STAINLESS_TEST")));
    Console.WriteLine("gone: "
        + Text.FromBool(Environment.GetEnvironmentVariable("STAINLESS_TEST").IsEmpty));

    // --- errors -------------------------------------------------------------
    Console.WriteLine("code 2: " + Win32.FormatErrorMessage(2u));
    Console.WriteLine("code 5: " + Win32.FormatErrorMessage(5u));
    Console.WriteLine("an impossible code has no message: "
        + Text.FromBool(Win32.FormatErrorMessage(0xFFFFFFFEu).IsEmpty));

    Console.WriteLine("0 is failure: " + Text.FromBool(Win32.IsBoolFailure(0)));
    Console.WriteLine("1 is success: " + Text.FromBool(Win32.IsBoolSuccess(1)));
    Console.WriteLine("null is invalid: " + Text.FromBool(Win32.IsInvalidHandle(null)));
    Console.WriteLine("-1 is invalid: " + Text.FromBool(Win32.IsInvalidHandle(InvalidHandle())));

    // --- paths ---------------------------------------------------------------
    Console.WriteLine("the exe exists: "
        + Text.FromBool(Files.FileExists(Machine.GetExecutablePath())));
    Console.WriteLine("the exe is not a directory: "
        + Text.FromBool(!Files.DirectoryExists(Machine.GetExecutablePath())));
    Console.WriteLine("nothing is at C:\\no\\such\\place: "
        + Text.FromBool(!Files.FileExists("C:\\no\\such\\place")));
    Console.WriteLine("the system directory is one: "
        + Text.FromBool(Files.DirectoryExists(Environment.GetSystemDirectory())));

    // GetFullPathNameW is textual: it resolves .. without asking the
    // filesystem, so this works for a path that is not there.
    Console.WriteLine("normalised: " + Files.GetFullPath("C:\\one\\two\\..\\three\\.\\four.txt"));

    String temp = Files.GetTempPath();
    Console.WriteLine("the temp path ends in a separator: "
        + Text.FromBool(temp.Substring(temp.ByteLength() - 1u, 1u) == "\\"));

    // --- a directory walk ----------------------------------------------------
    String directory = Files.GetTempPath() + "stainless-win32-case";
    RemoveTree(directory);
    Console.WriteLine("made: " + Text.FromBool(
        Win32.IsBoolSuccess(CreateDirectoryW(directory.ToUtf16().ToPointer(), null))));

    Touch(directory + "\\alpha.txt");
    Touch(directory + "\\béta.txt");
    Touch(directory + "\\日本.txt");

    var names = Files.GetDirectoryEntries(directory);
    Sort(names);
    Console.WriteLine("found " + Text.FromInteger((long)names.Count) + ":");
    foreach (String name in names)
        Console.WriteLine("  " + name);

    // WIN32_FIND_DATAW is a struct with the two inline WCHAR arrays the header
    // gives it, so this is a plain local: 592 bytes, no allocation.
    Console.WriteLine("sizeof(FindData) = " + Text.FromInteger(sizeof(FindData)));
    Console.WriteLine("offsetof(FileName) = " + Text.FromInteger(offsetof(FindData, FileName)));

    FindData data;
    HANDLE find = Files.FindFirstFile(directory + "\\alpha.txt", ref data);
    Console.WriteLine("alpha found: " + Text.FromBool(!Win32.IsInvalidHandle(find)));
    Console.WriteLine("  name: " + Files.GetEntryName(ref data));
    Console.WriteLine("  size: " + Text.FromInteger((long)Files.GetEntrySize(ref data)));
    Console.WriteLine("  is a directory: " + Text.FromBool(Files.IsDirectoryEntry(ref data)));
    Console.WriteLine("  written after 1601: "
        + Text.FromBool(Clock.FileTimeToTicks(data.Written) > 0u));
    FindClose(find);

    // A pattern nothing matches is InvalidHandle with ERROR_FILE_NOT_FOUND
    // rather than an empty walk.
    HANDLE missing = Files.FindFirstFile(directory + "\\*.nothing", ref data);
    Console.WriteLine("no match is invalid: " + Text.FromBool(Win32.IsInvalidHandle(missing)));
    Console.WriteLine("  because: " + Text.FromBool(Win32.GetLastErrorCode() == ErrorFileNotFound));

    RemoveTree(directory);
    Console.WriteLine("removed: " + Text.FromBool(!Files.FileExists(directory)));

    // --- the system -----------------------------------------------------------
    var info = Machine.QuerySystemInfo();
    Console.WriteLine("at least one processor: " + Text.FromBool(info.ProcessorCount >= 1u));
    Console.WriteLine("pages are 4K: " + Text.FromBool(info.PageSize == 4096u));
    // SYSTEM_INFO's first word is a nameless union of a whole DWORD and two
    // halves, so both names reach the same bytes -- as they do in C.
    Console.WriteLine("the nameless union reads both ways: "
        + Text.FromBool((info.OemId & 0xFFFFu) == (uint)info.Architecture));

    var memory = Machine.QueryMemoryStatus();
    Console.WriteLine("some memory is free: " + Text.FromBool(memory.AvailablePhysical > 0u));
    Console.WriteLine("load is a percentage: " + Text.FromBool(memory.MemoryLoad <= 100u));

    // --- pages ----------------------------------------------------------------
    void* pages = Machine.AllocatePages(65536u);
    Console.WriteLine("allocated: " + Text.FromBool(pages != null));
    byte* bytes = (byte*)pages;
    bytes[0] = 42u;
    bytes[65535u] = 24u;
    Console.WriteLine("readable: " + Text.FromBool(bytes[0] == 42u && bytes[65535u] == 24u));
    Console.WriteLine("released: " + Text.FromBool(Machine.ReleasePages(pages)));
    return 0;
}

/// Creates an empty file, through the binding rather than through Standard.File,
/// so that CreateFileW and CloseHandle are what is being tested.
void Touch(String path)
{
    HANDLE file = Files.OpenFileHandle(path, GenericWrite, 0u, CreateAlways);
    if (!Win32.IsInvalidHandle(file))
        CloseHandle(file);
}

/// Deletes the directory and everything directly in it. One level deep is all
/// this case makes.
void RemoveTree(String directory)
{
    foreach (String name in Files.GetDirectoryEntries(directory))
    {
        DeleteFileW((directory + "\\" + name).ToUtf16().ToPointer());
    }
    RemoveDirectoryW(directory.ToUtf16().ToPointer());
}
