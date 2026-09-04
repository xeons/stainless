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
// A convenience layer over `Win32.Kernel32`. Nothing here needs a `-l`.
//
// `CreateProcessW` has a trap worth stating once: it may *write to* the command
// line it is given, so the buffer cannot be a string literal or anything
// shared. `Run` copies into a `Win32.WideBuffer` for exactly that reason, and a
// caller using the declaration directly has to do the same.
module Win32.Tasks;

#if WINDOWS

import Win32;
import Win32.Kernel32;
import Win32.Handles;

/// A `SECURITY_ATTRIBUTES` that says only "the child may inherit this handle".
public SecurityAttributes Inheritable() {
    SecurityAttributes attributes;
    attributes.Length = (uint)sizeof(SecurityAttributes);
    attributes.Descriptor = null;
    attributes.InheritHandle = 1;
    return attributes;
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

/// Blocks until the handle is signalled, and answers whether it was.
///
/// A process handle becomes signalled when the process exits, a thread's when
/// the thread does, and an event's when it is set — which is why one function
/// covers all three.
public bool Wait(HANDLE handle, uint milliseconds) {
    return WaitForSingleObject(handle, milliseconds) == WaitObject0;
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

    HANDLE readEnd = null;
    HANDLE writeEnd = null;
    if (!Win32.Succeeded(CreatePipe(&readEnd, &writeEnd, &security, 0u))) {
        return completed;
    }

    // The parent's read end must *not* be inheritable, or the child holds a
    // copy of it and the pipe never reports end-of-file.
    SetHandleInformation(readEnd, HandleFlagInherit, 0u);

    var startup = NewStartupInfo();
    startup.Flags = StartFlagUseStdHandles | StartFlagUseShowWindow;
    startup.ShowWindow = 0u;                    // SW_HIDE
    startup.StandardOutput = writeEnd;
    startup.StandardError = writeEnd;
    startup.StandardInput = null;

    // CreateProcessW may write to the command line, so it gets a copy it owns.
    var mutable = Win32.Copy(commandLine);

    ProcessInformation information;
    char16* directory = workingDirectory.IsEmpty()
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
/// page. `Win32.Terminal.UseUtf8` is what a child of this program would call.
public String ReadAll(HANDLE pipe) {
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
/// owns both and must close them with `CloseProcess`.
public ProcessInformation Start(String commandLine, uint flags) {
    ProcessInformation information;
    information.Process = null;
    information.Thread = null;
    information.ProcessId = 0u;
    information.ThreadId = 0u;

    var mutable = Win32.Copy(commandLine);
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
