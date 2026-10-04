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
/// `SocketErrorCode` has the exact one, and the two are there together because a
/// generic reader wants the first and code that knows it is a socket wants the
/// second.
public class TcpClient : IStream
{
    Socket _socket;
    bool _finished;

    /// Connects to a host and port.
    ///
    /// @failure SocketError.NoName       the host did not resolve
    /// @failure SocketError.Refused      nothing is listening there
    /// @failure SocketError.TimedOut     no answer from any address the name
    ///                                   resolved to
    /// @failure SocketError.Unreachable  no route to any of them
    /// @failure SocketError.Unknown      the last address failed for a reason
    ///                                   with no case of its own
    /// @see TcpListener.Accept
    public static Result<TcpClient, SocketError> Connect(String host, ushort port)
    {
        return Connect(host, port, AddressFamily.Any);
    }

    /// Connects, naming the family rather than letting the resolver choose.
    ///
    /// Blocks until the connection is made or refused; there is no timeout
    /// here, and the system's own is measured in tens of seconds.
    ///
    /// @param host    the name or address to reach
    /// @param port    the port to reach it on
    /// @param family  which family to resolve the name in
    /// @failure SocketError.NoName       the host did not resolve in that
    ///                                   family
    /// @failure SocketError.Refused      nothing is listening there
    /// @failure SocketError.TimedOut     no answer from any address the name
    ///                                   resolved to
    /// @failure SocketError.Unreachable  no route to any of them
    /// @failure SocketError.Unknown      the last address failed for a reason
    ///                                   with no case of its own
    public static Result<TcpClient, SocketError> Connect(
            String host, ushort port, AddressFamily family)
    {
        return Connect(host, port, family, -1);
    }

    /// Connects within a time limit.
    ///
    /// Every address the name resolved to is tried until one connects, and
    /// all the attempts together get `timeoutMilliseconds`. Resolving the name
    /// is not bounded.
    ///
    /// @param host                 the name or address to reach
    /// @param port                 the port to reach it on
    /// @param family               which family to resolve the name in
    /// @param timeoutMilliseconds  the limit for every attempt together;
    ///                             negative is none
    /// @failure SocketError.NoName       the host did not resolve in that
    ///                                   family
    /// @failure SocketError.TryAgain     the resolver could not answer for now
    /// @failure SocketError.Refused      nothing is listening there
    /// @failure SocketError.TimedOut     the time ran out, or no answer from
    ///                                   any address
    /// @failure SocketError.Unreachable  no route to any of them
    /// @failure SocketError.Unknown      the last address failed for a reason
    ///                                   with no case of its own
    /// @see Socket.OpenConnected
    public static Result<TcpClient, SocketError> Connect(
            String host, ushort port, AddressFamily family, int timeoutMilliseconds)
    {
        var opened = Socket.OpenConnected(host, port, family, SocketType.Stream,
                                          timeoutMilliseconds);
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
    public SocketError SocketErrorCode => _socket.Error;

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
    ///
    /// @failure SocketError.Closed        the connection was closed, or the
    ///                                    peer took nothing and reported
    ///                                    nothing
    /// @failure SocketError.NotConnected  the connection was never made
    /// @failure SocketError.Reset         the peer went away mid-send
    /// @failure SocketError.TimedOut      a send timeout ran out
    /// @failure SocketError.Unknown       the platform reported something with
    ///                                    no case of its own
    /// @see TcpClient.SendAll
    public SocketError SendText(String text) => _socket.SendText(text);

    /// Sends all of `data`.
    ///
    /// @failure SocketError.Closed        the connection was closed, or the
    ///                                    peer took nothing and reported
    ///                                    nothing
    /// @failure SocketError.NotConnected  the connection was never made
    /// @failure SocketError.Reset         the peer went away mid-send
    /// @failure SocketError.TimedOut      a send timeout ran out
    /// @failure SocketError.Unknown       the platform reported something with
    ///                                    no case of its own
    /// @see TcpClient.SendText
    public SocketError SendAll(byte[] data) => _socket.SendAll(data);

    /// Reads until the peer finishes, and gives back what arrived.
    ///
    /// For a protocol that ends by closing -- HTTP/1.0, or anything behind
    /// `shutdown` -- this is the whole body. For one that does not, it never
    /// returns, which is the caller's to know.
    ///
    /// **A failure ends the read too**, and what arrived before it comes back
    /// looking complete. The caller MUST check `SocketErrorCode` afterwards,
    /// or use `ReceiveToEnd`, which says.
    ///
    /// @see TcpClient.ReceiveToEnd
    public byte[] ReceiveAll()
    {
        var built = new List<byte>();
        ReceiveInto(built);
        return built.ToArray();
    }

    /// Reads until the peer finishes, and gives back what arrived, or the
    /// error that stopped the read before the peer finished.
    ///
    /// @failure SocketError.Reset         the peer went away without finishing
    /// @failure SocketError.TimedOut      a receive timeout ran out
    /// @failure SocketError.Closed        the connection was closed
    /// @failure SocketError.NotConnected  the connection was never made
    /// @failure SocketError.Unknown       the platform reported something with
    ///                                    no case of its own
    /// @see TcpClient.ReceiveAll
    public Result<byte[], SocketError> ReceiveToEnd()
    {
        var built = new List<byte>();
        SocketError error = ReceiveInto(built);
        if (error != SocketError.None)
            return Fail(error);
        return Ok(built.ToArray());
    }

    /// The same as `ReceiveAll`, read as UTF-8. Anything malformed becomes
    /// U+FFFD, because the result is a `String` and a `String` is valid UTF-8
    /// by invariant.
    ///
    /// A failure ends the read as it does `ReceiveAll`'s, so the caller MUST
    /// check `SocketErrorCode` afterwards.
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

        nuint read = _socket.Receive(buffer, offset, count, out SocketError error);
        if (read == 0 && error == SocketError.None)
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

    /// Closes once the peer has seen everything written: finishes sending,
    /// then reads and throws away what the peer still sends until it ends the
    /// connection, waiting at most `milliseconds` for each read, then closes.
    ///
    /// A close with unread bytes waiting makes the kernel answer with a
    /// reset, and a reset can overtake the last bytes written and take them
    /// with it -- a TLS alert, most often. Waiting for the peer's own ending
    /// is what lets it read them. At most 64 KiB is read, so a peer that
    /// keeps sending cannot hold the close open.
    public void CloseAfterDraining(int milliseconds)
    {
        if (_socket.IsOpen && _socket.Shutdown(SocketShutdown.Send) == SocketError.None)
        {
            var discarded = new byte[4096u];
            for (int i = 0; i < 16 && _socket.WaitToRead(milliseconds); i++)
            {
                if (_socket.Receive(discarded, 0u, discarded.Length) == 0u)
                    break;
            }
        }
        Close();
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

    // ----------------------------------------------------------- private

    /// Reads into `built` until the peer finishes or a read fails, answering
    /// the failure or `None`.
    SocketError ReceiveInto(List<byte> built)
    {
        var chunk = new byte[4096];
        while (true)
        {
            nuint read = _socket.Receive(chunk, 0, chunk.Length, out SocketError error);
            if (read == 0)
            {
                if (error == SocketError.None)
                    _finished = true;
                return error;
            }
            built.AddRange(chunk[:read]);
        }
    }
}
