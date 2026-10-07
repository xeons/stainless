// SPDX-License-Identifier: 0BSD

// Mach tasks, threads, memory and exception ports: what a debugger controls a
// process through on macOS.
//
// `ptrace` on macOS stops and starts a process and does nothing else. Memory,
// registers and breakpoints all go through the task port, which
// `task_for_pid` hands only to a caller signed with
// `com.apple.security.cs.debugger` and authorized by
// `system.privilege.taskport`.
//
// Every port here is a name in this task's space, a `uint`. A call that
// answers one adds a reference, which `mach_port_deallocate` gives back.
//
// Structures whose C layout is `#pragma pack(4)` with 64-bit members, such as
// `vm_region_basic_info_64` and the exception message, are read as words
// rather than declared.
module MacOS.Mach;

#if MACOS

// ============================================================ ports

/// This task's own port. `mach_task_self()` is a macro reading it.
public extern "C" uint mach_task_self_;

public const int KERN_SUCCESS = 0;

public const uint MACH_PORT_NULL = 0u;
public const uint MACH_PORT_RIGHT_RECEIVE = 1u;
public const uint MACH_PORT_RIGHT_PORT_SET = 3u;

public const uint MACH_MSG_TYPE_MOVE_SEND_ONCE = 18u;
public const uint MACH_MSG_TYPE_COPY_SEND = 19u;
public const uint MACH_MSG_TYPE_MAKE_SEND = 20u;

// ========================================================= messages

public const int MACH_SEND_MSG = 0x00000001;
public const int MACH_RCV_MSG = 0x00000002;
public const int MACH_SEND_TIMEOUT = 0x00000010;
public const int MACH_RCV_TIMEOUT = 0x00000100;

/// What `mach_msg` answers when a receive with a timeout found nothing.
public const int MACH_RCV_TIMED_OUT = 0x10004003;

/// `mach_msg_header_t`.
public struct mach_msg_header_t
{
    public uint msgh_bits;
    public uint msgh_size;
    public uint msgh_remote_port;
    public uint msgh_local_port;
    public uint msgh_voucher_port;
    public int msgh_id;
}

// ======================================================= exceptions

public const int EXC_BAD_ACCESS = 1;
public const int EXC_BAD_INSTRUCTION = 2;
public const int EXC_ARITHMETIC = 3;
public const int EXC_BREAKPOINT = 6;

public const uint EXC_MASK_BAD_ACCESS = 1u << EXC_BAD_ACCESS;
public const uint EXC_MASK_BAD_INSTRUCTION = 1u << EXC_BAD_INSTRUCTION;
public const uint EXC_MASK_ARITHMETIC = 1u << EXC_ARITHMETIC;
public const uint EXC_MASK_BREAKPOINT = 1u << EXC_BREAKPOINT;

public const int EXCEPTION_DEFAULT = 1;
public const int MACH_EXCEPTION_CODES = (int)0x80000000u;

/// A `mach_exception_raise` message, with 64-bit codes.
public const int EXCEPTION_DEFAULT_64 = EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES;

/// `mach_exception_raise`, and its reply, which is the request's id plus 100.
public const int MACH_EXCEPTION_RAISE_ID = 2405;
public const int MACH_EXCEPTION_REPLY_ID = 2505;

// ===================================================== thread state

public const int ARM_THREAD_STATE64 = 6;
public const int ARM_DEBUG_STATE64 = 15;
public const int THREAD_STATE_NONE = 5;

/// `arm_thread_state64_t`, as an arm64 process sees an arm64 one.
public struct arm_thread_state64_t
{
    public ulong[29] x;
    public ulong fp;
    public ulong lr;
    public ulong sp;
    public ulong pc;
    public uint cpsr;
    public uint flags;
}

public const uint ARM_THREAD_STATE64_COUNT = 68u;

/// `arm_debug_state64_t`. Bit 0 of `mdscr_el1` is single step.
public struct arm_debug_state64_t
{
    public ulong[16] bvr;
    public ulong[16] bcr;
    public ulong[16] wvr;
    public ulong[16] wcr;
    public ulong mdscr_el1;
}

public const uint ARM_DEBUG_STATE64_COUNT = 130u;
public const ulong MDSCR_SS = 1u;

// =========================================================== memory

public const int VM_PROT_READ = 0x01;
public const int VM_PROT_WRITE = 0x02;
public const int VM_PROT_EXECUTE = 0x04;

/// Write to a private copy of the page, which is how code is changed.
public const int VM_PROT_COPY = 0x10;

/// `VM_REGION_BASIC_INFO_64`. Its info is nine words; the first two are the
/// current and the maximum protection.
public const int VM_REGION_BASIC_INFO_64 = 9;
public const uint VM_REGION_BASIC_INFO_COUNT_64 = 9u;

public const uint MATTR_CACHE = 1u;
public const int MATTR_VAL_CACHE_FLUSH = 6;

// ========================================================== spawning

/// Darwin's own flag: the task is created suspended, before dyld runs.
public const short POSIX_SPAWN_START_SUSPENDED = 0x0080;

public const int SIGKILL = 9;
public const int WNOHANG = 1;

public extern "C"
{
    int task_for_pid(uint task, int pid, uint* target);
    int task_threads(uint task, uint** threads, uint* count);
    int task_suspend(uint task);
    int task_resume(uint task);
    int task_set_exception_ports(uint task, uint mask, uint port, int behavior, int flavor);

    int thread_suspend(uint thread);
    int thread_resume(uint thread);
    int thread_get_state(uint thread, int flavor, uint* state, uint* count);
    int thread_set_state(uint thread, int flavor, uint* state, uint count);

    int mach_vm_read_overwrite(uint task, ulong address, ulong size, ulong into, ulong* read);
    int mach_vm_write(uint task, ulong address, nuint data, uint count);
    int mach_vm_protect(uint task, ulong address, ulong size, int setMaximum, int protection);
    int mach_vm_region(uint task, ulong* address, ulong* size, int flavor, int* info,
                       uint* count, uint* objectName);
    int mach_vm_deallocate(uint task, ulong address, ulong size);
    int vm_machine_attribute(uint task, nuint address, nuint size, uint which, int* setting);

    int mach_port_allocate(uint space, uint right, uint* name);
    int mach_port_insert_right(uint space, uint name, uint port, uint disposition);
    int mach_port_move_member(uint space, uint member, uint after);
    int mach_port_mod_refs(uint space, uint name, uint right, int delta);
    int mach_port_deallocate(uint space, uint name);

    int mach_msg(mach_msg_header_t* message, int option, uint sendSize, uint receiveSize,
                 uint receiveName, uint timeout, uint notify);

    /// `posix_spawnattr_t` is a pointer on Darwin.
    int posix_spawnattr_init(void** attributes);
    int posix_spawnattr_setflags(void** attributes, short flags);
    int posix_spawnattr_destroy(void** attributes);
    int posix_spawn(int* pid, byte* path, void* fileActions, void** attributes,
                    byte** argv, byte** envp);

    /// The environment, as a program's own `environ` holds it.
    byte*** _NSGetEnviron();

    int waitpid(int pid, int* status, int options);
    int kill(int pid, int signal);
}

#endif
