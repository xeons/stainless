/*
 * Stainless - an experimental systems language.
 * Copyright (C) 2026 Brandon Scott
 *
 * This file is part of the Stainless runtime library. It is free
 * software: you can redistribute it and/or modify it under the terms of
 * the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any
 * later version.
 *
 * It is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * for more details.
 *
 * As an additional permission under section 7 of that License, compiling
 * a program with Stainless does not by itself place that program under
 * the GNU General Public License. See LICENSE.RUNTIME.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

/*
 * Sockets, with the platform taken out of them.
 *
 * Winsock and BSD sockets are the same design and disagree about nearly every
 * detail: a socket is a pointer-sized handle on one and a file descriptor on
 * the other, errors arrive through WSAGetLastError or errno, closing is
 * closesocket or close, and Winsock will not do anything at all until
 * WSAStartup has been called. None of that is interesting to a program that
 * wants to open a connection, and all of it is here so that Standard.Net does
 * not have to know.
 *
 * A socket crosses the boundary as a size_t rather than as an allocated
 * handle, because the two platforms already agree on a sentinel: Winsock's
 * INVALID_SOCKET is (SOCKET)~0 and a failed POSIX call returns -1, and both
 * are all-ones once widened. So there is nothing to allocate and nothing to
 * free but the socket itself.
 *
 * Errors come back as the small stable enum below rather than as errno or a
 * WSA code, for the reason io.c gives: neither platform's numbers are the
 * other's, and a Stainless enum is a value that crosses as itself.
 */

/*
 * Asked for before any header, because glibc hides getaddrinfo, getnameinfo,
 * struct addrinfo, AI_PASSIVE, NI_NUMERICHOST and MSG_NOSIGNAL behind it.
 * The driver compiles the runtime in the compiler's default dialect, which
 * defines _DEFAULT_SOURCE and so exposes them anyway -- but that makes this
 * file's correctness a property of a flag nobody passed, and `-std=c11` alone
 * does not compile it. Saying what it needs is cheaper than finding that out.
 */
#ifndef _WIN32
#  define _GNU_SOURCE 1
#endif

#include "stainless.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <winsock2.h>
#  include <ws2tcpip.h>
#  pragma comment(lib, "ws2_32.lib")

typedef SOCKET SlNative;
typedef int    SlLength;            /* Winsock's socklen_t is a plain int */

#  define SL_BAD_SOCKET INVALID_SOCKET
#  define sl_close_native closesocket
#else
#  include <arpa/inet.h>
#  include <errno.h>
#  include <fcntl.h>
#  include <netdb.h>
#  include <netinet/in.h>
#  include <netinet/tcp.h>
#  include <poll.h>
#  include <sys/socket.h>
#  include <sys/types.h>
#  include <unistd.h>

typedef int       SlNative;
typedef socklen_t SlLength;

#  define SL_BAD_SOCKET (-1)
#  define sl_close_native close
#endif

/* --------------------------------------------------------------- error codes */

/* Must match Standard.Net.SocketError. */
enum {
    SL_NET_OK = 0,
    SL_NET_WOULD_BLOCK = 1,
    SL_NET_REFUSED = 2,
    SL_NET_TIMED_OUT = 3,
    SL_NET_UNREACHABLE = 4,
    SL_NET_ADDRESS_IN_USE = 5,
    SL_NET_NOT_CONNECTED = 6,
    SL_NET_RESET = 7,
    SL_NET_CLOSED = 8,
    SL_NET_INTERRUPTED = 9,
    SL_NET_ACCESS_DENIED = 10,
    SL_NET_NO_NAME = 11,
    SL_NET_INVALID = 12,
    SL_NET_UNKNOWN = 13
};

/* The families and kinds Standard.Net names, which are not the platform's. */
enum { SL_NET_IPV4 = 4, SL_NET_IPV6 = 6 };
enum { SL_NET_STREAM = 1, SL_NET_DATAGRAM = 2 };

/*
 * The last error, translated.
 *
 * Read immediately after the call that failed and never speculatively: on
 * Windows WSAGetLastError is thread-local and on POSIX errno is, but both are
 * clobbered by the next call that sets them, including ones that succeeded.
 */
static int sl_net_last(void)
{
#ifdef _WIN32
    switch (WSAGetLastError()) {
        case WSAEWOULDBLOCK:  return SL_NET_WOULD_BLOCK;
        case WSAEINPROGRESS:  return SL_NET_WOULD_BLOCK;
        case WSAEALREADY:     return SL_NET_WOULD_BLOCK;
        case WSAECONNREFUSED: return SL_NET_REFUSED;
        case WSAETIMEDOUT:    return SL_NET_TIMED_OUT;
        case WSAEHOSTUNREACH: return SL_NET_UNREACHABLE;
        case WSAENETUNREACH:  return SL_NET_UNREACHABLE;
        case WSAEADDRINUSE:   return SL_NET_ADDRESS_IN_USE;
        case WSAENOTCONN:     return SL_NET_NOT_CONNECTED;
        case WSAECONNRESET:   return SL_NET_RESET;
        case WSAECONNABORTED: return SL_NET_RESET;
        case WSAESHUTDOWN:    return SL_NET_CLOSED;
        case WSAENOTSOCK:     return SL_NET_CLOSED;
        case WSAEINTR:        return SL_NET_INTERRUPTED;
        case WSAEACCES:       return SL_NET_ACCESS_DENIED;
        case WSAEINVAL:       return SL_NET_INVALID;
        case WSAEAFNOSUPPORT: return SL_NET_INVALID;
        case 0:               return SL_NET_OK;
        default:              return SL_NET_UNKNOWN;
    }
#else
    switch (errno) {
        case EWOULDBLOCK:   return SL_NET_WOULD_BLOCK;
#  if EAGAIN != EWOULDBLOCK
        case EAGAIN:        return SL_NET_WOULD_BLOCK;
#  endif
        case EINPROGRESS:   return SL_NET_WOULD_BLOCK;
        case EALREADY:      return SL_NET_WOULD_BLOCK;
        case ECONNREFUSED:  return SL_NET_REFUSED;
        case ETIMEDOUT:     return SL_NET_TIMED_OUT;
        case EHOSTUNREACH:  return SL_NET_UNREACHABLE;
        case ENETUNREACH:   return SL_NET_UNREACHABLE;
        case EADDRINUSE:    return SL_NET_ADDRESS_IN_USE;
        case EADDRNOTAVAIL: return SL_NET_ADDRESS_IN_USE;
        case ENOTCONN:      return SL_NET_NOT_CONNECTED;
        case ECONNRESET:    return SL_NET_RESET;
        case ECONNABORTED:  return SL_NET_RESET;
        case EPIPE:         return SL_NET_RESET;
        case EBADF:         return SL_NET_CLOSED;
        case ENOTSOCK:      return SL_NET_CLOSED;
        case EINTR:         return SL_NET_INTERRUPTED;
        case EACCES:        return SL_NET_ACCESS_DENIED;
        case EPERM:         return SL_NET_ACCESS_DENIED;
        case EINVAL:        return SL_NET_INVALID;
        case EAFNOSUPPORT:  return SL_NET_INVALID;
        case 0:             return SL_NET_OK;
        default:            return SL_NET_UNKNOWN;
    }
#endif
}

static void sl_net_report(int *error, int code)
{
    if (error != NULL) *error = code;
}

static void sl_net_failed(int *error)
{
    sl_net_report(error, sl_net_last());
}

/* ------------------------------------------------------------------ startup */

/*
 * Winsock does nothing until WSAStartup has been called, and nothing here can
 * ask the program to remember to. So it happens on the first socket, once,
 * under a compare-exchange -- two threads opening their first socket at the
 * same instant is not a race the caller should have to think about.
 *
 * There is no matching WSACleanup. It would have to run after the last socket
 * closed, which nothing here knows, and Windows unwinds the reference when the
 * process exits regardless.
 */
#ifdef _WIN32
static long sl_net_started = 0;

static int sl_net_start(int *error)
{
    long expected = 0;
    WSADATA data;

    if (__atomic_load_n(&sl_net_started, __ATOMIC_ACQUIRE) == 2) return 1;

    /* 0 -> 1 means this thread does the startup; anything else waits for it. */
    if (__atomic_compare_exchange_n(&sl_net_started, &expected, 1, 0,
                                    __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
        if (WSAStartup(MAKEWORD(2, 2), &data) != 0) {
            __atomic_store_n(&sl_net_started, 0, __ATOMIC_RELEASE);
            sl_net_report(error, SL_NET_UNKNOWN);
            return 0;
        }
        __atomic_store_n(&sl_net_started, 2, __ATOMIC_RELEASE);
        return 1;
    }

    while (__atomic_load_n(&sl_net_started, __ATOMIC_ACQUIRE) == 1) { Sleep(0); }
    return __atomic_load_n(&sl_net_started, __ATOMIC_ACQUIRE) == 2;
}
#else
static int sl_net_start(int *error) { (void)error; return 1; }
#endif

/* ---------------------------------------------------------------- addresses */

static int sl_net_family(int family)
{
    if (family == SL_NET_IPV6) return AF_INET6;
    if (family == SL_NET_IPV4) return AF_INET;
    return AF_UNSPEC;
}

/*
 * Resolves a host and port to the first address that fits.
 *
 * `host` may be a name or a literal address, and NULL means "any" -- which is
 * what a listener binds to. getaddrinfo answers both, so there is no separate
 * inet_pton path and no place for the two to disagree.
 */
static int sl_net_lookup(const char *host, uint16_t port, int family, int kind,
                         int passive, struct addrinfo **out, int *error)
{
    struct addrinfo hints;
    char service[8];
    int result;

    memset(&hints, 0, sizeof hints);
    hints.ai_family = sl_net_family(family);
    hints.ai_socktype = kind == SL_NET_DATAGRAM ? SOCK_DGRAM : SOCK_STREAM;
    if (passive) hints.ai_flags = AI_PASSIVE;

    snprintf(service, sizeof service, "%u", (unsigned)port);

    result = getaddrinfo(host, service, &hints, out);
    if (result != 0) {
        sl_net_report(error, SL_NET_NO_NAME);
        return 0;
    }
    return 1;
}

/* An address as text, and the port beside it. */
static void sl_net_describe(const struct sockaddr *address, SlLength length,
                            char *host, size_t size, uint16_t *port)
{
    char service[16];

    if (host != NULL && size > 0) host[0] = '\0';
    if (port != NULL) *port = 0;

    if (getnameinfo(address, length, host, (unsigned)size,
                    service, sizeof service, NI_NUMERICHOST | NI_NUMERICSERV) != 0)
        return;

    if (port != NULL) *port = (uint16_t)strtoul(service, NULL, 10);
}

/* ------------------------------------------------------------------ opening */

size_t sl_socket_open(int family, int kind, int *error)
{
    SlNative handle;

    sl_net_report(error, SL_NET_OK);
    if (!sl_net_start(error)) return (size_t)-1;

    handle = socket(sl_net_family(family),
                    kind == SL_NET_DATAGRAM ? SOCK_DGRAM : SOCK_STREAM,
                    kind == SL_NET_DATAGRAM ? IPPROTO_UDP : IPPROTO_TCP);

    if (handle == SL_BAD_SOCKET) {
        sl_net_failed(error);
        return (size_t)-1;
    }
    return (size_t)handle;
}

void sl_socket_close(size_t handle)
{
    if (handle == (size_t)-1) return;
    sl_close_native((SlNative)handle);
}

int sl_socket_shutdown(size_t handle, int how, int *error)
{
    /* 0 receive, 1 send, 2 both -- the same three everywhere, spelled twice. */
#ifdef _WIN32
    int native = how == 0 ? SD_RECEIVE : how == 1 ? SD_SEND : SD_BOTH;
#else
    int native = how == 0 ? SHUT_RD : how == 1 ? SHUT_WR : SHUT_RDWR;
#endif

    sl_net_report(error, SL_NET_OK);
    if (shutdown((SlNative)handle, native) != 0) {
        sl_net_failed(error);
        return 0;
    }
    return 1;
}

/* ------------------------------------------------------------------ binding */

int sl_socket_bind(size_t handle, const char *host, uint16_t port, int family,
                   int kind, int *error)
{
    struct addrinfo *found = NULL;
    int ok;

    sl_net_report(error, SL_NET_OK);
    if (!sl_net_lookup(host != NULL && host[0] != '\0' ? host : NULL,
                       port, family, kind, 1, &found, error))
        return 0;

    ok = bind((SlNative)handle, found->ai_addr, (SlLength)found->ai_addrlen) == 0;
    if (!ok) sl_net_failed(error);

    freeaddrinfo(found);
    return ok;
}

int sl_socket_listen(size_t handle, int backlog, int *error)
{
    sl_net_report(error, SL_NET_OK);
    if (listen((SlNative)handle, backlog) != 0) {
        sl_net_failed(error);
        return 0;
    }
    return 1;
}

size_t sl_socket_accept(size_t handle, int *error)
{
    SlNative accepted = accept((SlNative)handle, NULL, NULL);

    sl_net_report(error, SL_NET_OK);
    if (accepted == SL_BAD_SOCKET) {
        sl_net_failed(error);
        return (size_t)-1;
    }
    return (size_t)accepted;
}

/*
 * Connects a socket that is already open.
 *
 * Only the first address of the requested family is tried, and that is a real
 * limitation rather than an oversight: a socket whose connect failed is not
 * usable for a second attempt, and this function does not own the socket and
 * so cannot replace it. `sl_socket_open_connected` is the one that tries them
 * all, because it makes the socket.
 */
int sl_socket_connect(size_t handle, const char *host, uint16_t port, int family,
                      int kind, int *error)
{
    struct addrinfo *found = NULL;
    int ok;

    sl_net_report(error, SL_NET_OK);
    if (!sl_net_lookup(host, port, family, kind, 0, &found, error)) return 0;

    ok = connect((SlNative)handle, found->ai_addr, (SlLength)found->ai_addrlen) == 0;
    if (!ok) sl_net_failed(error);

    freeaddrinfo(found);
    return ok;
}

/*
 * Opens a socket and connects it, trying every address the name resolved to.
 *
 * This is the shape a client wants, and the reason is that **connecting is what
 * decides the address family**. A caller that has only a name does not know
 * whether it will end up with IPv4 or IPv6, so it cannot open the socket first
 * -- and asking for AF_UNSPEC does not help: Winsock quietly hands back an
 * AF_INET socket and Linux returns EAFNOSUPPORT, which is the more honest of
 * the two answers.
 *
 * So a socket is made per candidate, of that candidate's own family, and
 * closed again if it does not connect. A host with both an A and an AAAA
 * record where only one route works is the ordinary case rather than the
 * exotic one.
 */
size_t sl_socket_open_connected(const char *host, uint16_t port, int family,
                                int kind, int *error)
{
    struct addrinfo *found = NULL;
    struct addrinfo *step;

    sl_net_report(error, SL_NET_OK);
    if (!sl_net_start(error)) return (size_t)-1;
    if (!sl_net_lookup(host, port, family, kind, 0, &found, error)) return (size_t)-1;

    for (step = found; step != NULL; step = step->ai_next) {
        SlNative handle = socket(step->ai_family, step->ai_socktype, step->ai_protocol);
        if (handle == SL_BAD_SOCKET) {
            sl_net_failed(error);
            continue;
        }

        if (connect(handle, step->ai_addr, (SlLength)step->ai_addrlen) == 0) {
            freeaddrinfo(found);
            sl_net_report(error, SL_NET_OK);
            return (size_t)handle;
        }

        sl_net_failed(error);
        sl_close_native(handle);
    }

    freeaddrinfo(found);
    return (size_t)-1;
}

/* ------------------------------------------------------------------ transfer */

size_t sl_socket_send(size_t handle, const uint8_t *data, size_t count, int *error)
{
#ifdef _WIN32
    int moved;
#else
    ssize_t moved;
#endif

    sl_net_report(error, SL_NET_OK);
    if (count == 0) return 0;

#ifdef _WIN32
    moved = send((SlNative)handle, (const char *)data, (int)count, 0);
#else
    /* MSG_NOSIGNAL where it exists: writing to a closed peer is an error to
       return, not a signal that kills the process. macOS uses SO_NOSIGPIPE at
       open time instead, which is set in sl_socket_open's caller path. */
#  ifdef MSG_NOSIGNAL
    moved = send((SlNative)handle, data, count, MSG_NOSIGNAL);
#  else
    moved = send((SlNative)handle, data, count, 0);
#  endif
#endif

    if (moved < 0) {
        sl_net_failed(error);
        return 0;
    }
    return (size_t)moved;
}

size_t sl_socket_receive(size_t handle, uint8_t *data, size_t count, int *error)
{
#ifdef _WIN32
    int moved;
#else
    ssize_t moved;
#endif

    sl_net_report(error, SL_NET_OK);
    if (count == 0) return 0;

#ifdef _WIN32
    moved = recv((SlNative)handle, (char *)data, (int)count, 0);
#else
    moved = recv((SlNative)handle, data, count, 0);
#endif

    if (moved < 0) {
        sl_net_failed(error);
        return 0;
    }
    return (size_t)moved;      /* zero is the peer having finished, not an error */
}

size_t sl_socket_send_to(size_t handle, const uint8_t *data, size_t count,
                         const char *host, uint16_t port, int family, int *error)
{
    struct addrinfo *found = NULL;
#ifdef _WIN32
    int moved;
#else
    ssize_t moved;
#endif

    sl_net_report(error, SL_NET_OK);
    if (!sl_net_lookup(host, port, family, SL_NET_DATAGRAM, 0, &found, error)) return 0;

#ifdef _WIN32
    moved = sendto((SlNative)handle, (const char *)data, (int)count, 0,
                   found->ai_addr, (SlLength)found->ai_addrlen);
#else
    moved = sendto((SlNative)handle, data, count, 0,
                   found->ai_addr, (SlLength)found->ai_addrlen);
#endif

    freeaddrinfo(found);

    if (moved < 0) {
        sl_net_failed(error);
        return 0;
    }
    return (size_t)moved;
}

size_t sl_socket_receive_from(size_t handle, uint8_t *data, size_t count,
                              char *host, size_t hostSize, uint16_t *port, int *error)
{
    struct sockaddr_storage from;
    SlLength length = (SlLength)sizeof from;
#ifdef _WIN32
    int moved;
#else
    ssize_t moved;
#endif

    sl_net_report(error, SL_NET_OK);

#ifdef _WIN32
    moved = recvfrom((SlNative)handle, (char *)data, (int)count, 0,
                     (struct sockaddr *)&from, &length);
#else
    moved = recvfrom((SlNative)handle, data, count, 0,
                     (struct sockaddr *)&from, &length);
#endif

    if (moved < 0) {
        sl_net_failed(error);
        return 0;
    }

    sl_net_describe((struct sockaddr *)&from, length, host, hostSize, port);
    return (size_t)moved;
}

/* ------------------------------------------------------------------ options */

int sl_socket_set_blocking(size_t handle, int blocking, int *error)
{
    sl_net_report(error, SL_NET_OK);

#ifdef _WIN32
    {
        u_long mode = blocking ? 0 : 1;
        if (ioctlsocket((SlNative)handle, FIONBIO, &mode) != 0) {
            sl_net_failed(error);
            return 0;
        }
    }
#else
    {
        int flags = fcntl((SlNative)handle, F_GETFL, 0);
        if (flags < 0) { sl_net_failed(error); return 0; }

        flags = blocking ? (flags & ~O_NONBLOCK) : (flags | O_NONBLOCK);
        if (fcntl((SlNative)handle, F_SETFL, flags) < 0) {
            sl_net_failed(error);
            return 0;
        }
    }
#endif
    return 1;
}

static int sl_socket_flag(size_t handle, int level, int name, int on, int *error)
{
    int value = on ? 1 : 0;

    sl_net_report(error, SL_NET_OK);
#ifdef _WIN32
    if (setsockopt((SlNative)handle, level, name, (const char *)&value, sizeof value) != 0)
#else
    if (setsockopt((SlNative)handle, level, name, &value, sizeof value) != 0)
#endif
    {
        sl_net_failed(error);
        return 0;
    }
    return 1;
}

int sl_socket_set_no_delay(size_t handle, int on, int *error)
{
    return sl_socket_flag(handle, IPPROTO_TCP, TCP_NODELAY, on, error);
}

/*
 * SO_REUSEADDR, which does not mean the same thing on both platforms.
 *
 * On POSIX it lets a listener bind a port still held by connections in
 * TIME_WAIT, which is what a server restarting wants. On Windows it lets a
 * second socket steal a port another process is actively listening on, which
 * is not -- so Windows gets SO_EXCLUSIVEADDRUSE off and nothing else, and the
 * TIME_WAIT behaviour it already has by default.
 */
int sl_socket_set_reuse_address(size_t handle, int on, int *error)
{
#ifdef _WIN32
    (void)handle; (void)on;
    sl_net_report(error, SL_NET_OK);
    return 1;
#else
    return sl_socket_flag(handle, SOL_SOCKET, SO_REUSEADDR, on, error);
#endif
}

int sl_socket_set_broadcast(size_t handle, int on, int *error)
{
    return sl_socket_flag(handle, SOL_SOCKET, SO_BROADCAST, on, error);
}

int sl_socket_set_keep_alive(size_t handle, int on, int *error)
{
    return sl_socket_flag(handle, SOL_SOCKET, SO_KEEPALIVE, on, error);
}

/* `receiving` picks SO_RCVTIMEO or SO_SNDTIMEO. Zero milliseconds is no
   timeout, which is what both platforms mean by it. */
int sl_socket_set_timeout(size_t handle, int milliseconds, int receiving, int *error)
{
    int name = receiving ? SO_RCVTIMEO : SO_SNDTIMEO;

    sl_net_report(error, SL_NET_OK);

#ifdef _WIN32
    {
        DWORD value = (DWORD)(milliseconds < 0 ? 0 : milliseconds);
        if (setsockopt((SlNative)handle, SOL_SOCKET, name,
                       (const char *)&value, sizeof value) != 0) {
            sl_net_failed(error);
            return 0;
        }
    }
#else
    {
        struct timeval value;
        value.tv_sec = milliseconds / 1000;
        value.tv_usec = (milliseconds % 1000) * 1000;
        if (milliseconds < 0) { value.tv_sec = 0; value.tv_usec = 0; }

        if (setsockopt((SlNative)handle, SOL_SOCKET, name, &value, sizeof value) != 0) {
            sl_net_failed(error);
            return 0;
        }
    }
#endif
    return 1;
}

/* --------------------------------------------------------------- addresses */

int sl_socket_local(size_t handle, char *host, size_t size, uint16_t *port, int *error)
{
    struct sockaddr_storage address;
    SlLength length = (SlLength)sizeof address;

    sl_net_report(error, SL_NET_OK);
    if (getsockname((SlNative)handle, (struct sockaddr *)&address, &length) != 0) {
        sl_net_failed(error);
        return 0;
    }

    sl_net_describe((struct sockaddr *)&address, length, host, size, port);
    return 1;
}

int sl_socket_remote(size_t handle, char *host, size_t size, uint16_t *port, int *error)
{
    struct sockaddr_storage address;
    SlLength length = (SlLength)sizeof address;

    sl_net_report(error, SL_NET_OK);
    if (getpeername((SlNative)handle, (struct sockaddr *)&address, &length) != 0) {
        sl_net_failed(error);
        return 0;
    }

    sl_net_describe((struct sockaddr *)&address, length, host, size, port);
    return 1;
}

/*
 * A host's first address, as text.
 *
 * One address rather than the list, because the list is only useful to
 * something that will try each in turn -- which is what connect already does
 * internally, where it can also try each socket.
 */
int sl_socket_resolve(const char *host, int family, char *out, size_t size, int *error)
{
    struct addrinfo *found = NULL;

    sl_net_report(error, SL_NET_OK);
    if (!sl_net_start(error)) return 0;
    if (!sl_net_lookup(host, 0, family, SL_NET_STREAM, 0, &found, error)) return 0;

    sl_net_describe(found->ai_addr, (SlLength)found->ai_addrlen, out, size, NULL);
    freeaddrinfo(found);
    return out[0] != '\0';
}

/* --------------------------------------------------------------- waiting */

/*
 * Waits until the socket is ready, or the time runs out.
 *
 * poll where there is one and select on Windows, which has poll only under a
 * different name and with a different history. A negative timeout waits
 * forever; the answer is 1 for ready, 0 for the timeout, -1 for an error.
 */
int sl_socket_wait(size_t handle, int forWriting, int milliseconds, int *error)
{
    sl_net_report(error, SL_NET_OK);

#ifdef _WIN32
    {
        fd_set set;
        struct timeval limit;
        int ready;

        FD_ZERO(&set);
        FD_SET((SlNative)handle, &set);

        limit.tv_sec = milliseconds / 1000;
        limit.tv_usec = (milliseconds % 1000) * 1000;

        ready = select(0,
                       forWriting ? NULL : &set,
                       forWriting ? &set : NULL,
                       NULL,
                       milliseconds < 0 ? NULL : &limit);

        if (ready < 0) { sl_net_failed(error); return -1; }
        return ready > 0 ? 1 : 0;
    }
#else
    {
        struct pollfd entry;
        int ready;

        entry.fd = (SlNative)handle;
        entry.events = (short)(forWriting ? POLLOUT : POLLIN);
        entry.revents = 0;

        ready = poll(&entry, 1, milliseconds);
        if (ready < 0) { sl_net_failed(error); return -1; }
        return ready > 0 ? 1 : 0;
    }
#endif
}
