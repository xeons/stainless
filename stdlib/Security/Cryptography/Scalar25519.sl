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

// ================================================================ mod L

/// Arithmetic modulo L = 2^252 + 27742317777372353535851937790883648493, the
/// order of Ed25519's base point, on 32-byte little-endian scalars.
///
/// Reduction is binary long division: one shift and one masked subtraction
/// per bit of the input, 512 of them for a hash. That is slower than the
/// Barrett reduction a tuned implementation uses, and still small beside the
/// two scalar multiplications a signature needs.
///
/// **Constant time.** The loops run a fixed number of times, and whether a
/// subtraction is kept is a mask made from its borrow.
static class Scalar25519
{
    /// L as eight little-endian words. Inline, so there is no object to
    /// outlive the program.
    static readonly uint[8] s_order = [
        0x5CF5D3EDu, 0x5812631Au, 0xA2F79CD6u, 0x14DEF9DEu, 0u, 0u, 0u, 0x10000000u,
    ];

    /// Sixty-four little-endian bytes, such as a SHA-512 digest, modulo L.
    static byte[] ReduceWide(ReadOnlySpan<byte> wide) => ReduceWords(ReadWords(wide, 16u));

    /// `left * right + addend` modulo L, each of them 32 bytes.
    static byte[] MultiplyAdd(ReadOnlySpan<byte> left, ReadOnlySpan<byte> right,
                              ReadOnlySpan<byte> addend)
    {
        uint[] leftWords = ReadWords(left, 8u);
        uint[] rightWords = ReadWords(right, 8u);
        uint[] addendWords = ReadWords(addend, 8u);
        uint[] product = new uint[16u];

        // A word product plus two words is at most 2^64 − 1, so a row never
        // loses a carry.
        for (nuint i = 0u; i < 8u; i++)
        {
            ulong carry = 0u;
            for (nuint j = 0u; j < 8u; j++)
            {
                ulong sum = (ulong)leftWords[i] * (ulong)rightWords[j] +
                            (ulong)product[i + j] + carry;
                product[i + j] = (uint)(sum & 0xFFFFFFFFu);
                carry = sum >> 32;
            }
            product[i + 8u] = (uint)carry;
        }

        // Both factors are below 2^256 and the addend below 2^253 in every
        // use, so the sum stays below 2^512.
        ulong running = 0u;
        for (nuint i = 0u; i < 16u; i++)
        {
            running += (ulong)product[i];
            if (i < 8u)
                running += (ulong)addendWords[i];
            product[i] = (uint)(running & 0xFFFFFFFFu);
            running >>= 32;
        }

        return ReduceWords(product);
    }

    /// Whether 32 bytes are a scalar below L, which RFC 8032 requires of a
    /// signature's S.
    static bool IsCanonical(ReadOnlySpan<byte> scalar)
    {
        uint[] words = ReadWords(scalar, 8u);
        ulong borrow = 0u;
        for (nuint i = 0u; i < 8u; i++)
        {
            ulong difference = (ulong)words[i] - (ulong)s_order[i] - borrow;
            borrow = difference >> 63;
        }
        return borrow == 1u;
    }

    /// Any number of little-endian words modulo L, as 32 bytes.
    static byte[] ReduceWords(uint[] words)
    {
        uint[] remainder = new uint[8u];
        uint[] difference = new uint[8u];

        for (nuint position = words.Length * 32u; position > 0u; position--)
        {
            nuint bit = position - 1u;

            // The remainder is below L, so twice it plus one bit is below
            // 2L < 2^254 and the shift loses nothing.
            uint carry = (words[bit / 32u] >> (int)(bit % 32u)) & 1u;
            for (nuint i = 0u; i < 8u; i++)
            {
                uint word = remainder[i];
                remainder[i] = (word << 1) | carry;
                carry = word >> 31;
            }

            ulong borrow = 0u;
            for (nuint i = 0u; i < 8u; i++)
            {
                ulong subtracted = (ulong)remainder[i] - (ulong)s_order[i] - borrow;
                difference[i] = (uint)(subtracted & 0xFFFFFFFFu);
                borrow = subtracted >> 63;
            }

            // A borrow means the remainder was already below L.
            uint keep = OpaqueCopy(0u - (uint)borrow);
            for (nuint i = 0u; i < 8u; i++)
                remainder[i] = (remainder[i] & keep) | (difference[i] & ~keep);
        }

        byte[] bytes = new byte[32u];
        for (nuint i = 0u; i < 8u; i++)
            WriteLittleWord(bytes, i * 4u, remainder[i]);
        return bytes;
    }

    /// `count` little-endian words from the front of `bytes`.
    static uint[] ReadWords(ReadOnlySpan<byte> bytes, nuint count)
    {
        uint[] words = new uint[count];
        for (nuint i = 0u; i < count; i++)
        {
            nuint at = i * 4u;
            words[i] = ((uint)bytes[at + 3u] << 24) | ((uint)bytes[at + 2u] << 16) |
                       ((uint)bytes[at + 1u] << 8) | (uint)bytes[at];
        }
        return words;
    }
}
