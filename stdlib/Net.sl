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
///   UdpSocket     datagrams, which are not a stream and are not pretended to be
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

// ------------------------------------------------------------------ errors

/// Why an operation did not work. `None` is success.
///
/// These are the distinctions a program can act on rather than the platform's
/// whole list, for the reason `IOError` gives: the values are the same
/// everywhere, and neither `errno` nor a WSA code is.
public enum SocketError
{
    /// Nothing went wrong.
    None = 0,

    /// Nothing to read, or no room to write, on a socket that is not blocking.
    /// Not a failure -- it is what a non-blocking socket says instead of
    /// waiting.
    WouldBlock = 1,

    /// Nothing is listening there.
    Refused = 2,

    /// A timeout set on the socket ran out before the call finished.
    TimedOut = 3,
    /// No route to that address.
    Unreachable = 4,

    /// Something else already has that port.
    AddressInUse = 5,

    /// An operation that needs a connection, on a socket that has none.
    NotConnected = 6,

    /// The peer went away without closing: a reset rather than an ending.
    Reset = 7,

    /// The socket was closed before the call.
    Closed = 8,
    /// A signal arrived mid-call. Retrying is usually right.
    Interrupted = 9,
    /// Not permitted -- a low port without the privilege for it, or a
    /// broadcast send on a socket that was not asked to allow one.
    AccessDenied = 10,

    /// The name did not resolve.
    NoName = 11,

    /// The request made no sense for this socket in this state.
    Invalid = 12,
    /// The platform said something this enum has no name for.
    Unknown = 13,
}

/// Which internet protocol.
public enum AddressFamily
{
    /// Whichever the name resolves to.
    ///
    /// Only meaningful where a name is being resolved: connecting to one, or
    /// `Resolve`. There is no socket of no family, so opening one with `Any`
    /// is `SocketError.Invalid` -- which is what Linux says and Windows
    /// quietly does not, handing back an IPv4 socket instead.
    Any = 0,
    /// IPv4 only.
    IPv4 = 4,
    /// IPv6 only. Whether it also accepts IPv4 is the platform's default,
    /// not something set here.
    IPv6 = 6,
}

/// Which of the two shapes a socket has.
public enum SocketKind
{
    /// TCP: a stream, ordered and reliable, with no message boundaries.
    Stream = 1,

    /// UDP: datagrams, each whole or absent, in no particular order.
    Datagram = 2,
}

/// Which half of a connection to finish.
public enum SocketShutdown
{
    /// Stop receiving. The peer can still be written to.
    Receive = 0,
    /// Stop sending, which is what tells the peer there is no more coming.
    Send = 1,
    /// Stop both, which is what `Close` does first.
    Both = 2,
}

/// What went wrong, in words.
public String Describe(SocketError error)
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

// ------------------------------------------------------------- an endpoint

/// A host and a port, together, because they always travel together.
///
/// A struct rather than a class: it holds a `String`, so copying it retains --
/// which is fine, and is why it cannot cross `extern "C"` (§7.6). Nothing here
/// needs it to.
public struct EndPoint
{
    /// The address or name. An empty host means every address on this machine,
    /// which is what a server binds to.
    public String Host;

    /// The port. Zero asks the system to choose one, which `LocalEndPoint`
    /// will then say.
    public ushort Port;

    /// An endpoint, made in one expression.
    public static EndPoint At(String host, ushort port)
    {
        EndPoint made;
        made.Host = host;
        made.Port = port;
        return made;
    }

    /// Written the way one is written.
    public String Format()
    {
        // A bare IPv6 address contains colons, so the port needs the brackets
        // that a URL puts round one. IPv4 and a name do not.
        if (Host.Contains(':'))
        {
            return $"[{Host}]:{Port}";
        }
        return $"{Host}:{Port}";
    }
}

/// The first address a name resolves to, as text.
///
/// One address rather than the list: a list is only useful to something that
/// will try each in turn, and that is what connecting already does inside the
/// runtime, where it can try each socket as well as each address.
public Result<String, SocketError> Resolve(String host)
{
    return Resolve(host, AddressFamily.Any);
}

/// The first address a name resolves to in one family, as text.
///
/// `AddressFamily.Any` takes whichever the resolver prefers. Name it when the
/// socket that will use the address is already one family or the other, since
/// an IPv6 address cannot be connected to from an IPv4 socket.
public Result<String, SocketError> Resolve(String host, AddressFamily family)
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

// ---------------------------------------------------------------- a socket

/// One socket, and nothing above it.
///
/// `TcpListener`, `TcpClient` and `UdpSocket` are what a program should reach
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
    SocketKind _kind;
    bool _closed;

    /// A socket of a given family and kind, unbound and unconnected.
    public static Result<Socket, SocketError> Open(AddressFamily family, SocketKind kind)
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
    public static Result<Socket, SocketError> OpenConnected(
            String host, ushort port, AddressFamily family, SocketKind kind)
    {
        var made = new Socket(host, port, family, kind);
        if (!made.IsOpen)
            return Fail(made.Error);
        return Ok(made);
    }

    Socket(AddressFamily family, SocketKind kind)
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
    Socket(String host, ushort port, AddressFamily family, SocketKind kind)
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
    Socket(nuint accepted, AddressFamily family, SocketKind kind)
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
    public SocketKind Kind => _kind;

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
    public SocketError Bind(String host, ushort port)
    {
        if (_closed)
            return Note(SocketError.Closed);

        int code = 0;
        sl_socket_bind(_handle, host.ToPointer(), port, (int)_family, (int)_kind, &code);
        return Note((SocketError)code);
    }

    /// Binds to every address on this machine, which is what a server wants
    /// and what an empty host means to the resolver.
    public SocketError BindAny(ushort port) => Bind("", port);

    /// Starts accepting connections. `backlog` is how many may wait before
    /// the system refuses more; the platform may cap it lower than asked.
    ///
    /// Bind first -- listening on a socket that was never bound fails.
    public SocketError Listen(int backlog)
    {
        if (_closed)
            return Note(SocketError.Closed);

        int code = 0;
        sl_socket_listen(_handle, backlog, &code);
        return Note((SocketError)code);
    }

    /// Waits for a connection. The socket that comes back is open, or is not
    /// and says why.
    public Socket Accept()
    {
        if (_closed)
        {
            Note(SocketError.Closed);
            return new Socket(NoSocket, _family, _kind);
        }

        int code = 0;
        nuint accepted = sl_socket_accept(_handle, &code);
        Note((SocketError)code);
        return new Socket(accepted, _family, _kind);
    }

    /// Connects a socket that is already open.
    ///
    /// Only the first address of this socket's family is tried, because a
    /// socket whose connect failed cannot be used for a second attempt and
    /// this one is already made. `new Socket(host, port, family, kind)` is the
    /// form that tries them all, and the one a client should reach for.
    public SocketError Connect(String host, ushort port)
    {
        if (_closed)
            return Note(SocketError.Closed);

        int code = 0;
        sl_socket_connect(_handle, host.ToPointer(), port, (int)_family, (int)_kind, &code);
        return Note((SocketError)code);
    }

    /// This end of the connection.
    public EndPoint LocalEndPoint => Address(true);

    /// The other end.
    public EndPoint RemoteEndPoint => Address(false);

    // ------------------------------------------------------------- transfer

    /// Sends up to `count` bytes and reports how many went.
    ///
    /// Fewer than asked for is normal on a stream: the kernel took what fitted
    /// in its buffer. A loop over what is left is the caller's job, or
    /// `SendAll` is.
    public nuint Send(byte[] buffer, nuint offset, nuint count)
    {
        if (_closed)
        {
            Note(SocketError.Closed);
            return 0;
        }
        if (!RangeLiesWithin(buffer, offset, count))
        {
            Note(SocketError.Invalid);
            return 0;
        }
        if (count == 0)
            return 0;

        int code = 0;
        nuint sent = sl_socket_send(_handle, &buffer[offset], count, &code);
        Note((SocketError)code);
        return sent;
    }

    /// Sends all of it, or says why it could not.
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
    public SocketError SendText(String text)
    {
        if (_closed)
            return Note(SocketError.Closed);

        nuint at = 0;
        nuint size = text.ByteLength();

        while (at < size)
        {
            int code = 0;
            nuint sent = sl_socket_send(_handle, text.ToPointer() + at, size - at, &code);
            Note((SocketError)code);

            if (sent == 0)
                return _error == SocketError.None ? SocketError.Closed : _error;
            at = at + sent;
        }
        return SocketError.None;
    }

    /// Reads up to `count` bytes and reports how many arrived. Zero is the
    /// peer having finished, which is an ending rather than an error -- ask
    /// `Error` to tell the two apart.
    public nuint Receive(byte[] buffer, nuint offset, nuint count)
    {
        if (_closed)
        {
            Note(SocketError.Closed);
            return 0;
        }
        if (!RangeLiesWithin(buffer, offset, count))
        {
            Note(SocketError.Invalid);
            return 0;
        }
        if (count == 0)
            return 0;

        int code = 0;
        nuint read = sl_socket_receive(_handle, &buffer[offset], count, &code);
        Note((SocketError)code);
        return read;
    }

    // ------------------------------------------------------------ datagrams

    /// Sends one datagram. It arrives whole or not at all.
    public nuint SendTo(byte[] buffer, EndPoint target)
    {
        if (_closed)
        {
            Note(SocketError.Closed);
            return 0;
        }

        int code = 0;
        nuint sent = sl_socket_send_to(_handle, FirstByteAddressOrNull(buffer), buffer.Length,
                                       target.Host.ToPointer(), target.Port,
                                       (int)_family, &code);
        Note((SocketError)code);
        return sent;
    }

    /// Reads one datagram, and says where it came from.
    ///
    /// A datagram longer than the buffer is truncated and the rest is gone,
    /// which is what a datagram is: there is no second read to get the rest of
    /// one. The count is what fitted, and it is not an error.
    ///
    /// When the read fails, `from` is an empty host and port 0.
    public nuint ReceiveFrom(byte[] buffer, ref EndPoint from)
    {
        if (_closed)
        {
            Note(SocketError.Closed);
            return 0;
        }

        byte[64] host;
        ushort port = 0;
        int code = 0;

        host[0] = 0;
        nuint read = sl_socket_receive_from(_handle, FirstByteAddressOrNull(buffer), buffer.Length,
                                            &host[0], AddressSize, &port, &code);
        Note((SocketError)code);

        from.Host = Text.FromNullTerminated(&host[0]);
        from.Port = port;
        return read;
    }

    // -------------------------------------------------------------- options

    /// Whether a call waits. A socket that does not block answers
    /// `WouldBlock` instead of waiting, which is not a failure.
    public SocketError SetBlocking(bool blocking)
    {
        return Option(sl_socket_set_blocking(_handle, blocking ? 1 : 0, &_code), _code);
    }

    /// Turns off Nagle's algorithm, so a small write goes out now rather than
    /// waiting to be joined by the next one.
    public SocketError SetNoDelay(bool on)
    {
        return Option(sl_socket_set_no_delay(_handle, on ? 1 : 0, &_code), _code);
    }

    /// Lets a listener take a port that connections in TIME_WAIT still hold,
    /// which is what a server restarting wants.
    ///
    /// A no-op on Windows, deliberately: SO_REUSEADDR there lets a second
    /// process steal a port another is actively listening on, which is a
    /// different and much worse thing to ask for. Windows already allows the
    /// TIME_WAIT case without being asked.
    public SocketError SetReuseAddress(bool on)
    {
        return Option(sl_socket_set_reuse_address(_handle, on ? 1 : 0, &_code), _code);
    }

    /// Lets a datagram socket send to a broadcast address. Off by default,
    /// and meaningless on a stream socket.
    public SocketError SetBroadcast(bool on)
    {
        return Option(sl_socket_set_broadcast(_handle, on ? 1 : 0, &_code), _code);
    }

    /// Asks the system to probe an idle connection, so a peer that vanished
    /// without closing is eventually noticed. The interval is the platform's
    /// and is measured in hours by default, so this detects a dead peer rather
    /// than a slow one.
    public SocketError SetKeepAlive(bool on)
    {
        return Option(sl_socket_set_keep_alive(_handle, on ? 1 : 0, &_code), _code);
    }

    /// How long a read waits before giving up. Zero is forever.
    public SocketError SetReceiveTimeout(int milliseconds)
    {
        return Option(sl_socket_set_timeout(_handle, milliseconds, 1, &_code), _code);
    }

    /// How long a send waits before giving up. Zero is forever.
    public SocketError SetSendTimeout(int milliseconds)
    {
        return Option(sl_socket_set_timeout(_handle, milliseconds, 0, &_code), _code);
    }

    /// Finishes one direction, or both. The other end sees an ending rather
    /// than a reset, which is the difference between this and closing.
    public SocketError Shutdown(SocketShutdown how)
    {
        if (_closed)
            return Note(SocketError.Closed);

        int code = 0;
        sl_socket_shutdown(_handle, (int)how, &code);
        return Note((SocketError)code);
    }

    // -------------------------------------------------------------- waiting

    /// Waits until there is something to read, the time runs out, or it fails.
    /// A negative wait is forever.
    public bool WaitToRead(int milliseconds) => Wait(false, milliseconds);

    /// Waits until there is room to write. On a socket that is connecting
    /// without blocking, this is also how the connection finishing is seen:
    /// a connect that failed answers false, and `Error` says why.
    public bool WaitToWrite(int milliseconds) => Wait(true, milliseconds);

    // -------------------------------------------------------------- private

    /// Scratch for the option calls, which all have the same shape and would
    /// otherwise each need a local and four lines.
    int _code;

    SocketError Option(int ok, int code)
    {
        if (_closed)
            return Note(SocketError.Closed);
        return Note((SocketError)code);
    }

    bool Wait(bool forWriting, int milliseconds)
    {
        if (_closed)
        {
            Note(SocketError.Closed);
            return false;
        }

        int code = 0;
        int ready = sl_socket_wait(_handle, forWriting ? 1 : 0, milliseconds, &code);
        Note((SocketError)code);
        return ready == 1;
    }

    EndPoint Address(bool local)
    {
        EndPoint found;
        found.Host = "";
        found.Port = 0;

        if (_closed)
        {
            Note(SocketError.Closed);
            return found;
        }

        byte[64] host;
        ushort port = 0;
        int code = 0;

        int ok = local
            ? sl_socket_local(_handle, &host[0], AddressSize, &port, &code)
            : sl_socket_remote(_handle, &host[0], AddressSize, &port, &code);

        Note((SocketError)code);
        if (ok == 0)
            return found;

        found.Host = Text.FromNullTerminated(&host[0]);
        found.Port = port;
        return found;
    }

    /// Records an error and hands it back, so a caller can write
    /// `return Note(...)` and a reader sees both at once.
    SocketError Note(SocketError code)
    {
        _error = code;
        return code;
    }
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
    public static Result<TcpListener, SocketError> Listen(ushort port)
    {
        return Listen("", port, AddressFamily.IPv4, 16);
    }

    /// Listens on one address. `"127.0.0.1"` is the useful one: a service that
    /// only its own machine should reach says so here rather than in a
    /// firewall.
    public static Result<TcpListener, SocketError> Listen(String host, ushort port)
    {
        return Listen(host, port, AddressFamily.IPv4, 16);
    }

    /// Listens with everything named: the address, the port, the family and
    /// how many connections may queue.
    ///
    /// The other two overloads are this one with IPv4 and a backlog of 16.
    public static Result<TcpListener, SocketError> Listen(
            String host, ushort port, AddressFamily family, int backlog)
    {
        var opened = Socket.Open(family, SocketKind.Stream);
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

// --------------------------------------------------------------- TCP client

/// One TCP connection, and an `IStream`.
///
/// Being a stream is the point: a reader written against a file works over a
/// connection with nothing changed. `CanSeek` is false and `Seek` fails,
/// because a connection has no position to move to -- which is the honest
/// answer and the one an `IStream` is built to give.
///
///     var client = try TcpClient.Connect("example.com", 80u);
///     client.SendText("GET / HTTP/1.0\r\n\r\n");
///
/// The `IOError` an `IStream` reports is the nearest one to the socket error;
/// `SocketError()` has the exact one, and the two are there together because a
/// generic reader wants the first and code that knows it is a socket wants the
/// second.
public class TcpClient : IStream
{
    Socket _socket;
    bool _finished;

    /// Connects to a host and port.
    public static Result<TcpClient, SocketError> Connect(String host, ushort port)
    {
        return Connect(host, port, AddressFamily.Any);
    }

    /// Connects, naming the family rather than letting the resolver choose.
    ///
    /// Blocks until the connection is made or refused; there is no timeout
    /// here, and the system's own is measured in tens of seconds.
    public static Result<TcpClient, SocketError> Connect(
            String host, ushort port, AddressFamily family)
    {
        var opened = Socket.OpenConnected(host, port, family, SocketKind.Stream);
        if (!opened.Ok)
            return Fail(opened.Error);
        return Ok(new TcpClient(opened.Value));
    }

    /// Wraps a socket somebody else opened, which is what `Accept` produces.
    public TcpClient(Socket accepted)
    {
        _socket = accepted;
        _finished = false;
    }

    ~TcpClient() { Close(); }

    /// Whether the connection is there. False after the peer finished, after
    /// `Close`, and if connecting never worked.
    public bool IsConnected
    {
        get
        {
            return _socket.IsOpen && !_finished && _socket.Error == SocketError.None;
        }
    }

    /// The exact reason, which `Error` rounds off to fit an `IStream`.
    public SocketError SocketError() => _socket.Error;

    /// This end of the connection -- the address and the port the system
    /// chose for it.
    public EndPoint LocalEndPoint => _socket.LocalEndPoint;

    /// The other end: who is connected. What an accepted connection is asked
    /// to find out where it came from.
    public EndPoint RemoteEndPoint => _socket.RemoteEndPoint;

    /// The socket underneath, for an option this does not expose. Closing it
    /// closes the connection.
    public Socket Underlying => _socket;

    /// Sends all of `text`, looping until it has gone.
    public SocketError SendText(String text) => _socket.SendText(text);

    /// Sends all of `data`.
    public SocketError SendAll(byte[] data) => _socket.SendAll(data);

    /// Reads until the peer finishes, and gives back what arrived.
    ///
    /// For a protocol that ends by closing -- HTTP/1.0, or anything behind
    /// `shutdown` -- this is the whole body. For one that does not, it never
    /// returns, which is the caller's to know.
    public byte[] ReceiveAll()
    {
        var built = new List<byte>();
        var chunk = new byte[4096];

        while (true)
        {
            nuint read = _socket.Receive(chunk, 0, chunk.Length);
            if (read == 0)
            {
                _finished = true;
                break;
            }

            for (nuint i = 0; i < read; i++)
                built.Add(chunk[i]);
        }

        var all = new byte[built.Count];
        for (nuint i = 0; i < all.Length; i++)
            all[i] = built[i];
        return all;
    }

    /// The same, read as UTF-8. Anything malformed becomes U+FFFD, because the
    /// result is a `String` and a `String` is valid UTF-8 by invariant.
    public String ReceiveText()
    {
        var all = ReceiveAll();
        if (all.Length == 0)
            return "";
        return Text.FromBytes(&all[0], all.Length);
    }

    /// Waits up to `milliseconds` for something to read, answering whether
    /// there is. A peer that closed counts as readable -- the read that
    /// follows returns zero, which is how the ending is seen.
    public bool WaitToRead(int milliseconds) => _socket.WaitToRead(milliseconds);

    /// Waits up to `milliseconds` for room to write, answering whether there
    /// is. Only interesting once a send has filled the kernel's buffer.
    public bool WaitToWrite(int milliseconds) => _socket.WaitToWrite(milliseconds);

    // ----------------------------------------------------------- IStream

    /// True while the connection is open and the peer has not finished.
    public bool CanRead => _socket.IsOpen && !_finished;

    /// True while the connection is open. A peer that finished sending can
    /// still be written to, until it closes for real.
    public bool CanWrite => _socket.IsOpen;

    /// A connection has no position to move to.
    public bool CanSeek => false;

    /// Reads up to `count` bytes into `buffer` at `offset`, answering how
    /// many arrived.
    ///
    /// Fewer than asked for is normal and not an error: a stream delivers what
    /// has arrived. Zero means the peer finished, and `Error` distinguishes
    /// that from a failure.
    public nuint Read(byte[] buffer, nuint offset, nuint count)
    {
        if (count == 0u)
            return 0u;

        nuint read = _socket.Receive(buffer, offset, count);
        if (read == 0 && _socket.Error == SocketError.None)
            _finished = true;
        return read;
    }

    /// Writes up to `count` bytes from `buffer` at `offset`, answering how
    /// many went. A short write is normal; `SendAll` is the one that loops.
    public nuint Write(byte[] buffer, nuint offset, nuint count)
    {
        return _socket.Send(buffer, offset, count);
    }

    /// Not a position, and not pretended to be one.
    public long Position => -1;
    /// Not a length either. A connection does not know how much is coming.
    public long Length => -1;

    /// Always false. There is nowhere to seek to on a connection.
    public bool Seek(long offset, SeekOrigin origin) => false;

    /// Nothing is buffered here; the kernel decides when bytes leave.
    public void Flush() { }

    /// Ends the connection politely: shuts both directions down first, so the
    /// peer sees an ending rather than a reset, then closes. Idempotent, and
    /// the destructor calls it.
    public void Close()
    {
        if (_socket.IsOpen)
            _socket.Shutdown(SocketShutdown.Both);
        _socket.Close();
        _finished = true;
    }

    /// The socket error as the nearest `IOError`, so that a reader which knows
    /// nothing about sockets still gets something it can act on.
    public IOError Error
    {
        get
        {
            switch (_socket.Error)
            {
                case SocketError.None:         return IOError.None;
                case SocketError.Closed:       return IOError.Closed;
                case SocketError.NotConnected: return IOError.Closed;
                case SocketError.Reset:        return IOError.Closed;
                case SocketError.AccessDenied: return IOError.AccessDenied;
                case SocketError.NoName:       return IOError.NotFound;
                case SocketError.Refused:      return IOError.NotFound;
                case SocketError.Invalid:      return IOError.Invalid;
                default:                       return IOError.Unknown;
            }
        }
    }
}

// ---------------------------------------------------------------- UDP

/// Datagrams.
///
/// Not an `IStream`, and that is deliberate. A datagram arrives whole or not
/// at all, in no particular order, possibly twice; a stream is ordered,
/// reliable and has no message boundaries at all. Pretending the first is the
/// second is how a program comes to assume things about UDP that are not true.
///
///     var socket = try UdpSocket.Bind(9000u);
///     var from = EndPoint.At("", 0u);
///     var buffer = new byte[1500];
///     nuint got = socket.Receive(buffer, ref from);
public class UdpSocket
{
    Socket _socket;
    bool _ready;

    /// A socket that can send and not receive, because nothing bound it.
    public static Result<UdpSocket, SocketError> Datagram()
    {
        return Datagram(AddressFamily.IPv4);
    }

    /// The same, in a named family.
    public static Result<UdpSocket, SocketError> Datagram(AddressFamily family)
    {
        var opened = Socket.Open(family, SocketKind.Datagram);
        if (!opened.Ok)
            return Fail(opened.Error);
        return Ok(new UdpSocket(opened.Value));
    }

    /// A socket bound to a port, so it can receive. Port 0 asks the system to
    /// choose one, which `LocalEndPoint` will say.
    public static Result<UdpSocket, SocketError> Bind(ushort port)
    {
        return Bind("", port, AddressFamily.IPv4);
    }

    /// The same, on one address rather than all of them.
    public static Result<UdpSocket, SocketError> Bind(String host, ushort port)
    {
        return Bind(host, port, AddressFamily.IPv4);
    }

    /// Binds with everything named: the address, the port and the family.
    public static Result<UdpSocket, SocketError> Bind(
            String host, ushort port, AddressFamily family)
    {
        var opened = Socket.Open(family, SocketKind.Datagram);
        if (!opened.Ok)
            return Fail(opened.Error);

        var bound = opened.Value;
        var failure = bound.Bind(host, port);
        if (failure != SocketError.None)
            return Fail(failure);

        return Ok(new UdpSocket(bound));
    }

    UdpSocket(Socket opened)
    {
        _socket = opened;
        _ready = opened.IsOpen;
    }

    ~UdpSocket() { Close(); }

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
        return _socket.SendTo(data, EndPoint.At(host, port));
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
    public SocketError SetBroadcast(bool on) => _socket.SetBroadcast(on);

    /// How long `Receive` waits before giving up. Zero is forever.
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
