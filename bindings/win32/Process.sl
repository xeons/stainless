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

// Starting a child process and reading what it wrote.
//
// This is kernel32, so it needs no `-l`.
//
// `CreateProcessW` has a trap worth stating once: it may *write to* the command
// line it is given, so the buffer cannot be a string literal or anything shared.
// `Run` below copies into a `WideBuffer` for exactly that reason, and a caller
// using `CreateProcessW` directly has to do the same.
module Win32.Process;

#if WINDOWS

import Win32;
import Win32.Kernel;

/// `STARTUPINFOW`. `sizeof` is 104. `Size` must be set before the call, which
/// `NewStartupInfo()` does.
public struct StartupInfo {
    public uint  Size;
    public ushort* Reserved;
    public ushort* Desktop;
    public ushort* Title;
    public uint  X;
    public uint  Y;
    public uint  XSize;
    public uint  YSize;
    public uint  XCountChars;
    public uint  YCountChars;
    public uint  FillAttribute;
    public uint  Flags;
    public ushort ShowWindow;
    public ushort Reserved2;
    public byte* Reserved3;
    public void* StandardInput;
    public void* StandardOutput;
    public void* StandardError;
}

/// `PROCESS_INFORMATION`. Both handles belong to the caller and both must be
/// closed, including the thread handle nobody wants.
public struct ProcessInformation {
    public void* Process;
    public void* Thread;
    public uint  ProcessId;
    public uint  ThreadId;
}

public const uint StartFlagUseShowWindow = 0x00000001u;
public const uint StartFlagUseStdHandles = 0x00000100u;

/// `CreateProcessW` creation flags.
public const uint CreateNoWindow       = 0x08000000u;
public const uint CreateNewConsole     = 0x00000010u;
public const uint CreateSuspended      = 0x00000004u;
public const uint CreateUnicodeEnvironment = 0x00000400u;
public const uint DetachedProcess      = 0x00000008u;
public const uint CreateNewProcessGroup = 0x00000200u;

/// `SW_HIDE`, for a child that should not flash a console window.
public const ushort HideWindow = 0u;

// Five kernel32 calls this module makes. They are declared privately here and
// publicly in `Win32.Kernel`: an `extern "C"` declaration is local to the module
// that writes it, so this is a second declaration of one function rather than a
// conflict -- but making both public would leave `CloseHandle` ambiguous in a
// file that imported both modules. `Win32.Kernel` is where they are exported.
extern "C" {
    int  CloseHandle(void* handle);
    int  SetHandleInformation(void* handle, uint mask, uint flags);
    uint WaitForSingleObject(void* handle, uint milliseconds);
    int  GetExitCodeProcess(void* process, uint* code);
    int  ReadFile(void* file, void* buffer, uint toRead, uint* read, void* overlapped);
}

public extern "C" {
    int CreateProcessW(ushort* application, ushort* commandLine,
                       void* processSecurity, void* threadSecurity,
                       int inheritHandles, uint flags, void* environment,
                       ushort* currentDirectory,
                       StartupInfo* startup, ProcessInformation* information);
    int CreatePipe(void** read, void** write, SecurityAttributes* security, uint size);
    int PeekNamedPipe(void* pipe, void* buffer, uint size, uint* read,
                      uint* available, uint* left);
}

/// A `STARTUPINFOW` with `cb` filled in and everything else zeroed.
public StartupInfo NewStartupInfo() {
    StartupInfo startup;
    startup.Size = (uint)sizeof(StartupInfo);
    startup.Reserved = null;
    startup.Desktop = null;
    startup.Title = null;
    startup.X = 0u;
    startup.Y = 0u;
    startup.XSize = 0u;
    startup.YSize = 0u;
    startup.XCountChars = 0u;
    startup.YCountChars = 0u;
    startup.FillAttribute = 0u;
    startup.Flags = 0u;
    startup.ShowWindow = 0u;
    startup.Reserved2 = 0u;
    startup.Reserved3 = null;
    startup.StandardInput = null;
    startup.StandardOutput = null;
    startup.StandardError = null;
    return startup;
}

/// What a finished child left behind.
public struct Completed {
    /// True when the process actually started. Everything else is meaningless
    /// when this is false.
    public bool Started;

    /// The process's exit code, which is whatever it returned from `main`.
    public uint ExitCode;

    /// Whatever the child wrote to its standard output and standard error,
    /// interleaved as the child wrote them.
    public String Output;
}

/// Starts a command, waits for it, and returns its output and exit code.
///
/// The whole command including the program name goes in `commandLine`, quoted
/// the way a shell would quote it — this does not run a shell, so `>` and `|`
/// are not redirections but ordinary characters the child receives.
///
/// Reading has to happen *while* the child runs rather than after: a pipe holds
/// about 64KB and a child that fills it blocks forever waiting for a reader
/// that is itself waiting for the child to exit. This reads until the write end
/// is gone, which happens when the last holder of it closes — hence closing the
/// parent's copy immediately after the child is started.
public Completed Run(String commandLine, String workingDirectory) {
    Completed completed;
    completed.Started = false;
    completed.ExitCode = 0u;
    completed.Output = "";

    // Both ends must be inheritable for the child to receive one.
    var security = Inheritable();

    void* readEnd = null;
    void* writeEnd = null;
    if (!Win32.Succeeded(CreatePipe(&readEnd, &writeEnd, &security, 0u))) {
        return completed;
    }

    // The parent's read end must *not* be inheritable, or the child holds a
    // copy of it and the pipe never reports end-of-file.
    SetHandleInformation(readEnd, HandleFlagInherit, 0u);

    var startup = NewStartupInfo();
    startup.Flags = StartFlagUseStdHandles | StartFlagUseShowWindow;
    startup.ShowWindow = HideWindow;
    startup.StandardOutput = writeEnd;
    startup.StandardError = writeEnd;
    startup.StandardInput = null;

    // CreateProcessW may write to the command line, so it gets a copy it owns.
    var wide = commandLine.ToUtf16();
    var mutable = new WideBuffer((uint)wide.UnitCount());
    ushort* target = mutable.Pointer();
    ushort* source = wide.ToPointer();
    for (nuint i = 0u; i < wide.UnitCount(); i = i + 1u) { target[i] = source[i]; }

    ProcessInformation information;
    ushort* directory = workingDirectory.IsEmpty()
        ? null : workingDirectory.ToUtf16().ToPointer();

    bool started = Win32.Succeeded(CreateProcessW(
        null, mutable.Pointer(), null, null, 1, CreateNoWindow, null,
        directory, &startup, &information));

    // The parent's write end has to go now, whether or not the child started:
    // while it is open the pipe has a writer and the read below never ends.
    CloseHandle(writeEnd);

    if (!started) {
        CloseHandle(readEnd);
        return completed;
    }

    completed.Started = true;
    completed.Output = ReadAll(readEnd);
    CloseHandle(readEnd);

    WaitForSingleObject(information.Process, Infinite);
    GetExitCodeProcess(information.Process, &completed.ExitCode);
    CloseHandle(information.Process);
    CloseHandle(information.Thread);
    return completed;
}

/// Reads a pipe until it ends, as text.
///
/// The child's output is bytes, and this treats them as UTF-8 — which is right
/// for a program that says so and wrong for one still writing the OEM code
/// page. `Win32.Console.UseUtf8` is what a child of this program would call.
public String ReadAll(void* pipe) {
    var text = new StringBuilder();
    var chunk = new ByteBuffer(4096u);

    while (true) {
        uint read = 0u;
        int result = ReadFile(pipe, (void*)chunk.Pointer(), chunk.Capacity(), &read, null);

        // Zero bytes, or ERROR_BROKEN_PIPE, both mean the writer is gone.
        if (result == 0 || read == 0u) { break; }

        text.Append(Text.FromBytes(chunk.Pointer(), (nuint)read));
    }

    return text.ToText();
}

/// Starts a command without waiting for it, and returns the handles. The caller
/// owns both and must close them.
public ProcessInformation Start(String commandLine, uint flags) {
    ProcessInformation information;
    information.Process = null;
    information.Thread = null;
    information.ProcessId = 0u;
    information.ThreadId = 0u;

    var wide = commandLine.ToUtf16();
    var mutable = new WideBuffer((uint)wide.UnitCount());
    ushort* target = mutable.Pointer();
    ushort* source = wide.ToPointer();
    for (nuint i = 0u; i < wide.UnitCount(); i = i + 1u) { target[i] = source[i]; }

    var startup = NewStartupInfo();
    CreateProcessW(null, mutable.Pointer(), null, null, 0, flags, null, null,
                   &startup, &information);
    return information;
}

/// Waits for a started process and returns its exit code.
public uint WaitFor(ProcessInformation information) {
    WaitForSingleObject(information.Process, Infinite);
    uint code = 0u;
    GetExitCodeProcess(information.Process, &code);
    return code;
}

/// Closes both handles a start produced. Not doing this leaks the process
/// object for as long as the program runs, even after the child has exited.
public void CloseProcess(ProcessInformation information) {
    CloseHandle(information.Process);
    CloseHandle(information.Thread);
}

#endif
