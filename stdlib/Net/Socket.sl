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

// ---------------------------------------------------------------- a socket

/// One socket, and nothing above it.
///
/// `TcpListener`, `TcpClient` and `UdpClient` are what a program should reach
/// for; this is what they are made of, and what is left when none of the three
/// is the shape of the problem.
///
/// Made through `Socket.Open`, which returns a `Result`. A constructor has to
/// return its own type, so it cannot say why an open failed -- the best it
/// could do is hand back a socket holding nothing, and nothing then forces the
/// check that would have caught it.
///
/// Closing is the destructor's job, so a socket that goes out of scope gives
/// its handle back whether or not `Close` was called.
public class Socket
{
    nuint _handle;
    SocketError _error;
    AddressFamily _family;
    SocketType _kind;
    bool _closed;

    /// A socket of a given family and kind, unbound and unconnected.
    ///
    /// @failure SocketError.Invalid  `AddressFamily.Any`, which is a question
    ///                               for a resolver rather than a family a
    ///                               socket can have
    /// @failure SocketError.Unknown  the platform refused a socket -- out of
    ///                               descriptors, among others
    /// @see Socket.OpenConnected
    public static Result<Socket, SocketError> Open(AddressFamily family, SocketType kind)
    {
        var made = new Socket(family, kind);
        if (!made.IsOpen)
            return Fail(made.Error);
        return Ok(made);
    }

    /// A socket already connected to a host and port.
    ///
    /// One step, because connecting is what decides the family: a caller with
    /// a name does not know whether it will get IPv4 or IPv6, so it cannot
    /// open first.
    ///
    /// @failure SocketError.NoName       the host did not resolve
    /// @failure SocketError.Refused      nothing is listening there
    /// @failure SocketError.TimedOut     no answer from any address the name
    ///                                   resolved to
    /// @failure SocketError.Unreachable  no route to any of them
    /// @failure SocketError.Unknown      the last address failed for a reason
    ///                                   with no case of its own
    /// @see Socket.Connect
    public static Result<Socket, SocketError> OpenConnected(
            String host, ushort port, AddressFamily family, SocketType kind)
    {
        var made = new Socket(host, port, family, kind);
        if (!made.IsOpen)
            return Fail(made.Error);
        return Ok(made);
    }

    Socket(AddressFamily family, SocketType kind)
    {
        this._family = family;
        this._kind = kind;

        // There is no socket of no family. `Any` is a question for a resolver,
        // and is answered by connecting rather than by opening.
        if (family == AddressFamily.Any)
        {
            _handle = NoSocket;
            _error = SocketError.Invalid;
            _closed = true;
            return;
        }

        int code = 0;
        _handle = sl_socket_open((int)family, (int)kind, &code);
        _error = (SocketError)code;
        _closed = _handle == NoSocket;
    }

    /// A socket that is already connected.
    ///
    /// Opening and connecting are one step because connecting is what decides
    /// the family: a caller with a name does not know whether it will get IPv4
    /// or IPv6, so it cannot open first. Each address the name resolved to gets
    /// a socket of its own family, and a socket whose connect failed is closed
    /// rather than retried -- which is the other reason this cannot be two
    /// steps.
    Socket(String host, ushort port, AddressFamily family, SocketType kind)
    {
        this._family = family;
        this._kind = kind;

        int code = 0;
        _handle = sl_socket_open_connected(host.ToPointer(), port, (int)family,
                                          (int)kind, &code);
        _error = (SocketError)code;
        _closed = _handle == NoSocket;
    }

    /// Wraps a handle the runtime already opened, which is what `Accept` has.
    Socket(nuint accepted, AddressFamily family, SocketType kind)
    {
        _handle = accepted;
        this._family = family;
        this._kind = kind;
        _error = SocketError.None;
        _closed = accepted == NoSocket;
    }

    ~Socket() { Close(); }

    /// Whether the handle is still live. False before a failed open and after
    /// `Close`; it says nothing about whether the peer is still there, which
    /// only a read can find out.
    public bool IsOpen => !_closed;

    /// The last error, or `None`. Set by every call that failed, and cleared
    /// by the next one that did not.
    public SocketError Error => _error;

    /// Which family the socket was opened for. Fixed at open.
    public AddressFamily Family => _family;

    /// Stream or datagram. Fixed at open.
    public SocketType Kind => _kind;

    /// The handle itself, for a platform call this wrapper does not make.
    /// A `SOCKET` on Windows and a file descriptor on everything else.
    public nuint Handle => _handle;

    /// Closes the handle. Idempotent, and the destructor calls it, so a
    /// socket that goes out of scope is not leaked.
    ///
    /// Closing a stream socket without `Shutdown` first leaves what the peer
    /// sees up to the platform and to what is still unread; `TcpClient.Close`
    /// shuts both directions down first, which is what ends one politely.
    public void Close()
    {
        if (_closed)
            return;
        sl_socket_close(_handle);
        _closed = true;
        _handle = NoSocket;
    }

    // ------------------------------------------------------------ addresses

    /// Takes the address, and the port. Port 0 asks the system to choose one,
    /// which `LocalEndPoint` will then say.
    ///
    /// @failure SocketError.Closed        the socket was closed before the call
    /// @failure SocketError.NoName        the host did not resolve
    /// @failure SocketError.AddressInUse  something else holds that port, or
    ///                                    this machine has no such address
    /// @failure SocketError.AccessDenied  a port this process may not take
    /// @failure SocketError.Unknown       the platform reported something with
    ///                                    no case of its own
    /// @see Socket.Listen
    public SocketError Bind(String host, ushort port)
    {
        if (_closed)
            return RecordError(SocketError.Closed);

        int code = 0;
        sl_socket_bind(_handle, host.ToPointer(), port, (int)_family, (int)_kind, &code);
        return RecordError((SocketError)code);
    }

    /// Binds to every address on this machine, which is what a server wants
    /// and what an empty host means to the resolver.
    ///
    /// @failure SocketError.Closed        the socket was closed before the call
    /// @failure SocketError.AddressInUse  something else holds that port
    /// @failure SocketError.AccessDenied  a port this process may not take
    /// @failure SocketError.Unknown       the platform reported something with
    ///                                    no case of its own
    /// @see Socket.Bind
    public SocketError BindAny(ushort port) => Bind("", port);

    /// Starts accepting connections. `backlog` is how many may wait before
    /// the system refuses more; the platform may cap it lower than asked.
    ///
    /// Bind first -- listening on a socket that was never bound fails.
    ///
    /// @failure SocketError.Closed        the socket was closed before the call
    /// @failure SocketError.Invalid       the socket was never bound, or is a
    ///                                    datagram socket, which has nothing to
    ///                                    listen for
    /// @failure SocketError.AddressInUse  another socket is already listening
    ///                                    on that address
    /// @failure SocketError.Unknown       the platform reported something with
    ///                                    no case of its own
    /// @see Socket.Bind
    /// @seealso Socket.Accept
    public SocketError Listen(int backlog)
    {
        if (_closed)
            return RecordError(SocketError.Closed);

        int code = 0;
        sl_socket_listen(_handle, backlog, &code);
        return RecordError((SocketError)code);
    }

    /// Waits for a connection. The socket that comes back is open, or is not
    /// and says why.
    public Socket Accept()
    {
        if (_closed)
        {
            RecordError(SocketError.Closed);
            return new Socket(NoSocket, _family, _kind);
        }

        int code = 0;
        nuint accepted = sl_socket_accept(_handle, &code);
        RecordError((SocketError)code);
        return new Socket(accepted, _family, _kind);
    }

    /// Connects a socket that is already open.
    ///
    /// Only the first address of this socket's family is tried, because a
    /// socket whose connect failed cannot be used for a second attempt and
    /// this one is already made. `Socket.OpenConnected` is the form that tries
    /// them all, and the one a client should reach for.
    ///
    /// @failure SocketError.Closed       the socket was closed before the call
    /// @failure SocketError.NoName       the host did not resolve in this
    ///                                   socket's family
    /// @failure SocketError.WouldBlock   a socket that does not block, where
    ///                                   the connection is still being made;
    ///                                   `WaitToWrite` is how it finishes
    /// @failure SocketError.Refused      nothing is listening there
    /// @failure SocketError.TimedOut     no answer from that address
    /// @failure SocketError.Unreachable  no route to it
    /// @failure SocketError.Unknown      the platform reported something with
    ///                                   no case of its own
    /// @see Socket.OpenConnected
    public SocketError Connect(String host, ushort port)
    {
        if (_closed)
            return RecordError(SocketError.Closed);

        int code = 0;
        sl_socket_connect(_handle, host.ToPointer(), port, (int)_family, (int)_kind, &code);
        return RecordError((SocketError)code);
    }

    /// This end of the connection.
    public EndPoint LocalEndPoint => QueryEndPoint(true);

    /// The other end.
    public EndPoint RemoteEndPoint => QueryEndPoint(false);

    // ------------------------------------------------------------- transfer

    /// Sends up to `count` bytes and reports how many went.
    ///
    /// Fewer than asked for is normal on a stream: the kernel took what fitted
    /// in its buffer. A loop over what is left is the caller's job, or
    /// `SendAll` is.
    ///
    /// @param buffer  where the bytes come from
    /// @param offset  where in it to start
    /// @param count   how many to send from there
    /// @see Socket.SendAll
    /// @seealso Socket.Receive
    public nuint Send(byte[] buffer, nuint offset, nuint count)
    {
        if (_closed)
        {
            RecordError(SocketError.Closed);
            return 0;
        }
        if (!RangeLiesWithin(buffer, offset, count))
        {
            RecordError(SocketError.Invalid);
            return 0;
        }
        if (count == 0)
            return 0;

        int code = 0;
        nuint sent = sl_socket_send(_handle, &buffer[offset], count, &code);
        RecordError((SocketError)code);
        return sent;
    }

    /// Sends all of it, or says why it could not.
    ///
    /// @failure SocketError.Closed        the socket was closed, or the peer
    ///                                    took nothing and reported nothing
    /// @failure SocketError.NotConnected  the socket has no peer to send to
    /// @failure SocketError.Reset         the peer went away mid-send
    /// @failure SocketError.TimedOut      a send timeout ran out
    /// @failure SocketError.WouldBlock    a socket that does not block, with no
    ///                                    room left for the rest
    /// @failure SocketError.Unknown       the platform reported something with
    ///                                    no case of its own
    /// @see Socket.Send
    public SocketError SendAll(byte[] buffer)
    {
        nuint at = 0;
        while (at < buffer.Length)
        {
            nuint sent = Send(buffer, at, buffer.Length - at);
            if (sent == 0)
                return _error == SocketError.None ? SocketError.Closed : _error;
            at = at + sent;
        }
        return SocketError.None;
    }

    /// Sends the UTF-8 bytes of `text`, which is what a String already holds,
    /// so nothing is converted or copied on the way.
    ///
    /// @failure SocketError.Closed        the socket was closed, or the peer
    ///                                    took nothing and reported nothing
    /// @failure SocketError.NotConnected  the socket has no peer to send to
    /// @failure SocketError.Reset         the peer went away mid-send
    /// @failure SocketError.TimedOut      a send timeout ran out
    /// @failure SocketError.WouldBlock    a socket that does not block, with no
    ///                                    room left for the rest
    /// @failure SocketError.Unknown       the platform reported something with
    ///                                    no case of its own
    /// @see Socket.SendAll
    public SocketError SendText(String text)
    {
        if (_closed)
            return RecordError(SocketError.Closed);

        nuint at = 0;
        nuint size = text.ByteLength();

        while (at < size)
        {
            int code = 0;
            nuint sent = sl_socket_send(_handle, text.ToPointer() + at, size - at, &code);
            RecordError((SocketError)code);

            if (sent == 0)
                return _error == SocketError.None ? SocketError.Closed : _error;
            at = at + sent;
        }
        return SocketError.None;
    }

    /// Reads up to `count` bytes and reports how many arrived. Zero is the
    /// peer having finished, which is an ending rather than an error -- ask
    /// `Error` to tell the two apart.
    ///
    /// @param buffer  where the bytes go
    /// @param offset  where in it to start writing them
    /// @param count   how many to make room for
    /// @see Socket.Send
    public nuint Receive(byte[] buffer, nuint offset, nuint count)
    {
        if (_closed)
        {
            RecordError(SocketError.Closed);
            return 0;
        }
        if (!RangeLiesWithin(buffer, offset, count))
        {
            RecordError(SocketError.Invalid);
            return 0;
        }
        if (count == 0)
            return 0;

        int code = 0;
        nuint read = sl_socket_receive(_handle, &buffer[offset], count, &code);
        RecordError((SocketError)code);
        return read;
    }

    // ------------------------------------------------------------ datagrams

    /// Sends one datagram. It arrives whole or not at all.
    ///
    /// @see Socket.ReceiveFrom
    public nuint SendTo(byte[] buffer, EndPoint target)
    {
        if (_closed)
        {
            RecordError(SocketError.Closed);
            return 0;
        }

        int code = 0;
        nuint sent = sl_socket_send_to(_handle, FirstByteAddressOrNull(buffer), buffer.Length,
                                       target.Host.ToPointer(), target.Port,
                                       (int)_family, &code);
        RecordError((SocketError)code);
        return sent;
    }

    /// Reads one datagram, and says where it came from.
    ///
    /// A datagram longer than the buffer is truncated and the rest is gone,
    /// which is what a datagram is: there is no second read to get the rest of
    /// one. The count is what fitted, and it is not an error.
    ///
    /// When the read fails, `from` is an empty host and port 0.
    ///
    /// @param buffer  where the datagram goes, from its first byte
    /// @param from    filled in with where it came from
    /// @see Socket.SendTo
    public nuint ReceiveFrom(byte[] buffer, ref EndPoint from)
    {
        if (_closed)
        {
            RecordError(SocketError.Closed);
            return 0;
        }

        byte[64] host;
        ushort port = 0;
        int code = 0;

        host[0] = 0;
        nuint read = sl_socket_receive_from(_handle, FirstByteAddressOrNull(buffer), buffer.Length,
                                            &host[0], AddressSize, &port, &code);
        RecordError((SocketError)code);

        from.Host = Text.FromNullTerminated(&host[0]);
        from.Port = port;
        return read;
    }

    // -------------------------------------------------------------- options

    /// Whether a call waits. A socket that does not block answers
    /// `WouldBlock` instead of waiting, which is not a failure.
    ///
    /// @failure SocketError.Closed   the socket was closed before the call
    /// @failure SocketError.Unknown  the platform refused the change
    public SocketError SetBlocking(bool blocking)
    {
        return CheckOption(sl_socket_set_blocking(_handle, blocking ? 1 : 0, &_code), _code);
    }

    /// Turns off Nagle's algorithm, so a small write goes out now rather than
    /// waiting to be joined by the next one.
    ///
    /// @failure SocketError.Closed   the socket was closed before the call
    /// @failure SocketError.Unknown  the platform refused the option -- a
    ///                               datagram socket has no Nagle to turn off
    public SocketError SetNoDelay(bool on)
    {
        return CheckOption(sl_socket_set_no_delay(_handle, on ? 1 : 0, &_code), _code);
    }

    /// Lets a listener take a port that connections in TIME_WAIT still hold,
    /// which is what a server restarting wants.
    ///
    /// A no-op on Windows, deliberately: SO_REUSEADDR there lets a second
    /// process steal a port another is actively listening on, which is a
    /// different and much worse thing to ask for. Windows already allows the
    /// TIME_WAIT case without being asked.
    ///
    /// @failure SocketError.Closed   the socket was closed before the call
    /// @failure SocketError.Unknown  the platform refused the option
    public SocketError SetReuseAddress(bool on)
    {
        return CheckOption(sl_socket_set_reuse_address(_handle, on ? 1 : 0, &_code), _code);
    }

    /// Lets a datagram socket send to a broadcast address. Off by default,
    /// and meaningless on a stream socket.
    ///
    /// @failure SocketError.Closed   the socket was closed before the call
    /// @failure SocketError.Unknown  the platform refused the option, which is
    ///                               what a stream socket does with it
    public SocketError SetBroadcast(bool on)
    {
        return CheckOption(sl_socket_set_broadcast(_handle, on ? 1 : 0, &_code), _code);
    }

    /// Asks the system to probe an idle connection, so a peer that vanished
    /// without closing is eventually noticed. The interval is the platform's
    /// and is measured in hours by default, so this detects a dead peer rather
    /// than a slow one.
    ///
    /// @failure SocketError.Closed   the socket was closed before the call
    /// @failure SocketError.Unknown  the platform refused the option
    public SocketError SetKeepAlive(bool on)
    {
        return CheckOption(sl_socket_set_keep_alive(_handle, on ? 1 : 0, &_code), _code);
    }

    /// How long a read waits before giving up. Zero is forever.
    ///
    /// @failure SocketError.Closed   the socket was closed before the call
    /// @failure SocketError.Unknown  the platform refused the option
    /// @see Socket.SetSendTimeout
    public SocketError SetReceiveTimeout(int milliseconds)
    {
        return CheckOption(sl_socket_set_timeout(_handle, milliseconds, 1, &_code), _code);
    }

    /// How long a send waits before giving up. Zero is forever.
    ///
    /// @failure SocketError.Closed   the socket was closed before the call
    /// @failure SocketError.Unknown  the platform refused the option
    /// @see Socket.SetReceiveTimeout
    public SocketError SetSendTimeout(int milliseconds)
    {
        return CheckOption(sl_socket_set_timeout(_handle, milliseconds, 0, &_code), _code);
    }

    /// Finishes one direction, or both. The other end sees an ending rather
    /// than a reset, which is the difference between this and closing.
    ///
    /// @failure SocketError.Closed        the socket was closed before the call
    /// @failure SocketError.NotConnected  there is no connection to finish
    /// @failure SocketError.Unknown       the platform reported something with
    ///                                    no case of its own
    /// @see Socket.Close
    public SocketError Shutdown(SocketShutdown how)
    {
        if (_closed)
            return RecordError(SocketError.Closed);

        int code = 0;
        sl_socket_shutdown(_handle, (int)how, &code);
        return RecordError((SocketError)code);
    }

    // -------------------------------------------------------------- waiting

    /// Waits until there is something to read, the time runs out, or it fails.
    /// A negative wait is forever.
    public bool WaitToRead(int milliseconds) => WaitUntilReady(false, milliseconds);

    /// Waits until there is room to write. On a socket that is connecting
    /// without blocking, this is also how the connection finishing is seen:
    /// a connect that failed answers false, and `Error` says why.
    public bool WaitToWrite(int milliseconds) => WaitUntilReady(true, milliseconds);

    // -------------------------------------------------------------- private

    /// Scratch for the option calls, which all have the same shape and would
    /// otherwise each need a local and four lines.
    int _code;

    SocketError CheckOption(int ok, int code)
    {
        if (_closed)
            return RecordError(SocketError.Closed);
        return RecordError((SocketError)code);
    }

    bool WaitUntilReady(bool forWriting, int milliseconds)
    {
        if (_closed)
        {
            RecordError(SocketError.Closed);
            return false;
        }

        int code = 0;
        int ready = sl_socket_wait(_handle, forWriting ? 1 : 0, milliseconds, &code);
        RecordError((SocketError)code);
        return ready == 1;
    }

    EndPoint QueryEndPoint(bool local)
    {
        EndPoint found;
        found.Host = "";
        found.Port = 0;

        if (_closed)
        {
            RecordError(SocketError.Closed);
            return found;
        }

        byte[64] host;
        ushort port = 0;
        int code = 0;

        int ok = local
            ? sl_socket_local(_handle, &host[0], AddressSize, &port, &code)
            : sl_socket_remote(_handle, &host[0], AddressSize, &port, &code);

        RecordError((SocketError)code);
        if (ok == 0)
            return found;

        found.Host = Text.FromNullTerminated(&host[0]);
        found.Port = port;
        return found;
    }

    /// Records an error and hands it back, so a caller can write
    /// `return RecordError(...)` and a reader sees both at once.
    SocketError RecordError(SocketError code)
    {
        _error = code;
        return code;
    }
}
