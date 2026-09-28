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

// ============================================================ stream cipher

/// ChaCha20, the stream cipher of RFC 8439: a 256-bit key, a 96-bit nonce and
/// a 32-bit block counter.
///
/// ```csharp
/// var cipher = try ChaCha20.FromKey(key);
/// var sealed = try cipher.ApplyKeystream(nonce, 1u, plaintext);
/// var opened = try cipher.ApplyKeystream(nonce, 1u, sealed);
/// ```
///
/// **This is encryption without authentication.** Anyone can flip a bit of
/// the ciphertext and the same bit of the plaintext flips. `ChaCha20Poly1305`
/// is the construction to use; this is here for a protocol that specifies the
/// bare cipher, and for the block vectors that pin it.
///
/// **It is constant time by construction.** The whole cipher is additions,
/// rotations and exclusive-ors on 32-bit words, with no table and no branch on
/// the key, which is why it is the software answer to AES's cache leak.
///
/// The nonce MUST NOT repeat under one key. A repeated nonce gives the same
/// keystream twice, and the XOR of two ciphertexts is then the XOR of the two
/// plaintexts.
///
/// @see ChaCha20Poly1305
public sealed class ChaCha20
{
    /// @value thirty-two bytes.
    public const nuint KeySize = 32u;

    /// @value twelve bytes.
    public const nuint NonceSize = 12u;

    /// What one counter value covers.
    ///
    /// @value sixty-four bytes.
    public const nuint BlockSize = 64u;

    private uint[] _key;

    ChaCha20(ReadOnlySpan<byte> key)
    {
        byte[] copy = key.ToArray();
        _key = new uint[8u];
        for (nuint i = 0u; i < 8u; i++)
            _key[i] = ReadLittleWord(copy, i * 4u);
        CryptographicOperations.ZeroMemory(copy);
    }

    /// A cipher under `key`, which must be 32 bytes.
    ///
    /// @failure CryptoError.KeyLength  `key` is not 32 bytes
    public static Result<ChaCha20, CryptoError> FromKey(ReadOnlySpan<byte> key)
    {
        if (key.Length != KeySize)
            return Fail(CryptoError.KeyLength);
        return Ok(new ChaCha20(key));
    }

    /// `input` exclusive-ored with the keystream that begins at block
    /// `counter`. The same call encrypts and decrypts.
    ///
    /// RFC 8439 starts at one when block zero has another use, as it has in
    /// the AEAD construction, and at zero otherwise.
    ///
    /// @param nonce    twelve bytes, never to repeat under this key
    /// @param counter  the block the keystream starts at
    /// @param input    the plaintext or the ciphertext
    /// @failure CryptoError.NonceLength  `nonce` is not twelve bytes
    /// @failure CryptoError.Parameter    `input` runs past block 2^32 - 1, where the counter
    ///                                   would wrap
    public Result<byte[], CryptoError> ApplyKeystream(ReadOnlySpan<byte> nonce, uint counter,
                                                      ReadOnlySpan<byte> input)
    {
        if (nonce.Length != NonceSize)
            return Fail(CryptoError.NonceLength);

        ulong blocks = ((ulong)input.Length + 63u) / 64u;
        ulong available = 0x100000000u - (ulong)counter;
        if (blocks > available)
            return Fail(CryptoError.Parameter);

        return Ok(TransformKeystream(nonce, counter, input));
    }

    /// `ApplyKeystream` without the checks. The nonce MUST be twelve bytes and
    /// the counter MUST NOT wrap.
    byte[] TransformKeystream(ReadOnlySpan<byte> nonce, uint counter, ReadOnlySpan<byte> input)
    {
        byte[] nonceBytes = nonce.ToArray();
        uint[] state = new uint[16u];
        state[0u] = 0x61707865u;
        state[1u] = 0x3320646Eu;
        state[2u] = 0x79622D32u;
        state[3u] = 0x6B206574u;
        for (nuint i = 0u; i < 8u; i++)
            state[4u + i] = _key[i];
        state[12u] = counter;
        state[13u] = ReadLittleWord(nonceBytes, 0u);
        state[14u] = ReadLittleWord(nonceBytes, 4u);
        state[15u] = ReadLittleWord(nonceBytes, 8u);

        uint[] working = new uint[16u];
        byte[] keystream = new byte[BlockSize];
        byte[] output = new byte[input.Length];

        for (nuint at = 0u; at < input.Length; at += BlockSize)
        {
            ComputeBlock(state, working, keystream);
            state[12u]++;

            nuint span = input.Length - at;
            if (span > BlockSize)
                span = BlockSize;

            for (nuint i = 0u; i < span; i++)
                output[at + i] = (byte)(input[at + i] ^ keystream[i]);
        }

        for (nuint i = 0u; i < 16u; i++)
        {
            state[i] = 0u;
            working[i] = 0u;
        }
        CryptographicOperations.ZeroMemory(keystream);
        return output;
    }

    /// Twenty rounds over `state`, added back to it, serialized little-endian
    /// into `into`. `working` is scratch of sixteen words.
    static void ComputeBlock(uint[] state, uint[] working, byte[] into)
    {
        for (nuint i = 0u; i < 16u; i++)
            working[i] = state[i];

        for (nuint round = 0u; round < 10u; round++)
        {
            MixQuarter(working, 0u, 4u, 8u, 12u);
            MixQuarter(working, 1u, 5u, 9u, 13u);
            MixQuarter(working, 2u, 6u, 10u, 14u);
            MixQuarter(working, 3u, 7u, 11u, 15u);

            MixQuarter(working, 0u, 5u, 10u, 15u);
            MixQuarter(working, 1u, 6u, 11u, 12u);
            MixQuarter(working, 2u, 7u, 8u, 13u);
            MixQuarter(working, 3u, 4u, 9u, 14u);
        }

        for (nuint i = 0u; i < 16u; i++)
            WriteLittleWord(into, i * 4u, working[i] + state[i]);
    }

    /// The quarter round of RFC 8439 §2.1, on four words of `x`.
    static void MixQuarter(uint[] x, nuint a, nuint b, nuint c, nuint d)
    {
        x[a] += x[b];
        x[d] = RotateLeft(x[d] ^ x[a], 16);
        x[c] += x[d];
        x[b] = RotateLeft(x[b] ^ x[c], 12);
        x[a] += x[b];
        x[d] = RotateLeft(x[d] ^ x[a], 8);
        x[c] += x[d];
        x[b] = RotateLeft(x[b] ^ x[c], 7);
    }
}
