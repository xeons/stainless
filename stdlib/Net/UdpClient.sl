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

module Standard.Net;

import Standard.Collections;
import Standard.IO;
import Standard.Text;

// ---------------------------------------------------------------- UDP

/// Datagrams.
///
/// Not an `IStream`, and that is deliberate. A datagram arrives whole or not
/// at all, in no particular order, possibly twice; a stream is ordered,
/// reliable and has no message boundaries at all. Pretending the first is the
/// second is how a program comes to assume things about UDP that are not true.
///
///     var socket = try UdpClient.Bind(9000u);
///     var from = EndPoint.Create("", 0u);
///     var buffer = new byte[1500];
///     nuint got = socket.Receive(buffer, ref from);
public class UdpClient
{
    Socket _socket;
    bool _ready;

    /// A socket that can send and not receive, because nothing bound it.
    ///
    /// @failure SocketError.Unknown  the platform refused a socket -- out of
    ///                               descriptors, among others
    /// @see UdpClient.Bind
    public static Result<UdpClient, SocketError> Create()
    {
        return Create(AddressFamily.IPv4);
    }

    /// The same, in a named family.
    ///
    /// @failure SocketError.Invalid  `AddressFamily.Any`, which no socket can
    ///                               be opened in
    /// @failure SocketError.Unknown  the platform refused a socket
    public static Result<UdpClient, SocketError> Create(AddressFamily family)
    {
        var opened = Socket.Open(family, SocketType.Datagram);
        if (!opened.Ok)
            return Fail(opened.Error);
        return Ok(new UdpClient(opened.Value));
    }

    /// A socket bound to a port, so it can receive. Port 0 asks the system to
    /// choose one, which `LocalEndPoint` will say.
    ///
    /// @failure SocketError.AddressInUse  something else holds that port
    /// @failure SocketError.AccessDenied  a port this process may not take
    /// @failure SocketError.Unknown       the open or the bind failed for a
    ///                                    reason with no case of its own
    /// @see UdpClient.Create
    public static Result<UdpClient, SocketError> Bind(ushort port)
    {
        return Bind("", port, AddressFamily.IPv4);
    }

    /// The same, on one address rather than all of them.
    ///
    /// @failure SocketError.NoName        the host did not resolve, or is not
    ///                                    an address this machine has
    /// @failure SocketError.AddressInUse  something else holds that port
    /// @failure SocketError.AccessDenied  a port this process may not take
    /// @failure SocketError.Unknown       the open or the bind failed for a
    ///                                    reason with no case of its own
    public static Result<UdpClient, SocketError> Bind(String host, ushort port)
    {
        return Bind(host, port, AddressFamily.IPv4);
    }

    /// Binds with everything named: the address, the port and the family.
    ///
    /// @param host    which address to take, empty for every one of them
    /// @param port    which port to take, 0 to be given one
    /// @param family  which family to bind in
    /// @failure SocketError.Invalid       `AddressFamily.Any`, which no socket
    ///                                    can be opened in
    /// @failure SocketError.NoName        the host did not resolve in that
    ///                                    family
    /// @failure SocketError.AddressInUse  something else holds that port
    /// @failure SocketError.AccessDenied  a port this process may not take
    /// @failure SocketError.Unknown       the open or the bind failed for a
    ///                                    reason with no case of its own
    public static Result<UdpClient, SocketError> Bind(
            String host, ushort port, AddressFamily family)
    {
        var opened = Socket.Open(family, SocketType.Datagram);
        if (!opened.Ok)
            return Fail(opened.Error);

        var bound = opened.Value;
        var failure = bound.Bind(host, port);
        if (failure != SocketError.None)
            return Fail(failure);

        return Ok(new UdpClient(bound));
    }

    UdpClient(Socket opened)
    {
        _socket = opened;
        _ready = opened.IsOpen;
    }

    ~UdpClient() { Close(); }

    /// Whether the socket is usable. False after `Close`, and after an open
    /// that did not work.
    public bool IsOpen => _ready;

    /// The last error from the socket underneath, or `None`.
    public SocketError Error => _socket.Error;

    /// Where it is bound. With port 0 this is how the port the system chose is
    /// found out; an unbound socket answers with nothing useful.
    public EndPoint LocalEndPoint => _socket.LocalEndPoint;

    /// The socket underneath, for an option this does not expose.
    public Socket Underlying => _socket;

    /// Sends one datagram. The count back is how many bytes went, which for a
    /// datagram is all of them or none.
    public nuint Send(byte[] data, String host, ushort port)
    {
        return _socket.SendTo(data, EndPoint.Create(host, port));
    }

    /// Sends one datagram of UTF-8. The encoded length is what goes on the
    /// wire, so a string of multi-byte characters is longer than its character
    /// count -- which matters against the roughly 1500-byte practical limit.
    public nuint SendText(String text, String host, ushort port)
    {
        return Send(text.ToBytes(), host, port);
    }

    /// Reads one datagram and says where it came from. A datagram longer than
    /// the buffer is truncated, and the rest is gone -- there is no second
    /// read to collect it.
    public nuint Receive(byte[] buffer, ref EndPoint from)
    {
        return _socket.ReceiveFrom(buffer, ref from);
    }

    /// Waits up to `milliseconds` for a datagram to arrive, answering whether
    /// one has. The way to poll without blocking forever on an empty socket.
    public bool WaitToRead(int milliseconds) => _socket.WaitToRead(milliseconds);

    /// Lets this socket send to a broadcast address.
    ///
    /// @failure SocketError.Closed   the socket was closed before the call
    /// @failure SocketError.Unknown  the platform refused the option
    public SocketError SetBroadcast(bool on) => _socket.SetBroadcast(on);

    /// How long `Receive` waits before giving up. Zero is forever.
    ///
    /// @failure SocketError.Closed   the socket was closed before the call
    /// @failure SocketError.Unknown  the platform refused the option
    public SocketError SetReceiveTimeout(int milliseconds)
    {
        return _socket.SetReceiveTimeout(milliseconds);
    }

    /// Closes the socket. Idempotent, and the destructor calls it.
    public void Close()
    {
        _ready = false;
        _socket.Close();
    }
}
