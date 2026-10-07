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

// The Mach exception loop, for arm64 macOS.
//
// The program is spawned suspended, before dyld runs, and its task port is
// taken with `task_for_pid`. Its exception ports are pointed at a port this
// target receives on, so a trap or a fault arrives as a message from the
// faulting thread, which waits for a reply. The rest of the task keeps
// running until it is suspended, so every exception suspends the whole task
// and the reply is held until `Resume`.
//
// `ptrace` is not used. The process is this one's child, so `waitpid` reports
// its exit. A break request is a message to a second port in the same set, so
// one receive waits for both.
//
// Taking the task port needs two things the program cannot give itself:
// sldb signed with `com.apple.security.cs.debugger`, which the project file
// does, and `system.privilege.taskport` granted. Over ssh there is no window
// to grant it in; see debug/README.md.
module Debugger;

import Standard.Collections;
import Standard.Text;
#if MACOS && ARM64
import MacOS.Mach;

/// Sent to the interrupt port by `RequestBreak`.
const int BreakRequestId = 0x534C4442;

/// How long one receive waits before the process is checked for an exit.
const uint ReceiveSliceMilliseconds = 50u;

/// Large enough for a `mach_exception_raise` with its two codes.
const nuint MessageBufferSize = 1024u;

/// Where `mach_exception_raise`'s fields sit. The message is `pack(4)`, so
/// the codes are not eight-byte aligned.
const nuint ExceptionThreadAt = 28u;
const nuint ExceptionTypeAt = 60u;

public class MachTarget : ITarget
{
    int _pid;
    uint _task;
    nuint _imageBase;
    bool _running;
    bool _reportedStart;

    /// The receive rights: exceptions, break requests, and the set holding
    /// both.
    uint _exceptions;
    uint _interrupt;
    uint _portSet;

    /// The task is suspended and a stop has been reported but not answered.
    bool _stopped;

    /// The exception reply owed, or `MACH_PORT_NULL` for a stop with none.
    uint _replyPort;
    uint _replyBits;
    int _replyId;

    /// A single step was asked for, on this thread, with these others held.
    bool _stepping;
    uint _steppingThread;
    List<uint> _heldForStep;

    /// The thread of the last stop, which `Threads` lists first.
    uint _lastThread;

    /// Thread port names this target holds one reference to.
    List<uint> _knownThreads;

    byte[] _message;

    public MachTarget()
    {
        _pid = 0;
        _task = MACH_PORT_NULL;
        _imageBase = 0u;
        _running = false;
        _reportedStart = false;
        _exceptions = MACH_PORT_NULL;
        _interrupt = MACH_PORT_NULL;
        _portSet = MACH_PORT_NULL;
        _stopped = false;
        _replyPort = MACH_PORT_NULL;
        _replyBits = 0u;
        _replyId = 0;
        _stepping = false;
        _steppingThread = 0u;
        _heldForStep = new List<uint>();
        _lastThread = 0u;
        _knownThreads = new List<uint>();
        _message = new byte[MessageBufferSize];
    }

    public nuint ImageBase => _imageBase;
    public bool IsRunning => _running;

    public Result<bool, String> Launch(String path, String arguments)
    {
        var words = SplitArguments(arguments);
        byte*[] argv = new byte*[words.Count + 2u];
        argv[0u] = path.ToPointer();
        for (nuint i = 0u; i < words.Count; i++)
            argv[i + 1u] = words[i].ToPointer();
        argv[words.Count + 1u] = null;

        void* attributes = null;
        posix_spawnattr_init(&attributes);
        posix_spawnattr_setflags(&attributes, POSIX_SPAWN_START_SUSPENDED);
        int pid = 0;
        int spawned = posix_spawn(&pid, path.ToPointer(), null, &attributes, &argv[0u],
                                  *_NSGetEnviron());
        posix_spawnattr_destroy(&attributes);
        if (spawned != 0)
            return Fail("could not start " + path + " (posix_spawn answered "
                        + Standard.Text.FromInteger((long)spawned) + ")");

        _pid = pid;
        _running = true;
        _stopped = true;

        int taken = task_for_pid(mach_task_self_, _pid, &_task);
        if (taken != KERN_SUCCESS)
        {
            Terminate();
            return Fail("macOS refused the task port of " + path + " (kern_return "
                        + Standard.Text.FromInteger((long)taken) + "). The debugger MUST be"
                        + " signed with com.apple.security.cs.debugger, and"
                        + " system.privilege.taskport must allow it; see debug/README.md");
        }

        if (!OpenPorts())
        {
            Terminate();
            return Fail("could not set up the exception ports of " + path);
        }

        _imageBase = FindExecutableBase(_task);
        var threads = Threads();
        if (threads.Count != 0u)
            _lastThread = threads[0u];
        return Ok(true);
    }

    /// The exception and interrupt ports, in one set, with the task's
    /// exceptions sent to the first.
    bool OpenPorts()
    {
        uint self = mach_task_self_;
        if (mach_port_allocate(self, MACH_PORT_RIGHT_RECEIVE, &_exceptions) != KERN_SUCCESS
            || mach_port_insert_right(self, _exceptions, _exceptions,
                                      MACH_MSG_TYPE_MAKE_SEND) != KERN_SUCCESS)
            return false;
        if (mach_port_allocate(self, MACH_PORT_RIGHT_RECEIVE, &_interrupt) != KERN_SUCCESS
            || mach_port_insert_right(self, _interrupt, _interrupt,
                                      MACH_MSG_TYPE_MAKE_SEND) != KERN_SUCCESS)
            return false;
        if (mach_port_allocate(self, MACH_PORT_RIGHT_PORT_SET, &_portSet) != KERN_SUCCESS
            || mach_port_move_member(self, _exceptions, _portSet) != KERN_SUCCESS
            || mach_port_move_member(self, _interrupt, _portSet) != KERN_SUCCESS)
            return false;

        uint mask = EXC_MASK_BAD_ACCESS | EXC_MASK_BAD_INSTRUCTION | EXC_MASK_ARITHMETIC
                  | EXC_MASK_BREAKPOINT;
        return task_set_exception_ports(_task, mask, _exceptions, EXCEPTION_DEFAULT_64,
                                        THREAD_STATE_NONE) == KERN_SUCCESS;
    }

    public DebugEvent Wait(uint milliseconds)
    {
        if (!_running)
            return Exited(0);

        if (!_reportedStart)
        {
            _reportedStart = true;
            return Started(_imageBase, _lastThread);
        }

        // A stop not yet answered: nothing has run since.
        if (_stopped)
            return Nothing();

        uint waited = 0u;
        while (true)
        {
            var header = (mach_msg_header_t*)&_message[0u];
            int got = mach_msg(header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0u,
                               (uint)MessageBufferSize, _portSet, ReceiveSliceMilliseconds,
                               MACH_PORT_NULL);
            if (got == KERN_SUCCESS)
                return InterpretMessage();

            int status = 0;
            if (waitpid(_pid, &status, WNOHANG) == _pid)
            {
                _running = false;
                ReleasePorts();
                return Exited(DescribeWaitStatus(status));
            }

            if (got != MACH_RCV_TIMED_OUT)
                return Nothing();

            waited += ReceiveSliceMilliseconds;
            if (waited >= milliseconds)
                return Nothing();
        }
    }

    /// The message in `_message`, which is either a break request or an
    /// exception.
    DebugEvent InterpretMessage()
    {
        var header = (mach_msg_header_t*)&_message[0u];
        task_suspend(_task);
        _stopped = true;

        if (header->msgh_id == BreakRequestId)
        {
            Registers registers = default;
            ReadRegisters(_lastThread, &registers);
            return Stopped(_lastThread, registers.Pc, 0u, true);
        }

        _replyPort = header->msgh_remote_port;
        _replyBits = header->msgh_bits & 0x1Fu;
        _replyId = header->msgh_id + 100;

        uint thread = (uint)LittleEndianAt(_message, ExceptionThreadAt, 4u);
        int exception = (int)LittleEndianAt(_message, ExceptionTypeAt, 4u);
        AdoptThreadReference(thread);
        mach_port_deallocate(mach_task_self_, (uint)LittleEndianAt(_message, 40u, 4u));
        _lastThread = thread;

        Registers registers = default;
        ReadRegisters(thread, &registers);

        if (exception == EXC_BREAKPOINT)
        {
            // A completed step and a planted `brk` are one exception. Which
            // one is what was asked for.
            if (_stepping)
            {
                FinishStep();
                return Stopped(thread, registers.Pc, StepExceptionCode(), true);
            }

            // `brk` does not advance the program counter, so it is on the trap.
            return Stopped(thread, registers.Pc, BreakpointExceptionCode(), true);
        }

        if (_stepping)
            FinishStep();
        return Stopped(thread, registers.Pc, (uint)exception, true);
    }

    /// Takes the single-step bit off and lets the threads held for it go.
    void FinishStep()
    {
        WriteSingleStepBit(_steppingThread, false);
        for (nuint i = 0u; i < _heldForStep.Count; i++)
            thread_resume(_heldForStep[i]);
        _heldForStep.Clear();
        _stepping = false;
    }

    public void Resume(bool handled)
    {
        if (!_running || !_stopped)
            return;
        _stopped = false;

        if (_stepping)
        {
            // One instruction of one thread. Anything else running would pass
            // the breakpoint lifted for it.
            WriteSingleStepBit(_steppingThread, true);
            var all = Threads();
            for (nuint i = 0u; i < all.Count; i++)
            {
                if (all[i] != _steppingThread && thread_suspend(all[i]) == KERN_SUCCESS)
                    _heldForStep.Add(all[i]);
            }
        }

        if (_replyPort != MACH_PORT_NULL)
        {
            SendExceptionReply(handled ? KERN_SUCCESS : 5);
            _replyPort = MACH_PORT_NULL;
        }
        task_resume(_task);
    }

    /// Answers the held exception. `KERN_FAILURE` hands it back to the
    /// kernel, which delivers it to the program as its signal.
    void SendExceptionReply(int answer)
    {
        // `mig_reply_error_t`: a header, `NDR_record`, and the return code.
        byte[] reply = new byte[36];
        var header = (mach_msg_header_t*)&reply[0u];
        header->msgh_bits = _replyBits;
        header->msgh_size = 36u;
        header->msgh_remote_port = _replyPort;
        header->msgh_local_port = MACH_PORT_NULL;
        header->msgh_voucher_port = MACH_PORT_NULL;
        header->msgh_id = _replyId;
        reply[28u] = 1;                            // NDR int_rep: little-endian
        *(int*)&reply[32u] = answer;
        mach_msg(header, MACH_SEND_MSG, 36u, 0u, MACH_PORT_NULL, 0u, MACH_PORT_NULL);
    }

    public bool ReadMemory(nuint address, byte[] into, nuint count)
    {
        if (!_running || count == 0u || count > into.Length)
            return false;
        ulong read = 0u;
        int done = mach_vm_read_overwrite(_task, (ulong)address, (ulong)count,
                                          (ulong)(nuint)&into[0u], &read);
        return done == KERN_SUCCESS && read == (ulong)count;
    }

    /// Writes, through a private copy of the page when it is not writable,
    /// which code is not. The instruction cache is flushed after, or the
    /// processor goes on executing what was there.
    public bool WriteMemory(nuint address, byte[] from, nuint count)
    {
        if (!_running || count == 0u || count > from.Length)
            return false;

        int protection = 0;
        bool known = ReadProtection(address, &protection);
        bool lifted = known && (protection & VM_PROT_WRITE) == 0;
        if (lifted && mach_vm_protect(_task, (ulong)address, (ulong)count, 0,
                                      VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY)
                      != KERN_SUCCESS)
            return false;

        int written = mach_vm_write(_task, (ulong)address, (nuint)&from[0u], (uint)count);

        if (lifted)
            mach_vm_protect(_task, (ulong)address, (ulong)count, 0, protection);

        int flush = MATTR_VAL_CACHE_FLUSH;
        vm_machine_attribute(_task, address, count, MATTR_CACHE, &flush);
        return written == KERN_SUCCESS;
    }

    /// The current protection of the region holding an address.
    bool ReadProtection(nuint address, int* protection)
    {
        ulong at = (ulong)address;
        ulong size = 0u;
        int[] info = new int[VM_REGION_BASIC_INFO_COUNT_64];
        uint count = VM_REGION_BASIC_INFO_COUNT_64;
        uint objectName = MACH_PORT_NULL;
        if (mach_vm_region(_task, &at, &size, VM_REGION_BASIC_INFO_64, &info[0u], &count,
                           &objectName) != KERN_SUCCESS)
            return false;
        if (objectName != MACH_PORT_NULL)
            mach_port_deallocate(mach_task_self_, objectName);
        if (at > (ulong)address)
            return false;
        *protection = info[0u];
        return true;
    }

    public bool ReadRegisters(uint thread, Registers* into)
    {
        if (!_running)
            return false;
        arm_thread_state64_t state;
        uint count = ARM_THREAD_STATE64_COUNT;
        if (thread_get_state(thread, ARM_THREAD_STATE64, (uint*)&state, &count) != KERN_SUCCESS)
            return false;
        into->Pc = (nuint)state.pc;
        into->StackPointer = (nuint)state.sp;
        into->FramePointer = (nuint)state.fp;
        into->LinkRegister = (nuint)state.lr;
        return true;
    }

    public bool WriteRegisters(uint thread, Registers* from)
    {
        if (!_running)
            return false;

        // Read, change, write: the state has thirty-four registers and
        // `Registers` carries four.
        arm_thread_state64_t state;
        uint count = ARM_THREAD_STATE64_COUNT;
        if (thread_get_state(thread, ARM_THREAD_STATE64, (uint*)&state, &count) != KERN_SUCCESS)
            return false;
        state.pc = (ulong)from->Pc;
        state.sp = (ulong)from->StackPointer;
        state.fp = (ulong)from->FramePointer;
        if (from->LinkRegister != 0u)
            state.lr = (ulong)from->LinkRegister;
        return thread_set_state(thread, ARM_THREAD_STATE64, (uint*)&state,
                                ARM_THREAD_STATE64_COUNT) == KERN_SUCCESS;
    }

    /// Records a step for the next `Resume`, which sets the bit then.
    public bool SetSingleStep(uint thread, bool on)
    {
        _stepping = on;
        _steppingThread = thread;
        return true;
    }

    /// `MDSCR_EL1.SS`, which the kernel turns into one instruction and then
    /// `EXC_BREAKPOINT`.
    bool WriteSingleStepBit(uint thread, bool on)
    {
        arm_debug_state64_t state;
        uint count = ARM_DEBUG_STATE64_COUNT;
        if (thread_get_state(thread, ARM_DEBUG_STATE64, (uint*)&state, &count) != KERN_SUCCESS)
            return false;
        if (on)
            state.mdscr_el1 = state.mdscr_el1 | MDSCR_SS;
        else
            state.mdscr_el1 = state.mdscr_el1 & ~MDSCR_SS;
        return thread_set_state(thread, ARM_DEBUG_STATE64, (uint*)&state,
                                ARM_DEBUG_STATE64_COUNT) == KERN_SUCCESS;
    }

    /// A message to the interrupt port, from whichever thread asks. The
    /// session's thread is waiting on the set that holds it.
    public bool RequestBreak()
    {
        if (!_running || _stopped || _interrupt == MACH_PORT_NULL)
            return false;
        mach_msg_header_t header;
        header.msgh_bits = MACH_MSG_TYPE_COPY_SEND;
        header.msgh_size = (uint)sizeof(mach_msg_header_t);
        header.msgh_remote_port = _interrupt;
        header.msgh_local_port = MACH_PORT_NULL;
        header.msgh_voucher_port = MACH_PORT_NULL;
        header.msgh_id = BreakRequestId;
        return mach_msg(&header, MACH_SEND_MSG | MACH_SEND_TIMEOUT, header.msgh_size, 0u,
                        MACH_PORT_NULL, 0u, MACH_PORT_NULL) == KERN_SUCCESS;
    }

    /// Every thread, the last one to stop first. Every one can be read.
    public List<uint> Threads()
    {
        var found = new List<uint>();
        if (!_running)
            return found;

        uint* list = null;
        uint count = 0u;
        if (task_threads(_task, &list, &count) != KERN_SUCCESS)
            return found;

        if (_lastThread != 0u)
            found.Add(_lastThread);
        for (uint i = 0u; i < count; i++)
        {
            uint thread = list[i];
            AdoptThreadReference(thread);
            if (thread != _lastThread)
                found.Add(thread);
        }
        mach_vm_deallocate(mach_task_self_, (ulong)(nuint)list, (ulong)count * 4u);
        return found;
    }

    /// Keeps one reference to a thread port, so its name stays the thread's
    /// id, and gives back any other.
    void AdoptThreadReference(uint thread)
    {
        for (nuint i = 0u; i < _knownThreads.Count; i++)
        {
            if (_knownThreads[i] == thread)
            {
                mach_port_deallocate(mach_task_self_, thread);
                return;
            }
        }
        _knownThreads.Add(thread);
    }

    public bool CanRead(uint thread) => _running;

    public void Terminate()
    {
        if (_running && _pid > 0)
        {
            kill(_pid, SIGKILL);
            int status = 0;
            waitpid(_pid, &status, 0);
        }
        _running = false;
        ReleasePorts();
    }

    void ReleasePorts()
    {
        uint self = mach_task_self_;
        if (_portSet != MACH_PORT_NULL)
            mach_port_mod_refs(self, _portSet, MACH_PORT_RIGHT_PORT_SET, -1);
        if (_exceptions != MACH_PORT_NULL)
        {
            mach_port_mod_refs(self, _exceptions, MACH_PORT_RIGHT_RECEIVE, -1);
            mach_port_deallocate(self, _exceptions);
        }
        if (_interrupt != MACH_PORT_NULL)
        {
            mach_port_mod_refs(self, _interrupt, MACH_PORT_RIGHT_RECEIVE, -1);
            mach_port_deallocate(self, _interrupt);
        }
        for (nuint i = 0u; i < _knownThreads.Count; i++)
            mach_port_deallocate(self, _knownThreads[i]);
        if (_task != MACH_PORT_NULL)
            mach_port_deallocate(self, _task);

        _portSet = MACH_PORT_NULL;
        _exceptions = MACH_PORT_NULL;
        _interrupt = MACH_PORT_NULL;
        _task = MACH_PORT_NULL;
        _knownThreads.Clear();
    }
}

/// Where the kernel mapped the executable: the region that begins with a
/// 64-bit Mach header of type `MH_EXECUTE`.
///
/// Read before dyld has run, when the only other image mapped is dyld itself,
/// whose header says `MH_DYLINKER`.
nuint FindExecutableBase(uint task)
{
    ulong at = 0u;
    for (int guard = 0; guard < 4096; guard++)
    {
        ulong size = 0u;
        int[] info = new int[VM_REGION_BASIC_INFO_COUNT_64];
        uint count = VM_REGION_BASIC_INFO_COUNT_64;
        uint objectName = MACH_PORT_NULL;
        if (mach_vm_region(task, &at, &size, VM_REGION_BASIC_INFO_64, &info[0u], &count,
                           &objectName) != KERN_SUCCESS)
            return 0u;
        if (objectName != MACH_PORT_NULL)
            mach_port_deallocate(mach_task_self_, objectName);

        uint[] header = new uint[4];
        ulong read = 0u;
        if (mach_vm_read_overwrite(task, at, 16u, (ulong)(nuint)&header[0u], &read) == KERN_SUCCESS
            && read == 16u && header[0u] == MachMagic64 && header[3u] == 2u)
            return (nuint)at;

        at += size;
    }
    return 0u;
}

/// The exit code `waitpid` reported, or -1 for a program killed by a signal.
int DescribeWaitStatus(int status)
{
    if ((status & 0x7F) == 0)
        return (status >> 8) & 0xFF;
    return -1;
}

/// Arguments split at spaces. No quoting: what sldb and the IDE pass is a
/// list of words.
List<String> SplitArguments(String arguments)
{
    var words = new List<String>();
    nuint length = arguments.ByteLength();
    nuint start = 0u;
    for (nuint i = 0u; i <= length; i++)
    {
        if (i == length || arguments.GetByteAt(i) == (byte)32)
        {
            if (i > start)
                words.Add(arguments.Substring(start, i - start));
            start = i + 1u;
        }
    }
    return words;
}

#endif
