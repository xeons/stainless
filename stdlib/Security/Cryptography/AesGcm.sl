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

// =========================================================== authenticated

/// AES-GCM: encryption and authentication in one pass, as .NET's `AesGcm`.
///
/// ```csharp
/// var box = try AesGcm.FromKey(key);
/// byte[] tag = new byte[16u];
/// var sealed = try box.Encrypt(nonce, plaintext, associated, tag);
/// var opened = try box.Decrypt(nonce, sealed, associated, tag);
/// ```
///
/// **The nonce must never repeat under one key.** GCM is CTR mode with a MAC
/// over the result, and a repeated nonce gives an attacker the XOR of two
/// plaintexts *and*, worse, the authentication key itself -- after which they
/// can forge. Twelve random bytes per message is fine up to about 2^32
/// messages; a counter is better where one can be kept.
///
/// `Decrypt` returns `CryptoError.AuthenticationFailed` and no plaintext when
/// the tag does not match. That is not a convenience: releasing unauthenticated
/// plaintext is the single most common way AEAD is misused, and a `Result` is
/// what makes it impossible here.
public sealed class AesGcm
{
    /// What the tag is, and the only length this produces. .NET allows 12 to
    /// 16; a shorter tag weakens forgery resistance by exactly the bits it
    /// drops, and no format here asks for one.
    ///
    /// @value sixteen bytes.
    public const nuint TagSize = 16u;

    /// What every protocol built on GCM uses, and the only length for which
    /// the nonce is used directly rather than hashed.
    ///
    /// @value twelve bytes.
    public const nuint NonceSize = 12u;

    private Aes _cipher;

    /// The hash key H, as two big-endian halves.
    private ulong _hashHigh;
    private ulong _hashLow;

    AesGcm(Aes cipher)
    {
        _cipher = cipher;

        byte[] key = new byte[16u];
        cipher.EncryptBlock(key, 0u);
        _hashHigh = ReadBigDoubleWord(key, 0u);
        _hashLow = ReadBigDoubleWord(key, 8u);
        CryptographicOperations.ZeroMemory(key);
    }

    /// A GCM box under `key`, which must be 16, 24 or 32 bytes.
    ///
    /// @failure CryptoError.KeyLength  `key` is not 16, 24 or 32 bytes
    public static Result<AesGcm, CryptoError> FromKey(ReadOnlySpan<byte> key)
    {
        var cipher = Aes.FromKey(key);
        if (!cipher.Ok)
            return Fail(cipher.Error);
        return Ok(new AesGcm(cipher.Value));
    }

    /// The ciphertext, with the tag written into `tag`.
    ///
    /// `associatedData` is authenticated and not encrypted -- a message header,
    /// a record number, anything the recipient must be sure of and that is not
    /// secret. Pass an empty array when there is none.
    ///
    /// @param nonce           never to repeat under this key; twelve bytes is what every
    ///                        protocol uses
    /// @param plaintext       the message to encipher
    /// @param associatedData  authenticated and not encrypted; empty when there is none
    /// @param tag             a `TagSize` array the tag is written into
    /// @failure CryptoError.NonceLength  `nonce` is empty
    /// @failure CryptoError.TagLength    `tag` is not `TagSize` long
    /// @see AesGcm.Decrypt
    public Result<byte[], CryptoError> Encrypt(ReadOnlySpan<byte> nonce, ReadOnlySpan<byte> plaintext,
                                               ReadOnlySpan<byte> associatedData, byte[] tag)
    {
        if (nonce.Length == 0u)
            return Fail(CryptoError.NonceLength);
        if (tag.Length != TagSize)
            return Fail(CryptoError.TagLength);

        byte[] counter = ComputeInitialCounter(nonce);
        byte[] keystream = new byte[16u];
        for (nuint i = 0u; i < 16u; i++)
            keystream[i] = counter[i];

        Aes.IncrementCounter(counter, 12u);
        var enciphered = _cipher.ApplyCounter(plaintext, counter, 12u);
        if (!enciphered.Ok)
            return Fail(enciphered.Error);

        byte[] ciphertext = enciphered.Value;
        byte[] computed = ComputeTag(associatedData, ciphertext, keystream);
        for (nuint i = 0u; i < TagSize; i++)
            tag[i] = computed[i];

        return Ok(ciphertext);
    }

    /// The plaintext, or `AuthenticationFailed` and nothing.
    ///
    /// @param nonce           the one the message was enciphered under
    /// @param ciphertext      the message to open
    /// @param associatedData  the same bytes the sender authenticated
    /// @param tag             the tag the sender sent
    /// @failure CryptoError.NonceLength           `nonce` is empty
    /// @failure CryptoError.TagLength             `tag` is not `TagSize` long
    /// @failure CryptoError.AuthenticationFailed  the tag does not match, and no plaintext is
    ///                                            returned
    /// @see AesGcm.Encrypt
    public Result<byte[], CryptoError> Decrypt(ReadOnlySpan<byte> nonce, ReadOnlySpan<byte> ciphertext,
                                               ReadOnlySpan<byte> associatedData, ReadOnlySpan<byte> tag)
    {
        if (nonce.Length == 0u)
            return Fail(CryptoError.NonceLength);
        if (tag.Length != TagSize)
            return Fail(CryptoError.TagLength);

        byte[] counter = ComputeInitialCounter(nonce);
        byte[] keystream = new byte[16u];
        for (nuint i = 0u; i < 16u; i++)
            keystream[i] = counter[i];

        byte[] expected = ComputeTag(associatedData, ciphertext, keystream);
        if (!CryptographicOperations.FixedTimeEquals(expected, tag))
            return Fail(CryptoError.AuthenticationFailed);

        Aes.IncrementCounter(counter, 12u);
        var deciphered = _cipher.ApplyCounter(ciphertext, counter, 12u);
        if (!deciphered.Ok)
            return Fail(deciphered.Error);

        return Ok(deciphered.Value);
    }

    /// J0: the nonce and a one when the nonce is twelve bytes, and GHASH of
    /// the nonce otherwise -- which is the standard's rule and the reason
    /// twelve is the length everything uses.
    byte[] ComputeInitialCounter(ReadOnlySpan<byte> nonce)
    {
        byte[] counter = new byte[16u];

        if (nonce.Length == NonceSize)
        {
            for (nuint i = 0u; i < NonceSize; i++)
                counter[i] = nonce[i];
            counter[15u] = 1;
            return counter;
        }

        ulong high = 0u;
        ulong low = 0u;
        UpdateGhash(ref high, ref low, nonce);

        byte[] lengths = new byte[16u];
        WriteBigDoubleWord(lengths, 8u, (ulong)nonce.Length * 8u);
        UpdateGhash(ref high, ref low, lengths);

        WriteBigDoubleWord(counter, 0u, high);
        WriteBigDoubleWord(counter, 8u, low);
        return counter;
    }

    /// GHASH over the associated data and the ciphertext, enciphered under the
    /// first counter block. That last step is what stops GHASH -- which is a
    /// keyed hash and not a MAC on its own -- from being invertible.
    byte[] ComputeTag(ReadOnlySpan<byte> associatedData, ReadOnlySpan<byte> ciphertext, byte[] keystream)
    {
        ulong high = 0u;
        ulong low = 0u;
        UpdateGhash(ref high, ref low, associatedData);
        UpdateGhash(ref high, ref low, ciphertext);

        byte[] lengths = new byte[16u];
        WriteBigDoubleWord(lengths, 0u, (ulong)associatedData.Length * 8u);
        WriteBigDoubleWord(lengths, 8u, (ulong)ciphertext.Length * 8u);
        UpdateGhash(ref high, ref low, lengths);

        byte[] mask = new byte[16u];
        for (nuint i = 0u; i < 16u; i++)
            mask[i] = keystream[i];
        _cipher.EncryptBlock(mask, 0u);

        byte[] tag = new byte[TagSize];
        WriteBigDoubleWord(tag, 0u, high);
        WriteBigDoubleWord(tag, 8u, low);
        for (nuint i = 0u; i < TagSize; i++)
            tag[i] = (byte)(tag[i] ^ mask[i]);

        CryptographicOperations.ZeroMemory(mask);
        return tag;
    }

    /// `data` folded into the accumulator `high`:`low` a block at a time, the
    /// last block zero-padded.
    void UpdateGhash(ref ulong high, ref ulong low, ReadOnlySpan<byte> data)
    {
        ulong keyHigh = _hashHigh;
        ulong keyLow = _hashLow;
        ulong keyHighReversed = ReverseBits(keyHigh);
        ulong keyLowReversed = ReverseBits(keyLow);

        for (nuint at = 0u; at < data.Length; at += 16u)
        {
            ulong first = 0u;
            ulong second = 0u;

            if (data.Length - at >= 16u)
            {
                for (nuint i = 0u; i < 8u; i++)
                {
                    first = (first << 8) | (ulong)data[at + i];
                    second = (second << 8) | (ulong)data[at + 8u + i];
                }
            }
            else
            {
                nuint span = data.Length - at;
                for (nuint i = 0u; i < 16u; i++)
                {
                    ulong octet = 0u;
                    if (i < span)
                        octet = (ulong)data[at + i];

                    if (i < 8u)
                        first = (first << 8) | octet;
                    else
                        second = (second << 8) | octet;
                }
            }

            high ^= first;
            low ^= second;
            MultiplyGhash(ref high, ref low, keyHigh, keyLow, keyHighReversed, keyLowReversed);
        }
    }

    /// `high`:`low` times H in GF(2^128), as BearSSL's `ghash_ctmul64` does it.
    ///
    /// Karatsuba over carry-less 64-bit products. The high half of a product
    /// is the low half of the product of the bit-reversed operands, reversed,
    /// so every multiply keeps only its low 64 bits. No table and no branch
    /// touches H or the data.
    static void MultiplyGhash(ref ulong high, ref ulong low, ulong keyHigh, ulong keyLow,
                              ulong keyHighReversed, ulong keyLowReversed)
    {
        ulong y1 = high;
        ulong y0 = low;
        ulong y2 = y0 ^ y1;
        ulong y1r = ReverseBits(y1);
        ulong y0r = ReverseBits(y0);
        ulong y2r = y0r ^ y1r;
        ulong h2 = keyLow ^ keyHigh;
        ulong h2r = keyLowReversed ^ keyHighReversed;

        ulong z0 = MultiplyCarryless(y0, keyLow);
        ulong z1 = MultiplyCarryless(y1, keyHigh);
        ulong z2 = MultiplyCarryless(y2, h2);
        ulong z0h = MultiplyCarryless(y0r, keyLowReversed);
        ulong z1h = MultiplyCarryless(y1r, keyHighReversed);
        ulong z2h = MultiplyCarryless(y2r, h2r);
        z2 ^= z0 ^ z1;
        z2h ^= z0h ^ z1h;
        z0h = ReverseBits(z0h) >> 1;
        z1h = ReverseBits(z1h) >> 1;
        z2h = ReverseBits(z2h) >> 1;

        // The 256-bit product, lowest word first, shifted left by one because
        // GCM's bit order is reflected.
        ulong v0 = z0;
        ulong v1 = z0h ^ z2;
        ulong v2 = z1 ^ z2h;
        ulong v3 = z1h;

        v3 = (v3 << 1) | (v2 >> 63);
        v2 = (v2 << 1) | (v1 >> 63);
        v1 = (v1 << 1) | (v0 >> 63);
        v0 = v0 << 1;

        // Reduction by x^128 + x^7 + x^2 + x + 1, in the reflected order.
        v2 ^= v0 ^ (v0 >> 1) ^ (v0 >> 2) ^ (v0 >> 7);
        v1 ^= (v0 << 63) ^ (v0 << 62) ^ (v0 << 57);
        v3 ^= v1 ^ (v1 >> 1) ^ (v1 >> 2) ^ (v1 >> 7);
        v2 ^= (v1 << 63) ^ (v1 << 62) ^ (v1 << 57);

        high = v3;
        low = v2;
    }

    /// The low 64 bits of the carry-less product of `x` and `y`.
    ///
    /// Integer multiplies with holes: each operand is split four ways, every
    /// fourth bit apiece, so the carries of each product land in bits that the
    /// masks at the end discard. It relies on a multiply whose time does not
    /// depend on its operands, which every x64 and ARMv8 core has.
    static ulong MultiplyCarryless(ulong x, ulong y)
    {
        ulong x0 = x & 0x1111111111111111u;
        ulong x1 = x & 0x2222222222222222u;
        ulong x2 = x & 0x4444444444444444u;
        ulong x3 = x & 0x8888888888888888u;
        ulong y0 = y & 0x1111111111111111u;
        ulong y1 = y & 0x2222222222222222u;
        ulong y2 = y & 0x4444444444444444u;
        ulong y3 = y & 0x8888888888888888u;

        ulong z0 = (x0 * y0) ^ (x1 * y3) ^ (x2 * y2) ^ (x3 * y1);
        ulong z1 = (x0 * y1) ^ (x1 * y0) ^ (x2 * y3) ^ (x3 * y2);
        ulong z2 = (x0 * y2) ^ (x1 * y1) ^ (x2 * y0) ^ (x3 * y3);
        ulong z3 = (x0 * y3) ^ (x1 * y2) ^ (x2 * y1) ^ (x3 * y0);

        return (z0 & 0x1111111111111111u) | (z1 & 0x2222222222222222u) |
               (z2 & 0x4444444444444444u) | (z3 & 0x8888888888888888u);
    }

    /// `value` with its 64 bits in the opposite order.
    static ulong ReverseBits(ulong value)
    {
        ulong x = value;
        x = ((x & 0x5555555555555555u) << 1) | ((x >> 1) & 0x5555555555555555u);
        x = ((x & 0x3333333333333333u) << 2) | ((x >> 2) & 0x3333333333333333u);
        x = ((x & 0x0F0F0F0F0F0F0F0Fu) << 4) | ((x >> 4) & 0x0F0F0F0F0F0F0F0Fu);
        x = ((x & 0x00FF00FF00FF00FFu) << 8) | ((x >> 8) & 0x00FF00FF00FF00FFu);
        x = ((x & 0x0000FFFF0000FFFFu) << 16) | ((x >> 16) & 0x0000FFFF0000FFFFu);
        return RotateLeft(x, 32);
    }
}
