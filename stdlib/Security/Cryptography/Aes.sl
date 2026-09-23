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

/// AES, in ECB, CBC, CFB and CTR.
///
/// ```csharp
/// var cipher = try Aes.FromKey(key);          // 16, 24 or 32 bytes
/// var sealed = try cipher.EncryptCbc(plaintext, iv, PaddingMode.Pkcs7);
/// var opened = try cipher.DecryptCbc(sealed, iv, PaddingMode.Pkcs7);
/// ```
///
/// **None of these modes authenticates anything.** A ciphertext an attacker
/// can modify is a plaintext they can modify, and CBC in particular hands them
/// a bit-flipping attack on the block after the one they touched. Reach for
/// `AesGcm` unless a format forces one of these; where one is forced, put an
/// HMAC over the ciphertext and check it with `FixedTimeEquals` before
/// decrypting anything.
///
/// The one-shot methods are .NET 6's `EncryptCbc` and friends rather than its
/// older `CreateEncryptor`/`ICryptoTransform` pair. A transform object exists
/// to stream a message larger than memory; `CryptoStream` is the piece that
/// would want one and is not written, so the object with no stream to feed
/// would be a shape with no user.
///
/// @see AesGcm
public sealed class Aes
{
    /// One block, for every key length. AES is a 128-bit block cipher; it is
    /// Rijndael that had others, and no standard uses them.
    public const nuint BlockSize = 16u;

    byte[] _forward;
    byte[] _reverse;
    byte[] _schedule;
    nuint _rounds;

    Aes(byte[:] key)
    {
        _forward = BuildSubstitutionBox();
        _reverse = new byte[256u];
        for (nuint i = 0u; i < 256u; i++)
            _reverse[(nuint)_forward[i]] = (byte)i;

        // Written out rather than as a ternary: `nuint` is four bytes on a
        // 32-bit target and eight on a 64-bit one, and the arms of a ternary
        // over unsuffixed literals meet at a type that is neither.
        _rounds = 14u;
        if (key.Length == 16u)
            _rounds = 10u;
        else if (key.Length == 24u)
            _rounds = 12u;

        _schedule = ExpandKey(key);
    }

    /// A cipher under `key`, which must be 16, 24 or 32 bytes -- AES-128,
    /// AES-192 or AES-256.
    ///
    /// @failure CryptoError.KeyLength  `key` is not 16, 24 or 32 bytes
    public static Result<Aes, CryptoError> FromKey(byte[:] key)
    {
        if (key.Length != 16u && key.Length != 24u && key.Length != 32u)
            return Fail(CryptoError.KeyLength);
        return Ok(new Aes(key));
    }

    /// A cipher under a fresh 256-bit key from the platform, which is what
    /// .NET's `Aes.Create()` gives. Aborts if the machine will supply no
    /// entropy, which is a broken machine rather than an outcome to plan for.
    public static Aes Create()
    {
        byte[] key = new byte[32u];
        if (!sl_random_bytes(&key[0u], key.Length))
            sl_fail("Aes.Create: the platform supplied no entropy".ToPointer());
        return new Aes(key);
    }

    /// How many rounds this key length runs: 10, 12 or 14.
    public nuint Rounds => _rounds;

    // ------------------------------------------------------------- one block

    /// One block enciphered in place, at `offset` in `block`.
    ///
    /// Public because AES-GCM and a CTR keystream are built on it and a caller
    /// implementing a mode this class does not have needs the same door.
    /// **Not a way to encrypt a message**: a bare block cipher applied twice
    /// to the same input gives the same output, which is what a mode exists to
    /// fix.
    public void EncryptBlock(byte[] block, nuint offset)
    {
        AddRoundKey(block, offset, 0u);

        for (nuint round = 1u; round < _rounds; round++)
        {
            SubstituteBytes(block, offset, _forward);
            ShiftRows(block, offset);
            MixColumns(block, offset);
            AddRoundKey(block, offset, round);
        }

        SubstituteBytes(block, offset, _forward);
        ShiftRows(block, offset);
        AddRoundKey(block, offset, _rounds);
    }

    /// One block deciphered in place, at `offset` in `block`.
    public void DecryptBlock(byte[] block, nuint offset)
    {
        AddRoundKey(block, offset, _rounds);

        for (nuint round = _rounds - 1u; round > 0u; round--)
        {
            UnshiftRows(block, offset);
            SubstituteBytes(block, offset, _reverse);
            AddRoundKey(block, offset, round);
            UnmixColumns(block, offset);
        }

        UnshiftRows(block, offset);
        SubstituteBytes(block, offset, _reverse);
        AddRoundKey(block, offset, 0u);
    }

    // ------------------------------------------------------------------ ECB

    /// Every block on its own. See `CipherMode.Ecb` for why this is almost
    /// always the wrong answer.
    ///
    /// @failure CryptoError.BlockLength  `padding` is `None` and the input is not a whole
    ///                                   number of blocks
    /// @see CipherMode.Ecb
    /// @see Aes.DecryptEcb
    public Result<byte[], CryptoError> EncryptEcb(byte[:] plaintext, PaddingMode padding)
    {
        var padded = AddPadding(plaintext, padding);
        if (!padded.Ok)
            return Fail(padded.Error);

        byte[] output = padded.Value;
        for (nuint at = 0u; at < output.Length; at += BlockSize)
            EncryptBlock(output, at);

        return Ok(output);
    }

    /// The inverse of `EncryptEcb`.
    ///
    /// @failure CryptoError.BlockLength  the input is empty or not a whole number of blocks
    /// @failure CryptoError.Padding      the padding does not describe itself, which is usually
    ///                                   the wrong key
    /// @see Aes.EncryptEcb
    public Result<byte[], CryptoError> DecryptEcb(byte[:] ciphertext, PaddingMode padding)
    {
        if (ciphertext.Length == 0u || ciphertext.Length % BlockSize != 0u)
            return Fail(CryptoError.BlockLength);

        byte[] output = CopyBytes(ciphertext);
        for (nuint at = 0u; at < output.Length; at += BlockSize)
            DecryptBlock(output, at);

        return RemovePadding(output, padding);
    }

    // ------------------------------------------------------------------ CBC

    /// Chained blocks. `iv` must be one block and must never be reused with
    /// this key; `RandomNumberGenerator.GetBytes(16u)` is how to make one, and
    /// it is not secret -- send it alongside the ciphertext.
    ///
    /// @failure CryptoError.IvLength     `iv` is not one block
    /// @failure CryptoError.BlockLength  `padding` is `None` and the input is not a whole
    ///                                   number of blocks
    /// @see Aes.DecryptCbc
    /// @seealso RandomNumberGenerator.GetBytes
    public Result<byte[], CryptoError> EncryptCbc(byte[:] plaintext, byte[:] iv,
                                                  PaddingMode padding)
    {
        if (iv.Length != BlockSize)
            return Fail(CryptoError.IvLength);

        var padded = AddPadding(plaintext, padding);
        if (!padded.Ok)
            return Fail(padded.Error);

        byte[] output = padded.Value;
        byte[] chain = CopyBytes(iv);

        for (nuint at = 0u; at < output.Length; at += BlockSize)
        {
            for (nuint i = 0u; i < BlockSize; i++)
                output[at + i] = (byte)(output[at + i] ^ chain[i]);

            EncryptBlock(output, at);

            for (nuint i = 0u; i < BlockSize; i++)
                chain[i] = output[at + i];
        }

        return Ok(output);
    }

    /// The inverse of `EncryptCbc`.
    ///
    /// A wrong key shows up as `CryptoError.Padding` about 255 times in 256,
    /// and as a plausible-looking wrong plaintext the rest of the time. That
    /// is the whole reason to authenticate a ciphertext before decrypting it.
    ///
    /// @failure CryptoError.IvLength     `iv` is not one block
    /// @failure CryptoError.BlockLength  the input is empty or not a whole number of blocks
    /// @failure CryptoError.Padding      the padding does not describe itself
    /// @see Aes.EncryptCbc
    public Result<byte[], CryptoError> DecryptCbc(byte[:] ciphertext, byte[:] iv,
                                                  PaddingMode padding)
    {
        if (iv.Length != BlockSize)
            return Fail(CryptoError.IvLength);
        if (ciphertext.Length == 0u || ciphertext.Length % BlockSize != 0u)
            return Fail(CryptoError.BlockLength);

        byte[] output = CopyBytes(ciphertext);
        byte[] chain = CopyBytes(iv);
        byte[] carry = new byte[BlockSize];

        for (nuint at = 0u; at < output.Length; at += BlockSize)
        {
            for (nuint i = 0u; i < BlockSize; i++)
                carry[i] = output[at + i];

            DecryptBlock(output, at);

            for (nuint i = 0u; i < BlockSize; i++)
            {
                output[at + i] = (byte)(output[at + i] ^ chain[i]);
                chain[i] = carry[i];
            }
        }

        return RemovePadding(output, padding);
    }

    // ------------------------------------------------------------------ CFB

    /// Cipher feedback over whole blocks, which is .NET's `CipherMode.CFB`
    /// with a feedback size of 128 bits. No padding: the mode is a stream.
    ///
    /// @failure CryptoError.IvLength  `iv` is not one block
    /// @see Aes.DecryptCfb
    public Result<byte[], CryptoError> EncryptCfb(byte[:] plaintext, byte[:] iv)
    {
        if (iv.Length != BlockSize)
            return Fail(CryptoError.IvLength);

        byte[] output = CopyBytes(plaintext);
        byte[] chain = CopyBytes(iv);

        for (nuint at = 0u; at < output.Length; at += BlockSize)
        {
            EncryptBlock(chain, 0u);

            nuint span = output.Length - at;
            if (span > BlockSize)
                span = BlockSize;

            for (nuint i = 0u; i < span; i++)
            {
                output[at + i] = (byte)(output[at + i] ^ chain[i]);
                chain[i] = output[at + i];
            }
        }

        return Ok(output);
    }

    /// The inverse of `EncryptCfb`.
    ///
    /// @failure CryptoError.IvLength  `iv` is not one block
    /// @see Aes.EncryptCfb
    public Result<byte[], CryptoError> DecryptCfb(byte[:] ciphertext, byte[:] iv)
    {
        if (iv.Length != BlockSize)
            return Fail(CryptoError.IvLength);

        byte[] output = CopyBytes(ciphertext);
        byte[] chain = CopyBytes(iv);

        for (nuint at = 0u; at < output.Length; at += BlockSize)
        {
            EncryptBlock(chain, 0u);

            nuint span = output.Length - at;
            if (span > BlockSize)
                span = BlockSize;

            for (nuint i = 0u; i < span; i++)
            {
                byte enciphered = output[at + i];
                output[at + i] = (byte)(enciphered ^ chain[i]);
                chain[i] = enciphered;
            }
        }

        return Ok(output);
    }

    // ------------------------------------------------------------------ CTR

    /// Counter mode, which is its own inverse: the same call decrypts.
    ///
    /// `counter` is sixteen bytes and is incremented as one big-endian number
    /// per block, which is what NIST SP 800-38A and every protocol built on it
    /// do. **A counter value used twice under one key is fatal** -- the two
    /// messages XOR to the XOR of their plaintexts -- so the usual arrangement
    /// is a random nonce in the high bytes and a block counter in the low.
    ///
    /// @failure CryptoError.IvLength  `counter` is not one block
    public Result<byte[], CryptoError> ApplyCtr(byte[:] data, byte[:] counter) =>
        ApplyCounter(data, counter, 0u);

    /// The same, stepping only the bytes from `from` onward.
    ///
    /// GCM increments the last four bytes and leaves the nonce in the first
    /// twelve alone, so a message long enough to carry past 2^32 blocks wraps
    /// within the counter rather than walking into the nonce. That is the one
    /// difference between GCM's CTR and SP 800-38A's, and it is why this is a
    /// parameter rather than two loops.
    Result<byte[], CryptoError> ApplyCounter(byte[:] data, byte[:] counter, nuint from)
    {
        if (counter.Length != BlockSize)
            return Fail(CryptoError.IvLength);

        byte[] output = CopyBytes(data);
        byte[] position = CopyBytes(counter);
        byte[] keystream = new byte[BlockSize];

        for (nuint at = 0u; at < output.Length; at += BlockSize)
        {
            for (nuint i = 0u; i < BlockSize; i++)
                keystream[i] = position[i];

            EncryptBlock(keystream, 0u);

            nuint span = output.Length - at;
            if (span > BlockSize)
                span = BlockSize;

            for (nuint i = 0u; i < span; i++)
                output[at + i] = (byte)(output[at + i] ^ keystream[i]);

            IncrementCounter(position, from);
        }

        CryptographicOperations.ZeroMemory(keystream);
        return Ok(output);
    }

    /// One added to a big-endian counter in `block`, from byte `from` to the
    /// end. GCM increments only the last four bytes, which is what `from` is
    /// for.
    static void IncrementCounter(byte[] block, nuint from)
    {
        nuint at = block.Length;
        while (at > from)
        {
            at--;
            block[at] = (byte)(block[at] + 1u);
            if (block[at] != 0)
                return;
        }
    }

    // -------------------------------------------------------------- padding

    Result<byte[], CryptoError> AddPadding(byte[:] data, PaddingMode padding)
    {
        nuint remainder = data.Length % BlockSize;

        switch (padding)
        {
            case PaddingMode.None:
                if (remainder != 0u)
                    return Fail(CryptoError.BlockLength);
                return Ok(CopyBytes(data));

            case PaddingMode.Pkcs7:
            {
                // Always adds, even to a whole number of blocks -- that is what
                // makes it removable without ambiguity.
                nuint added = BlockSize - remainder;
                byte[] output = new byte[data.Length + added];
                for (nuint i = 0u; i < data.Length; i++)
                    output[i] = data[i];
                for (nuint i = data.Length; i < output.Length; i++)
                    output[i] = (byte)added;
                return Ok(output);
            }

            case PaddingMode.Zeros:
            {
                nuint added = 0u;
                if (remainder != 0u)
                    added = BlockSize - remainder;

                byte[] output = new byte[data.Length + added];
                for (nuint i = 0u; i < data.Length; i++)
                    output[i] = data[i];
                return Ok(output);
            }

            case PaddingMode.AnsiX923:
            {
                nuint added = BlockSize - remainder;
                byte[] output = new byte[data.Length + added];
                for (nuint i = 0u; i < data.Length; i++)
                    output[i] = data[i];
                output[output.Length - 1u] = (byte)added;
                return Ok(output);
            }
        }

        // Every case above returns; the binder wants a path out of the switch
        // itself, and this is it.
        return Fail(CryptoError.Parameter);
    }

    Result<byte[], CryptoError> RemovePadding(byte[] data, PaddingMode padding)
    {
        if (padding == PaddingMode.None || padding == PaddingMode.Zeros)
            return Ok(data);

        nuint added = (nuint)data[data.Length - 1u];
        if (added == 0u || added > BlockSize || added > data.Length)
            return Fail(CryptoError.Padding);

        if (padding == PaddingMode.Pkcs7)
        {
            for (nuint i = data.Length - added; i < data.Length; i++)
            {
                if ((nuint)data[i] != added)
                    return Fail(CryptoError.Padding);
            }
        }
        else
        {
            for (nuint i = data.Length - added; i < data.Length - 1u; i++)
            {
                if (data[i] != 0)
                    return Fail(CryptoError.Padding);
            }
        }

        byte[] output = new byte[data.Length - added];
        for (nuint i = 0u; i < output.Length; i++)
            output[i] = data[i];
        return Ok(output);
    }

    // ------------------------------------------------------------ the cipher

    void AddRoundKey(byte[] block, nuint offset, nuint round)
    {
        nuint at = round * BlockSize;
        for (nuint i = 0u; i < BlockSize; i++)
            block[offset + i] = (byte)(block[offset + i] ^ _schedule[at + i]);
    }

    static void SubstituteBytes(byte[] block, nuint offset, byte[] box)
    {
        for (nuint i = 0u; i < BlockSize; i++)
            block[offset + i] = box[(nuint)block[offset + i]];
    }

    /// The state is column-major, so row `r` is bytes r, r+4, r+8, r+12.
    static void ShiftRows(byte[] s, nuint at)
    {
        byte carry = s[at + 1u];
        s[at + 1u] = s[at + 5u];
        s[at + 5u] = s[at + 9u];
        s[at + 9u] = s[at + 13u];
        s[at + 13u] = carry;

        carry = s[at + 2u];
        s[at + 2u] = s[at + 10u];
        s[at + 10u] = carry;
        carry = s[at + 6u];
        s[at + 6u] = s[at + 14u];
        s[at + 14u] = carry;

        carry = s[at + 15u];
        s[at + 15u] = s[at + 11u];
        s[at + 11u] = s[at + 7u];
        s[at + 7u] = s[at + 3u];
        s[at + 3u] = carry;
    }

    static void UnshiftRows(byte[] s, nuint at)
    {
        byte carry = s[at + 13u];
        s[at + 13u] = s[at + 9u];
        s[at + 9u] = s[at + 5u];
        s[at + 5u] = s[at + 1u];
        s[at + 1u] = carry;

        carry = s[at + 2u];
        s[at + 2u] = s[at + 10u];
        s[at + 10u] = carry;
        carry = s[at + 6u];
        s[at + 6u] = s[at + 14u];
        s[at + 14u] = carry;

        carry = s[at + 3u];
        s[at + 3u] = s[at + 7u];
        s[at + 7u] = s[at + 11u];
        s[at + 11u] = s[at + 15u];
        s[at + 15u] = carry;
    }

    static void MixColumns(byte[] s, nuint at)
    {
        for (nuint column = 0u; column < 4u; column++)
        {
            nuint c = at + column * 4u;
            byte a0 = s[c];
            byte a1 = s[c + 1u];
            byte a2 = s[c + 2u];
            byte a3 = s[c + 3u];

            s[c] = (byte)(MultiplyByTwo(a0) ^ MultiplyByTwo(a1) ^ a1 ^ a2 ^ a3);
            s[c + 1u] = (byte)(a0 ^ MultiplyByTwo(a1) ^ MultiplyByTwo(a2) ^ a2 ^ a3);
            s[c + 2u] = (byte)(a0 ^ a1 ^ MultiplyByTwo(a2) ^ MultiplyByTwo(a3) ^ a3);
            s[c + 3u] = (byte)(MultiplyByTwo(a0) ^ a0 ^ a1 ^ a2 ^ MultiplyByTwo(a3));
        }
    }

    static void UnmixColumns(byte[] s, nuint at)
    {
        for (nuint column = 0u; column < 4u; column++)
        {
            nuint c = at + column * 4u;
            byte a0 = s[c];
            byte a1 = s[c + 1u];
            byte a2 = s[c + 2u];
            byte a3 = s[c + 3u];

            s[c] = (byte)(MultiplyInField(a0, 14) ^ MultiplyInField(a1, 11) ^
                          MultiplyInField(a2, 13) ^ MultiplyInField(a3, 9));
            s[c + 1u] = (byte)(MultiplyInField(a0, 9) ^ MultiplyInField(a1, 14) ^
                               MultiplyInField(a2, 11) ^ MultiplyInField(a3, 13));
            s[c + 2u] = (byte)(MultiplyInField(a0, 13) ^ MultiplyInField(a1, 9) ^
                               MultiplyInField(a2, 14) ^ MultiplyInField(a3, 11));
            s[c + 3u] = (byte)(MultiplyInField(a0, 11) ^ MultiplyInField(a1, 13) ^
                               MultiplyInField(a2, 9) ^ MultiplyInField(a3, 14));
        }
    }

    byte[] ExpandKey(byte[:] key)
    {
        nuint words = 4u * (_rounds + 1u);
        nuint keyWords = key.Length / 4u;
        byte[] schedule = new byte[words * 4u];

        for (nuint i = 0u; i < key.Length; i++)
            schedule[i] = key[i];

        byte constant = 1;

        for (nuint i = keyWords; i < words; i++)
        {
            nuint previous = (i - 1u) * 4u;
            byte t0 = schedule[previous];
            byte t1 = schedule[previous + 1u];
            byte t2 = schedule[previous + 2u];
            byte t3 = schedule[previous + 3u];

            if (i % keyWords == 0u)
            {
                // RotWord, SubWord, and the round constant on the first byte.
                byte carry = t0;
                t0 = _forward[(nuint)t1];
                t1 = _forward[(nuint)t2];
                t2 = _forward[(nuint)t3];
                t3 = _forward[(nuint)carry];

                t0 = (byte)(t0 ^ constant);
                constant = MultiplyByTwo(constant);
            }
            else if (keyWords > 6u && i % keyWords == 4u)
            {
                // AES-256 substitutes without rotating every fourth word.
                t0 = _forward[(nuint)t0];
                t1 = _forward[(nuint)t1];
                t2 = _forward[(nuint)t2];
                t3 = _forward[(nuint)t3];
            }

            nuint back = (i - keyWords) * 4u;
            nuint here = i * 4u;
            schedule[here] = (byte)(schedule[back] ^ t0);
            schedule[here + 1u] = (byte)(schedule[back + 1u] ^ t1);
            schedule[here + 2u] = (byte)(schedule[back + 2u] ^ t2);
            schedule[here + 3u] = (byte)(schedule[back + 3u] ^ t3);
        }

        return schedule;
    }

    /// The S-box, derived rather than transcribed.
    ///
    /// It is defined as the multiplicative inverse in GF(2^8) followed by an
    /// affine transform, and computing it is twenty lines where copying it is
    /// 256 hex constants that nothing would catch a typo in. The cost is a
    /// table built per cipher object, which is a few thousand instructions
    /// once.
    static byte[] BuildSubstitutionBox()
    {
        byte[] box = new byte[256u];
        box[0u] = 0x63;

        for (nuint i = 1u; i < 256u; i++)
        {
            uint inverse = (uint)InvertInField((byte)i);
            uint folded = inverse ^ RotateOctet(inverse, 1u) ^ RotateOctet(inverse, 2u) ^
                          RotateOctet(inverse, 3u) ^ RotateOctet(inverse, 4u) ^ 0x63u;
            box[i] = (byte)(folded & 0xFFu);
        }

        return box;
    }

    static uint RotateOctet(uint value, uint by) =>
        ((value << by) | (value >> (8u - by))) & 0xFFu;

    /// x times 2 in GF(2^8) with the AES polynomial, which is the only
    /// multiplication the forward direction needs.
    static byte MultiplyByTwo(byte value)
    {
        uint doubled = (uint)value << 1;
        if ((value & 0x80u) != 0u)
            doubled ^= 0x1Bu;
        return (byte)(doubled & 0xFFu);
    }

    /// A full GF(2^8) multiply, for the inverse mix columns.
    static byte MultiplyInField(byte left, byte right)
    {
        uint result = 0u;
        uint a = (uint)left;
        uint b = (uint)right;

        for (nuint i = 0u; i < 8u; i++)
        {
            if ((b & 1u) != 0u)
                result ^= a;

            bool overflowed = (a & 0x80u) != 0u;
            a = (a << 1) & 0xFFu;
            if (overflowed)
                a ^= 0x1Bu;

            b >>= 1;
        }

        return (byte)(result & 0xFFu);
    }

    /// The multiplicative inverse, as a^254 -- which it is, because the group
    /// has 255 elements.
    static byte InvertInField(byte value)
    {
        if (value == 0)
            return 0;

        byte result = 1;
        byte power = value;

        for (nuint bit = 1u; bit < 8u; bit++)
        {
            power = MultiplyInField(power, power);
            result = MultiplyInField(result, power);
        }

        return result;
    }

    static byte[] CopyBytes(byte[:] data)
    {
        byte[] copy = new byte[data.Length];
        for (nuint i = 0u; i < data.Length; i++)
            copy[i] = data[i];
        return copy;
    }
}
