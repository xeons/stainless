// Stainless - an experimental systems language.
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

// The Linux socket API, declared and nothing else.
//
// This is a raw binding: entry points, structs and constants, with the names
// the headers give them, so that anything found in `man 2 socket` is here
// under the same spelling. The conveniences are `Standard.Net`, which does not
// go through this file -- it goes through runtime/socket.c, because the
// standard library is compiled with every program and the bindings are not.
//
// **Linux, and not POSIX in general.** The *functions* are POSIX and would be
// the same on macOS and the BSDs; the *numbers* are not. `AF_INET6` is 10
// here, 23 on Windows and 30 on macOS; `SOL_SOCKET` is 1 here, 0xFFFF on both
// of the others; every `SO_*` value differs. So this file says `#if LINUX` and
// means it, and the numbers below are x86-64 glibc's. Porting it is a matter
// of the constants, not the calls.
//
// Three things a Windows reader will trip over:
//
//   - **A socket is a file descriptor.** A small non-negative `int`, -1 on
//     failure, and `read`, `write`, `close`, `poll` and `select` all work on
//     one because it is a file.
//   - **Errors are `errno`.** Not a return value -- the call returns -1 and
//     `errno` says why. `__errno_location()` is where glibc keeps the
//     thread's copy, which is what the macro expands to.
//   - **A dead peer raises SIGPIPE.** Writing to a connection the other end
//     closed kills the process by default. `MSG_NOSIGNAL` on the send, or
//     ignoring the signal, is what stops it; there is no equivalent to forget
//     on Windows because Windows has no such signal.
module Linux.Sockets;

#if LINUX

// ================================================================= the types

/// A socket is a file descriptor: an `int`, and -1 when a call failed.
public using SOCKET = int;

/// `socklen_t`, which is 32 bits and unsigned. Windows uses a plain `int` for
/// the same parameter, which is why a shared declaration is not possible.
public using socklen_t = uint;

// ================================================================= addresses

/// `struct in_addr`. One IPv4 address, in network byte order.
public struct in_addr {
    public uint s_addr;
}

/// `struct in6_addr`. One IPv6 address, as sixteen bytes in order.
public struct in6_addr {
    public byte[16] s6_addr;
}

/// `struct sockaddr`. The base every address begins with, and never the whole
/// of one: what is really there is a `sockaddr_in` or a `sockaddr_in6`, and
/// `sa_family` says which.
public struct sockaddr {
    public ushort sa_family;
    public byte[14] sa_data;
}

/// `struct sockaddr_in`. `sin_port` and `sin_addr` are in network byte order.
public struct sockaddr_in {
    public ushort sin_family;
    public ushort sin_port;
    public in_addr sin_addr;
    public byte[8] sin_zero;
}

/// `struct sockaddr_in6`.
public struct sockaddr_in6 {
    public ushort sin6_family;
    public ushort sin6_port;
    public uint sin6_flowinfo;
    public in6_addr sin6_addr;
    public uint sin6_scope_id;
}

/// `struct sockaddr_storage`: big enough and aligned enough for either family,
/// which is what `accept` and `recvfrom` should be handed.
public struct sockaddr_storage {
    public ushort ss_family;
    public byte[6] __pad1;
    public long __align;
    public byte[112] __pad2;
}

/// `struct addrinfo`.
///
/// **The field order is not the same as Windows'.** glibc puts `ai_addr`
/// before `ai_canonname`; Windows puts `ai_canonname` first. A struct copied
/// from one header and used against the other reads the two through each
/// other, which is a dereference of a string and a print of a pointer.
/// `ai_addrlen` differs too: `socklen_t` here, `size_t` there.
public struct addrinfo {
    public int ai_flags;
    public int ai_family;
    public int ai_socktype;
    public int ai_protocol;
    public uint ai_addrlen;
    public sockaddr* ai_addr;
    public byte* ai_canonname;
    public addrinfo* ai_next;
}

/// `struct timeval`. Both fields are 64 bits on x86-64, where Windows' are 32.
public struct timeval {
    public long tv_sec;
    public long tv_usec;
}

/// `struct linger`, for `SO_LINGER`. Both fields are `int` here and `u_short`
/// on Windows.
public struct linger {
    public int l_onoff;
    public int l_linger;
}

/// `struct pollfd`.
public struct pollfd {
    public int fd;
    public short events;
    public short revents;
}

/// `fd_set`, which is a bitmask here and an array of handles on Windows --
/// so `FD_SETSIZE` limits how *large* a descriptor may be rather than how many
/// there may be, and a process with a high descriptor cannot use `select` at
/// all. `poll` has no such limit and is the one to reach for.
public struct fd_set {
    public long[16] fds_bits;
}

public const int FD_SETSIZE = 1024;

// ================================================================= families

public const int AF_UNSPEC = 0;
public const int AF_UNIX = 1;
public const int AF_INET = 2;
public const int AF_INET6 = 10;         // 10 on Linux, 23 on Windows, 30 on macOS
public const int AF_PACKET = 17;

public const int SOCK_STREAM = 1;
public const int SOCK_DGRAM = 2;
public const int SOCK_RAW = 3;
public const int SOCK_SEQPACKET = 5;

/// Linux lets `socket` and `accept4` take these in the type argument, which
/// saves an `fcntl` and closes the window between the two in a threaded
/// program.
public const int SOCK_NONBLOCK = 2048;
public const int SOCK_CLOEXEC = 524288;

public const int IPPROTO_IP = 0;
public const int IPPROTO_ICMP = 1;
public const int IPPROTO_TCP = 6;
public const int IPPROTO_UDP = 17;
public const int IPPROTO_IPV6 = 41;
public const int IPPROTO_ICMPV6 = 58;

/// In host order; `htonl` is what puts them on the wire.
public const uint INADDR_ANY = 0u;
public const uint INADDR_LOOPBACK = 2130706433u;        // 127.0.0.1
public const uint INADDR_BROADCAST = 4294967295u;
public const uint INADDR_NONE = 4294967295u;

// ============================================================ opening, closing

public extern "C" {
    int socket(int family, int kind, int protocol);

    /// Not `closesocket`: a socket is a file, and this is the same `close`
    /// that closes one.
    int close(int fd);

    int shutdown(int fd, int how);

    int bind(int fd, sockaddr* address, uint length);
    int listen(int fd, int backlog);
    int accept(int fd, sockaddr* address, uint* length);

    /// Linux's own, which sets `SOCK_NONBLOCK` or `SOCK_CLOEXEC` on the
    /// accepted socket without a second call.
    int accept4(int fd, sockaddr* address, uint* length, int flags);

    int connect(int fd, sockaddr* address, uint length);

    int getsockname(int fd, sockaddr* address, uint* length);
    int getpeername(int fd, sockaddr* address, uint* length);

    /// A connected pair with no address, which is how a parent and a child
    /// talk. Windows has nothing like it.
    int socketpair(int family, int kind, int protocol, int* fds);
}

public const int SHUT_RD = 0;
public const int SHUT_WR = 1;
public const int SHUT_RDWR = 2;

/// The queue length a listener asks for. 4096 on current Linux; it was 128
/// for a long time, and `/proc/sys/net/core/somaxconn` is the real ceiling.
public const int SOMAXCONN = 4096;

// ================================================================== transfer

public extern "C" {
    /// Return `ssize_t`, which is signed and pointer-sized: -1 for failure and
    /// a count otherwise. Windows returns `int` from the same four.
    long send(int fd, byte* data, nuint length, int flags);
    long recv(int fd, byte* data, nuint length, int flags);

    long sendto(int fd, byte* data, nuint length, int flags,
                sockaddr* to, uint toLength);
    long recvfrom(int fd, byte* data, nuint length, int flags,
                  sockaddr* from, uint* fromLength);

    /// A socket is a file, so these work on one too.
    long read(int fd, byte* data, nuint length);
    long write(int fd, byte* data, nuint length);
}

public const int MSG_OOB = 1;
public const int MSG_PEEK = 2;
public const int MSG_DONTROUTE = 4;
public const int MSG_TRUNC = 32;
public const int MSG_DONTWAIT = 64;
public const int MSG_WAITALL = 256;

/// Return `EPIPE` instead of raising `SIGPIPE`, which by default kills the
/// process. There is nothing to remember on Windows because Windows has no
/// such signal, which is exactly why this is the one that gets forgotten.
public const int MSG_NOSIGNAL = 16384;

// =================================================================== options

public extern "C" {
    int setsockopt(int fd, int level, int name, void* value, uint length);
    int getsockopt(int fd, int level, int name, void* value, uint* length);

    /// How a descriptor is made non-blocking: `F_GETFL`, then `F_SETFL` with
    /// `O_NONBLOCK` added. Windows uses `ioctlsocket(FIONBIO)` instead.
    int fcntl(int fd, int command, int argument);

    int ioctl(int fd, nuint request, void* argument);
}

public const int SOL_SOCKET = 1;        // 1 on Linux, 0xFFFF on Windows

public const int SO_DEBUG = 1;
public const int SO_REUSEADDR = 2;
public const int SO_TYPE = 3;
public const int SO_ERROR = 4;
public const int SO_DONTROUTE = 5;
public const int SO_BROADCAST = 6;
public const int SO_SNDBUF = 7;
public const int SO_RCVBUF = 8;
public const int SO_KEEPALIVE = 9;
public const int SO_OOBINLINE = 10;
public const int SO_LINGER = 13;

/// Linux's own: several sockets may listen on one port and the kernel spreads
/// connections between them, which is how a multi-process server accepts
/// without a lock. `SO_REUSEADDR` does not do this and never did.
public const int SO_REUSEPORT = 15;

public const int SO_RCVLOWAT = 18;
public const int SO_SNDLOWAT = 19;
public const int SO_RCVTIMEO = 20;
public const int SO_SNDTIMEO = 21;
public const int SO_ACCEPTCONN = 30;

public const int TCP_NODELAY = 1;
public const int TCP_MAXSEG = 2;
public const int TCP_CORK = 3;
public const int TCP_KEEPIDLE = 4;
public const int TCP_KEEPINTVL = 5;
public const int TCP_KEEPCNT = 6;

public const int IPV6_V6ONLY = 26;      // 26 on Linux, 27 on Windows
public const int IP_MULTICAST_TTL = 33;
public const int IP_ADD_MEMBERSHIP = 35;
public const int IP_DROP_MEMBERSHIP = 36;

public const int F_GETFL = 3;
public const int F_SETFL = 4;
public const int O_NONBLOCK = 2048;

// ==================================================================== waiting

public extern "C" {
    /// The one to use. `select` has the `FD_SETSIZE` ceiling and this does
    /// not; a negative timeout waits forever.
    int poll(pollfd* entries, nuint count, int milliseconds);

    /// `nfds` is the highest descriptor plus one, and is not ignored here the
    /// way Windows ignores it.
    int select(int nfds, fd_set* readable, fd_set* writable, fd_set* failed,
               timeval* timeout);
}

public const short POLLIN = 1;
public const short POLLPRI = 2;
public const short POLLOUT = 4;
public const short POLLERR = 8;
public const short POLLHUP = 16;
public const short POLLNVAL = 32;
public const short POLLRDNORM = 64;
public const short POLLRDBAND = 128;
public const short POLLWRNORM = 256;
public const short POLLWRBAND = 512;

// ================================================================== byte order

public extern "C" {
    ushort htons(ushort value);
    ushort ntohs(ushort value);
    uint htonl(uint value);
    uint ntohl(uint value);
}

// ==================================================================== names

public extern "C" {
    /// Both `node` and `service` may be null, and one of them must not be.
    /// The result is a chain: walk `ai_next` and try each, because a host with
    /// both an A and an AAAA record may only be reachable through one.
    int getaddrinfo(byte* node, byte* service, addrinfo* hints, addrinfo** result);
    void freeaddrinfo(addrinfo* list);

    /// What an `EAI_` code means. Not `strerror`: the two number spaces are
    /// unrelated, and `EAI_SYSTEM` is the one that says to look at `errno`.
    byte* gai_strerror(int code);

    int getnameinfo(sockaddr* address, uint addressLength, byte* host, uint hostLength,
                    byte* service, uint serviceLength, int flags);

    int gethostname(byte* name, nuint length);

    int inet_pton(int family, byte* text, void* address);
    byte* inet_ntop(int family, void* address, byte* text, uint size);
}

public const int AI_PASSIVE = 1;
public const int AI_CANONNAME = 2;
public const int AI_NUMERICHOST = 4;
public const int AI_V4MAPPED = 8;
public const int AI_ALL = 16;
public const int AI_ADDRCONFIG = 32;
public const int AI_NUMERICSERV = 1024;

/// **Not the same numbers as Windows'**, which has `NI_NUMERICHOST` as 2 and
/// `NI_NUMERICSERV` as 8. Passing one platform's flags to the other's
/// `getnameinfo` asks a different question and gets a plausible wrong answer.
public const int NI_NUMERICHOST = 1;
public const int NI_NUMERICSERV = 2;
public const int NI_NOFQDN = 4;
public const int NI_NAMEREQD = 8;
public const int NI_DGRAM = 16;

public const int NI_MAXHOST = 1025;
public const int NI_MAXSERV = 32;

public const int EAI_BADFLAGS = -1;
public const int EAI_NONAME = -2;
public const int EAI_AGAIN = -3;
public const int EAI_FAIL = -4;
public const int EAI_FAMILY = -6;
public const int EAI_SOCKTYPE = -7;
public const int EAI_SERVICE = -8;
public const int EAI_MEMORY = -10;

/// The one that means "the reason is in `errno`", which is why a program that
/// prints only `gai_strerror` sometimes prints nothing useful.
public const int EAI_SYSTEM = -11;

public const int EAI_OVERFLOW = -12;

// =================================================================== errno

public extern "C" {
    /// Where glibc keeps this thread's `errno`. The macro `errno` expands to
    /// `*__errno_location()`, and this is the function under it.
    int* __errno_location();
}

/// This thread's `errno`.
public int Errno() { return *__errno_location(); }

public const int EINTR = 4;
public const int EBADF = 9;

/// `EAGAIN` and `EWOULDBLOCK` are the same number on Linux. They are not
/// required to be, which is why portable code tests both.
public const int EAGAIN = 11;
public const int EWOULDBLOCK = 11;

public const int EACCES = 13;
public const int EFAULT = 14;
public const int EINVAL = 22;
public const int EMFILE = 24;
public const int EPIPE = 32;
public const int ENOTSOCK = 88;
public const int EMSGSIZE = 90;
public const int EPROTOTYPE = 91;
public const int ENOPROTOOPT = 92;
public const int EPROTONOSUPPORT = 93;
public const int EOPNOTSUPP = 95;
public const int EAFNOSUPPORT = 97;
public const int EADDRINUSE = 98;
public const int EADDRNOTAVAIL = 99;
public const int ENETDOWN = 100;
public const int ENETUNREACH = 101;
public const int ENETRESET = 102;
public const int ECONNABORTED = 103;
public const int ECONNRESET = 104;
public const int ENOBUFS = 105;
public const int EISCONN = 106;
public const int ENOTCONN = 107;
public const int ESHUTDOWN = 108;
public const int ETIMEDOUT = 110;
public const int ECONNREFUSED = 111;
public const int EHOSTDOWN = 112;
public const int EHOSTUNREACH = 113;
public const int EALREADY = 114;
public const int EINPROGRESS = 115;

#endif
