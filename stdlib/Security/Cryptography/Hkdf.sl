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

/// HKDF (RFC 5869), which .NET has as `HKDF` and which is what to use when the
/// input is already a key rather than a password.
///
/// PBKDF2 is slow on purpose because a password has little entropy. HKDF is
/// fast on purpose because its input -- a Diffie-Hellman shared secret, a
/// master key -- already has plenty, and all that is wanted is to spread it
/// into several keys that reveal nothing about each other.
public static class Hkdf
{
    /// The extract step: a uniformly random key from input that is random but
    /// not uniform. `salt` may be empty, and then a block of zeros is used.
    ///
    /// @param hash      the HMAC's inner hash
    /// @param inputKey  the secret that is random but not uniform
    /// @param salt      a non-secret value, or empty for a block of zeros
    /// @see Hkdf.Expand
    public static byte[] Extract(IHashAlgorithm hash, byte[:] inputKey, byte[:] salt)
    {
        byte[] actual = salt.Length == 0u ? new byte[hash.HashSizeInBytes] : ToArray(salt);
        return new Hmac(hash, actual).ComputeHash(inputKey);
    }

    /// The expand step: as many bytes as asked for, bound to `info`.
    ///
    /// `info` is what separates one derived key from another -- "encryption"
    /// and "authentication" from the same secret -- and is the argument that
    /// makes this worth using over a bare hash.
    ///
    /// @param hash       the HMAC's inner hash, the same one `Extract` used
    /// @param pseudoKey  what `Extract` answered
    /// @param info       what separates one derived key from another
    /// @param length     how many bytes to derive, at most 255 digests' worth
    /// @failure CryptoError.Parameter  `length` is zero, or past 255 times the digest size
    /// @see Hkdf.Extract
    public static Result<byte[], CryptoError> Expand(IHashAlgorithm hash, byte[:] pseudoKey,
                                                     byte[:] info, nuint length)
    {
        nuint macSize = hash.HashSizeInBytes;
        if (length == 0u || length > macSize * 255u)
            return Fail(CryptoError.Parameter);

        var mac = new Hmac(hash, pseudoKey);
        byte[] derived = new byte[length];
        byte[] previous = new byte[0u];
        byte[] counter = new byte[1u];
        nuint filled = 0u;
        uint index = 1u;

        while (filled < length)
        {
            counter[0u] = (byte)index;
            mac.Reset();
            mac.AppendData(previous);
            mac.AppendData(info);
            mac.AppendData(counter);
            previous = mac.GetHashAndReset();

            nuint take = length - filled;
            if (take > macSize)
                take = macSize;

            for (nuint i = 0u; i < take; i++)
                derived[filled + i] = previous[i];

            filled += take;
            index++;
        }

        return Ok(derived);
    }

    /// Extract and expand together, which is how HKDF is nearly always used.
    ///
    /// @param hash      the HMAC's inner hash
    /// @param inputKey  the secret that is random but not uniform
    /// @param salt      a non-secret value, or empty for a block of zeros
    /// @param info      what separates one derived key from another
    /// @param length    how many bytes to derive, at most 255 digests' worth
    /// @failure CryptoError.Parameter  `length` is zero, or past 255 times the digest size
    /// @see Hkdf.Extract
    /// @see Hkdf.Expand
    public static Result<byte[], CryptoError> DeriveKey(IHashAlgorithm hash, byte[:] inputKey,
                                                        byte[:] salt, byte[:] info,
                                                        nuint length)
    {
        byte[] pseudoKey = Extract(hash, inputKey, salt);
        return Expand(hash, pseudoKey, info, length);
    }

    static byte[] ToArray(byte[:] data)
    {
        byte[] copy = new byte[data.Length];
        for (nuint i = 0u; i < data.Length; i++)
            copy[i] = data[i];
        return copy;
    }
}
