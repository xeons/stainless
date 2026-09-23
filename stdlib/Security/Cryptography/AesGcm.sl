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

    Aes _cipher;
    byte[] _hashKey;

    AesGcm(Aes cipher)
    {
        _cipher = cipher;
        _hashKey = new byte[16u];
        cipher.EncryptBlock(_hashKey, 0u);
    }

    /// A GCM box under `key`, which must be 16, 24 or 32 bytes.
    ///
    /// @failure CryptoError.KeyLength  `key` is not 16, 24 or 32 bytes
    public static Result<AesGcm, CryptoError> FromKey(byte[:] key)
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
    public Result<byte[], CryptoError> Encrypt(byte[:] nonce, byte[:] plaintext,
                                               byte[:] associatedData, byte[] tag)
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
    public Result<byte[], CryptoError> Decrypt(byte[:] nonce, byte[:] ciphertext,
                                               byte[:] associatedData, byte[:] tag)
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
    byte[] ComputeInitialCounter(byte[:] nonce)
    {
        byte[] counter = new byte[16u];

        if (nonce.Length == NonceSize)
        {
            for (nuint i = 0u; i < NonceSize; i++)
                counter[i] = nonce[i];
            counter[15u] = 1;
            return counter;
        }

        UpdateGhash(counter, nonce);
        byte[] lengths = new byte[16u];
        WriteLength(lengths, 8u, (ulong)nonce.Length * 8u);
        UpdateGhash(counter, lengths);
        return counter;
    }

    /// GHASH over the associated data and the ciphertext, enciphered under the
    /// first counter block. That last step is what stops GHASH -- which is a
    /// keyed hash and not a MAC on its own -- from being invertible.
    byte[] ComputeTag(byte[:] associatedData, byte[:] ciphertext, byte[] keystream)
    {
        byte[] accumulator = new byte[16u];
        UpdateGhash(accumulator, associatedData);
        UpdateGhash(accumulator, ciphertext);

        byte[] lengths = new byte[16u];
        WriteLength(lengths, 0u, (ulong)associatedData.Length * 8u);
        WriteLength(lengths, 8u, (ulong)ciphertext.Length * 8u);
        UpdateGhash(accumulator, lengths);

        byte[] mask = new byte[16u];
        for (nuint i = 0u; i < 16u; i++)
            mask[i] = keystream[i];
        _cipher.EncryptBlock(mask, 0u);

        byte[] tag = new byte[TagSize];
        for (nuint i = 0u; i < TagSize; i++)
            tag[i] = (byte)(accumulator[i] ^ mask[i]);

        return tag;
    }

    /// `data` folded into the accumulator, a block at a time and zero-padded.
    void UpdateGhash(byte[] accumulator, byte[:] data)
    {
        byte[] block = new byte[16u];

        for (nuint at = 0u; at < data.Length; at += 16u)
        {
            nuint span = data.Length - at;
            if (span > 16u)
                span = 16u;

            for (nuint i = 0u; i < 16u; i++)
                block[i] = 0;

            for (nuint i = 0u; i < span; i++)
                block[i] = data[at + i];

            for (nuint i = 0u; i < 16u; i++)
                accumulator[i] = (byte)(accumulator[i] ^ block[i]);

            MultiplyGhash(accumulator, _hashKey);
        }
    }

    /// `left` times `right` in GF(2^128), bit by bit.
    ///
    /// The tabulated version is four times faster and leaks through the cache
    /// the way an AES table does; this one is the shift-and-add definition,
    /// which is what a reference implementation should be. 128 iterations per
    /// block is the price.
    static void MultiplyGhash(byte[] left, byte[] right)
    {
        byte[] product = new byte[16u];
        byte[] running = new byte[16u];
        for (nuint i = 0u; i < 16u; i++)
            running[i] = right[i];

        for (nuint bit = 0u; bit < 128u; bit++)
        {
            nuint at = bit / 8u;
            uint mask = (uint)(0x80u >> (uint)(bit % 8u));

            if (((uint)left[at] & mask) != 0u)
            {
                for (nuint i = 0u; i < 16u; i++)
                    product[i] = (byte)(product[i] ^ running[i]);
            }

            bool odd = (running[15u] & 1u) != 0u;
            for (nuint i = 16u; i > 0u; i--)
            {
                nuint index = i - 1u;
                uint shifted = (uint)running[index] >> 1;
                if (index > 0u)
                    shifted |= ((uint)running[index - 1u] & 1u) << 7;
                running[index] = (byte)shifted;
            }

            // The reduction polynomial, whose only set bits above the low byte
            // are in the first: x^128 + x^7 + x^2 + x + 1.
            if (odd)
                running[0u] = (byte)(running[0u] ^ 0xE1u);
        }

        for (nuint i = 0u; i < 16u; i++)
            left[i] = product[i];
    }

    static void WriteLength(byte[] into, nuint at, ulong bits)
    {
        for (nuint i = 0u; i < 8u; i++)
            into[at + i] = (byte)((bits >> (uint)(8u * (7u - i))) & 0xFFu);
    }
}
