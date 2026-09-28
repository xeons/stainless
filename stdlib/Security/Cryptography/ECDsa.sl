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

module Standard.Security.Cryptography;

import Standard.Formats.Asn1;

/// ECDSA over P-256 or P-384: FIPS 186-5's signature, in .NET's `ECDsa`
/// shape.
///
/// ```csharp
/// var key = try ECDsa.Create(ECCurve.NamedCurves.NistP256);
/// byte[] signature = try key.SignData(message, HashAlgorithmName.Sha256);
/// bool genuine = key.VerifyData(message, signature, HashAlgorithmName.Sha256);
///
/// var verifier = try ECDsa.Create(ECCurve.NamedCurves.NistP256);
/// try verifier.ImportSubjectPublicKeyInfo(publicKeyDer);
/// ```
///
/// **Signing is deterministic**: the nonce is RFC 6979's, derived by HMAC
/// from the key and the hash, so the same key and message always give the
/// same signature and no weak random number can leak the key. Signing is
/// constant time: the scalar multiplication, the inversion and the nonce
/// derivation run the same operations and touch the same addresses whatever
/// the key and nonce are.
///
/// **Verifying is variable time**, which is safe because everything it reads
/// is public, and it never fails: a signature that is malformed, out of
/// range or simply wrong is `false`.
///
/// A key made by `Create` is checked, and so is every key imported: a public
/// point on the curve and not at infinity, a private scalar in `[1, n - 1]`
/// that gives the public point beside it.
///
/// @see ECDiffieHellman
public sealed class ECDsa
{
    private EcKey _key;

    ECDsa(EcKey key)
    {
        _key = key;
    }

    /// A new key on P-256.
    ///
    /// @failure CryptoError.NoEntropy  the platform supplied no random bytes
    public static Result<ECDsa, CryptoError> Create() => Create(ECCurve.NamedCurves.NistP256);

    /// A new key on `curve`.
    ///
    /// @param curve  P-256 or P-384
    /// @failure CryptoError.Unsupported  `curve` is another curve
    /// @failure CryptoError.NoEntropy    the platform supplied no random bytes
    public static Result<ECDsa, CryptoError> Create(ECCurve curve)
    {
        var key = EcKey.Generate(curve);
        if (!key.Ok)
            return Fail(key.Error);
        return Ok(new ECDsa(key.Value));
    }

    /// The key `parameters` describe: private when `D` is set, and public
    /// otherwise.
    ///
    /// @param parameters  the curve, the point and perhaps the scalar
    /// @failure CryptoError.Unsupported   the curve is not P-256 or P-384
    /// @failure CryptoError.InvalidPoint  the point is not on the curve
    /// @failure CryptoError.InvalidKey    the scalar is not in `[1, n - 1]` or does not
    ///                                    give the point
    public static Result<ECDsa, CryptoError> Create(ECParameters parameters)
    {
        var key = EcKey.Import(parameters);
        if (!key.Ok)
            return Fail(key.Error);
        return Ok(new ECDsa(key.Value));
    }

    /// The size of the key in bits: 256 or 384.
    public nuint KeySize => _key.KeySize;

    /// Replaces the key with the one `parameters` describe. On failure the
    /// key is unchanged.
    ///
    /// @param parameters  the curve, the point and perhaps the scalar
    /// @failure CryptoError.Unsupported   the curve is not P-256 or P-384
    /// @failure CryptoError.InvalidPoint  the point is not on the curve
    /// @failure CryptoError.InvalidKey    the scalar is not in `[1, n - 1]` or does not
    ///                                    give the point
    public Result<bool, CryptoError> ImportParameters(ECParameters parameters)
    {
        var key = EcKey.Import(parameters);
        if (!key.Ok)
            return Fail(key.Error);
        _key = key.Value;
        return Ok(true);
    }

    /// The key's numbers.
    ///
    /// @param includePrivateParameters  whether to include `D`
    /// @failure CryptoError.InvalidKey  `D` was asked for and this is a public key
    public Result<ECParameters, CryptoError> ExportParameters(bool includePrivateParameters) =>
        _key.ExportParameters(includePrivateParameters);

    // ------------------------------------------------------------------ signing

    /// The signature of a hash already computed, as `r` then `s`.
    ///
    /// The nonce's HMAC uses the hash whose length `hash` has — SHA-1,
    /// SHA-256, SHA-384 or SHA-512 — and the curve's own for any other length.
    ///
    /// @param hash  the digest of the message
    /// @failure CryptoError.InvalidKey  this is a public key
    /// @see ECDsa.VerifyHash
    public Result<byte[], CryptoError> SignHash(ReadOnlySpan<byte> hash) =>
        SignHash(hash, DsaSignatureFormat.IeeeP1363FixedFieldConcatenation);

    /// The signature of a hash already computed, in `signatureFormat`.
    ///
    /// @param hash             the digest of the message
    /// @param signatureFormat  how to lay out `r` and `s`
    /// @failure CryptoError.InvalidKey  this is a public key
    public Result<byte[], CryptoError> SignHash(ReadOnlySpan<byte> hash,
                                                DsaSignatureFormat signatureFormat)
    {
        HashAlgorithmName nonceHash;
        switch (hash.Length)
        {
            case 20u:
                nonceHash = HashAlgorithmName.Sha1;
                break;
            case 32u:
                nonceHash = HashAlgorithmName.Sha256;
                break;
            case 48u:
                nonceHash = HashAlgorithmName.Sha384;
                break;
            case 64u:
                nonceHash = HashAlgorithmName.Sha512;
                break;
            default:
                nonceHash = KeySize == 384u ? HashAlgorithmName.Sha384 : HashAlgorithmName.Sha256;
                break;
        }
        return SignHashWith(hash, nonceHash, signatureFormat);
    }

    /// The signature of `data` hashed with `hashAlgorithm`, as `r` then `s`.
    ///
    /// @param data           the message
    /// @param hashAlgorithm  the hash, which the nonce's HMAC uses too
    /// @failure CryptoError.InvalidKey   this is a public key
    /// @failure CryptoError.Unsupported  `hashAlgorithm` is the zero value
    /// @see ECDsa.VerifyData
    public Result<byte[], CryptoError> SignData(ReadOnlySpan<byte> data,
                                                HashAlgorithmName hashAlgorithm) =>
        SignData(data, hashAlgorithm, DsaSignatureFormat.IeeeP1363FixedFieldConcatenation);

    /// The signature of `data` hashed with `hashAlgorithm`, in
    /// `signatureFormat`.
    ///
    /// @param data             the message
    /// @param hashAlgorithm    the hash, which the nonce's HMAC uses too
    /// @param signatureFormat  how to lay out `r` and `s`
    /// @failure CryptoError.InvalidKey   this is a public key
    /// @failure CryptoError.Unsupported  `hashAlgorithm` is the zero value
    public Result<byte[], CryptoError> SignData(ReadOnlySpan<byte> data,
                                                HashAlgorithmName hashAlgorithm,
                                                DsaSignatureFormat signatureFormat)
    {
        var hash = hashAlgorithm.CreateHashAlgorithm();
        if (!hash.Ok)
            return Fail(hash.Error);
        hash.Value.AppendData(data);
        return SignHashWith(hash.Value.GetHashAndReset(), hashAlgorithm, signatureFormat);
    }

    Result<byte[], CryptoError> SignHashWith(ReadOnlySpan<byte> hash, HashAlgorithmName nonceHash,
                                             DsaSignatureFormat signatureFormat)
    {
        var signature = _key.SignHash(hash, nonceHash);
        if (!signature.Ok || signatureFormat == DsaSignatureFormat.IeeeP1363FixedFieldConcatenation)
            return signature;
        return Ok(EncodeDerEcSignature(signature.Value));
    }

    // -------------------------------------------------------------- verifying

    /// Whether `signature`, as `r` then `s`, signs `hash` under this key.
    ///
    /// @param hash       the digest of the message
    /// @param signature  `r` then `s`, each as wide as the order
    public bool VerifyHash(ReadOnlySpan<byte> hash, ReadOnlySpan<byte> signature) =>
        VerifyHash(hash, signature, DsaSignatureFormat.IeeeP1363FixedFieldConcatenation);

    /// Whether `signature`, laid out as `signatureFormat` says, signs `hash`
    /// under this key.
    ///
    /// @param hash             the digest of the message
    /// @param signature        the signature
    /// @param signatureFormat  how `r` and `s` are laid out
    public bool VerifyHash(ReadOnlySpan<byte> hash, ReadOnlySpan<byte> signature,
                           DsaSignatureFormat signatureFormat)
    {
        nuint size = KeySize / 8u;
        if (signatureFormat == DsaSignatureFormat.Rfc3279DerSequence)
        {
            var fixedWidth = DecodeDerEcSignature(signature, size);
            if (!fixedWidth.Some)
                return false;
            return VerifyFixedWidth(hash, fixedWidth.Value, size);
        }
        return VerifyFixedWidth(hash, signature, size);
    }

    bool VerifyFixedWidth(ReadOnlySpan<byte> hash, ReadOnlySpan<byte> signature, nuint size)
    {
        if (signature.Length != 2u * size)
            return false;
        return _key.VerifyHash(hash, signature[:size], signature[size:]);
    }

    /// Whether `signature`, as `r` then `s`, signs `data` hashed with
    /// `hashAlgorithm`.
    ///
    /// @param data           the message
    /// @param signature      `r` then `s`, each as wide as the order
    /// @param hashAlgorithm  the hash the signer used
    public bool VerifyData(ReadOnlySpan<byte> data, ReadOnlySpan<byte> signature,
                           HashAlgorithmName hashAlgorithm) =>
        VerifyData(data, signature, hashAlgorithm,
                   DsaSignatureFormat.IeeeP1363FixedFieldConcatenation);

    /// Whether `signature`, laid out as `signatureFormat` says, signs `data`
    /// hashed with `hashAlgorithm`.
    ///
    /// @param data             the message
    /// @param signature        the signature
    /// @param hashAlgorithm    the hash the signer used
    /// @param signatureFormat  how `r` and `s` are laid out
    public bool VerifyData(ReadOnlySpan<byte> data, ReadOnlySpan<byte> signature,
                           HashAlgorithmName hashAlgorithm, DsaSignatureFormat signatureFormat)
    {
        var hash = hashAlgorithm.CreateHashAlgorithm();
        if (!hash.Ok)
            return false;
        hash.Value.AppendData(data);
        return VerifyHash(hash.Value.GetHashAndReset(), signature, signatureFormat);
    }

    /// The most bytes a signature in `signatureFormat` can take: 64 or 96 for
    /// the fixed-width form, and 72 or 104 for DER.
    ///
    /// @param signatureFormat  the layout
    public nuint GetMaxSignatureSize(DsaSignatureFormat signatureFormat)
    {
        nuint size = KeySize / 8u;
        if (signatureFormat == DsaSignatureFormat.Rfc3279DerSequence)
            return 2u * size + 8u;
        return 2u * size;
    }
}

// ============================================================ the arithmetic

/// `hash` as a scalar, by SEC 1 §4.1.3: as many of its leading bits as the
/// order has, reduced once. Both curves' orders are a whole number of bytes,
/// so that is the leading bytes.
EcElement ReduceEcHashToScalar(ReadOnlySpan<byte> hash, ref EcDomain domain)
{
    nuint size = domain.Size;
    nuint take = hash.Length < size ? hash.Length : size;
    byte[] padded = new byte[size];
    for (nuint i = 0u; i < take; i++)
        padded[size - take + i] = hash[i];
    return ReduceEcElementOnce(ReadEcElement(padded), ref domain.Order);
}

/// The ECDSA signature of `hash` under `privateScalar`, as `r` then `s`.
///
/// Constant time in the key and the nonce: the only branch is on `r` or `s`
/// being zero, which are public once returned and happen with probability
/// near 2^-256.
byte[] SignEcHash(ReadOnlySpan<byte> hash, EcElement privateScalar, HashAlgorithmName nonceHash,
                  ref EcDomain domain)
{
    nuint size = domain.Size;
    EcElement digest = ReduceEcHashToScalar(hash, ref domain);
    var nonces = new EcNonceGenerator(privateScalar, digest, nonceHash, domain.Order.Value, size);

    // A plain number times one in Montgomery form is the plain product, so
    // only the key and the nonce's inverse are ever converted.
    EcElement montgomeryKey = ConvertEcElementToMontgomery(privateScalar, ref domain.Order);
    while (true)
    {
        EcElement nonce = nonces.GenerateNonce();
        EcProjectivePoint commitment = MultiplyEcPoint(domain.Generator, nonce, ref domain);
        ConvertEcPointToAffine(commitment, ref domain, out EcElement x, out EcElement y);

        // x is below p, and p is below 2n for both curves.
        EcElement r = ReduceEcElementOnce(x, ref domain.Order);
        EcElement montgomeryNonce = ConvertEcElementToMontgomery(nonce, ref domain.Order);
        EcElement inverse = InvertEcElement(montgomeryNonce, ref domain.Order);
        EcElement product = MultiplyEcElements(r, montgomeryKey, ref domain.Order);
        EcElement sum = AddEcElements(digest, product, ref domain.Order);
        EcElement s = MultiplyEcElements(sum, inverse, ref domain.Order);

        if (ComputeEcElementZeroMask(r) == 0u && ComputeEcElementZeroMask(s) == 0u)
        {
            byte[] signature = new byte[2u * size];
            WriteEcElement(r, size, signature, 0u);
            WriteEcElement(s, size, signature, size);
            return signature;
        }
    }
}

/// Whether `r` and `s`, big-endian and as wide as the order, sign `hash`
/// under `publicPoint`. Everything here is public, so it may answer early.
bool VerifyEcHashVariableTime(ReadOnlySpan<byte> hash, ReadOnlySpan<byte> rBytes,
                              ReadOnlySpan<byte> sBytes, EcProjectivePoint publicPoint,
                              ref EcDomain domain)
{
    nuint size = domain.Size;
    if (rBytes.Length != size || sBytes.Length != size)
        return false;

    EcElement r = ReadEcElement(rBytes);
    EcElement s = ReadEcElement(sBytes);
    if (!IsValidEcScalar(r, ref domain) || !IsValidEcScalar(s, ref domain))
        return false;

    EcElement digest = ReduceEcHashToScalar(hash, ref domain);
    EcElement montgomeryS = ConvertEcElementToMontgomery(s, ref domain.Order);
    EcElement inverse = InvertEcElement(montgomeryS, ref domain.Order);
    EcElement first = MultiplyEcElements(digest, inverse, ref domain.Order);
    EcElement second = MultiplyEcElements(r, inverse, ref domain.Order);

    EcProjectivePoint sum = MultiplyEcPointsVariableTime(first, second, publicPoint, ref domain);
    if (!ConvertEcPointToAffine(sum, ref domain, out EcElement x, out EcElement y))
        return false;
    return ComputeEcElementEqualMask(ReduceEcElementOnce(x, ref domain.Order), r) != 0u;
}

/// `r` then `s` as RFC 3279's `SEQUENCE { INTEGER, INTEGER }`.
byte[] EncodeDerEcSignature(ReadOnlySpan<byte> fixedWidth)
{
    nuint size = fixedWidth.Length / 2u;
    var writer = new AsnWriter();
    writer.PushSequence();
    writer.WriteIntegerUnsigned(fixedWidth[:size]);
    writer.WriteIntegerUnsigned(fixedWidth[size:]);
    writer.PopSequence();
    return writer.Encode();
}

/// RFC 3279's `SEQUENCE { INTEGER, INTEGER }` as `r` then `s`, each `size`
/// bytes, or `None` when it is not strict DER of two non-negative integers
/// that fit.
Optional<byte[]> DecodeDerEcSignature(ReadOnlySpan<byte> der, nuint size)
{
    var document = new AsnReader(der, AsnEncodingRules.Der);
    var sequence = document.ReadSequence();
    if (!sequence.Ok || document.VerifyEndOfData() != AsnError.None)
        return None;

    AsnReader pair = sequence.Value;
    byte[] fixedWidth = new byte[2u * size];
    for (nuint half = 0u; half < 2u; half++)
    {
        var integer = pair.ReadIntegerBytes();
        if (!integer.Ok)
            return None;

        ReadOnlySpan<byte> magnitude = integer.Value;
        if ((magnitude[0u] & 0x80) != 0)
            return None;
        if (magnitude.Length > 1u && magnitude[0u] == 0x00)
            magnitude = magnitude[1u:];
        if (magnitude.Length > size)
            return None;

        nuint end = (half + 1u) * size;
        for (nuint i = 0u; i < magnitude.Length; i++)
            fixedWidth[end - magnitude.Length + i] = magnitude[i];
    }

    if (pair.VerifyEndOfData() != AsnError.None)
        return None;
    return Some(fixedWidth);
}

// ------------------------------------------------------------------ RFC 6979

/// The deterministic nonces of RFC 6979 §3.2: HMAC-DRBG seeded with the
/// private key and the hash.
///
/// Every candidate runs the same HMACs whatever the key is. A candidate
/// outside `[1, n - 1]` is discarded and the next drawn, which reveals only
/// that a number nobody will use was out of range.
sealed class EcNonceGenerator
{
    private HashAlgorithmName _hash;
    private byte[] _key;
    private byte[] _value;
    private EcElement _order;
    private nuint _size;
    private bool _drawn;

    public EcNonceGenerator(EcElement privateScalar, EcElement digest, HashAlgorithmName hash,
                            EcElement order, nuint size)
    {
        _hash = hash;
        _order = order;
        _size = size;

        nuint length = hash.HashSizeInBytes;
        _key = new byte[length];
        _value = new byte[length];
        for (nuint i = 0u; i < length; i++)
            _value[i] = 0x01;

        byte[] seed = new byte[2u * size];
        WriteEcElement(privateScalar, size, seed, 0u);
        WriteEcElement(digest, size, seed, size);

        _key = ComputeMac(0x00, seed);
        _value = ComputeMac(_value);
        _key = ComputeMac(0x01, seed);
        _value = ComputeMac(_value);
        CryptographicOperations.ZeroMemory(seed);
    }

    /// The next nonce in `[1, n - 1]`.
    public EcElement GenerateNonce()
    {
        byte[] candidate = new byte[_size];
        while (true)
        {
            if (_drawn)
            {
                _key = ComputeMac(0x00, new byte[0u]);
                _value = ComputeMac(_value);
            }
            _drawn = true;

            nuint filled = 0u;
            while (filled < _size)
            {
                _value = ComputeMac(_value);
                for (nuint i = 0u; i < _value.Length && filled < _size; i++)
                {
                    candidate[filled] = _value[i];
                    filled++;
                }
            }

            EcElement nonce = ReadEcElement(candidate);
            ulong below = ComputeEcElementBelow(nonce, _order);
            ulong zero = ComputeEcElementZeroMask(nonce) & 1u;
            if ((below & (zero ^ 1u)) != 0u)
            {
                CryptographicOperations.ZeroMemory(candidate);
                return nonce;
            }
        }
    }

    /// `HMAC_K(V || separator || material)`.
    byte[] ComputeMac(byte separator, ReadOnlySpan<byte> material)
    {
        var mac = CreateMac();
        mac.AppendData(_value);
        byte[] one = [separator];
        mac.AppendData(one);
        mac.AppendData(material);
        return mac.GetHashAndReset();
    }

    /// `HMAC_K(data)`.
    byte[] ComputeMac(ReadOnlySpan<byte> data)
    {
        var mac = CreateMac();
        mac.AppendData(data);
        return mac.GetHashAndReset();
    }

    /// HMAC under `K`. The constructor's caller has already refused a hash
    /// that cannot be made, so SHA-256 is never the one used.
    Hmac CreateMac()
    {
        var hash = _hash.CreateHashAlgorithm();
        return new Hmac(hash.Ok ? hash.Value : new Sha256(), _key);
    }
}
