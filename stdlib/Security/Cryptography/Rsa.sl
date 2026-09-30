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
/// **Sizes are bounded.** Every key read or built from numbers, public or
/// private, has a modulus of 1024 to 8192 bits and a public exponent of at
/// most 33 bits, as BoringSSL requires; `Create(int)` makes 2048 to 8192.
/// The bounds keep one verification with a key from the network cheap.
///
/// An `Rsa` is not changed by anything after it is made, so one MAY be used
/// from several threads at once.
public sealed class Rsa
{
    private const nuint MinimumKeySize = 1024u;
    private const nuint MinimumGeneratedKeySize = 2048u;
    private const nuint MaximumKeySize = 8192u;
    private const nuint MaximumExponentSize = 33u;
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

    /// A new key of `keySizeInBits` bits, with public exponent 65537.
    ///
    /// FIPS 186-5 §A.1.3: two random probable primes of half the size each,
    /// at least `sqrt(2) * 2^(half - 1)`, at least `2^(half - 100)` apart,
    /// each passing Miller-Rabin with random bases as many times as Table B.1
    /// asks; `d` is `65537^-1 mod lcm(p - 1, q - 1)` and at least `2^half`.
    ///
    /// **The time taken is random**, since it is a search: from a few tens to
    /// a few hundred milliseconds for 2048 bits on a current x64, and from
    /// under one second to several for 4096.
    /// A candidate is thrown away as soon as a small prime divides it or a
    /// Miller-Rabin round finds a witness, so the time reveals something
    /// about numbers that are not kept. What is kept is handled in constant
    /// time, `d` included.
    ///
    /// @param keySizeInBits  a multiple of 64 from 2048 to 8192
    /// @failure CryptoError.KeyLength  `keySizeInBits` is not a size this makes
    /// @failure CryptoError.NoEntropy  the platform would not supply randomness
    public static Result<Rsa, CryptoError> Create(int keySizeInBits)
    {
        if (keySizeInBits < (int)MinimumGeneratedKeySize || keySizeInBits > (int)MaximumKeySize ||
            keySizeInBits % 64 != 0)
        {
            return Fail(CryptoError.KeyLength);
        }

        ulong[][] parts = try RsaKeyGenerator.GenerateKeyParts((nuint)keySizeInBits);
        ulong[] exponent = [RsaKeyGenerator.PublicExponent];
        var privateKey = new RsaPrivateKey(parts[1u], parts[2u], parts[3u], parts[4u], parts[5u],
                                           parts[6u]);
        return Ok(new Rsa(new MontgomeryModulus(parts[0u]), exponent, (nuint)keySizeInBits,
                          privateKey));
    }

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

    /// A public key from its numbers: a modulus of 1024 to 8192 bits and an
    /// odd exponent of 2 to 33 bits. Every key this type holds passes here.
    static Result<Rsa, CryptoError> CreateFromNumbers(ReadOnlySpan<byte> modulus,
                                                      ReadOnlySpan<byte> exponent)
    {
        nuint bits = Limbs.CountBits(modulus);
        bool odd = (modulus[modulus.Length - 1u] & 1) != 0;
        if (bits < MinimumKeySize || bits > MaximumKeySize || !odd)
            return Fail(CryptoError.InvalidKey);

        nuint exponentBits = Limbs.CountBits(exponent);
        if (exponentBits < 2u || exponentBits > MaximumExponentSize ||
            (exponent[exponent.Length - 1u] & 1) == 0)
        {
            return Fail(CryptoError.InvalidKey);
        }

        // An exponent of 33 bits is always below a modulus of 1024.
        nuint count = Limbs.CountLimbsForBits(bits);
        ulong[] n = Limbs.FromBigEndian(modulus, count);
        ulong[] e = Limbs.FromBigEndian(exponent, Limbs.CountLimbsForBits(exponentBits));
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

    static ulong[] CopyNumber(ulong[] value) => value[:].ToArray();

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
    /// @failure CryptoError.InvalidKey  the numbers are not an RSA key of a size this reads
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
    /// @failure CryptoError.InvalidKey   the numbers are not a consistent RSA key of a
    ///                                   size this reads
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
    /// @failure CryptoError.InvalidKey  the numbers are not an RSA key of a size this reads
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
    /// @failure CryptoError.InvalidKey  the numbers are not a consistent RSA key of a
    ///                                  size this reads
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
    /// @failure CryptoError.InvalidKey   the numbers are not a consistent RSA key of a
    ///                                   size this reads
    public static Result<Rsa, CryptoError> ImportFromPem(String input)
    {
        nuint at = 0u;
        String label = "";
        byte[] data = new byte[0u];
        nuint found = 0u;
        byte[] text = input.ToBytes();
        while (true)
        {
            var next = PemEncoding.FindUtf8(text, at);
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

    // ------------------------------------------------------------ signatures

    /// The signature of `data`'s hash.
    ///
    /// @param data           what to sign; it is hashed here
    /// @param hashAlgorithm  the hash, which the verifier MUST use too
    /// @param padding        PKCS #1 v1.5, or PSS with its salt length
    /// @failure CryptoError.InvalidKey      this is a public key
    /// @failure CryptoError.Unsupported     the hash is not one this module has
    /// @failure CryptoError.MessageLength   the key is too small for the hash and padding
    /// @failure CryptoError.NoEntropy       the platform would not supply randomness
    /// @see Rsa.VerifyData
    public Result<byte[], CryptoError> SignData(ReadOnlySpan<byte> data,
                                                HashAlgorithmName hashAlgorithm,
                                                RsaSignaturePadding padding)
    {
        IHashAlgorithm hash = try hashAlgorithm.CreateHashAlgorithm();
        hash.AppendData(data);
        return SignHash(hash.GetHashAndReset(), hashAlgorithm, padding);
    }

    /// The signature of a hash already computed.
    ///
    /// @param hash           the digest, exactly as long as `hashAlgorithm`'s
    /// @param hashAlgorithm  the hash that made it
    /// @param padding        PKCS #1 v1.5, or PSS with its salt length
    /// @failure CryptoError.Parameter       `hash` is not the digest's length
    /// @failure CryptoError.InvalidKey      this is a public key
    /// @failure CryptoError.Unsupported     the hash is not one this module has
    /// @failure CryptoError.MessageLength   the key is too small for the hash and padding
    /// @failure CryptoError.NoEntropy       the platform would not supply randomness
    /// @see Rsa.VerifyHash
    public Result<byte[], CryptoError> SignHash(ReadOnlySpan<byte> hash,
                                                HashAlgorithmName hashAlgorithm,
                                                RsaSignaturePadding padding)
    {
        IHashAlgorithm algorithm = try hashAlgorithm.CreateHashAlgorithm();
        if (hash.Length != algorithm.HashSizeInBytes)
            return Fail(CryptoError.Parameter);
        if (_privateKey == null)
            return Fail(CryptoError.InvalidKey);

        byte[] encoded;
        if (padding.Mode == RsaSignaturePaddingMode.Pkcs1)
        {
            encoded = try EncodePkcs1Signature(hash, hashAlgorithm);
        }
        else
        {
            nuint salt = try ChoosePssSaltLength(padding, algorithm.HashSizeInBytes);
            encoded = try EncodePss(hash, algorithm, salt);
        }

        return ApplyPrivateExponent(Limbs.FromBigEndian(encoded, _modulus.LimbCount));
    }

    /// Whether `signature` is this key's signature of `data`'s hash.
    ///
    /// **Never fails**: a signature that is malformed, the wrong length or
    /// for another message is simply not valid, and an unknown hash is false.
    ///
    /// @param data           what was signed
    /// @param signature      the signature, as long as the modulus
    /// @param hashAlgorithm  the hash the signer used
    /// @param padding        the encoding the signer used
    /// @see Rsa.SignData
    public bool VerifyData(ReadOnlySpan<byte> data, ReadOnlySpan<byte> signature,
                           HashAlgorithmName hashAlgorithm, RsaSignaturePadding padding)
    {
        var created = hashAlgorithm.CreateHashAlgorithm();
        if (!created.Ok)
            return false;
        IHashAlgorithm hash = created.Value;
        hash.AppendData(data);
        return VerifyHash(hash.GetHashAndReset(), signature, hashAlgorithm, padding);
    }

    /// Whether `signature` is this key's signature of a hash already
    /// computed. Never fails, as `VerifyData` does not.
    ///
    /// @param hash           the digest
    /// @param signature      the signature, as long as the modulus
    /// @param hashAlgorithm  the hash that made the digest
    /// @param padding        the encoding the signer used
    public bool VerifyHash(ReadOnlySpan<byte> hash, ReadOnlySpan<byte> signature,
                           HashAlgorithmName hashAlgorithm, RsaSignaturePadding padding)
    {
        var created = hashAlgorithm.CreateHashAlgorithm();
        if (!created.Ok)
            return false;
        IHashAlgorithm algorithm = created.Value;
        if (hash.Length != algorithm.HashSizeInBytes)
            return false;

        var number = ConvertToNumberBelowModulus(signature);
        if (!number.Some)
            return false;
        byte[] encoded = Limbs.ToBigEndian(ApplyPublicExponent(number.Value), _modulusLength);

        if (padding.Mode == RsaSignaturePaddingMode.Pkcs1)
        {
            var expected = EncodePkcs1Signature(hash, hashAlgorithm);
            return expected.Ok && CryptographicOperations.FixedTimeEquals(encoded, expected.Value);
        }
        return VerifyPss(hash, encoded, algorithm, padding.PssSaltLength);
    }

    /// EMSA-PKCS1-v1_5 (RFC 8017 §9.2): `00 01 FF...FF 00 DigestInfo`, as
    /// long as the modulus.
    Result<byte[], CryptoError> EncodePkcs1Signature(ReadOnlySpan<byte> hash,
                                                     HashAlgorithmName hashAlgorithm)
    {
        var prefix = hashAlgorithm.CreateDigestInfoPrefix();
        if (!prefix.Some)
            return Fail(CryptoError.Unsupported);
        nuint length = prefix.Value.Length + hash.Length;
        if (_modulusLength < length + 11u)
            return Fail(CryptoError.MessageLength);

        byte[] encoded = new byte[_modulusLength];
        encoded[1u] = 0x01;
        nuint separator = _modulusLength - length - 1u;
        for (nuint i = 2u; i < separator; i++)
            encoded[i] = 0xFF;
        prefix.Value[:].CopyTo(encoded[separator + 1u:]);
        hash.CopyTo(encoded[separator + 1u + prefix.Value.Length:]);
        return Ok(encoded);
    }

    /// How many bytes of salt `padding` asks for with this key and a digest
    /// of `hashLength` bytes.
    Result<nuint, CryptoError> ChoosePssSaltLength(RsaSignaturePadding padding, nuint hashLength)
    {
        int asked = padding.PssSaltLength;
        if (asked == RsaSignaturePadding.PssSaltLengthIsHashLength)
            return Ok(hashLength);

        nuint encodedLength = (_keySize - 1u + 7u) / 8u;
        if (asked == RsaSignaturePadding.PssSaltLengthMax)
        {
            if (encodedLength < hashLength + 2u)
                return Fail(CryptoError.MessageLength);
            return Ok(encodedLength - hashLength - 2u);
        }
        return Ok((nuint)asked);
    }

    /// EMSA-PSS-ENCODE (RFC 8017 §9.1.1) with MGF1 over the same hash,
    /// into `emLen` bytes for `emBits` one short of the modulus's.
    Result<byte[], CryptoError> EncodePss(ReadOnlySpan<byte> hash, IHashAlgorithm algorithm,
                                          nuint saltLength)
    {
        nuint hashLength = algorithm.HashSizeInBytes;
        nuint encodedBits = _keySize - 1u;
        nuint encodedLength = (encodedBits + 7u) / 8u;
        if (encodedLength < hashLength + saltLength + 2u)
            return Fail(CryptoError.MessageLength);

        byte[] salt = new byte[saltLength];
        if (!RandomNumberGenerator.Fill(salt))
            return Fail(CryptoError.NoEntropy);

        algorithm.Reset();
        algorithm.AppendData(new byte[8u]);
        algorithm.AppendData(hash);
        algorithm.AppendData(salt);
        byte[] digest = algorithm.GetHashAndReset();

        nuint maskedLength = encodedLength - hashLength - 1u;
        byte[] encoded = GenerateMask(algorithm, digest, maskedLength);
        encoded[maskedLength - saltLength - 1u] ^= 0x01;
        for (nuint i = 0u; i < saltLength; i++)
            encoded[maskedLength - saltLength + i] ^= salt[i];
        encoded[0u] &= (byte)(0xFFu >> (uint)(8u * encodedLength - encodedBits));

        byte[] result = new byte[encodedLength];
        encoded[:maskedLength].CopyTo(result);
        digest[:hashLength].CopyTo(result[maskedLength:]);
        result[encodedLength - 1u] = 0xBC;
        return Ok(result);
    }

    /// EMSA-PSS-VERIFY (RFC 8017 §9.1.2) over the modulus-length `decoded`.
    /// A `saltLength` of `PssSaltLengthMax` accepts any salt.
    bool VerifyPss(ReadOnlySpan<byte> hash, byte[] decoded, IHashAlgorithm algorithm,
                   int saltLength)
    {
        nuint hashLength = algorithm.HashSizeInBytes;
        nuint encodedBits = _keySize - 1u;
        nuint encodedLength = (encodedBits + 7u) / 8u;
        if (encodedLength < hashLength + 2u)
            return false;

        // The encoding is one byte short of the modulus when emBits is a
        // multiple of eight, and that byte MUST be zero.
        nuint skip = _modulusLength - encodedLength;
        if (skip == 1u && decoded[0u] != 0)
            return false;
        if (decoded[_modulusLength - 1u] != 0xBC)
            return false;

        nuint maskedLength = encodedLength - hashLength - 1u;
        byte topMask = (byte)(0xFFu >> (uint)(8u * encodedLength - encodedBits));
        if ((decoded[skip] & ~topMask) != 0)
            return false;

        ReadOnlySpan<byte> digest = decoded[skip + maskedLength:skip + maskedLength + hashLength];
        byte[] block = GenerateMask(algorithm, digest, maskedLength);
        for (nuint i = 0u; i < maskedLength; i++)
            block[i] ^= decoded[skip + i];
        block[0u] &= topMask;

        nuint separator = 0u;
        while (separator < maskedLength && block[separator] == 0)
            separator++;
        if (separator == maskedLength || block[separator] != 0x01)
            return false;
        nuint foundSalt = maskedLength - separator - 1u;

        if (saltLength != RsaSignaturePadding.PssSaltLengthMax)
        {
            nuint wanted = saltLength == RsaSignaturePadding.PssSaltLengthIsHashLength
                               ? hashLength
                               : (nuint)saltLength;
            if (foundSalt != wanted)
                return false;
        }

        algorithm.Reset();
        algorithm.AppendData(new byte[8u]);
        algorithm.AppendData(hash);
        algorithm.AppendData(block[maskedLength - foundSalt:]);
        byte[] expected = algorithm.GetHashAndReset();
        return CryptographicOperations.FixedTimeEquals(expected, digest);
    }

    /// MGF1 (RFC 8017 §B.2.1): `length` bytes from `seed`.
    static byte[] GenerateMask(IHashAlgorithm hash, ReadOnlySpan<byte> seed, nuint length)
    {
        byte[] mask = new byte[length];
        byte[] counter = new byte[4u];
        nuint filled = 0u;
        uint index = 0u;
        while (filled < length)
        {
            WriteBigWord(counter, 0u, index);
            hash.Reset();
            hash.AppendData(seed);
            hash.AppendData(counter);
            byte[] block = hash.GetHashAndReset();
            nuint take = length - filled < block.Length ? length - filled : block.Length;
            block[:take].CopyTo(mask[filled:]);
            filled += take;
            index++;
        }
        return mask;
    }

    // ------------------------------------------------------------ encryption

    /// `data` encrypted to this key.
    ///
    /// @param data     at most the modulus's length less 11 bytes under PKCS #1
    ///                 v1.5, or less twice the digest and 2 under OAEP
    /// @param padding  OAEP with its hash and label, or PKCS #1 v1.5
    /// @failure CryptoError.MessageLength  `data` is too long for the key and padding
    /// @failure CryptoError.Unsupported    OAEP's hash is not one this module has
    /// @failure CryptoError.NoEntropy      the platform would not supply randomness
    /// @see Rsa.Decrypt
    public Result<byte[], CryptoError> Encrypt(ReadOnlySpan<byte> data,
                                               RsaEncryptionPadding padding)
    {
        nuint k = _modulusLength;
        byte[] encoded = new byte[k];

        if (padding.Mode == RsaEncryptionPaddingMode.Pkcs1)
        {
            if (k < 11u || data.Length > k - 11u)
                return Fail(CryptoError.MessageLength);

            // 00 02, random non-zero padding, 00, the message.
            encoded[1u] = 0x02;
            nuint separator = k - data.Length - 1u;
            byte[] one = new byte[1u];
            for (nuint i = 2u; i < separator; i++)
            {
                do
                {
                    if (!RandomNumberGenerator.Fill(one))
                        return Fail(CryptoError.NoEntropy);
                }
                while (one[0u] == 0);
                encoded[i] = one[0u];
            }
            data.CopyTo(encoded[separator + 1u:]);
        }
        else
        {
            IHashAlgorithm hash = try padding.OaepHashAlgorithm.CreateHashAlgorithm();
            nuint hashLength = hash.HashSizeInBytes;
            if (k < 2u * hashLength + 2u || data.Length > k - 2u * hashLength - 2u)
                return Fail(CryptoError.MessageLength);

            // 00, masked seed, masked (label hash, zeros, 01, message).
            hash.AppendData(padding.OaepLabel);
            byte[] labelHash = hash.GetHashAndReset();
            nuint blockLength = k - hashLength - 1u;
            byte[] block = new byte[blockLength];
            labelHash[:hashLength].CopyTo(block);
            block[blockLength - data.Length - 1u] = 0x01;
            data.CopyTo(block[blockLength - data.Length:]);

            byte[] seed = new byte[hashLength];
            if (!RandomNumberGenerator.Fill(seed))
                return Fail(CryptoError.NoEntropy);
            byte[] blockMask = GenerateMask(hash, seed, blockLength);
            for (nuint i = 0u; i < blockLength; i++)
                block[i] ^= blockMask[i];
            byte[] seedMask = GenerateMask(hash, block, hashLength);
            for (nuint i = 0u; i < hashLength; i++)
                encoded[1u + i] = (byte)(seed[i] ^ seedMask[i]);
            block[:].CopyTo(encoded[1u + hashLength:]);
        }

        ulong[] number = Limbs.FromBigEndian(encoded, _modulus.LimbCount);
        CryptographicOperations.ZeroMemory(encoded);
        return Ok(Limbs.ToBigEndian(ApplyPublicExponent(number), k));
    }

    /// `data` decrypted with this key.
    ///
    /// **OAEP** decodes in constant time and fails with one error however the
    /// encoding is wrong, so the failure says nothing about the plaintext.
    ///
    /// **PKCS #1 v1.5 never fails on bad padding.** It uses implicit rejection
    /// (draft-irtf-cfrg-rsa-guidance, as OpenSSL 3.2 does): a ciphertext whose
    /// padding is wrong decrypts to a random-looking message derived from the
    /// ciphertext and the key, the same every time, in the same time as a
    /// valid one. That is what closes Bleichenbacher's oracle; the caller MUST
    /// treat what comes back as untrusted and check it by other means.
    ///
    /// @param data     the ciphertext, exactly as long as the modulus
    /// @param padding  what it was encrypted with
    /// @failure CryptoError.InvalidKey     this is a public key
    /// @failure CryptoError.MessageLength  `data` is not the modulus's length, or not below it
    /// @failure CryptoError.Padding        OAEP only: the ciphertext is not a valid encoding
    ///                                     under this key and label
    /// @failure CryptoError.Unsupported    OAEP's hash is not one this module has
    /// @failure CryptoError.NoEntropy      the platform would not supply randomness
    /// @see Rsa.Encrypt
    public Result<byte[], CryptoError> Decrypt(ReadOnlySpan<byte> data,
                                               RsaEncryptionPadding padding)
    {
        if (_privateKey is not RsaPrivateKey key)
            return Fail(CryptoError.InvalidKey);
        var number = ConvertToNumberBelowModulus(data);
        if (!number.Some)
            return Fail(CryptoError.MessageLength);

        if (padding.Mode == RsaEncryptionPaddingMode.Pkcs1)
        {
            if (_modulusLength < 11u)
                return Fail(CryptoError.MessageLength);
            byte[] encoded = try ApplyPrivateExponent(number.Value);
            byte[] message = DecodePkcs1Encryption(encoded, data, key);
            CryptographicOperations.ZeroMemory(encoded);
            return Ok(message);
        }

        IHashAlgorithm hash = try padding.OaepHashAlgorithm.CreateHashAlgorithm();
        if (_modulusLength < 2u * hash.HashSizeInBytes + 2u)
            return Fail(CryptoError.Padding);
        byte[] decrypted = try ApplyPrivateExponent(number.Value);
        var decoded = DecodeOaep(decrypted, hash, padding.OaepLabel);
        CryptographicOperations.ZeroMemory(decrypted);
        return decoded;
    }

    /// EME-OAEP decoding (RFC 8017 §7.1.2 step 3), in constant time up to the
    /// single branch on the combined verdict.
    Result<byte[], CryptoError> DecodeOaep(byte[] encoded, IHashAlgorithm hash, byte[] label)
    {
        nuint k = _modulusLength;
        nuint hashLength = hash.HashSizeInBytes;
        nuint blockLength = k - hashLength - 1u;

        hash.AppendData(label);
        byte[] labelHash = hash.GetHashAndReset();

        ReadOnlySpan<byte> maskedBlock = encoded[1u + hashLength:];
        byte[] seedMask = GenerateMask(hash, maskedBlock, hashLength);
        byte[] seed = new byte[hashLength];
        for (nuint i = 0u; i < hashLength; i++)
            seed[i] = (byte)(encoded[1u + i] ^ seedMask[i]);
        byte[] block = GenerateMask(hash, seed, blockLength);
        for (nuint i = 0u; i < blockLength; i++)
            block[i] ^= maskedBlock[i];

        ulong good = Limbs.MaskIfZero((ulong)encoded[0u]);
        ulong difference = 0ul;
        for (nuint i = 0u; i < hashLength; i++)
            difference |= (ulong)(block[i] ^ labelHash[i]);
        good &= Limbs.MaskIfZero(difference);

        // The first byte past the label hash that is not zero MUST be 01.
        ulong found = 0ul;
        ulong wrong = 0ul;
        ulong start = 0ul;
        for (nuint i = hashLength; i < blockLength; i++)
        {
            ulong value = (ulong)block[i];
            ulong isZero = Limbs.MaskIfZero(value);
            ulong first = ~found & ~isZero;
            start = ((ulong)(i + 1u) & first) | (start & ~first);
            wrong |= first & ~Limbs.MaskIfEqual(value, 1ul);
            found |= ~isZero;
        }
        good &= found & ~wrong;

        CryptographicOperations.ZeroMemory(seed);
        if (good == 0ul)
        {
            CryptographicOperations.ZeroMemory(block);
            return Fail(CryptoError.Padding);
        }

        byte[] message = block[(nuint)start:].ToArray();
        CryptographicOperations.ZeroMemory(block);
        return Ok(message);
    }

    /// EME-PKCS1-v1_5 decoding with implicit rejection, as OpenSSL 3.2 has
    /// it: a synthetic message from HMAC-SHA-256 under a key derived from
    /// `d` and the ciphertext stands in for a badly padded one, chosen by
    /// mask so the time is the same either way.
    byte[] DecodePkcs1Encryption(byte[] encoded, ReadOnlySpan<byte> ciphertext, RsaPrivateKey key)
    {
        nuint k = _modulusLength;

        byte[] exponent = Limbs.ToBigEndian(key.Exponent, k);
        byte[] exponentHash = Sha256.HashData(exponent);
        CryptographicOperations.ZeroMemory(exponent);
        byte[] derivationKey = new Hmac(new Sha256(), exponentHash).ComputeHash(ciphertext);
        CryptographicOperations.ZeroMemory(exponentHash);

        byte[] synthetic = ComputeRejectionBytes(derivationKey, "message", k);
        byte[] candidates = ComputeRejectionBytes(derivationKey, "length", 256u);
        CryptographicOperations.ZeroMemory(derivationKey);

        // The last of 128 candidate lengths that is short enough, each masked
        // to the bits the longest possible message needs.
        ulong longest = (ulong)(k - 10u);
        ulong spread = longest;
        spread |= spread >> 1;
        spread |= spread >> 2;
        spread |= spread >> 4;
        spread |= spread >> 8;
        ulong syntheticLength = 0ul;
        for (nuint i = 0u; i < 256u; i += 2u)
        {
            ulong candidate = (((ulong)candidates[i] << 8) | (ulong)candidates[i + 1u]) & spread;
            ulong shorter = Limbs.MaskFromBit((candidate - longest) >> 63);
            syntheticLength = (candidate & shorter) | (syntheticLength & ~shorter);
        }

        ulong good = Limbs.MaskIfZero((ulong)encoded[0u]) &
                     Limbs.MaskIfEqual((ulong)encoded[1u], 2ul);
        ulong found = 0ul;
        ulong separator = 0ul;
        for (nuint i = 2u; i < k; i++)
        {
            ulong isZero = Limbs.MaskIfZero((ulong)encoded[i]);
            ulong first = ~found & isZero;
            separator = ((ulong)i & first) | (separator & ~first);
            found |= isZero;
        }

        // At least eight bytes of padding; no separator leaves it at zero.
        good &= ~Limbs.MaskFromBit((separator - 10ul) >> 63);

        ulong start = ((separator + 1ul) & good) | (((ulong)k - syntheticLength) & ~good);
        nuint from = (nuint)start;
        byte[] message = new byte[k - from];
        byte keep = (byte)(good & 0xFFul);
        for (nuint i = from; i < k; i++)
            message[i - from] = (byte)((encoded[i] & keep) | (synthetic[i] & ~keep));

        CryptographicOperations.ZeroMemory(synthetic);
        return message;
    }

    /// The pseudo-random function implicit rejection draws from: HMAC-SHA-256
    /// over a two-byte counter, `label`, and the output length in bits.
    static byte[] ComputeRejectionBytes(byte[] key, String label, nuint length)
    {
        var mac = new Hmac(new Sha256(), key);
        byte[] labelBytes = label.ToBytes();
        nuint bits = length * 8u;
        byte[] bitLength = [(byte)((bits >> 8) & 0xFFu), (byte)(bits & 0xFFu)];
        byte[] output = new byte[length];
        byte[] counter = new byte[2u];
        nuint filled = 0u;
        uint index = 0u;
        while (filled < length)
        {
            counter[0u] = (byte)((index >> 8) & 0xFFu);
            counter[1u] = (byte)(index & 0xFFu);
            mac.AppendData(counter);
            mac.AppendData(labelBytes);
            mac.AppendData(bitLength);
            byte[] block = mac.GetHashAndReset();
            nuint take = length - filled < block.Length ? length - filled : block.Length;
            block[:take].CopyTo(output[filled:]);
            filled += take;
            index++;
        }
        return output;
    }
}
