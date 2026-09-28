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

/// A key on P-256 or P-384, private or public only: what `ECDsa` and
/// `ECDiffieHellman` both hold, and the formats both read and write.
///
/// Every key here has been checked. A public point is on the curve and is
/// not the point at infinity; a private scalar is in `[1, n - 1]` and the
/// public point is the one it gives.
sealed class EcKey
{
    private static readonly String s_publicKeyAlgorithm = "1.2.840.10045.2.1";

    private EcDomain _domain;
    private ECCurve _curve;
    private bool _hasPrivateKey;
    private EcElement _privateScalar;
    private EcProjectivePoint _publicPoint;
    private byte[] _publicKey;

    EcKey(ECCurve curve, EcDomain domain, EcElement x, EcElement y)
    {
        _curve = curve;
        _domain = domain;
        _publicPoint = CreateEcPointFromAffine(x, y, ref _domain);
        _publicKey = EncodeEcPoint(x, y, domain.Size);
    }

    /// The size of the key in bits: 256 or 384.
    public nuint KeySize => _domain.Size * 8u;

    /// The public point, uncompressed. The caller MUST NOT change it.
    public byte[] PublicKey => _publicKey;

    // ---------------------------------------------------------------- making

    /// A new private key on `curve`, from the platform's generator.
    ///
    /// A candidate at or above the order is drawn again rather than reduced,
    /// so every scalar is equally likely.
    public static Result<EcKey, CryptoError> Generate(ECCurve curve)
    {
        var domain = CreateEcDomainForCurve(curve);
        if (!domain.Ok)
            return Fail(domain.Error);

        EcDomain chosen = domain.Value;
        byte[] candidate = new byte[chosen.Size];
        while (true)
        {
            if (!RandomNumberGenerator.Fill(candidate))
                return Fail(CryptoError.NoEntropy);

            EcElement scalar = ReadEcElement(candidate);
            if (IsValidEcScalar(scalar, ref chosen))
            {
                CryptographicOperations.ZeroMemory(candidate);
                return Ok(CreateFromScalar(curve, chosen, scalar));
            }
        }
    }

    /// The key `parameters` describe, checked.
    public static Result<EcKey, CryptoError> Import(ECParameters parameters)
    {
        var domain = CreateEcDomainForCurve(parameters.Curve);
        if (!domain.Ok)
            return Fail(domain.Error);

        EcDomain chosen = domain.Value;
        nuint size = chosen.Size;
        bool hasPoint = parameters.Q.X.Length > 0u || parameters.Q.Y.Length > 0u;
        if (hasPoint && (parameters.Q.X.Length != size || parameters.Q.Y.Length != size))
            return Fail(CryptoError.InvalidPoint);

        byte[] encoded = new byte[0u];
        if (hasPoint)
        {
            encoded = new byte[1u + 2u * size];
            encoded[0u] = 0x04;
            parameters.Q.X[:size].CopyTo(encoded[1u:]);
            parameters.Q.Y[:size].CopyTo(encoded[1u + size:]);
        }

        if (parameters.D.Length == 0u)
        {
            if (!hasPoint)
                return Fail(CryptoError.InvalidPoint);
            return CreateFromPublic(parameters.Curve, chosen, encoded);
        }

        if (parameters.D.Length != size)
            return Fail(CryptoError.InvalidKey);
        return CreateFromPrivate(parameters.Curve, chosen, parameters.D, encoded);
    }

    /// A public key from a point in SEC 1 form, compressed or not.
    static Result<EcKey, CryptoError> CreateFromPublic(ECCurve curve, EcDomain domain,
                                                       ReadOnlySpan<byte> encoded)
    {
        var decoded = DecodeEcPointVariableTime(encoded, ref domain, out EcElement x,
                                                out EcElement y);
        if (!decoded.Ok)
            return Fail(decoded.Error);
        return Ok(new EcKey(curve, domain, x, y));
    }

    /// A private key from its scalar, big-endian and no wider than the order.
    /// `encoded`, when not empty, is the public point it MUST give.
    static Result<EcKey, CryptoError> CreateFromPrivate(ECCurve curve, EcDomain domain,
                                                        ReadOnlySpan<byte> scalar,
                                                        ReadOnlySpan<byte> encoded)
    {
        nuint size = domain.Size;
        if (scalar.Length == 0u || scalar.Length > size)
            return Fail(CryptoError.InvalidKey);

        byte[] padded = new byte[size];
        scalar.CopyTo(padded[size - scalar.Length:]);
        EcElement value = ReadEcElement(padded);
        CryptographicOperations.ZeroMemory(padded);

        if (!IsValidEcScalar(value, ref domain))
            return Fail(CryptoError.InvalidKey);

        EcKey key = CreateFromScalar(curve, domain, value);
        if (encoded.Length > 0u)
        {
            var given = DecodeEcPointVariableTime(encoded, ref domain, out EcElement x,
                                                  out EcElement y);
            if (!given.Ok)
                return Fail(given.Error);
            if (!CryptographicOperations.FixedTimeEquals(EncodeEcPoint(x, y, size),
                                                         key._publicKey))
                return Fail(CryptoError.InvalidKey);
        }
        return Ok(key);
    }

    static EcKey CreateFromScalar(ECCurve curve, EcDomain domain, EcElement scalar)
    {
        EcProjectivePoint point = MultiplyEcPoint(domain.Generator, scalar, ref domain);
        ConvertEcPointToAffine(point, ref domain, out EcElement x, out EcElement y);
        var key = new EcKey(curve, domain, x, y);
        key._privateScalar = scalar;
        key._hasPrivateKey = true;
        return key;
    }

    // ----------------------------------------------------------- arithmetic

    /// The x coordinate of `d * Q` for the other party's point `Q`: the raw
    /// Diffie-Hellman secret.
    ///
    /// @failure CryptoError.InvalidKey    this key has no private scalar, or the
    ///                                    result is the point at infinity
    /// @failure CryptoError.InvalidPoint  `otherPartyPublicKey` is not a point on
    ///                                    this key's curve
    public Result<byte[], CryptoError> DeriveSharedSecret(ReadOnlySpan<byte> otherPartyPublicKey)
    {
        if (!_hasPrivateKey)
            return Fail(CryptoError.InvalidKey);

        var decoded = DecodeEcPointVariableTime(otherPartyPublicKey, ref _domain,
                                                out EcElement otherX, out EcElement otherY);
        if (!decoded.Ok)
            return Fail(decoded.Error);

        EcProjectivePoint other = CreateEcPointFromAffine(otherX, otherY, ref _domain);
        EcProjectivePoint shared = MultiplyEcPoint(other, _privateScalar, ref _domain);
        bool finite = ConvertEcPointToAffine(shared, ref _domain, out EcElement x,
                                             out EcElement y);
        if (!finite)
            return Fail(CryptoError.InvalidKey);

        byte[] secret = new byte[_domain.Size];
        WriteEcElement(x, _domain.Size, secret, 0u);
        return Ok(secret);
    }

    /// The signature of `hash` as `r` then `s`, with the nonce RFC 6979 derives
    /// through HMAC over `nonceHash`.
    ///
    /// @failure CryptoError.InvalidKey   this key has no private scalar
    /// @failure CryptoError.Unsupported  `nonceHash` is the zero value
    public Result<byte[], CryptoError> SignHash(ReadOnlySpan<byte> hash,
                                                HashAlgorithmName nonceHash)
    {
        if (!_hasPrivateKey)
            return Fail(CryptoError.InvalidKey);
        if (nonceHash.HashSizeInBytes == 0u)
            return Fail(CryptoError.Unsupported);
        return Ok(SignEcHash(hash, _privateScalar, nonceHash, ref _domain));
    }

    /// Whether `r` and `s` sign `hash` under this key.
    public bool VerifyHash(ReadOnlySpan<byte> hash, ReadOnlySpan<byte> r, ReadOnlySpan<byte> s) =>
        VerifyEcHashVariableTime(hash, r, s, _publicPoint, ref _domain);

    // ------------------------------------------------------------ parameters

    /// The key's numbers, with `D` empty unless `includePrivate` is set.
    ///
    /// @failure CryptoError.InvalidKey  `includePrivate` is set and there is no
    ///                                  private scalar
    public Result<ECParameters, CryptoError> ExportParameters(bool includePrivate)
    {
        if (includePrivate && !_hasPrivateKey)
            return Fail(CryptoError.InvalidKey);

        nuint size = _domain.Size;
        var point = new ECPoint(_publicKey[1u:1u + size].ToArray(),
                                _publicKey[1u + size:].ToArray());
        if (!includePrivate)
            return Ok(new ECParameters(_curve, point));
        return Ok(new ECParameters(_curve, point, ExportPrivateScalar()));
    }

    byte[] ExportPrivateScalar()
    {
        byte[] scalar = new byte[_domain.Size];
        WriteEcElement(_privateScalar, _domain.Size, scalar, 0u);
        return scalar;
    }

    // --------------------------------------------------- SubjectPublicKeyInfo

    /// RFC 5480's `SubjectPublicKeyInfo`: `id-ecPublicKey`, the curve's
    /// identifier, and the point uncompressed.
    public byte[] ExportSubjectPublicKeyInfo()
    {
        var writer = new AsnWriter();
        writer.PushSequence();
        WriteAlgorithmIdentifier(writer);
        writer.WriteBitString(_publicKey);
        writer.PopSequence();
        return writer.Encode();
    }

    void WriteAlgorithmIdentifier(AsnWriter writer)
    {
        writer.PushSequence();
        writer.WriteObjectIdentifier(s_publicKeyAlgorithm);
        writer.WriteObjectIdentifier(_curve.OidValue);
        writer.PopSequence();
    }

    /// The key a `SubjectPublicKeyInfo` holds, and how many bytes it took.
    public static Result<EcKey, CryptoError> ImportSubjectPublicKeyInfo(
        ReadOnlySpan<byte> source, out nuint bytesRead)
    {
        bytesRead = 0u;
        var document = new AsnReader(source, AsnEncodingRules.Der);
        var whole = document.ReadEncodedValue();
        if (!whole.Ok)
            return Fail(CryptoError.Encoding);

        var outer = new AsnReader(whole.Value, AsnEncodingRules.Der).ReadSequence();
        if (!outer.Ok)
            return Fail(CryptoError.Encoding);
        AsnReader info = outer.Value;

        var curve = ReadAlgorithmIdentifier(info);
        if (!curve.Ok)
            return Fail(curve.Error);
        var domain = CreateEcDomainForCurve(curve.Value);
        if (!domain.Ok)
            return Fail(domain.Error);

        var point = info.ReadBitString(out int unused);
        if (!point.Ok || unused != 0 || info.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        var key = CreateFromPublic(curve.Value, domain.Value, point.Value);
        if (key.Ok)
            bytesRead = whole.Value.Length;
        return key;
    }

    /// The curve an `AlgorithmIdentifier` for `id-ecPublicKey` names.
    static Result<ECCurve, CryptoError> ReadAlgorithmIdentifier(AsnReader reader)
    {
        var sequence = reader.ReadSequence();
        if (!sequence.Ok)
            return Fail(CryptoError.Encoding);
        AsnReader algorithm = sequence.Value;

        var oid = algorithm.ReadObjectIdentifier();
        if (!oid.Ok || oid.Value != s_publicKeyAlgorithm)
            return Fail(CryptoError.Encoding);

        var curve = ReadNamedCurve(algorithm);
        if (!curve.Ok)
            return curve;
        if (algorithm.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);
        return curve;
    }

    /// RFC 5480's `ECParameters`: a named curve. Explicit parameters are valid
    /// and unsupported; anything else is not an encoding of one.
    static Result<ECCurve, CryptoError> ReadNamedCurve(AsnReader reader)
    {
        var tag = reader.PeekTag();
        if (!tag.Ok)
            return Fail(CryptoError.Encoding);
        if (tag.Value == Asn1Tag.Sequence)
            return Fail(CryptoError.Unsupported);

        var oid = reader.ReadObjectIdentifier();
        if (!oid.Ok)
            return Fail(CryptoError.Encoding);
        return Ok(ECCurve.CreateFromValue(oid.Value));
    }

    // ------------------------------------------------------------ ECPrivateKey

    /// RFC 5915's `ECPrivateKey`: version 1, the scalar, and the curve and the
    /// point in their tagged fields, as OpenSSL writes it.
    ///
    /// @failure CryptoError.InvalidKey  there is no private scalar
    public Result<byte[], CryptoError> ExportECPrivateKey()
    {
        if (!_hasPrivateKey)
            return Fail(CryptoError.InvalidKey);
        return Ok(EncodeECPrivateKey(true));
    }

    byte[] EncodeECPrivateKey(bool includeCurve)
    {
        byte[] scalar = ExportPrivateScalar();
        var writer = new AsnWriter();
        writer.PushSequence();
        writer.WriteInteger(1);
        writer.WriteOctetString(scalar);
        if (includeCurve)
        {
            writer.PushSequence(new Asn1Tag(TagClass.ContextSpecific, 0, true));
            writer.WriteObjectIdentifier(_curve.OidValue);
            writer.PopSequence();
        }
        writer.PushSequence(new Asn1Tag(TagClass.ContextSpecific, 1, true));
        writer.WriteBitString(_publicKey);
        writer.PopSequence();
        writer.PopSequence();
        CryptographicOperations.ZeroMemory(scalar);
        return writer.Encode();
    }

    /// The key an `ECPrivateKey` holds, and how many bytes it took.
    public static Result<EcKey, CryptoError> ImportECPrivateKey(ReadOnlySpan<byte> source,
                                                                out nuint bytesRead)
    {
        bytesRead = 0u;
        var whole = new AsnReader(source, AsnEncodingRules.Der).ReadEncodedValue();
        if (!whole.Ok)
            return Fail(CryptoError.Encoding);

        ECCurve none;
        var key = ReadECPrivateKey(whole.Value, none);
        if (key.Ok)
            bytesRead = whole.Value.Length;
        return key;
    }

    /// An `ECPrivateKey`, on `outerCurve` when that names one, which is how
    /// PKCS #8 carries it. A curve inside MUST then agree with it.
    static Result<EcKey, CryptoError> ReadECPrivateKey(ReadOnlySpan<byte> encoded,
                                                       ECCurve outerCurve)
    {
        var outer = new AsnReader(encoded, AsnEncodingRules.Der).ReadSequence();
        if (!outer.Ok)
            return Fail(CryptoError.Encoding);
        AsnReader sequence = outer.Value;

        var version = sequence.ReadInt64();
        if (!version.Ok || version.Value != 1)
            return Fail(CryptoError.Encoding);

        var scalar = sequence.ReadOctetString();
        if (!scalar.Ok)
            return Fail(CryptoError.Encoding);

        ECCurve curve = outerCurve;
        var curveTag = new Asn1Tag(TagClass.ContextSpecific, 0, true);
        var pointTag = new Asn1Tag(TagClass.ContextSpecific, 1, true);
        if (sequence.HasData && sequence.PeekTag().GetValueOrDefault(Asn1Tag.Null) == curveTag)
        {
            var wrapper = sequence.ReadSequence(curveTag);
            if (!wrapper.Ok)
                return Fail(CryptoError.Encoding);
            AsnReader parameters = wrapper.Value;
            var named = ReadNamedCurve(parameters);
            if (!named.Ok)
                return Fail(named.Error);
            if (parameters.VerifyEndOfData() != AsnError.None)
                return Fail(CryptoError.Encoding);
            if (outerCurve.IsNamed && !outerCurve.Equals(named.Value))
                return Fail(CryptoError.Encoding);
            curve = named.Value;
        }

        ReadOnlySpan<byte> point = new byte[0u];
        if (sequence.HasData && sequence.PeekTag().GetValueOrDefault(Asn1Tag.Null) == pointTag)
        {
            var wrapper = sequence.ReadSequence(pointTag);
            if (!wrapper.Ok)
                return Fail(CryptoError.Encoding);
            AsnReader inner = wrapper.Value;
            var bits = inner.ReadBitString(out int unused);
            if (!bits.Ok || unused != 0 || inner.VerifyEndOfData() != AsnError.None)
                return Fail(CryptoError.Encoding);
            point = bits.Value;
        }

        if (sequence.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);
        if (!curve.IsNamed)
            return Fail(CryptoError.Encoding);

        var domain = CreateEcDomainForCurve(curve);
        if (!domain.Ok)
            return Fail(domain.Error);
        return CreateFromPrivate(curve, domain.Value, scalar.Value, point);
    }

    // ------------------------------------------------------------------ PKCS #8

    /// PKCS #8's `PrivateKeyInfo`, unencrypted: version 0, the algorithm and
    /// curve, and an `ECPrivateKey` without the curve, as OpenSSL writes it.
    ///
    /// @failure CryptoError.InvalidKey  there is no private scalar
    public Result<byte[], CryptoError> ExportPkcs8PrivateKey()
    {
        if (!_hasPrivateKey)
            return Fail(CryptoError.InvalidKey);

        byte[] inner = EncodeECPrivateKey(false);
        var writer = new AsnWriter();
        writer.PushSequence();
        writer.WriteInteger(0);
        WriteAlgorithmIdentifier(writer);
        writer.WriteOctetString(inner);
        writer.PopSequence();
        CryptographicOperations.ZeroMemory(inner);
        return Ok(writer.Encode());
    }

    /// The key a PKCS #8 `PrivateKeyInfo` or `OneAsymmetricKey` holds, and how
    /// many bytes it took. Attributes and a trailing public key are passed
    /// over.
    public static Result<EcKey, CryptoError> ImportPkcs8PrivateKey(ReadOnlySpan<byte> source,
                                                                   out nuint bytesRead)
    {
        bytesRead = 0u;
        var whole = new AsnReader(source, AsnEncodingRules.Der).ReadEncodedValue();
        if (!whole.Ok)
            return Fail(CryptoError.Encoding);

        var outer = new AsnReader(whole.Value, AsnEncodingRules.Der).ReadSequence();
        if (!outer.Ok)
            return Fail(CryptoError.Encoding);
        AsnReader info = outer.Value;

        var version = info.ReadInt64();
        if (!version.Ok || (version.Value != 0 && version.Value != 1))
            return Fail(CryptoError.Encoding);

        var curve = ReadAlgorithmIdentifier(info);
        if (!curve.Ok)
            return Fail(curve.Error);

        var inner = info.ReadOctetString();
        if (!inner.Ok)
            return Fail(CryptoError.Encoding);

        while (info.HasData)
        {
            var tag = info.PeekTag();
            if (!tag.Ok || tag.Value.TagClass != TagClass.ContextSpecific)
                return Fail(CryptoError.Encoding);
            if (!info.ReadEncodedValue().Ok)
                return Fail(CryptoError.Encoding);
        }

        var key = ReadECPrivateKey(inner.Value, curve.Value);
        if (key.Ok)
            bytesRead = whole.Value.Length;
        return key;
    }

    // ---------------------------------------------------------------------- PEM

    /// The first key in `text` labelled `PUBLIC KEY`, `EC PRIVATE KEY` or
    /// `PRIVATE KEY`. Blocks with any other label, such as OpenSSL's
    /// `EC PARAMETERS`, are passed over.
    ///
    /// @failure CryptoError.Encoding     no such block, or its contents are not
    ///                                   the one structure its label names
    /// @failure CryptoError.Unsupported  the first key is `ENCRYPTED PRIVATE KEY`
    public static Result<EcKey, CryptoError> ImportFromPem(String text)
    {
        nuint at = 0u;
        while (true)
        {
            var found = PemEncoding.Find(text, at);
            if (!found.Some)
                return Fail(CryptoError.Encoding);

            PemFields block = found.Value;
            at = block.Location.End.Value;
            nuint bytesRead = 0u;
            Result<EcKey, CryptoError> key;
            switch (block.Label)
            {
                case "PUBLIC KEY":
                    key = ImportSubjectPublicKeyInfo(block.Data, out bytesRead);
                    break;
                case "EC PRIVATE KEY":
                    key = ImportECPrivateKey(block.Data, out bytesRead);
                    break;
                case "PRIVATE KEY":
                    key = ImportPkcs8PrivateKey(block.Data, out bytesRead);
                    break;
                case "ENCRYPTED PRIVATE KEY":
                    return Fail(CryptoError.Unsupported);
                default:
                    continue;
            }

            if (key.Ok && bytesRead != block.Data.Length)
                return Fail(CryptoError.Encoding);
            return key;
        }
    }
}

/// Whether `scalar` is in `[1, n - 1]`. The comparison is constant time; only
/// the answer shows.
bool IsValidEcScalar(EcElement scalar, ref EcDomain domain)
{
    ulong below = ComputeEcElementBelow(scalar, domain.Order.Value);
    ulong zero = ComputeEcElementZeroMask(scalar) & 1u;
    return (below & (zero ^ 1u)) != 0u;
}
