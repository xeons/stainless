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

/// Elliptic-curve Diffie-Hellman over P-256 or P-384: SP 800-56A's ECC CDH
/// primitive, in .NET's `ECDiffieHellman` shape.
///
/// ```csharp
/// var mine = try ECDiffieHellman.Create(ECCurve.NamedCurves.NistP256);
/// send(mine.PublicKey);
/// byte[] shared = try mine.DeriveRawSecretAgreement(received);
/// ```
///
/// **Points travel in SEC 1 form**, the one TLS key shares and X9.63 use:
/// `PublicKey` is `04 X Y`, and a point from the other party may be that or
/// compressed. Every such point is checked before it is used — on the curve,
/// not at infinity, each coordinate below `p` — so an invalid-curve attack
/// has nothing to work with.
///
/// **The secret is the shared point's x coordinate, raw.** It is not a key:
/// run it through a KDF, as TLS 1.3 does with HKDF, or ask for one of the
/// `DeriveKeyFrom*` forms. The scalar multiplication behind it is constant
/// time.
///
/// @see ECDsa
public sealed class ECDiffieHellman
{
    private EcKey _key;

    ECDiffieHellman(EcKey key)
    {
        _key = key;
    }

    /// A new key on P-256.
    ///
    /// @failure CryptoError.NoEntropy  the platform supplied no random bytes
    public static Result<ECDiffieHellman, CryptoError> Create() =>
        Create(ECCurve.NamedCurves.NistP256);

    /// A new key on `curve`.
    ///
    /// @param curve  P-256 or P-384
    /// @failure CryptoError.Unsupported  `curve` is another curve
    /// @failure CryptoError.NoEntropy    the platform supplied no random bytes
    public static Result<ECDiffieHellman, CryptoError> Create(ECCurve curve)
    {
        var key = EcKey.Generate(curve);
        if (!key.Ok)
            return Fail(key.Error);
        return Ok(new ECDiffieHellman(key.Value));
    }

    /// The key `parameters` describe: private when `D` is set, and public
    /// otherwise.
    ///
    /// @param parameters  the curve, the point and perhaps the scalar
    /// @failure CryptoError.Unsupported   the curve is not P-256 or P-384
    /// @failure CryptoError.InvalidPoint  the point is not on the curve
    /// @failure CryptoError.InvalidKey    the scalar is not in `[1, n - 1]` or does not
    ///                                    give the point
    public static Result<ECDiffieHellman, CryptoError> Create(ECParameters parameters)
    {
        var key = EcKey.Import(parameters);
        if (!key.Ok)
            return Fail(key.Error);
        return Ok(new ECDiffieHellman(key.Value));
    }

    /// The size of the key in bits: 256 or 384.
    public nuint KeySize => _key.KeySize;

    /// The public point in SEC 1's uncompressed form, `04 X Y`: 65 bytes for
    /// P-256 and 97 for P-384. What a TLS key share carries.
    public byte[] PublicKey => _key.PublicKey[0u:].ToArray();

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

    // --------------------------------------------------------------- agreement

    /// The shared secret with the holder of `otherPartyPublicKey`: the x
    /// coordinate of `d * Q`, as wide as the field.
    ///
    /// @param otherPartyPublicKey  the other party's point in SEC 1 form, on this
    ///                             key's curve
    /// @failure CryptoError.InvalidPoint  the point is malformed, on another curve, or
    ///                                    not on the curve at all
    /// @failure CryptoError.InvalidKey    this is a public key, or the result is the
    ///                                    point at infinity
    /// @see ECDiffieHellman.PublicKey
    public Result<byte[], CryptoError> DeriveRawSecretAgreement(
        ReadOnlySpan<byte> otherPartyPublicKey) => _key.DeriveSharedSecret(otherPartyPublicKey);

    /// `hashAlgorithm` over the shared secret: .NET's `DeriveKeyFromHash` with
    /// nothing before or after it.
    ///
    /// @param otherPartyPublicKey  the other party's point in SEC 1 form
    /// @param hashAlgorithm        the hash
    /// @failure CryptoError.InvalidPoint  the point does not check
    /// @failure CryptoError.InvalidKey    this is a public key, or the result is infinity
    /// @failure CryptoError.Unsupported   `hashAlgorithm` is the zero value
    public Result<byte[], CryptoError> DeriveKeyFromHash(ReadOnlySpan<byte> otherPartyPublicKey,
                                                         HashAlgorithmName hashAlgorithm) =>
        DeriveKeyFromHash(otherPartyPublicKey, hashAlgorithm, new byte[0u], new byte[0u]);

    /// `hashAlgorithm` over `secretPrepend`, the shared secret and
    /// `secretAppend`.
    ///
    /// @param otherPartyPublicKey  the other party's point in SEC 1 form
    /// @param hashAlgorithm        the hash
    /// @param secretPrepend        what to hash before the secret
    /// @param secretAppend         what to hash after it
    /// @failure CryptoError.InvalidPoint  the point does not check
    /// @failure CryptoError.InvalidKey    this is a public key, or the result is infinity
    /// @failure CryptoError.Unsupported   `hashAlgorithm` is the zero value
    public Result<byte[], CryptoError> DeriveKeyFromHash(ReadOnlySpan<byte> otherPartyPublicKey,
                                                         HashAlgorithmName hashAlgorithm,
                                                         ReadOnlySpan<byte> secretPrepend,
                                                         ReadOnlySpan<byte> secretAppend)
    {
        var hash = hashAlgorithm.CreateHashAlgorithm();
        if (!hash.Ok)
            return Fail(hash.Error);
        var secret = _key.DeriveSharedSecret(otherPartyPublicKey);
        if (!secret.Ok)
            return Fail(secret.Error);

        hash.Value.AppendData(secretPrepend);
        hash.Value.AppendData(secret.Value);
        hash.Value.AppendData(secretAppend);
        CryptographicOperations.ZeroMemory(secret.Value);
        return Ok(hash.Value.GetHashAndReset());
    }

    /// HMAC under `hmacKey` over the shared secret.
    ///
    /// @param otherPartyPublicKey  the other party's point in SEC 1 form
    /// @param hashAlgorithm        the hash under the HMAC
    /// @param hmacKey              the HMAC key
    /// @failure CryptoError.InvalidPoint  the point does not check
    /// @failure CryptoError.InvalidKey    this is a public key, or the result is infinity
    /// @failure CryptoError.Unsupported   `hashAlgorithm` is the zero value
    public Result<byte[], CryptoError> DeriveKeyFromHmac(ReadOnlySpan<byte> otherPartyPublicKey,
                                                         HashAlgorithmName hashAlgorithm,
                                                         ReadOnlySpan<byte> hmacKey) =>
        DeriveKeyFromHmac(otherPartyPublicKey, hashAlgorithm, hmacKey, new byte[0u], new byte[0u]);

    /// HMAC under `hmacKey` over `secretPrepend`, the shared secret and
    /// `secretAppend`.
    ///
    /// @param otherPartyPublicKey  the other party's point in SEC 1 form
    /// @param hashAlgorithm        the hash under the HMAC
    /// @param hmacKey              the HMAC key
    /// @param secretPrepend        what to authenticate before the secret
    /// @param secretAppend         what to authenticate after it
    /// @failure CryptoError.InvalidPoint  the point does not check
    /// @failure CryptoError.InvalidKey    this is a public key, or the result is infinity
    /// @failure CryptoError.Unsupported   `hashAlgorithm` is the zero value
    public Result<byte[], CryptoError> DeriveKeyFromHmac(ReadOnlySpan<byte> otherPartyPublicKey,
                                                         HashAlgorithmName hashAlgorithm,
                                                         ReadOnlySpan<byte> hmacKey,
                                                         ReadOnlySpan<byte> secretPrepend,
                                                         ReadOnlySpan<byte> secretAppend)
    {
        var hash = hashAlgorithm.CreateHashAlgorithm();
        if (!hash.Ok)
            return Fail(hash.Error);
        var secret = _key.DeriveSharedSecret(otherPartyPublicKey);
        if (!secret.Ok)
            return Fail(secret.Error);

        var mac = new Hmac(hash.Value, hmacKey);
        mac.AppendData(secretPrepend);
        mac.AppendData(secret.Value);
        mac.AppendData(secretAppend);
        CryptographicOperations.ZeroMemory(secret.Value);
        return Ok(mac.GetHashAndReset());
    }
}
