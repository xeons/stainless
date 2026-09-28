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

module Standard.Net.Security;

import Standard.Collections;
import Standard.IO;
import Standard.Net;

/// A TLS connection that owns its TCP connection: `TcpClient` and
/// `TlsStream` as one thing, and an `IStream`.
///
///     var options = new TlsClientOptions();
///     options.CertificateValidator = PinnedLeaf;
///     var socket = try TlsSocket.Connect("example.com", 443u, options);
///
/// `Client` is the TCP connection, for its timeouts and its end points.
/// Everything else is the `TlsStream`'s, and `Stream` is that.
public sealed class TlsSocket : IStream
{
    private TcpClient _client;
    private TlsStream _stream;

    private TlsSocket(TcpClient client, TlsStream stream)
    {
        _client = client;
        _stream = stream;
    }

    ~TlsSocket() { Close(); }

    /// Connects to `host` and runs the client's handshake. An empty
    /// `TargetHost` in `options` means `host`.
    ///
    /// @param host     the name or address to reach
    /// @param port     the port to reach it on
    /// @param options  what to offer, and how to judge the certificate
    /// @failure TlsError.Io                  the TCP connection could not be made
    /// @failure TlsError.CertificateRefused  the validator refused the chain
    /// @failure TlsError.AlertReceived       the server refused
    public static Result<TlsSocket, TlsError> Connect(
        String host, ushort port, TlsClientOptions options) =>
        Connect(host, port, options, out TlsAlertDescription alert);

    /// Connects and runs the client's handshake, and reports the alert the
    /// server sent when it refused.
    ///
    /// @param host           the name or address to reach
    /// @param port           the port to reach it on
    /// @param options        what to offer, and how to judge the certificate
    /// @param alertReceived  the server's alert when the failure is
    ///                       `AlertReceived`, and `CloseNotify` otherwise
    /// @failure TlsError.AlertReceived  the server refused, and `alertReceived`
    ///                                  says why
    public static Result<TlsSocket, TlsError> Connect(
        String host, ushort port, TlsClientOptions options, out TlsAlertDescription alertReceived)
    {
        alertReceived = TlsAlertDescription.CloseNotify;
        var connected = TcpClient.Connect(host, port);
        if (!connected.Ok)
            return Fail(TlsError.Io);
        TcpClient client = connected.Value;

        String target = options.TargetHost.ByteLength() == 0u ? host : options.TargetHost;
        var connection = new TlsConnection(client, false, false);
        var handshake = new TlsClientHandshake(connection, options, target);
        TlsError failed = handshake.RunTlsClientHandshake();
        alertReceived = connection._alertReceived;
        if (failed != TlsError.None)
        {
            connection.AbandonTls(failed);
            return Fail(failed);
        }
        return Ok(new TlsSocket(client, TlsStream.WrapTlsConnection(connection)));
    }

    /// Accepts a connection from `listener` and runs the server's handshake.
    ///
    /// @param listener  where connections arrive
    /// @param options   the certificate, the key, and what to accept
    /// @failure TlsError.Io                     the accept failed
    /// @failure TlsError.NoCommonCipherSuite    no suite on both lists
    /// @failure TlsError.NoApplicationProtocol  no ALPN name on both lists
    public static Result<TlsSocket, TlsError> Accept(
        TcpListener listener, TlsServerOptions options) =>
        Accept(listener, options, out TlsAlertDescription alert);

    /// Accepts a connection and runs the server's handshake, and reports the
    /// alert the client sent when it refused.
    ///
    /// @param listener       where connections arrive
    /// @param options        the certificate, the key, and what to accept
    /// @param alertReceived  the client's alert when the failure is
    ///                       `AlertReceived`, and `CloseNotify` otherwise
    /// @failure TlsError.AlertReceived  the client refused, and `alertReceived`
    ///                                  says why
    public static Result<TlsSocket, TlsError> Accept(TcpListener listener, TlsServerOptions options,
                                                     out TlsAlertDescription alertReceived)
    {
        alertReceived = TlsAlertDescription.CloseNotify;
        TcpClient client = listener.Accept();
        if (!client.IsConnected)
            return Fail(TlsError.Io);
        var connection = new TlsConnection(client, true, false);
        var handshake = new TlsServerHandshake(connection, options);
        TlsError failed = handshake.RunTlsServerHandshake();
        alertReceived = connection._alertReceived;
        if (failed != TlsError.None)
        {
            connection.AbandonTls(failed);
            return Fail(failed);
        }
        return Ok(new TlsSocket(client, TlsStream.WrapTlsConnection(connection)));
    }

    /// The TCP connection underneath, for timeouts and end points. Reading
    /// or writing it directly corrupts the TLS stream.
    public TcpClient Client => _client;

    /// The TLS stream.
    public TlsStream Stream => _stream;

    public bool IsServer => _stream.IsServer;

    public TlsProtocolVersion NegotiatedProtocol => _stream.NegotiatedProtocol;

    public TlsCipherSuite CipherSuite => _stream.CipherSuite;

    public TlsNamedGroup KeyExchangeGroup => _stream.KeyExchangeGroup;

    public TlsSignatureScheme SignatureScheme => _stream.SignatureScheme;

    public String? NegotiatedApplicationProtocol => _stream.NegotiatedApplicationProtocol;

    public String TargetHostName => _stream.TargetHostName;

    public byte[] RemoteCertificate => _stream.RemoteCertificate;

    public List<byte[]> RemoteCertificateChain => _stream.RemoteCertificateChain;

    public TlsError TlsErrorCode => _stream.TlsErrorCode;

    public TlsAlertDescription AlertDescription => _stream.AlertDescription;

    public bool CanRead => _stream.CanRead;

    public bool CanWrite => _stream.CanWrite;

    public bool CanSeek => false;

    public nuint Read(byte[] buffer, nuint offset, nuint count) => _stream.Read(
        buffer, offset, count);

    public nuint Write(byte[] buffer, nuint offset, nuint count) => _stream.Write(
        buffer, offset, count);

    public long Position => -1;

    public long Length => -1;

    public bool Seek(long offset, SeekOrigin origin) => false;

    public void Flush() => _stream.Flush();

    /// Sends close_notify and closes the TCP connection. Idempotent.
    public void Close() => _stream.Close();

    public IOError Error => _stream.Error;
}
