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
/// **It is constant time.** The cipher is bitsliced, as BearSSL's `aes_ct64`
/// is: four blocks are spread across eight 64-bit words, one word for each bit
/// position of every byte, and the S-box is the Boyar–Peralta logic circuit
/// rather than a table. Nothing is indexed by, and nothing branches on, the
/// key or the data. ECB, CTR and the decrypting half of CBC and CFB run four
/// blocks in each pass. CBC and CFB encryption chain each block into the next,
/// so they run one block per pass at the cost of four.
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

    /// Four blocks, which is what one pass of the bitsliced cipher carries.
    private const nuint BatchSize = 64u;

    /// Eight words per round key, already bitsliced and repeated across the
    /// four blocks, so adding a round key is eight exclusive-ors.
    private ulong[] _schedule;
    private nuint _rounds;

    Aes(ReadOnlySpan<byte> key)
    {
        // Written out rather than as a ternary: `nuint` is four bytes on a
        // 32-bit target and eight on a 64-bit one, and the arms of a ternary
        // over unsuffixed literals meet at a type that is neither.
        _rounds = 14u;
        if (key.Length == 16u)
            _rounds = 10u;
        else if (key.Length == 24u)
            _rounds = 12u;

        _schedule = ExpandKey(key, _rounds);
    }

    /// A cipher under `key`, which must be 16, 24 or 32 bytes -- AES-128,
    /// AES-192 or AES-256.
    ///
    /// @failure CryptoError.KeyLength  `key` is not 16, 24 or 32 bytes
    public static Result<Aes, CryptoError> FromKey(ReadOnlySpan<byte> key)
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
        var cipher = new Aes(key);
        CryptographicOperations.ZeroMemory(key);
        return cipher;
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
    /// fix. One block costs a pass that could have carried four.
    public void EncryptBlock(byte[] block, nuint offset) => EncryptBlocks(block, offset, 1u);

    /// One block deciphered in place, at `offset` in `block`.
    public void DecryptBlock(byte[] block, nuint offset) => DecryptBlocks(block, offset, 1u);

    // ------------------------------------------------------------------ ECB

    /// Every block on its own. See `CipherMode.Ecb` for why this is almost
    /// always the wrong answer.
    ///
    /// @failure CryptoError.BlockLength  `padding` is `None` and the input is not a whole
    ///                                   number of blocks
    /// @see CipherMode.Ecb
    /// @see Aes.DecryptEcb
    public Result<byte[], CryptoError> EncryptEcb(ReadOnlySpan<byte> plaintext, PaddingMode padding)
    {
        var padded = AddPadding(plaintext, padding);
        if (!padded.Ok)
            return Fail(padded.Error);

        byte[] output = padded.Value;
        EncryptWholeBlocks(output);
        return Ok(output);
    }

    /// The inverse of `EncryptEcb`.
    ///
    /// @failure CryptoError.BlockLength  the input is empty or not a whole number of blocks
    /// @failure CryptoError.Padding      the padding does not describe itself, which is usually
    ///                                   the wrong key
    /// @see Aes.EncryptEcb
    public Result<byte[], CryptoError> DecryptEcb(ReadOnlySpan<byte> ciphertext, PaddingMode padding)
    {
        if (ciphertext.Length == 0u || ciphertext.Length % BlockSize != 0u)
            return Fail(CryptoError.BlockLength);

        byte[] output = CopyBytes(ciphertext);
        for (nuint at = 0u; at < output.Length; at += BatchSize)
            DecryptBlocks(output, at, CountBatchBlocks(output.Length - at));

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
    public Result<byte[], CryptoError> EncryptCbc(ReadOnlySpan<byte> plaintext, ReadOnlySpan<byte> iv,
                                                  PaddingMode padding)
    {
        if (iv.Length != BlockSize)
            return Fail(CryptoError.IvLength);

        var padded = AddPadding(plaintext, padding);
        if (!padded.Ok)
            return Fail(padded.Error);

        byte[] output = padded.Value;
        for (nuint at = 0u; at < output.Length; at += BlockSize)
        {
            for (nuint i = 0u; i < BlockSize; i++)
            {
                byte previous = at == 0u ? iv[i] : output[at - BlockSize + i];
                output[at + i] = (byte)(output[at + i] ^ previous);
            }

            EncryptBlocks(output, at, 1u);
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
    public Result<byte[], CryptoError> DecryptCbc(ReadOnlySpan<byte> ciphertext, ReadOnlySpan<byte> iv,
                                                  PaddingMode padding)
    {
        if (iv.Length != BlockSize)
            return Fail(CryptoError.IvLength);
        if (ciphertext.Length == 0u || ciphertext.Length % BlockSize != 0u)
            return Fail(CryptoError.BlockLength);

        // Every block is deciphered before any is unchained, which is what
        // lets four go through at once; `ciphertext` still holds the chain.
        byte[] output = CopyBytes(ciphertext);
        for (nuint at = 0u; at < output.Length; at += BatchSize)
            DecryptBlocks(output, at, CountBatchBlocks(output.Length - at));

        for (nuint i = 0u; i < BlockSize; i++)
            output[i] = (byte)(output[i] ^ iv[i]);
        for (nuint i = BlockSize; i < output.Length; i++)
            output[i] = (byte)(output[i] ^ ciphertext[i - BlockSize]);

        return RemovePadding(output, padding);
    }

    // ------------------------------------------------------------------ CFB

    /// Cipher feedback over whole blocks, which is .NET's `CipherMode.CFB`
    /// with a feedback size of 128 bits. No padding: the mode is a stream.
    ///
    /// @failure CryptoError.IvLength  `iv` is not one block
    /// @see Aes.DecryptCfb
    public Result<byte[], CryptoError> EncryptCfb(ReadOnlySpan<byte> plaintext, ReadOnlySpan<byte> iv)
    {
        if (iv.Length != BlockSize)
            return Fail(CryptoError.IvLength);

        byte[] output = CopyBytes(plaintext);
        byte[] chain = CopyBytes(iv);

        for (nuint at = 0u; at < output.Length; at += BlockSize)
        {
            EncryptBlocks(chain, 0u, 1u);

            nuint span = output.Length - at;
            if (span > BlockSize)
                span = BlockSize;

            for (nuint i = 0u; i < span; i++)
            {
                output[at + i] = (byte)(output[at + i] ^ chain[i]);
                chain[i] = output[at + i];
            }
        }

        CryptographicOperations.ZeroMemory(chain);
        return Ok(output);
    }

    /// The inverse of `EncryptCfb`.
    ///
    /// @failure CryptoError.IvLength  `iv` is not one block
    /// @see Aes.EncryptCfb
    public Result<byte[], CryptoError> DecryptCfb(ReadOnlySpan<byte> ciphertext, ReadOnlySpan<byte> iv)
    {
        if (iv.Length != BlockSize)
            return Fail(CryptoError.IvLength);

        // Each block's keystream is the encipherment of the ciphertext block
        // before it, so all of it is known before any is made.
        nuint blocks = (ciphertext.Length + BlockSize - 1u) / BlockSize;
        byte[] keystream = new byte[blocks * BlockSize];
        for (nuint i = 0u; i < keystream.Length; i++)
            keystream[i] = i < BlockSize ? iv[i] : ciphertext[i - BlockSize];

        EncryptWholeBlocks(keystream);

        byte[] output = new byte[ciphertext.Length];
        for (nuint i = 0u; i < output.Length; i++)
            output[i] = (byte)(ciphertext[i] ^ keystream[i]);

        CryptographicOperations.ZeroMemory(keystream);
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
    public Result<byte[], CryptoError> ApplyCtr(ReadOnlySpan<byte> data, ReadOnlySpan<byte> counter) =>
        ApplyCounter(data, counter, 0u);

    /// The same, stepping only the bytes from `from` onward.
    ///
    /// GCM increments the last four bytes and leaves the nonce in the first
    /// twelve alone, so a message long enough to carry past 2^32 blocks wraps
    /// within the counter rather than walking into the nonce. That is the one
    /// difference between GCM's CTR and SP 800-38A's, and it is why this is a
    /// parameter rather than two loops.
    Result<byte[], CryptoError> ApplyCounter(ReadOnlySpan<byte> data, ReadOnlySpan<byte> counter, nuint from)
    {
        if (counter.Length != BlockSize)
            return Fail(CryptoError.IvLength);

        byte[] output = CopyBytes(data);
        byte[] position = CopyBytes(counter);
        byte[] keystream = new byte[BatchSize];

        for (nuint at = 0u; at < output.Length; at += BatchSize)
        {
            nuint count = CountBatchBlocks(output.Length - at);
            for (nuint block = 0u; block < count; block++)
            {
                for (nuint i = 0u; i < BlockSize; i++)
                    keystream[block * BlockSize + i] = position[i];
                IncrementCounter(position, from);
            }

            EncryptBlocks(keystream, 0u, count);

            nuint span = output.Length - at;
            if (span > BatchSize)
                span = BatchSize;

            for (nuint i = 0u; i < span; i++)
                output[at + i] = (byte)(output[at + i] ^ keystream[i]);
        }

        CryptographicOperations.ZeroMemory(keystream);
        return Ok(output);
    }

    /// One added to a big-endian counter in `block`, from byte `from` to the
    /// end. GCM increments only the last four bytes, which is what `from` is
    /// for. The counter is public, so the early return leaks nothing.
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

    Result<byte[], CryptoError> AddPadding(ReadOnlySpan<byte> data, PaddingMode padding)
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
                data.CopyTo(output);
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
                data.CopyTo(output);
                return Ok(output);
            }

            case PaddingMode.AnsiX923:
            {
                nuint added = BlockSize - remainder;
                byte[] output = new byte[data.Length + added];
                data.CopyTo(output);
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

        return Ok(data[:data.Length - added].ToArray());
    }

    // ------------------------------------------------------------ the cipher
    //
    // Bit `b` of every byte of four blocks is in `q[b]`, at position
    // 16 * row + 4 * column + block. A row is sixteen bits, so ShiftRows moves
    // nibbles within one and MixColumns rotates the rows past each other.

    /// Every block of `data` enciphered in place, four to a pass. The length
    /// MUST be a whole number of blocks.
    void EncryptWholeBlocks(byte[] data)
    {
        for (nuint at = 0u; at < data.Length; at += BatchSize)
            EncryptBlocks(data, at, CountBatchBlocks(data.Length - at));
    }

    /// `count` blocks from `offset` enciphered in place, in one pass. `count`
    /// MUST be one to four.
    void EncryptBlocks(byte[] data, nuint offset, nuint count)
    {
        ulong[8] q;
        LoadBlocks(ref q, data, offset, count);
        EncryptState(ref q);
        StoreBlocks(ref q, data, offset, count);
    }

    /// `count` blocks from `offset` deciphered in place, in one pass.
    void DecryptBlocks(byte[] data, nuint offset, nuint count)
    {
        ulong[8] q;
        LoadBlocks(ref q, data, offset, count);
        DecryptState(ref q);
        StoreBlocks(ref q, data, offset, count);
    }

    /// How many blocks the next pass carries, with `remaining` bytes to go.
    static nuint CountBatchBlocks(nuint remaining)
    {
        nuint blocks = (remaining + BlockSize - 1u) / BlockSize;
        if (blocks > 4u)
            return 4u;
        return blocks;
    }

    void EncryptState(ref ulong[8] q)
    {
        ulong[] schedule = _schedule;
        nuint rounds = _rounds;

        for (nuint i = 0u; i < 8u; i++)
            q[i] ^= schedule[i];

        for (nuint round = 1u; round < rounds; round++)
        {
            SubstituteBytes(ref q);
            ShiftRows(ref q);
            MixColumns(ref q);

            nuint at = round * 8u;
            for (nuint i = 0u; i < 8u; i++)
                q[i] ^= schedule[at + i];
        }

        SubstituteBytes(ref q);
        ShiftRows(ref q);

        nuint last = rounds * 8u;
        for (nuint i = 0u; i < 8u; i++)
            q[i] ^= schedule[last + i];
    }

    void DecryptState(ref ulong[8] q)
    {
        ulong[] schedule = _schedule;
        nuint rounds = _rounds;

        nuint last = rounds * 8u;
        for (nuint i = 0u; i < 8u; i++)
            q[i] ^= schedule[last + i];

        for (nuint round = rounds - 1u; round > 0u; round--)
        {
            UnshiftRows(ref q);
            UnsubstituteBytes(ref q);

            nuint at = round * 8u;
            for (nuint i = 0u; i < 8u; i++)
                q[i] ^= schedule[at + i];

            UnmixColumns(ref q);
        }

        UnshiftRows(ref q);
        UnsubstituteBytes(ref q);

        for (nuint i = 0u; i < 8u; i++)
            q[i] ^= schedule[i];
    }

    /// `count` blocks of `data` from `offset` into the bitsliced state, as
    /// little-endian words. A block past `count` is zeros, and its result is
    /// thrown away.
    static void LoadBlocks(ref ulong[8] q, byte[] data, nuint offset, nuint count)
    {
        for (nuint block = 0u; block < 4u; block++)
        {
            uint[4] words;
            if (block < count)
            {
                nuint at = offset + block * BlockSize;
                for (nuint i = 0u; i < BlockSize; i++)
                    words[i / 4u] |= (uint)data[at + i] << (int)(8u * (i % 4u));
            }

            q[block] = SpreadWord(words[0u]) | (SpreadWord(words[2u]) << 8);
            q[block + 4u] = SpreadWord(words[1u]) | (SpreadWord(words[3u]) << 8);
        }

        Orthogonalize(ref q);
    }

    /// The inverse of `LoadBlocks`, writing `count` blocks back.
    static void StoreBlocks(ref ulong[8] q, byte[] data, nuint offset, nuint count)
    {
        Orthogonalize(ref q);

        for (nuint block = 0u; block < count; block++)
        {
            uint[4] words;
            words[0u] = GatherWord(q[block]);
            words[1u] = GatherWord(q[block + 4u]);
            words[2u] = GatherWord(q[block] >> 8);
            words[3u] = GatherWord(q[block + 4u] >> 8);

            nuint at = offset + block * BlockSize;
            for (nuint i = 0u; i < BlockSize; i++)
                data[at + i] = (byte)(words[i / 4u] >> (int)(8u * (i % 4u)));
        }
    }

    /// The four bytes of `word` moved to the low byte of each 16-bit lane.
    static ulong SpreadWord(uint word)
    {
        ulong x = (ulong)word;
        x = (x | (x << 16)) & 0x0000FFFF0000FFFFu;
        x = (x | (x << 8)) & 0x00FF00FF00FF00FFu;
        return x;
    }

    /// The inverse of `SpreadWord`, ignoring the high byte of each lane.
    static uint GatherWord(ulong spread)
    {
        ulong x = spread & 0x00FF00FF00FF00FFu;
        x = (x | (x >> 8)) & 0x0000FFFF0000FFFFu;
        return (uint)x | (uint)(x >> 16);
    }

    /// Transposes the eight words as eight-by-eight bit matrices, which moves
    /// between one byte per lane and one bit position per word. It is its own
    /// inverse.
    static void Orthogonalize(ref ulong[8] q)
    {
        SwapBits(ref q[0u], ref q[1u], 0x5555555555555555u, 1);
        SwapBits(ref q[2u], ref q[3u], 0x5555555555555555u, 1);
        SwapBits(ref q[4u], ref q[5u], 0x5555555555555555u, 1);
        SwapBits(ref q[6u], ref q[7u], 0x5555555555555555u, 1);

        SwapBits(ref q[0u], ref q[2u], 0x3333333333333333u, 2);
        SwapBits(ref q[1u], ref q[3u], 0x3333333333333333u, 2);
        SwapBits(ref q[4u], ref q[6u], 0x3333333333333333u, 2);
        SwapBits(ref q[5u], ref q[7u], 0x3333333333333333u, 2);

        SwapBits(ref q[0u], ref q[4u], 0x0F0F0F0F0F0F0F0Fu, 4);
        SwapBits(ref q[1u], ref q[5u], 0x0F0F0F0F0F0F0F0Fu, 4);
        SwapBits(ref q[2u], ref q[6u], 0x0F0F0F0F0F0F0F0Fu, 4);
        SwapBits(ref q[3u], ref q[7u], 0x0F0F0F0F0F0F0F0Fu, 4);
    }

    /// The bits of `high` under `mask` exchanged with the bits of `low` one
    /// `shift` above them.
    static void SwapBits(ref ulong low, ref ulong high, ulong mask, int shift)
    {
        ulong a = low;
        ulong b = high;
        low = (a & mask) | ((b & mask) << shift);
        high = ((a >> shift) & mask) | (b & ~mask);
    }

    /// The S-box on all 64 bytes at once, as the circuit of Boyar and Peralta,
    /// "A new combinational logic minimization technique with applications to
    /// cryptology" (2009). The names are the paper's: `x0` is the high bit.
    static void SubstituteBytes(ref ulong[8] q)
    {
        ulong x0 = q[7u];
        ulong x1 = q[6u];
        ulong x2 = q[5u];
        ulong x3 = q[4u];
        ulong x4 = q[3u];
        ulong x5 = q[2u];
        ulong x6 = q[1u];
        ulong x7 = q[0u];

        // The top linear transformation.
        ulong y14 = x3 ^ x5;
        ulong y13 = x0 ^ x6;
        ulong y9 = x0 ^ x3;
        ulong y8 = x0 ^ x5;
        ulong t0 = x1 ^ x2;
        ulong y1 = t0 ^ x7;
        ulong y4 = y1 ^ x3;
        ulong y12 = y13 ^ y14;
        ulong y2 = y1 ^ x0;
        ulong y5 = y1 ^ x6;
        ulong y3 = y5 ^ y8;
        ulong t1 = x4 ^ y12;
        ulong y15 = t1 ^ x5;
        ulong y20 = t1 ^ x1;
        ulong y6 = y15 ^ x7;
        ulong y10 = y15 ^ t0;
        ulong y11 = y20 ^ y9;
        ulong y7 = x7 ^ y11;
        ulong y17 = y10 ^ y11;
        ulong y19 = y10 ^ y8;
        ulong y16 = t0 ^ y11;
        ulong y21 = y13 ^ y16;
        ulong y18 = x0 ^ y16;

        // The nonlinear middle: inversion in GF(2^4)^2.
        ulong t2 = y12 & y15;
        ulong t3 = y3 & y6;
        ulong t4 = t3 ^ t2;
        ulong t5 = y4 & x7;
        ulong t6 = t5 ^ t2;
        ulong t7 = y13 & y16;
        ulong t8 = y5 & y1;
        ulong t9 = t8 ^ t7;
        ulong t10 = y2 & y7;
        ulong t11 = t10 ^ t7;
        ulong t12 = y9 & y11;
        ulong t13 = y14 & y17;
        ulong t14 = t13 ^ t12;
        ulong t15 = y8 & y10;
        ulong t16 = t15 ^ t12;
        ulong t17 = t4 ^ t14;
        ulong t18 = t6 ^ t16;
        ulong t19 = t9 ^ t14;
        ulong t20 = t11 ^ t16;
        ulong t21 = t17 ^ y20;
        ulong t22 = t18 ^ y19;
        ulong t23 = t19 ^ y21;
        ulong t24 = t20 ^ y18;

        ulong t25 = t21 ^ t22;
        ulong t26 = t21 & t23;
        ulong t27 = t24 ^ t26;
        ulong t28 = t25 & t27;
        ulong t29 = t28 ^ t22;
        ulong t30 = t23 ^ t24;
        ulong t31 = t22 ^ t26;
        ulong t32 = t31 & t30;
        ulong t33 = t32 ^ t24;
        ulong t34 = t23 ^ t33;
        ulong t35 = t27 ^ t33;
        ulong t36 = t24 & t35;
        ulong t37 = t36 ^ t34;
        ulong t38 = t27 ^ t36;
        ulong t39 = t29 & t38;
        ulong t40 = t25 ^ t39;

        ulong t41 = t40 ^ t37;
        ulong t42 = t29 ^ t33;
        ulong t43 = t29 ^ t40;
        ulong t44 = t33 ^ t37;
        ulong t45 = t42 ^ t41;
        ulong z0 = t44 & y15;
        ulong z1 = t37 & y6;
        ulong z2 = t33 & x7;
        ulong z3 = t43 & y16;
        ulong z4 = t40 & y1;
        ulong z5 = t29 & y7;
        ulong z6 = t42 & y11;
        ulong z7 = t45 & y17;
        ulong z8 = t41 & y10;
        ulong z9 = t44 & y12;
        ulong z10 = t37 & y3;
        ulong z11 = t33 & y4;
        ulong z12 = t43 & y13;
        ulong z13 = t40 & y5;
        ulong z14 = t29 & y2;
        ulong z15 = t42 & y9;
        ulong z16 = t45 & y14;
        ulong z17 = t41 & y8;

        // The bottom linear transformation, with the affine constant folded
        // into the four complements.
        ulong t46 = z15 ^ z16;
        ulong t47 = z10 ^ z11;
        ulong t48 = z5 ^ z13;
        ulong t49 = z9 ^ z10;
        ulong t50 = z2 ^ z12;
        ulong t51 = z2 ^ z5;
        ulong t52 = z7 ^ z8;
        ulong t53 = z0 ^ z3;
        ulong t54 = z6 ^ z7;
        ulong t55 = z16 ^ z17;
        ulong t56 = z12 ^ t48;
        ulong t57 = t50 ^ t53;
        ulong t58 = z4 ^ t46;
        ulong t59 = z3 ^ t54;
        ulong t60 = t46 ^ t57;
        ulong t61 = z14 ^ t57;
        ulong t62 = t52 ^ t58;
        ulong t63 = t49 ^ t58;
        ulong t64 = z4 ^ t59;
        ulong t65 = t61 ^ t62;
        ulong t66 = z1 ^ t63;
        ulong s0 = t59 ^ t63;
        ulong s6 = t56 ^ ~t62;
        ulong s7 = t48 ^ ~t60;
        ulong t67 = t64 ^ t65;
        ulong s3 = t53 ^ t66;
        ulong s4 = t51 ^ t66;
        ulong s5 = t47 ^ t65;
        ulong s1 = t64 ^ ~s3;
        ulong s2 = t55 ^ ~t67;

        q[7u] = s0;
        q[6u] = s1;
        q[5u] = s2;
        q[4u] = s3;
        q[3u] = s4;
        q[2u] = s5;
        q[1u] = s6;
        q[0u] = s7;
    }

    /// The inverse S-box. Inversion in the field is its own inverse, so the
    /// forward circuit between two applications of the inverse affine map is
    /// the whole of it.
    static void UnsubstituteBytes(ref ulong[8] q)
    {
        UndoAffineMap(ref q);
        SubstituteBytes(ref q);
        UndoAffineMap(ref q);
    }

    /// The inverse of the S-box's affine map, constant included: bit `i` is
    /// bits `i + 2`, `i + 5` and `i + 7` of the input, after 0x63 is removed.
    static void UndoAffineMap(ref ulong[8] q)
    {
        ulong q0 = ~q[0u];
        ulong q1 = ~q[1u];
        ulong q2 = q[2u];
        ulong q3 = q[3u];
        ulong q4 = q[4u];
        ulong q5 = ~q[5u];
        ulong q6 = ~q[6u];
        ulong q7 = q[7u];

        q[7u] = q1 ^ q4 ^ q6;
        q[6u] = q0 ^ q3 ^ q5;
        q[5u] = q7 ^ q2 ^ q4;
        q[4u] = q6 ^ q1 ^ q3;
        q[3u] = q5 ^ q0 ^ q2;
        q[2u] = q4 ^ q7 ^ q1;
        q[1u] = q3 ^ q6 ^ q0;
        q[0u] = q2 ^ q5 ^ q7;
    }

    /// Row `r` rotated left by `r` columns, a column being four bits.
    static void ShiftRows(ref ulong[8] q)
    {
        for (nuint i = 0u; i < 8u; i++)
        {
            ulong x = q[i];
            q[i] = (x & 0x000000000000FFFFu) |
                   ((x & 0x00000000FFF00000u) >> 4) | ((x & 0x00000000000F0000u) << 12) |
                   ((x & 0x0000FF0000000000u) >> 8) | ((x & 0x000000FF00000000u) << 8) |
                   ((x & 0xF000000000000000u) >> 12) | ((x & 0x0FFF000000000000u) << 4);
        }
    }

    static void UnshiftRows(ref ulong[8] q)
    {
        for (nuint i = 0u; i < 8u; i++)
        {
            ulong x = q[i];
            q[i] = (x & 0x000000000000FFFFu) |
                   ((x & 0x000000000FFF0000u) << 4) | ((x & 0x00000000F0000000u) >> 12) |
                   ((x & 0x000000FF00000000u) << 8) | ((x & 0x0000FF0000000000u) >> 8) |
                   ((x & 0x000F000000000000u) << 12) | ((x & 0xFFF0000000000000u) >> 4);
        }
    }

    /// Each output row is 2·a + 3·b + c + d over the rows below it. Rotating a
    /// word right by 16 brings the next row down, and by 32 the one after, so
    /// the column is never taken apart; doubling in the field is a shift of the
    /// bit planes with the polynomial's taps where the top bit lands.
    static void MixColumns(ref ulong[8] q)
    {
        ulong q0 = q[0u];
        ulong q1 = q[1u];
        ulong q2 = q[2u];
        ulong q3 = q[3u];
        ulong q4 = q[4u];
        ulong q5 = q[5u];
        ulong q6 = q[6u];
        ulong q7 = q[7u];
        ulong r0 = RotateRight(q0, 16);
        ulong r1 = RotateRight(q1, 16);
        ulong r2 = RotateRight(q2, 16);
        ulong r3 = RotateRight(q3, 16);
        ulong r4 = RotateRight(q4, 16);
        ulong r5 = RotateRight(q5, 16);
        ulong r6 = RotateRight(q6, 16);
        ulong r7 = RotateRight(q7, 16);

        q[0u] = q7 ^ r7 ^ r0 ^ RotateRight(q0 ^ r0, 32);
        q[1u] = q0 ^ r0 ^ q7 ^ r7 ^ r1 ^ RotateRight(q1 ^ r1, 32);
        q[2u] = q1 ^ r1 ^ r2 ^ RotateRight(q2 ^ r2, 32);
        q[3u] = q2 ^ r2 ^ q7 ^ r7 ^ r3 ^ RotateRight(q3 ^ r3, 32);
        q[4u] = q3 ^ r3 ^ q7 ^ r7 ^ r4 ^ RotateRight(q4 ^ r4, 32);
        q[5u] = q4 ^ r4 ^ r5 ^ RotateRight(q5 ^ r5, 32);
        q[6u] = q5 ^ r5 ^ r6 ^ RotateRight(q6 ^ r6, 32);
        q[7u] = q6 ^ r6 ^ r7 ^ RotateRight(q7 ^ r7, 32);
    }

    /// 14·a + 11·b + 13·c + 9·d, the same way: 14·q + 11·r for the row and
    /// the row below it, and 13·q + 9·r rotated by two rows for the others.
    static void UnmixColumns(ref ulong[8] q)
    {
        ulong q0 = q[0u];
        ulong q1 = q[1u];
        ulong q2 = q[2u];
        ulong q3 = q[3u];
        ulong q4 = q[4u];
        ulong q5 = q[5u];
        ulong q6 = q[6u];
        ulong q7 = q[7u];
        ulong r0 = RotateRight(q0, 16);
        ulong r1 = RotateRight(q1, 16);
        ulong r2 = RotateRight(q2, 16);
        ulong r3 = RotateRight(q3, 16);
        ulong r4 = RotateRight(q4, 16);
        ulong r5 = RotateRight(q5, 16);
        ulong r6 = RotateRight(q6, 16);
        ulong r7 = RotateRight(q7, 16);

        q[0u] = q5 ^ q6 ^ q7 ^ r0 ^ r5 ^ r7 ^ RotateRight(q0 ^ q5 ^ q6 ^ r0 ^ r5, 32);
        q[1u] = q0 ^ q5 ^ r0 ^ r1 ^ r5 ^ r6 ^ r7 ^ RotateRight(q1 ^ q5 ^ q7 ^ r1 ^ r5 ^ r6, 32);
        q[2u] = q0 ^ q1 ^ q6 ^ r1 ^ r2 ^ r6 ^ r7 ^ RotateRight(q0 ^ q2 ^ q6 ^ r2 ^ r6 ^ r7, 32);
        q[3u] = q0 ^ q1 ^ q2 ^ q5 ^ q6 ^ r0 ^ r2 ^ r3 ^ r5 ^
                RotateRight(q0 ^ q1 ^ q3 ^ q5 ^ q6 ^ q7 ^ r0 ^ r3 ^ r5 ^ r7, 32);
        q[4u] = q1 ^ q2 ^ q3 ^ q5 ^ r1 ^ r3 ^ r4 ^ r5 ^ r6 ^ r7 ^
                RotateRight(q1 ^ q2 ^ q4 ^ q5 ^ q7 ^ r1 ^ r4 ^ r5 ^ r6, 32);
        q[5u] = q2 ^ q3 ^ q4 ^ q6 ^ r2 ^ r4 ^ r5 ^ r6 ^ r7 ^
                RotateRight(q2 ^ q3 ^ q5 ^ q6 ^ r2 ^ r5 ^ r6 ^ r7, 32);
        q[6u] = q3 ^ q4 ^ q5 ^ q7 ^ r3 ^ r5 ^ r6 ^ r7 ^
                RotateRight(q3 ^ q4 ^ q6 ^ q7 ^ r3 ^ r6 ^ r7, 32);
        q[7u] = q4 ^ q5 ^ q6 ^ r4 ^ r6 ^ r7 ^ RotateRight(q4 ^ q5 ^ q7 ^ r4 ^ r7, 32);
    }

    // ------------------------------------------------------------ the key

    /// The FIPS-197 key expansion, bitsliced a round key at a time.
    ///
    /// The words are little-endian, so RotWord is a rotate right by eight.
    /// SubWord goes through the same circuit as the data, so the key never
    /// indexes a table either; the branches are on the word's position, which
    /// is public.
    static ulong[] ExpandKey(ReadOnlySpan<byte> key, nuint rounds)
    {
        nuint keyWords = key.Length / 4u;
        nuint words = 4u * (rounds + 1u);

        uint[60] schedule;
        for (nuint i = 0u; i < key.Length; i++)
            schedule[i / 4u] |= (uint)key[i] << (int)(8u * (i % 4u));

        uint word = schedule[keyWords - 1u];
        uint constant = 1u;
        nuint position = 0u;
        for (nuint i = keyWords; i < words; i++)
        {
            if (position == 0u)
            {
                word = SubstituteWord(RotateRight(word, 8)) ^ constant;
                constant = (constant << 1) ^ ((constant >> 7) * 0x11Bu);
            }
            else if (keyWords > 6u && position == 4u)
            {
                word = SubstituteWord(word);
            }

            word ^= schedule[i - keyWords];
            schedule[i] = word;

            position++;
            if (position == keyWords)
                position = 0u;
        }

        // Four copies of a round key, bitsliced, are eight words in which every
        // nibble is all ones or all zeros; they are what the rounds add.
        ulong[] expanded = new ulong[8u * (rounds + 1u)];
        ulong[8] q;
        for (nuint round = 0u; round <= rounds; round++)
        {
            nuint at = round * 4u;
            ulong low = SpreadWord(schedule[at]) | (SpreadWord(schedule[at + 2u]) << 8);
            ulong high = SpreadWord(schedule[at + 1u]) | (SpreadWord(schedule[at + 3u]) << 8);
            for (nuint i = 0u; i < 4u; i++)
            {
                q[i] = low;
                q[i + 4u] = high;
            }

            Orthogonalize(ref q);
            for (nuint i = 0u; i < 8u; i++)
                expanded[round * 8u + i] = q[i];
        }

        return expanded;
    }

    /// The S-box on each byte of `word`, through the bitsliced circuit.
    static uint SubstituteWord(uint word)
    {
        ulong[8] q;
        q[0u] = (ulong)word;
        Orthogonalize(ref q);
        SubstituteBytes(ref q);
        Orthogonalize(ref q);
        return (uint)q[0u];
    }

    static byte[] CopyBytes(ReadOnlySpan<byte> data) => data.ToArray();
}
