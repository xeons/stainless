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
    internal byte[] ExpandTlsLabel(
        ReadOnlySpan<byte> secret, String label, ReadOnlySpan<byte> context, nuint length)
    {
        var info = new TlsBuffer(64u);
        info.WriteUInt16((uint)length);
        nuint labelAt = info.BeginVector(1u);
        info.WriteBytes("tls13 "u8);
        info.WriteBytes(ConvertTlsTextToBytes(label));
        info.EndVector(labelAt, 1u);
        nuint contextAt = info.BeginVector(1u);
        info.WriteBytes(context);
        info.EndVector(contextAt, 1u);

        var expanded = Hkdf.Expand(CreateTlsHash(), secret, info.Written, length);
        if (!expanded.Ok)
            return new byte[length];
        return expanded.Value;
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

    /// The record key and IV a traffic secret yields under `suite`.
    internal Result<TlsRecordCipher, TlsError> CreateTlsRecordCipher(
        TlsCipherSuite suite, ReadOnlySpan<byte> trafficSecret)
    {
        byte[] key = ExpandTlsLabel(
            trafficSecret, "key", new byte[0u], GetTlsSuiteKeyLength(suite));
        byte[] iv = ExpandTlsLabel(trafficSecret, "iv", new byte[0u], 12u);
        return TlsRecordCipher.Create(suite, key, iv);
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
        return new Hmac(CreateTlsHash(), finishedKey).ComputeHash(transcriptHash);
    }

    /// The pre-shared key a ticket's nonce yields from the resumption
    /// master secret.
    internal byte[] DeriveTlsResumptionKey(ReadOnlySpan<byte> ticketNonce) =>
        ExpandTlsLabel(_resumptionMasterSecret, "resumption", ticketNonce, _hashLength);

    /// RFC 8446 §7.5's exporter.
    internal byte[] ExportTlsKeyingMaterial(String label, ReadOnlySpan<byte> context, nuint length)
    {
        byte[] secret = DeriveTlsSecret(_exporterMasterSecret, label, HashTlsBytes(new byte[0u]));
        return ExpandTlsLabel(secret, "exporter", HashTlsBytes(context), length);
    }
}
