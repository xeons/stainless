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

import Standard.Text;
import Standard.Bits;
import Standard.Formats.Asn1;

// ============================================================ public key

/// An RSA key, public or private: signatures and encryption under RFC 8017,
/// and the key formats of PKCS #1, PKCS #8 and X.509.
///
/// ```csharp
/// var key = try Rsa.Create(2048);
/// byte[] signature = try key.SignData(message, HashAlgorithmName.Sha256,
///                                     RsaSignaturePadding.Pss);
///
/// var peer = try Rsa.ImportFromPem(pem);
/// bool genuine = peer.VerifyData(message, signature, HashAlgorithmName.Sha256,
///                                RsaSignaturePadding.Pss);
/// ```
///
/// **The shape is .NET's `RSA`**, with two differences that follow from
/// failing by `Result`. An `Rsa` always holds a key, so what .NET does with
/// `RSA.Create()` and an `Import` method is a static method here that answers
/// the key: `Rsa.ImportFromPem(pem)` rather than `rsa.ImportFromPem(pem)`. And
/// a DER import takes exactly one value, where .NET reports how many bytes it
/// read and ignores the rest.
///
/// **What is constant time.** Every operation on a secret — the private
/// exponentiation, the reduction of its input modulo each prime, the
/// recombination, the inverse of the blinding factor, OAEP and PKCS #1 v1.5
/// decoding after decryption, and the generation of `d` from the primes — runs
/// in time and touches memory in a pattern fixed by the key's size alone. The
/// public operations, verifying and encrypting, are not constant time and do
/// not need to be. Key generation rejects candidates in variable time; see
/// `Create(int)`.
///
/// **The private operation is blinded and checked.** Its input is multiplied
/// by `r^e` for a fresh random `r`, so the exponentiation never sees a value
/// the caller chose, and its result is raised to `e` again and compared with
/// the input before it is used, so a fault in the arithmetic cannot leak a
/// prime through a wrong signature.
///
/// An `Rsa` is not changed by anything after it is made, so one MAY be used
/// from several threads at once.
public sealed class Rsa
{
    private const nuint MinimumKeySize = 512u;
    private const nuint MaximumKeySize = 16384u;
    private static readonly String RsaEncryptionIdentifier = "1.2.840.113549.1.1.1";

    private MontgomeryModulus _modulus;
    private ulong[] _exponent;
    private nuint _keySize;
    private nuint _modulusLength;
    private RsaPrivateKey? _privateKey;

    Rsa(MontgomeryModulus modulus, ulong[] exponent, nuint keySize, RsaPrivateKey? privateKey)
    {
        _modulus = modulus;
        _exponent = exponent;
        _keySize = keySize;
        _modulusLength = (keySize + 7u) / 8u;
        _privateKey = privateKey;
    }

    /// The modulus's size in bits: 2048 for a 2048-bit key.
    public int KeySize => (int)_keySize;

    /// Whether this holds the private key as well as the public one.
    public bool HasPrivateKey => _privateKey != null;

    // ------------------------------------------------------------ making one

    /// The key `parameters` describes: public when it has only `Modulus` and
    /// `Exponent`, private when it has all eight.
    ///
    /// A private key is checked before it is accepted: `p * q` MUST be `n`,
    /// and `d`, `DP`, `DQ` and `InverseQ` MUST agree with `e`, `p` and `q`.
    /// A key that is only nearly right would sign wrongly, and a wrong
    /// signature from a CRT key is enough to factor its modulus.
    ///
    /// @param parameters  the numbers, big-endian; leading zeros are ignored
    /// @failure CryptoError.InvalidKey  a number is missing, out of range or
    ///                                  inconsistent with the others
    /// @see Rsa.ExportParameters
    public static Result<Rsa, CryptoError> Create(RsaParameters parameters)
    {
        byte[] modulus = parameters.Modulus;
        byte[] exponent = parameters.Exponent;
        if (modulus.Length == 0u || exponent.Length == 0u)
            return Fail(CryptoError.InvalidKey);

        nuint present = CountPresent(parameters.D) + CountPresent(parameters.P) +
                        CountPresent(parameters.Q) + CountPresent(parameters.DP) +
                        CountPresent(parameters.DQ) + CountPresent(parameters.InverseQ);
        if (present == 0u)
            return CreateFromNumbers(modulus, exponent);
        if (present != 6u)
            return Fail(CryptoError.InvalidKey);
        return CreateFromNumbers(modulus, exponent, parameters.D, parameters.P, parameters.Q,
                                 parameters.DP, parameters.DQ, parameters.InverseQ);
    }

    static nuint CountPresent(byte[] number) => number.Length > 0u ? 1u : 0u;

    /// A public key from its numbers.
    static Result<Rsa, CryptoError> CreateFromNumbers(ReadOnlySpan<byte> modulus,
                                                      ReadOnlySpan<byte> exponent)
    {
        nuint bits = Limbs.CountBits(modulus);
        bool odd = (modulus[modulus.Length - 1u] & 1) != 0;
        if (bits < MinimumKeySize || bits > MaximumKeySize || !odd)
            return Fail(CryptoError.InvalidKey);

        nuint exponentBits = Limbs.CountBits(exponent);
        if (exponentBits < 2u || exponentBits > bits || (exponent[exponent.Length - 1u] & 1) == 0)
            return Fail(CryptoError.InvalidKey);

        nuint count = Limbs.CountLimbsForBits(bits);
        ulong[] n = Limbs.FromBigEndian(modulus, count);
        ulong[] e = Limbs.FromBigEndian(exponent, Limbs.CountLimbsForBits(exponentBits));
        ulong[] widened = Limbs.FromBigEndian(exponent, count);
        if (Limbs.CompareVariableTime(&widened[0u], &n[0u], count) >= 0)
            return Fail(CryptoError.InvalidKey);

        return Ok(new Rsa(new MontgomeryModulus(n), e, bits, null));
    }

    /// A private key from its numbers, checked for consistency in constant
    /// time before it is accepted.
    static Result<Rsa, CryptoError> CreateFromNumbers(
        ReadOnlySpan<byte> modulus, ReadOnlySpan<byte> exponent, ReadOnlySpan<byte> d,
        ReadOnlySpan<byte> p, ReadOnlySpan<byte> q, ReadOnlySpan<byte> dp, ReadOnlySpan<byte> dq,
        ReadOnlySpan<byte> inverseQ)
    {
        Rsa key = try CreateFromNumbers(modulus, exponent);
        nuint count = key._modulus.LimbCount;
        nuint halfLength = (key._modulusLength + 1u) / 2u;

        // Sizes are not the secret; each number must fit where it is held.
        nuint pBits = Limbs.CountBits(p);
        nuint qBits = Limbs.CountBits(q);
        if (pBits < 2u || qBits < 2u || pBits > 8u * halfLength || qBits > 8u * halfLength ||
            Limbs.CountBits(d) > key._keySize || Limbs.CountBits(dp) > pBits ||
            Limbs.CountBits(dq) > qBits || Limbs.CountBits(inverseQ) > pBits)
        {
            return Fail(CryptoError.InvalidKey);
        }

        nuint pCount = Limbs.CountLimbsForBits(pBits);
        nuint qCount = Limbs.CountLimbsForBits(qBits);
        ulong[] n = key._modulus.Modulus;
        ulong[] e = key._exponent;
        ulong[] dLimbs = Limbs.FromBigEndian(d, count);
        ulong[] pLimbs = Limbs.FromBigEndian(p, pCount);
        ulong[] qLimbs = Limbs.FromBigEndian(q, qCount);
        ulong[] dpLimbs = Limbs.FromBigEndian(dp, pCount);
        ulong[] dqLimbs = Limbs.FromBigEndian(dq, qCount);
        ulong[] inverseQLimbs = Limbs.FromBigEndian(inverseQ, pCount);

        // Every check folds into one mask, so the time says nothing about
        // which failed.
        ulong wrong = ~(pLimbs[0u] & qLimbs[0u] & 1ul) & 1ul;
        wrong = Limbs.MaskFromBit(wrong);

        ulong[] product = new ulong[pCount + qCount];
        Limbs.Multiply(&product[0u], &pLimbs[0u], pCount, &qLimbs[0u], qCount);
        wrong |= ~MaskIfEqualNumbers(product, n);

        wrong |= Limbs.MaskIfAllZero(&dLimbs[0u], count);
        wrong |= ~Limbs.MaskIfLess(&dLimbs[0u], &n[0u], count);
        wrong |= ~Limbs.MaskIfLess(&dpLimbs[0u], &pLimbs[0u], pCount);
        wrong |= ~Limbs.MaskIfLess(&dqLimbs[0u], &qLimbs[0u], qCount);
        wrong |= ~Limbs.MaskIfLess(&inverseQLimbs[0u], &pLimbs[0u], pCount);

        // e * dp = 1 mod (p - 1) and d = dp mod (p - 1); the same for q.
        wrong |= CheckCrtExponent(e, dLimbs, pLimbs, dpLimbs);
        wrong |= CheckCrtExponent(e, dLimbs, qLimbs, dqLimbs);

        // q * InverseQ = 1 mod p, which needs p odd to be asked this way.
        if ((pLimbs[0u] & 1ul) != 0ul && pBits > 1u)
        {
            var primeP = new MontgomeryModulus(CopyNumber(pLimbs));
            ulong[] unit = primeP.MultiplyModular(primeP.Reduce(qLimbs), inverseQLimbs);
            ulong[] one = new ulong[pCount];
            one[0u] = 1ul;
            wrong |= ~MaskIfEqualNumbers(unit, one);
        }

        Limbs.ZeroMemory(product);
        if (wrong != 0ul)
            return Fail(CryptoError.InvalidKey);

        var privateKey = new RsaPrivateKey(dLimbs, pLimbs, qLimbs, dpLimbs, dqLimbs, inverseQLimbs);
        return Ok(new Rsa(key._modulus, e, key._keySize, privateKey));
    }

    /// All ones unless `e * exponentP = 1` and `d = exponentP`, both modulo
    /// `prime - 1`.
    static ulong CheckCrtExponent(ulong[] e, ulong[] d, ulong[] prime, ulong[] exponentP)
    {
        nuint count = prime.Length;
        ulong[] lower = CopyNumber(prime);
        Limbs.SubtractLimb(&lower[0u], 1ul, count);
        ulong[] scratch = new ulong[count];
        ulong[] remainder = new ulong[count];

        ulong[] product = new ulong[e.Length + count];
        Limbs.Multiply(&product[0u], &e[0u], e.Length, &exponentP[0u], count);
        Limbs.DivideConstantTime(null, &remainder[0u], &product[0u], product.Length, &lower[0u],
                                 count, &scratch[0u]);
        ulong wrong = ~Limbs.MaskIfOne(&remainder[0u], count);

        Limbs.DivideConstantTime(null, &remainder[0u], &d[0u], d.Length, &lower[0u], count,
                                 &scratch[0u]);
        wrong |= ~MaskIfEqualNumbers(remainder, exponentP);

        Limbs.ZeroMemory(product);
        Limbs.ZeroMemory(remainder);
        return wrong;
    }

    /// All ones when two numbers are equal, whatever their limb counts.
    static ulong MaskIfEqualNumbers(ulong[] left, ulong[] right)
    {
        nuint count = left.Length > right.Length ? left.Length : right.Length;
        ulong difference = 0ul;
        for (nuint i = 0u; i < count; i++)
        {
            ulong x = i < left.Length ? left[i] : 0ul;
            ulong y = i < right.Length ? right[i] : 0ul;
            difference |= x ^ y;
        }
        return Limbs.MaskIfZero(difference);
    }

    static ulong[] CopyNumber(ulong[] value)
    {
        ulong[] copy = new ulong[value.Length];
        for (nuint i = 0u; i < value.Length; i++)
            copy[i] = value[i];
        return copy;
    }

    // ------------------------------------------------------------ parameters

    /// The key's numbers.
    ///
    /// `Modulus` and `D` are the modulus's length in bytes, and `P`, `Q`,
    /// `DP`, `DQ` and `InverseQ` half of it rounded up, each with leading
    /// zeros where the number is shorter. `Exponent` has none.
    ///
    /// @param includePrivateParameters  whether to include the six private numbers
    /// @failure CryptoError.InvalidKey  the private numbers were asked for, and this is
    ///                                  a public key
    /// @see Rsa.Create
    public Result<RsaParameters, CryptoError> ExportParameters(bool includePrivateParameters)
    {
        var parameters = new RsaParameters();
        parameters.Modulus = Limbs.ToBigEndian(_modulus.Modulus, _modulusLength);
        parameters.Exponent = ExportExponent();
        if (!includePrivateParameters)
            return Ok(parameters);

        if (_privateKey is not RsaPrivateKey key)
            return Fail(CryptoError.InvalidKey);

        nuint half = (_modulusLength + 1u) / 2u;
        parameters.D = Limbs.ToBigEndian(key.Exponent, _modulusLength);
        parameters.P = Limbs.ToBigEndian(key.PrimeP.Modulus, half);
        parameters.Q = Limbs.ToBigEndian(key.PrimeQ.Modulus, half);
        parameters.DP = Limbs.ToBigEndian(key.ExponentP, half);
        parameters.DQ = Limbs.ToBigEndian(key.ExponentQ, half);
        parameters.InverseQ = Limbs.ToBigEndian(key.Coefficient, half);
        return Ok(parameters);
    }

    byte[] ExportExponent()
    {
        nuint bits = Limbs.CountBitsVariableTime(&_exponent[0u], _exponent.Length);
        return Limbs.ToBigEndian(_exponent, (bits + 7u) / 8u);
    }

    // ------------------------------------------------------------ DER

    /// The public key as a PKCS #1 `RSAPublicKey` (RFC 8017 §A.1.1), DER.
    public byte[] ExportRsaPublicKey()
    {
        var writer = new AsnWriter();
        WriteRsaPublicKey(writer);
        return writer.Encode();
    }

    /// The private key as a PKCS #1 `RSAPrivateKey` (RFC 8017 §A.1.2), DER.
    ///
    /// @failure CryptoError.InvalidKey  this is a public key
    public Result<byte[], CryptoError> ExportRsaPrivateKey()
    {
        if (_privateKey is not RsaPrivateKey key)
            return Fail(CryptoError.InvalidKey);

        var writer = new AsnWriter();
        WriteRsaPrivateKey(writer, key);
        return Ok(writer.Encode());
    }

    /// The public key as an X.509 `SubjectPublicKeyInfo` (RFC 5280 §4.1),
    /// DER: what a certificate carries and what `PUBLIC KEY` PEM holds.
    public byte[] ExportSubjectPublicKeyInfo()
    {
        var inner = new AsnWriter();
        WriteRsaPublicKey(inner);

        var writer = new AsnWriter();
        writer.PushSequence();
        WriteAlgorithmIdentifier(writer);
        writer.WriteBitString(inner.Encode());
        writer.PopSequence();
        return writer.Encode();
    }

    /// The private key as an unencrypted PKCS #8 `PrivateKeyInfo` (RFC 5208),
    /// DER: what `PRIVATE KEY` PEM holds.
    ///
    /// @failure CryptoError.InvalidKey  this is a public key
    public Result<byte[], CryptoError> ExportPkcs8PrivateKey()
    {
        if (_privateKey is not RsaPrivateKey key)
            return Fail(CryptoError.InvalidKey);

        var inner = new AsnWriter();
        WriteRsaPrivateKey(inner, key);
        byte[] encoded = inner.Encode();

        var writer = new AsnWriter();
        writer.PushSequence();
        writer.WriteInteger(0L);
        WriteAlgorithmIdentifier(writer);
        writer.WriteOctetString(encoded);
        writer.PopSequence();
        CryptographicOperations.ZeroMemory(encoded);
        return Ok(writer.Encode());
    }

    /// A key from a PKCS #1 `RSAPublicKey`, DER.
    ///
    /// @param source  exactly one DER value
    /// @failure CryptoError.Encoding    `source` is not one `RSAPublicKey`
    /// @failure CryptoError.InvalidKey  the numbers are not an RSA key
    public static Result<Rsa, CryptoError> ImportRsaPublicKey(ReadOnlySpan<byte> source)
    {
        var reader = new AsnReader(source, AsnEncodingRules.Der);
        Rsa key = try ReadRsaPublicKey(reader);
        if (reader.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);
        return Ok(key);
    }

    /// A key from a PKCS #1 `RSAPrivateKey`, DER.
    ///
    /// @param source  exactly one DER value
    /// @failure CryptoError.Encoding     `source` is not one `RSAPrivateKey`
    /// @failure CryptoError.Unsupported  a multi-prime key, version 1
    /// @failure CryptoError.InvalidKey   the numbers are not a consistent RSA key
    public static Result<Rsa, CryptoError> ImportRsaPrivateKey(ReadOnlySpan<byte> source)
    {
        var reader = new AsnReader(source, AsnEncodingRules.Der);
        Rsa key = try ReadRsaPrivateKey(reader);
        if (reader.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);
        return Ok(key);
    }

    /// A key from an X.509 `SubjectPublicKeyInfo`, DER.
    ///
    /// @param source  exactly one DER value
    /// @failure CryptoError.Encoding    `source` is not one `SubjectPublicKeyInfo` holding
    ///                                  an RSA key
    /// @failure CryptoError.InvalidKey  the numbers are not an RSA key
    public static Result<Rsa, CryptoError> ImportSubjectPublicKeyInfo(ReadOnlySpan<byte> source)
    {
        var reader = new AsnReader(source, AsnEncodingRules.Der);
        var outer = reader.ReadSequence();
        if (!outer.Ok || reader.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);
        AsnReader info = outer.Value;
        if (!ReadAlgorithmIdentifier(info))
            return Fail(CryptoError.Encoding);

        var bits = info.ReadBitString(out int unused);
        if (!bits.Ok || unused != 0 || info.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);
        return ImportRsaPublicKey(bits.Value);
    }

    /// A key from an unencrypted PKCS #8 `PrivateKeyInfo` or
    /// `OneAsymmetricKey`, DER. Attributes and an embedded public key are
    /// passed over.
    ///
    /// @param source  exactly one DER value
    /// @failure CryptoError.Encoding    `source` is not one `PrivateKeyInfo` holding an
    ///                                  RSA key
    /// @failure CryptoError.InvalidKey  the numbers are not a consistent RSA key
    public static Result<Rsa, CryptoError> ImportPkcs8PrivateKey(ReadOnlySpan<byte> source)
    {
        var reader = new AsnReader(source, AsnEncodingRules.Der);
        var outer = reader.ReadSequence();
        if (!outer.Ok || reader.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);
        AsnReader info = outer.Value;

        var version = info.ReadInt64();
        if (!version.Ok || version.Value < 0L || version.Value > 1L)
            return Fail(CryptoError.Encoding);
        if (!ReadAlgorithmIdentifier(info))
            return Fail(CryptoError.Encoding);
        var octets = info.ReadOctetString();
        if (!octets.Ok)
            return Fail(CryptoError.Encoding);

        while (info.HasData)
        {
            var tag = info.PeekTag();
            if (!tag.Ok || tag.Value.TagClass != TagClass.ContextSpecific ||
                !info.ReadEncodedValue().Ok)
            {
                return Fail(CryptoError.Encoding);
            }
        }
        return ImportRsaPrivateKey(octets.Value);
    }

    static Result<Rsa, CryptoError> ReadRsaPublicKey(AsnReader reader)
    {
        var sequence = reader.ReadSequence();
        if (!sequence.Ok)
            return Fail(CryptoError.Encoding);
        AsnReader fields = sequence.Value;
        byte[] modulus = try ReadUnsignedInteger(fields);
        byte[] exponent = try ReadUnsignedInteger(fields);
        if (fields.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);
        return CreateFromNumbers(modulus, exponent);
    }

    static Result<Rsa, CryptoError> ReadRsaPrivateKey(AsnReader reader)
    {
        var sequence = reader.ReadSequence();
        if (!sequence.Ok)
            return Fail(CryptoError.Encoding);
        AsnReader fields = sequence.Value;

        var version = fields.ReadInt64();
        if (!version.Ok)
            return Fail(CryptoError.Encoding);
        if (version.Value == 1L)
            return Fail(CryptoError.Unsupported);
        if (version.Value != 0L)
            return Fail(CryptoError.Encoding);

        byte[] modulus = try ReadUnsignedInteger(fields);
        byte[] exponent = try ReadUnsignedInteger(fields);
        byte[] d = try ReadUnsignedInteger(fields);
        byte[] p = try ReadUnsignedInteger(fields);
        byte[] q = try ReadUnsignedInteger(fields);
        byte[] dp = try ReadUnsignedInteger(fields);
        byte[] dq = try ReadUnsignedInteger(fields);
        byte[] inverseQ = try ReadUnsignedInteger(fields);
        if (fields.VerifyEndOfData() != AsnError.None)
            return Fail(CryptoError.Encoding);

        var key = CreateFromNumbers(modulus, exponent, d, p, q, dp, dq, inverseQ);
        CryptographicOperations.ZeroMemory(d);
        CryptographicOperations.ZeroMemory(p);
        CryptographicOperations.ZeroMemory(q);
        CryptographicOperations.ZeroMemory(dp);
        CryptographicOperations.ZeroMemory(dq);
        CryptographicOperations.ZeroMemory(inverseQ);
        return key;
    }

    /// The next `INTEGER`, which MUST NOT be negative, as its magnitude.
    static Result<byte[], CryptoError> ReadUnsignedInteger(AsnReader reader)
    {
        var value = reader.ReadIntegerBytes();
        if (!value.Ok || (value.Value[0u] & 0x80) != 0)
            return Fail(CryptoError.Encoding);
        return Ok(value.Value.ToArray());
    }

    /// Reads an `AlgorithmIdentifier` and answers whether it is
    /// `rsaEncryption` with the `NULL` parameters RFC 3279 requires, or
    /// with none.
    static bool ReadAlgorithmIdentifier(AsnReader reader)
    {
        var sequence = reader.ReadSequence();
        if (!sequence.Ok)
            return false;
        AsnReader algorithm = sequence.Value;
        var identifier = algorithm.ReadObjectIdentifier();
        if (!identifier.Ok || identifier.Value != RsaEncryptionIdentifier)
            return false;
        if (algorithm.HasData && algorithm.ReadNull() != AsnError.None)
            return false;
        return algorithm.VerifyEndOfData() == AsnError.None;
    }

    static void WriteAlgorithmIdentifier(AsnWriter writer)
    {
        writer.PushSequence();
        writer.WriteObjectIdentifier(RsaEncryptionIdentifier);
        writer.WriteNull();
        writer.PopSequence();
    }

    void WriteRsaPublicKey(AsnWriter writer)
    {
        writer.PushSequence();
        writer.WriteIntegerUnsigned(Limbs.ToBigEndian(_modulus.Modulus, _modulusLength));
        writer.WriteIntegerUnsigned(ExportExponent());
        writer.PopSequence();
    }

    void WriteRsaPrivateKey(AsnWriter writer, RsaPrivateKey key)
    {
        nuint half = (_modulusLength + 1u) / 2u;
        writer.PushSequence();
        writer.WriteInteger(0L);
        writer.WriteIntegerUnsigned(Limbs.ToBigEndian(_modulus.Modulus, _modulusLength));
        writer.WriteIntegerUnsigned(ExportExponent());
        WriteSecretInteger(writer, key.Exponent, _modulusLength);
        WriteSecretInteger(writer, key.PrimeP.Modulus, half);
        WriteSecretInteger(writer, key.PrimeQ.Modulus, half);
        WriteSecretInteger(writer, key.ExponentP, half);
        WriteSecretInteger(writer, key.ExponentQ, half);
        WriteSecretInteger(writer, key.Coefficient, half);
        writer.PopSequence();
    }

    static void WriteSecretInteger(AsnWriter writer, ulong[] value, nuint length)
    {
        byte[] bytes = Limbs.ToBigEndian(value, length);
        writer.WriteIntegerUnsigned(bytes);
        CryptographicOperations.ZeroMemory(bytes);
    }

    // ------------------------------------------------------------ PEM

    /// The public key as PKCS #1 in PEM: `-----BEGIN RSA PUBLIC KEY-----`.
    public String ExportRsaPublicKeyPem() =>
        PemEncoding.Write("RSA PUBLIC KEY", ExportRsaPublicKey());

    /// The private key as PKCS #1 in PEM: `-----BEGIN RSA PRIVATE KEY-----`.
    ///
    /// @failure CryptoError.InvalidKey  this is a public key
    public Result<String, CryptoError> ExportRsaPrivateKeyPem()
    {
        byte[] der = try ExportRsaPrivateKey();
        String pem = PemEncoding.Write("RSA PRIVATE KEY", der);
        CryptographicOperations.ZeroMemory(der);
        return Ok(pem);
    }

    /// The public key as X.509 in PEM: `-----BEGIN PUBLIC KEY-----`.
    public String ExportSubjectPublicKeyInfoPem() =>
        PemEncoding.Write("PUBLIC KEY", ExportSubjectPublicKeyInfo());

    /// The private key as PKCS #8 in PEM: `-----BEGIN PRIVATE KEY-----`.
    ///
    /// @failure CryptoError.InvalidKey  this is a public key
    public Result<String, CryptoError> ExportPkcs8PrivateKeyPem()
    {
        byte[] der = try ExportPkcs8PrivateKey();
        String pem = PemEncoding.Write("PRIVATE KEY", der);
        CryptographicOperations.ZeroMemory(der);
        return Ok(pem);
    }

    /// The one RSA key in `input`, which may hold other text and PEM blocks
    /// of other kinds: `RSA PUBLIC KEY`, `RSA PRIVATE KEY`, `PUBLIC KEY` or
    /// `PRIVATE KEY`, as .NET's `ImportFromPem` reads.
    ///
    /// @param input  text holding exactly one key block
    /// @failure CryptoError.Encoding     no key block, more than one, or one that does
    ///                                   not parse
    /// @failure CryptoError.Unsupported  the block is an `ENCRYPTED PRIVATE KEY`
    /// @failure CryptoError.InvalidKey   the numbers are not a consistent RSA key
    public static Result<Rsa, CryptoError> ImportFromPem(String input)
    {
        nuint at = 0u;
        String label = "";
        byte[] data = new byte[0u];
        nuint found = 0u;
        while (true)
        {
            var next = PemEncoding.Find(input, at);
            if (!next.Some)
                break;
            PemFields block = next.Value;
            at = block.Location.End.Value;
            switch (block.Label)
            {
                case "RSA PUBLIC KEY":
                case "RSA PRIVATE KEY":
                case "PUBLIC KEY":
                case "PRIVATE KEY":
                case "ENCRYPTED PRIVATE KEY":
                    label = block.Label;
                    data = block.Data;
                    found++;
                    break;
            }
        }

        if (found != 1u)
            return Fail(CryptoError.Encoding);

        switch (label)
        {
            case "RSA PUBLIC KEY": return ImportRsaPublicKey(data);
            case "RSA PRIVATE KEY": return ImportRsaPrivateKey(data);
            case "PUBLIC KEY": return ImportSubjectPublicKeyInfo(data);
            case "PRIVATE KEY": return ImportPkcs8PrivateKey(data);
        }
        return Fail(CryptoError.Unsupported);
    }

    // ------------------------------------------------------------ the primitives

    /// `value^e mod n`, for a value already below `n`.
    ulong[] ApplyPublicExponent(ulong[] value) => _modulus.PowerVariableTime(value, _exponent);

    /// `input^d mod n` as the modulus's length in bytes: blinded, by the
    /// Chinese remainder theorem, and checked against the public key.
    ///
    /// @failure CryptoError.InvalidKey  this is a public key, or the result did
    ///                                  not survive the check
    Result<byte[], CryptoError> ApplyPrivateExponent(ulong[] input)
    {
        if (_privateKey is not RsaPrivateKey key)
            return Fail(CryptoError.InvalidKey);

        ulong[] blinding = try RsaKeyGenerator.DrawRandomBelow(_modulus.Modulus);
        ulong[] blinded = _modulus.MultiplyModular(input, ApplyPublicExponent(blinding));
        ulong[] result = key.ComputeUnblindedPower(_modulus, blinded, blinding);
        Limbs.ZeroMemory(blinding);

        ulong[] check = ApplyPublicExponent(result);
        if (MaskIfEqualNumbers(check, input) == 0ul)
        {
            Limbs.ZeroMemory(result);
            return Fail(CryptoError.InvalidKey);
        }

        byte[] output = Limbs.ToBigEndian(result, _modulusLength);
        Limbs.ZeroMemory(result);
        return Ok(output);
    }

    /// `value` as a number, when it is exactly the modulus's length and below
    /// it, which is what a signature and a ciphertext have to be.
    Optional<ulong[]> ConvertToNumberBelowModulus(ReadOnlySpan<byte> value)
    {
        if (value.Length != _modulusLength)
            return None;
        nuint count = _modulus.LimbCount;
        ulong[] number = Limbs.FromBigEndian(value, count);
        if (Limbs.CompareVariableTime(&number[0u], &_modulus.Modulus[0u], count) >= 0)
            return None;
        return Some(number);
    }
}
