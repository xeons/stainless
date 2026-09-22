// SPDX-License-Identifier: 0BSD

// epoll, eventfd, timerfd, signalfd and inotify — declared and nothing else.
//
// These are the calls a Linux server loop is built out of, and they have no
// counterpart anywhere else: `poll` is POSIX and is in `Linux.Sockets`, but
// epoll is Linux's, and so is the trick the rest of this file is about.
//
// **Everything here is a file descriptor.** A timer is a descriptor that
// becomes readable when it fires; a signal is a descriptor that becomes
// readable when it arrives; a wakeup from another thread is a descriptor that
// becomes readable when somebody writes to it. So one epoll wait covers
// sockets, files, timers, signals and other threads together — which is the
// point, and is why a Linux program does not need a separate mechanism for
// each the way a Windows one does.
//
// **The values are x86-64 Linux's.** `struct epoll_event` is packed on x86 and
// not on other architectures, which is the sort of thing that makes this file
// Linux-on-amd64 rather than Linux.
module Linux.Events;

#if LINUX

// ==================================================================== epoll

/// What happened, or what to watch for. A bit set.
public const uint EPOLLIN     = 0x001u;   // readable
public const uint EPOLLPRI    = 0x002u;   // urgent data
public const uint EPOLLOUT    = 0x004u;   // writable
public const uint EPOLLERR    = 0x008u;   // an error — always reported
public const uint EPOLLHUP    = 0x010u;   // hung up — always reported
public const uint EPOLLRDHUP  = 0x2000u;  // the peer closed its writing half

/// Report only once per change rather than while the condition holds.
///
/// Faster and much easier to get wrong: with it, a reader that stops before
/// the buffer is empty is never told again. Level triggering is the default
/// and is what to use unless the difference has been measured.
public const uint EPOLLET     = 0x80000000u;

/// Report once and then disable the entry, which is how work is handed to one
/// thread out of several without two of them taking it.
public const uint EPOLLONESHOT = 0x40000000u;

public const int EPOLL_CTL_ADD = 1;
public const int EPOLL_CTL_DEL = 2;
public const int EPOLL_CTL_MOD = 3;

/// Close the epoll descriptor across an `exec`.
public const int EPOLL_CLOEXEC = 0x80000;

/// `struct epoll_event`.
///
/// **Packed on x86-64**, which is why this is `[Packed]` and not a plain
/// struct: the kernel expects 12 bytes, and a natural layout would put four
/// bytes of padding after `events` and hand the kernel a 16-byte struct it
/// reads the wrong fields out of.
[Packed]
public struct epoll_event
{
    public uint events;

    /// Whatever the program put there when it added the entry, handed back
    /// unchanged. A pointer or an index, and the only way to tell which
    /// descriptor woke up: the kernel does not send the descriptor back.
    public ulong data;
}

// ================================================================= eventfd

/// A counter in the kernel that a read empties and a write adds to.
///
/// The way one thread wakes another out of an epoll wait: the reader watches
/// it like any other descriptor, and the writer writes eight bytes to it.
public const int EFD_CLOEXEC   = 0x80000;
public const int EFD_NONBLOCK  = 0x800;

/// Count down by one per read rather than emptying, which makes it a
/// semaphore.
public const int EFD_SEMAPHORE = 1;

// ================================================================= timerfd

/// Which clock a timer counts on. `CLOCK_MONOTONIC` only goes forward, and is
/// the one to use for a delay; `CLOCK_REALTIME` can jump when the time is set.
public const int CLOCK_REALTIME  = 0;
public const int CLOCK_MONOTONIC = 1;

public const int TFD_CLOEXEC  = 0x80000;
public const int TFD_NONBLOCK = 0x800;

/// The time is absolute rather than a delay from now.
public const int TFD_TIMER_ABSTIME = 1;

/// `struct timespec`.
public struct timespec
{
    public long tv_sec;
    public long tv_nsec;
}

/// `struct itimerspec`. A first firing, and an interval to repeat at — an
/// interval of zero fires once.
public struct itimerspec
{
    public timespec it_interval;
    public timespec it_value;
}

// ================================================================= inotify

public const int IN_CLOEXEC  = 0x80000;
public const int IN_NONBLOCK = 0x800;

/// What to watch for. A bit set, the same one that comes back in an event.
public const uint IN_ACCESS        = 0x00000001u;
public const uint IN_MODIFY        = 0x00000002u;
public const uint IN_ATTRIB        = 0x00000004u;
public const uint IN_CLOSE_WRITE   = 0x00000008u;
public const uint IN_CLOSE_NOWRITE = 0x00000010u;
public const uint IN_OPEN          = 0x00000020u;
public const uint IN_MOVED_FROM    = 0x00000040u;
public const uint IN_MOVED_TO      = 0x00000080u;
public const uint IN_CREATE        = 0x00000100u;
public const uint IN_DELETE        = 0x00000200u;
public const uint IN_DELETE_SELF   = 0x00000400u;
public const uint IN_MOVE_SELF     = 0x00000800u;

/// Reported without being asked for: the watch went away by itself, or the
/// queue overflowed and events were lost.
public const uint IN_IGNORED  = 0x00008000u;
public const uint IN_Q_OVERFLOW = 0x00004000u;

/// The event is about a directory rather than a file inside it.
public const uint IN_ISDIR = 0x40000000u;

/// Everything an editor saving a file does, which is what a watcher usually
/// wants: written and closed, created, deleted, or renamed either way.
public const uint IN_ALL_EDITS = 0x000003C8u;

/// `struct inotify_event`, followed in the buffer by `len` bytes of name.
///
/// **The name is not in the struct.** A read answers with a run of these, each
/// followed by its own name, so walking the buffer means stepping by
/// `sizeof(inotify_event) + len` rather than by a fixed size. That is the one
/// thing about inotify that catches everybody.
public struct inotify_event
{
    public int wd;          // which watch, as add_watch answered
    public uint mask;        // what happened
    public uint cookie;      // pairs a MOVED_FROM with its MOVED_TO
    public uint len;         // bytes of name that follow, padding included
}

// ================================================================ the calls

public extern "C"
{
    /// Makes an epoll descriptor. `flags` is 0 or `EPOLL_CLOEXEC`; the older
    /// `epoll_create` took a size and ignored it.
    int epoll_create1(int flags);

    /// Adds, changes or removes an entry. `event` may be null for a delete.
    int epoll_ctl(int epfd, int operation, int fd, epoll_event* event);

    /// Waits. `timeout` is milliseconds, -1 to wait forever and 0 to look and
    /// return. Answers how many events were written, 0 on a timeout, and -1
    /// with `EINTR` when a signal arrived — which is not an error.
    int epoll_wait(int epfd, epoll_event* events, int most, int timeout);

    /// A counter to wake a waiter with. Read and write it eight bytes at a time.
    int eventfd(uint initial, int flags);

    /// A descriptor that becomes readable when the timer fires. Reading it
    /// answers with eight bytes: how many times it has fired since last read.
    int timerfd_create(int clock, int flags);
    int timerfd_settime(int fd, int flags, itimerspec* wanted, itimerspec* previous);
    int timerfd_gettime(int fd, itimerspec* current);

    /// A descriptor that becomes readable when a watched file changes.
    int inotify_init1(int flags);

    /// Watches a path. Answers a watch descriptor, which is what comes back in
    /// an event's `wd` -- not the path, which the program has to remember.
    int inotify_add_watch(int fd, byte* path, uint mask);
    int inotify_rm_watch(int fd, int wd);

    /// The same read, write and close every descriptor uses.
    nint read(int fd, void* buffer, nuint count);
    nint write(int fd, void* buffer, nuint count);
    int close(int fd);

    int* __errno_location();
}

/// `errno`, which every call above reports through rather than returning.
public int GetErrno() => *__errno_location();

/// A read or a wait that a signal interrupted. Not an error: ask again.
public const int EINTR = 4;

/// Nothing was there, on a descriptor that was asked not to wait.
public const int EAGAIN = 11;

#endif
