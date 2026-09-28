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
/// the key, which is also what makes it fast without hardware support.
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

        byte[] keystream = new byte[BlockSize];
        byte[] output = new byte[input.Length];

        for (nuint at = 0u; at < input.Length; at += BlockSize)
        {
            ComputeBlock(state, keystream);
            state[12u]++;

            nuint span = input.Length - at;
            if (span > BlockSize)
                span = BlockSize;

            for (nuint i = 0u; i < span; i++)
                output[at + i] = (byte)(input[at + i] ^ keystream[i]);
        }

        for (nuint i = 0u; i < 16u; i++)
            state[i] = 0u;

        CryptographicOperations.ZeroMemory(keystream);
        return output;
    }

    /// Twenty rounds over `state`, added back to it, serialized little-endian
    /// into `into`. The words are locals so they can live in registers.
    static void ComputeBlock(uint[] state, byte[] into)
    {
        uint x0 = state[0u];
        uint x1 = state[1u];
        uint x2 = state[2u];
        uint x3 = state[3u];
        uint x4 = state[4u];
        uint x5 = state[5u];
        uint x6 = state[6u];
        uint x7 = state[7u];
        uint x8 = state[8u];
        uint x9 = state[9u];
        uint x10 = state[10u];
        uint x11 = state[11u];
        uint x12 = state[12u];
        uint x13 = state[13u];
        uint x14 = state[14u];
        uint x15 = state[15u];

        for (nuint round = 0u; round < 10u; round++)
        {
            x0 += x4;
            x12 = RotateLeft(x12 ^ x0, 16);
            x8 += x12;
            x4 = RotateLeft(x4 ^ x8, 12);
            x0 += x4;
            x12 = RotateLeft(x12 ^ x0, 8);
            x8 += x12;
            x4 = RotateLeft(x4 ^ x8, 7);

            x1 += x5;
            x13 = RotateLeft(x13 ^ x1, 16);
            x9 += x13;
            x5 = RotateLeft(x5 ^ x9, 12);
            x1 += x5;
            x13 = RotateLeft(x13 ^ x1, 8);
            x9 += x13;
            x5 = RotateLeft(x5 ^ x9, 7);

            x2 += x6;
            x14 = RotateLeft(x14 ^ x2, 16);
            x10 += x14;
            x6 = RotateLeft(x6 ^ x10, 12);
            x2 += x6;
            x14 = RotateLeft(x14 ^ x2, 8);
            x10 += x14;
            x6 = RotateLeft(x6 ^ x10, 7);

            x3 += x7;
            x15 = RotateLeft(x15 ^ x3, 16);
            x11 += x15;
            x7 = RotateLeft(x7 ^ x11, 12);
            x3 += x7;
            x15 = RotateLeft(x15 ^ x3, 8);
            x11 += x15;
            x7 = RotateLeft(x7 ^ x11, 7);

            x0 += x5;
            x15 = RotateLeft(x15 ^ x0, 16);
            x10 += x15;
            x5 = RotateLeft(x5 ^ x10, 12);
            x0 += x5;
            x15 = RotateLeft(x15 ^ x0, 8);
            x10 += x15;
            x5 = RotateLeft(x5 ^ x10, 7);

            x1 += x6;
            x12 = RotateLeft(x12 ^ x1, 16);
            x11 += x12;
            x6 = RotateLeft(x6 ^ x11, 12);
            x1 += x6;
            x12 = RotateLeft(x12 ^ x1, 8);
            x11 += x12;
            x6 = RotateLeft(x6 ^ x11, 7);

            x2 += x7;
            x13 = RotateLeft(x13 ^ x2, 16);
            x8 += x13;
            x7 = RotateLeft(x7 ^ x8, 12);
            x2 += x7;
            x13 = RotateLeft(x13 ^ x2, 8);
            x8 += x13;
            x7 = RotateLeft(x7 ^ x8, 7);

            x3 += x4;
            x14 = RotateLeft(x14 ^ x3, 16);
            x9 += x14;
            x4 = RotateLeft(x4 ^ x9, 12);
            x3 += x4;
            x14 = RotateLeft(x14 ^ x3, 8);
            x9 += x14;
            x4 = RotateLeft(x4 ^ x9, 7);
        }

        WriteLittleWord(into, 0u, x0 + state[0u]);
        WriteLittleWord(into, 4u, x1 + state[1u]);
        WriteLittleWord(into, 8u, x2 + state[2u]);
        WriteLittleWord(into, 12u, x3 + state[3u]);
        WriteLittleWord(into, 16u, x4 + state[4u]);
        WriteLittleWord(into, 20u, x5 + state[5u]);
        WriteLittleWord(into, 24u, x6 + state[6u]);
        WriteLittleWord(into, 28u, x7 + state[7u]);
        WriteLittleWord(into, 32u, x8 + state[8u]);
        WriteLittleWord(into, 36u, x9 + state[9u]);
        WriteLittleWord(into, 40u, x10 + state[10u]);
        WriteLittleWord(into, 44u, x11 + state[11u]);
        WriteLittleWord(into, 48u, x12 + state[12u]);
        WriteLittleWord(into, 52u, x13 + state[13u]);
        WriteLittleWord(into, 56u, x14 + state[14u]);
        WriteLittleWord(into, 60u, x15 + state[15u]);
    }
}
