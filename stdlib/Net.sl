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

// Sockets, the same on every platform.
//
// Winsock and BSD sockets are the same design that disagrees about every
// detail -- a handle that is pointer-sized on one and a file descriptor on the
// other, errors through WSAGetLastError or errno, closesocket or close, and a
// startup call one of them will not work without. All of that is in
// runtime/socket.c, for the reason every other platform difference is: a
// Stainless enum crosses the boundary as itself and an errno does not.
//
// Four types, and the choice between them is what the program is doing rather
// than what the platform offers:
//
//   TcpListener   accepts connections
//   TcpClient     one connection, and an `IStream`, so everything that already
//                 reads a stream reads a socket
//   UdpSocket     datagrams, which are not a stream and are not pretended to be
//   Socket        the one underneath, for anything the three do not cover
//
// `TcpClient` being an `IStream` is the point of the design. A reader written
// against a file works over a connection with nothing changed, because there
// was never anything file-shaped in it.
module Standard.Net;

import Standard.Collections;
import Standard.IO;
import Standard.Text;

extern "C" {
    nuint sl_socket_open(int family, int kind, int* error);
    void  sl_socket_close(nuint handle);
    int   sl_socket_shutdown(nuint handle, int how, int* error);

    int   sl_socket_bind(nuint handle, byte* host, ushort port, int family,
                         int kind, int* error);
    int   sl_socket_listen(nuint handle, int backlog, int* error);
    nuint sl_socket_accept(nuint handle, int* error);
    int   sl_socket_connect(nuint handle, byte* host, ushort port, int family,
                            int kind, int* error);

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
public enum SocketError {
    None = 0,

    /// Nothing to read, or no room to write, on a socket that is not blocking.
    /// Not a failure -- it is what a non-blocking socket says instead of
    /// waiting.
    WouldBlock = 1,

    /// Nothing is listening there.
    Refused = 2,

    TimedOut = 3,
    Unreachable = 4,

    /// Something else already has that port.
    AddressInUse = 5,

    NotConnected = 6,

    /// The peer went away without closing: a reset rather than an ending.
    Reset = 7,

    Closed = 8,
    Interrupted = 9,
    AccessDenied = 10,

    /// The name did not resolve.
    NoName = 11,

    Invalid = 12,
    Unknown = 13,
}

/// Which internet protocol.
public enum AddressFamily {
    /// Whichever the name resolves to, which is what a client usually wants.
    Any = 0,
    IPv4 = 4,
    IPv6 = 6,
}

/// Which of the two shapes a socket has.
public enum SocketKind {
    /// TCP: a stream, ordered and reliable, with no message boundaries.
    Stream = 1,

    /// UDP: datagrams, each whole or absent, in no particular order.
    Datagram = 2,
}

/// Which half of a connection to finish.
public enum SocketShutdown {
    Receive = 0,
    Send = 1,
    Both = 2,
}

/// What went wrong, in words.
public String Describe(SocketError error) {
    switch (error) {
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
public struct EndPoint {
    public String Host;
    public ushort Port;
}

/// An endpoint, made in one expression.
public EndPoint At(String host, ushort port) {
    EndPoint made;
    made.Host = host;
    made.Port = port;
    return made;
}

/// An endpoint, written the way one is written.
public String Format(EndPoint point) {
    // A bare IPv6 address contains colons, so the port needs the brackets that
    // a URL puts round one. IPv4 and a name do not.
    if (point.Host.Contains(':')) {
        return "[" + point.Host + "]:" + Text.FromInteger((long)point.Port);
    }
    return point.Host + ":" + Text.FromInteger((long)point.Port);
}

/// The first address a name resolves to, as text.
///
/// One address rather than the list: a list is only useful to something that
/// will try each in turn, and that is what connecting already does inside the
/// runtime, where it can try each socket as well as each address.
public Result<String, SocketError> Resolve(String host) {
    return Resolve(host, AddressFamily.Any);
}

public Result<String, SocketError> Resolve(String host, AddressFamily family) {
    byte[64] buffer;
    int code = 0;

    if (sl_socket_resolve(host.ToPointer(), (int)family, &buffer[0],
                          AddressSize, &code) == 0) {
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
/// Construction is the open, so a `Socket` always exists and `IsOpen()` says
/// whether it holds anything -- the same bargain `FileStream` makes, and for
/// the same reason: a null a caller cannot unwrap is worse than an object that
/// says why.
///
/// Closing is the destructor's job too, so a socket that goes out of scope
/// gives its handle back whether or not `Close` was called.
public class Socket {
    nuint handle;
    SocketError error;
    AddressFamily family;
    SocketKind kind;
    bool closed;

    public Socket(AddressFamily family, SocketKind kind) {
        int code = 0;
        handle = sl_socket_open((int)family, (int)kind, &code);
        this.family = family;
        this.kind = kind;
        error = (SocketError)code;
        closed = handle == NoSocket;
    }

    /// Wraps a handle the runtime already opened, which is what `Accept` has.
    Socket(nuint accepted, AddressFamily family, SocketKind kind) {
        handle = accepted;
        this.family = family;
        this.kind = kind;
        error = SocketError.None;
        closed = accepted == NoSocket;
    }

    ~Socket() { Close(); }

    public bool IsOpen() { return !closed; }

    /// The last error, or `None`. Set by every call that failed, and cleared
    /// by the next one that did not.
    public SocketError Error() { return error; }

    public AddressFamily Family() { return family; }
    public SocketKind Kind() { return kind; }

    /// The handle itself, for a platform call this wrapper does not make.
    /// A `SOCKET` on Windows and a file descriptor on everything else.
    public nuint Handle() { return handle; }

    public void Close() {
        if (closed) { return; }
        sl_socket_close(handle);
        closed = true;
        handle = NoSocket;
    }

    // ------------------------------------------------------------ addresses

    /// Takes the address, and the port. Port 0 asks the system to choose one,
    /// which `LocalEndPoint` will then say.
    public SocketError Bind(String host, ushort port) {
        if (closed) { return Note(SocketError.Closed); }

        int code = 0;
        sl_socket_bind(handle, host.ToPointer(), port, (int)family, (int)kind, &code);
        return Note((SocketError)code);
    }

    /// Binds to every address on this machine, which is what a server wants
    /// and what an empty host means to the resolver.
    public SocketError BindAny(ushort port) { return Bind("", port); }

    public SocketError Listen(int backlog) {
        if (closed) { return Note(SocketError.Closed); }

        int code = 0;
        sl_socket_listen(handle, backlog, &code);
        return Note((SocketError)code);
    }

    /// Waits for a connection. The socket that comes back is open, or is not
    /// and says why.
    public Socket Accept() {
        if (closed) {
            Note(SocketError.Closed);
            return new Socket(NoSocket, family, kind);
        }

        int code = 0;
        nuint accepted = sl_socket_accept(handle, &code);
        Note((SocketError)code);
        return new Socket(accepted, family, kind);
    }

    /// Connects, trying every address the name resolved to -- a host with both
    /// an A and an AAAA record where only one route works is the ordinary case.
    public SocketError Connect(String host, ushort port) {
        if (closed) { return Note(SocketError.Closed); }

        int code = 0;
        sl_socket_connect(handle, host.ToPointer(), port, (int)family, (int)kind, &code);
        return Note((SocketError)code);
    }

    /// This end of the connection.
    public EndPoint LocalEndPoint() { return Address(true); }

    /// The other end.
    public EndPoint RemoteEndPoint() { return Address(false); }

    // ------------------------------------------------------------- transfer

    /// Sends up to `count` bytes and reports how many went.
    ///
    /// Fewer than asked for is normal on a stream: the kernel took what fitted
    /// in its buffer. A loop over what is left is the caller's job, or
    /// `SendAll` is.
    public nuint Send(byte[] buffer, nuint offset, nuint count) {
        if (closed) { Note(SocketError.Closed); return 0; }
        if (count == 0) { return 0; }
        if (offset + count > buffer.Length) { Note(SocketError.Invalid); return 0; }

        int code = 0;
        nuint sent = sl_socket_send(handle, &buffer[offset], count, &code);
        Note((SocketError)code);
        return sent;
    }

    /// Sends all of it, or says why it could not.
    public SocketError SendAll(byte[] buffer) {
        nuint at = 0;
        while (at < buffer.Length) {
            nuint sent = Send(buffer, at, buffer.Length - at);
            if (sent == 0) { return error == SocketError.None ? SocketError.Closed : error; }
            at = at + sent;
        }
        return SocketError.None;
    }

    /// Sends the UTF-8 bytes of `text`, which is what a String already holds,
    /// so nothing is converted or copied on the way.
    public SocketError SendText(String text) {
        if (closed) { return Note(SocketError.Closed); }

        nuint at = 0;
        nuint size = text.ByteLength();

        while (at < size) {
            int code = 0;
            nuint sent = sl_socket_send(handle, text.ToPointer() + at, size - at, &code);
            Note((SocketError)code);

            if (sent == 0) { return error == SocketError.None ? SocketError.Closed : error; }
            at = at + sent;
        }
        return SocketError.None;
    }

    /// Reads up to `count` bytes and reports how many arrived. Zero is the
    /// peer having finished, which is an ending rather than an error -- ask
    /// `Error()` to tell the two apart.
    public nuint Receive(byte[] buffer, nuint offset, nuint count) {
        if (closed) { Note(SocketError.Closed); return 0; }
        if (count == 0) { return 0; }
        if (offset + count > buffer.Length) { Note(SocketError.Invalid); return 0; }

        int code = 0;
        nuint read = sl_socket_receive(handle, &buffer[offset], count, &code);
        Note((SocketError)code);
        return read;
    }

    // ------------------------------------------------------------ datagrams

    /// Sends one datagram. It arrives whole or not at all.
    public nuint SendTo(byte[] buffer, EndPoint target) {
        if (closed) { Note(SocketError.Closed); return 0; }

        int code = 0;
        nuint sent = sl_socket_send_to(handle, &buffer[0], buffer.Length,
                                       target.Host.ToPointer(), target.Port,
                                       (int)family, &code);
        Note((SocketError)code);
        return sent;
    }

    /// Reads one datagram, and says where it came from.
    ///
    /// A datagram longer than the buffer is truncated and the rest is gone,
    /// which is what a datagram is: there is no second read to get the rest of
    /// one.
    public nuint ReceiveFrom(byte[] buffer, ref EndPoint from) {
        if (closed) { Note(SocketError.Closed); return 0; }

        byte[64] host;
        ushort port = 0;
        int code = 0;

        nuint read = sl_socket_receive_from(handle, &buffer[0], buffer.Length,
                                            &host[0], AddressSize, &port, &code);
        Note((SocketError)code);

        from.Host = Text.FromNullTerminated(&host[0]);
        from.Port = port;
        return read;
    }

    // -------------------------------------------------------------- options

    /// Whether a call waits. A socket that does not block answers
    /// `WouldBlock` instead of waiting, which is not a failure.
    public SocketError SetBlocking(bool blocking) {
        return Option(sl_socket_set_blocking(handle, blocking ? 1 : 0, &_code), _code);
    }

    /// Turns off Nagle's algorithm, so a small write goes out now rather than
    /// waiting to be joined by the next one.
    public SocketError SetNoDelay(bool on) {
        return Option(sl_socket_set_no_delay(handle, on ? 1 : 0, &_code), _code);
    }

    /// Lets a listener take a port that connections in TIME_WAIT still hold,
    /// which is what a server restarting wants.
    ///
    /// A no-op on Windows, deliberately: SO_REUSEADDR there lets a second
    /// process steal a port another is actively listening on, which is a
    /// different and much worse thing to ask for. Windows already allows the
    /// TIME_WAIT case without being asked.
    public SocketError SetReuseAddress(bool on) {
        return Option(sl_socket_set_reuse_address(handle, on ? 1 : 0, &_code), _code);
    }

    public SocketError SetBroadcast(bool on) {
        return Option(sl_socket_set_broadcast(handle, on ? 1 : 0, &_code), _code);
    }

    public SocketError SetKeepAlive(bool on) {
        return Option(sl_socket_set_keep_alive(handle, on ? 1 : 0, &_code), _code);
    }

    /// How long a read waits before giving up. Zero is forever.
    public SocketError SetReceiveTimeout(int milliseconds) {
        return Option(sl_socket_set_timeout(handle, milliseconds, 1, &_code), _code);
    }

    public SocketError SetSendTimeout(int milliseconds) {
        return Option(sl_socket_set_timeout(handle, milliseconds, 0, &_code), _code);
    }

    /// Finishes one direction, or both. The other end sees an ending rather
    /// than a reset, which is the difference between this and closing.
    public SocketError Shutdown(SocketShutdown how) {
        if (closed) { return Note(SocketError.Closed); }

        int code = 0;
        sl_socket_shutdown(handle, (int)how, &code);
        return Note((SocketError)code);
    }

    // -------------------------------------------------------------- waiting

    /// Waits until there is something to read, the time runs out, or it fails.
    /// A negative wait is forever.
    public bool WaitToRead(int milliseconds) { return Wait(false, milliseconds); }

    /// Waits until there is room to write. On a socket that is connecting
    /// without blocking, this is also how the connection finishing is seen.
    public bool WaitToWrite(int milliseconds) { return Wait(true, milliseconds); }

    // -------------------------------------------------------------- private

    /// Scratch for the option calls, which all have the same shape and would
    /// otherwise each need a local and four lines.
    int _code;

    SocketError Option(int ok, int code) {
        if (closed) { return Note(SocketError.Closed); }
        return Note((SocketError)code);
    }

    bool Wait(bool forWriting, int milliseconds) {
        if (closed) { Note(SocketError.Closed); return false; }

        int code = 0;
        int ready = sl_socket_wait(handle, forWriting ? 1 : 0, milliseconds, &code);
        Note((SocketError)code);
        return ready == 1;
    }

    EndPoint Address(bool local) {
        EndPoint found;
        found.Host = "";
        found.Port = 0;

        if (closed) { Note(SocketError.Closed); return found; }

        byte[64] host;
        ushort port = 0;
        int code = 0;

        int ok = local
            ? sl_socket_local(handle, &host[0], AddressSize, &port, &code)
            : sl_socket_remote(handle, &host[0], AddressSize, &port, &code);

        Note((SocketError)code);
        if (ok == 0) { return found; }

        found.Host = Text.FromNullTerminated(&host[0]);
        found.Port = port;
        return found;
    }

    /// Records an error and hands it back, so a caller can write
    /// `return Note(...)` and a reader sees both at once.
    SocketError Note(SocketError code) {
        error = code;
        return code;
    }
}

// ------------------------------------------------------------- TCP listener

/// A socket that accepts connections, and does nothing else.
///
/// Construction opens, binds and listens, because there is no useful state
/// between those three: a listener that exists and is not listening is a thing
/// to check for and never a thing to want.
///
///     var server = new TcpListener(8080u);
///     if (!server.IsListening()) { Complain(Net.Describe(server.Error())); }
///
///     var client = server.Accept();
///     while (client.IsConnected()) { ... }
public class TcpListener {
    Socket socket;
    bool listening;

    /// Listens on every address this machine has.
    public TcpListener(ushort port) {
        this("", port, AddressFamily.IPv4, 16);
    }

    /// Listens on one address. `"127.0.0.1"` is the useful one: a service that
    /// only its own machine should reach says so here rather than in a
    /// firewall.
    public TcpListener(String host, ushort port) {
        this(host, port, AddressFamily.IPv4, 16);
    }

    public TcpListener(String host, ushort port, AddressFamily family, int backlog) {
        socket = new Socket(family, SocketKind.Stream);
        listening = false;

        if (!socket.IsOpen()) { return; }

        socket.SetReuseAddress(true);
        if (socket.Bind(host, port) != SocketError.None) { return; }
        if (socket.Listen(backlog) != SocketError.None) { return; }

        listening = true;
    }

    ~TcpListener() { Close(); }

    public bool IsListening() { return listening; }
    public SocketError Error() { return socket.Error(); }

    /// Where it is listening. With port 0 this is how the port the system
    /// chose is found out.
    public EndPoint LocalEndPoint() { return socket.LocalEndPoint(); }

    /// The socket underneath, for an option this does not expose.
    public Socket Underlying() { return socket; }

    /// Waits for a connection. The client that comes back is connected, or is
    /// not and says why.
    public TcpClient Accept() {
        return new TcpClient(socket.Accept());
    }

    /// Whether a connection is waiting, without blocking to find out.
    public bool Pending(int milliseconds) {
        return socket.WaitToRead(milliseconds);
    }

    public void Close() {
        listening = false;
        socket.Close();
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
///     var client = new TcpClient("example.com", 80u);
///     client.SendText("GET / HTTP/1.0\r\n\r\n");
///
/// The `IOError` an `IStream` reports is the nearest one to the socket error;
/// `SocketError()` has the exact one, and the two are there together because a
/// generic reader wants the first and code that knows it is a socket wants the
/// second.
public class TcpClient : IStream {
    Socket socket;
    bool finished;

    public TcpClient(String host, ushort port) {
        this(host, port, AddressFamily.Any);
    }

    public TcpClient(String host, ushort port, AddressFamily family) {
        socket = new Socket(family, SocketKind.Stream);
        finished = false;
        if (socket.IsOpen()) { socket.Connect(host, port); }
    }

    /// Wraps a socket somebody else opened, which is what `Accept` produces.
    public TcpClient(Socket accepted) {
        socket = accepted;
        finished = false;
    }

    ~TcpClient() { Close(); }

    /// Whether the connection is there. False after the peer finished, after
    /// `Close`, and if connecting never worked.
    public bool IsConnected() {
        return socket.IsOpen() && !finished && socket.Error() == SocketError.None;
    }

    /// The exact reason, which `Error()` rounds off to fit an `IStream`.
    public SocketError SocketError() { return socket.Error(); }

    public EndPoint LocalEndPoint() { return socket.LocalEndPoint(); }
    public EndPoint RemoteEndPoint() { return socket.RemoteEndPoint(); }

    public Socket Underlying() { return socket; }

    /// Sends all of `text`, looping until it has gone.
    public SocketError SendText(String text) { return socket.SendText(text); }

    /// Sends all of `data`.
    public SocketError SendAll(byte[] data) { return socket.SendAll(data); }

    /// Reads until the peer finishes, and gives back what arrived.
    ///
    /// For a protocol that ends by closing -- HTTP/1.0, or anything behind
    /// `shutdown` -- this is the whole body. For one that does not, it never
    /// returns, which is the caller's to know.
    public byte[] ReceiveAll() {
        var built = new List<byte>();
        var chunk = new byte[4096];

        while (true) {
            nuint read = socket.Receive(chunk, 0, chunk.Length);
            if (read == 0) { finished = true; break; }

            for (nuint i = 0; i < read; i = i + 1) { built.Add(chunk[i]); }
        }

        var all = new byte[built.Count()];
        for (nuint i = 0; i < all.Length; i = i + 1) { all[i] = built.At(i); }
        return all;
    }

    /// The same, read as UTF-8. Anything malformed becomes U+FFFD, because the
    /// result is a `String` and a `String` is valid UTF-8 by invariant.
    public String ReceiveText() {
        var all = ReceiveAll();
        if (all.Length == 0) { return ""; }
        return Text.FromBytes(&all[0], all.Length);
    }

    public bool WaitToRead(int milliseconds) { return socket.WaitToRead(milliseconds); }
    public bool WaitToWrite(int milliseconds) { return socket.WaitToWrite(milliseconds); }

    // ----------------------------------------------------------- IStream

    public bool CanRead() { return socket.IsOpen() && !finished; }
    public bool CanWrite() { return socket.IsOpen(); }

    /// A connection has no position to move to.
    public bool CanSeek() { return false; }

    public nuint Read(byte[] buffer, nuint offset, nuint count) {
        nuint read = socket.Receive(buffer, offset, count);
        if (read == 0 && socket.Error() == SocketError.None) { finished = true; }
        return read;
    }

    public nuint Write(byte[] buffer, nuint offset, nuint count) {
        return socket.Send(buffer, offset, count);
    }

    /// Not a position, and not pretended to be one.
    public long Position() { return -1; }
    public long Length() { return -1; }
    public bool Seek(long offset, SeekOrigin origin) { return false; }

    /// Nothing is buffered here; the kernel decides when bytes leave.
    public void Flush() { }

    public void Close() {
        if (socket.IsOpen()) { socket.Shutdown(SocketShutdown.Both); }
        socket.Close();
        finished = true;
    }

    /// The socket error as the nearest `IOError`, so that a reader which knows
    /// nothing about sockets still gets something it can act on.
    public IOError Error() {
        switch (socket.Error()) {
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

// ---------------------------------------------------------------- UDP

/// Datagrams.
///
/// Not an `IStream`, and that is deliberate. A datagram arrives whole or not
/// at all, in no particular order, possibly twice; a stream is ordered,
/// reliable and has no message boundaries at all. Pretending the first is the
/// second is how a program comes to assume things about UDP that are not true.
///
///     var socket = new UdpSocket(9000u);
///     var from = Net.At("", 0u);
///     var buffer = new byte[1500];
///     nuint got = socket.Receive(buffer, ref from);
public class UdpSocket {
    Socket socket;
    bool ready;

    /// A socket that can send and not receive, because nothing bound it.
    public UdpSocket() {
        this(AddressFamily.IPv4);
    }

    public UdpSocket(AddressFamily family) {
        socket = new Socket(family, SocketKind.Datagram);
        ready = socket.IsOpen();
    }

    /// A socket bound to a port, so it can receive. Port 0 asks the system to
    /// choose one, which `LocalEndPoint` will say.
    public UdpSocket(ushort port) {
        this("", port, AddressFamily.IPv4);
    }

    /// The same, on one address rather than all of them.
    public UdpSocket(String host, ushort port) {
        this(host, port, AddressFamily.IPv4);
    }

    public UdpSocket(String host, ushort port, AddressFamily family) {
        socket = new Socket(family, SocketKind.Datagram);
        ready = socket.IsOpen() && socket.Bind(host, port) == SocketError.None;
    }

    ~UdpSocket() { Close(); }

    public bool IsOpen() { return ready; }
    public SocketError Error() { return socket.Error(); }

    public EndPoint LocalEndPoint() { return socket.LocalEndPoint(); }
    public Socket Underlying() { return socket; }

    /// Sends one datagram. The count back is how many bytes went, which for a
    /// datagram is all of them or none.
    public nuint Send(byte[] data, String host, ushort port) {
        return socket.SendTo(data, At(host, port));
    }

    public nuint SendText(String text, String host, ushort port) {
        return Send(text.ToBytes(), host, port);
    }

    /// Reads one datagram and says where it came from. A datagram longer than
    /// the buffer is truncated, and the rest is gone -- there is no second
    /// read to collect it.
    public nuint Receive(byte[] buffer, ref EndPoint from) {
        return socket.ReceiveFrom(buffer, ref from);
    }

    public bool WaitToRead(int milliseconds) { return socket.WaitToRead(milliseconds); }

    /// Lets this socket send to a broadcast address.
    public SocketError SetBroadcast(bool on) { return socket.SetBroadcast(on); }

    public SocketError SetReceiveTimeout(int milliseconds) {
        return socket.SetReceiveTimeout(milliseconds);
    }

    public void Close() {
        ready = false;
        socket.Close();
    }
}
