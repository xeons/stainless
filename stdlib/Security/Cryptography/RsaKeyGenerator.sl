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
    /// `ceil(sqrt(2) * 2^63)`: a prime's top 64 bits are at least this, so
    /// the product of two has exactly twice their bits.
    private const ulong SquareRootTwoBound = 0xB504F333F9DE6485ul;

    /// The public exponent every generated key uses, F4.
    const ulong PublicExponent = 65537ul;

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

    /// The parts of a new key of `keySizeInBits` bits with `e` = 65537:
    /// `n`, `d`, `p`, `q`, `d mod (p - 1)`, `d mod (q - 1)` and `q^-1 mod p`.
    ///
    /// `d` is `e^-1 mod lcm(p - 1, q - 1)`, found by a constant-time binary
    /// GCD and inverse; `q^-1 mod p` is `q^(p - 2) mod p`.
    static Result<ulong[][], CryptoError> GenerateKeyParts(nuint keySizeInBits)
    {
        nuint half = keySizeInBits / 2u;
        nuint primeCount = Limbs.CountLimbsForBits(half);
        nuint count = Limbs.CountLimbsForBits(keySizeInBits);
        ushort[] smallPrimes = CreateSmallPrimes();

        while (true)
        {
            ulong[] p = try GenerateProbablePrime(half, smallPrimes);
            ulong[] q = try GenerateProbablePrime(half, smallPrimes);

            // FIPS 186-5 A.1.3 step 5.5: |p - q| > 2^(half - 100).
            if (!IsDistanceEnough(p, q, half - 100u))
                continue;

            ulong[] n = new ulong[count];
            ulong[] product = new ulong[2u * primeCount];
            Limbs.Multiply(&product[0u], &p[0u], primeCount, &q[0u], primeCount);
            Limbs.Copy(&n[0u], &product[0u], count);

            ulong[] pMinusOne = CopyLimbs(p, primeCount);
            ulong[] qMinusOne = CopyLimbs(q, primeCount);
            Limbs.SubtractLimb(&pMinusOne[0u], 1ul, primeCount);
            Limbs.SubtractLimb(&qMinusOne[0u], 1ul, primeCount);

            ulong[] lambda = ComputeLeastCommonMultiple(pMinusOne, qMinusOne, count);
            ulong[] exponent = new ulong[count];
            exponent[0u] = PublicExponent;
            ulong[] d = new ulong[count];
            ulong[] scratch = new ulong[8u * count];
            if (!Limbs.InvertConstantTime(&d[0u], &exponent[0u], &lambda[0u], count, &scratch[0u]))
                continue;

            // FIPS 186-5 A.1.1 step 4: d > 2^half, else start again.
            if (!IsDistanceEnough(d, new ulong[count], half))
                continue;

            ulong[] dP = ReduceModuloEven(d, pMinusOne);
            ulong[] dQ = ReduceModuloEven(d, qMinusOne);

            var primeP = new MontgomeryModulus(CopyLimbs(p, primeCount));
            ulong[] exponentP = CopyLimbs(p, primeCount);
            Limbs.SubtractLimb(&exponentP[0u], 2ul, primeCount);
            ulong[] coefficient = primeP.Power(primeP.Reduce(q), exponentP);

            Limbs.ZeroMemory(lambda);
            Limbs.ZeroMemory(product);
            Limbs.ZeroMemory(pMinusOne);
            Limbs.ZeroMemory(qMinusOne);
            Limbs.ZeroMemory(scratch);
            return Ok([n, d, p, q, dP, dQ, coefficient]);
        }
    }

    /// Whether `left` and `right` differ by more than `2^bits`, in time
    /// that does not depend on either.
    static bool IsDistanceEnough(ulong[] left, ulong[] right, nuint bits)
    {
        nuint count = left.Length;
        ulong[] forward = new ulong[count];
        ulong[] backward = new ulong[count];
        ulong borrow = Limbs.Subtract(&forward[0u], &left[0u], &right[0u], count);
        Limbs.Subtract(&backward[0u], &right[0u], &left[0u], count);
        Limbs.Select(&forward[0u], Limbs.MaskFromBit(borrow), &backward[0u], &forward[0u], count);

        // |left - right| - 1 has a bit at `bits` or above exactly when the
        // distance is more than 2^bits; a distance of zero wraps.
        ulong wrapped = Limbs.SubtractLimb(&forward[0u], 1ul, count);
        ulong high = 0ul;
        for (nuint i = 0u; i < count; i++)
        {
            nuint start = i * 64u;
            if (start >= bits)
                high |= forward[i];
            else if (bits - start < 64u)
                high |= forward[i] >> (int)(bits - start);
        }

        Limbs.ZeroMemory(forward);
        Limbs.ZeroMemory(backward);
        return (Limbs.MaskIfZero(high) | Limbs.MaskFromBit(wrapped)) == 0ul;
    }

    /// `lcm(left, right)`, into `count` limbs: `left * right`, shifted right
    /// by the gcd's power of two and divided by its odd part, all in time
    /// that depends on the lengths alone.
    static ulong[] ComputeLeastCommonMultiple(ulong[] left, ulong[] right, nuint count)
    {
        nuint width = left.Length;
        ulong[] product = new ulong[2u * width];
        Limbs.Multiply(&product[0u], &left[0u], width, &right[0u], width);

        ulong[] odd = CopyLimbs(left, width);
        ulong[] other = CopyLimbs(right, width);
        ulong[] scratch = new ulong[2u * width];
        ulong shift = Limbs.FindGreatestCommonDivisor(&odd[0u], &other[0u], width, &scratch[0u]);
        Limbs.ShiftRightSecret(&product[0u], shift, 2u * width, &scratch[0u]);

        ulong[] quotient = new ulong[2u * width];
        ulong[] remainder = new ulong[width];
        Limbs.DivideConstantTime(&quotient[0u], &remainder[0u], &product[0u], 2u * width,
                                 &odd[0u], width, &scratch[0u]);

        ulong[] result = new ulong[count];
        Limbs.Copy(&result[0u], &quotient[0u], count < 2u * width ? count : 2u * width);
        Limbs.ZeroMemory(product);
        Limbs.ZeroMemory(odd);
        Limbs.ZeroMemory(other);
        Limbs.ZeroMemory(quotient);
        return result;
    }

    /// `value mod modulus` for a modulus that may be even, into the
    /// modulus's limbs, by constant-time long division.
    static ulong[] ReduceModuloEven(ulong[] value, ulong[] modulus)
    {
        ulong[] remainder = new ulong[modulus.Length];
        ulong[] scratch = new ulong[modulus.Length];
        Limbs.DivideConstantTime(null, &remainder[0u], &value[0u], value.Length, &modulus[0u],
                                 modulus.Length, &scratch[0u]);
        return remainder;
    }

    /// `value`'s first `count` limbs, copied, padded with zeros.
    static ulong[] CopyLimbs(ulong[] value, nuint count)
    {
        ulong[] copy = new ulong[count];
        value[:count < value.Length ? count : value.Length].CopyTo(copy);
        return copy;
    }

    // ------------------------------------------------------------ primes

    /// The odd primes below 2048, for sieving candidates.
    static ushort[] CreateSmallPrimes()
    {
        bool[] composite = new bool[2048u];
        nuint found = 0u;
        for (nuint i = 3u; i < 2048u; i += 2u)
        {
            if (composite[i])
                continue;
            found++;
            for (nuint j = i * i; j < 2048u; j += 2u * i)
                composite[j] = true;
        }

        ushort[] primes = new ushort[found];
        nuint at = 0u;
        for (nuint i = 3u; i < 2048u; i += 2u)
        {
            if (!composite[i])
            {
                primes[at] = (ushort)i;
                at++;
            }
        }
        return primes;
    }

    /// `value mod divisor` for a public `divisor` below 2^16, in time that
    /// does not depend on `value`: Barrett reduction of 32 bits at a time.
    static ulong ComputeSmallRemainder(ulong[] value, ulong divisor)
    {
        ulong reciprocal = 0xFFFFFFFFFFFFFFFFul / divisor;
        ulong remainder = 0ul;
        nuint i = value.Length;
        while (i > 0u)
        {
            i--;
            remainder = ReduceSmall((remainder << 32) | (value[i] >> 32), divisor, reciprocal);
            remainder = ReduceSmall((remainder << 32) | (value[i] & 0xFFFFFFFFul), divisor,
                                    reciprocal);
        }
        return remainder;
    }

    /// `value mod divisor` for `value` below 2^48.
    static ulong ReduceSmall(ulong value, ulong divisor, ulong reciprocal)
    {
        ulong estimate = MultiplyHigh(value, reciprocal);
        ulong remainder = value - estimate * divisor;
        ulong over = remainder - divisor;
        ulong keep = Limbs.MaskFromBit(over >> 63);
        return (remainder & keep) | (over & ~keep);
    }

    /// A probable prime of exactly `bits` bits whose top 64 bits are at
    /// least `sqrt(2) * 2^63`, and for which `p - 1` is prime to 65537.
    static Result<ulong[], CryptoError> GenerateProbablePrime(nuint bits, ushort[] smallPrimes)
    {
        nuint count = Limbs.CountLimbsForBits(bits);
        byte[] bytes = new byte[count * 8u];
        int rounds = CountMillerRabinRounds(bits);

        while (true)
        {
            if (!RandomNumberGenerator.Fill(bytes))
                return Fail(CryptoError.NoEntropy);
            ulong[] candidate = Limbs.FromBigEndian(bytes, count);
            MaskToBits(candidate, bits);
            candidate[0u] |= 1ul;

            // Draws below the bound are thrown away rather than adjusted.
            if (ReadTopBits(candidate, bits) < SquareRootTwoBound)
                continue;

            bool divisible = false;
            for (nuint i = 0u; i < smallPrimes.Length; i++)
            {
                if (ComputeSmallRemainder(candidate, (ulong)smallPrimes[i]) == 0ul)
                {
                    divisible = true;
                    break;
                }
            }
            if (divisible)
                continue;

            if (ComputeSmallRemainder(candidate, PublicExponent) == 1ul)
                continue;

            if (!(try IsProbablePrime(candidate, rounds)))
                continue;

            CryptographicOperations.ZeroMemory(bytes);
            return Ok(candidate);
        }
    }

    /// The 64 bits of `value` below bit `bits`, which is its top when it has
    /// exactly `bits` bits.
    static ulong ReadTopBits(ulong[] value, nuint bits)
    {
        nuint start = bits - 64u;
        nuint limb = start / 64u;
        int within = (int)(start % 64u);
        ulong low = value[limb] >> within;
        if (within == 0)
            return low;
        return low | (value[limb + 1u] << (64 - within));
    }

    /// Miller-Rabin rounds for a candidate of `bits` bits: FIPS 186-5
    /// Table B.1 asks five at 1024 and four at 1536 and 2048; these are
    /// BoringSSL's counts, which meet it and give 2^-128 for a random
    /// candidate at every size.
    static int CountMillerRabinRounds(nuint bits)
    {
        if (bits >= 3747u)
            return 3;
        if (bits >= 1345u)
            return 4;
        if (bits >= 476u)
            return 5;
        if (bits >= 400u)
            return 6;
        if (bits >= 347u)
            return 7;
        if (bits >= 308u)
            return 8;
        return 27;
    }

    /// Whether `candidate`, odd and above three, passes `rounds` rounds of
    /// Miller-Rabin with random bases (FIPS 186-5 B.3.1).
    static Result<bool, CryptoError> IsProbablePrime(ulong[] candidate, int rounds)
    {
        nuint count = candidate.Length;
        var modulus = new MontgomeryModulus(candidate);

        ulong[] minusOne = CopyLimbs(candidate, count);
        Limbs.SubtractLimb(&minusOne[0u], 1ul, count);

        // candidate - 1 = 2^twos * odd.
        nuint twos = 0u;
        while ((minusOne[twos / 64u] >> (int)(twos % 64u) & 1ul) == 0ul)
            twos++;
        ulong[] odd = CopyLimbs(minusOne, count);
        ulong[] scratch = new ulong[count];
        Limbs.ShiftRightSecret(&odd[0u], (ulong)twos, count, &scratch[0u]);

        ulong[] one = new ulong[count];
        one[0u] = 1ul;
        ulong[] upper = CopyLimbs(minusOne, count);
        Limbs.SubtractLimb(&upper[0u], 1ul, count);

        for (int round = 0; round < rounds; round++)
        {
            // A base in [2, candidate - 2].
            ulong[] witness = try DrawRandomBelow(upper);
            Limbs.AddLimb(&witness[0u], 1ul, count);

            ulong[] z = modulus.Power(witness, odd);
            ulong passed = MaskIfEqualLimbs(z, one) | MaskIfEqualLimbs(z, minusOne);
            for (nuint j = 1u; j < twos; j++)
            {
                z = modulus.MultiplyModular(z, z);
                passed |= MaskIfEqualLimbs(z, minusOne);
            }
            if (passed == 0ul)
                return Ok(false);
        }
        return Ok(true);
    }

    static ulong MaskIfEqualLimbs(ulong[] left, ulong[] right)
    {
        ulong difference = 0ul;
        for (nuint i = 0u; i < left.Length; i++)
            difference |= left[i] ^ right[i];
        return Limbs.MaskIfZero(difference);
    }
}
