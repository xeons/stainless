// SPDX-License-Identifier: 0BSD

// kqueue: one wait for everything a program can be woken by.
//
// What Linux spreads over four kinds of descriptor -- epoll for the wait,
// eventfd for a wakeup, timerfd for a timer, inotify for a file -- is one call
// here, told apart by its filter:
//
//   - **`EVFILT_READ` and `EVFILT_WRITE`** are epoll's readable and writable.
//   - **`EVFILT_USER`** is eventfd: an event with no descriptor behind it,
//     which another thread fires with `NOTE_TRIGGER`.
//   - **`EVFILT_TIMER`** is timerfd, with the period in the event's `data`.
//   - **`EVFILT_VNODE`** is inotify for one file or directory, opened with
//     `O_EVTONLY` so that watching it does not keep a volume from unmounting.
//
// One call both changes what is watched and waits: `kevent` takes a list of
// changes and a buffer for what happened, either of which may be empty.
module MacOS.Events;

#if MACOS

// ================================================================== filters

/// What an event is about. Negative, which is how kqueue keeps them apart
/// from the descriptors an `ident` usually is.
public const short EVFILT_READ = -1;
public const short EVFILT_WRITE = -2;
public const short EVFILT_VNODE = -4;
public const short EVFILT_PROC = -5;
public const short EVFILT_SIGNAL = -6;
public const short EVFILT_TIMER = -7;
public const short EVFILT_USER = -10;

// ==================================================================== flags

/// What to do with an entry, in a change; what happened to it, in a result.
public const ushort EV_ADD = 0x0001;
public const ushort EV_DELETE = 0x0002;
public const ushort EV_ENABLE = 0x0004;
public const ushort EV_DISABLE = 0x0008;

/// Report once and remove the entry.
public const ushort EV_ONESHOT = 0x0010;

/// Reset the state after it is reported, which is what makes a user event or
/// a vnode event fire again rather than every time after.
public const ushort EV_CLEAR = 0x0020;

/// Report once and disable the entry, which is how work is handed to one
/// thread out of several without two of them taking it.
public const ushort EV_DISPATCH = 0x0080;

/// In a result: the change failed, and `data` is the errno.
public const ushort EV_ERROR = 0x4000;

/// In a result: the other end closed, or the file reached its end.
public const ushort EV_EOF = 0x8000;

// ============================================================ filter flags

/// `EVFILT_USER`: fire the event. Written into `fflags` of a change.
public const uint NOTE_TRIGGER = 0x01000000u;

/// `EVFILT_TIMER`: the unit of `data`. Milliseconds when none is given.
public const uint NOTE_SECONDS = 0x00000001u;
public const uint NOTE_USECONDS = 0x00000002u;
public const uint NOTE_NSECONDS = 0x00000004u;

/// `EVFILT_VNODE`: what to watch for. A bit set, the same one that comes back.
public const uint NOTE_DELETE = 0x00000001u;
public const uint NOTE_WRITE = 0x00000002u;
public const uint NOTE_EXTEND = 0x00000004u;
public const uint NOTE_ATTRIB = 0x00000008u;
public const uint NOTE_LINK = 0x00000010u;
public const uint NOTE_RENAME = 0x00000020u;
public const uint NOTE_REVOKE = 0x00000040u;

/// Everything an editor saving a file does: written, grown, deleted, renamed.
public const uint NOTE_ALL_EDITS = 0x00000027u;

/// `open` for watching only: the file can be watched but not read, and the
/// watch does not keep its volume from being unmounted.
public const int O_EVTONLY = 0x8000;

/// `O_CLOEXEC`, for `open` and `kqueue` alike to not reach a child.
public const int O_CLOEXEC = 0x01000000;

/// `struct kevent`: 32 bytes, as Apple lays it out on both of its 64-bit
/// targets.
public struct kevent_t
{
    /// A descriptor for most filters; anything the program likes for a user
    /// event or a timer, which comes back to say which one fired.
    public nuint ident;
    public short filter;
    public ushort flags;
    public uint fflags;

    /// A count of bytes, a timer's period, or an errno: the filter decides.
    public nint data;

    /// Whatever the program put here, handed back unchanged.
    public void* udata;
}

/// `struct timespec`.
public struct timespec
{
    public long tv_sec;
    public long tv_nsec;
}

// ================================================================ the calls

public extern "C"
{
    /// A queue to wait on. Close it like any descriptor.
    int kqueue();

    /// Applies `changes` and then waits for up to `most` events, for at most
    /// `timeout` -- null to wait for ever, zero to look and return. Answers how
    /// many events were written, 0 on a timeout, and -1 with `EINTR` when a
    /// signal arrived, which is not an error.
    int kevent(int kq, kevent_t* changes, int changeCount, kevent_t* events, int most,
               timespec* timeout);

    /// Variadic in C, and on Apple silicon a variadic argument travels on the
    /// stack rather than in a register: declared as anything else, the mode
    /// would be read from wherever the stack happened to point.
    int open(byte* path, int flags, ...);

    /// The same read, write and close every descriptor uses.
    nint read(int fd, void* buffer, nuint count);
    nint write(int fd, void* buffer, nuint count);
    int close(int fd);

    /// Where Darwin keeps this thread's `errno`.
    int* __error();
}

/// `errno`, which every call above reports through rather than returning.
public int GetErrno() => *__error();

/// A wait that a signal interrupted. Not an error: ask again.
public const int EINTR = 4;

/// Nothing was there, on a descriptor that was asked not to wait.
public const int EAGAIN = 35;

#endif
