# Linux bindings

The Linux system call interface, declared and nothing else.

```
bindings/linux/api/
  Sockets.sl     module Linux.Sockets;    socket, bind, listen, accept,
                                          connect, send, recv, poll, select,
                                          getaddrinfo, and the constants
```

Same rules as [the Win32 bindings](../win32/README.md): a binding is a
declaration, not a wrapper. `struct sockaddr_in` is a Stainless `struct` with
the same fields in the same order — `sizeof` returns 16, as it does in C — and
`poll` is `poll`. Nothing is generated and nothing is marshalled, because
Stainless already speaks the platform C ABI.

Nothing here needs a `-l`. Sockets are in libc on Linux, which every program
already links.

## Why `Linux` and not `Posix`

The *functions* are POSIX and would be the same on macOS and the BSDs. The
*numbers* are not:

| | Linux | Windows | macOS |
|---|---|---|---|
| `AF_INET6` | 10 | 23 | 30 |
| `SOL_SOCKET` | 1 | 0xFFFF | 0xFFFF |
| `SO_REUSEADDR` | 2 | 4 | 4 |
| `SO_BROADCAST` | 6 | 32 | 32 |
| `SO_RCVTIMEO` | 20 | 4102 | 4102 |
| `NI_NUMERICHOST` | 1 | 2 | 1 |
| `IPV6_V6ONLY` | 26 | 27 | 27 |

A file that claimed to be POSIX would have to be wrong on two platforms out of
three. So this one says `#if LINUX`, and means the x86-64 glibc numbers.
Porting it is a matter of the constants and not of the calls, which is the
useful thing to know about it.

## What is verified, and how

[tests/cases/linux-sockets](../../tests/cases/linux-sockets) compiles a C file
beside the Stainless one, has it return what the headers actually say, and
compares every constant, every `sizeof` and two `offsetof`s against the
binding. A constant in a binding is either the header's number or a bug that
shows up on a Tuesday, and there is no way to tell by reading it.

The offsets are there for one specific trap. `struct addrinfo` has
`ai_addr` before `ai_canonname` on Linux and the other way round on Windows,
and both orders give a struct of exactly the same size — so a header copied
from the wrong platform passes every size check and then dereferences a string
as a pointer.

The same case was found to be worth having immediately: the Windows one caught
`FIONBIO` declared with the signed reading of its bit pattern rather than the
unsigned one the header produces.

## What this is not

`Standard.Net` does not go through this file. The standard library is compiled
with every program and the bindings are not, so the cross-platform wrapper goes
through `runtime/socket.c` instead — which is C, and gets to use `#ifdef`.

That is a deliberate split rather than a duplication. This file is for a
program that wants Linux's sockets, including the parts that are only Linux's:
`SO_REUSEPORT`, `accept4`, `SOCK_NONBLOCK`, `socketpair`, `MSG_NOSIGNAL`. None
of those has a Windows equivalent, so none of them can be in a wrapper that
claims to work on both.

## The terminal

```
bindings/linux/
  api/Termios.sl   module Linux.Termios;   struct termios, tcgetattr,
                                           tcsetattr, ioctl, winsize, isatty
  api/Events.sl    module Linux.Events;    epoll, eventfd, timerfd, inotify
  Terminal.sl      module Linux.Terminal;  raw mode, the size, the cursor,
                                           colour
```

`Standard.Console` writes text and is what a program should use for that.
`Linux.Terminal` is for the things that are not writing text — reading a key
without waiting for Enter, asking how wide the window is, moving the cursor.

It is called `Terminal` rather than `Console` for the reason the Win32 one is:
a module is reached by its last name segment, so a `Linux.Console` would shadow
`Standard.Console` in every file that imported it, and a program doing terminal
work is exactly the program that also wants to print.

**Colour is ANSI escapes, not calls.** Every terminal Linux has spoken to in
thirty years understands them, so there is nothing to bind: the sequences are
written to the output like any other text. What needs binding is the *state* —
raw mode and the size — which is `termios` and `ioctl`.

**Ask `IsTerminal()` first.** Writing escapes into a pipe puts them in the file.
That is the same rule the Win32 module states, reached from the other
direction: there, every console call simply fails when the output is redirected.

**Put the terminal back.** A program that leaves it in raw mode leaves the
shell it returns to unusable — no echo, no line editing, Ctrl-C doing nothing.
`Mode` restores in its destructor, so letting it go out of scope is enough.

## The event loop

`epoll`, `eventfd`, `timerfd` and `inotify` have no counterpart on Windows and
no POSIX equivalent worth the name — `poll` is in `Sockets.sl` and is what
POSIX has.

**Everything is a file descriptor.** A timer is a descriptor that becomes
readable when it fires; a wakeup from another thread is a descriptor that
becomes readable when somebody writes to it; a file change is a descriptor that
becomes readable when the file changes. So one `epoll_wait` covers sockets,
files, timers and other threads together, which is why a Linux program needs no
separate mechanism for each.

## Checked against the headers, not the documentation

Every struct size, offset and constant in these files was printed from the real
header on the machine before it was written down:

```sh
printf '#include <termios.h>\n#include <stdio.h>\nint main(void){printf("%%zu\n", sizeof(struct termios));}' > /tmp/c.c
clang /tmp/c.c -o /tmp/c && /tmp/c
```

`sizeof(termios)` is 60 and `struct epoll_event` is 12 — the second because it
is **packed on x86-64**, which a natural layout would get wrong by four bytes
and hand the kernel a struct it reads the wrong fields out of. `tests/cases/
linux-terminal` asserts both, so a change that breaks one fails rather than
misbehaves.
