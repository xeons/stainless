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

/// TLS 1.3, client and server, in Stainless and over any stream.
///
/// ```csharp
/// var options = new TlsClientOptions();
/// options.CertificateValidator = PinnedLeaf;
/// options.ApplicationProtocols.Add("http/1.1");
/// var tls = try TlsSocket.Connect("example.com", 443u, options);
/// tls.Write(request, 0u, request.Length);
///
/// var server = new TlsServerOptions();
/// server.CertificateChain.Add(leafDer);
/// server.PrivateKey = try TlsSigningKey.ImportFromPem(keyPem);
/// var accepted = try TlsSocket.Accept(listener, server);
/// ```
///
/// **The shape is `System.Net.Security`'s.** `TlsStream` is `SslStream`: an
/// `IStream` over another `IStream`, so it runs over a `TcpClient`, a proxy's
/// tunnel or anything else that carries bytes in order. It is made by
/// `AuthenticateAsClient` or `AuthenticateAsServer`, which return a `Result`
/// where .NET throws. `TlsSocket` owns its TCP connection as well, for the
/// common case.
///
/// **What is implemented** is RFC 8446 whole, less resumption: the three
/// AEAD suites; key exchange over X25519, P-256 and P-384, with a
/// HelloRetryRequest when the client guessed the wrong group; certificates
/// signed with Ed25519, ECDSA on P-256 or P-384, or RSA-PSS, on either side;
/// ALPN, server_name, KeyUpdate in both directions, the exporter, and the
/// middlebox compatibility mode. Session tickets are read and handed to
/// `TlsClientOptions.SessionTicketReceived`, and nothing yet offers one back.
///
/// **What is not:** TLS 1.2, which `TlsProtocolVersion.Tls12` names so that
/// options can already ask for it; resumption; a server that issues tickets;
/// and 0-RTT data, which is never coming, since it is replayable by design.
///
/// **Certificates are judged by a `TlsCertificateValidator`**, a closure the
/// options carry. The default is the platform's trust: an `X509Chain` from
/// the peer's certificates to a root in the system store, the
/// server-authentication usage, and the host name the client asked for. A
/// program that pins a certificate, or trusts a private CA, supplies its own.
/// The validator decides whom to trust; the CertificateVerify signature
/// against the leaf's key is always checked here.
///
/// **The record layer is constant time where a secret is involved.** The
/// AEADs check their tags in constant time, and the padding of a TLS 1.3
/// record is stripped by a scan over the whole record that selects by mask,
/// so how much of a record was padding does not show in how long it took.
/// Finished values are compared with `FixedTimeEquals`.
///
/// **Blocking, one reader and one writer.** A read blocks until a record of
/// application data arrives, and one thread MAY read while another writes;
/// every record written goes under one lock, because a read can write too:
/// the alert that ends a connection it found at fault. The KeyUpdate a peer
/// asks for is sent before the next application data written, as RFC 8446
/// §4.6.3 allows, so a reader that never writes never answers one.
module Standard.Net.Security;

import Standard.Collections;
import Standard.IO;
import Standard.Net;
import Standard.Text;
import Standard.Security.Cryptography;

extern "C"
{
    byte* memcpy(byte* to, byte* from, nuint count);
    byte* memmove(byte* to, byte* from, nuint count);
}

// ------------------------------------------------------------------ limits

/// The most plaintext one record carries: 2^14 bytes.
internal const nuint TlsMaxPlaintext = 16384u;

/// The most a protected record's body may be: the plaintext, the content
/// type, padding, and the AEAD's expansion, which RFC 8446 caps at 256.
internal const nuint TlsMaxCiphertext = 16640u;

internal const nuint TlsRecordHeaderSize = 5u;

internal const nuint TlsAeadTagSize = 16u;

/// The largest handshake message accepted. A certificate chain is the only
/// large one, and a chain of four 4096-bit RSA certificates is under 12 KiB.
internal const nuint TlsMaxHandshakeMessage = 262144u;

/// Records written under one key before it is replaced. RFC 8446 §5.5 puts
/// AES-GCM's limit at 2^24.5 full records; this is 2^24, for every suite.
internal const ulong TlsKeyUsageLimit = 16777216u;

/// What a TLS 1.3 message carries as `legacy_version`, and as the version in
/// a supported_versions list.
internal const uint TlsLegacyVersion = 0x0303u;

internal const uint TlsVersion13 = 0x0304u;

// ------------------------------------------------------------------ wire enums

internal enum TlsContentType : byte
{
    Invalid = 0,
    ChangeCipherSpec = 20,
    Alert = 21,
    Handshake = 22,
    ApplicationData = 23,
}

internal enum TlsHandshakeType : byte
{
    ClientHello = 1,
    ServerHello = 2,
    NewSessionTicket = 4,
    EndOfEarlyData = 5,
    EncryptedExtensions = 8,
    Certificate = 11,
    CertificateRequest = 13,
    CertificateVerify = 15,
    Finished = 20,
    KeyUpdate = 24,
    MessageHash = 254,
}

internal enum TlsExtensionType : ushort
{
    ServerName = 0,
    MaxFragmentLength = 1,
    StatusRequest = 5,
    SupportedGroups = 10,
    SignatureAlgorithms = 13,
    UseSrtp = 14,
    Heartbeat = 15,
    ApplicationLayerProtocolNegotiation = 16,
    SignedCertificateTimestamp = 18,
    ClientCertificateType = 19,
    ServerCertificateType = 20,
    Padding = 21,
    PreSharedKey = 41,
    EarlyData = 42,
    SupportedVersions = 43,
    Cookie = 44,
    PskKeyExchangeModes = 45,
    CertificateAuthorities = 47,
    OidFilters = 48,
    PostHandshakeAuth = 49,
    SignatureAlgorithmsCert = 50,
    KeyShare = 51,
}

// ------------------------------------------------------------------ errors

/// A sentence describing a TLS error, for a message a person will read.
///
/// @see TlsError
public String DescribeTlsError(TlsError error)
{
    switch (error)
    {
        case TlsError.None: return "no error";
        case TlsError.HandshakeFailed: return "the handshake failed";
        case TlsError.ProtocolVersion: return "no protocol version in common";
        case TlsError.UnexpectedMessage: return "a message arrived out of order";
        case TlsError.Decode: return "a message was malformed";
        case TlsError.BadRecordMac: return "a record failed authentication";
        case TlsError.RecordOverflow: return "a record was too long";
        case TlsError.IllegalParameter: return "a message held a forbidden value";
        case TlsError.CertificateRefused: return "the certificate was refused";
        case TlsError.UnsupportedCertificate: return "the certificate's key is unsupported";
        case TlsError.CertificateExpired: return "the certificate has expired or is not yet valid";
        case TlsError.UnknownCertificateAuthority: return "the certificate's issuer is not trusted";
        case TlsError.CertificateRequired: return "a client certificate was required";
        case TlsError.NoCommonCipherSuite: return "no cipher suite in common";
        case TlsError.NoCommonGroup: return "no key-exchange group in common";
        case TlsError.NoApplicationProtocol: return "no application protocol in common";
        case TlsError.DecryptError: return "a signature or Finished did not verify";
        case TlsError.MissingExtension: return "a required extension was missing";
        case TlsError.UnsupportedExtension: return "an extension arrived that was never offered";
        case TlsError.InternalError: return "an internal error";
        case TlsError.Closed: return "the connection is closed";
        case TlsError.AlertReceived: return "the peer sent a fatal alert";
        case TlsError.Io: return "the stream underneath failed";
    }
    return "an unknown error";
}

/// The alert that reports `error` to the peer, and whether there is one.
internal bool MapTlsErrorToAlert(TlsError error, out TlsAlertDescription alert)
{
    alert = TlsAlertDescription.InternalError;
    switch (error)
    {
        case TlsError.HandshakeFailed:
        case TlsError.NoCommonCipherSuite:
        case TlsError.NoCommonGroup:
            alert = TlsAlertDescription.HandshakeFailure;
            return true;
        case TlsError.ProtocolVersion:
            alert = TlsAlertDescription.ProtocolVersion;
            return true;
        case TlsError.UnexpectedMessage:
            alert = TlsAlertDescription.UnexpectedMessage;
            return true;
        case TlsError.Decode:
            alert = TlsAlertDescription.DecodeError;
            return true;
        case TlsError.BadRecordMac:
            alert = TlsAlertDescription.BadRecordMac;
            return true;
        case TlsError.RecordOverflow:
            alert = TlsAlertDescription.RecordOverflow;
            return true;
        case TlsError.IllegalParameter:
            alert = TlsAlertDescription.IllegalParameter;
            return true;
        case TlsError.CertificateRefused:
            alert = TlsAlertDescription.BadCertificate;
            return true;
        case TlsError.UnsupportedCertificate:
            alert = TlsAlertDescription.UnsupportedCertificate;
            return true;
        case TlsError.CertificateExpired:
            alert = TlsAlertDescription.CertificateExpired;
            return true;
        case TlsError.UnknownCertificateAuthority:
            alert = TlsAlertDescription.UnknownCa;
            return true;
        case TlsError.CertificateRequired:
            alert = TlsAlertDescription.CertificateRequired;
            return true;
        case TlsError.NoApplicationProtocol:
            alert = TlsAlertDescription.NoApplicationProtocol;
            return true;
        case TlsError.DecryptError:
            alert = TlsAlertDescription.DecryptError;
            return true;
        case TlsError.MissingExtension:
            alert = TlsAlertDescription.MissingExtension;
            return true;
        case TlsError.UnsupportedExtension:
            alert = TlsAlertDescription.UnsupportedExtension;
            return true;
        case TlsError.InternalError:
            alert = TlsAlertDescription.InternalError;
            return true;
        default:
            return false;
    }
}

// ------------------------------------------------------------------ suites

/// The suites this end implements, most preferred first. ChaCha20 leads
/// because AES runs in software here and is the slower of the two.
internal List<TlsCipherSuite> CreateDefaultTlsCipherSuites()
{
    var suites = new List<TlsCipherSuite>();
    suites.Add(TlsCipherSuite.TlsChaCha20Poly1305Sha256);
    suites.Add(TlsCipherSuite.TlsAes128GcmSha256);
    suites.Add(TlsCipherSuite.TlsAes256GcmSha384);
    return suites;
}

internal List<TlsNamedGroup> CreateDefaultTlsGroups()
{
    var groups = new List<TlsNamedGroup>();
    groups.Add(TlsNamedGroup.X25519);
    groups.Add(TlsNamedGroup.Secp256r1);
    groups.Add(TlsNamedGroup.Secp384r1);
    return groups;
}

internal bool IsImplementedTlsCipherSuite(TlsCipherSuite suite)
{
    switch (suite)
    {
        case TlsCipherSuite.TlsAes128GcmSha256:
        case TlsCipherSuite.TlsAes256GcmSha384:
        case TlsCipherSuite.TlsChaCha20Poly1305Sha256:
            return true;
    }
    return false;
}

internal bool IsImplementedTlsGroup(TlsNamedGroup group)
{
    switch (group)
    {
        case TlsNamedGroup.X25519:
        case TlsNamedGroup.Secp256r1:
        case TlsNamedGroup.Secp384r1:
            return true;
    }
    return false;
}

/// The hash of the key schedule under `suite`.
internal HashAlgorithmName GetTlsSuiteHash(TlsCipherSuite suite) =>
    suite == TlsCipherSuite.TlsAes256GcmSha384
        ? HashAlgorithmName.Sha384
        : HashAlgorithmName.Sha256;

/// How long the record key of `suite` is.
nuint GetTlsSuiteKeyLength(TlsCipherSuite suite) =>
    suite == TlsCipherSuite.TlsAes128GcmSha256 ? 16u : 32u;

/// The signature schemes this end can verify in a `CertificateVerify`, most
/// preferred first.
internal List<TlsSignatureScheme> CreateDefaultTlsSignatureSchemes()
{
    var schemes = new List<TlsSignatureScheme>();
    schemes.Add(TlsSignatureScheme.Ed25519);
    schemes.Add(TlsSignatureScheme.EcdsaSecp256r1Sha256);
    schemes.Add(TlsSignatureScheme.EcdsaSecp384r1Sha384);
    schemes.Add(TlsSignatureScheme.RsaPssRsaeSha256);
    schemes.Add(TlsSignatureScheme.RsaPssRsaeSha384);
    schemes.Add(TlsSignatureScheme.RsaPssRsaeSha512);
    schemes.Add(TlsSignatureScheme.RsaPssPssSha256);
    schemes.Add(TlsSignatureScheme.RsaPssPssSha384);
    schemes.Add(TlsSignatureScheme.RsaPssPssSha512);
    return schemes;
}

/// What a certificate's own signature may be made with: the handshake's
/// schemes, and PKCS #1 v1.5, which RFC 8446 §4.2.3 allows in certificates.
internal List<TlsSignatureScheme> CreateDefaultTlsCertificateSignatureSchemes()
{
    var schemes = CreateDefaultTlsSignatureSchemes();
    schemes.Add(TlsSignatureScheme.RsaPkcs1Sha256);
    schemes.Add(TlsSignatureScheme.RsaPkcs1Sha384);
    schemes.Add(TlsSignatureScheme.RsaPkcs1Sha512);
    return schemes;
}

// ------------------------------------------------------------------ bytes

/// SHA-256 of "HelloRetryRequest": the random of a ServerHello that is a
/// HelloRetryRequest.
internal byte[] CreateTlsHelloRetryRequestRandom() => [
    0xCF, 0x21, 0xAD, 0x74, 0xE5, 0x9A, 0x61, 0x11, 0xBE, 0x1D, 0x8C, 0x02, 0x1E, 0x65, 0xB8, 0x91,
    0xC2, 0xA2, 0x11, 0x16, 0x7A, 0xBB, 0x8C, 0x5E, 0x07, 0x9E, 0x09, 0xE2, 0xC8, 0xA8, 0x33, 0x9C,
];

/// The first seven bytes of the last eight of a ServerHello random from a
/// server that could have spoken TLS 1.3 and chose an older version.
internal byte[] CreateTlsDowngradeSentinel() => [0x44, 0x4F, 0x57, 0x4E, 0x47, 0x52, 0x44];

/// Whether two views hold the same bytes. Not constant time; for anything
/// secret use `CryptographicOperations.FixedTimeEquals`.
internal bool AreTlsBytesEqual(ReadOnlySpan<byte> left, ReadOnlySpan<byte> right)
{
    if (left.Length != right.Length)
        return false;
    for (nuint i = 0u; i < left.Length; i++)
    {
        if (left[i] != right[i])
            return false;
    }
    return true;
}

/// Whether `count` bytes from `offset` lie inside `buffer`, asked so that
/// the sum cannot wrap.
internal bool IsTlsRangeWithin(byte[] buffer, nuint offset, nuint count) =>
    offset <= buffer.Length && count <= buffer.Length - offset;

/// Whether `host` is a literal address, which RFC 6066 keeps out of
/// server_name.
internal bool IsTlsAddressLiteral(String host)
{
    var bytes = host.ToBytes();
    if (bytes.Length == 0u)
        return false;

    bool allDigitsAndDots = true;
    for (nuint i = 0u; i < bytes.Length; i++)
    {
        byte b = bytes[i];
        if (b == 0x3A)
            return true;
        if (b != 0x2E && (b < 0x30 || b > 0x39))
            allDigitsAndDots = false;
    }
    return allDigitsAndDots;
}

/// The bytes of `text`, which MUST be ASCII to go on the wire as a host name
/// or a protocol name.
internal byte[] ConvertTlsTextToBytes(String text) => text.ToBytes();

internal String ConvertTlsBytesToText(ReadOnlySpan<byte> bytes)
{
    var copy = bytes.ToArray();
    if (copy.Length == 0u)
        return "";
    return Text.FromBytes(&copy[0u], copy.Length);
}
