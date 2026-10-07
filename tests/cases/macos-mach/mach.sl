// SPDX-License-Identifier: 0BSD
//
// The Mach binding sldb debugs through, measured against Darwin's headers and
// then used on this process's own task, which needs no entitlement.
//
// A misfiled constant here is a debugger that waits for a message it never
// asked for, or writes a register into the wrong slot of a thread state.
module MacMach;

import Standard.Console;
import MacOS.Mach;

extern "C"
{
    long probe_kern_success();
    long probe_right_receive();
    long probe_right_port_set();
    long probe_move_send_once();
    long probe_copy_send();
    long probe_make_send();
    long probe_send_msg();
    long probe_rcv_msg();
    long probe_send_timeout();
    long probe_rcv_timeout();
    long probe_rcv_timed_out();
    long probe_sizeof_header();
    long probe_offset_msgh_id();
    long probe_exc_bad_access();
    long probe_exc_bad_instruction();
    long probe_exc_arithmetic();
    long probe_exc_breakpoint();
    long probe_mask_bad_access();
    long probe_mask_bad_instruction();
    long probe_mask_arithmetic();
    long probe_mask_breakpoint();
    long probe_default_64();
    long probe_prot_read();
    long probe_prot_write();
    long probe_prot_execute();
    long probe_prot_copy();
    long probe_region_basic_64();
    long probe_region_basic_count_64();
    long probe_mattr_cache();
    long probe_mattr_flush();
    long probe_start_suspended();
    long probe_sigkill();
    long probe_wnohang();
#if ARM64
    long probe_thread_state64();
    long probe_debug_state64();
    long probe_state_none();
    long probe_sizeof_thread_state();
    long probe_offset_pc();
    long probe_thread_state_count();
    long probe_sizeof_debug_state();
    long probe_offset_mdscr();
    long probe_debug_state_count();
#endif
}

/// Zero when the binding agrees with the header, and one when it does not.
int Check(String name, long bound, long header)
{
    if (bound == header)
        return 0;
    Console.WriteLine($"{name}: the binding says {bound}, the header says {header}");
    return 1;
}

int CheckConstants()
{
    int wrong = 0;
    wrong += Check("KERN_SUCCESS", (long)KERN_SUCCESS, probe_kern_success());
    wrong += Check("MACH_PORT_RIGHT_RECEIVE", (long)MACH_PORT_RIGHT_RECEIVE, probe_right_receive());
    wrong += Check("MACH_PORT_RIGHT_PORT_SET", (long)MACH_PORT_RIGHT_PORT_SET, probe_right_port_set());
    wrong += Check("MACH_MSG_TYPE_MOVE_SEND_ONCE", (long)MACH_MSG_TYPE_MOVE_SEND_ONCE, probe_move_send_once());
    wrong += Check("MACH_MSG_TYPE_COPY_SEND", (long)MACH_MSG_TYPE_COPY_SEND, probe_copy_send());
    wrong += Check("MACH_MSG_TYPE_MAKE_SEND", (long)MACH_MSG_TYPE_MAKE_SEND, probe_make_send());
    wrong += Check("MACH_SEND_MSG", (long)MACH_SEND_MSG, probe_send_msg());
    wrong += Check("MACH_RCV_MSG", (long)MACH_RCV_MSG, probe_rcv_msg());
    wrong += Check("MACH_SEND_TIMEOUT", (long)MACH_SEND_TIMEOUT, probe_send_timeout());
    wrong += Check("MACH_RCV_TIMEOUT", (long)MACH_RCV_TIMEOUT, probe_rcv_timeout());
    wrong += Check("MACH_RCV_TIMED_OUT", (long)MACH_RCV_TIMED_OUT, probe_rcv_timed_out());
    wrong += Check("sizeof(mach_msg_header_t)", (long)sizeof(mach_msg_header_t), probe_sizeof_header());
    wrong += Check("offsetof(mach_msg_header_t, msgh_id)",
                   (long)offsetof(mach_msg_header_t, msgh_id), probe_offset_msgh_id());
    wrong += Check("EXC_BAD_ACCESS", (long)EXC_BAD_ACCESS, probe_exc_bad_access());
    wrong += Check("EXC_BAD_INSTRUCTION", (long)EXC_BAD_INSTRUCTION, probe_exc_bad_instruction());
    wrong += Check("EXC_ARITHMETIC", (long)EXC_ARITHMETIC, probe_exc_arithmetic());
    wrong += Check("EXC_BREAKPOINT", (long)EXC_BREAKPOINT, probe_exc_breakpoint());
    wrong += Check("EXC_MASK_BAD_ACCESS", (long)EXC_MASK_BAD_ACCESS, probe_mask_bad_access());
    wrong += Check("EXC_MASK_BAD_INSTRUCTION", (long)EXC_MASK_BAD_INSTRUCTION,
                   probe_mask_bad_instruction());
    wrong += Check("EXC_MASK_ARITHMETIC", (long)EXC_MASK_ARITHMETIC, probe_mask_arithmetic());
    wrong += Check("EXC_MASK_BREAKPOINT", (long)EXC_MASK_BREAKPOINT, probe_mask_breakpoint());
    wrong += Check("EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES", (long)EXCEPTION_DEFAULT_64,
                   probe_default_64());
    wrong += Check("VM_PROT_READ", (long)VM_PROT_READ, probe_prot_read());
    wrong += Check("VM_PROT_WRITE", (long)VM_PROT_WRITE, probe_prot_write());
    wrong += Check("VM_PROT_EXECUTE", (long)VM_PROT_EXECUTE, probe_prot_execute());
    wrong += Check("VM_PROT_COPY", (long)VM_PROT_COPY, probe_prot_copy());
    wrong += Check("VM_REGION_BASIC_INFO_64", (long)VM_REGION_BASIC_INFO_64, probe_region_basic_64());
    wrong += Check("VM_REGION_BASIC_INFO_COUNT_64", (long)VM_REGION_BASIC_INFO_COUNT_64,
                   probe_region_basic_count_64());
    wrong += Check("MATTR_CACHE", (long)MATTR_CACHE, probe_mattr_cache());
    wrong += Check("MATTR_VAL_CACHE_FLUSH", (long)MATTR_VAL_CACHE_FLUSH, probe_mattr_flush());
    wrong += Check("POSIX_SPAWN_START_SUSPENDED", (long)POSIX_SPAWN_START_SUSPENDED,
                   probe_start_suspended());
    wrong += Check("SIGKILL", (long)SIGKILL, probe_sigkill());
    wrong += Check("WNOHANG", (long)WNOHANG, probe_wnohang());
#if ARM64
    wrong += Check("ARM_THREAD_STATE64", (long)ARM_THREAD_STATE64, probe_thread_state64());
    wrong += Check("ARM_DEBUG_STATE64", (long)ARM_DEBUG_STATE64, probe_debug_state64());
    wrong += Check("THREAD_STATE_NONE", (long)THREAD_STATE_NONE, probe_state_none());
    wrong += Check("sizeof(arm_thread_state64_t)", (long)sizeof(arm_thread_state64_t),
                   probe_sizeof_thread_state());
    wrong += Check("offsetof(arm_thread_state64_t, pc)", (long)offsetof(arm_thread_state64_t, pc),
                   probe_offset_pc());
    wrong += Check("ARM_THREAD_STATE64_COUNT", (long)ARM_THREAD_STATE64_COUNT,
                   probe_thread_state_count());
    wrong += Check("sizeof(arm_debug_state64_t)", (long)sizeof(arm_debug_state64_t),
                   probe_sizeof_debug_state());
    wrong += Check("offsetof(arm_debug_state64_t, mdscr_el1)",
                   (long)offsetof(arm_debug_state64_t, mdscr_el1), probe_offset_mdscr());
    wrong += Check("ARM_DEBUG_STATE64_COUNT", (long)ARM_DEBUG_STATE64_COUNT,
                   probe_debug_state_count());
#endif
    return wrong;
}

/// A message to a port of this task's own, then a wait that finds nothing.
void SendToSelf()
{
    uint self = mach_task_self_;
    uint port = MACH_PORT_NULL;
    bool made = mach_port_allocate(self, MACH_PORT_RIGHT_RECEIVE, &port) == KERN_SUCCESS
             && mach_port_insert_right(self, port, port, MACH_MSG_TYPE_MAKE_SEND) == KERN_SUCCESS;

    mach_msg_header_t sent;
    sent.msgh_bits = MACH_MSG_TYPE_COPY_SEND;
    sent.msgh_size = (uint)sizeof(mach_msg_header_t);
    sent.msgh_remote_port = port;
    sent.msgh_local_port = MACH_PORT_NULL;
    sent.msgh_voucher_port = MACH_PORT_NULL;
    sent.msgh_id = 4242;
    bool delivered = mach_msg(&sent, MACH_SEND_MSG | MACH_SEND_TIMEOUT, sent.msgh_size, 0u,
                              MACH_PORT_NULL, 0u, MACH_PORT_NULL) == KERN_SUCCESS;

    byte[] buffer = new byte[256];
    var received = (mach_msg_header_t*)&buffer[0u];
    bool arrived = mach_msg(received, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0u, 256u, port, 1000u,
                            MACH_PORT_NULL) == KERN_SUCCESS;
    Console.WriteLine($"message  made {made} sent {delivered} received {arrived} id {received->msgh_id}");

    int nothing = mach_msg(received, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0u, 256u, port, 10u,
                           MACH_PORT_NULL);
    Console.WriteLine($"empty    timed out {nothing == MACH_RCV_TIMED_OUT}");

    mach_port_mod_refs(self, port, MACH_PORT_RIGHT_RECEIVE, -1);
    mach_port_deallocate(self, port);
}

/// This program's own image, found the way sldb finds a debuggee's.
bool FindOwnExecutable()
{
    uint self = mach_task_self_;
    ulong at = 0u;
    for (int guard = 0; guard < 4096; guard++)
    {
        ulong size = 0u;
        int[] info = new int[VM_REGION_BASIC_INFO_COUNT_64];
        uint count = VM_REGION_BASIC_INFO_COUNT_64;
        uint objectName = MACH_PORT_NULL;
        if (mach_vm_region(self, &at, &size, VM_REGION_BASIC_INFO_64, &info[0u], &count,
                           &objectName) != KERN_SUCCESS)
            return false;

        uint[] header = new uint[4];
        ulong read = 0u;
        if (mach_vm_read_overwrite(self, at, 16u, (ulong)(nuint)&header[0u], &read) == KERN_SUCCESS
            && read == 16u && header[0u] == 0xFEEDFACFu && header[3u] == 2u)
            return (info[0u] & VM_PROT_EXECUTE) != 0;
        at += size;
    }
    return false;
}

public int Main()
{
    Console.WriteLine($"constants and layouts that disagree with the headers: {CheckConstants()}");

    SendToSelf();
    Console.WriteLine($"image    executable {FindOwnExecutable()}");

    int value = 1234;
    int copy = 0;
    ulong read = 0u;
    bool copied = mach_vm_read_overwrite(mach_task_self_, (ulong)(nuint)&value, 4u,
                                         (ulong)(nuint)&copy, &read) == KERN_SUCCESS;
    Console.WriteLine($"read     {copied} {copy}");

    uint* threads = null;
    uint counted = 0u;
    bool listed = task_threads(mach_task_self_, &threads, &counted) == KERN_SUCCESS;
    Console.WriteLine($"threads  {listed && counted >= 1u}");
    if (listed)
    {
        for (uint i = 0u; i < counted; i++)
            mach_port_deallocate(mach_task_self_, threads[i]);
        mach_vm_deallocate(mach_task_self_, (ulong)(nuint)threads, (ulong)counted * 4u);
    }
    return 0;
}
