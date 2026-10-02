# macOS bindings

The Darwin calls a terminal program and an event loop need, declared and
nothing else, with the same terminal module over them that `bindings/linux`
has.

```
bindings/macos/
  api/Termios.sl   module MacOS.Termios;   struct termios, tcgetattr,
                                           tcsetattr, ioctl, winsize, isatty
  api/Events.sl    module MacOS.Events;    kqueue, kevent, and the filters
  Terminal.sl      module MacOS.Terminal;  raw mode, the size, the cursor,
                                           colour
```

Same rules as [the Linux bindings](../linux/README.md): a binding is a
declaration, not a wrapper, and every file is `#if MACOS`. Nothing here needs
a `-l` or a framework; all of it is in libSystem.

## The terminal

`MacOS.Terminal` has the functions `Linux.Terminal` has, with the same names
and the same behaviour, so a program choosing between them needs an `#if` on
the import and nothing else. The layer under it is where they differ:

| | Linux | macOS |
|---|---|---|
| `tcflag_t`, `speed_t` | 4 bytes | 8 bytes |
| `NCCS` | 32 | 20 |
| `sizeof(struct termios)` | 60 | 72 |
| `ICANON` | 0x2 | 0x100 |
| `ECHO` | 0x8 | 0x8 |
| `ISIG` | 0x1 | 0x80 |
| `VMIN`, `VTIME` | 6, 5 | 16, 17 |
| `TIOCGWINSZ` | 0x5413 | 0x40087468 |

A `termios` copied from the other platform is wrong in every field after the
first, and `tcsetattr` takes it without complaint.

**`ioctl` is declared variadic, and MUST stay so.** On Apple silicon a variadic
argument travels on the stack rather than in a register; declared with a fixed
third parameter, the `winsize` pointer is read from wherever the stack points.
`open` in `Events.sl` is variadic for the same reason.

## The event loop

kqueue is one wait for what Linux spreads over four kinds of descriptor:

| Linux | macOS |
|---|---|
| `epoll` | `kqueue` and `kevent` |
| `eventfd` | `EVFILT_USER`, fired with `NOTE_TRIGGER` |
| `timerfd` | `EVFILT_TIMER`, the period in `data` |
| `inotify` | `EVFILT_VNODE`, on a file opened `O_EVTONLY` |

One `kevent` call both changes what is watched and waits. A user event or a
vnode event SHOULD be added with `EV_CLEAR`, or it reports again on every wait
after the first.

## What is verified, and how

[tests/cases/macos-terminal](../../tests/cases/macos-terminal) compiles a C
file that returns what Darwin's headers say and compares every constant, every
`sizeof` and the offsets that matter against the bindings, then runs a kqueue
with a user event, a timer and a watched file. It runs on macOS only.
