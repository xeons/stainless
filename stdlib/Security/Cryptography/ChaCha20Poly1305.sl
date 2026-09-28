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

/// ChaCha20-Poly1305: the AEAD of RFC 8439 §2.8, as .NET's
/// `ChaCha20Poly1305`, and with exactly `AesGcm`'s shape.
///
/// ```csharp
/// var box = try ChaCha20Poly1305.FromKey(key);
/// byte[] tag = new byte[16u];
/// var sealed = try box.Encrypt(nonce, plaintext, associated, tag);
/// var opened = try box.Decrypt(nonce, sealed, associated, tag);
/// ```
///
/// **It is AES-GCM's alternative where AES would leak.** Every step is
/// additions, rotations and exclusive-ors on words, with no table and no
/// branch on a secret, so it is constant time in software where the AES here
/// is not. TLS 1.3, WireGuard and SSH all offer it for that reason.
///
/// **The nonce MUST NOT repeat under one key.** A repeat reuses the keystream
/// and the one-time Poly1305 key both, which gives away the XOR of the two
/// plaintexts and lets an attacker forge. Twelve random bytes per message is
/// safe to about 2^32 messages; a counter is better where one can be kept.
///
/// `Decrypt` returns `CryptoError.AuthenticationFailed` and no plaintext when
/// the tag does not match. The tag is checked before anything is deciphered.
///
/// @see AesGcm
public sealed class ChaCha20Poly1305
{
    /// @value sixteen bytes.
    public const nuint TagSize = 16u;

    /// The only length RFC 8439 defines.
    ///
    /// @value twelve bytes.
    public const nuint NonceSize = 12u;

    private ChaCha20 _cipher;

    ChaCha20Poly1305(ChaCha20 cipher)
    {
        _cipher = cipher;
    }

    /// A box under `key`, which must be 32 bytes.
    ///
    /// @failure CryptoError.KeyLength  `key` is not 32 bytes
    public static Result<ChaCha20Poly1305, CryptoError> FromKey(ReadOnlySpan<byte> key)
    {
        var cipher = ChaCha20.FromKey(key);
        if (!cipher.Ok)
            return Fail(cipher.Error);
        return Ok(new ChaCha20Poly1305(cipher.Value));
    }

    /// The ciphertext, with the tag written into `tag`.
    ///
    /// `associatedData` is authenticated and not encrypted — a message header,
    /// a record number, anything the recipient must be sure of and that is not
    /// secret. Pass an empty array when there is none.
    ///
    /// @param nonce           twelve bytes, never to repeat under this key
    /// @param plaintext       the message to encipher
    /// @param associatedData  authenticated and not encrypted; empty when there is none
    /// @param tag             a `TagSize` array the tag is written into
    /// @failure CryptoError.NonceLength  `nonce` is not twelve bytes
    /// @failure CryptoError.TagLength    `tag` is not `TagSize` long
    /// @failure CryptoError.Parameter    `plaintext` is longer than the 256 GiB the counter
    ///                                   covers
    /// @see ChaCha20Poly1305.Decrypt
    public Result<byte[], CryptoError> Encrypt(ReadOnlySpan<byte> nonce, ReadOnlySpan<byte> plaintext,
                                               ReadOnlySpan<byte> associatedData, byte[] tag)
    {
        if (nonce.Length != NonceSize)
            return Fail(CryptoError.NonceLength);
        if (tag.Length != TagSize)
            return Fail(CryptoError.TagLength);

        var enciphered = _cipher.ApplyKeystream(nonce, 1u, plaintext);
        if (!enciphered.Ok)
            return Fail(enciphered.Error);

        byte[] ciphertext = enciphered.Value;
        byte[] computed = ComputeTag(nonce, associatedData, ciphertext);
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
    /// @failure CryptoError.NonceLength           `nonce` is not twelve bytes
    /// @failure CryptoError.TagLength             `tag` is not `TagSize` long
    /// @failure CryptoError.Parameter             `ciphertext` is longer than the counter covers
    /// @failure CryptoError.AuthenticationFailed  the tag does not match, and no plaintext is
    ///                                            returned
    /// @see ChaCha20Poly1305.Encrypt
    public Result<byte[], CryptoError> Decrypt(ReadOnlySpan<byte> nonce, ReadOnlySpan<byte> ciphertext,
                                               ReadOnlySpan<byte> associatedData, ReadOnlySpan<byte> tag)
    {
        if (nonce.Length != NonceSize)
            return Fail(CryptoError.NonceLength);
        if (tag.Length != TagSize)
            return Fail(CryptoError.TagLength);

        byte[] expected = ComputeTag(nonce, associatedData, ciphertext);
        if (!CryptographicOperations.FixedTimeEquals(expected, tag))
            return Fail(CryptoError.AuthenticationFailed);

        return _cipher.ApplyKeystream(nonce, 1u, ciphertext);
    }

    /// Poly1305 under the first 32 bytes of block zero, over the associated
    /// data and the ciphertext, each padded to sixteen bytes, and then their
    /// two lengths as little-endian doublewords.
    byte[] ComputeTag(ReadOnlySpan<byte> nonce, ReadOnlySpan<byte> associatedData,
                      ReadOnlySpan<byte> ciphertext)
    {
        byte[] oneTimeKey = _cipher.TransformKeystream(nonce, 0u, new byte[Poly1305.KeySize]);
        var mac = new Poly1305(oneTimeKey);
        CryptographicOperations.ZeroMemory(oneTimeKey);

        byte[] zeros = new byte[16u];
        mac.AppendData(associatedData);
        mac.AppendData(zeros[:PaddingFor(associatedData.Length)]);
        mac.AppendData(ciphertext);
        mac.AppendData(zeros[:PaddingFor(ciphertext.Length)]);

        byte[] lengths = new byte[16u];
        WriteLittleDoubleWord(lengths, 0u, (ulong)associatedData.Length);
        WriteLittleDoubleWord(lengths, 8u, (ulong)ciphertext.Length);
        mac.AppendData(lengths);

        return mac.GetTag();
    }

    /// How many zeros bring `length` to a multiple of sixteen.
    static nuint PaddingFor(nuint length) => (16u - length % 16u) % 16u;
}
