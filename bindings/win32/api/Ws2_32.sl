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

// ws2_32.dll, declared and nothing else.
//
// This is a raw binding: entry points, structs and constants, with the names
// Windows gives them, so that anything found on MSDN is here under the same
// spelling. The conveniences are `Standard.Net`, which does not go through this
// file at all -- it goes through runtime/socket.c, because the standard library
// is compiled with every program and the bindings are not.
//
// Three things about Winsock that a POSIX reader will trip over, and that this
// file cannot hide because hiding them is not what a binding does:
//
//   - **A SOCKET is not a file descriptor.** It is a `UINT_PTR`, unsigned and
//     pointer-sized, and the failure value is `InvalidSocket` (all ones) rather
//     than -1. Comparing one against zero or against a negative number is the
//     classic port-from-Unix bug.
//   - **Errors are not errno.** `WSAGetLastError()` has them, the codes are
//     10000 and up, and nothing sets errno.
//   - **Nothing works before `WSAStartup`.** Not even `socket`. Windows keeps
//     a per-process reference count and unwinds it at exit, which is why
//     `WSACleanup` is optional and mostly a formality.
//
// `#pragma comment(lib, "ws2_32")` is at the bottom, so a program that names
// this file needs no `-l`.
module Win32.Ws2_32;

import Win32.Handles;

#if WINDOWS

// ================================================================== the type

/// `SOCKET`: unsigned and pointer-sized, and not a file descriptor.
public using SOCKET = nuint;

/// `INVALID_SOCKET`, which is what a failed `socket` or `accept` returns.
/// All ones rather than -1, because a SOCKET is unsigned.
public const nuint InvalidSocket = 18446744073709551615u;

/// `SOCKET_ERROR`, which is what most of the rest return on failure.
public const int SocketError = -1;

// ================================================================== startup

/// `WSADATA`. `sizeof` is 408, as it is in C.
///
/// Only `Version` and `HighVersion` are worth reading, and only to check that
/// the version asked for is the version given. The rest is documented as
/// obsolete by Microsoft's own header.
public struct WSADATA {
    public ushort Version;
    public ushort HighVersion;
    public byte[257] Description;
    public byte[129] SystemStatus;
    public ushort MaxSockets;
    public ushort MaxUdpDg;
    public byte* VendorInfo;
}

public extern "C" {
    /// Must be called before anything else here. `version` is
    /// `MakeWord(2, 2)` for every program written this century.
    int WSAStartup(ushort version, WSADATA* data);

    int WSACleanup();

    /// The last error on this thread. Not errno, and not `GetLastError` --
    /// although on current Windows they happen to be the same storage.
    int WSAGetLastError();

    void WSASetLastError(int error);
}

/// `MAKEWORD(low, high)`, which is what `WSAStartup` wants its version as.
public ushort MakeWord(byte low, byte high) {
    return (ushort)((ushort)low | ((ushort)high << 8));
}

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

/// `struct sockaddr_in`. `sin_port` and `sin_addr` are in network byte order:
/// `htons` and `inet_pton` put them there.
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
/// **The field order is not the same as Linux's.** Windows puts `ai_canonname`
/// before `ai_addr`; glibc puts `ai_addr` first. A struct copied from a Linux
/// header and used here reads the two through each other, which is a pointer
/// dereference of a string and a string print of a pointer. `ai_addrlen` also
/// differs: `size_t` here, `socklen_t` there.
public struct addrinfo {
    public int ai_flags;
    public int ai_family;
    public int ai_socktype;
    public int ai_protocol;
    public nuint ai_addrlen;
    public byte* ai_canonname;
    public sockaddr* ai_addr;
    public addrinfo* ai_next;
}

/// `struct timeval`, for `select`. Both fields are `long` in Windows' header,
/// which is 32 bits there and not 64.
public struct timeval {
    public int tv_sec;
    public int tv_usec;
}

/// `struct linger`, for `SO_LINGER`.
public struct linger {
    public ushort l_onoff;
    public ushort l_linger;
}

/// `struct fd_set`. Windows' is an array of sockets and a count, not the
/// bitmask POSIX uses -- which is why `FD_SETSIZE` here is a limit on *how
/// many* sockets rather than on how large a descriptor may be.
public struct fd_set {
    public uint fd_count;
    public nuint[64] fd_array;
}

public const uint FdSetSize = 64u;

// ================================================================= families

public const int AF_UNSPEC = 0;
public const int AF_INET = 2;
public const int AF_INET6 = 23;         // 23 on Windows, 10 on Linux
public const int AF_NETBIOS = 17;
public const int AF_BTH = 32;

public const int SOCK_STREAM = 1;
public const int SOCK_DGRAM = 2;
public const int SOCK_RAW = 3;
public const int SOCK_RDM = 4;
public const int SOCK_SEQPACKET = 5;

public const int IPPROTO_IP = 0;
public const int IPPROTO_ICMP = 1;
public const int IPPROTO_TCP = 6;
public const int IPPROTO_UDP = 17;
public const int IPPROTO_IPV6 = 41;
public const int IPPROTO_ICMPV6 = 58;

/// `INADDR_ANY`, `INADDR_LOOPBACK` and `INADDR_BROADCAST`, in host order.
/// `htonl` is what puts them on the wire.
public const uint INADDR_ANY = 0u;
public const uint INADDR_LOOPBACK = 2130706433u;        // 127.0.0.1
public const uint INADDR_BROADCAST = 4294967295u;
public const uint INADDR_NONE = 4294967295u;

// ============================================================ opening, closing

public extern "C" {
    nuint socket(int family, int kind, int protocol);
    int closesocket(nuint handle);
    int shutdown(nuint handle, int how);

    int bind(nuint handle, sockaddr* address, int length);
    int listen(nuint handle, int backlog);
    nuint accept(nuint handle, sockaddr* address, int* length);
    int connect(nuint handle, sockaddr* address, int length);

    int getsockname(nuint handle, sockaddr* address, int* length);
    int getpeername(nuint handle, sockaddr* address, int* length);
}

/// `SD_RECEIVE`, `SD_SEND`, `SD_BOTH`. POSIX spells the same three
/// `SHUT_RD`, `SHUT_WR` and `SHUT_RDWR`, with the same values.
public const int SD_RECEIVE = 0;
public const int SD_SEND = 1;
public const int SD_BOTH = 2;

public const int SOMAXCONN = 2147483647;

// ================================================================== transfer

public extern "C" {
    /// Returns how many bytes moved, or `SocketError`. A `send` that moves
    /// fewer than asked is normal on a stream and not an error.
    int send(nuint handle, byte* data, int length, int flags);
    int recv(nuint handle, byte* data, int length, int flags);

    int sendto(nuint handle, byte* data, int length, int flags,
               sockaddr* to, int toLength);
    int recvfrom(nuint handle, byte* data, int length, int flags,
                 sockaddr* from, int* fromLength);
}

public const int MSG_OOB = 1;
public const int MSG_PEEK = 2;
public const int MSG_DONTROUTE = 4;
public const int MSG_WAITALL = 8;

// =================================================================== options

public extern "C" {
    int setsockopt(nuint handle, int level, int name, byte* value, int length);
    int getsockopt(nuint handle, int level, int name, byte* value, int* length);

    /// The one Winsock has instead of `fcntl`. `FIONBIO` with a non-zero
    /// value is what makes a socket non-blocking.
    int ioctlsocket(nuint handle, int command, uint* argument);
}

public const int SOL_SOCKET = 65535;    // 0xFFFF on Windows, 1 on Linux

public const int SO_DEBUG = 1;
public const int SO_ACCEPTCONN = 2;
public const int SO_REUSEADDR = 4;
public const int SO_KEEPALIVE = 8;
public const int SO_DONTROUTE = 16;
public const int SO_BROADCAST = 32;
public const int SO_LINGER = 128;
public const int SO_OOBINLINE = 256;
public const int SO_SNDBUF = 4097;
public const int SO_RCVBUF = 4098;
public const int SO_SNDTIMEO = 4101;
public const int SO_RCVTIMEO = 4102;
public const int SO_ERROR = 4103;
public const int SO_TYPE = 4104;

/// Windows' own, and the one to reach for instead of `SO_REUSEADDR`: it stops
/// another process taking a port this one is listening on, which is what
/// `SO_REUSEADDR` here would otherwise allow.
public const int SO_EXCLUSIVEADDRUSE = -5;

public const int TCP_NODELAY = 1;
public const int TCP_KEEPALIVE = 3;

public const int IPV6_V6ONLY = 27;
public const int IP_MULTICAST_TTL = 10;
public const int IP_ADD_MEMBERSHIP = 12;
public const int IP_DROP_MEMBERSHIP = 13;

/// `FIONBIO`, for `ioctlsocket`. Also `FIONREAD`, which asks how many bytes
/// are waiting.
///
/// Unsigned, because that is what the header's expression is: `IOC_IN` is
/// `0x80000000`, which makes the whole `_IOW` unsigned in C. `ioctlsocket`
/// takes a signed `long`, so the call needs `(int)FIONBIO` -- the same
/// thirty-two bits either way, and the cast is where that is said out loud.
public const uint FIONBIO = 2147772030u;        // 0x8004667E
public const uint FIONREAD = 1074030207u;       // 0x4004667F

// ==================================================================== waiting

public extern "C" {
    /// `nfds` is ignored on Windows -- the sets carry their own counts -- and
    /// is present only so that code written for POSIX compiles.
    int select(int nfds, fd_set* readable, fd_set* writable, fd_set* failed,
               timeval* timeout);

    /// `WSAPoll`: Winsock's `poll`, present since Vista. It does not report a
    /// failed connect on a non-blocking socket, which `select` does, so a
    /// connect loop still wants `select`.
    int WSAPoll(WSAPOLLFD* entries, uint count, int milliseconds);
}

/// `WSAPOLLFD`, which is `struct pollfd` under another name.
public struct WSAPOLLFD {
    public nuint fd;
    public short events;
    public short revents;
}

public const short POLLRDNORM = 256;
public const short POLLRDBAND = 512;
public const short POLLIN = 768;
public const short POLLPRI = 1024;
public const short POLLWRNORM = 16;
public const short POLLOUT = 16;
public const short POLLWRBAND = 32;
public const short POLLERR = 1;
public const short POLLHUP = 2;
public const short POLLNVAL = 4;

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

    int GetAddrInfoW(char16* node, char16* service, addrinfo* hints, addrinfo** result);

    int getnameinfo(sockaddr* address, int addressLength, byte* host, uint hostLength,
                    byte* service, uint serviceLength, int flags);

    int gethostname(byte* name, int length);

    /// Text to bytes and back. `family` is `AF_INET` or `AF_INET6`.
    int inet_pton(int family, byte* text, void* address);
    byte* inet_ntop(int family, void* address, byte* text, nuint size);
}

public const int AI_PASSIVE = 1;
public const int AI_CANONNAME = 2;
public const int AI_NUMERICHOST = 4;
public const int AI_NUMERICSERV = 8;
public const int AI_ALL = 256;
public const int AI_ADDRCONFIG = 1024;
public const int AI_V4MAPPED = 2048;

public const int NI_NUMERICHOST = 2;
public const int NI_NUMERICSERV = 8;
public const int NI_NAMEREQD = 4;
public const int NI_DGRAM = 16;

public const int NI_MAXHOST = 1025;
public const int NI_MAXSERV = 32;

// =================================================================== errors

/// The codes `WSAGetLastError` returns. They begin at 10000 and share nothing
/// with `errno`, which is the whole reason they are listed here.
public const int WSAEINTR = 10004;
public const int WSAEBADF = 10009;
public const int WSAEACCES = 10013;
public const int WSAEFAULT = 10014;
public const int WSAEINVAL = 10022;
public const int WSAEMFILE = 10024;
public const int WSAEWOULDBLOCK = 10035;
public const int WSAEINPROGRESS = 10036;
public const int WSAEALREADY = 10037;
public const int WSAENOTSOCK = 10038;
public const int WSAEMSGSIZE = 10040;
public const int WSAEPROTOTYPE = 10041;
public const int WSAENOPROTOOPT = 10042;
public const int WSAEPROTONOSUPPORT = 10043;
public const int WSAEOPNOTSUPP = 10045;
public const int WSAEAFNOSUPPORT = 10047;
public const int WSAEADDRINUSE = 10048;
public const int WSAEADDRNOTAVAIL = 10049;
public const int WSAENETDOWN = 10050;
public const int WSAENETUNREACH = 10051;
public const int WSAENETRESET = 10052;
public const int WSAECONNABORTED = 10053;
public const int WSAECONNRESET = 10054;
public const int WSAENOBUFS = 10055;
public const int WSAEISCONN = 10056;
public const int WSAENOTCONN = 10057;
public const int WSAESHUTDOWN = 10058;
public const int WSAETIMEDOUT = 10060;
public const int WSAECONNREFUSED = 10061;
public const int WSAEHOSTDOWN = 10064;
public const int WSAEHOSTUNREACH = 10065;
public const int WSASYSNOTREADY = 10091;
public const int WSAVERNOTSUPPORTED = 10092;
public const int WSANOTINITIALISED = 10093;
public const int WSAEDISCON = 10101;
public const int WSAHOST_NOT_FOUND = 11001;
public const int WSATRY_AGAIN = 11002;
public const int WSANO_RECOVERY = 11003;
public const int WSANO_DATA = 11004;

#pragma comment(lib, "ws2_32")

#endif
