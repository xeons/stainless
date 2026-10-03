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

module Standard.Security.Cryptography.X509Certificates;

import Standard.Formats.Asn1;
import Standard.Security.Cryptography;

/// A private key that signs certificates: .NET's `X509SignatureGenerator`.
///
/// ```csharp
/// var issuerKey = try X509SignatureGenerator.CreateForEd25519(privateKey);
/// var signer = X509SignatureGenerator.CreateForECDsa(ecdsa);
/// var rsaSigner = X509SignatureGenerator.CreateForRsa(rsa, RsaSignaturePadding.Pss);
/// ```
///
/// Ed25519 signs the certificate itself and ignores the hash it is given;
/// ECDSA signs with the hash, as `ecdsa-with-SHA256` and its siblings; RSA
/// signs with PKCS #1 v1.5 or PSS as its padding says, PSS with MGF1 over
/// the same hash and the salt length written into the parameters.
public sealed class X509SignatureGenerator
{
    private SignatureKeyKind _kind;
    private byte[] _ed25519PrivateKey;
    private ECDsa? _ecdsa;
    private Rsa? _rsa;
    private RsaSignaturePadding _padding;
    private PublicKey _publicKey;

    private X509SignatureGenerator(SignatureKeyKind kind, byte[] ed25519PrivateKey, ECDsa? ecdsa,
                                   Rsa? rsa, RsaSignaturePadding padding, PublicKey publicKey)
    {
        _kind = kind;
        _ed25519PrivateKey = ed25519PrivateKey;
        _ecdsa = ecdsa;
        _rsa = rsa;
        _padding = padding;
        _publicKey = publicKey;
    }

    /// A generator signing with the Ed25519 key `privateKey`.
    ///
    /// @param privateKey  the 32-byte seed RFC 8032 calls the private key
    /// @failure CryptoError.KeyLength  it is not 32 bytes
    public static Result<X509SignatureGenerator, CryptoError> CreateForEd25519(
        ReadOnlySpan<byte> privateKey)
    {
        byte[] publicKey = try Ed25519.GetPublicKey(privateKey);
        PublicKey key = try PublicKey.CreateFromEd25519PublicKey(publicKey);
        return Ok(new X509SignatureGenerator(SignatureKeyKind.Ed25519, privateKey.ToArray(), null,
                                             null, RsaSignaturePadding.Pkcs1, key));
    }

    /// A generator signing with `key`, which MUST hold its private half for
    /// signing to succeed.
    ///
    /// @failure CryptoError.Encoding  never, in practice: the key writes its own
    public static Result<X509SignatureGenerator, CryptoError> CreateForECDsa(ECDsa key)
    {
        PublicKey publicKey = try PublicKey.CreateFromECDsa(key);
        return Ok(new X509SignatureGenerator(SignatureKeyKind.ECDsa, new byte[0u], key, null,
                                             RsaSignaturePadding.Pkcs1, publicKey));
    }

    /// A generator signing with `key` under `padding`, which MUST hold its
    /// private half for signing to succeed.
    ///
    /// @failure CryptoError.Encoding  never, in practice: the key writes its own
    public static Result<X509SignatureGenerator, CryptoError> CreateForRsa(
        Rsa key, RsaSignaturePadding padding)
    {
        PublicKey publicKey = try PublicKey.CreateFromRsa(key);
        return Ok(new X509SignatureGenerator(SignatureKeyKind.Rsa, new byte[0u], null, key,
                                             padding, publicKey));
    }

    /// The public half, for a self-signed certificate's subject key.
    public PublicKey PublicKey => _publicKey;

    /// The `AlgorithmIdentifier` a certificate signed with `hashAlgorithm`
    /// names, as DER.
    ///
    /// @failure CryptoError.Unsupported  the hash is not SHA-256, -384 or -512 for
    ///                                   ECDSA, or SHA-1, -256, -384 or -512 for RSA
    public Result<byte[], CryptoError> GetSignatureAlgorithmIdentifier(
        HashAlgorithmName hashAlgorithm)
    {
        var writer = new AsnWriter();
        writer.PushSequence();
        switch (_kind)
        {
            case SignatureKeyKind.Ed25519:
                writer.WriteObjectIdentifier(PublicKey.Ed25519Oid);
                break;

            case SignatureKeyKind.ECDsa:
                writer.WriteObjectIdentifier(try FindECDsaAlgorithm(hashAlgorithm));
                break;

            case SignatureKeyKind.Rsa:
                if (_padding.Mode == RsaSignaturePaddingMode.Pss)
                {
                    writer.WriteObjectIdentifier(PublicKey.RsaPssOid);
                    writer.WriteEncodedValue(SignatureVerifier.EncodePssParameters(
                        hashAlgorithm, try ChoosePssSaltLength(hashAlgorithm)));
                }
                else
                {
                    writer.WriteObjectIdentifier(try FindRsaPkcs1Algorithm(hashAlgorithm));
                    writer.WriteNull();
                }
                break;
        }
        writer.PopSequence();
        return Ok(writer.Encode());
    }

    /// The signature of `data`, in the form a certificate carries it.
    ///
    /// @failure CryptoError.InvalidKey   the key has no private half
    /// @failure CryptoError.Unsupported  the hash is not one the key signs with
    public Result<byte[], CryptoError> SignData(ReadOnlySpan<byte> data,
                                                HashAlgorithmName hashAlgorithm)
    {
        switch (_kind)
        {
            case SignatureKeyKind.Ed25519:
                return Ed25519.Sign(_ed25519PrivateKey, data);

            case SignatureKeyKind.ECDsa:
            {
                try FindECDsaAlgorithm(hashAlgorithm);
                ECDsa? key = _ecdsa;
                if (key == null)
                    return Fail(CryptoError.InvalidKey);
                return key.SignData(data, hashAlgorithm, DsaSignatureFormat.Rfc3279DerSequence);
            }

            case SignatureKeyKind.Rsa:
            {
                try FindRsaPkcs1Algorithm(hashAlgorithm);
                Rsa? key = _rsa;
                if (key == null)
                    return Fail(CryptoError.InvalidKey);
                RsaSignaturePadding padding = _padding;
                if (padding.Mode == RsaSignaturePaddingMode.Pss)
                    padding = try RsaSignaturePadding.CreatePss(try ChoosePssSaltLength(hashAlgorithm));
                return key.SignData(data, hashAlgorithm, padding);
            }
        }
        return Fail(CryptoError.Unsupported);
    }

    /// The salt a PSS signature under this key uses: the padding's, with its
    /// two special lengths made concrete, since the certificate names it.
    private Result<int, CryptoError> ChoosePssSaltLength(HashAlgorithmName hashAlgorithm)
    {
        int hashLength = (int)hashAlgorithm.HashSizeInBytes;
        if (hashLength == 0)
            return Fail(CryptoError.Unsupported);
        switch (_padding.PssSaltLength)
        {
            case RsaSignaturePadding.PssSaltLengthIsHashLength:
                return Ok(hashLength);
            case RsaSignaturePadding.PssSaltLengthMax:
            {
                Rsa? key = _rsa;
                if (key == null)
                    return Fail(CryptoError.InvalidKey);
                int encodedLength = (key.KeySize - 1 + 7) / 8;
                return Ok(encodedLength - hashLength - 2);
            }
        }
        return Ok(_padding.PssSaltLength);
    }

    private static Result<String, CryptoError> FindECDsaAlgorithm(HashAlgorithmName hash)
    {
        if (hash == HashAlgorithmName.Sha256)
            return Ok("1.2.840.10045.4.3.2");
        if (hash == HashAlgorithmName.Sha384)
            return Ok("1.2.840.10045.4.3.3");
        if (hash == HashAlgorithmName.Sha512)
            return Ok("1.2.840.10045.4.3.4");
        return Fail(CryptoError.Unsupported);
    }

    private static Result<String, CryptoError> FindRsaPkcs1Algorithm(HashAlgorithmName hash)
    {
        if (hash == HashAlgorithmName.Sha1)
            return Ok("1.2.840.113549.1.1.5");
        if (hash == HashAlgorithmName.Sha256)
            return Ok("1.2.840.113549.1.1.11");
        if (hash == HashAlgorithmName.Sha384)
            return Ok("1.2.840.113549.1.1.12");
        if (hash == HashAlgorithmName.Sha512)
            return Ok("1.2.840.113549.1.1.13");
        return Fail(CryptoError.Unsupported);
    }
}
