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

// -------------------------------------------------------------------- MD5

/// MD5, which is **broken** and is here because formats still carry it.
///
/// Collisions are cheap and have been since 2004: two inputs with the same
/// digest can be produced on a laptop in seconds. That makes it unusable for a
/// signature, a certificate or anything else where an adversary chooses the
/// input. It remains what an old protocol field, a package manifest and a
/// legacy database column contain, and refusing to implement it does not make
/// those go away.
///
/// Use `Sha256` for anything new.
///
/// @see Sha256
public sealed class Md5 : HashAlgorithm
{
    uint _a;
    uint _b;
    uint _c;
    uint _d;
    uint[] _sines;
    uint[] _shifts;

    public Md5()
    {
        base(64u, 8u, false);

        // floor(abs(sin(i + 1)) * 2^32), written out rather than computed:
        // the table is the specification, and a rounding that differed by one
        // in the last place would be a hash that is silently not MD5.
        _sines = [
            0xD76AA478u, 0xE8C7B756u, 0x242070DBu, 0xC1BDCEEEu,
            0xF57C0FAFu, 0x4787C62Au, 0xA8304613u, 0xFD469501u,
            0x698098D8u, 0x8B44F7AFu, 0xFFFF5BB1u, 0x895CD7BEu,
            0x6B901122u, 0xFD987193u, 0xA679438Eu, 0x49B40821u,
            0xF61E2562u, 0xC040B340u, 0x265E5A51u, 0xE9B6C7AAu,
            0xD62F105Du, 0x02441453u, 0xD8A1E681u, 0xE7D3FBC8u,
            0x21E1CDE6u, 0xC33707D6u, 0xF4D50D87u, 0x455A14EDu,
            0xA9E3E905u, 0xFCEFA3F8u, 0x676F02D9u, 0x8D2A4C8Au,
            0xFFFA3942u, 0x8771F681u, 0x6D9D6122u, 0xFDE5380Cu,
            0xA4BEEA44u, 0x4BDECFA9u, 0xF6BB4B60u, 0xBEBFBC70u,
            0x289B7EC6u, 0xEAA127FAu, 0xD4EF3085u, 0x04881D05u,
            0xD9D4D039u, 0xE6DB99E5u, 0x1FA27CF8u, 0xC4AC5665u,
            0xF4292244u, 0x432AFF97u, 0xAB9423A7u, 0xFC93A039u,
            0x655B59C3u, 0x8F0CCC92u, 0xFFEFF47Du, 0x85845DD1u,
            0x6FA87E4Fu, 0xFE2CE6E0u, 0xA3014314u, 0x4E0811A1u,
            0xF7537E82u, 0xBD3AF235u, 0x2AD7D2BBu, 0xEB86D391u,
        ];

        _shifts = [
            7u, 12u, 17u, 22u, 7u, 12u, 17u, 22u,
            7u, 12u, 17u, 22u, 7u, 12u, 17u, 22u,
            5u, 9u, 14u, 20u, 5u, 9u, 14u, 20u,
            5u, 9u, 14u, 20u, 5u, 9u, 14u, 20u,
            4u, 11u, 16u, 23u, 4u, 11u, 16u, 23u,
            4u, 11u, 16u, 23u, 4u, 11u, 16u, 23u,
            6u, 10u, 15u, 21u, 6u, 10u, 15u, 21u,
            6u, 10u, 15u, 21u, 6u, 10u, 15u, 21u,
        ];

        InitializeState();
    }

    public override String Name => "MD5";

    public override nuint HashSizeInBytes => 16u;

    /// The digest of `data`, with no object to keep.
    public static byte[] HashData(byte[:] data) => new Md5().ComputeHash(data);

    protected override void InitializeState()
    {
        _a = 0x67452301u;
        _b = 0xEFCDAB89u;
        _c = 0x98BADCFEu;
        _d = 0x10325476u;
    }

    protected override void CompressBlock(byte[] block)
    {
        uint[] words = new uint[16u];
        for (nuint i = 0u; i < 16u; i++)
            words[i] = ReadLittleWord(block, i * 4u);

        uint a = _a;
        uint b = _b;
        uint c = _c;
        uint d = _d;

        for (nuint step = 0u; step < 64u; step++)
        {
            uint mixed = 0u;
            nuint word = 0u;

            if (step < 16u)
            {
                mixed = (b & c) | (~b & d);
                word = step;
            }
            else if (step < 32u)
            {
                mixed = (d & b) | (~d & c);
                word = (5u * step + 1u) % 16u;
            }
            else if (step < 48u)
            {
                mixed = b ^ c ^ d;
                word = (3u * step + 5u) % 16u;
            }
            else
            {
                mixed = c ^ (b | ~d);
                word = (7u * step) % 16u;
            }

            uint rotated = a + mixed + _sines[step] + words[word];
            a = d;
            d = c;
            c = b;
            b = b + RotateLeft(rotated, (int)_shifts[step]);
        }

        _a += a;
        _b += b;
        _c += c;
        _d += d;
    }

    protected override byte[] ComputeDigest()
    {
        byte[] digest = new byte[16u];
        WriteLittleWord(digest, 0u, _a);
        WriteLittleWord(digest, 4u, _b);
        WriteLittleWord(digest, 8u, _c);
        WriteLittleWord(digest, 12u, _d);
        return digest;
    }
}
