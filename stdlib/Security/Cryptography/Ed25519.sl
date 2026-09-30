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

import Standard.Bits;

// ================================================================ signing

/// Ed25519 (RFC 8032): signatures over edwards25519 with SHA-512, which is
/// what SSH, TLS 1.3, minisign and most new protocols sign with.
///
/// ```csharp
/// byte[] privateKey = Ed25519.GeneratePrivateKey();
/// byte[] publicKey = try Ed25519.GetPublicKey(privateKey);
/// byte[] signature = try Ed25519.Sign(privateKey, message);
/// bool genuine = Ed25519.Verify(publicKey, message, signature);
/// ```
///
/// This is pure Ed25519, the RFC's first variant: the message is signed as
/// it is, with no context string and no prehash. A private key is the RFC's
/// 32-byte seed, a public key 32 bytes and a signature 64. Signing is
/// deterministic, so the same key and message always give the same
/// signature and no randomness is needed to sign.
///
/// **Verification is strict and cofactorless.** A signature whose S is not
/// below the group order is refused, as is a public key that is not the one
/// canonical encoding of a point on the curve, and a public key of small
/// order -- one of the eight points that eight times is the identity. Such a
/// key has no secret behind it: under the identity, R = B and S = 1 sign
/// every message. RFC 8032 does not ask for that refusal and libsodium makes
/// it. The check is
/// [S]B = R + [k]A, the equation RFC 8032 §5.1.7 names as sufficient, rather
/// than the same multiplied through by the cofactor 8. The two differ only on
/// a signature crafted with a component of small order, which no honest
/// signer makes; a protocol that needs every implementation to agree on such
/// signatures must specify one or the other.
///
/// **Constant time where the data is secret.** Signing multiplies by a
/// secret scalar with a fixed window read by mask, and reduces and combines
/// scalars with fixed loops. Verification touches nothing secret and uses a
/// faster variable-time multiplication.
public static class Ed25519
{
    /// The length of a private key: the RFC's seed.
    ///
    /// @value thirty-two bytes.
    public const nuint PrivateKeySize = 32u;

    /// The length of a public key.
    ///
    /// @value thirty-two bytes.
    public const nuint PublicKeySize = 32u;

    /// The length of a signature: R, then S.
    ///
    /// @value sixty-four bytes.
    public const nuint SignatureSize = 64u;

    /// A new private key: 32 bytes from `RandomNumberGenerator`.
    ///
    /// Aborts if the platform supplies no entropy, as
    /// `RandomNumberGenerator.GetBytes` does.
    public static byte[] GeneratePrivateKey() => RandomNumberGenerator.GetBytes(PrivateKeySize);

    /// The public key that goes with `privateKey`.
    ///
    /// @param privateKey  the 32-byte seed
    /// @failure CryptoError.KeyLength  `privateKey` is not `PrivateKeySize` long
    public static Result<byte[], CryptoError> GetPublicKey(ReadOnlySpan<byte> privateKey)
    {
        if (privateKey.Length != PrivateKeySize)
            return Fail(CryptoError.KeyLength);

        byte[] expanded = Sha512.HashData(privateKey);
        byte[] scalar = ClampScalar(expanded);
        byte[] publicKey = Edwards25519Point.MultiplyScalar(Edwards25519Point.Base, scalar).Encode();

        CryptographicOperations.ZeroMemory(expanded);
        CryptographicOperations.ZeroMemory(scalar);
        return Ok(publicKey);
    }

    /// The 64-byte signature of `message` under `privateKey`.
    ///
    /// @param privateKey  the 32-byte seed
    /// @param message     the bytes to sign, of any length
    /// @failure CryptoError.KeyLength  `privateKey` is not `PrivateKeySize` long
    /// @see Ed25519.Verify
    public static Result<byte[], CryptoError> Sign(ReadOnlySpan<byte> privateKey,
                                                   ReadOnlySpan<byte> message)
    {
        if (privateKey.Length != PrivateKeySize)
            return Fail(CryptoError.KeyLength);

        byte[] expanded = Sha512.HashData(privateKey);
        byte[] scalar = ClampScalar(expanded);
        Edwards25519Point basePoint = Edwards25519Point.Base;
        byte[] publicKey = Edwards25519Point.MultiplyScalar(basePoint, scalar).Encode();

        // The nonce is a hash of the key's second half and the message, which
        // is what makes signing deterministic and a repeated nonce impossible.
        var hash = new Sha512();
        hash.AppendData(expanded[32u:]);
        hash.AppendData(message);
        byte[] nonce = Scalar25519.ReduceWide(hash.GetHashAndReset());
        byte[] commitment = Edwards25519Point.MultiplyScalar(basePoint, nonce).Encode();

        hash.AppendData(commitment);
        hash.AppendData(publicKey);
        hash.AppendData(message);
        byte[] challenge = Scalar25519.ReduceWide(hash.GetHashAndReset());
        byte[] response = Scalar25519.MultiplyAdd(challenge, scalar, nonce);

        byte[] signature = new byte[SignatureSize];
        for (nuint i = 0u; i < 32u; i++)
        {
            signature[i] = commitment[i];
            signature[32u + i] = response[i];
        }

        CryptographicOperations.ZeroMemory(expanded);
        CryptographicOperations.ZeroMemory(scalar);
        CryptographicOperations.ZeroMemory(nonce);
        return Ok(signature);
    }

    /// Whether `signature` is `publicKey`'s signature of `message`.
    ///
    /// A key or signature of the wrong length answers false, as does a key
    /// that is not a canonical point encoding, a key of small order and a
    /// signature whose S is not below the group order. The equation checked is the cofactorless one;
    /// the type's own documentation says what that means.
    ///
    /// @param publicKey  the signer's 32-byte key
    /// @param message    the bytes that were signed
    /// @param signature  the 64 bytes `Sign` produced
    /// @returns true only for a valid signature
    /// @see Ed25519.Sign
    public static bool Verify(ReadOnlySpan<byte> publicKey, ReadOnlySpan<byte> message,
                              ReadOnlySpan<byte> signature)
    {
        if (publicKey.Length != PublicKeySize || signature.Length != SignatureSize)
            return false;

        ReadOnlySpan<byte> commitment = signature[0u:32u];
        ReadOnlySpan<byte> response = signature[32u:];
        if (!Scalar25519.IsCanonical(response))
            return false;

        if (!Edwards25519Point.TryDecode(publicKey, out Edwards25519Point signer))
            return false;
        if (signer.IsOfSmallOrder())
            return false;

        var hash = new Sha512();
        hash.AppendData(commitment);
        hash.AppendData(publicKey);
        hash.AppendData(message);
        byte[] challenge = Scalar25519.ReduceWide(hash.GetHashAndReset());

        // [S]B − [k]A is R exactly when the signature is valid, and comparing
        // encodings refuses a non-canonical R with no decoding at all.
        Edwards25519Point expected =
            Edwards25519Point.MultiplyDoubleVariableTime(challenge, -signer, response);
        return CryptographicOperations.FixedTimeEquals(expected.Encode(), commitment);
    }

    /// The first half of the expanded key, clamped as RFC 8032 §5.1.5 says:
    /// the low three bits cleared so the scalar is a multiple of the
    /// cofactor, the top bit cleared and the one below it set.
    static byte[] ClampScalar(byte[] expanded)
    {
        byte[] scalar = new byte[32u];
        for (nuint i = 0u; i < 32u; i++)
            scalar[i] = expanded[i];
        scalar[0u] = (byte)(scalar[0u] & 248u);
        scalar[31u] = (byte)((scalar[31u] & 127u) | 64u);
        return scalar;
    }
}
