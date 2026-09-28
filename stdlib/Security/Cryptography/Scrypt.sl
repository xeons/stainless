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

// ===================================================== key derivation

/// scrypt (RFC 7914): a password hash that costs memory as well as time.
///
/// ```csharp
/// var key = try Scrypt.DeriveKey(password, salt, 32768u, 8u, 1u, 32u);
/// ```
///
/// **Memory is the point.** PBKDF2 is a loop an attacker runs on a thousand
/// GPU cores at once. scrypt fills 128 · `blockSize` · `cost` bytes and reads
/// them back in an order it cannot predict, so each guess needs that memory
/// for its whole duration, and memory is what a GPU has least of per core.
/// `cost` = 2^15 with `blockSize` = 8 is 32 MiB, which is the usual interactive
/// answer. Raise `cost` rather than `parallelism`: the passes run one after
/// another here, so `parallelism` buys time and no memory.
///
/// **The second pass reads memory at addresses derived from the password.**
/// That is what makes it memory-hard, and it is also a cache-timing channel:
/// an attacker who shares the machine and can watch the cache learns
/// something about the password. It is inherent in scrypt. `Argon2id`
/// spends its first half on addresses that do not depend on the password,
/// which is why RFC 9106 prefers it.
///
/// Built on `Rfc2898DeriveBytes.Pbkdf2` over HMAC-SHA-256 and the Salsa20/8
/// core, as the RFC defines it.
///
/// @see Rfc2898DeriveBytes
public static class Scrypt
{
    /// The most working memory a derivation may ask for: 4 GiB, which is
    /// `cost` = 2^22 at `blockSize` = 8. Parameters read from a stored hash
    /// are input like any other, and this bounds what one can make a call
    /// allocate.
    ///
    /// @value 2^32 bytes.
    public const ulong MaxMemoryBytes = 0x100000000u;

    /// `length` bytes derived from `password` and `salt`.
    ///
    /// @param password     the secret to stretch
    /// @param salt         at least sixteen random bytes, stored beside the result
    /// @param cost         N, the number of blocks the memory holds; a power of two
    ///                     greater than one
    /// @param blockSize    r, the width of a block in 128-byte units; 8 is the usual answer
    /// @param parallelism  p, how many independent passes to run, one after another here
    /// @param length       how many bytes to derive
    /// @failure CryptoError.Parameter  `cost` is not a power of two above one; `blockSize`,
    ///                                 `parallelism` or `length` is zero; `blockSize` times
    ///                                 `parallelism` reaches 2^30; `cost` reaches 2^(16 ·
    ///                                 `blockSize`); `length` is past (2^32 - 1) · 32; or the
    ///                                 memory needed is past `MaxMemoryBytes`
    public static Result<byte[], CryptoError> DeriveKey(ReadOnlySpan<byte> password,
                                                        ReadOnlySpan<byte> salt, nuint cost,
                                                        nuint blockSize, nuint parallelism,
                                                        nuint length)
    {
        if (!AreParametersValid(cost, blockSize, parallelism, length))
            return Fail(CryptoError.Parameter);

        nuint chunk = 128u * blockSize;
        nuint expandedLength = chunk * parallelism;
        var expanded = Rfc2898DeriveBytes.Pbkdf2(password, salt, 1u, new Sha256(), expandedLength);
        if (!expanded.Ok)
            return Fail(expanded.Error);

        byte[] blocks = expanded.Value;
        uint[] memory = new uint[cost * 32u * blockSize];
        for (nuint i = 0u; i < parallelism; i++)
            MixMemory(blocks, i * chunk, cost, blockSize, memory);

        for (nuint i = 0u; i < memory.Length; i++)
            memory[i] = 0u;

        var derived = Rfc2898DeriveBytes.Pbkdf2(password, blocks, 1u, new Sha256(), length);
        CryptographicOperations.ZeroMemory(blocks);
        return derived;
    }

    /// The limits of RFC 7914 §2, and `MaxMemoryBytes`.
    static bool AreParametersValid(nuint cost, nuint blockSize, nuint parallelism, nuint length)
    {
        if (cost < 2u || (cost & (cost - 1u)) != 0u)
            return false;
        if (blockSize == 0u || parallelism == 0u || length == 0u)
            return false;

        ulong width = (ulong)blockSize;
        if (width >= 0x40000000u || width * (ulong)parallelism >= 0x40000000u)
            return false;
        if (width < 4u && (ulong)cost >= ((ulong)1u << (int)(16u * (uint)width)))
            return false;
        if ((ulong)length > 0x1FFFFFFFE0u)
            return false;

        // Both products are below 2^62 once the checks above have passed, so
        // neither can wrap.
        ulong chunk = 128u * width;
        if ((ulong)cost > MaxMemoryBytes / chunk)
            return false;
        if (chunk * (ulong)parallelism > MaxMemoryBytes)
            return false;

        return true;
    }

    /// ROMix of RFC 7914 §5, on the `128 · blockSize` bytes of `blocks` at
    /// `at`, in place. `memory` is the V array, `32 · blockSize · cost` words.
    static void MixMemory(byte[] blocks, nuint at, nuint cost, nuint blockSize, uint[] memory)
    {
        nuint words = 32u * blockSize;
        uint[] current = new uint[words];
        uint[] next = new uint[words];
        uint[] mixing = new uint[16u];

        for (nuint i = 0u; i < words; i++)
            current[i] = ReadLittleWord(blocks, at + i * 4u);

        for (nuint i = 0u; i < cost; i++)
        {
            nuint start = i * words;
            for (nuint k = 0u; k < words; k++)
                memory[start + k] = current[k];

            MixBlocks(current, next, blockSize, mixing);
            uint[] swap = current;
            current = next;
            next = swap;
        }

        // Integerify: the first word of the last 64-byte block. `cost` is at
        // most 2^25 under `MaxMemoryBytes`, so one word holds every index.
        nuint last = (2u * blockSize - 1u) * 16u;
        nuint mask = cost - 1u;
        for (nuint i = 0u; i < cost; i++)
        {
            nuint start = ((nuint)current[last] & mask) * words;
            for (nuint k = 0u; k < words; k++)
                current[k] ^= memory[start + k];

            MixBlocks(current, next, blockSize, mixing);
            uint[] swap = current;
            current = next;
            next = swap;
        }

        for (nuint i = 0u; i < words; i++)
        {
            WriteLittleWord(blocks, at + i * 4u, current[i]);
            current[i] = 0u;
            next[i] = 0u;
        }
    }

    /// BlockMix of RFC 7914 §4: `input` through Salsa20/8 a 64-byte block at a
    /// time, chained, into `output` with the even blocks first and the odd
    /// ones after.
    static void MixBlocks(uint[] input, uint[] output, nuint blockSize, uint[] mixing)
    {
        nuint last = (2u * blockSize - 1u) * 16u;
        for (nuint k = 0u; k < 16u; k++)
            mixing[k] = input[last + k];

        for (nuint i = 0u; i < 2u * blockSize; i++)
        {
            nuint from = i * 16u;
            for (nuint k = 0u; k < 16u; k++)
                mixing[k] ^= input[from + k];

            ComputeSalsa(mixing);

            nuint to = (i / 2u + (i % 2u) * blockSize) * 16u;
            for (nuint k = 0u; k < 16u; k++)
                output[to + k] = mixing[k];
        }
    }

    /// The Salsa20/8 core of RFC 7914 §3, on `block` in place.
    ///
    /// Sixteen locals rather than an array, which is the difference between
    /// registers and a bounds-checked load for every one of 256 operations.
    static void ComputeSalsa(uint[] block)
    {
        uint x0 = block[0u];
        uint x1 = block[1u];
        uint x2 = block[2u];
        uint x3 = block[3u];
        uint x4 = block[4u];
        uint x5 = block[5u];
        uint x6 = block[6u];
        uint x7 = block[7u];
        uint x8 = block[8u];
        uint x9 = block[9u];
        uint x10 = block[10u];
        uint x11 = block[11u];
        uint x12 = block[12u];
        uint x13 = block[13u];
        uint x14 = block[14u];
        uint x15 = block[15u];

        for (nuint round = 0u; round < 4u; round++)
        {
            x4 ^= RotateLeft(x0 + x12, 7);
            x8 ^= RotateLeft(x4 + x0, 9);
            x12 ^= RotateLeft(x8 + x4, 13);
            x0 ^= RotateLeft(x12 + x8, 18);

            x9 ^= RotateLeft(x5 + x1, 7);
            x13 ^= RotateLeft(x9 + x5, 9);
            x1 ^= RotateLeft(x13 + x9, 13);
            x5 ^= RotateLeft(x1 + x13, 18);

            x14 ^= RotateLeft(x10 + x6, 7);
            x2 ^= RotateLeft(x14 + x10, 9);
            x6 ^= RotateLeft(x2 + x14, 13);
            x10 ^= RotateLeft(x6 + x2, 18);

            x3 ^= RotateLeft(x15 + x11, 7);
            x7 ^= RotateLeft(x3 + x15, 9);
            x11 ^= RotateLeft(x7 + x3, 13);
            x15 ^= RotateLeft(x11 + x7, 18);

            x1 ^= RotateLeft(x0 + x3, 7);
            x2 ^= RotateLeft(x1 + x0, 9);
            x3 ^= RotateLeft(x2 + x1, 13);
            x0 ^= RotateLeft(x3 + x2, 18);

            x6 ^= RotateLeft(x5 + x4, 7);
            x7 ^= RotateLeft(x6 + x5, 9);
            x4 ^= RotateLeft(x7 + x6, 13);
            x5 ^= RotateLeft(x4 + x7, 18);

            x11 ^= RotateLeft(x10 + x9, 7);
            x8 ^= RotateLeft(x11 + x10, 9);
            x9 ^= RotateLeft(x8 + x11, 13);
            x10 ^= RotateLeft(x9 + x8, 18);

            x12 ^= RotateLeft(x15 + x14, 7);
            x13 ^= RotateLeft(x12 + x15, 9);
            x14 ^= RotateLeft(x13 + x12, 13);
            x15 ^= RotateLeft(x14 + x13, 18);
        }

        block[0u] += x0;
        block[1u] += x1;
        block[2u] += x2;
        block[3u] += x3;
        block[4u] += x4;
        block[5u] += x5;
        block[6u] += x6;
        block[7u] += x7;
        block[8u] += x8;
        block[9u] += x9;
        block[10u] += x10;
        block[11u] += x11;
        block[12u] += x12;
        block[13u] += x13;
        block[14u] += x14;
        block[15u] += x15;
    }
}
