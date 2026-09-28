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

module Standard.IO.Compression;

// ------------------------------------------------------ canonical decoding

// One canonical Huffman code, as RFC 1951 §3.2.2 builds it from lengths.
//
// A code of up to `FastBits` bits is found by one lookup of the next
// `FastBits` input bits. A longer one, or a pattern the fast table does not
// hold, is walked a bit at a time over the per-length counts, which is also
// what finds a pattern no code stands for.
class HuffmanDecoder
{
    const int FastBits = 10;
    const nuint FastSize = 1024;
    const int MaxBits = 15;

    // (symbol << 4) | length, or zero for a code longer than FastBits.
    ushort[] _fast;
    ushort[] _counts;
    ushort[] _symbols;
    ushort[] _offsets;
    ushort[] _nextCode;

    HuffmanDecoder(nuint maxSymbols)
    {
        _fast = new ushort[FastSize];
        _counts = new ushort[16];
        _symbols = new ushort[maxSymbols];
        _offsets = new ushort[16];
        _nextCode = new ushort[16];
    }

    // Builds the code for `count` lengths from `start`, answering false when
    // they do not describe one. An over-subscribed set never does. An
    // incomplete one does only when `allowSparse` and it is empty or one code
    // of one bit, the two cases RFC 1951 and zlib accept for distances.
    bool Build(byte[] lengths, nuint start, nuint count, bool allowSparse)
    {
        for (nuint i = 0; i < 16u; i++)
            _counts[i] = 0;
        for (nuint i = 0; i < count; i++)
            _counts[lengths[start + i]]++;

        int left = 1;
        for (int bits = 1; bits <= MaxBits; bits++)
        {
            left <<= 1;
            left -= (int)_counts[bits];
            if (left < 0)
                return false;
        }

        if (left > 0)
        {
            int used = 0;
            for (int bits = 1; bits <= MaxBits; bits++)
                used += (int)_counts[bits];
            if (!allowSparse || used > 1 || (used == 1 && _counts[1] != 1))
                return false;
        }

        _offsets[1] = 0;
        for (int bits = 1; bits < MaxBits; bits++)
            _offsets[bits + 1] = (ushort)(_offsets[bits] + _counts[bits]);

        int code = 0;
        _counts[0] = 0;
        for (int bits = 1; bits <= MaxBits; bits++)
        {
            code = (code + (int)_counts[bits - 1]) << 1;
            _nextCode[bits] = (ushort)code;
        }

        for (nuint i = 0; i < FastSize; i++)
            _fast[i] = 0;

        for (nuint symbol = 0; symbol < count; symbol++)
        {
            int length = (int)lengths[start + symbol];
            if (length == 0)
                continue;

            _symbols[_offsets[length]] = (ushort)symbol;
            _offsets[length]++;

            uint assigned = (uint)_nextCode[length];
            _nextCode[length]++;
            if (length > FastBits)
                continue;

            nuint slot = (nuint)ReverseBits(assigned, length);
            nuint step = (nuint)1 << length;
            ushort entry = (ushort)((symbol << 4) | (nuint)length);
            while (slot < FastSize)
            {
                _fast[slot] = entry;
                slot += step;
            }
        }

        return true;
    }

    // The symbol the low bits of `peeked` start with, and its length in
    // `length`; -1 when no code matches. The bits past the input's end are
    // zeros, so a caller MUST check `length` against what it holds.
    int DecodeSymbol(ulong peeked, out int length)
    {
        uint entry = (uint)_fast[(nuint)(peeked & 1023u)];
        if (entry != 0u)
        {
            length = (int)(entry & 15u);
            return (int)(entry >> 4);
        }

        int code = 0;
        int first = 0;
        int index = 0;
        for (int bits = 1; bits <= MaxBits; bits++)
        {
            code |= (int)((peeked >> (bits - 1)) & 1u);
            int count = (int)_counts[bits];
            if (code - count < first)
            {
                length = bits;
                return (int)_symbols[index + (code - first)];
            }
            index += count;
            first += count;
            first <<= 1;
            code <<= 1;
        }

        length = 0;
        return -1;
    }
}

// `value`'s low `count` bits in the opposite order: a Huffman code is
// defined most significant bit first and packed into the stream least
// significant bit first.
uint ReverseBits(uint value, int count)
{
    uint reversed = 0;
    for (int i = 0; i < count; i++)
    {
        reversed = (reversed << 1) | (value & 1u);
        value >>= 1;
    }
    return reversed;
}
