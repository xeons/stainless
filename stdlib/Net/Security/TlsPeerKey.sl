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

internal static readonly String s_ed25519Identifier = "1.3.101.112";
internal static readonly String s_ecPublicKeyIdentifier = "1.2.840.10045.2.1";
internal static readonly String s_rsaEncryptionIdentifier = "1.2.840.113549.1.1.1";
internal static readonly String s_rsaPssIdentifier = "1.2.840.113549.1.1.10";

/// Whether a key of `kind` signs with `scheme` in a CertificateVerify.
internal bool IsTlsSchemeForKey(TlsSignatureScheme scheme, TlsKeyKind kind)
{
    switch (scheme)
    {
        case TlsSignatureScheme.Ed25519:
            return kind == TlsKeyKind.Ed25519;
        case TlsSignatureScheme.EcdsaSecp256r1Sha256:
            return kind == TlsKeyKind.EcdsaP256;
        case TlsSignatureScheme.EcdsaSecp384r1Sha384:
            return kind == TlsKeyKind.EcdsaP384;
        case TlsSignatureScheme.RsaPssRsaeSha256:
        case TlsSignatureScheme.RsaPssRsaeSha384:
        case TlsSignatureScheme.RsaPssRsaeSha512:
            return kind == TlsKeyKind.Rsa;
        case TlsSignatureScheme.RsaPssPssSha256:
        case TlsSignatureScheme.RsaPssPssSha384:
        case TlsSignatureScheme.RsaPssPssSha512:
            return kind == TlsKeyKind.RsaPss;
    }
    return false;
}

/// Whether a key of `kind` signs with `scheme` in TLS 1.2, where an ECDSA
/// scheme names only its hash and not its curve, and PKCS #1 v1.5 is allowed.
internal bool IsTls12SchemeForKey(TlsSignatureScheme scheme, TlsKeyKind kind)
{
    switch (scheme)
    {
        case TlsSignatureScheme.EcdsaSecp256r1Sha256:
        case TlsSignatureScheme.EcdsaSecp384r1Sha384:
            return kind == TlsKeyKind.EcdsaP256 || kind == TlsKeyKind.EcdsaP384;
        case TlsSignatureScheme.RsaPkcs1Sha256:
        case TlsSignatureScheme.RsaPkcs1Sha384:
        case TlsSignatureScheme.RsaPkcs1Sha512:
            return kind == TlsKeyKind.Rsa;
    }
    return IsTlsSchemeForKey(scheme, kind);
}

/// The hash `scheme` signs with. Ed25519 hashes internally, and answers
/// SHA-512 here only to have an answer.
internal HashAlgorithmName GetTlsSchemeHash(TlsSignatureScheme scheme)
{
    switch (scheme)
    {
        case TlsSignatureScheme.EcdsaSecp384r1Sha384:
        case TlsSignatureScheme.RsaPssRsaeSha384:
        case TlsSignatureScheme.RsaPssPssSha384:
        case TlsSignatureScheme.RsaPkcs1Sha384:
            return HashAlgorithmName.Sha384;
        case TlsSignatureScheme.RsaPssRsaeSha512:
        case TlsSignatureScheme.RsaPssPssSha512:
        case TlsSignatureScheme.RsaPkcs1Sha512:
        case TlsSignatureScheme.Ed25519:
            return HashAlgorithmName.Sha512;
    }
    return HashAlgorithmName.Sha256;
}

/// The RSA padding `scheme` signs with: PKCS #1 v1.5 for the `RsaPkcs1`
/// schemes, and PSS for the rest.
internal RsaSignaturePadding GetTlsSchemeRsaPadding(TlsSignatureScheme scheme)
{
    switch (scheme)
    {
        case TlsSignatureScheme.RsaPkcs1Sha256:
        case TlsSignatureScheme.RsaPkcs1Sha384:
        case TlsSignatureScheme.RsaPkcs1Sha512:
            return RsaSignaturePadding.Pkcs1;
    }
    return RsaSignaturePadding.Pss;
}

/// What a CertificateVerify signs (RFC 8446 §4.4.3): 64 spaces, a context
/// string naming the signer's role, a zero, and the transcript hash.
internal byte[] BuildTlsSignedContent(bool signedByServer, ReadOnlySpan<byte> transcriptHash)
{
    var content = new TlsBuffer(160u);
    for (nuint i = 0u; i < 64u; i++)
        content.WriteByte(0x20u);
    content.WriteBytes(signedByServer ? "TLS 1.3, server CertificateVerify"u8
                                      : "TLS 1.3, client CertificateVerify"u8);
    content.WriteByte(0u);
    content.WriteBytes(transcriptHash);
    return content.ToArray();
}

/// The public key of a peer's leaf certificate, read from its
/// `SubjectPublicKeyInfo` and used for nothing but CertificateVerify.
///
/// This reads just far enough into the certificate to find the key. Whether
/// the certificate deserves trust is the validator's question, and is asked
/// before this is.
internal sealed class TlsPeerKey
{
    private TlsKeyKind _kind;
    private byte[] _ed25519PublicKey;
    private ECDsa? _ecdsa;
    private Rsa? _rsa;

    private TlsPeerKey(TlsKeyKind kind, byte[] ed25519PublicKey, ECDsa? ecdsa, Rsa? rsa)
    {
        _kind = kind;
        _ed25519PublicKey = ed25519PublicKey;
        _ecdsa = ecdsa;
        _rsa = rsa;
    }

    internal TlsKeyKind Kind => _kind;

    /// The key in a DER certificate.
    ///
    /// @failure TlsError.CertificateRefused      the certificate does not parse
    /// @failure TlsError.UnsupportedCertificate  its key is of a type with no
    ///                                           scheme here
    internal static Result<TlsPeerKey, TlsError> ReadTlsPeerKey(ReadOnlySpan<byte> certificate)
    {
        var document = new AsnReader(certificate, AsnEncodingRules.Der);
        var outer = document.ReadSequence();
        if (!outer.Ok)
            return Fail(TlsError.CertificateRefused);
        AsnReader signed = outer.Value;
        var tbs = signed.ReadSequence();
        if (!tbs.Ok)
            return Fail(TlsError.CertificateRefused);
        AsnReader fields = tbs.Value;

        var first = fields.PeekTag();
        if (!first.Ok)
            return Fail(TlsError.CertificateRefused);
        if (first.Value == new Asn1Tag(TagClass.ContextSpecific, 0, true))
        {
            if (!fields.ReadEncodedValue().Ok)
                return Fail(TlsError.CertificateRefused);
        }

        // serialNumber, signature, issuer, validity, subject
        for (nuint i = 0u; i < 5u; i++)
        {
            if (!fields.ReadEncodedValue().Ok)
                return Fail(TlsError.CertificateRefused);
        }

        var info = fields.ReadEncodedValue();
        if (!info.Ok)
            return Fail(TlsError.CertificateRefused);
        return ReadTlsSubjectPublicKeyInfo(info.Value);
    }

    /// The key in a DER `SubjectPublicKeyInfo`.
    internal static Result<TlsPeerKey, TlsError> ReadTlsSubjectPublicKeyInfo(
        ReadOnlySpan<byte> info)
    {
        var document = new AsnReader(info, AsnEncodingRules.Der);
        var outer = document.ReadSequence();
        if (!outer.Ok)
            return Fail(TlsError.CertificateRefused);
        AsnReader fields = outer.Value;
        var algorithm = fields.ReadSequence();
        if (!algorithm.Ok)
            return Fail(TlsError.CertificateRefused);
        var identifier = algorithm.Value.ReadObjectIdentifier();
        if (!identifier.Ok)
            return Fail(TlsError.CertificateRefused);
        var bits = fields.ReadBitString(out int unused);
        if (!bits.Ok || unused != 0)
            return Fail(TlsError.CertificateRefused);

        String oid = identifier.Value;
        if (oid == s_ed25519Identifier)
        {
            if (bits.Value.Length != Ed25519.PublicKeySize)
                return Fail(TlsError.CertificateRefused);
            return Ok(new TlsPeerKey(TlsKeyKind.Ed25519, bits.Value.ToArray(), null, null));
        }

        if (oid == s_ecPublicKeyIdentifier)
        {
            var created = ECDsa.Create();
            if (!created.Ok)
                return Fail(TlsError.InternalError);
            ECDsa ecdsa = created.Value;
            var imported = ecdsa.ImportSubjectPublicKeyInfo(info);
            if (!imported.Ok)
            {
                if (imported.Error == CryptoError.Unsupported)
                    return Fail(TlsError.UnsupportedCertificate);
                return Fail(TlsError.CertificateRefused);
            }
            var kind = ecdsa.KeySize == 384u ? TlsKeyKind.EcdsaP384 : TlsKeyKind.EcdsaP256;
            return Ok(new TlsPeerKey(kind, new byte[0u], ecdsa, null));
        }

        if (oid == s_rsaEncryptionIdentifier || oid == s_rsaPssIdentifier)
        {
            // An RSASSA-PSS key MAY carry parameters that narrow the hash;
            // they are not read, and the scheme's own hash is used.
            var rsa = Rsa.ImportRsaPublicKey(bits.Value);
            if (!rsa.Ok)
                return Fail(TlsError.CertificateRefused);
            if (!IsTlsRsaKeyWithinBounds(rsa.Value))
                return Fail(TlsError.UnsupportedCertificate);
            var kind = oid == s_rsaPssIdentifier ? TlsKeyKind.RsaPss : TlsKeyKind.Rsa;
            return Ok(new TlsPeerKey(kind, new byte[0u], null, rsa.Value));
        }

        return Fail(TlsError.UnsupportedCertificate);
    }

    /// Whether an RSA key is one a peer may make this end verify with: a
    /// modulus of at most `TlsMaxRsaModulusBits` and a public exponent of at
    /// most `TlsMaxRsaExponentBits`. Verifying costs the product of the two,
    /// and a peer MUST NOT be able to choose it without bound.
    private static bool IsTlsRsaKeyWithinBounds(Rsa rsa)
    {
        if (rsa.KeySize <= 0 || (nuint)rsa.KeySize > TlsMaxRsaModulusBits)
            return false;
        var parameters = rsa.ExportParameters(false);
        if (!parameters.Ok)
            return false;
        byte[] exponent = parameters.Value.Exponent;
        nuint first = 0u;
        while (first < exponent.Length && exponent[first] == 0)
            first++;
        if (first == exponent.Length)
            return false;
        nuint bits = 8u * (exponent.Length - first);
        for (uint top = (uint)exponent[first]; top < 0x80u; top <<= 1)
            bits--;
        return bits <= TlsMaxRsaExponentBits;
    }

    /// Whether `signature` is this key's, under the TLS 1.3 `scheme`, of
    /// `content`.
    internal bool VerifyTlsSignature(TlsSignatureScheme scheme, ReadOnlySpan<byte> content,
                                     ReadOnlySpan<byte> signature)
    {
        if (!IsTlsSchemeForKey(scheme, _kind))
            return false;
        return VerifyTlsSignatureUnderScheme(scheme, content, signature);
    }

    /// Whether `signature` is this key's, under the TLS 1.2 `scheme`, of
    /// `content`.
    internal bool VerifyTls12Signature(TlsSignatureScheme scheme, ReadOnlySpan<byte> content,
                                       ReadOnlySpan<byte> signature)
    {
        if (!IsTls12SchemeForKey(scheme, _kind))
            return false;
        return VerifyTlsSignatureUnderScheme(scheme, content, signature);
    }

    private bool VerifyTlsSignatureUnderScheme(
        TlsSignatureScheme scheme, ReadOnlySpan<byte> content, ReadOnlySpan<byte> signature)
    {
        switch (_kind)
        {
            case TlsKeyKind.Ed25519:
                return Ed25519.Verify(_ed25519PublicKey, content, signature);

            case TlsKeyKind.EcdsaP256:
            case TlsKeyKind.EcdsaP384:
            {
                var ecdsa = _ecdsa;
                if (ecdsa == null)
                    return false;
                return ecdsa.VerifyData(content, signature, GetTlsSchemeHash(scheme),
                                        DsaSignatureFormat.Rfc3279DerSequence);
            }

            case TlsKeyKind.Rsa:
            case TlsKeyKind.RsaPss:
            {
                var rsa = _rsa;
                if (rsa == null)
                    return false;
                return rsa.VerifyData(content, signature, GetTlsSchemeHash(scheme),
                                      GetTlsSchemeRsaPadding(scheme));
            }
        }
        return false;
    }
}
