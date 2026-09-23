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

// ---------------------------------------------------------------- SHA-256

/// SHA-256: the one to reach for when nothing else decides.
public sealed class Sha256 : HashAlgorithm
{
    uint[] _state;
    uint[] _constants;

    public Sha256()
    {
        base(64u, 8u, true);

        _state = new uint[8u];
        _constants = [
            0x428A2F98u, 0x71374491u, 0xB5C0FBCFu, 0xE9B5DBA5u,
            0x3956C25Bu, 0x59F111F1u, 0x923F82A4u, 0xAB1C5ED5u,
            0xD807AA98u, 0x12835B01u, 0x243185BEu, 0x550C7DC3u,
            0x72BE5D74u, 0x80DEB1FEu, 0x9BDC06A7u, 0xC19BF174u,
            0xE49B69C1u, 0xEFBE4786u, 0x0FC19DC6u, 0x240CA1CCu,
            0x2DE92C6Fu, 0x4A7484AAu, 0x5CB0A9DCu, 0x76F988DAu,
            0x983E5152u, 0xA831C66Du, 0xB00327C8u, 0xBF597FC7u,
            0xC6E00BF3u, 0xD5A79147u, 0x06CA6351u, 0x14292967u,
            0x27B70A85u, 0x2E1B2138u, 0x4D2C6DFCu, 0x53380D13u,
            0x650A7354u, 0x766A0ABBu, 0x81C2C92Eu, 0x92722C85u,
            0xA2BFE8A1u, 0xA81A664Bu, 0xC24B8B70u, 0xC76C51A3u,
            0xD192E819u, 0xD6990624u, 0xF40E3585u, 0x106AA070u,
            0x19A4C116u, 0x1E376C08u, 0x2748774Cu, 0x34B0BCB5u,
            0x391C0CB3u, 0x4ED8AA4Au, 0x5B9CCA4Fu, 0x682E6FF3u,
            0x748F82EEu, 0x78A5636Fu, 0x84C87814u, 0x8CC70208u,
            0x90BEFFFAu, 0xA4506CEBu, 0xBEF9A3F7u, 0xC67178F2u,
        ];

        InitializeState();
    }

    public override String Name => "SHA-256";

    public override nuint HashSizeInBytes => 32u;

    /// The digest of `data`, with no object to keep.
    public static byte[] HashData(byte[:] data) => new Sha256().ComputeHash(data);

    protected override void InitializeState()
    {
        _state[0u] = 0x6A09E667u;
        _state[1u] = 0xBB67AE85u;
        _state[2u] = 0x3C6EF372u;
        _state[3u] = 0xA54FF53Au;
        _state[4u] = 0x510E527Fu;
        _state[5u] = 0x9B05688Cu;
        _state[6u] = 0x1F83D9ABu;
        _state[7u] = 0x5BE0CD19u;
    }

    protected override void CompressBlock(byte[] block)
    {
        uint[] schedule = new uint[64u];
        for (nuint i = 0u; i < 16u; i++)
            schedule[i] = ReadBigWord(block, i * 4u);

        for (nuint i = 16u; i < 64u; i++)
        {
            uint previous = schedule[i - 15u];
            uint recent = schedule[i - 2u];
            uint small = RotateLeft(previous, 25) ^ RotateLeft(previous, 14) ^ (previous >> 3);
            uint large = RotateLeft(recent, 15) ^ RotateLeft(recent, 13) ^ (recent >> 10);
            schedule[i] = schedule[i - 16u] + small + schedule[i - 7u] + large;
        }

        uint a = _state[0u];
        uint b = _state[1u];
        uint c = _state[2u];
        uint d = _state[3u];
        uint e = _state[4u];
        uint f = _state[5u];
        uint g = _state[6u];
        uint h = _state[7u];

        for (nuint i = 0u; i < 64u; i++)
        {
            uint sum1 = RotateLeft(e, 26) ^ RotateLeft(e, 21) ^ RotateLeft(e, 7);
            uint choose = (e & f) ^ (~e & g);
            uint first = h + sum1 + choose + _constants[i] + schedule[i];
            uint sum0 = RotateLeft(a, 30) ^ RotateLeft(a, 19) ^ RotateLeft(a, 10);
            uint majority = (a & b) ^ (a & c) ^ (b & c);
            uint second = sum0 + majority;

            h = g;
            g = f;
            f = e;
            e = d + first;
            d = c;
            c = b;
            b = a;
            a = first + second;
        }

        _state[0u] += a;
        _state[1u] += b;
        _state[2u] += c;
        _state[3u] += d;
        _state[4u] += e;
        _state[5u] += f;
        _state[6u] += g;
        _state[7u] += h;
    }

    protected override byte[] ComputeDigest()
    {
        byte[] digest = new byte[32u];
        for (nuint i = 0u; i < 8u; i++)
            WriteBigWord(digest, i * 4u, _state[i]);
        return digest;
    }
}
