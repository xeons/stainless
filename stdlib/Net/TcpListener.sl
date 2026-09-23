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

// ------------------------------------------------------------- TCP listener

/// A socket that accepts connections, and does nothing else.
///
/// Opening, binding and listening are one step, because there is no useful
/// state between them: a listener that exists and is not listening is a thing
/// to check for and never a thing to want. So the step is `Listen`, and it
/// says which of the three failed.
///
///     var server = try TcpListener.Listen(8080u);
///
///     var client = server.Accept();
///     while (client.IsConnected) { ... }
public class TcpListener
{
    Socket _socket;
    bool _listening;

    /// Listens on every address this machine has.
    ///
    /// @failure SocketError.AddressInUse  something else holds that port
    /// @failure SocketError.AccessDenied  a port this process may not take
    /// @failure SocketError.Unknown       the open, the bind or the listen
    ///                                    failed for a reason with no case of
    ///                                    its own
    public static Result<TcpListener, SocketError> Listen(ushort port)
    {
        return Listen("", port, AddressFamily.IPv4, 16);
    }

    /// Listens on one address. `"127.0.0.1"` is the useful one: a service that
    /// only its own machine should reach says so here rather than in a
    /// firewall.
    ///
    /// @failure SocketError.NoName        the host did not resolve, or is not
    ///                                    an address this machine has
    /// @failure SocketError.AddressInUse  something else holds that port
    /// @failure SocketError.AccessDenied  a port this process may not take
    /// @failure SocketError.Unknown       the open, the bind or the listen
    ///                                    failed for a reason with no case of
    ///                                    its own
    public static Result<TcpListener, SocketError> Listen(String host, ushort port)
    {
        return Listen(host, port, AddressFamily.IPv4, 16);
    }

    /// Listens with everything named: the address, the port, the family and
    /// how many connections may queue.
    ///
    /// The other two overloads are this one with IPv4 and a backlog of 16.
    ///
    /// @param host     which address to take, empty for every one of them
    /// @param port     which port to take, 0 to be given one
    /// @param family   which family to listen in
    /// @param backlog  how many connections may queue before the system refuses
    ///                 more
    /// @failure SocketError.Invalid       `AddressFamily.Any`, which no socket
    ///                                    can be opened in
    /// @failure SocketError.NoName        the host did not resolve in that
    ///                                    family
    /// @failure SocketError.AddressInUse  something else holds that port
    /// @failure SocketError.AccessDenied  a port this process may not take
    /// @failure SocketError.Unknown       the open, the bind or the listen
    ///                                    failed for a reason with no case of
    ///                                    its own
    public static Result<TcpListener, SocketError> Listen(
            String host, ushort port, AddressFamily family, int backlog)
    {
        var opened = Socket.Open(family, SocketType.Stream);
        if (!opened.Ok)
            return Fail(opened.Error);

        var made = new TcpListener(opened.Value, host, port, backlog);
        if (!made.IsListening)
            return Fail(made.Error);
        return Ok(made);
    }

    TcpListener(Socket opened, String host, ushort port, int backlog)
    {
        _socket = opened;
        _listening = false;

        _socket.SetReuseAddress(true);
        if (_socket.Bind(host, port) != SocketError.None)
            return;
        if (_socket.Listen(backlog) != SocketError.None)
            return;

        _listening = true;
    }

    ~TcpListener() { Close(); }

    /// Whether it bound and listened. False means the constructor gave up
    /// part-way, and `Error` says where.
    public bool IsListening => _listening;

    /// The last error from the socket underneath, or `None`.
    public SocketError Error => _socket.Error;

    /// Where it is listening. With port 0 this is how the port the system
    /// chose is found out.
    public EndPoint LocalEndPoint => _socket.LocalEndPoint;

    /// The socket underneath, for an option this does not expose.
    public Socket Underlying => _socket;

    /// Waits for a connection. The client that comes back is connected, or is
    /// not and says why.
    public TcpClient Accept()
    {
        return new TcpClient(_socket.Accept());
    }

    /// Whether a connection is waiting, without blocking to find out.
    public bool Pending(int milliseconds)
    {
        return _socket.WaitToRead(milliseconds);
    }

    /// Stops listening and closes the socket. Connections already accepted
    /// are their own sockets and are unaffected.
    public void Close()
    {
        _listening = false;
        _socket.Close();
    }
}
