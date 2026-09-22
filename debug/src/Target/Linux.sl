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

// The ptrace loop.
//
// **This was meant to be a transcription, and mostly was.** The seam asks for
// launch, wait, resume, read and write memory, read and write registers, step
// and terminate; ptrace has all of them, and the two platforms agree on the
// shape of the conversation -- a process that stops and reports, and does not
// run again until told to.
//
// Where they genuinely differ, and where the work was:
//
//   - **Windows reports events; ptrace reports signals.** A `DEBUG_EVENT` says
//     what happened; a `waitpid` says a signal arrived, and which. A breakpoint
//     and a completed single step are both `SIGTRAP` and are told apart by what
//     was asked for rather than by the number -- which is why `_stepping` is
//     kept here and is not something the engine had to learn.
//
//   - **The stop address is not reported, it is read.** Windows hands over the
//     faulting address; here the program counter has to be fetched, and for a
//     breakpoint it is one past the trap exactly as on Windows.
//
//   - **Memory is a file.** `/proc/<pid>/mem` with positional reads beats
//     `PEEKDATA` a word at a time by a wide margin and is simpler, which is the
//     rare case of both.
//
//   - **There is no loader breakpoint to swallow.** The first stop is the
//     `SIGTRAP` the kernel raises when `execv` completes under a tracer, and
//     that one *is* the start of the session rather than something to hide.
module Debugger;

import Standard.Collections;
import Standard.Convert;
import Standard.Directory;
import Standard.File;
import Standard.Path;
import Standard.Text;
#if LINUX
import Linux.Ptrace;

public class LinuxTarget : ITarget
{
    int _pid;
    nuint _imageBase;
    bool _running;
    String _path;

    /// The open `/proc/<pid>/mem`, which is how memory is reached.
    int _memory;

    /// Whether the resume now pending is a single step.
    ///
    /// **Windows does not need this and ptrace does.** A trap flag is state the
    /// thread carries, so an exception can say which kind it is; `PTRACE_CONT`
    /// and `PTRACE_SINGLESTEP` are two different requests and both end in the
    /// same `SIGTRAP`, so the only thing that knows which arrived is whatever
    /// asked.
    bool _stepping;

    /// The signal to deliver on the next resume. Zero swallows it, which is
    /// right for the traps this engine planted and wrong for anything else.
    int _pendingSignal;

    /// Whether a stop is waiting to be answered, so that a resume with nothing
    /// outstanding does nothing rather than continuing a process twice.
    bool _stopped;

    public LinuxTarget()
    {
        _pid = 0;
        _imageBase = 0u;
        _running = false;
        _path = "";
        _memory = -1;
        _stepping = false;
        _pendingSignal = 0;
        _stopped = false;
    }

    public nuint ImageBase => _imageBase;
    public bool IsRunning => _running;

    public Result<bool, String> Launch(String path, String arguments)
    {
        _path = path;

        // **Everything the child needs is built before the fork.** Between the
        // fork and the exec only async-signal-safe calls are legal, and a
        // Stainless value going out of scope there would release through the
        // allocator whose lock another thread may have been holding.
        byte* program = path.ToPointer();

        byte*[] argv = new byte*[2];
        argv[0u] = program;
        argv[1u] = null;

        int child = fork();
        if (child < 0)
            return Fail("could not fork to start " + path);

        if (child == 0)
        {
            // The child. Nothing here allocates, nothing here returns, and
            // nothing managed is in scope -- which is why it is a call to a
            // function taking raw pointers rather than code written inline.
            TraceMeAndExec(program, &argv[0u]);
        }

        _pid = child;
        _running = true;

        // The first stop is the kernel's own, when the exec completes under a
        // tracer. Waiting for it is what makes the process ours before any of
        // its code has run.
        int status = 0;
        if (waitpid(_pid, &status, 0) < 0)
            return Fail("the child never stopped after exec");
        _stopped = true;

        // Die with us, which is what a debugging session wants. Asked for
        // explicitly so that it is a decision rather than a default.
        ptrace(PtraceSetOptions, _pid, null, (void*)(nuint)PtraceOptionExitKill);

        String memoryPath = "/proc/" + Standard.Text.FromInteger((long)_pid)
                          + "/mem";
        _memory = open(memoryPath.ToPointer(), OpenReadWrite, 0);
        if (_memory < 0)
            return Fail("cannot open " + memoryPath
                        + " -- the process is traced but unreadable");

        _imageBase = MappedBaseOf(_pid, path);
        return Ok(true);
    }

    public DebugEvent Wait(uint milliseconds)
    {
        if (!_running)
            return Exited(0);

        // The first call after a launch reports the stop that is already in
        // hand, which is what `Started` is.
        if (_stopped && _imageBase != 0u && !_reportedStart)
        {
            _reportedStart = true;
            return Started(_imageBase, (uint)_pid);
        }

        if (_stopped)
        {
            // Nothing has been resumed, so nothing new can have happened.
            return Nothing();
        }

        int status = 0;
        int got = waitpid(_pid, &status, 0);
        if (got < 0)
        {
            _running = false;
            return Exited(0);
        }

        _stopped = true;

        if (HasExitedNormally(status))
        {
            _running = false;
            return Exited(GetExitStatus(status));
        }

        if (!IsStoppedBySignal(status))
        {
            // Killed by a signal rather than stopped by one.
            _running = false;
            return Exited(-1);
        }

        int signal = GetStopSignal(status);

        UserRegisters registers;
        if (ptrace(PtraceGetRegs, _pid, null, (void*)&registers) < 0)
            return Stopped((uint)_pid, 0u, (uint)signal, true);

        nuint pc = (nuint)registers.Rip;

        if (signal == SignalTrap)
        {
            // **Both a planted trap and a finished step arrive here.** Which it
            // was is what this engine asked for a moment ago, and nothing in
            // the status says.
            if (_stepping)
            {
                _stepping = false;
                _pendingSignal = 0;
                return Stopped((uint)_pid, pc, StepExceptionCode(), true);
            }

            // A trap that was executed leaves the program counter one past it,
            // the same as on Windows -- so the address reported is the
            // instruction, which is what the engine expects to rewind on to.
            _pendingSignal = 0;
            return Stopped((uint)_pid, pc - 1u, BreakpointExceptionCode(), true);
        }

        // `SIGSTOP` is never the program's: nothing here sends it but
        // `RequestBreak`. Holding it pending would re-deliver it on the resume
        // and stop the process again the instant it ran.
        if (signal == SignalStop)
        {
            _pendingSignal = 0;
            return Stopped((uint)_pid, pc, (uint)signal, true);
        }

        // Anything else is the program's own and is delivered back to it when
        // the engine resumes, which is what lets a real fault kill it normally.
        _pendingSignal = signal;
        return Stopped((uint)_pid, pc, (uint)signal, true);
    }

    bool _reportedStart;

    public void Resume(bool handled)
    {
        if (!_running || !_stopped)
            return;
        _stopped = false;

        int signal = handled ? 0 : _pendingSignal;
        _pendingSignal = 0;

        int request = _stepping ? PtraceSingleStep : PtraceCont;
        ptrace(request, _pid, null, (void*)(nuint)signal);
    }

    public bool ReadMemory(nuint address, byte[] into, nuint count)
    {
        if (_memory < 0 || count == 0u || count > into.Length)
            return false;
        long read = pread64(_memory, (void*)&into[0u], count, (long)address);
        return read == (long)count;
    }

    public bool WriteMemory(nuint address, byte[] from, nuint count)
    {
        if (_memory < 0 || count == 0u || count > from.Length)
            return false;

        // **No instruction cache to flush.** x86 keeps its own coherent with
        // stores, which is the one place this backend is shorter than the
        // Windows one rather than longer.
        long written = pwrite64(_memory, (void*)&from[0u], count, (long)address);
        return written == (long)count;
    }

    public bool ReadRegisters(uint thread, Registers* into)
    {
        if (!_running)
            return false;
        UserRegisters registers;
        if (ptrace(PtraceGetRegs, _pid, null, (void*)&registers) < 0)
            return false;
        into->Pc = (nuint)registers.Rip;
        into->StackPointer = (nuint)registers.Rsp;
        into->FramePointer = (nuint)registers.Rbp;
        return true;
    }

    public bool WriteRegisters(uint thread, Registers* from)
    {
        if (!_running)
            return false;

        // Read, change, write: the structure has twenty-seven fields and this
        // engine carries three, so writing one built from nothing would hand
        // the thread twenty-four zeros.
        UserRegisters registers;
        if (ptrace(PtraceGetRegs, _pid, null, (void*)&registers) < 0)
            return false;
        registers.Rip = (ulong)from->Pc;
        registers.Rsp = (ulong)from->StackPointer;
        registers.Rbp = (ulong)from->FramePointer;
        return ptrace(PtraceSetRegs, _pid, null, (void*)&registers) >= 0;
    }

    /// Asks for one instruction on the next resume.
    ///
    /// Nothing is written to the thread here: unlike Windows, where the trap
    /// flag is state, this only records which of two requests `Resume` will
    /// make.
    public bool SetSingleStep(uint thread, bool on)
    {
        _stepping = on;
        return true;
    }

    /// `SIGSTOP`, which stops the program wherever it is.
    ///
    /// A signal is addressed to a process, not to a tracing relationship, so
    /// `kill` need not come from the thread that attached. See
    /// `ITarget.RequestBreak`.
    public bool RequestBreak()
    {
        if (!_running || _pid <= 0 || _stopped)
            return false;
        return kill(_pid, SignalStop) == 0;
    }

    /// Every thread of the process, from `/proc/<pid>/task`.
    ///
    /// **Listed, not traced.** The launch put one thread under
    /// `PTRACE_TRACEME` and that is the one this engine drives; a thread the
    /// program started since is in the directory and is not ours, so its
    /// registers and its stack cannot be read. `CanRead` says which is which.
    ///
    /// Tracing them all means `PTRACE_O_TRACECLONE`, a `waitpid` over the
    /// whole group rather than one pid, and a stopped-or-running state per
    /// thread -- a different event loop, not a longer one.
    public List<uint> Threads()
    {
        var found = new List<uint>();
        if (!_running)
            return found;

        // Ours first, whatever order the directory is in: it is the one a
        // caller can do anything with.
        found.Add((uint)_pid);

        String tasks = "/proc/" + Standard.Text.FromInteger((long)_pid) + "/task";
        var read = Standard.Directory.Directories(tasks);
        if (!read.Ok)
            return found;

        var names = read.Value;
        for (nuint i = 0u; i < names.Count; i++)
        {
            var number = Standard.Convert.ToInt(Standard.Path.FileName(names[i]));
            if (!number.Ok || number.Value == (long)_pid)
                continue;
            found.Add((uint)number.Value);
        }
        return found;
    }

    /// Only the thread that was launched under the tracer. See `Threads`.
    public bool CanRead(uint thread) => thread == (uint)_pid;

    public void Terminate()
    {
        if (_running && _pid > 0)
        {
            ptrace(PtraceKill, _pid, null, null);
            kill(_pid, SignalKill);
            int status = 0;
            waitpid(_pid, &status, 0);
        }
        if (_memory >= 0)
        {
            close(_memory);
            _memory = -1;
        }
        _running = false;
    }
}

/// The child's half of a launch: become traced, become the program, or die.
///
/// **Raw pointers and no managed locals, deliberately.** This runs between a
/// fork and an exec, where only async-signal-safe calls are legal, so it must
/// not allocate and must not release -- and a function with nothing managed in
/// scope cannot do either. It never returns, which is also what keeps the
/// caller's own locals from being released in the child.
void TraceMeAndExec(byte* program, byte** argv)
{
    ptrace(PtraceTraceMe, 0, null, null);
    execv(program, argv);
    _exit(127);
}

/// Where the loader actually put the executable, from `/proc/<pid>/maps`.
///
/// **A position-independent executable never lands where it was linked**, so
/// this is the whole of the slide on Linux and is not optional the way it
/// nearly is on Windows. The first mapping whose path is the program is its
/// base; the file is read rather than parsed properly because every line has
/// the same shape and only the first field of one line is wanted.
nuint MappedBaseOf(int pid, String path)
{
    String mapsPath = "/proc/" + Standard.Text.FromInteger((long)pid) + "/maps";
    var read = Standard.File.ReadAllText(mapsPath);
    if (!read.Ok)
        return 0u;

    String maps = read.Value;
    nuint at = 0u;
    nuint length = maps.ByteLength();

    while (at < length)
    {
        nuint end = at;
        while (end < length && maps.ByteAt(end) != (byte)10)
            end++;

        String line = maps.Substring(at, end - at);
        at = end + 1u;

        if (!PathEndsWithName(line, path))
            continue;

        // The line begins `<start>-<end> `, in hexadecimal with no `0x`.
        nuint dash = 0u;
        bool found = false;
        for (nuint i = 0u; i < line.ByteLength(); i++)
        {
            if (line.ByteAt(i) == (byte)45)          // '-'
            {
                dash = i;
                found = true;
                break;
            }
        }
        if (!found)
            continue;
        return (nuint)HexadecimalValueOf(line, 0u, dash);
    }
    return 0u;
}

/// Whether a `maps` line names this program.
///
/// The path is the last field and is separated by spaces, so this looks at the
/// tail rather than splitting -- a mapping's path may itself contain spaces and
/// splitting would be the thing that breaks on one.
bool PathEndsWithName(String line, String path)
{
    nuint a = line.ByteLength();
    nuint b = path.ByteLength();
    if (b == 0u || b > a)
        return false;
    for (nuint i = 0u; i < b; i++)
    {
        if (line.ByteAt(a - b + i) != path.ByteAt(i))
            return false;
    }
    return true;
}

ulong HexadecimalValueOf(String text, nuint from, nuint to)
{
    ulong answer = 0u;
    for (nuint i = from; i < to; i++)
    {
        byte here = text.ByteAt(i);
        ulong digit = 16u;
        if (here >= (byte)48 && here <= (byte)57)
            digit = (ulong)(here - (byte)48);
        else if (here >= (byte)97 && here <= (byte)102)
            digit = (ulong)(here - (byte)97) + 10u;
        else if (here >= (byte)65 && here <= (byte)70)
            digit = (ulong)(here - (byte)65) + 10u;
        if (digit >= 16u)
            break;
        answer = answer * 16u + digit;
    }
    return answer;
}

#endif
