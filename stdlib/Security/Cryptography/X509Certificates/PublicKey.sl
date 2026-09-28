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

/// A certificate's public key: the algorithm, its parameters and the key,
/// as a `SubjectPublicKeyInfo` holds them.
///
/// ```csharp
/// PublicKey key = certificate.PublicKey;
/// ECDsa verifier = try key.GetECDsaPublicKey();
/// ```
///
/// .NET's `PublicKey`, with the algorithm a dotted identifier and a reader
/// for each kind of key this module signs with: `GetEd25519PublicKey`,
/// `GetRsaPublicKey` and the modulus and exponent, `GetECDsaPublicKey` and
/// the curve and point. Each answers `CryptoError.Unsupported` for a key of
/// another algorithm, and `CryptoError.Encoding` for one whose bytes are not
/// what that algorithm's key is.
public sealed class PublicKey
{
    private byte[] _encoded;
    private String _oid;
    private byte[] _parameters;
    private byte[] _keyValue;

    private PublicKey(byte[] encoded, String oid, byte[] parameters, byte[] keyValue)
    {
        _encoded = encoded;
        _oid = oid;
        _parameters = parameters;
        _keyValue = keyValue;
    }

    /// `id-Ed25519`, RFC 8410's.
    public static String Ed25519Oid => "1.3.101.112";

    /// `rsaEncryption`, PKCS #1's.
    public static String RsaOid => "1.2.840.113549.1.1.1";

    /// `id-RSASSA-PSS`, for a key restricted to PSS signatures.
    public static String RsaPssOid => "1.2.840.113549.1.1.10";

    /// `id-ecPublicKey`, RFC 5480's.
    public static String ECOid => "1.2.840.10045.2.1";

    // ------------------------------------------------------------ making one

    /// The key a `SubjectPublicKeyInfo` holds.
    ///
    /// @param source     the DER, perhaps with more after it
    /// @param bytesRead  how many bytes of `source` the structure took; zero on failure
    /// @failure CryptoError.Encoding  it is not a `SubjectPublicKeyInfo`
    public static Result<PublicKey, CryptoError> CreateFromSubjectPublicKeyInfo(
        ReadOnlySpan<byte> source, out nuint bytesRead)
    {
        bytesRead = 0u;
        var document = new AsnReader(source, AsnEncodingRules.Der);
        ReadOnlySpan<byte> whole = try ConvertAsnResult(document.ReadEncodedValue());
        PublicKey key = try DecodeSubjectPublicKeyInfo(whole);
        bytesRead = whole.Length;
        return Ok(key);
    }

    /// An Ed25519 key.
    ///
    /// @param publicKey  the 32 bytes RFC 8032 encodes a point as
    /// @failure CryptoError.KeyLength  `publicKey` is not 32 bytes
    public static Result<PublicKey, CryptoError> CreateFromEd25519PublicKey(
        ReadOnlySpan<byte> publicKey)
    {
        if (publicKey.Length != Ed25519.PublicKeySize)
            return Fail(CryptoError.KeyLength);
        var writer = new AsnWriter();
        writer.PushSequence();
        writer.PushSequence();
        writer.WriteObjectIdentifier(Ed25519Oid);
        writer.PopSequence();
        writer.WriteBitString(publicKey);
        writer.PopSequence();
        return DecodeSubjectPublicKeyInfo(writer.Encode());
    }

    /// `key`'s public half.
    ///
    /// @failure CryptoError.Encoding  never, in practice: the key writes its own
    public static Result<PublicKey, CryptoError> CreateFromECDsa(ECDsa key) =>
        DecodeSubjectPublicKeyInfo(key.ExportSubjectPublicKeyInfo());

    /// `key`'s public half.
    ///
    /// @failure CryptoError.Encoding  never, in practice: the key writes its own
    public static Result<PublicKey, CryptoError> CreateFromRsa(Rsa key) =>
        DecodeSubjectPublicKeyInfo(key.ExportSubjectPublicKeyInfo());

    /// Exactly one `SubjectPublicKeyInfo`.
    internal static Result<PublicKey, CryptoError> DecodeSubjectPublicKeyInfo(
        ReadOnlySpan<byte> encoded)
    {
        var document = new AsnReader(encoded, AsnEncodingRules.Der);
        AsnReader info = try ConvertAsnResult(document.ReadSequence());
        if (document.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        AsnReader algorithm = try ConvertAsnResult(info.ReadSequence());
        String oid = try ConvertAsnResult(algorithm.ReadObjectIdentifier());
        byte[] parameters = new byte[0u];
        if (algorithm.HasData)
            parameters = (try ConvertAsnResult(algorithm.ReadEncodedValue())).ToArray();
        if (algorithm.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        ReadOnlySpan<byte> key = try ConvertAsnResult(info.ReadBitString(out int unused));
        if (unused != 0 || info.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        return Ok(new PublicKey(encoded.ToArray(), oid, parameters, key.ToArray()));
    }

    // ------------------------------------------------------------ reading it

    /// The algorithm, dotted: `Ed25519Oid`, `RsaOid`, `RsaPssOid` or `ECOid`
    /// for the keys this module reads, and anything at all otherwise.
    public String Oid => _oid;

    /// The algorithm's parameters as DER, or empty when there are none.
    public byte[] EncodedParameters => _parameters;

    /// The key itself: the contents of the `BIT STRING`.
    public byte[] EncodedKeyValue => _keyValue;

    /// The whole `SubjectPublicKeyInfo`, as DER.
    public byte[] ExportSubjectPublicKeyInfo() => _encoded;

    /// Whether `other` is the same key under the same algorithm.
    public bool Equals(PublicKey other) => AreBytesEqual(_encoded, other._encoded);

    /// The 32 bytes of an Ed25519 key.
    ///
    /// @failure CryptoError.Unsupported  the key is not Ed25519
    /// @failure CryptoError.Encoding     it has parameters, which RFC 8410 forbids,
    ///                                   or is not 32 bytes
    public Result<byte[], CryptoError> GetEd25519PublicKey()
    {
        if (_oid != Ed25519Oid)
            return Fail(CryptoError.Unsupported);
        if (_parameters.Length != 0u || _keyValue.Length != Ed25519.PublicKeySize)
            return Fail(CryptoError.Encoding);
        return Ok(_keyValue);
    }

    /// The RSA key, for verifying or encrypting.
    ///
    /// @failure CryptoError.Unsupported  the key is not RSA
    /// @failure CryptoError.Encoding     it is not a PKCS #1 `RSAPublicKey`
    /// @failure CryptoError.InvalidKey   the modulus or exponent is not usable
    public Result<Rsa, CryptoError> GetRsaPublicKey()
    {
        if (_oid != RsaOid && _oid != RsaPssOid)
            return Fail(CryptoError.Unsupported);
        return Rsa.ImportRsaPublicKey(_keyValue);
    }

    /// The RSA modulus, big-endian and without a sign octet.
    ///
    /// @failure CryptoError.Unsupported  the key is not RSA
    /// @failure CryptoError.Encoding     it is not a PKCS #1 `RSAPublicKey`
    public Result<byte[], CryptoError> GetRsaModulus() => ReadRsaPublicKeyInteger(0u);

    /// The RSA public exponent, big-endian and without a sign octet.
    ///
    /// @failure CryptoError.Unsupported  the key is not RSA
    /// @failure CryptoError.Encoding     it is not a PKCS #1 `RSAPublicKey`
    public Result<byte[], CryptoError> GetRsaExponent() => ReadRsaPublicKeyInteger(1u);

    private Result<byte[], CryptoError> ReadRsaPublicKeyInteger(nuint which)
    {
        if (_oid != RsaOid && _oid != RsaPssOid)
            return Fail(CryptoError.Unsupported);

        var document = new AsnReader(_keyValue, AsnEncodingRules.Der);
        AsnReader sequence = try ConvertAsnResult(document.ReadSequence());
        ReadOnlySpan<byte> modulus = try ConvertAsnResult(sequence.ReadIntegerBytes());
        ReadOnlySpan<byte> exponent = try ConvertAsnResult(sequence.ReadIntegerBytes());
        if (sequence.VerifyEndOfData() != AsnError.None ||
            document.VerifyEndOfData() != AsnError.None)
        {
            return Fail(CryptoError.Encoding);
        }

        ReadOnlySpan<byte> number = which == 0u ? modulus : exponent;
        if ((number[0u] & 0x80) != 0)
            return Fail(CryptoError.Encoding);
        if (number.Length > 1u && number[0u] == 0x00)
            number = number[1u:];
        return Ok(number.ToArray());
    }

    /// The curve an elliptic-curve key is on.
    ///
    /// @failure CryptoError.Unsupported  the key is not an elliptic-curve key, or its
    ///                                   curve is given by explicit parameters
    /// @failure CryptoError.Encoding     the parameters are not a curve's identifier
    public Result<ECCurve, CryptoError> GetECCurve()
    {
        if (_oid != ECOid)
            return Fail(CryptoError.Unsupported);
        var reader = new AsnReader(_parameters, AsnEncodingRules.Der);
        Asn1Tag tag = try ConvertAsnResult(reader.PeekTag());
        if (tag == Asn1Tag.Sequence)
            return Fail(CryptoError.Unsupported);
        String curve = try ConvertAsnResult(reader.ReadObjectIdentifier());
        if (reader.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);
        return Ok(ECCurve.CreateFromValue(curve));
    }

    /// The point of an elliptic-curve key as SEC 1 encodes it: `04`, then
    /// `X` and `Y`, for the uncompressed form every certificate uses.
    ///
    /// @failure CryptoError.Unsupported  the key is not an elliptic-curve key
    public Result<byte[], CryptoError> GetECPoint()
    {
        if (_oid != ECOid)
            return Fail(CryptoError.Unsupported);
        return Ok(_keyValue);
    }

    /// The elliptic-curve key, for verifying.
    ///
    /// @failure CryptoError.Unsupported   the key is not on P-256 or P-384, or its
    ///                                    point is compressed
    /// @failure CryptoError.Encoding      the point is not the curve's size
    /// @failure CryptoError.InvalidPoint  the point is not on the curve
    public Result<ECDsa, CryptoError> GetECDsaPublicKey()
    {
        ECCurve curve = try GetECCurve();
        nuint size;
        switch (curve.OidValue)
        {
            case "1.2.840.10045.3.1.7":
                size = 32u;
                break;
            case "1.3.132.0.34":
                size = 48u;
                break;
            default:
                return Fail(CryptoError.Unsupported);
        }

        if (_keyValue.Length == 0u || _keyValue[0u] != 0x04)
            return Fail(CryptoError.Unsupported);
        if (_keyValue.Length != 1u + 2u * size)
            return Fail(CryptoError.Encoding);

        byte[] x = _keyValue[1u:1u + size].ToArray();
        byte[] y = _keyValue[1u + size:].ToArray();
        return ECDsa.Create(new ECParameters(curve, new ECPoint(x, y)));
    }
}
