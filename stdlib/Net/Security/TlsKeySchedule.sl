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

import Standard.Security.Cryptography;

/// The TLS 1.3 key schedule of RFC 8446 §7: HKDF over the suite's hash,
/// stepping from the early secret through the handshake secret to the master
/// secret, and the traffic secrets drawn from each.
///
/// The secrets are kept as fields so that a test can read each against the
/// values RFC 8448 publishes.
internal sealed class TlsKeySchedule
{
    private HashAlgorithmName _hash;
    private nuint _hashLength;

    internal byte[] _earlySecret;
    internal byte[] _handshakeSecret;
    internal byte[] _masterSecret;
    internal byte[] _clientHandshakeTrafficSecret;
    internal byte[] _serverHandshakeTrafficSecret;
    internal byte[] _clientApplicationTrafficSecret;
    internal byte[] _serverApplicationTrafficSecret;
    internal byte[] _exporterMasterSecret;
    internal byte[] _resumptionMasterSecret;

    internal TlsKeySchedule(HashAlgorithmName hash)
    {
        _hash = hash;
        _hashLength = hash.HashSizeInBytes;
        _earlySecret = new byte[0u];
        _handshakeSecret = new byte[0u];
        _masterSecret = new byte[0u];
        _clientHandshakeTrafficSecret = new byte[0u];
        _serverHandshakeTrafficSecret = new byte[0u];
        _clientApplicationTrafficSecret = new byte[0u];
        _serverApplicationTrafficSecret = new byte[0u];
        _exporterMasterSecret = new byte[0u];
        _resumptionMasterSecret = new byte[0u];

        // No pre-shared key: the early secret is extracted from zeros.
        _earlySecret = Hkdf.Extract(CreateTlsHash(), new byte[_hashLength], new byte[0u]);
    }

    internal HashAlgorithmName Hash => _hash;

    internal nuint HashLength => _hashLength;

    /// A fresh instance of the suite's hash. `Hmac` takes the one it is
    /// given, so every use needs its own.
    internal IHashAlgorithm CreateTlsHash()
    {
        if (_hash == HashAlgorithmName.Sha384)
            return new Sha384();
        return new Sha256();
    }

    /// The digest of `data` under the suite's hash.
    internal byte[] HashTlsBytes(ReadOnlySpan<byte> data)
    {
        var hash = CreateTlsHash();
        hash.AppendData(data);
        return hash.GetHashAndReset();
    }

    /// HKDF-Expand-Label: HKDF-Expand with the label and context laid out as
    /// an `HkdfLabel`, whose label is prefixed with "tls13 ".
    ///
    /// For the schedule's own labels and lengths, which cannot fail. A
    /// failure answers an empty array, which no cipher accepts as a key.
    internal byte[] ExpandTlsLabel(
        ReadOnlySpan<byte> secret, String label, ReadOnlySpan<byte> context, nuint length)
    {
        var expanded = TryExpandTlsLabel(secret, label, context, length);
        if (!expanded.Ok)
            return new byte[0u];
        return expanded.Value;
    }

    /// HKDF-Expand-Label for a label, context or length that MAY be out of
    /// range: a label over 249 bytes, a context over 255, or more than 255
    /// digests of output.
    ///
    /// @failure TlsError.InternalError  one of them is out of range
    internal Result<byte[], TlsError> TryExpandTlsLabel(
        ReadOnlySpan<byte> secret, String label, ReadOnlySpan<byte> context, nuint length)
    {
        if (length > 0xFFFFu)
            return Fail(TlsError.InternalError);
        var info = new TlsBuffer(64u);
        info.WriteUInt16((uint)length);
        nuint labelAt = info.BeginVector(1u);
        info.WriteBytes("tls13 "u8);
        info.WriteBytes(ConvertTlsTextToBytes(label));
        info.EndVector(labelAt, 1u);
        nuint contextAt = info.BeginVector(1u);
        info.WriteBytes(context);
        info.EndVector(contextAt, 1u);
        if (info.HasOverflowed)
            return Fail(TlsError.InternalError);

        var expanded = Hkdf.Expand(CreateTlsHash(), secret, info.Written, length);
        if (!expanded.Ok)
            return Fail(TlsError.InternalError);
        return Ok(expanded.Value);
    }

    /// Derive-Secret: the label expanded over a transcript hash, as long as
    /// the hash.
    internal byte[] DeriveTlsSecret(ReadOnlySpan<byte> secret, String label,
                                    ReadOnlySpan<byte> transcriptHash) =>
        ExpandTlsLabel(secret, label, transcriptHash, _hashLength);

    /// The handshake secret, from the (EC)DHE shared secret, and the two
    /// handshake traffic secrets over the hash through ServerHello.
    internal void DeriveHandshakeSecrets(
        ReadOnlySpan<byte> sharedSecret, ReadOnlySpan<byte> helloHash)
    {
        byte[] derived = DeriveTlsSecret(_earlySecret, "derived", HashTlsBytes(new byte[0u]));
        _handshakeSecret = Hkdf.Extract(CreateTlsHash(), sharedSecret, derived);
        CryptographicOperations.ZeroMemory(derived);
        _clientHandshakeTrafficSecret = DeriveTlsSecret(
            _handshakeSecret, "c hs traffic", helloHash);
        _serverHandshakeTrafficSecret = DeriveTlsSecret(
            _handshakeSecret, "s hs traffic", helloHash);
    }

    /// The master secret, and the application traffic and exporter secrets
    /// over the hash through the server's Finished.
    internal void DeriveApplicationSecrets(ReadOnlySpan<byte> serverFinishedHash)
    {
        byte[] derived = DeriveTlsSecret(_handshakeSecret, "derived", HashTlsBytes(new byte[0u]));
        _masterSecret = Hkdf.Extract(CreateTlsHash(), new byte[_hashLength], derived);
        CryptographicOperations.ZeroMemory(derived);
        _clientApplicationTrafficSecret = DeriveTlsSecret(
            _masterSecret, "c ap traffic", serverFinishedHash);
        _serverApplicationTrafficSecret = DeriveTlsSecret(
            _masterSecret, "s ap traffic", serverFinishedHash);
        _exporterMasterSecret = DeriveTlsSecret(_masterSecret, "exp master", serverFinishedHash);
    }

    /// The resumption master secret, over the hash through the client's
    /// Finished.
    internal void DeriveResumptionSecret(ReadOnlySpan<byte> clientFinishedHash)
    {
        _resumptionMasterSecret = DeriveTlsSecret(_masterSecret, "res master", clientFinishedHash);
    }

    /// Overwrites every secret the handshake alone needs. It MUST come after
    /// `DeriveResumptionSecret` and after both Finished messages. The exporter
    /// and resumption secrets stay, and the application traffic secrets are
    /// the connection's from here on.
    internal void WipeTlsHandshakeSecrets()
    {
        CryptographicOperations.ZeroMemory(_earlySecret);
        CryptographicOperations.ZeroMemory(_handshakeSecret);
        CryptographicOperations.ZeroMemory(_masterSecret);
        CryptographicOperations.ZeroMemory(_clientHandshakeTrafficSecret);
        CryptographicOperations.ZeroMemory(_serverHandshakeTrafficSecret);
    }

    /// Overwrites every secret, for a connection that has ended.
    internal void WipeTlsSecrets()
    {
        WipeTlsHandshakeSecrets();
        CryptographicOperations.ZeroMemory(_clientApplicationTrafficSecret);
        CryptographicOperations.ZeroMemory(_serverApplicationTrafficSecret);
        CryptographicOperations.ZeroMemory(_exporterMasterSecret);
        CryptographicOperations.ZeroMemory(_resumptionMasterSecret);
    }

    /// The record key and IV a traffic secret yields under `suite`.
    internal Result<TlsRecordCipher, TlsError> CreateTlsRecordCipher(
        TlsCipherSuite suite, ReadOnlySpan<byte> trafficSecret)
    {
        byte[] key = ExpandTlsLabel(
            trafficSecret, "key", new byte[0u], GetTlsSuiteKeyLength(suite));
        byte[] iv = ExpandTlsLabel(trafficSecret, "iv", new byte[0u], 12u);
        var cipher = TlsRecordCipher.Create(suite, key, iv);
        CryptographicOperations.ZeroMemory(key);
        return cipher;
    }

    /// The next generation of a traffic secret, for a KeyUpdate.
    internal byte[] UpdateTlsTrafficSecret(ReadOnlySpan<byte> trafficSecret) =>
        ExpandTlsLabel(trafficSecret, "traffic upd", new byte[0u], _hashLength);

    /// The `verify_data` of a Finished: an HMAC, under the key the base
    /// secret yields, of the transcript hash.
    internal byte[] ComputeTlsFinished(
        ReadOnlySpan<byte> baseSecret, ReadOnlySpan<byte> transcriptHash)
    {
        byte[] finishedKey = ExpandTlsLabel(baseSecret, "finished", new byte[0u], _hashLength);
        byte[] verifyData = new Hmac(CreateTlsHash(), finishedKey).ComputeHash(transcriptHash);
        CryptographicOperations.ZeroMemory(finishedKey);
        return verifyData;
    }

    /// The pre-shared key a ticket's nonce yields from the resumption
    /// master secret.
    internal byte[] DeriveTlsResumptionKey(ReadOnlySpan<byte> ticketNonce) =>
        ExpandTlsLabel(_resumptionMasterSecret, "resumption", ticketNonce, _hashLength);

    /// RFC 8446 section 7.5's exporter.
    ///
    /// @failure TlsError.InternalError  the label is over 249 bytes, or
    ///                                  `length` over 255 digests
    internal Result<byte[], TlsError> ExportTlsKeyingMaterial(
        String label, ReadOnlySpan<byte> context, nuint length)
    {
        var secret = TryExpandTlsLabel(
            _exporterMasterSecret, label, HashTlsBytes(new byte[0u]), _hashLength);
        if (!secret.Ok)
            return secret;
        var exported = TryExpandTlsLabel(secret.Value, "exporter", HashTlsBytes(context), length);
        CryptographicOperations.ZeroMemory(secret.Value);
        return exported;
    }
}
