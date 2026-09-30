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

/// The client's side of a handshake, run once over a fresh connection: TLS
/// 1.3 (RFC 8446 §4) here, and TLS 1.2 handed to `Tls12ClientHandshake`.
///
/// One ClientHello offers both versions. The two part ways at the
/// ServerHello: one without supported_versions is TLS 1.2's, and is checked
/// for the downgrade sentinel before anything else is read from it.
internal sealed class TlsClientHandshake
{
    private TlsConnection _connection;
    private TlsClientOptions _options;
    private bool _offersTls13;
    private bool _offersTls12;
    private Tls12ClientHandshake? _tls12;
    private TlsTranscript _transcript;
    private TlsClientHello _offered;
    private byte[] _clientHello;
    private List<TlsKeyShare> _shares;
    private TlsKeySchedule? _schedule;
    private bool _retried;
    private uint _retrySuite;
    private bool _changeCipherSpecSent;
    private bool _certificateRequested;
    private byte[] _certificateRequestContext;
    private List<TlsSignatureScheme> _requestedSchemes;
    private TlsPeerKey? _serverKey;

    internal TlsClientHandshake(
        TlsConnection connection, TlsClientOptions options, String targetHost)
    {
        _connection = connection;
        _options = options;
        _offersTls13 = options.EnabledProtocols.HasFlag(TlsProtocolVersion.Tls13) &&
                       HasTlsSuiteForVersion(options.CipherSuites, true);
        _offersTls12 = options.EnabledProtocols.HasFlag(TlsProtocolVersion.Tls12) &&
                       HasTlsSuiteForVersion(options.CipherSuites, false);
        _tls12 = null;
        _transcript = new TlsTranscript();
        _offered = new TlsClientHello();
        _clientHello = new byte[0u];
        _shares = new List<TlsKeyShare>();
        _schedule = null;
        _retried = false;
        _retrySuite = 0u;
        _changeCipherSpecSent = false;
        _certificateRequested = false;
        _certificateRequestContext = new byte[0u];
        _requestedSchemes = new List<TlsSignatureScheme>();
        _serverKey = null;
        connection._targetHost = targetHost;
        connection._ticketHandler = options.SessionTicketReceived;
    }

    internal TlsKeySchedule? Schedule => _schedule;

    /// The whole handshake: `None`, or the failure, whose alert has not been
    /// sent yet.
    internal TlsError RunTlsClientHandshake()
    {
        if (!_offersTls13 && !_offersTls12)
            return TlsError.ProtocolVersion;
        // The default validator would have no name to check the certificate
        // against; only a validator of the program's own MAY do without one.
        if (_connection._targetHost.IsEmpty && !_options._hasCertificateValidatorSet)
            return TlsError.InternalError;

        TlsError step = SendTlsClientHello();
        if (step != TlsError.None)
            return step;
        step = ReadTlsServerHello();
        if (step != TlsError.None)
            return step;
        var legacy = _tls12;
        if (legacy != null)
            return legacy.RunTls12ClientHandshake();
        step = ReadTlsEncryptedExtensions();
        if (step != TlsError.None)
            return step;
        step = ReadTlsServerAuthentication();
        if (step != TlsError.None)
            return step;
        return SendTlsClientFinished();
    }

    // ------------------------------------------------------------ ClientHello

    private TlsError SendTlsClientHello()
    {
        TlsError shared = GenerateTlsKeyShares();
        if (shared != TlsError.None)
            return shared;

        if (_options._fixedClientHello.Length > 0u)
        {
            _clientHello = _options._fixedClientHello;
        }
        else
        {
            var built = BuildTlsClientHello();
            if (!built.Ok)
                return built.Error;
            _clientHello = built.Value;
        }

        // What was offered is read back from the message itself, so that a
        // ClientHello supplied whole is checked against as faithfully as one
        // built here.
        var offered = TlsClientHello.ParseTlsClientHello(_clientHello);
        if (!offered.Ok)
            return TlsError.InternalError;
        _offered = offered.Value;

        _transcript.AddTlsMessage(_clientHello);
        _connection._records._plaintextVersion = 0x0301u;
        _connection.QueueTlsHandshakeMessage(_clientHello);
        TlsError sent = _connection.FlushTlsHandshake();
        _connection._records._plaintextVersion = TlsLegacyVersion;
        _connection._records._changeCipherSpecAllowed = true;
        _connection._skipsHelloRequest = _offersTls12;
        return sent;
    }

    /// A key share for each group asked for, or the fixed X25519 key a test
    /// supplied.
    private TlsError GenerateTlsKeyShares()
    {
        _shares.Clear();
        if (!_offersTls13)
            return TlsError.None;
        if (_options._fixedX25519PrivateKey.Length > 0u)
        {
            var fixedShare = TlsKeyShare.CreateTlsX25519KeyShare(_options._fixedX25519PrivateKey);
            if (!fixedShare.Ok)
                return fixedShare.Error;
            _shares.Add(fixedShare.Value);
            return TlsError.None;
        }

        List<TlsNamedGroup> wanted = _options.KeyShareGroups;
        for (nuint i = 0u; i < wanted.Count; i++)
        {
            TlsNamedGroup group = wanted[i];
            if (!_options.KeyExchangeGroups.Contains(group) || !IsImplementedTlsGroup(group))
                return TlsError.InternalError;
            var share = TlsKeyShare.GenerateTlsKeyShare(wanted[i]);
            if (!share.Ok)
                return share.Error;
            _shares.Add(share.Value);
        }
        return TlsError.None;
    }

    private Result<byte[], TlsError> BuildTlsClientHello()
    {
        List<TlsCipherSuite> suites = _options.CipherSuites;
        List<TlsNamedGroup> groups = _options.KeyExchangeGroups;
        if (suites.Count == 0u || groups.Count == 0u)
            return Fail(TlsError.InternalError);

        byte[] random = _offered._random;
        byte[] sessionId = _offered._sessionId;
        if (random.Length != 32u)
        {
            random = _options._fixedRandom.Length == 32u
                ? _options._fixedRandom
                : RandomNumberGenerator.GetBytes(32u);
            // Middlebox compatibility mode (RFC 8446 Appendix D.4): a
            // non-empty session id, and a change_cipher_spec before the
            // second flight. A TLS 1.2 server would read it as an offer to
            // resume, so a client of TLS 1.2 alone sends none.
            if (_offersTls13)
                sessionId = RandomNumberGenerator.GetBytes(32u);
        }

        var message = new TlsBuffer(512u);
        nuint body = BeginTlsHandshakeMessage(message, TlsHandshakeType.ClientHello);
        message.WriteUInt16(TlsLegacyVersion);
        message.WriteBytes(random);
        nuint sessionAt = message.BeginVector(1u);
        message.WriteBytes(sessionId);
        message.EndVector(sessionAt, 1u);

        nuint suitesAt = message.BeginVector(2u);
        for (nuint i = 0u; i < suites.Count; i++)
        {
            TlsCipherSuite suite = suites[i];
            if (!IsImplementedTlsCipherSuite(suite))
                return Fail(TlsError.InternalError);
            if (IsTls13CipherSuite(suite) ? _offersTls13 : _offersTls12)
                message.WriteUInt16((uint)suite);
        }
        message.EndVector(suitesAt, 2u);
        message.WriteByte(1u);
        message.WriteByte(0u);

        nuint extensionsAt = message.BeginVector(2u);

        String host = _connection._targetHost;
        if (host.ByteLength() > 0u && !IsTlsAddressLiteral(host))
        {
            nuint at = BeginTlsExtension(message, TlsExtensionType.ServerName);
            nuint listAt = message.BeginVector(2u);
            message.WriteByte(0u);
            nuint nameAt = message.BeginVector(2u);
            message.WriteBytes(ConvertTlsTextToBytes(host));
            message.EndVector(nameAt, 2u);
            message.EndVector(listAt, 2u);
            EndTlsExtension(message, at);
        }

        // A client of TLS 1.2 alone sends no supported_versions at all, as a
        // TLS 1.2 client would.
        if (_offersTls13)
        {
            nuint versionsAt = BeginTlsExtension(message, TlsExtensionType.SupportedVersions);
            nuint versionListAt = message.BeginVector(1u);
            message.WriteUInt16(TlsVersion13);
            if (_offersTls12)
                message.WriteUInt16(TlsVersion12);
            message.EndVector(versionListAt, 1u);
            EndTlsExtension(message, versionsAt);
        }

        nuint groupsAt = BeginTlsExtension(message, TlsExtensionType.SupportedGroups);
        nuint groupListAt = message.BeginVector(2u);
        for (nuint i = 0u; i < groups.Count; i++)
            message.WriteUInt16((uint)groups[i]);
        message.EndVector(groupListAt, 2u);
        EndTlsExtension(message, groupsAt);

        if (_offersTls13)
        {
            nuint sharesAt = BeginTlsExtension(message, TlsExtensionType.KeyShare);
            nuint shareListAt = message.BeginVector(2u);
            for (nuint i = 0u; i < _shares.Count; i++)
            {
                message.WriteUInt16((uint)_shares[i].Group);
                nuint keyAt = message.BeginVector(2u);
                message.WriteBytes(_shares[i].PublicKey);
                message.EndVector(keyAt, 2u);
            }
            message.EndVector(shareListAt, 2u);
            EndTlsExtension(message, sharesAt);
        }

        nuint signaturesAt = BeginTlsExtension(message, TlsExtensionType.SignatureAlgorithms);
        WriteTlsSignatureSchemes(message, _offersTls12 ? CreateDefaultTls12SignatureSchemes()
                                                       : CreateDefaultTlsSignatureSchemes());
        EndTlsExtension(message, signaturesAt);

        if (_offersTls13)
        {
            nuint certificateSignaturesAt = BeginTlsExtension(
                message, TlsExtensionType.SignatureAlgorithmsCert);
            WriteTlsSignatureSchemes(message, CreateDefaultTlsCertificateSignatureSchemes());
            EndTlsExtension(message, certificateSignaturesAt);
        }

        if (_offersTls12)
        {
            // Uncompressed points only; the extended master secret, which a
            // TLS 1.2 server MUST answer; secure renegotiation, as the empty
            // renegotiation_info of RFC 5746, since this end never
            // renegotiates; and an empty session_ticket, so that a server
            // MAY send a ticket.
            nuint formatsAt = BeginTlsExtension(message, TlsExtensionType.EcPointFormats);
            message.WriteByte(1u);
            message.WriteByte(0u);
            EndTlsExtension(message, formatsAt);

            nuint masterAt = BeginTlsExtension(message, TlsExtensionType.ExtendedMasterSecret);
            EndTlsExtension(message, masterAt);

            nuint renegotiationAt = BeginTlsExtension(message, TlsExtensionType.RenegotiationInfo);
            message.WriteByte(0u);
            EndTlsExtension(message, renegotiationAt);

            nuint ticketAt = BeginTlsExtension(message, TlsExtensionType.SessionTicket);
            EndTlsExtension(message, ticketAt);
        }

        List<String> protocols = _options.ApplicationProtocols;
        if (protocols.Count > 0u)
        {
            nuint at = BeginTlsExtension(
                message, TlsExtensionType.ApplicationLayerProtocolNegotiation);
            nuint listAt = message.BeginVector(2u);
            for (nuint i = 0u; i < protocols.Count; i++)
            {
                byte[] name = ConvertTlsTextToBytes(protocols[i]);
                if (name.Length == 0u || name.Length > 255u)
                    return Fail(TlsError.InternalError);
                nuint nameAt = message.BeginVector(1u);
                message.WriteBytes(name);
                message.EndVector(nameAt, 1u);
            }
            message.EndVector(listAt, 2u);
            EndTlsExtension(message, at);
        }

        // psk_dhe_ke, so that a server sends tickets for a later resumption.
        if (_offersTls13)
        {
            nuint modesAt = BeginTlsExtension(message, TlsExtensionType.PskKeyExchangeModes);
            message.WriteByte(1u);
            message.WriteByte(1u);
            EndTlsExtension(message, modesAt);
        }

        if (_retried && _offered._hasCookie)
        {
            nuint at = BeginTlsExtension(message, TlsExtensionType.Cookie);
            nuint cookieAt = message.BeginVector(2u);
            message.WriteBytes(_offered._cookie);
            message.EndVector(cookieAt, 2u);
            EndTlsExtension(message, at);
        }

        message.EndVector(extensionsAt, 2u);
        EndTlsHandshakeMessage(message, body);
        // A cookie is the server's to size, and one too long to echo beside
        // the rest is its fault; anything else too long is the options'.
        if (message.HasOverflowed)
        {
            return Fail(_retried && _offered._hasCookie ? TlsError.IllegalParameter
                                                        : TlsError.InternalError);
        }
        return Ok(message.ToArray());
    }

    // ------------------------------------------------------------ ServerHello

    private TlsError ReadTlsServerHello()
    {
        var read = _connection.ReadTlsHandshakeMessage();
        if (!read.Ok)
            return read.Error;
        byte[] message = read.Value;
        if ((TlsHandshakeType)message[0u] != TlsHandshakeType.ServerHello)
            return TlsError.UnexpectedMessage;
        if (!HasTlsSupportedVersionsExtension(message))
            return ReadTls12ServerHello(message);
        _connection._skipsHelloRequest = false;

        var reader = new TlsReader(message, 4u, message.Length - 4u);
        uint legacyVersion = reader.ReadUInt16();
        ReadOnlySpan<byte> random = reader.ReadSpan(32u);
        byte[] sessionId = reader.ReadVectorArray(1u, 0u, 32u);
        uint suite = reader.ReadUInt16();
        uint compression = reader.ReadByte();

        // A TLS 1.2 ServerHello MAY end here, with no extensions at all.
        TlsReader extensions = reader.IsAtEnd
            ? new TlsReader(message, message.Length, 0u)
            : reader.ReadVector(2u, 0u, 65535u);
        if (reader.Failed || !reader.IsAtEnd)
            return TlsError.Decode;

        bool isRetry = AreTlsBytesEqual(random, CreateTlsHelloRetryRequestRandom());

        // Read the extensions first: whether this is TLS 1.3 at all is in
        // them.
        uint selectedVersion = 0u;
        bool hasVersion = false;
        uint shareGroup = 0u;
        byte[] shareKey = new byte[0u];
        bool hasShare = false;
        byte[] cookie = new byte[0u];
        bool hasCookie = false;
        var seen = new TlsCodePointSet();
        while (!extensions.IsAtEnd)
        {
            uint type = extensions.ReadUInt16();
            TlsReader data = extensions.ReadVector(2u, 0u, 65535u);
            if (extensions.Failed)
                return TlsError.Decode;
            if (!seen.Add(type))
                return TlsError.IllegalParameter;
            if (!_offered._extensionTypes.Contains(type) && type != (uint)TlsExtensionType.Cookie)
                return TlsError.UnsupportedExtension;

            switch ((TlsExtensionType)(ushort)type)
            {
                case TlsExtensionType.SupportedVersions:
                    selectedVersion = data.ReadUInt16();
                    hasVersion = true;
                    break;
                case TlsExtensionType.KeyShare:
                    shareGroup = data.ReadUInt16();
                    if (!isRetry)
                        shareKey = data.ReadVectorArray(2u, 1u, 65535u);
                    hasShare = true;
                    break;
                case TlsExtensionType.Cookie:
                    if (!isRetry)
                        return TlsError.UnsupportedExtension;
                    cookie = data.ReadVectorArray(2u, 1u, 65535u);
                    hasCookie = true;
                    break;
                case TlsExtensionType.PreSharedKey:
                    return TlsError.IllegalParameter;
                default:
                    return TlsError.IllegalParameter;
            }
            if (data.Failed || !data.IsAtEnd)
                return TlsError.Decode;
        }

        if (!hasVersion)
            return TlsError.InternalError;
        if (selectedVersion != TlsVersion13 || legacyVersion != TlsLegacyVersion)
            return TlsError.IllegalParameter;
        if (!AreTlsBytesEqual(sessionId, _offered._sessionId))
            return TlsError.IllegalParameter;
        if (!_offered._cipherSuites.Contains(suite) || compression != 0u ||
            !IsTls13CipherSuite((TlsCipherSuite)(ushort)suite))
        {
            return TlsError.IllegalParameter;
        }
        if (_retried && suite != _retrySuite)
            return TlsError.IllegalParameter;

        var cipherSuite = (TlsCipherSuite)(ushort)suite;
        if (isRetry)
        {
            // A retry that asks for no share and sends no cookie would not
            // change the ClientHello (RFC 8446 section 4.1.4).
            if (!hasShare && !hasCookie)
                return TlsError.IllegalParameter;
            return RetryTlsClientHello(
                message, cipherSuite, hasShare, shareGroup, hasCookie, cookie);
        }
        if (!hasShare)
            return TlsError.MissingExtension;

        TlsKeyShare? mine = null;
        for (nuint i = 0u; i < _shares.Count; i++)
        {
            if ((uint)_shares[i].Group == shareGroup)
                mine = _shares[i];
        }
        if (mine == null)
            return TlsError.IllegalParameter;
        var shared = mine.DeriveTlsSharedSecret(shareKey);
        if (!shared.Ok)
            return shared.Error;

        // A retry made the schedule already, to hash the first ClientHello.
        TlsKeySchedule schedule;
        var existing = _schedule;
        if (existing != null)
        {
            schedule = existing;
        }
        else
        {
            schedule = new TlsKeySchedule(GetTlsSuiteHash(cipherSuite));
            _schedule = schedule;
        }
        _transcript.AddTlsMessage(message);
        schedule.DeriveHandshakeSecrets(
            shared.Value, _transcript.ComputeTlsTranscriptHash(schedule));
        CryptographicOperations.ZeroMemory(shared.Value);
        for (nuint i = 0u; i < _shares.Count; i++)
            _shares[i].WipeTlsPrivateKey();

        _connection._cipherSuite = cipherSuite;
        _connection._group = mine.Group;
        _connection._schedule = schedule;

        TlsError boundary = _connection.RequireTlsRecordBoundary();
        if (boundary != TlsError.None)
            return boundary;
        var reading = schedule.CreateTlsRecordCipher(
            cipherSuite, schedule._serverHandshakeTrafficSecret);
        if (!reading.Ok)
            return reading.Error;
        _connection._records.InstallTlsReadCipher(reading.Value);

        // From here an alert this end sends is protected, as the server
        // reads it; the compatibility change_cipher_spec is never protected.
        var writing = schedule.CreateTlsRecordCipher(
            cipherSuite, schedule._clientHandshakeTrafficSecret);
        if (!writing.Ok)
            return writing.Error;
        _connection.InstallTlsWriteCipher(writing.Value);
        return TlsError.None;
    }

    /// A ServerHello that chose TLS 1.2 or older. A client that offered TLS
    /// 1.3 first looks for the downgrade sentinel (RFC 8446 §4.1.3), which is
    /// the only defence against a machine in the middle that stripped TLS
    /// 1.3 from the ClientHello.
    private TlsError ReadTls12ServerHello(byte[] message)
    {
        if (message.Length >= 4u + 2u + 32u && _offersTls13)
        {
            ReadOnlySpan<byte> random = message[6u:][:32u];
            if (AreTlsBytesEqual(random[24u:][:7u], CreateTlsDowngradeSentinel()))
                return TlsError.IllegalParameter;
        }
        if (!_offersTls12 || _retried)
            return TlsError.ProtocolVersion;

        var legacy = new Tls12ClientHandshake(_connection, _options, _transcript, _offered);
        _tls12 = legacy;
        return legacy.ReadTls12ServerHello(message);
    }

    /// Answers a HelloRetryRequest with a second ClientHello: one share, in
    /// the group asked for, or the same shares when none was asked for; and
    /// the cookie echoed (RFC 8446 section 4.1.4).
    private TlsError RetryTlsClientHello(byte[] retry, TlsCipherSuite suite, bool hasShare,
                                         uint group, bool hasCookie, byte[] cookie)
    {
        if (_retried)
            return TlsError.UnexpectedMessage;
        _retried = true;
        _retrySuite = (uint)suite;

        var wanted = (TlsNamedGroup)(ushort)group;
        if (hasShare)
        {
            if (!_offered._supportedGroups.Contains(group) || !IsImplementedTlsGroup(wanted))
                return TlsError.IllegalParameter;
            for (nuint i = 0u; i < _shares.Count; i++)
            {
                if (_shares[i].Group == wanted)
                    return TlsError.IllegalParameter;
            }
        }
        if (_options._fixedClientHello.Length > 0u)
            return TlsError.InternalError;

        var schedule = new TlsKeySchedule(GetTlsSuiteHash(suite));
        _schedule = schedule;
        _transcript.ReplaceWithTlsMessageHash(schedule);
        _transcript.AddTlsMessage(retry);

        if (hasShare)
        {
            var share = TlsKeyShare.GenerateTlsKeyShare(wanted);
            if (!share.Ok)
                return share.Error;
            for (nuint i = 0u; i < _shares.Count; i++)
                _shares[i].WipeTlsPrivateKey();
            _shares.Clear();
            _shares.Add(share.Value);
        }
        _offered._hasCookie = hasCookie;
        _offered._cookie = cookie;
        if (hasCookie)
            _offered._extensionTypes.Add((uint)TlsExtensionType.Cookie);

        var built = BuildTlsClientHello();
        if (!built.Ok)
            return built.Error;
        _clientHello = built.Value;
        _transcript.AddTlsMessage(_clientHello);

        TlsError compatible = SendTlsCompatibilityChangeCipherSpec();
        if (compatible != TlsError.None)
            return compatible;
        _connection.QueueTlsHandshakeMessage(_clientHello);
        TlsError sent = _connection.FlushTlsHandshake();
        if (sent != TlsError.None)
            return sent;
        return ReadTlsServerHello();
    }

    private TlsError SendTlsCompatibilityChangeCipherSpec()
    {
        if (_changeCipherSpecSent || _offered._sessionId.Length == 0u)
            return TlsError.None;
        _changeCipherSpecSent = true;
        return _connection.WriteTlsChangeCipherSpec();
    }

    // ---------------------------------------------------- EncryptedExtensions

    private TlsError ReadTlsEncryptedExtensions()
    {
        var read = _connection.ReadTlsHandshakeMessage();
        if (!read.Ok)
            return read.Error;
        byte[] message = read.Value;
        if ((TlsHandshakeType)message[0u] != TlsHandshakeType.EncryptedExtensions)
            return TlsError.UnexpectedMessage;
        _transcript.AddTlsMessage(message);

        var reader = new TlsReader(message, 4u, message.Length - 4u);
        TlsReader extensions = reader.ReadVector(2u, 0u, 65535u);
        if (reader.Failed || !reader.IsAtEnd)
            return TlsError.Decode;

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
                    if (!data.IsAtEnd)
                        return TlsError.Decode;
                    break;

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

                case TlsExtensionType.SupportedGroups:
                case TlsExtensionType.MaxFragmentLength:
                case TlsExtensionType.UseSrtp:
                case TlsExtensionType.Heartbeat:
                case TlsExtensionType.ClientCertificateType:
                case TlsExtensionType.ServerCertificateType:
                case TlsExtensionType.EarlyData:
                    break;

                // TLS 1.2's, which a ServerHello choosing it carries and
                // EncryptedExtensions never does.
                case TlsExtensionType.EcPointFormats:
                case TlsExtensionType.ExtendedMasterSecret:
                case TlsExtensionType.RenegotiationInfo:
                case TlsExtensionType.SessionTicket:
                case TlsExtensionType.StatusRequest:
                case TlsExtensionType.SignatureAlgorithms:
                case TlsExtensionType.SignedCertificateTimestamp:
                case TlsExtensionType.Padding:
                case TlsExtensionType.KeyShare:
                case TlsExtensionType.PreSharedKey:
                case TlsExtensionType.PskKeyExchangeModes:
                case TlsExtensionType.Cookie:
                case TlsExtensionType.SupportedVersions:
                case TlsExtensionType.CertificateAuthorities:
                case TlsExtensionType.OidFilters:
                case TlsExtensionType.PostHandshakeAuth:
                case TlsExtensionType.SignatureAlgorithmsCert:
                    return TlsError.IllegalParameter;
            }
        }
        return TlsError.None;
    }

    // --------------------------------------------- the server authenticates

    private TlsError ReadTlsServerAuthentication()
    {
        var read = _connection.ReadTlsHandshakeMessage();
        if (!read.Ok)
            return read.Error;
        byte[] message = read.Value;

        if ((TlsHandshakeType)message[0u] == TlsHandshakeType.CertificateRequest)
        {
            TlsError requested = ReadTlsCertificateRequest(message);
            if (requested != TlsError.None)
                return requested;
            read = _connection.ReadTlsHandshakeMessage();
            if (!read.Ok)
                return read.Error;
            message = read.Value;
        }

        if ((TlsHandshakeType)message[0u] != TlsHandshakeType.Certificate)
            return TlsError.UnexpectedMessage;
        var chain = ReadTlsCertificateMessage(message, _offered, false, new byte[0u]);
        if (!chain.Ok)
            return chain.Error;
        _transcript.AddTlsMessage(message);

        TlsError verdict = _options.CertificateValidator(chain.Value, _connection._targetHost);
        if (verdict != TlsError.None)
            return verdict;
        var key = TlsPeerKey.ReadTlsPeerKey(chain.Value[0u]);
        if (!key.Ok)
            return key.Error;
        _serverKey = key.Value;
        _connection._remoteChain = chain.Value;

        var schedule = _schedule;
        if (schedule == null)
            return TlsError.InternalError;

        read = _connection.ReadTlsHandshakeMessage();
        if (!read.Ok)
            return read.Error;
        message = read.Value;
        if ((TlsHandshakeType)message[0u] != TlsHandshakeType.CertificateVerify)
            return TlsError.UnexpectedMessage;
        var scheme = VerifyTlsCertificateVerify(
            message, key.Value, _transcript.ComputeTlsTranscriptHash(schedule), true,
            CreateDefaultTlsSignatureSchemes());
        if (!scheme.Ok)
            return scheme.Error;
        _connection._signatureScheme = scheme.Value;
        _transcript.AddTlsMessage(message);

        read = _connection.ReadTlsHandshakeMessage();
        if (!read.Ok)
            return read.Error;
        message = read.Value;
        if ((TlsHandshakeType)message[0u] != TlsHandshakeType.Finished)
            return TlsError.UnexpectedMessage;
        byte[] expected = schedule.ComputeTlsFinished(
            schedule._serverHandshakeTrafficSecret, _transcript.ComputeTlsTranscriptHash(schedule));
        TlsError finished = VerifyTlsFinished(message, expected);
        if (finished != TlsError.None)
            return finished;
        _transcript.AddTlsMessage(message);

        TlsError boundary = _connection.RequireTlsRecordBoundary();
        if (boundary != TlsError.None)
            return boundary;
        schedule.DeriveApplicationSecrets(_transcript.ComputeTlsTranscriptHash(schedule));
        var reading = schedule.CreateTlsRecordCipher(_connection._cipherSuite,
                                                     schedule._serverApplicationTrafficSecret);
        if (!reading.Ok)
            return reading.Error;
        _connection._records.InstallTlsReadCipher(reading.Value);
        _connection._records._changeCipherSpecAllowed = false;
        _connection._readTrafficSecret = schedule._serverApplicationTrafficSecret;
        return TlsError.None;
    }

    private TlsError ReadTlsCertificateRequest(byte[] message)
    {
        var reader = new TlsReader(message, 4u, message.Length - 4u);
        _certificateRequestContext = reader.ReadVectorArray(1u, 0u, 255u);
        TlsReader extensions = reader.ReadVector(2u, 2u, 65535u);
        if (reader.Failed || !reader.IsAtEnd)
            return TlsError.Decode;
        if (_certificateRequestContext.Length != 0u)
            return TlsError.IllegalParameter;

        bool hasSchemes = false;
        var seen = new TlsCodePointSet();
        while (!extensions.IsAtEnd)
        {
            uint type = extensions.ReadUInt16();
            TlsReader data = extensions.ReadVector(2u, 0u, 65535u);
            if (extensions.Failed)
                return TlsError.Decode;
            if (!seen.Add(type))
                return TlsError.IllegalParameter;
            if (type == (uint)TlsExtensionType.SignatureAlgorithms)
            {
                hasSchemes = true;
                TlsError schemes = ReadTlsSignatureSchemes(data, _requestedSchemes);
                if (schemes != TlsError.None)
                    return schemes;
            }
        }
        if (!hasSchemes)
            return TlsError.MissingExtension;

        _certificateRequested = true;
        _transcript.AddTlsMessage(message);
        return TlsError.None;
    }

    // ------------------------------------------------------- client Finished

    private TlsError SendTlsClientFinished()
    {
        var schedule = _schedule;
        if (schedule == null)
            return TlsError.InternalError;

        TlsError compatible = SendTlsCompatibilityChangeCipherSpec();
        if (compatible != TlsError.None)
            return compatible;

        if (_certificateRequested)
        {
            TlsError authenticated = QueueTlsClientCertificate(schedule);
            if (authenticated != TlsError.None)
                return authenticated;
        }

        byte[] verifyData = schedule.ComputeTlsFinished(
            schedule._clientHandshakeTrafficSecret, _transcript.ComputeTlsTranscriptHash(schedule));
        byte[] finished = BuildTlsFinished(verifyData);
        _transcript.AddTlsMessage(finished);
        _connection.QueueTlsHandshakeMessage(finished);
        TlsError sent = _connection.FlushTlsHandshake();
        if (sent != TlsError.None)
            return sent;

        var application = schedule.CreateTlsRecordCipher(_connection._cipherSuite,
                                                         schedule._clientApplicationTrafficSecret);
        if (!application.Ok)
            return application.Error;
        _connection.InstallTlsWriteCipher(application.Value);
        _connection._writeTrafficSecret = schedule._clientApplicationTrafficSecret;
        schedule.DeriveResumptionSecret(_transcript.ComputeTlsTranscriptHash(schedule));
        schedule.WipeTlsHandshakeSecrets();
        _connection._records._plaintextAlertAllowed = false;
        _connection._handshakeComplete = true;
        return TlsError.None;
    }

    /// The client's Certificate and CertificateVerify, or an empty
    /// Certificate when it has none the server would accept.
    private TlsError QueueTlsClientCertificate(TlsKeySchedule schedule)
    {
        var key = _options.ClientPrivateKey;
        List<byte[]> chain = _options.ClientCertificateChain;
        Optional<TlsSignatureScheme> scheme = None;
        if (key != null && chain.Count > 0u)
            scheme = key.SelectTlsScheme(_requestedSchemes);

        var sending = new List<byte[]>();
        if (scheme.Some)
            sending = chain;
        byte[] certificate = BuildTlsCertificateMessage(_certificateRequestContext, sending);
        _transcript.AddTlsMessage(certificate);
        _connection.QueueTlsHandshakeMessage(certificate);
        if (!scheme.Some || key == null)
            return TlsError.None;

        byte[] content = BuildTlsSignedContent(
            false, _transcript.ComputeTlsTranscriptHash(schedule));
        var signature = key.SignTlsContent(scheme.Value, content);
        if (!signature.Ok)
            return signature.Error;
        byte[] verify = BuildTlsCertificateVerify(scheme.Value, signature.Value);
        _transcript.AddTlsMessage(verify);
        _connection.QueueTlsHandshakeMessage(verify);
        _connection._mutuallyAuthenticated = true;
        return TlsError.None;
    }
}

// ------------------------------------------------ messages both sides share

/// Whether `suites` holds one of TLS 1.3's suites, or else one of TLS 1.2's.
internal bool HasTlsSuiteForVersion(List<TlsCipherSuite> suites, bool tls13)
{
    for (nuint i = 0u; i < suites.Count; i++)
    {
        if (tls13 ? IsTls13CipherSuite(suites[i]) : IsTls12CipherSuite(suites[i]))
            return true;
    }
    return false;
}

/// Whether a hello message holds supported_versions, which is what makes a
/// ServerHello TLS 1.3's. A message too short to say answers false, and is
/// refused by the reader it then goes to.
internal bool HasTlsSupportedVersionsExtension(byte[] message)
{
    var reader = new TlsReader(message, 4u, message.Length - 4u);
    reader.ReadUInt16();
    reader.ReadSpan(32u);
    reader.ReadVector(1u, 0u, 32u);
    reader.ReadUInt16();
    reader.ReadByte();
    if (reader.Failed || reader.IsAtEnd)
        return false;
    TlsReader extensions = reader.ReadVector(2u, 0u, 65535u);
    while (!extensions.IsAtEnd && !extensions.Failed)
    {
        uint type = extensions.ReadUInt16();
        extensions.ReadVector(2u, 0u, 65535u);
        if (!extensions.Failed && type == (uint)TlsExtensionType.SupportedVersions)
            return true;
    }
    return false;
}

/// Reads a Certificate message into its chain of DER certificates.
///
/// `offered` is what the reader sent in its own hello, for the rule that an
/// entry's extensions MUST answer ones it offered. An empty chain is allowed
/// only when `mayBeEmpty`, which is a client answering a CertificateRequest.
internal Result<List<byte[]>, TlsError> ReadTlsCertificateMessage(
    byte[] message, TlsClientHello offered, bool mayBeEmpty, byte[] context)
{
    var reader = new TlsReader(message, 4u, message.Length - 4u);
    byte[] receivedContext = reader.ReadVectorArray(1u, 0u, 255u);
    TlsReader list = reader.ReadVector(3u, 0u, 16777215u);
    if (reader.Failed || !reader.IsAtEnd)
        return Fail(TlsError.Decode);
    if (!AreTlsBytesEqual(receivedContext, context))
        return Fail(TlsError.IllegalParameter);

    var chain = new List<byte[]>();
    while (!list.IsAtEnd)
    {
        byte[] certificate = list.ReadVectorArray(3u, 1u, 16777215u);
        TlsReader extensions = list.ReadVector(2u, 0u, 65535u);
        if (list.Failed)
            return Fail(TlsError.Decode);
        while (!extensions.IsAtEnd)
        {
            uint type = extensions.ReadUInt16();
            extensions.ReadVector(2u, 0u, 65535u);
            if (extensions.Failed)
                return Fail(TlsError.Decode);
            if (!offered._extensionTypes.Contains(type))
                return Fail(TlsError.UnsupportedExtension);
        }
        chain.Add(certificate);
    }

    if (chain.Count == 0u && !mayBeEmpty)
        return Fail(TlsError.Decode);
    return Ok(chain);
}

internal byte[] BuildTlsCertificateMessage(byte[] context, List<byte[]> chain)
{
    var message = new TlsBuffer(4096u);
    nuint body = BeginTlsHandshakeMessage(message, TlsHandshakeType.Certificate);
    nuint contextAt = message.BeginVector(1u);
    message.WriteBytes(context);
    message.EndVector(contextAt, 1u);
    nuint listAt = message.BeginVector(3u);
    for (nuint i = 0u; i < chain.Count; i++)
    {
        nuint entryAt = message.BeginVector(3u);
        message.WriteBytes(chain[i]);
        message.EndVector(entryAt, 3u);
        message.WriteUInt16(0u);
    }
    message.EndVector(listAt, 3u);
    EndTlsHandshakeMessage(message, body);
    return message.ToArray();
}

/// Checks a CertificateVerify against `key` and the transcript hash through
/// the Certificate, and answers the scheme it used.
internal Result<TlsSignatureScheme, TlsError> VerifyTlsCertificateVerify(
    byte[] message, TlsPeerKey key, byte[] transcriptHash, bool signedByServer,
    List<TlsSignatureScheme> offered)
{
    var reader = new TlsReader(message, 4u, message.Length - 4u);
    var scheme = (TlsSignatureScheme)(ushort)reader.ReadUInt16();
    byte[] signature = reader.ReadVectorArray(2u, 0u, 65535u);
    if (reader.Failed || !reader.IsAtEnd)
        return Fail(TlsError.Decode);

    if (!offered.Contains(scheme) || !IsTlsSchemeForKey(scheme, key.Kind))
        return Fail(TlsError.IllegalParameter);
    byte[] content = BuildTlsSignedContent(signedByServer, transcriptHash);
    if (!key.VerifyTlsSignature(scheme, content, signature))
        return Fail(TlsError.DecryptError);
    return Ok(scheme);
}

internal byte[] BuildTlsCertificateVerify(TlsSignatureScheme scheme, byte[] signature)
{
    var message = new TlsBuffer(signature.Length + 16u);
    nuint body = BeginTlsHandshakeMessage(message, TlsHandshakeType.CertificateVerify);
    message.WriteUInt16((uint)scheme);
    nuint signatureAt = message.BeginVector(2u);
    message.WriteBytes(signature);
    message.EndVector(signatureAt, 2u);
    EndTlsHandshakeMessage(message, body);
    return message.ToArray();
}

/// Compares a Finished with the expected `verify_data` in constant time.
internal TlsError VerifyTlsFinished(byte[] message, byte[] expected)
{
    if (message.Length != 4u + expected.Length)
        return TlsError.Decode;
    if (!CryptographicOperations.FixedTimeEquals(message[4u:], expected))
        return TlsError.DecryptError;
    return TlsError.None;
}

internal byte[] BuildTlsFinished(byte[] verifyData)
{
    var message = new TlsBuffer(verifyData.Length + 4u);
    nuint body = BeginTlsHandshakeMessage(message, TlsHandshakeType.Finished);
    message.WriteBytes(verifyData);
    EndTlsHandshakeMessage(message, body);
    return message.ToArray();
}
