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

// ------------------------------------------------------ SHA-384 and SHA-512

/// The 64-bit half of SHA-2, which SHA-384 and SHA-512 share entirely except
/// for where they start and how much of the answer they keep.
///
/// Public because a public class cannot usefully hide its base, and documented
/// as machinery: there is nothing here to construct. `Sha384` and `Sha512` are
/// the two that exist.
public abstract class Sha2Wide : HashAlgorithm
{
    /// Eight doublewords, which both algorithms carry and only the initial
    /// value of distinguishes.
    protected ulong[] _state;

    ulong[] _constants;

    protected Sha2Wide()
    {
        base(128u, 16u, true);

        _state = new ulong[8u];
        _constants = [
            0x428A2F98D728AE22u, 0x7137449123EF65CDu, 0xB5C0FBCFEC4D3B2Fu, 0xE9B5DBA58189DBBCu,
            0x3956C25BF348B538u, 0x59F111F1B605D019u, 0x923F82A4AF194F9Bu, 0xAB1C5ED5DA6D8118u,
            0xD807AA98A3030242u, 0x12835B0145706FBEu, 0x243185BE4EE4B28Cu, 0x550C7DC3D5FFB4E2u,
            0x72BE5D74F27B896Fu, 0x80DEB1FE3B1696B1u, 0x9BDC06A725C71235u, 0xC19BF174CF692694u,
            0xE49B69C19EF14AD2u, 0xEFBE4786384F25E3u, 0x0FC19DC68B8CD5B5u, 0x240CA1CC77AC9C65u,
            0x2DE92C6F592B0275u, 0x4A7484AA6EA6E483u, 0x5CB0A9DCBD41FBD4u, 0x76F988DA831153B5u,
            0x983E5152EE66DFABu, 0xA831C66D2DB43210u, 0xB00327C898FB213Fu, 0xBF597FC7BEEF0EE4u,
            0xC6E00BF33DA88FC2u, 0xD5A79147930AA725u, 0x06CA6351E003826Fu, 0x142929670A0E6E70u,
            0x27B70A8546D22FFCu, 0x2E1B21385C26C926u, 0x4D2C6DFC5AC42AEDu, 0x53380D139D95B3DFu,
            0x650A73548BAF63DEu, 0x766A0ABB3C77B2A8u, 0x81C2C92E47EDAEE6u, 0x92722C851482353Bu,
            0xA2BFE8A14CF10364u, 0xA81A664BBC423001u, 0xC24B8B70D0F89791u, 0xC76C51A30654BE30u,
            0xD192E819D6EF5218u, 0xD69906245565A910u, 0xF40E35855771202Au, 0x106AA07032BBD1B8u,
            0x19A4C116B8D2D0C8u, 0x1E376C085141AB53u, 0x2748774CDF8EEB99u, 0x34B0BCB5E19B48A8u,
            0x391C0CB3C5C95A63u, 0x4ED8AA4AE3418ACBu, 0x5B9CCA4F7763E373u, 0x682E6FF3D6B2B8A3u,
            0x748F82EE5DEFB2FCu, 0x78A5636F43172F60u, 0x84C87814A1F0AB72u, 0x8CC702081A6439ECu,
            0x90BEFFFA23631E28u, 0xA4506CEBDE82BDE9u, 0xBEF9A3F7B2C67915u, 0xC67178F2E372532Bu,
            0xCA273ECEEA26619Cu, 0xD186B8C721C0C207u, 0xEADA7DD6CDE0EB1Eu, 0xF57D4F7FEE6ED178u,
            0x06F067AA72176FBAu, 0x0A637DC5A2C898A6u, 0x113F9804BEF90DAEu, 0x1B710B35131C471Bu,
            0x28DB77F523047D84u, 0x32CAAB7B40C72493u, 0x3C9EBE0A15C9BEBCu, 0x431D67C49C100D4Cu,
            0x4CC5D4BECB3E42B6u, 0x597F299CFC657E2Au, 0x5FCB6FAB3AD6FAECu, 0x6C44198C4A475817u,
        ];
    }

    protected override void CompressBlock(byte[] block)
    {
        ulong[] schedule = new ulong[80u];
        for (nuint i = 0u; i < 16u; i++)
            schedule[i] = ReadBigDoubleWord(block, i * 8u);

        for (nuint i = 16u; i < 80u; i++)
        {
            ulong previous = schedule[i - 15u];
            ulong recent = schedule[i - 2u];
            ulong small = RotateRight(previous, 1) ^ RotateRight(previous, 8) ^ (previous >> 7);
            ulong large = RotateRight(recent, 19) ^ RotateRight(recent, 61) ^ (recent >> 6);
            schedule[i] = schedule[i - 16u] + small + schedule[i - 7u] + large;
        }

        ulong a = _state[0u];
        ulong b = _state[1u];
        ulong c = _state[2u];
        ulong d = _state[3u];
        ulong e = _state[4u];
        ulong f = _state[5u];
        ulong g = _state[6u];
        ulong h = _state[7u];

        for (nuint i = 0u; i < 80u; i++)
        {
            ulong sum1 = RotateRight(e, 14) ^ RotateRight(e, 18) ^ RotateRight(e, 41);
            ulong choose = (e & f) ^ (~e & g);
            ulong first = h + sum1 + choose + _constants[i] + schedule[i];
            ulong sum0 = RotateRight(a, 28) ^ RotateRight(a, 34) ^ RotateRight(a, 39);
            ulong majority = (a & b) ^ (a & c) ^ (b & c);
            ulong second = sum0 + majority;

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
        byte[] whole = new byte[64u];
        for (nuint i = 0u; i < 8u; i++)
            WriteBigDoubleWord(whole, i * 8u, _state[i]);

        if (HashSizeInBytes == 64u)
            return whole;

        byte[] digest = new byte[HashSizeInBytes];
        for (nuint i = 0u; i < digest.Length; i++)
            digest[i] = whole[i];
        return digest;
    }
}
