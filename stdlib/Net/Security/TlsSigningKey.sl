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
import Standard.Formats.Asn1;
import Standard.Security.Cryptography;

/// The private key that signs a CertificateVerify: Ed25519, ECDSA on P-256
/// or P-384, or RSA with PSS.
///
///     var key = try TlsSigningKey.ImportFromPem(File.ReadAllText("server.key"));
///     options.PrivateKey = key;
///
/// It MUST be the key of the leaf certificate it is configured beside; a
/// mismatch is found by the peer, as a signature that does not verify.
public sealed class TlsSigningKey
{
    private TlsKeyKind _kind;
    private byte[] _ed25519PrivateKey;
    private ECDsa? _ecdsa;
    private Rsa? _rsa;

    private TlsSigningKey(TlsKeyKind kind, byte[] ed25519PrivateKey, ECDsa? ecdsa, Rsa? rsa)
    {
        _kind = kind;
        _ed25519PrivateKey = ed25519PrivateKey;
        _ecdsa = ecdsa;
        _rsa = rsa;
    }

    /// An Ed25519 key from its 32-byte seed, RFC 8032's private key.
    ///
    /// @failure CryptoError.KeyLength  `privateKey` is not 32 bytes
    public static Result<TlsSigningKey, CryptoError> FromEd25519PrivateKey(ReadOnlySpan<byte> privateKey)
    {
        if (privateKey.Length != Ed25519.PrivateKeySize)
            return Fail(CryptoError.KeyLength);
        return Ok(new TlsSigningKey(TlsKeyKind.Ed25519, privateKey.ToArray(), null, null));
    }

    /// An ECDSA key, which MUST hold its private half and be on P-256 or
    /// P-384.
    ///
    /// @failure CryptoError.InvalidKey  `key` is a public key
    public static Result<TlsSigningKey, CryptoError> FromECDsa(ECDsa key)
    {
        var exported = key.ExportParameters(true);
        if (!exported.Ok)
            return Fail(CryptoError.InvalidKey);
        var kind = key.KeySize == 384u ? TlsKeyKind.EcdsaP384 : TlsKeyKind.EcdsaP256;
        return Ok(new TlsSigningKey(kind, new byte[0u], key, null));
    }

    /// An RSA key published as `rsaEncryption`, which signs with the
    /// `RsaPssRsae` schemes.
    ///
    /// @failure CryptoError.InvalidKey  `key` is a public key
    public static Result<TlsSigningKey, CryptoError> FromRsa(Rsa key)
    {
        if (!key.HasPrivateKey)
            return Fail(CryptoError.InvalidKey);
        return Ok(new TlsSigningKey(TlsKeyKind.Rsa, new byte[0u], null, key));
    }

    /// An RSA key published as `RSASSA-PSS`, which signs with the
    /// `RsaPssPss` schemes.
    ///
    /// @failure CryptoError.InvalidKey  `key` is a public key
    public static Result<TlsSigningKey, CryptoError> FromRsaPss(Rsa key)
    {
        if (!key.HasPrivateKey)
            return Fail(CryptoError.InvalidKey);
        return Ok(new TlsSigningKey(TlsKeyKind.RsaPss, new byte[0u], null, key));
    }

    /// The key in a PEM block: `PRIVATE KEY` (PKCS #8, for any of the four
    /// kinds), `EC PRIVATE KEY` or `RSA PRIVATE KEY`. The first such block is
    /// used; certificates beside it are passed over.
    ///
    /// @failure CryptoError.Encoding     no key block, or one that does not parse
    /// @failure CryptoError.Unsupported  a key of another algorithm, or an
    ///                                   encrypted one
    /// @failure CryptoError.InvalidKey   the numbers are not a consistent key
    public static Result<TlsSigningKey, CryptoError> ImportFromPem(String input)
    {
        nuint at = 0u;
        while (true)
        {
            var next = PemEncoding.Find(input, at);
            if (!next.Some)
                return Fail(CryptoError.Encoding);
            PemFields block = next.Value;
            at = block.Location.End.Value;

            switch (block.Label)
            {
                case "PRIVATE KEY":
                    return ImportPkcs8PrivateKey(block.Data);
                case "EC PRIVATE KEY":
                {
                    ECDsa ecdsa = try ECDsa.Create();
                    try ecdsa.ImportECPrivateKey(block.Data);
                    return FromECDsa(ecdsa);
                }
                case "RSA PRIVATE KEY":
                    return FromRsa(try Rsa.ImportRsaPrivateKey(block.Data));
                case "ENCRYPTED PRIVATE KEY":
                    return Fail(CryptoError.Unsupported);
            }
        }
    }

    /// The key in an unencrypted PKCS #8 `PrivateKeyInfo`, DER.
    ///
    /// @failure CryptoError.Encoding     not a `PrivateKeyInfo`
    /// @failure CryptoError.Unsupported  a key of another algorithm
    /// @failure CryptoError.InvalidKey   the numbers are not a consistent key
    public static Result<TlsSigningKey, CryptoError> ImportPkcs8PrivateKey(ReadOnlySpan<byte> source)
    {
        var document = new AsnReader(source, AsnEncodingRules.Der);
        var outer = document.ReadSequence();
        if (!outer.Ok)
            return Fail(CryptoError.Encoding);
        AsnReader info = outer.Value;
        var version = info.ReadInt64();
        if (!version.Ok)
            return Fail(CryptoError.Encoding);
        var algorithm = info.ReadSequence();
        if (!algorithm.Ok)
            return Fail(CryptoError.Encoding);
        var identifier = algorithm.Value.ReadObjectIdentifier();
        if (!identifier.Ok)
            return Fail(CryptoError.Encoding);
        var octets = info.ReadOctetString();
        if (!octets.Ok)
            return Fail(CryptoError.Encoding);

        String oid = identifier.Value;
        if (oid == s_ed25519Identifier)
        {
            // CurvePrivateKey, RFC 8410: the seed in an OCTET STRING of its own.
            var inner = new AsnReader(octets.Value, AsnEncodingRules.Der);
            var seed = inner.ReadOctetString();
            if (!seed.Ok || inner.VerifyEndOfData() != AsnError.None)
                return Fail(CryptoError.Encoding);
            return FromEd25519PrivateKey(seed.Value);
        }

        if (oid == s_ecPublicKeyIdentifier)
        {
            ECDsa ecdsa = try ECDsa.Create();
            try ecdsa.ImportPkcs8PrivateKey(source);
            return FromECDsa(ecdsa);
        }

        if (oid == s_rsaEncryptionIdentifier)
            return FromRsa(try Rsa.ImportRsaPrivateKey(octets.Value));

        if (oid == s_rsaPssIdentifier)
            return FromRsaPss(try Rsa.ImportRsaPrivateKey(octets.Value));

        return Fail(CryptoError.Unsupported);
    }

    internal TlsKeyKind Kind => _kind;

    /// The scheme this key signs with for a peer that accepts `offered`, in
    /// this key's order of preference, or none.
    internal Optional<TlsSignatureScheme> SelectTlsScheme(List<TlsSignatureScheme> offered)
    {
        var mine = CreateDefaultTlsSignatureSchemes();
        for (nuint i = 0u; i < mine.Count; i++)
        {
            TlsSignatureScheme scheme = mine[i];
            if (IsTlsSchemeForKey(scheme, _kind) && offered.Contains(scheme))
                return Some(scheme);
        }
        return None;
    }

    /// The signature of `content` under `scheme`.
    internal Result<byte[], TlsError> SignTlsContent(TlsSignatureScheme scheme, ReadOnlySpan<byte> content)
    {
        switch (_kind)
        {
            case TlsKeyKind.Ed25519:
            {
                var signed = Ed25519.Sign(_ed25519PrivateKey, content);
                if (!signed.Ok)
                    return Fail(TlsError.InternalError);
                return Ok(signed.Value);
            }

            case TlsKeyKind.EcdsaP256:
            case TlsKeyKind.EcdsaP384:
            {
                var ecdsa = _ecdsa;
                if (ecdsa == null)
                    return Fail(TlsError.InternalError);
                var signed = ecdsa.SignData(content, GetTlsSchemeHash(scheme),
                                            DsaSignatureFormat.Rfc3279DerSequence);
                if (!signed.Ok)
                    return Fail(TlsError.InternalError);
                return Ok(signed.Value);
            }

            case TlsKeyKind.Rsa:
            case TlsKeyKind.RsaPss:
            {
                var rsa = _rsa;
                if (rsa == null)
                    return Fail(TlsError.InternalError);
                var signed = rsa.SignData(content, GetTlsSchemeHash(scheme), RsaSignaturePadding.Pss);
                if (!signed.Ok)
                    return Fail(TlsError.InternalError);
                return Ok(signed.Value);
            }
        }
        return Fail(TlsError.InternalError);
    }
}
