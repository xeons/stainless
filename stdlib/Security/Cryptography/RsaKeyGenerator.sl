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

/// Random numbers below a bound, probable primes, and RSA keys made of them,
/// as FIPS 186-5 §A.1.3 describes.
///
/// **What is not constant time.** A candidate is rejected as soon as a small
/// prime divides it or a Miller-Rabin round finds a witness, which reveals
/// something about a number that is then thrown away and nothing about the
/// one kept. The one kept runs every step. The count of twos in `p - 1` sets
/// how many squarings each Miller-Rabin round takes, as in BoringSSL.
static class RsaKeyGenerator
{
    /// A uniform number in `[1, bound)`, of `bound`'s limbs. Rejection
    /// sampling, so the time depends on draws that are thrown away.
    static Result<ulong[], CryptoError> DrawRandomBelow(ulong[] bound)
    {
        nuint count = bound.Length;
        nuint bits = Limbs.CountBitsVariableTime(&bound[0u], count);
        byte[] bytes = new byte[count * 8u];
        while (true)
        {
            if (!RandomNumberGenerator.Fill(bytes))
                return Fail(CryptoError.NoEntropy);
            ulong[] drawn = Limbs.FromBigEndian(bytes, count);
            MaskToBits(drawn, bits);
            bool isZero = Limbs.MaskIfAllZero(&drawn[0u], count) != 0ul;
            bool isBelow = Limbs.MaskIfLess(&drawn[0u], &bound[0u], count) != 0ul;
            if (!isZero && isBelow)
            {
                CryptographicOperations.ZeroMemory(bytes);
                return Ok(drawn);
            }
        }
    }

    /// Clears every bit of `value` at or above `bits`.
    static void MaskToBits(ulong[] value, nuint bits)
    {
        for (nuint i = 0u; i < value.Length; i++)
        {
            nuint low = i * 64u;
            if (low >= bits)
                value[i] = 0ul;
            else if (bits - low < 64u)
                value[i] &= (1ul << (int)(bits - low)) - 1ul;
        }
    }
}
