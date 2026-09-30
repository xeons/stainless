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

/// One ephemeral key for the key exchange, in one group, and the agreement
/// it makes with the peer's share (RFC 8446 §4.2.8 and §7.4).
internal sealed class TlsKeyShare
{
    private TlsNamedGroup _group;
    private byte[] _x25519PrivateKey;
    private ECDiffieHellman? _ecdh;
    private byte[] _publicKey;

    private TlsKeyShare(TlsNamedGroup group, byte[] x25519PrivateKey, ECDiffieHellman? ecdh,
                        byte[] publicKey)
    {
        _group = group;
        _x25519PrivateKey = x25519PrivateKey;
        _ecdh = ecdh;
        _publicKey = publicKey;
    }

    /// A new key in `group`.
    internal static Result<TlsKeyShare, TlsError> GenerateTlsKeyShare(TlsNamedGroup group)
    {
        if (group == TlsNamedGroup.X25519)
            return CreateTlsX25519KeyShare(X25519.GeneratePrivateKey());

        ECCurve curve = group == TlsNamedGroup.Secp384r1
            ? ECCurve.NamedCurves.NistP384
            : ECCurve.NamedCurves.NistP256;
        var ecdh = ECDiffieHellman.Create(curve);
        if (!ecdh.Ok)
            return Fail(TlsError.InternalError);
        return Ok(new TlsKeyShare(group, new byte[0u], ecdh.Value, ecdh.Value.PublicKey));
    }

    /// The X25519 share of a private key chosen elsewhere: a test's fixed
    /// key, or a freshly generated one. The share keeps a copy, so that
    /// wiping it leaves `privateKey` as it was.
    internal static Result<TlsKeyShare, TlsError> CreateTlsX25519KeyShare(byte[] privateKey)
    {
        var publicKey = X25519.GetPublicKey(privateKey);
        if (!publicKey.Ok)
            return Fail(TlsError.InternalError);
        byte[] copy = privateKey[0u:].ToArray();
        return Ok(new TlsKeyShare(TlsNamedGroup.X25519, copy, null, publicKey.Value));
    }

    internal TlsNamedGroup Group => _group;

    /// What goes in the KeyShareEntry: 32 bytes for X25519, and an
    /// uncompressed point for the NIST curves.
    internal byte[] PublicKey => _publicKey;

    /// The shared secret with the peer's share.
    ///
    /// A share of the wrong length, a point off the curve and an X25519
    /// result of all zeros are each `IllegalParameter`, as RFC 8446 §4.2.8.2
    /// and §7.4.2 require.
    internal Result<byte[], TlsError> DeriveTlsSharedSecret(ReadOnlySpan<byte> peerShare)
    {
        if (!IsWellFormedTlsKeyShare(_group, peerShare))
            return Fail(TlsError.IllegalParameter);

        if (_group == TlsNamedGroup.X25519)
        {
            var shared = X25519.DeriveSharedSecret(_x25519PrivateKey, peerShare);
            if (!shared.Ok)
                return Fail(TlsError.IllegalParameter);

            byte any = 0;
            for (nuint i = 0u; i < shared.Value.Length; i++)
                any |= shared.Value[i];
            if (any == 0)
                return Fail(TlsError.IllegalParameter);
            return Ok(shared.Value);
        }

        var ecdh = _ecdh;
        if (ecdh == null)
            return Fail(TlsError.InternalError);
        var agreed = ecdh.DeriveRawSecretAgreement(peerShare);
        if (!agreed.Ok)
            return Fail(TlsError.IllegalParameter);
        return Ok(agreed.Value);
    }

    /// Overwrites the X25519 private key once the agreement is made. A NIST
    /// curve's key is inside its `ECDiffieHellman`, which offers no way to
    /// wipe it, and is dropped with the share.
    internal void WipeTlsPrivateKey()
    {
        CryptographicOperations.ZeroMemory(_x25519PrivateKey);
        _ecdh = null;
    }
}

/// Whether `share` is the length and form `group` requires. The NIST curves
/// MUST send the uncompressed form, which starts with 4.
internal bool IsWellFormedTlsKeyShare(TlsNamedGroup group, ReadOnlySpan<byte> share)
{
    switch (group)
    {
        case TlsNamedGroup.X25519:
            return share.Length == 32u;
        case TlsNamedGroup.Secp256r1:
            return share.Length == 65u && share[0u] == 4;
        case TlsNamedGroup.Secp384r1:
            return share.Length == 97u && share[0u] == 4;
    }
    return false;
}
