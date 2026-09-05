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
