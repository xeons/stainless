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

/// The server's side of a TLS 1.2 handshake (RFC 5246 §7.3) with ECDHE
/// (RFC 8422), from a ClientHello that `TlsServerHandshake` has read and
/// settled on TLS 1.2 for.
///
/// The client MUST offer the extended master secret (RFC 7627); one that
/// does not is refused with `handshake_failure`. No session is cached and no
/// ticket is issued, so nothing is ever resumed.
internal sealed class Tls12ServerHandshake
{
    private TlsConnection _connection;
    private TlsServerOptions _options;
    private TlsClientHello _hello;
    private TlsSigningKey _key;
    private TlsTranscript _transcript;
    private TlsCipherSuite _suite;
    private TlsNamedGroup _group;
    private TlsSignatureScheme _scheme;
    private byte[] _serverRandom;
    private Tls12KeySchedule? _schedule;
    private TlsKeyShare? _share;
    private bool _certificateRequested;

    internal Tls12ServerHandshake(TlsConnection connection, TlsServerOptions options,
                                  TlsClientHello hello, TlsSigningKey key)
    {
        _connection = connection;
        _options = options;
        _hello = hello;
        _key = key;
        _transcript = new TlsTranscript();
        _suite = TlsCipherSuite.TlsEcdheEcdsaWithAes128GcmSha256;
        _group = TlsNamedGroup.X25519;
        _scheme = TlsSignatureScheme.Ed25519;
        _serverRandom = new byte[0u];
        _schedule = null;
        _share = null;
        _certificateRequested = options.ClientCertificateRequested ||
                                options.ClientCertificateRequired;
    }

    /// The handshake from `clientHello` on. `speaksTls13` is whether this
    /// server could have spoken TLS 1.3, which obliges it to write the
    /// downgrade sentinel into its random.
    internal TlsError RunTls12ServerHandshake(byte[] clientHello, bool speaksTls13)
    {
        TlsError step = ChooseTls12Parameters();
        if (step != TlsError.None)
            return step;
        _transcript.AddTlsMessage(clientHello);
        step = SendTls12ServerFlight(speaksTls13);
        if (step != TlsError.None)
            return step;
        step = ReadTls12ClientFlight();
        if (step != TlsError.None)
            return step;
        return SendTls12ServerFinished();
    }

    // ------------------------------------------------------------ ClientHello

    /// The suite, group, signature scheme and application protocol, each by
    /// this server's preference.
    private TlsError ChooseTls12Parameters()
    {
        if (!_hello._nullCompressionOnly)
            return TlsError.IllegalParameter;
        if (!_hello._hasExtendedMasterSecret)
            return TlsError.HandshakeFailed;
        // RFC 5746 §3.6: the client's renegotiated_connection is empty in a
        // first handshake.
        if (_hello._hasRenegotiationInfo && _hello._renegotiationInfo.Length != 0u)
            return TlsError.HandshakeFailed;
        if (_hello._hasEcPointFormats && !_hello._offersUncompressedPoints)
            return TlsError.IllegalParameter;

        // A certificate on a curve the client did not name is one it cannot
        // use, which leaves no suite for this key.
        bool keyUsable = !_hello._hasSupportedGroups ||
                         IsTls12KeyOnSupportedCurve(_key.Kind, _hello._supportedGroups);
        bool foundSuite = false;
        List<TlsCipherSuite> suites = _options.CipherSuites;
        for (nuint i = 0u; i < suites.Count && !foundSuite && keyUsable; i++)
        {
            TlsCipherSuite suite = suites[i];
            if (IsTls12CipherSuite(suite) && IsTls12SuiteForKey(suite, _key.Kind) &&
                _hello._cipherSuites.Contains((uint)suite))
            {
                _suite = suite;
                foundSuite = true;
            }
        }
        if (!foundSuite)
            return TlsError.NoCommonCipherSuite;

        // Without signature_algorithms a TLS 1.2 client means SHA-1 (RFC
        // 5246 §7.4.1.4.1), which this end does not sign with.
        if (!_hello._hasSignatureAlgorithms)
            return TlsError.HandshakeFailed;
        var scheme = _key.SelectTls12Scheme(_hello._signatureAlgorithms);
        if (!scheme.Some)
            return TlsError.HandshakeFailed;
        _scheme = scheme.Value;

        // A client that names no groups leaves the choice to the server.
        List<TlsNamedGroup> groups = _options.KeyExchangeGroups;
        bool foundGroup = false;
        for (nuint i = 0u; i < groups.Count && !foundGroup; i++)
        {
            TlsNamedGroup group = groups[i];
            if (IsImplementedTlsGroup(group) &&
                (!_hello._hasSupportedGroups || _hello._supportedGroups.Contains((uint)group)))
            {
                _group = group;
                foundGroup = true;
            }
        }
        if (!foundGroup)
            return TlsError.NoCommonGroup;

        List<String> protocols = _options.ApplicationProtocols;
        if (protocols.Count > 0u && _hello._hasApplicationProtocols)
        {
            for (nuint i = 0u; i < protocols.Count; i++)
            {
                if (_hello._applicationProtocols.Contains(protocols[i]))
                {
                    _connection._applicationProtocol = protocols[i];
                    break;
                }
            }
            if (_connection._applicationProtocol == null)
                return TlsError.NoApplicationProtocol;
        }

        if (_hello._hasServerName)
            _connection._targetHost = _hello._serverName;
        _connection._cipherSuite = _suite;
        _connection._group = _group;
        _connection._signatureScheme = _scheme;
        return TlsError.None;
    }

    // ------------------------------------------------------ the server's flight

    /// ServerHello, Certificate, ServerKeyExchange, an optional
    /// CertificateRequest, and ServerHelloDone, in as few records as fit.
    private TlsError SendTls12ServerFlight(bool speaksTls13)
    {
        byte[] random = RandomNumberGenerator.GetBytes(32u);
        if (_options._fixedRandom.Length == 32u)
            memcpy(&random[0u], &_options._fixedRandom[0u], 32u);
        if (speaksTls13)
        {
            byte[] sentinel = CreateTlsDowngradeSentinel();
            for (nuint i = 0u; i < sentinel.Length; i++)
                random[24u + i] = sentinel[i];
            random[31u] = 1;
        }
        _serverRandom = random;
        _schedule = new Tls12KeySchedule(GetTlsSuiteHash(_suite), _hello._random, random);

        var hello = new TlsBuffer(256u);
        nuint body = BeginTlsHandshakeMessage(hello, TlsHandshakeType.ServerHello);
        hello.WriteUInt16(TlsVersion12);
        hello.WriteBytes(random);
        // An empty session id: this server caches nothing to resume.
        hello.WriteByte(0u);
        hello.WriteUInt16((uint)_suite);
        hello.WriteByte(0u);
        nuint extensionsAt = hello.BeginVector(2u);
        if (_hello.SignalsTlsRenegotiationInfo)
        {
            nuint at = BeginTlsExtension(hello, TlsExtensionType.RenegotiationInfo);
            hello.WriteByte(0u);
            EndTlsExtension(hello, at);
        }
        nuint masterAt = BeginTlsExtension(hello, TlsExtensionType.ExtendedMasterSecret);
        EndTlsExtension(hello, masterAt);
        if (_hello._hasEcPointFormats)
        {
            nuint at = BeginTlsExtension(hello, TlsExtensionType.EcPointFormats);
            hello.WriteByte(1u);
            hello.WriteByte(0u);
            EndTlsExtension(hello, at);
        }
        if (_hello._hasServerName)
        {
            nuint at = BeginTlsExtension(hello, TlsExtensionType.ServerName);
            EndTlsExtension(hello, at);
        }
        var protocol = _connection._applicationProtocol;
        if (protocol != null)
        {
            nuint at = BeginTlsExtension(
                hello, TlsExtensionType.ApplicationLayerProtocolNegotiation);
            nuint namesAt = hello.BeginVector(2u);
            nuint nameAt = hello.BeginVector(1u);
            hello.WriteBytes(ConvertTlsTextToBytes(protocol));
            hello.EndVector(nameAt, 1u);
            hello.EndVector(namesAt, 2u);
            EndTlsExtension(hello, at);
        }
        hello.EndVector(extensionsAt, 2u);
        EndTlsHandshakeMessage(hello, body);
        QueueTls12ServerMessage(hello.ToArray());

        QueueTls12ServerMessage(BuildTls12CertificateMessage(_options.CertificateChain));

        TlsError exchanged = QueueTls12ServerKeyExchange();
        if (exchanged != TlsError.None)
            return exchanged;

        if (_certificateRequested)
        {
            var request = new TlsBuffer(128u);
            nuint requestBody = BeginTlsHandshakeMessage(
                request, TlsHandshakeType.CertificateRequest);
            // rsa_sign and ecdsa_sign, which RFC 8422 also uses for Ed25519.
            request.WriteByte(2u);
            request.WriteByte(1u);
            request.WriteByte(64u);
            WriteTlsSignatureSchemes(request, CreateDefaultTls12SignatureSchemes());
            request.WriteUInt16(0u);
            EndTlsHandshakeMessage(request, requestBody);
            QueueTls12ServerMessage(request.ToArray());
        }

        var done = new TlsBuffer(4u);
        nuint doneBody = BeginTlsHandshakeMessage(done, TlsHandshakeType.ServerHelloDone);
        EndTlsHandshakeMessage(done, doneBody);
        QueueTls12ServerMessage(done.ToArray());
        return _connection.FlushTlsHandshake();
    }

    /// The ephemeral key, in the group chosen, signed over both randoms.
    private TlsError QueueTls12ServerKeyExchange()
    {
        Result<TlsKeyShare, TlsError> share = Fail(TlsError.InternalError);
        if (_options._fixedX25519PrivateKey.Length > 0u && _group == TlsNamedGroup.X25519)
        {
            share = TlsKeyShare.CreateTlsX25519KeyShare(_options._fixedX25519PrivateKey);
        }
        else
        {
            share = TlsKeyShare.GenerateTlsKeyShare(_group);
        }
        if (!share.Ok)
            return share.Error;
        _share = share.Value;

        var parameters = new TlsBuffer(128u);
        parameters.WriteByte(3u);
        parameters.WriteUInt16((uint)_group);
        nuint pointAt = parameters.BeginVector(1u);
        parameters.WriteBytes(share.Value.PublicKey);
        parameters.EndVector(pointAt, 1u);

        var signed = new TlsBuffer(64u + parameters.Length);
        signed.WriteBytes(_hello._random);
        signed.WriteBytes(_serverRandom);
        signed.WriteBytes(parameters.Written);
        var signature = _key.SignTlsContent(_scheme, signed.Written);
        if (!signature.Ok)
            return signature.Error;

        var exchange = new TlsBuffer(parameters.Length + signature.Value.Length + 16u);
        nuint body = BeginTlsHandshakeMessage(exchange, TlsHandshakeType.ServerKeyExchange);
        exchange.WriteBytes(parameters.Written);
        exchange.WriteUInt16((uint)_scheme);
        nuint signatureAt = exchange.BeginVector(2u);
        exchange.WriteBytes(signature.Value);
        exchange.EndVector(signatureAt, 2u);
        EndTlsHandshakeMessage(exchange, body);
        QueueTls12ServerMessage(exchange.ToArray());
        return TlsError.None;
    }

    private void QueueTls12ServerMessage(byte[] message)
    {
        _transcript.AddTlsMessage(message);
        _connection.QueueTlsHandshakeMessage(message);
    }

    // ------------------------------------------------------ the client's flight

    /// An optional Certificate, ClientKeyExchange, an optional
    /// CertificateVerify, change_cipher_spec and Finished.
    ///
    /// A client certificate that is missing or refused is reported only once
    /// the whole flight is read. The client sent it in one go, and a server
    /// that closed with it unread would reset the connection and lose its
    /// own alert. The CertificateVerify of a refused chain is read and not
    /// checked.
    private TlsError ReadTls12ClientFlight()
    {
        var schedule = _schedule;
        var share = _share;
        if (schedule == null || share == null)
            return TlsError.InternalError;

        TlsError refusal = TlsError.None;
        bool verifyExpected = false;
        TlsPeerKey? clientKey = null;
        if (_certificateRequested)
        {
            var read = ReadTls12ClientMessage(TlsHandshakeType.Certificate);
            if (!read.Ok)
                return read.Error;
            var chain = ReadTls12CertificateMessage(read.Value, true);
            if (!chain.Ok)
                return chain.Error;
            _transcript.AddTlsMessage(read.Value);

            if (chain.Value.Count == 0u)
            {
                if (_options.ClientCertificateRequired)
                    refusal = TlsError.CertificateRequired;
            }
            else
            {
                verifyExpected = true;
                refusal = _options.ClientCertificateValidator(chain.Value, "");
                _connection._remoteChain = chain.Value;
                // A refused chain's key is never used.
                if (refusal == TlsError.None)
                {
                    var key = TlsPeerKey.ReadTlsPeerKey(chain.Value[0u]);
                    if (!key.Ok)
                        return key.Error;
                    clientKey = key.Value;
                }
            }
        }

        var exchange = ReadTls12ClientMessage(TlsHandshakeType.ClientKeyExchange);
        if (!exchange.Ok)
            return exchange.Error;
        var reader = new TlsReader(exchange.Value, 4u, exchange.Value.Length - 4u);
        byte[] point = reader.ReadVectorArray(1u, 1u, 255u);
        if (reader.Failed || !reader.IsAtEnd)
            return TlsError.Decode;
        var premaster = share.DeriveTlsSharedSecret(point);
        share.WipeTlsPrivateKey();
        if (!premaster.Ok)
            return premaster.Error;
        _transcript.AddTlsMessage(exchange.Value);
        schedule.DeriveTlsExtendedMasterSecret(
            premaster.Value, _transcript.ComputeTls12TranscriptHash(schedule));
        CryptographicOperations.ZeroMemory(premaster.Value);
        _connection._tls12Schedule = schedule;

        if (verifyExpected)
        {
            var read = ReadTls12ClientMessage(TlsHandshakeType.CertificateVerify);
            if (!read.Ok)
                return read.Error;
            var verifying = new TlsReader(read.Value, 4u, read.Value.Length - 4u);
            var scheme = (TlsSignatureScheme)(ushort)verifying.ReadUInt16();
            byte[] signature = verifying.ReadVectorArray(2u, 0u, 65535u);
            if (verifying.Failed || !verifying.IsAtEnd)
                return TlsError.Decode;
            if (clientKey != null)
            {
                if (!CreateDefaultTls12SignatureSchemes().Contains(scheme) ||
                    !IsTls12SchemeForKey(scheme, clientKey.Kind))
                {
                    return TlsError.IllegalParameter;
                }
                if (!clientKey.VerifyTls12Signature(scheme, _transcript.Messages, signature))
                    return TlsError.DecryptError;
                _connection._mutuallyAuthenticated = true;
            }
            _transcript.AddTlsMessage(read.Value);
        }

        TlsError changed = _connection.ReadTlsChangeCipherSpec();
        if (changed != TlsError.None)
            return changed;
        var reading = schedule.TakeTls12RecordCipher(_suite, true);
        if (!reading.Ok)
            return reading.Error;
        _connection._records.InstallTlsReadCipher(reading.Value);

        var finished = ReadTls12ClientMessage(TlsHandshakeType.Finished);
        if (!finished.Ok)
            return finished.Error;
        byte[] expected = schedule.ComputeTls12Finished(
            true, _transcript.ComputeTls12TranscriptHash(schedule));
        TlsError verified = VerifyTlsFinished(finished.Value, expected);
        if (verified != TlsError.None)
            return verified;
        if (refusal != TlsError.None)
            return refusal;
        _transcript.AddTlsMessage(finished.Value);
        return _connection.RequireTlsRecordBoundary();
    }

    private Result<byte[], TlsError> ReadTls12ClientMessage(TlsHandshakeType type)
    {
        var read = _connection.ReadTlsHandshakeMessage();
        if (!read.Ok)
            return read;
        if ((TlsHandshakeType)read.Value[0u] != type)
            return Fail(TlsError.UnexpectedMessage);
        return read;
    }

    // ---------------------------------------------------- the server's Finished

    private TlsError SendTls12ServerFinished()
    {
        var schedule = _schedule;
        if (schedule == null)
            return TlsError.InternalError;

        TlsError sent = _connection.WriteTlsChangeCipherSpec();
        if (sent != TlsError.None)
            return sent;
        var writing = schedule.TakeTls12RecordCipher(_suite, false);
        if (!writing.Ok)
            return writing.Error;
        _connection.InstallTlsWriteCipher(writing.Value);

        byte[] verifyData = schedule.ComputeTls12Finished(
            false, _transcript.ComputeTls12TranscriptHash(schedule));
        _connection.QueueTlsHandshakeMessage(BuildTlsFinished(verifyData));
        sent = _connection.FlushTlsHandshake();
        if (sent != TlsError.None)
            return sent;
        _connection._handshakeComplete = true;
        return TlsError.None;
    }
}
