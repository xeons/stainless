// Stainless - an experimental general-purpose language.
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

// The Win32 debug loop.
//
// A process created with `DEBUG_ONLY_THIS_PROCESS` reports everything that
// happens to it to whoever created it, one event at a time, and does not run
// again until told to. That is the whole mechanism: `WaitForDebugEventEx` and
// `ContinueDebugEvent`, on the thread that launched it and no other.
//
// **`DEBUG_ONLY_THIS_PROCESS`, not `DEBUG_PROCESS`.** The latter also debugs
// every process the target starts, which for a compiler or a build tool means
// stopping on events from children nobody asked about.
module Debugger;

import Standard.Collections;
import Standard.Text;
#if WINDOWS
import Win32;
import Win32.Handles;
import Win32.Kernel32;

#pragma comment(lib, "kernel32")

public class Win32Target : ITarget
{
    HANDLE _process;
    HANDLE _thread;
    uint _processId;
    uint _threadId;
    nuint _imageBase;
    bool _running;

    /// Whether the loader's own breakpoint has been seen and swallowed.
    ///
    /// **Every Windows process raises one**, when the loader has finished and
    /// before `main` runs, and it belongs to the system rather than to any
    /// breakpoint a debugger planted. Reporting it as a stop makes every
    /// session begin at an address in `ntdll` that no source line covers;
    /// handing it back to the program with `DBG_EXCEPTION_NOT_HANDLED` kills
    /// the program outright.
    bool _loaderBreakpointSeen;

    /// The event most recently reported, kept because `ContinueDebugEvent`
    /// needs the thread it came from and the caller should not have to carry
    /// it back.
    uint _pendingThread;
    bool _pending;

    public Win32Target()
    {
        _process = null;
        _thread = null;
        _processId = 0u;
        _threadId = 0u;
        _imageBase = 0u;
        _running = false;
        _loaderBreakpointSeen = false;
        _pendingThread = 0u;
        _pending = false;
    }

    public nuint ImageBase => _imageBase;
    public bool IsRunning => _running;

    public Result<bool, String> Launch(String path, String arguments)
    {
        StartupInfo startup;
        ZeroStartupInfo(&startup);
        startup.Size = (uint)sizeof(StartupInfo);

        ProcessInformation made;
        made.Process = null;
        made.Thread = null;
        made.ProcessId = 0u;
        made.ThreadId = 0u;

        // The command line is what the program parses, and Windows wants the
        // image name inside it as argument zero -- a command line that omits
        // it gives the program an argument list shifted by one.
        String line = arguments.ByteLength() == 0u
                    ? "\"" + path + "\""
                    : "\"" + path + "\" " + arguments;

        var wideLine = line.ToUtf16();
        var widePath = path.ToUtf16();

        int ok = CreateProcessW(widePath.ToPointer(), wideLine.ToPointer(),
                                null, null, 0,
                                DebugOnlyThisProcess, null, null,
                                &startup, &made);
        if (ok == 0)
            return Fail("could not start " + path + ": Windows error "
                        + Standard.Text.FromInteger((long)GetLastError()));

        _process = made.Process;
        _thread = made.Thread;
        _processId = made.ProcessId;
        _threadId = made.ThreadId;
        _running = true;

        // **The debuggee must not outlive the debugger silently.** The default
        // is that it dies with us, which is right for a debugging session and
        // is being asked for explicitly so that it is a decision rather than a
        // default somebody changed.
        DebugSetProcessKillOnExit(1);
        return Ok(true);
    }

    public DebugEvent Wait(uint milliseconds)
    {
        if (!_running)
            return Exited(0);

        DebugEventRaw raw;
        raw.Code = 0u;
        raw.ProcessId = 0u;
        raw.ThreadId = 0u;
        raw.Reserved = 0u;

        if (WaitForDebugEventEx(&raw, milliseconds) == 0)
            return Nothing();

        _pendingThread = raw.ThreadId;
        _pending = true;

        switch (raw.Code)
        {
            case CreateProcessDebugEvent:
            {
                var info = (CreateProcessDebugInfo*)&raw.Body[0u];
                _imageBase = (nuint)info->BaseOfImage;
                // The handle the event carries is the one to keep: it is
                // already open and already has the access a debugger needs.
                if (info->Process != null)
                    _process = info->Process;
                if (info->Thread != null)
                    _thread = info->Thread;
                return Started(_imageBase, raw.ThreadId);
            }

            case ExitProcessDebugEvent:
            {
                var info = (ExitProcessDebugInfo*)&raw.Body[0u];
                _running = false;
                return Exited((int)info->ExitCode);
            }

            case ExceptionDebugEvent:
            {
                var info = (ExceptionDebugInfo*)&raw.Body[0u];
                uint code = info->ExceptionCode;
                nuint at = (nuint)info->ExceptionAddress;

                // The loader's breakpoint, once, and only the first one.
                if (code == ExceptionBreakpoint && !_loaderBreakpointSeen)
                {
                    _loaderBreakpointSeen = true;
                    return ModuleLoaded(_imageBase);
                }

                return Stopped(raw.ThreadId, at, code, info->FirstChance != 0u);
            }

            case CreateThreadDebugEvent:
                return ThreadCreated(raw.ThreadId);

            case ExitThreadDebugEvent:
                return ThreadExited(raw.ThreadId);

            case LoadDllDebugEvent:
            {
                var info = (LoadDllDebugInfo*)&raw.Body[0u];
                return ModuleLoaded((nuint)info->BaseOfDll);
            }

            default:
                // Unloads, debug strings and `RIP_EVENT`, none of which this
                // engine acts on yet. They still have to be continued, which
                // `_pending` above has already arranged.
                return Nothing();
        }
    }

    public void Resume(bool handled)
    {
        if (!_pending)
            return;
        _pending = false;
        ContinueDebugEvent(_processId, _pendingThread,
                           handled ? DbgContinue : DbgExceptionNotHandled);
    }

    public bool ReadMemory(nuint address, byte[] into, nuint count)
    {
        if (_process == null || count == 0u || count > into.Length)
            return false;
        nuint read = 0u;
        int ok = ReadProcessMemory(_process, (void*)address, (void*)&into[0u],
                                   count, &read);
        return ok != 0 && read == count;
    }

    public bool WriteMemory(nuint address, byte[] from, nuint count)
    {
        if (_process == null || count == 0u || count > from.Length)
            return false;

        nuint written = 0u;
        int ok = WriteProcessMemory(_process, (void*)address, (void*)&from[0u],
                                    count, &written);
        if (ok == 0 || written != count)
            return false;

        // **Without this a breakpoint is intermittent.** The processor may be
        // holding the old bytes, so code written and not flushed sometimes
        // traps and sometimes runs straight through, which reads as a
        // breakpoint that works on Tuesdays.
        FlushInstructionCache(_process, (void*)address, count);
        return true;
    }

    public bool ReadRegisters(uint thread, Registers* into)
    {
        HANDLE handle = HandleForThread(thread);
        if (handle == null)
            return false;

        Context context;
        context.ContextFlags = ContextControl | ContextInteger;
        if (GetThreadContext(handle, &context) == 0)
        {
            CloseIfBorrowed(handle, thread);
            return false;
        }

        into->Pc = (nuint)context.Rip;
        into->StackPointer = (nuint)context.Rsp;
        into->FramePointer = (nuint)context.Rbp;
        CloseIfBorrowed(handle, thread);
        return true;
    }

    public bool WriteRegisters(uint thread, Registers* from)
    {
        HANDLE handle = HandleForThread(thread);
        if (handle == null)
            return false;

        // **Read, change, write.** A context written from a structure that was
        // never filled sets every register the flags claim, which for
        // `CONTEXT_INTEGER` means handing the thread sixteen zeros.
        Context context;
        context.ContextFlags = ContextControl | ContextInteger;
        if (GetThreadContext(handle, &context) == 0)
        {
            CloseIfBorrowed(handle, thread);
            return false;
        }

        context.Rip = (ulong)from->Pc;
        context.Rsp = (ulong)from->StackPointer;
        context.Rbp = (ulong)from->FramePointer;
        context.ContextFlags = ContextControl | ContextInteger;

        int ok = SetThreadContext(handle, &context);
        CloseIfBorrowed(handle, thread);
        return ok != 0;
    }

    /// Sets or clears the trap flag on a thread, which is how one instruction
    /// is stepped.
    ///
    /// Here rather than on `ITarget` because it is the one piece of run control
    /// with no portable spelling: ptrace has `PTRACE_SINGLESTEP` as a *request*
    /// rather than a register bit, so the seam carries stepping as an intent
    /// and each backend spells it its own way.
    public bool SetSingleStep(uint thread, bool on)
    {
        HANDLE handle = HandleForThread(thread);
        if (handle == null)
            return false;

        Context context;
        context.ContextFlags = ContextControl;
        if (GetThreadContext(handle, &context) == 0)
        {
            CloseIfBorrowed(handle, thread);
            return false;
        }

        context.EFlags = on ? (context.EFlags | EFlagsTrap)
                            : (context.EFlags & ~EFlagsTrap);
        context.ContextFlags = ContextControl;

        int ok = SetThreadContext(handle, &context);
        CloseIfBorrowed(handle, thread);
        return ok != 0;
    }

    /// `DebugBreakProcess`, which puts an `int3` into the target.
    ///
    /// Not bound by the one-thread rule the rest of this class is; see
    /// `ITarget.RequestBreak`.
    public bool RequestBreak()
    {
        if (_process == null || !_running || _pending)
            return false;
        return DebugBreakProcess(_process) != 0;
    }

    public void Terminate()
    {
        if (_process != null && _running)
            TerminateProcess(_process, 1u);
        _running = false;
    }

    /// The main thread's handle when the id matches, and a borrowed one
    /// otherwise.
    ///
    /// A single-threaded debuggee only ever names the thread the event carried,
    /// which is the one whose handle arrived with `CREATE_PROCESS_DEBUG_EVENT`.
    HANDLE HandleForThread(uint thread)
    {
        if (thread == _threadId || thread == 0u)
            return _thread;
        return OpenThread(ThreadGetContext | ThreadSetContext
                          | ThreadQueryLimited, 0, thread);
    }

    void CloseIfBorrowed(HANDLE handle, uint thread)
    {
        if (handle != _thread && handle != null)
            CloseHandle(handle);
    }

    void ZeroStartupInfo(StartupInfo* startup)
    {
        var bytes = (byte*)startup;
        for (nuint i = 0u; i < (nuint)sizeof(StartupInfo); i++)
            bytes[i] = 0;
    }
}

#endif
