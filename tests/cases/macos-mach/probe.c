/*
 * What Darwin's headers say, so MacOS.Mach can be measured against them
 * rather than against anyone's memory.
 */

#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <signal.h>
#include <spawn.h>
#include <stddef.h>
#include <sys/wait.h>

long long probe_kern_success(void) { return KERN_SUCCESS; }
long long probe_right_receive(void) { return MACH_PORT_RIGHT_RECEIVE; }
long long probe_right_port_set(void) { return MACH_PORT_RIGHT_PORT_SET; }
long long probe_move_send_once(void) { return MACH_MSG_TYPE_MOVE_SEND_ONCE; }
long long probe_copy_send(void) { return MACH_MSG_TYPE_COPY_SEND; }
long long probe_make_send(void) { return MACH_MSG_TYPE_MAKE_SEND; }
long long probe_send_msg(void) { return MACH_SEND_MSG; }
long long probe_rcv_msg(void) { return MACH_RCV_MSG; }
long long probe_send_timeout(void) { return MACH_SEND_TIMEOUT; }
long long probe_rcv_timeout(void) { return MACH_RCV_TIMEOUT; }
long long probe_rcv_timed_out(void) { return MACH_RCV_TIMED_OUT; }
long long probe_sizeof_header(void) { return sizeof(mach_msg_header_t); }
long long probe_offset_msgh_id(void) { return offsetof(mach_msg_header_t, msgh_id); }

long long probe_exc_bad_access(void) { return EXC_BAD_ACCESS; }
long long probe_exc_bad_instruction(void) { return EXC_BAD_INSTRUCTION; }
long long probe_exc_arithmetic(void) { return EXC_ARITHMETIC; }
long long probe_exc_breakpoint(void) { return EXC_BREAKPOINT; }
long long probe_mask_bad_access(void) { return EXC_MASK_BAD_ACCESS; }
long long probe_mask_bad_instruction(void) { return EXC_MASK_BAD_INSTRUCTION; }
long long probe_mask_arithmetic(void) { return EXC_MASK_ARITHMETIC; }
long long probe_mask_breakpoint(void) { return EXC_MASK_BREAKPOINT; }
long long probe_default_64(void) { return (exception_behavior_t)(EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES); }

#if defined(__arm64__)
long long probe_thread_state64(void) { return ARM_THREAD_STATE64; }
long long probe_debug_state64(void) { return ARM_DEBUG_STATE64; }
long long probe_state_none(void) { return THREAD_STATE_NONE; }
long long probe_sizeof_thread_state(void) { return sizeof(arm_thread_state64_t); }
long long probe_offset_pc(void) { return offsetof(arm_thread_state64_t, __pc); }
long long probe_thread_state_count(void) { return ARM_THREAD_STATE64_COUNT; }
long long probe_sizeof_debug_state(void) { return sizeof(arm_debug_state64_t); }
long long probe_offset_mdscr(void) { return offsetof(arm_debug_state64_t, __mdscr_el1); }
long long probe_debug_state_count(void) { return ARM_DEBUG_STATE64_COUNT; }
#endif

long long probe_prot_read(void) { return VM_PROT_READ; }
long long probe_prot_write(void) { return VM_PROT_WRITE; }
long long probe_prot_execute(void) { return VM_PROT_EXECUTE; }
long long probe_prot_copy(void) { return VM_PROT_COPY; }
long long probe_region_basic_64(void) { return VM_REGION_BASIC_INFO_64; }
long long probe_region_basic_count_64(void) { return VM_REGION_BASIC_INFO_COUNT_64; }
long long probe_mattr_cache(void) { return MATTR_CACHE; }
long long probe_mattr_flush(void) { return MATTR_VAL_CACHE_FLUSH; }

long long probe_start_suspended(void) { return POSIX_SPAWN_START_SUSPENDED; }
long long probe_sigkill(void) { return SIGKILL; }
long long probe_wnohang(void) { return WNOHANG; }
