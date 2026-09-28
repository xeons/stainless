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

/// A TLS connection over another stream, and an `IStream` itself.
///
///     var tcp = try TcpClient.Connect("example.com", 443u);
///     var options = new TlsClientOptions();
///     options.TargetHost = "example.com";
///     options.CertificateValidator = PinnedLeaf;
///     var tls = try TlsStream.AuthenticateAsClient(tcp, options);
///     tls.Write(request, 0u, request.Length);
///
/// .NET's `SslStream`, made by a static method that returns a `Result`
/// rather than by a constructor and a method that throws. The stream
/// underneath can be anything — a `TcpClient`, a proxy's tunnel, a pipe — as
/// long as it delivers bytes in order.
///
/// `Read` blocks until a record of application data arrives, and returns
/// part of it if `count` is smaller; `Write` sends everything it is given,
/// in records of at most 16 KiB. One thread MAY read while another writes.
///
/// The IO error a failure rounds off to is `Closed` for a transport that
/// ended, the stream's own for one that failed, and `InvalidData` for
/// everything the protocol refused; `TlsErrorCode` has the exact reason.
public sealed class TlsStream : IStream
{
    private TlsConnection _connection;

    private TlsStream(TlsConnection connection)
    {
        _connection = connection;
    }

    ~TlsStream() { Close(); }

    internal static TlsStream WrapTlsConnection(
        TlsConnection connection) => new TlsStream(connection);

    /// Runs the client's handshake over `inner`.
    ///
    /// On failure the alert has been sent and `inner` closed, unless
    /// `LeaveInnerStreamOpen`.
    ///
    /// @param inner    the connection to the server
    /// @param options  what to offer, and how to judge the certificate
    /// @failure TlsError.CertificateRefused   the validator refused the chain
    /// @failure TlsError.ProtocolVersion      the server does not speak TLS 1.3
    /// @failure TlsError.AlertReceived        the server refused, and said why
    ///                                        in an alert
    /// @failure TlsError.Io                   the stream underneath failed
    public static Result<TlsStream, TlsError> AuthenticateAsClient(
        IStream inner, TlsClientOptions options)
    {
        return AuthenticateAsClient(inner, options, out TlsAlertDescription alert);
    }

    /// Runs the client's handshake, and reports the alert the server sent
    /// when it refused.
    ///
    /// @param inner          the connection to the server
    /// @param options        what to offer, and how to judge the certificate
    /// @param alertReceived  the server's alert when the failure is
    ///                       `AlertReceived`, and `CloseNotify` otherwise
    /// @failure TlsError.AlertReceived  the server refused, and `alertReceived`
    ///                                  says why
    public static Result<TlsStream, TlsError> AuthenticateAsClient(
        IStream inner, TlsClientOptions options, out TlsAlertDescription alertReceived)
    {
        var connection = new TlsConnection(inner, false, options.LeaveInnerStreamOpen);
        var handshake = new TlsClientHandshake(connection, options, options.TargetHost);
        TlsError failed = handshake.RunTlsClientHandshake();
        alertReceived = connection._alertReceived;
        if (failed != TlsError.None)
        {
            connection.AbandonTls(failed);
            return Fail(failed);
        }
        return Ok(new TlsStream(connection));
    }

    /// Runs the server's handshake over `inner`.
    ///
    /// On failure the alert has been sent and `inner` closed, unless
    /// `LeaveInnerStreamOpen`.
    ///
    /// @param inner    the connection from the client
    /// @param options  the certificate, the key, and what to accept
    /// @failure TlsError.NoCommonCipherSuite     no suite on both lists
    /// @failure TlsError.NoCommonGroup           no group on both lists
    /// @failure TlsError.NoApplicationProtocol   no ALPN name on both lists
    /// @failure TlsError.CertificateRequired     a client certificate was
    ///                                           required and none came
    /// @failure TlsError.InternalError           no certificate or no key is
    ///                                           configured
    public static Result<TlsStream, TlsError> AuthenticateAsServer(
        IStream inner, TlsServerOptions options)
    {
        return AuthenticateAsServer(inner, options, out TlsAlertDescription alert);
    }

    /// Runs the server's handshake, and reports the alert the client sent
    /// when it refused.
    ///
    /// @param inner          the connection from the client
    /// @param options        the certificate, the key, and what to accept
    /// @param alertReceived  the client's alert when the failure is
    ///                       `AlertReceived`, and `CloseNotify` otherwise
    /// @failure TlsError.AlertReceived  the client refused, and `alertReceived`
    ///                                  says why
    public static Result<TlsStream, TlsError> AuthenticateAsServer(
        IStream inner, TlsServerOptions options, out TlsAlertDescription alertReceived)
    {
        var connection = new TlsConnection(inner, true, options.LeaveInnerStreamOpen);
        var handshake = new TlsServerHandshake(connection, options);
        TlsError failed = handshake.RunTlsServerHandshake();
        alertReceived = connection._alertReceived;
        if (failed != TlsError.None)
        {
            connection.AbandonTls(failed);
            return Fail(failed);
        }
        return Ok(new TlsStream(connection));
    }

    // ------------------------------------------------------------ what it is

    /// Whether this end is the server.
    public bool IsServer => _connection._isServer;

    /// The version negotiated. Always TLS 1.3 for now.
    public TlsProtocolVersion NegotiatedProtocol => TlsProtocolVersion.Tls13;

    /// The suite negotiated.
    public TlsCipherSuite CipherSuite => _connection._cipherSuite;

    /// The group the key exchange was made in.
    public TlsNamedGroup KeyExchangeGroup => _connection._group;

    /// The scheme the server signed its CertificateVerify with.
    public TlsSignatureScheme SignatureScheme => _connection._signatureScheme;

    /// The ALPN protocol agreed, or null when there was none.
    public String? NegotiatedApplicationProtocol => _connection._applicationProtocol;

    /// On a client, the name it asked for; on a server, the name in the
    /// client's server_name, or empty.
    public String TargetHostName => _connection._targetHost;

    /// The peer's leaf certificate, DER, or empty when it sent none — which
    /// only a client can do.
    public byte[] RemoteCertificate
    {
        get
        {
            if (_connection._remoteChain.Count == 0u)
                return new byte[0u];
            return _connection._remoteChain[0u];
        }
    }

    /// The peer's certificates as it sent them, DER, leaf first.
    public List<byte[]> RemoteCertificateChain => _connection._remoteChain;

    /// Whether the client presented a certificate that was accepted.
    public bool IsMutuallyAuthenticated => _connection._mutuallyAuthenticated;

    /// The exact failure, or `None`.
    public TlsError TlsErrorCode => _connection._error;

    /// The alert the peer ended the connection with, when `TlsErrorCode` is
    /// `AlertReceived`.
    public TlsAlertDescription AlertDescription => _connection._alertReceived;

    /// The stream underneath.
    public IStream InnerStream => _connection.Inner;

    // --------------------------------------------------------- key material

    /// Keying material for a protocol above this one (RFC 8446 §7.5): the
    /// same bytes at both ends for the same label and context, and no use to
    /// anyone else.
    ///
    /// @param label    names the use, as the protocol that wants it defines
    /// @param context  bound into the result; empty when the protocol has none
    /// @param length   how many bytes, at most 255 digests' worth
    /// @failure TlsError.Closed  the stream is closed
    public Result<byte[], TlsError> ExportKeyingMaterial(
        String label, ReadOnlySpan<byte> context, nuint length)
    {
        var schedule = _connection._schedule;
        if (schedule == null || _connection.IsClosed)
            return Fail(TlsError.Closed);
        return Ok(schedule.ExportTlsKeyingMaterial(label, context, length));
    }

    /// Moves this end to its next write key with a KeyUpdate, and asks the
    /// peer to do the same when `requestPeerUpdate`. Keys are also updated
    /// without being asked, before one has protected 2^24 records.
    ///
    /// @failure TlsError.Closed  the stream is closed or failed
    /// @failure TlsError.Io      the stream underneath failed
    public TlsError UpdateTrafficKeys(bool requestPeerUpdate) =>
        _connection.SendTlsKeyUpdate(requestPeerUpdate);

    // --------------------------------------------------------------- IStream

    public bool CanRead => !_connection.IsClosed && _connection._error == TlsError.None;

    public bool CanWrite => !_connection.IsClosed && _connection._error == TlsError.None;

    /// A connection has no position.
    public bool CanSeek => false;

    /// Reads up to `count` bytes of application data. Zero means the peer
    /// sent close_notify, or a failure, which `Error` tells apart.
    public nuint Read(byte[] buffer, nuint offset, nuint count)
    {
        if (!IsTlsRangeWithin(buffer, offset, count))
            return 0u;
        return _connection.ReadTlsApplicationData(buffer, offset, count);
    }

    /// Writes all `count` bytes as application data, and answers `count`, or
    /// zero on a failure.
    public nuint Write(byte[] buffer, nuint offset, nuint count)
    {
        if (!IsTlsRangeWithin(buffer, offset, count))
            return 0u;
        return _connection.WriteTlsApplicationData(buffer, offset, count);
    }

    public long Position => -1;

    public long Length => -1;

    public bool Seek(long offset, SeekOrigin origin) => false;

    /// Flushes the stream underneath. Every `Write` has already sent its
    /// records.
    public void Flush() => _connection.Inner.Flush();

    /// Sends close_notify and closes the stream underneath, unless
    /// `LeaveInnerStreamOpen`. Idempotent, and the destructor calls it.
    public void Close() => _connection.CloseTls();

    public IOError Error
    {
        get
        {
            switch (_connection._error)
            {
                case TlsError.None: return IOError.None;
                case TlsError.Closed: return IOError.Closed;
                case TlsError.Io:
                {
                    IOError inner = _connection.Inner.Error;
                    return inner == IOError.None ? IOError.Unknown : inner;
                }
                default: return IOError.InvalidData;
            }
        }
    }
}
