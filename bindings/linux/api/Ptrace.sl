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

// `ptrace`, and the little around it a debugger needs.
//
// **Who may call these is not a detail, and it is the same rule Windows has.**
// Every request must come from the thread that attached -- the tracing
// relationship belongs to a thread, not to a process -- so an engine using
// this owns one thread for the whole session and does every one of these on
// it. A request from the wrong thread fails with `ESRCH`, which reads as "no
// such process" and is not.
//
// **`ptrace` is variadic in the header and is not variadic in the ABI.** glibc
// declares `long ptrace(enum __ptrace_request, ...)` and the four arguments go
// in registers like any other call, so binding it with its real shape is
// correct on x86-64 and is what every other language's binding does.
module Linux.Ptrace;

#if LINUX

/// The requests. Numbered by the kernel, and not contiguously -- 3 and 6 are
/// gaps where `PEEKUSER` and `POKEUSER` sit.
public const int PtraceTraceMe    = 0;
public const int PtracePeekData   = 2;
public const int PtracePokeData   = 5;
public const int PtraceCont       = 7;
public const int PtraceKill       = 8;
public const int PtraceSingleStep = 9;
public const int PtraceGetRegs    = 12;
public const int PtraceSetRegs    = 13;
public const int PtraceAttach     = 16;
public const int PtraceDetach     = 17;
public const int PtraceSetOptions = 0x4200;

/// Kill the tracee if the tracer goes away, which is what a debugging session
/// wants and is not the default.
public const int PtraceOptionExitKill = 0x00100000;

public const int SignalTrap = 5;
public const int SignalKill = 9;

/// `struct user_regs_struct` for x86-64, in the kernel's order.
///
/// **The order is the kernel's and is not the architecture's**: `r15` first and
/// `rip` two thirds of the way in, because the structure grew from the layout
/// `PTRACE_GETREGS` filled on i386. Nothing about it is guessable, and a field
/// out of place gives a program counter that is a segment selector.
public struct UserRegisters
{
    public ulong R15;
    public ulong R14;
    public ulong R13;
    public ulong R12;
    public ulong Rbp;
    public ulong Rbx;
    public ulong R11;
    public ulong R10;
    public ulong R9;
    public ulong R8;
    public ulong Rax;
    public ulong Rcx;
    public ulong Rdx;
    public ulong Rsi;
    public ulong Rdi;

    /// What the system call number was on entry, which `rax` no longer holds
    /// once one has returned.
    public ulong OriginalRax;

    public ulong Rip;
    public ulong Cs;
    public ulong EFlags;
    public ulong Rsp;
    public ulong Ss;
    public ulong FsBase;
    public ulong GsBase;
    public ulong Ds;
    public ulong Es;
    public ulong Fs;
    public ulong Gs;
}

/// The trap flag, which makes the processor raise a debug exception after one
/// instruction. The same bit Windows sets; the difference is only in how it is
/// written.
public const ulong EFlagsTrap = 0x00000100u;

public extern "C"
{
    long ptrace(int request, int pid, void* address, void* data);

    /// **Only ever called with the child's work already prepared.** Between a
    /// fork and an exec none but async-signal-safe calls are legal, because
    /// another thread may have held the allocator's lock at the moment of the
    /// fork and no thread exists in the child to release it.
    /// `runtime/process.c` says the same thing at more length and is the
    /// pattern this follows.
    int fork();
    int execv(byte* path, byte** argv);
    void _exit(int code);

    int waitpid(int pid, int* status, int options);
    int kill(int pid, int signal);

    int open(byte* path, int flags, int mode);
    int close(int handle);

    /// Positional reads, which is what makes `/proc/<pid>/mem` usable as
    /// memory rather than as a stream.
    long pread64(int handle, void* into, nuint count, long at);
    long pwrite64(int handle, void* from, nuint count, long at);
}

public const int OpenReadWrite = 2;

/// `WIFEXITED`, `WEXITSTATUS` and the rest, which are macros in C and so have
/// to be written out once here rather than guessed at each use.
public bool ExitedNormally(int status) => (status & 0x7F) == 0;
public int  ExitStatusOf(int status)   => (status >> 8) & 0xFF;
public bool StoppedBySignal(int status) => (status & 0xFF) == 0x7F;
public int  StopSignalOf(int status)    => (status >> 8) & 0xFF;

#endif
