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

// ------------------------------------------------------------------ SHA-1

/// SHA-1, which is **broken for collisions** and still required by some
/// protocols.
///
/// SHAttered produced two PDFs with the same digest in 2017 and the cost has
/// only fallen since. It is not safe for a signature or a certificate. It is
/// still what Git names an object with, what HMAC-SHA-1 inside TOTP and
/// PBKDF2 uses -- where the collision resistance is not what is relied on --
/// and what a dozen older protocols specify.
public sealed class Sha1 : HashAlgorithm
{
    uint[] _state;

    public Sha1()
    {
        base(64u, 8u, true);
        _state = new uint[5u];
        InitializeState();
    }

    public override String Name => "SHA-1";

    public override nuint HashSizeInBytes => 20u;

    /// The digest of `data`, with no object to keep.
    public static byte[] HashData(byte[:] data) => new Sha1().ComputeHash(data);

    protected override void InitializeState()
    {
        _state[0u] = 0x67452301u;
        _state[1u] = 0xEFCDAB89u;
        _state[2u] = 0x98BADCFEu;
        _state[3u] = 0x10325476u;
        _state[4u] = 0xC3D2E1F0u;
    }

    protected override void CompressBlock(byte[] block)
    {
        uint[] schedule = new uint[80u];
        for (nuint i = 0u; i < 16u; i++)
            schedule[i] = ReadBigWord(block, i * 4u);

        for (nuint i = 16u; i < 80u; i++)
        {
            uint mixed = schedule[i - 3u] ^ schedule[i - 8u] ^
                         schedule[i - 14u] ^ schedule[i - 16u];
            schedule[i] = RotateLeft(mixed, 1);
        }

        uint a = _state[0u];
        uint b = _state[1u];
        uint c = _state[2u];
        uint d = _state[3u];
        uint e = _state[4u];

        for (nuint i = 0u; i < 80u; i++)
        {
            uint mixed = 0u;
            uint constant = 0u;

            if (i < 20u)
            {
                mixed = (b & c) | (~b & d);
                constant = 0x5A827999u;
            }
            else if (i < 40u)
            {
                mixed = b ^ c ^ d;
                constant = 0x6ED9EBA1u;
            }
            else if (i < 60u)
            {
                mixed = (b & c) | (b & d) | (c & d);
                constant = 0x8F1BBCDCu;
            }
            else
            {
                mixed = b ^ c ^ d;
                constant = 0xCA62C1D6u;
            }

            uint next = RotateLeft(a, 5) + mixed + e + constant + schedule[i];
            e = d;
            d = c;
            c = RotateLeft(b, 30);
            b = a;
            a = next;
        }

        _state[0u] += a;
        _state[1u] += b;
        _state[2u] += c;
        _state[3u] += d;
        _state[4u] += e;
    }

    protected override byte[] ComputeDigest()
    {
        byte[] digest = new byte[20u];
        for (nuint i = 0u; i < 5u; i++)
            WriteBigWord(digest, i * 4u, _state[i]);
        return digest;
    }
}
