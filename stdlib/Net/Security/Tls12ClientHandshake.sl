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
import Standard.Security.Cryptography;

/// The client's side of a TLS 1.2 handshake (RFC 5246 §7.3) with ECDHE
/// (RFC 8422), from the ServerHello on. `TlsClientHandshake` sent the
/// ClientHello and hands over when the ServerHello chose TLS 1.2.
///
/// The server MUST negotiate the extended master secret (RFC 7627); one
/// that does not is refused with `handshake_failure`.
internal sealed class Tls12ClientHandshake
{
    private TlsConnection _connection;
    private TlsClientOptions _options;
    private TlsTranscript _transcript;
    private TlsClientHello _offered;
    private byte[] _serverRandom;
    private TlsCipherSuite _suite;
    private Tls12KeySchedule? _schedule;
    private TlsPeerKey? _serverKey;
    private TlsNamedGroup _group;
    private byte[] _serverPoint;
    private bool _ticketPromised;
    private bool _certificateRequested;
    private List<uint> _requestedCertificateTypes;
    private List<TlsSignatureScheme> _requestedSchemes;

    internal Tls12ClientHandshake(TlsConnection connection, TlsClientOptions options,
                                  TlsTranscript transcript, TlsClientHello offered)
    {
        _connection = connection;
        _options = options;
        _transcript = transcript;
        _offered = offered;
        _serverRandom = new byte[0u];
        _suite = TlsCipherSuite.TlsEcdheEcdsaWithAes128GcmSha256;
        _schedule = null;
        _serverKey = null;
        _group = TlsNamedGroup.X25519;
        _serverPoint = new byte[0u];
        _ticketPromised = false;
        _certificateRequested = false;
        _requestedCertificateTypes = new List<uint>();
        _requestedSchemes = new List<TlsSignatureScheme>();
    }

    internal Tls12KeySchedule? Schedule => _schedule;

    /// Everything after the ServerHello: `None`, or the failure, whose alert
    /// has not been sent yet.
    internal TlsError RunTls12ClientHandshake()
    {
        TlsError step = ReadTls12ServerFlight();
        if (step != TlsError.None)
            return step;
        step = SendTls12ClientFlight();
        if (step != TlsError.None)
            return step;
        return ReadTls12ServerFinished();
    }

    // ------------------------------------------------------------ ServerHello

    internal TlsError ReadTls12ServerHello(byte[] message)
    {
        var reader = new TlsReader(message, 4u, message.Length - 4u);
        uint version = reader.ReadUInt16();
        byte[] random = reader.ReadArray(32u);
        byte[] sessionId = reader.ReadVectorArray(1u, 0u, 32u);
        uint suite = reader.ReadUInt16();
        uint compression = reader.ReadByte();
        TlsReader extensions = reader.IsAtEnd
            ? new TlsReader(message, message.Length, 0u)
            : reader.ReadVector(2u, 0u, 65535u);
        if (reader.Failed || !reader.IsAtEnd)
            return TlsError.Decode;

        if (version != TlsVersion12)
            return TlsError.ProtocolVersion;
        var cipherSuite = (TlsCipherSuite)(ushort)suite;
        if (!_offered._cipherSuites.Contains(suite) || !IsTls12CipherSuite(cipherSuite))
            return TlsError.IllegalParameter;
        if (compression != 0u)
            return TlsError.IllegalParameter;
        // The same id back would be the server resuming a session, and none
        // was offered: the id is only middlebox compatibility's.
        if (sessionId.Length > 0u && AreTlsBytesEqual(sessionId, _offered._sessionId))
            return TlsError.IllegalParameter;

        bool extendedMasterSecret = false;
        var seen = new TlsCodePointSet();
        while (!extensions.IsAtEnd)
        {
            uint type = extensions.ReadUInt16();
            TlsReader data = extensions.ReadVector(2u, 0u, 65535u);
            if (extensions.Failed)
                return TlsError.Decode;
            if (!seen.Add(type))
                return TlsError.IllegalParameter;
            if (!_offered._extensionTypes.Contains(type))
                return TlsError.UnsupportedExtension;

            switch ((TlsExtensionType)(ushort)type)
            {
                case TlsExtensionType.ServerName:
                    break;

                case TlsExtensionType.ExtendedMasterSecret:
                    extendedMasterSecret = true;
                    break;

                case TlsExtensionType.SessionTicket:
                    _ticketPromised = true;
                    break;

                case TlsExtensionType.RenegotiationInfo:
                {
                    // Empty, since this is no renegotiation (RFC 5746 §3.4).
                    byte[] renegotiated = data.ReadVectorArray(1u, 0u, 255u);
                    if (data.Failed || !data.IsAtEnd)
                        return TlsError.Decode;
                    if (renegotiated.Length != 0u)
                        return TlsError.HandshakeFailed;
                    break;
                }

                case TlsExtensionType.EcPointFormats:
                {
                    byte[] formats = data.ReadVectorArray(1u, 1u, 255u);
                    if (data.Failed || !data.IsAtEnd)
                        return TlsError.Decode;
                    bool uncompressed = false;
                    for (nuint i = 0u; i < formats.Length; i++)
                    {
                        if (formats[i] == 0)
                            uncompressed = true;
                    }
                    if (!uncompressed)
                        return TlsError.IllegalParameter;
                    break;
                }

                case TlsExtensionType.ApplicationLayerProtocolNegotiation:
                {
                    TlsReader names = data.ReadVector(2u, 2u, 65535u);
                    byte[] name = names.ReadVectorArray(1u, 1u, 255u);
                    if (names.Failed || !names.IsAtEnd || data.Failed || !data.IsAtEnd)
                        return TlsError.Decode;
                    String chosen = ConvertTlsBytesToText(name);
                    if (!_offered._applicationProtocols.Contains(chosen))
                        return TlsError.IllegalParameter;
                    _connection._applicationProtocol = chosen;
                    break;
                }

                default:
                    return TlsError.IllegalParameter;
            }
            if (data.Failed || !data.IsAtEnd)
                return TlsError.Decode;
        }
        if (!extendedMasterSecret)
            return TlsError.HandshakeFailed;

        _transcript.AddTlsMessage(message);
        _serverRandom = random;
        _suite = cipherSuite;
        _schedule = new Tls12KeySchedule(GetTlsSuiteHash(cipherSuite), _offered._random, random);
        _connection.SelectTls12();
        _connection._cipherSuite = cipherSuite;
        return TlsError.None;
    }

    // ------------------------------------------------------ the server's flight

    /// Certificate, ServerKeyExchange, an optional CertificateRequest, and
    /// ServerHelloDone.
    private TlsError ReadTls12ServerFlight()
    {
        var read = ReadTls12HandshakeMessage(TlsHandshakeType.Certificate);
        if (!read.Ok)
            return read.Error;
        byte[] message = read.Value;
        var chain = ReadTls12CertificateMessage(message, false);
        if (!chain.Ok)
            return chain.Error;
        _transcript.AddTlsMessage(message);

        TlsError verdict = _options.CertificateValidator(chain.Value, _connection._targetHost);
        if (verdict != TlsError.None)
            return verdict;
        var key = TlsPeerKey.ReadTlsPeerKey(chain.Value[0u]);
        if (!key.Ok)
            return key.Error;
        if (!IsTls12SuiteForKey(_suite, key.Value.Kind) ||
            !IsTls12KeyOnSupportedCurve(key.Value.Kind, _offered._supportedGroups))
        {
            return TlsError.UnsupportedCertificate;
        }
        _serverKey = key.Value;
        _connection._remoteChain = chain.Value;

        read = ReadTls12HandshakeMessage(TlsHandshakeType.ServerKeyExchange);
        if (!read.Ok)
            return read.Error;
        TlsError exchanged = ReadTls12ServerKeyExchange(read.Value, key.Value);
        if (exchanged != TlsError.None)
            return exchanged;

        read = _connection.ReadTlsHandshakeMessage();
        if (!read.Ok)
            return read.Error;
        message = read.Value;
        if ((TlsHandshakeType)message[0u] == TlsHandshakeType.CertificateRequest)
        {
            TlsError requested = ReadTls12CertificateRequest(message);
            if (requested != TlsError.None)
                return requested;
            read = _connection.ReadTlsHandshakeMessage();
            if (!read.Ok)
                return read.Error;
            message = read.Value;
        }

        if ((TlsHandshakeType)message[0u] != TlsHandshakeType.ServerHelloDone)
            return TlsError.UnexpectedMessage;
        if (message.Length != 4u)
            return TlsError.Decode;
        _transcript.AddTlsMessage(message);
        return TlsError.None;
    }

    /// The server's ephemeral key and its signature over both randoms and
    /// the key (RFC 8422 §5.4).
    private TlsError ReadTls12ServerKeyExchange(byte[] message, TlsPeerKey key)
    {
        var reader = new TlsReader(message, 4u, message.Length - 4u);
        uint curveType = reader.ReadByte();
        uint group = reader.ReadUInt16();
        byte[] point = reader.ReadVectorArray(1u, 1u, 255u);
        nuint paramsEnd = reader.Position;
        var scheme = (TlsSignatureScheme)(ushort)reader.ReadUInt16();
        byte[] signature = reader.ReadVectorArray(2u, 0u, 65535u);
        if (reader.Failed || !reader.IsAtEnd)
            return TlsError.Decode;

        // named_curve, in a group that was offered.
        var named = (TlsNamedGroup)(ushort)group;
        if (curveType != 3u || !_offered._supportedGroups.Contains(group) ||
            !IsImplementedTlsGroup(named))
        {
            return TlsError.IllegalParameter;
        }
        if (!_offered._signatureAlgorithms.Contains(scheme) ||
            !IsTls12SchemeForKey(scheme, key.Kind))
        {
            return TlsError.IllegalParameter;
        }

        var signed = new TlsBuffer(64u + paramsEnd);
        signed.WriteBytes(_offered._random);
        signed.WriteBytes(_serverRandom);
        signed.WriteBytes(message[4u:][:paramsEnd - 4u]);
        if (!key.VerifyTls12Signature(scheme, signed.Written, signature))
            return TlsError.DecryptError;

        _transcript.AddTlsMessage(message);
        _group = named;
        _serverPoint = point;
        _connection._group = named;
        _connection._signatureScheme = scheme;
        return TlsError.None;
    }

    private TlsError ReadTls12CertificateRequest(byte[] message)
    {
        var reader = new TlsReader(message, 4u, message.Length - 4u);
        byte[] types = reader.ReadVectorArray(1u, 1u, 255u);
        TlsReader schemes = reader.ReadVector(2u, 2u, 65534u);
        reader.ReadVector(2u, 0u, 65535u);
        if (reader.Failed || !reader.IsAtEnd || schemes.Remaining % 2u != 0u)
            return TlsError.Decode;
        while (!schemes.IsAtEnd)
            _requestedSchemes.Add((TlsSignatureScheme)(ushort)schemes.ReadUInt16());

        for (nuint i = 0u; i < types.Length; i++)
            _requestedCertificateTypes.Add((uint)types[i]);
        _certificateRequested = true;
        _transcript.AddTlsMessage(message);
        return TlsError.None;
    }

    // ------------------------------------------------------ the client's flight

    /// An optional Certificate, ClientKeyExchange, an optional
    /// CertificateVerify, change_cipher_spec and Finished.
    private TlsError SendTls12ClientFlight()
    {
        var schedule = _schedule;
        if (schedule == null)
            return TlsError.InternalError;

        var key = _options.ClientPrivateKey;
        Optional<TlsSignatureScheme> scheme = None;
        if (_certificateRequested)
        {
            List<byte[]> chain = _options.ClientCertificateChain;
            if (key != null && chain.Count > 0u &&
                _requestedCertificateTypes.Contains(GetTls12CertificateType(key.Kind)))
            {
                scheme = key.SelectTls12Scheme(_requestedSchemes);
            }
            byte[] certificate = BuildTls12CertificateMessage(
                scheme.Some ? chain : new List<byte[]>());
            QueueTls12ClientMessage(certificate);
        }

        var share = TlsKeyShare.GenerateTlsKeyShare(_group);
        if (!share.Ok)
            return share.Error;
        var premaster = share.Value.DeriveTlsSharedSecret(_serverPoint);
        share.Value.WipeTlsPrivateKey();
        if (!premaster.Ok)
            return premaster.Error;

        var exchange = new TlsBuffer(128u);
        nuint body = BeginTlsHandshakeMessage(exchange, TlsHandshakeType.ClientKeyExchange);
        nuint pointAt = exchange.BeginVector(1u);
        exchange.WriteBytes(share.Value.PublicKey);
        exchange.EndVector(pointAt, 1u);
        EndTlsHandshakeMessage(exchange, body);
        QueueTls12ClientMessage(exchange.ToArray());

        schedule.DeriveTlsExtendedMasterSecret(
            premaster.Value, _transcript.ComputeTls12TranscriptHash(schedule));
        CryptographicOperations.ZeroMemory(premaster.Value);
        _connection._tls12Schedule = schedule;

        if (scheme.Some && key != null)
        {
            var signature = key.SignTlsContent(scheme.Value, _transcript.Messages);
            if (!signature.Ok)
                return signature.Error;
            QueueTls12ClientMessage(BuildTlsCertificateVerify(scheme.Value, signature.Value));
            _connection._mutuallyAuthenticated = true;
        }

        TlsError sent = _connection.FlushTlsHandshake();
        if (sent != TlsError.None)
            return sent;
        sent = _connection.WriteTlsChangeCipherSpec();
        if (sent != TlsError.None)
            return sent;
        var writing = schedule.TakeTls12RecordCipher(_suite, true);
        if (!writing.Ok)
            return writing.Error;
        _connection.InstallTlsWriteCipher(writing.Value);

        byte[] verifyData = schedule.ComputeTls12Finished(
            true, _transcript.ComputeTls12TranscriptHash(schedule));
        QueueTls12ClientMessage(BuildTlsFinished(verifyData));
        return _connection.FlushTlsHandshake();
    }

    private void QueueTls12ClientMessage(byte[] message)
    {
        _transcript.AddTlsMessage(message);
        _connection.QueueTlsHandshakeMessage(message);
    }

    // ---------------------------------------------------- the server's Finished

    /// An optional NewSessionTicket, change_cipher_spec and Finished.
    private TlsError ReadTls12ServerFinished()
    {
        var schedule = _schedule;
        if (schedule == null)
            return TlsError.InternalError;

        TlsSessionTicket? ticket = null;
        if (_ticketPromised)
        {
            var read = ReadTls12HandshakeMessage(TlsHandshakeType.NewSessionTicket);
            if (!read.Ok)
                return read.Error;
            var reader = new TlsReader(read.Value, 4u, read.Value.Length - 4u);
            uint lifetime = reader.ReadUInt32();
            byte[] opaque = reader.ReadVectorArray(2u, 0u, 65535u);
            if (reader.Failed || !reader.IsAtEnd)
                return TlsError.Decode;
            _transcript.AddTlsMessage(read.Value);
            // An empty ticket is the server changing its mind (RFC 5077 §3.3).
            if (opaque.Length > 0u)
            {
                ticket = new TlsSessionTicket(TlsProtocolVersion.Tls12, _suite,
                                              _connection._targetHost, lifetime, 0u,
                                              new byte[0u], opaque, schedule._masterSecret, 0u);
            }
        }

        TlsError changed = _connection.ReadTlsChangeCipherSpec();
        if (changed != TlsError.None)
            return changed;
        var reading = schedule.TakeTls12RecordCipher(_suite, false);
        if (!reading.Ok)
            return reading.Error;
        _connection._records.InstallTlsReadCipher(reading.Value);

        var finished = ReadTls12HandshakeMessage(TlsHandshakeType.Finished);
        if (!finished.Ok)
            return finished.Error;
        byte[] expected = schedule.ComputeTls12Finished(
            false, _transcript.ComputeTls12TranscriptHash(schedule));
        TlsError verified = VerifyTlsFinished(finished.Value, expected);
        if (verified != TlsError.None)
            return verified;
        TlsError boundary = _connection.RequireTlsRecordBoundary();
        if (boundary != TlsError.None)
            return boundary;

        _connection._handshakeComplete = true;
        if (ticket != null)
            _connection._ticketHandler(ticket);
        return TlsError.None;
    }

    /// The next handshake message, which MUST be of `type`. The connection
    /// passes over a HelloRequest (RFC 5246 section 7.4.1.1).
    private Result<byte[], TlsError> ReadTls12HandshakeMessage(TlsHandshakeType type)
    {
        var read = _connection.ReadTlsHandshakeMessage();
        if (!read.Ok)
            return read;
        if ((TlsHandshakeType)read.Value[0u] != type)
            return Fail(TlsError.UnexpectedMessage);
        return read;
    }
}

// ------------------------------------------------ messages both sides share

/// Reads a TLS 1.2 Certificate message: the chain, DER, leaf first, with no
/// context and no per-entry extensions. An empty chain is allowed only when
/// `mayBeEmpty`, which is a client answering a CertificateRequest.
internal Result<List<byte[]>, TlsError> ReadTls12CertificateMessage(byte[] message, bool mayBeEmpty)
{
    var reader = new TlsReader(message, 4u, message.Length - 4u);
    TlsReader list = reader.ReadVector(3u, 0u, 16777215u);
    if (reader.Failed || !reader.IsAtEnd)
        return Fail(TlsError.Decode);

    var chain = new List<byte[]>();
    while (!list.IsAtEnd)
    {
        byte[] certificate = list.ReadVectorArray(3u, 1u, 16777215u);
        if (list.Failed)
            return Fail(TlsError.Decode);
        chain.Add(certificate);
    }
    if (chain.Count == 0u && !mayBeEmpty)
        return Fail(TlsError.Decode);
    return Ok(chain);
}

internal byte[] BuildTls12CertificateMessage(List<byte[]> chain)
{
    var message = new TlsBuffer(4096u);
    nuint body = BeginTlsHandshakeMessage(message, TlsHandshakeType.Certificate);
    nuint listAt = message.BeginVector(3u);
    for (nuint i = 0u; i < chain.Count; i++)
    {
        nuint entryAt = message.BeginVector(3u);
        message.WriteBytes(chain[i]);
        message.EndVector(entryAt, 3u);
    }
    message.EndVector(listAt, 3u);
    EndTlsHandshakeMessage(message, body);
    return message.ToArray();
}

/// The ClientCertificateType a CertificateRequest names for a key of
/// `kind`: rsa_sign, or ecdsa_sign, which RFC 8422 §5.5 also uses for
/// Ed25519.
internal uint GetTls12CertificateType(TlsKeyKind kind)
{
    switch (kind)
    {
        case TlsKeyKind.Rsa:
        case TlsKeyKind.RsaPss:
            return 1u;
    }
    return 64u;
}
