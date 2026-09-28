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

// ============================================================ key agreement

/// X25519 (RFC 7748): Diffie-Hellman over Curve25519, which is what TLS 1.3,
/// SSH, WireGuard and Signal agree keys with.
///
/// ```csharp
/// byte[] mine = X25519.GeneratePrivateKey();
/// byte[] shared = try X25519.DeriveSharedSecret(mine, theirPublicKey);
/// byte[] key = try Hkdf.DeriveKey(new Sha256(), shared, salt, info, 32u);
/// ```
///
/// Every key is 32 bytes, and so is the shared secret. **The shared secret is
/// not a key.** It is a point on a curve, not uniformly random bytes, and it
/// MUST go through a key derivation such as `Hkdf` before it keys anything.
///
/// .NET has no X25519; `ECDiffieHellman` there is over the NIST curves. The
/// shape here is the RFC's: a private key is any 32 bytes, clamped as it is
/// used, and a public key is the u-coordinate of a point.
///
/// **Constant time.** The Montgomery ladder runs 255 steps whatever the key,
/// and each step's swap is a mask rather than a branch. The only test on the
/// result is the all-zero check, and what it reveals the failure reveals
/// anyway.
public static class X25519
{
    /// The length of a private key.
    ///
    /// @value thirty-two bytes.
    public const nuint PrivateKeySize = 32u;

    /// The length of a public key.
    ///
    /// @value thirty-two bytes.
    public const nuint PublicKeySize = 32u;

    /// The length of a shared secret.
    ///
    /// @value thirty-two bytes.
    public const nuint SharedSecretSize = 32u;

    /// A new private key: 32 bytes from `RandomNumberGenerator`.
    ///
    /// Aborts if the platform supplies no entropy, as
    /// `RandomNumberGenerator.GetBytes` does.
    public static byte[] GeneratePrivateKey() => RandomNumberGenerator.GetBytes(PrivateKeySize);

    /// The public key that goes with `privateKey`: the private key times the
    /// base point, whose u-coordinate is 9.
    ///
    /// @param privateKey  thirty-two bytes, clamped as they are used
    /// @failure CryptoError.KeyLength  `privateKey` is not `PrivateKeySize` long
    public static Result<byte[], CryptoError> GetPublicKey(ReadOnlySpan<byte> privateKey)
    {
        if (privateKey.Length != PrivateKeySize)
            return Fail(CryptoError.KeyLength);

        byte[] basePoint = new byte[32u];
        basePoint[0u] = 9;
        return Ok(MultiplyScalar(privateKey, basePoint));
    }

    /// The secret both sides arrive at: `privateKey` times the peer's public
    /// key.
    ///
    /// A public key of small order gives zero whatever the private key, which
    /// would let the peer choose the secret. RFC 7748 §6.1 has that checked,
    /// and it is refused here.
    ///
    /// @param privateKey  this side's key
    /// @param publicKey   the peer's key; its top bit is ignored, as the RFC
    ///                    requires
    /// @failure CryptoError.KeyLength         either key is not 32 bytes
    /// @failure CryptoError.InvalidKey        `publicKey` is of small order,
    ///                                        and the secret came out zero
    public static Result<byte[], CryptoError> DeriveSharedSecret(ReadOnlySpan<byte> privateKey,
                                                                 ReadOnlySpan<byte> publicKey)
    {
        if (privateKey.Length != PrivateKeySize || publicKey.Length != PublicKeySize)
            return Fail(CryptoError.KeyLength);

        byte[] shared = MultiplyScalar(privateKey, publicKey);

        uint any = 0u;
        for (nuint i = 0u; i < SharedSecretSize; i++)
            any |= (uint)shared[i];
        if (any == 0u)
            return Fail(CryptoError.InvalidKey);

        return Ok(shared);
    }

    /// The RFC's X25519 function: the clamped scalar times the point whose
    /// u-coordinate is `point`, by the Montgomery ladder of §5.
    static byte[] MultiplyScalar(ReadOnlySpan<byte> scalar, ReadOnlySpan<byte> point)
    {
        byte[] clamped = new byte[32u];
        for (nuint i = 0u; i < 32u; i++)
            clamped[i] = scalar[i];
        clamped[0u] = (byte)(clamped[0u] & 248u);
        clamped[31u] = (byte)((clamped[31u] & 127u) | 64u);

        Field25519 u = Field25519.FromBytes(point, 0u);
        Field25519 x2 = Field25519.One;
        Field25519 z2 = Field25519.Zero;
        Field25519 x3 = u;
        Field25519 z3 = Field25519.One;
        ulong swap = 0u;

        for (int bit = 254; bit >= 0; bit--)
        {
            ulong current = (ulong)(((uint)clamped[(nuint)(bit >> 3)] >> (bit & 7)) & 1u);
            swap ^= current;
            Field25519.ConditionalSwap(ref x2, ref x3, swap);
            Field25519.ConditionalSwap(ref z2, ref z3, swap);
            swap = current;

            Field25519 a = x2 + z2;
            Field25519 aa = a.Square();
            Field25519 b = x2 - z2;
            Field25519 bb = b.Square();
            Field25519 e = aa - bb;
            Field25519 c = x3 + z3;
            Field25519 d = x3 - z3;
            Field25519 da = d * a;
            Field25519 cb = c * b;
            x3 = (da + cb).Square();
            z3 = u * (da - cb).Square();
            x2 = aa * bb;

            // (A − 2)/4 for Curve25519's A = 486662.
            z2 = e * (aa + e.MultiplySmall(121665u));
        }

        Field25519.ConditionalSwap(ref x2, ref x3, swap);
        Field25519.ConditionalSwap(ref z2, ref z3, swap);

        CryptographicOperations.ZeroMemory(clamped);
        return (x2 * z2.Invert()).ToBytes();
    }
}
