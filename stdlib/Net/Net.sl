// Stainless - an experimental general-purpose language.
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

/// Sockets, the same on every platform.
///
/// Winsock and BSD sockets are the same design that disagrees about every
/// detail -- a handle that is pointer-sized on one and a file descriptor on the
/// other, errors through WSAGetLastError or errno, closesocket or close, and a
/// startup call one of them will not work without. All of that is in
/// runtime/socket.c, for the reason every other platform difference is: a
/// Stainless enum crosses the boundary as itself and an errno does not.
///
/// Four types, and the choice between them is what the program is doing rather
/// than what the platform offers:
///
///   TcpListener   accepts connections
///   TcpClient     one connection, and an `IStream`, so everything that already
///                 reads a stream reads a socket
///   UdpClient     datagrams, which are not a stream and are not pretended to be
///   Socket        the one underneath, for anything the three do not cover
///
/// `TcpClient` being an `IStream` is the point of the design. A reader written
/// against a file works over a connection with nothing changed, because there
/// was never anything file-shaped in it.
module Standard.Net;

import Standard.Collections;
import Standard.IO;
import Standard.Text;

extern "C"
{
    nuint sl_socket_open(int family, int kind, int* error);
    void  sl_socket_close(nuint handle);
    int   sl_socket_shutdown(nuint handle, int how, int* error);

    int   sl_socket_bind(nuint handle, byte* host, ushort port, int family,
                         int kind, int* error);
    int   sl_socket_listen(nuint handle, int backlog, int* error);
    nuint sl_socket_accept(nuint handle, int* error);
    int   sl_socket_connect(nuint handle, byte* host, ushort port, int family,
                            int kind, int* error);
    nuint sl_socket_open_connected(byte* host, ushort port, int family, int kind,
                                   int* error);

    nuint sl_socket_send(nuint handle, byte* data, nuint count, int* error);
    nuint sl_socket_receive(nuint handle, byte* data, nuint count, int* error);
    nuint sl_socket_send_to(nuint handle, byte* data, nuint count, byte* host,
                            ushort port, int family, int* error);
    nuint sl_socket_receive_from(nuint handle, byte* data, nuint count, byte* host,
                                 nuint hostSize, ushort* port, int* error);

    int sl_socket_set_blocking(nuint handle, int blocking, int* error);
    int sl_socket_set_no_delay(nuint handle, int on, int* error);
    int sl_socket_set_reuse_address(nuint handle, int on, int* error);
    int sl_socket_set_broadcast(nuint handle, int on, int* error);
    int sl_socket_set_keep_alive(nuint handle, int on, int* error);
    int sl_socket_set_timeout(nuint handle, int milliseconds, int receiving, int* error);

    int sl_socket_local(nuint handle, byte* host, nuint size, ushort* port, int* error);
    int sl_socket_remote(nuint handle, byte* host, nuint size, ushort* port, int* error);
    int sl_socket_resolve(byte* host, int family, byte* out, nuint size, int* error);
    int sl_socket_wait(nuint handle, int forWriting, int milliseconds, int* error);
}

/// What went wrong, in words.
///
/// @see SocketError
public String DescribeSocketError(SocketError error)
{
    switch (error)
    {
        case SocketError.None:         return "no error";
        case SocketError.WouldBlock:   return "nothing ready yet";
        case SocketError.Refused:      return "the connection was refused";
        case SocketError.TimedOut:     return "it timed out";
        case SocketError.Unreachable:  return "there is no route to that host";
        case SocketError.AddressInUse: return "that address is already in use";
        case SocketError.NotConnected: return "the socket is not connected";
        case SocketError.Reset:        return "the peer reset the connection";
        case SocketError.Closed:       return "the socket is closed";
        case SocketError.Interrupted:  return "it was interrupted";
        case SocketError.AccessDenied: return "access denied";
        case SocketError.NoName:       return "that name did not resolve";
        case SocketError.Invalid:      return "that request made no sense";
        default:                       return "it failed for an unknown reason";
    }
}

/// The largest address text either family produces, plus the terminator. An
/// IPv6 address with an embedded IPv4 tail and a scope id is the long case.
const nuint AddressSize = 64;

/// What the runtime hands back for a socket that was never opened.
const nuint NoSocket = 18446744073709551615u;

/// The first address a name resolves to, as text.
///
/// One address rather than the list: a list is only useful to something that
/// will try each in turn, and that is what connecting already does inside the
/// runtime, where it can try each socket as well as each address.
///
/// @failure SocketError.NoName   the name did not resolve, or resolved to an
///                               address the platform would not write out
/// @failure SocketError.Unknown  the platform's networking could not be started
public Result<String, SocketError> ResolveHost(String host)
{
    return ResolveHost(host, AddressFamily.Any);
}

/// The first address a name resolves to in one family, as text.
///
/// `AddressFamily.Any` takes whichever the resolver prefers. Name it when the
/// socket that will use the address is already one family or the other, since
/// an IPv6 address cannot be connected to from an IPv4 socket.
///
/// @param host    the name or literal address to look up
/// @param family  which family to take an address from
/// @failure SocketError.NoName   the name did not resolve in that family, or
///                               resolved to an address the platform would not
///                               write out
/// @failure SocketError.Unknown  the platform's networking could not be started
public Result<String, SocketError> ResolveHost(String host, AddressFamily family)
{
    byte[64] buffer;
    int code = 0;

    if (sl_socket_resolve(host.ToPointer(), (int)family, &buffer[0],
                          AddressSize, &code) == 0)
    {
        return Fail(code == 0 ? SocketError.NoName : (SocketError)code);
    }
    return Ok(Text.FromNullTerminated(&buffer[0]));
}

// Whether `count` bytes from `offset` lie inside `buffer`, asked so that the
// sum cannot wrap.
bool RangeLiesWithin(byte[] buffer, nuint offset, nuint count)
{
    return offset <= buffer.Length && count <= buffer.Length - offset;
}

// An empty array has no first element to take the address of, and an empty
// datagram is still one to send or receive.
byte* FirstByteAddressOrNull(byte[] buffer)
{
    if (buffer.Length == 0u)
        return null;
    return &buffer[0];
}
