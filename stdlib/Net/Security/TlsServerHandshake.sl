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

/// The server's side of a TLS 1.3 handshake (RFC 8446 §4), run once over a
/// fresh connection.
///
/// A ClientHello without supported_versions, or without TLS 1.3 in it, is
/// where TLS 1.2 plugs in; `ChooseTlsServerVersion` refuses it today.
internal sealed class TlsServerHandshake
{
    private TlsConnection _connection;
    private TlsServerOptions _options;
    private TlsTranscript _transcript;
    private TlsClientHello _hello;
    private TlsKeySchedule? _schedule;
    private TlsCipherSuite _suite;
    private TlsNamedGroup _group;
    private TlsSignatureScheme _scheme;
    private bool _retried;
    private byte[] _cookie;
    private bool _changeCipherSpecSent;
    private bool _certificateRequested;

    internal TlsServerHandshake(TlsConnection connection, TlsServerOptions options)
    {
        _connection = connection;
        _options = options;
        _transcript = new TlsTranscript();
        _hello = new TlsClientHello();
        _schedule = null;
        _suite = TlsCipherSuite.TlsAes128GcmSha256;
        _group = TlsNamedGroup.X25519;
        _scheme = TlsSignatureScheme.Ed25519;
        _retried = false;
        _cookie = new byte[0u];
        _changeCipherSpecSent = false;
        _certificateRequested = options.ClientCertificateRequested || options.ClientCertificateRequired;
    }

    internal TlsKeySchedule? Schedule => _schedule;

    internal TlsError RunTlsServerHandshake()
    {
        var key = _options.PrivateKey;
        if (key == null || _options.CertificateChain.Count == 0u)
            return TlsError.InternalError;
        if (!_options.EnabledProtocols.HasFlag(TlsProtocolVersion.Tls13))
            return TlsError.ProtocolVersion;

        var read = _connection.ReadTlsHandshakeMessage();
        if (!read.Ok)
            return read.Error;
        byte[] first = read.Value;
        if ((TlsHandshakeType)first[0u] != TlsHandshakeType.ClientHello)
            return TlsError.UnexpectedMessage;
        _connection._records._changeCipherSpecAllowed = true;

        TlsError step = ReadTlsClientHello(first, key);
        if (step != TlsError.None)
            return step;

        byte[] peerShare = _hello.FindTlsKeyShare(_group);
        if (peerShare.Length == 0u)
        {
            step = RequestTlsKeyShare(first, key);
            if (step != TlsError.None)
                return step;
            peerShare = _hello.FindTlsKeyShare(_group);
        }
        else
        {
            var schedule = new TlsKeySchedule(GetTlsSuiteHash(_suite));
            _schedule = schedule;
            _transcript.AddTlsMessage(first);
        }

        step = SendTlsServerHello(peerShare);
        if (step != TlsError.None)
            return step;
        step = SendTlsServerFlight(key);
        if (step != TlsError.None)
            return step;
        return ReadTlsClientFlight();
    }

    // ------------------------------------------------------------ ClientHello

    /// Reads a ClientHello and chooses the version, suite, group, signature
    /// scheme and application protocol, each by this server's preference.
    private TlsError ReadTlsClientHello(byte[] message, TlsSigningKey key)
    {
        var parsed = TlsClientHello.ParseTlsClientHello(message);
        if (!parsed.Ok)
            return parsed.Error;
        _hello = parsed.Value;

        if (!_hello._hasSupportedVersions || !_hello._supportedVersions.Contains(TlsVersion13))
            return TlsError.ProtocolVersion;
        if (!_hello._nullCompressionOnly)
            return TlsError.IllegalParameter;

        bool foundSuite = false;
        List<TlsCipherSuite> suites = _options.CipherSuites;
        for (nuint i = 0u; i < suites.Count && !foundSuite; i++)
        {
            if (IsImplementedTlsCipherSuite(suites[i]) && _hello._cipherSuites.Contains((uint)suites[i]))
            {
                _suite = suites[i];
                foundSuite = true;
            }
        }
        if (!foundSuite)
            return TlsError.NoCommonCipherSuite;

        if (!_hello._hasSignatureAlgorithms)
            return TlsError.MissingExtension;
        var scheme = key.SelectTlsScheme(_hello._signatureAlgorithms);
        if (!scheme.Some)
            return TlsError.HandshakeFailed;
        _scheme = scheme.Value;

        if (!_hello._hasSupportedGroups || !_hello._hasKeyShare)
            return TlsError.MissingExtension;

        // The server's favourite group among those the client sent a share
        // in; failing that, its favourite the client supports at all, which
        // costs a HelloRetryRequest.
        List<TlsNamedGroup> groups = _options.KeyExchangeGroups;
        bool foundGroup = false;
        for (nuint i = 0u; i < groups.Count && !foundGroup; i++)
        {
            if (IsImplementedTlsGroup(groups[i]) && _hello._keyShareGroups.Contains((uint)groups[i]))
            {
                _group = groups[i];
                foundGroup = true;
            }
        }
        for (nuint i = 0u; i < groups.Count && !foundGroup; i++)
        {
            if (IsImplementedTlsGroup(groups[i]) && _hello._supportedGroups.Contains((uint)groups[i]))
            {
                _group = groups[i];
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

    /// Sends a HelloRetryRequest for the chosen group, with a cookie the
    /// client MUST echo, and reads the second ClientHello (RFC 8446 §4.1.4).
    private TlsError RequestTlsKeyShare(byte[] first, TlsSigningKey key)
    {
        var schedule = new TlsKeySchedule(GetTlsSuiteHash(_suite));
        _schedule = schedule;
        _transcript.AddTlsMessage(first);
        _transcript.ReplaceWithTlsMessageHash(schedule);
        _cookie = RandomNumberGenerator.GetBytes(32u);
        _retried = true;

        var retry = new TlsBuffer(128u);
        nuint body = BeginTlsHandshakeMessage(retry, TlsHandshakeType.ServerHello);
        retry.WriteUInt16(TlsLegacyVersion);
        retry.WriteBytes(s_helloRetryRequestRandom);
        nuint sessionAt = retry.BeginVector(1u);
        retry.WriteBytes(_hello._sessionId);
        retry.EndVector(sessionAt, 1u);
        retry.WriteUInt16((uint)_suite);
        retry.WriteByte(0u);
        nuint extensionsAt = retry.BeginVector(2u);
        nuint versionAt = BeginTlsExtension(retry, TlsExtensionType.SupportedVersions);
        retry.WriteUInt16(TlsVersion13);
        EndTlsExtension(retry, versionAt);
        nuint shareAt = BeginTlsExtension(retry, TlsExtensionType.KeyShare);
        retry.WriteUInt16((uint)_group);
        EndTlsExtension(retry, shareAt);
        nuint cookieAt = BeginTlsExtension(retry, TlsExtensionType.Cookie);
        nuint cookieBytesAt = retry.BeginVector(2u);
        retry.WriteBytes(_cookie);
        retry.EndVector(cookieBytesAt, 2u);
        EndTlsExtension(retry, cookieAt);
        retry.EndVector(extensionsAt, 2u);
        EndTlsHandshakeMessage(retry, body);

        byte[] retryMessage = retry.ToArray();
        _transcript.AddTlsMessage(retryMessage);
        _connection.QueueTlsHandshakeMessage(retryMessage);
        TlsError sent = _connection.FlushTlsHandshake();
        if (sent != TlsError.None)
            return sent;
        sent = SendTlsCompatibilityChangeCipherSpec();
        if (sent != TlsError.None)
            return sent;

        var read = _connection.ReadTlsHandshakeMessage();
        if (!read.Ok)
            return read.Error;
        byte[] second = read.Value;
        if ((TlsHandshakeType)second[0u] != TlsHandshakeType.ClientHello)
            return TlsError.UnexpectedMessage;

        TlsClientHello previous = _hello;
        TlsCipherSuite suite = _suite;
        TlsNamedGroup group = _group;
        TlsError chosen = ReadTlsClientHello(second, key);
        if (chosen != TlsError.None)
            return chosen;

        // The second hello MUST be the first with one share, in the group
        // asked for, and the cookie; so the same choices MUST fall out of it.
        if (!AreTlsBytesEqual(previous._random, _hello._random) ||
            !AreTlsBytesEqual(previous._sessionId, _hello._sessionId) ||
            suite != _suite || group != _group)
        {
            return TlsError.IllegalParameter;
        }
        if (_hello._keyShareGroups.Count != 1u || _hello._keyShareGroups[0u] != (uint)_group)
            return TlsError.IllegalParameter;
        if (!_hello._hasCookie || !AreTlsBytesEqual(_hello._cookie, _cookie))
            return TlsError.IllegalParameter;

        _transcript.AddTlsMessage(second);
        return TlsError.None;
    }

    private TlsError SendTlsCompatibilityChangeCipherSpec()
    {
        if (_changeCipherSpecSent || _hello._sessionId.Length == 0u)
            return TlsError.None;
        _changeCipherSpecSent = true;
        return _connection.WriteTlsChangeCipherSpec();
    }

    // ------------------------------------------------------------ ServerHello

    private TlsError SendTlsServerHello(byte[] peerShare)
    {
        var schedule = _schedule;
        if (schedule == null)
            return TlsError.InternalError;

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
        var shared = share.Value.DeriveTlsSharedSecret(peerShare);
        if (!shared.Ok)
            return shared.Error;

        byte[] random = _options._fixedRandom.Length == 32u
            ? _options._fixedRandom
            : RandomNumberGenerator.GetBytes(32u);

        var hello = new TlsBuffer(256u);
        nuint body = BeginTlsHandshakeMessage(hello, TlsHandshakeType.ServerHello);
        hello.WriteUInt16(TlsLegacyVersion);
        hello.WriteBytes(random);
        nuint sessionAt = hello.BeginVector(1u);
        hello.WriteBytes(_hello._sessionId);
        hello.EndVector(sessionAt, 1u);
        hello.WriteUInt16((uint)_suite);
        hello.WriteByte(0u);
        nuint extensionsAt = hello.BeginVector(2u);
        nuint shareAt = BeginTlsExtension(hello, TlsExtensionType.KeyShare);
        hello.WriteUInt16((uint)_group);
        nuint keyAt = hello.BeginVector(2u);
        hello.WriteBytes(share.Value.PublicKey);
        hello.EndVector(keyAt, 2u);
        EndTlsExtension(hello, shareAt);
        nuint versionAt = BeginTlsExtension(hello, TlsExtensionType.SupportedVersions);
        hello.WriteUInt16(TlsVersion13);
        EndTlsExtension(hello, versionAt);
        hello.EndVector(extensionsAt, 2u);
        EndTlsHandshakeMessage(hello, body);

        byte[] message = hello.ToArray();
        _transcript.AddTlsMessage(message);
        _connection.QueueTlsHandshakeMessage(message);
        TlsError sent = _connection.FlushTlsHandshake();
        if (sent != TlsError.None)
            return sent;
        sent = SendTlsCompatibilityChangeCipherSpec();
        if (sent != TlsError.None)
            return sent;

        schedule.DeriveHandshakeSecrets(shared.Value, _transcript.ComputeTlsTranscriptHash(schedule));
        _connection._schedule = schedule;

        TlsError boundary = _connection.RequireTlsRecordBoundary();
        if (boundary != TlsError.None)
            return boundary;
        var writing = schedule.CreateTlsRecordCipher(_suite, schedule._serverHandshakeTrafficSecret);
        if (!writing.Ok)
            return writing.Error;
        var reading = schedule.CreateTlsRecordCipher(_suite, schedule._clientHandshakeTrafficSecret);
        if (!reading.Ok)
            return reading.Error;
        _connection.InstallTlsWriteCipher(writing.Value);
        _connection._records.InstallTlsReadCipher(reading.Value);
        return TlsError.None;
    }

    // ------------------------------------------------ the rest of the flight

    private TlsError SendTlsServerFlight(TlsSigningKey key)
    {
        var schedule = _schedule;
        if (schedule == null)
            return TlsError.InternalError;

        var extensions = new TlsBuffer(128u);
        nuint body = BeginTlsHandshakeMessage(extensions, TlsHandshakeType.EncryptedExtensions);
        nuint listAt = extensions.BeginVector(2u);
        if (_hello._hasServerName)
        {
            nuint at = BeginTlsExtension(extensions, TlsExtensionType.ServerName);
            EndTlsExtension(extensions, at);
        }
        var protocol = _connection._applicationProtocol;
        if (protocol != null)
        {
            nuint at = BeginTlsExtension(extensions, TlsExtensionType.ApplicationLayerProtocolNegotiation);
            nuint namesAt = extensions.BeginVector(2u);
            nuint nameAt = extensions.BeginVector(1u);
            extensions.WriteBytes(ConvertTlsTextToBytes(protocol));
            extensions.EndVector(nameAt, 1u);
            extensions.EndVector(namesAt, 2u);
            EndTlsExtension(extensions, at);
        }
        extensions.EndVector(listAt, 2u);
        EndTlsHandshakeMessage(extensions, body);
        QueueTlsServerMessage(extensions.ToArray());

        if (_certificateRequested)
        {
            var request = new TlsBuffer(128u);
            nuint requestBody = BeginTlsHandshakeMessage(request, TlsHandshakeType.CertificateRequest);
            request.WriteByte(0u);
            nuint requestExtensionsAt = request.BeginVector(2u);
            nuint schemesAt = BeginTlsExtension(request, TlsExtensionType.SignatureAlgorithms);
            WriteTlsSignatureSchemes(request, CreateDefaultTlsSignatureSchemes());
            EndTlsExtension(request, schemesAt);
            request.EndVector(requestExtensionsAt, 2u);
            EndTlsHandshakeMessage(request, requestBody);
            QueueTlsServerMessage(request.ToArray());
        }

        QueueTlsServerMessage(BuildTlsCertificateMessage(new byte[0u], _options.CertificateChain));

        byte[] content = BuildTlsSignedContent(true, _transcript.ComputeTlsTranscriptHash(schedule));
        var signature = key.SignTlsContent(_scheme, content);
        if (!signature.Ok)
            return signature.Error;
        QueueTlsServerMessage(BuildTlsCertificateVerify(_scheme, signature.Value));

        byte[] verifyData = schedule.ComputeTlsFinished(schedule._serverHandshakeTrafficSecret,
                                                        _transcript.ComputeTlsTranscriptHash(schedule));
        QueueTlsServerMessage(BuildTlsFinished(verifyData));
        TlsError sent = _connection.FlushTlsHandshake();
        if (sent != TlsError.None)
            return sent;

        schedule.DeriveApplicationSecrets(_transcript.ComputeTlsTranscriptHash(schedule));
        var writing = schedule.CreateTlsRecordCipher(_suite, schedule._serverApplicationTrafficSecret);
        if (!writing.Ok)
            return writing.Error;
        _connection.InstallTlsWriteCipher(writing.Value);
        _connection._writeTrafficSecret = schedule._serverApplicationTrafficSecret;
        return TlsError.None;
    }

    private void QueueTlsServerMessage(byte[] message)
    {
        _transcript.AddTlsMessage(message);
        _connection.QueueTlsHandshakeMessage(message);
    }

    // ------------------------------------------------------ the client's turn

    private TlsError ReadTlsClientFlight()
    {
        var schedule = _schedule;
        if (schedule == null)
            return TlsError.InternalError;

        var read = _connection.ReadTlsHandshakeMessage();
        if (!read.Ok)
            return read.Error;
        byte[] message = read.Value;

        if (_certificateRequested)
        {
            if ((TlsHandshakeType)message[0u] != TlsHandshakeType.Certificate)
                return TlsError.UnexpectedMessage;
            var chain = ReadTlsCertificateMessage(message, CreateTlsServerOffer(), true, new byte[0u]);
            if (!chain.Ok)
                return chain.Error;
            _transcript.AddTlsMessage(message);

            if (chain.Value.Count == 0u)
            {
                if (_options.ClientCertificateRequired)
                    return TlsError.CertificateRequired;
            }
            else
            {
                TlsError verdict = _options.ClientCertificateValidator(chain.Value, "");
                if (verdict != TlsError.None)
                    return verdict;
                var key = TlsPeerKey.ReadTlsPeerKey(chain.Value[0u]);
                if (!key.Ok)
                    return key.Error;
                _connection._remoteChain = chain.Value;

                read = _connection.ReadTlsHandshakeMessage();
                if (!read.Ok)
                    return read.Error;
                message = read.Value;
                if ((TlsHandshakeType)message[0u] != TlsHandshakeType.CertificateVerify)
                    return TlsError.UnexpectedMessage;
                var scheme = VerifyTlsCertificateVerify(message, key.Value,
                                                        _transcript.ComputeTlsTranscriptHash(schedule), false,
                                                        CreateDefaultTlsSignatureSchemes());
                if (!scheme.Ok)
                    return scheme.Error;
                _transcript.AddTlsMessage(message);
                _connection._mutuallyAuthenticated = true;
            }

            read = _connection.ReadTlsHandshakeMessage();
            if (!read.Ok)
                return read.Error;
            message = read.Value;
        }

        if ((TlsHandshakeType)message[0u] != TlsHandshakeType.Finished)
            return TlsError.UnexpectedMessage;
        byte[] expected = schedule.ComputeTlsFinished(schedule._clientHandshakeTrafficSecret,
                                                      _transcript.ComputeTlsTranscriptHash(schedule));
        TlsError finished = VerifyTlsFinished(message, expected);
        if (finished != TlsError.None)
            return finished;
        _transcript.AddTlsMessage(message);

        TlsError boundary = _connection.RequireTlsRecordBoundary();
        if (boundary != TlsError.None)
            return boundary;
        var reading = schedule.CreateTlsRecordCipher(_suite, schedule._clientApplicationTrafficSecret);
        if (!reading.Ok)
            return reading.Error;
        _connection._records.InstallTlsReadCipher(reading.Value);
        _connection._records._changeCipherSpecAllowed = false;
        _connection._records._plaintextAlertAllowed = false;
        _connection._readTrafficSecret = schedule._clientApplicationTrafficSecret;
        schedule.DeriveResumptionSecret(_transcript.ComputeTlsTranscriptHash(schedule));
        _connection._handshakeComplete = true;
        return TlsError.None;
    }

    /// What the server offered, as far as a client's Certificate entries may
    /// answer it: nothing, since the CertificateRequest carries only
    /// signature_algorithms.
    private TlsClientHello CreateTlsServerOffer() => new TlsClientHello();
}
