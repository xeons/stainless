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

// ============================================================ natural numbers

/// Arithmetic on natural numbers held as little-endian runs of 64-bit limbs.
///
/// **Everything here is constant time unless its name says `VariableTime`.**
/// A selection is a mask of all ones or all zeros, made by arithmetic and
/// passed through `OpaqueCopy`; no branch and no memory address depends on a
/// limb's value, and every loop runs a count fixed by the lengths alone.
///
/// The kernels take pointers so that a hot loop costs no reference count. A
/// pointer MUST address at least `count` limbs of an array the caller keeps
/// alive for the call.
static class Limbs
{
    // ------------------------------------------------------------ masks

    /// All ones when `bit` is 1, and zero when it is 0.
    static ulong MaskFromBit(ulong bit) => OpaqueCopy(0ul - bit);

    /// All ones when `value` is zero.
    static ulong MaskIfZero(ulong value) => MaskFromBit(~(value | (0ul - value)) >> 63);

    /// All ones when `left` equals `right`.
    static ulong MaskIfEqual(ulong left, ulong right) => MaskIfZero(left ^ right);

    /// All ones when every limb of `value` is zero.
    static ulong MaskIfAllZero(ulong* value, nuint count)
    {
        ulong any = 0ul;
        for (nuint i = 0u; i < count; i++)
            any |= value[i];
        return MaskIfZero(any);
    }

    /// All ones when `left` is below `right`.
    static ulong MaskIfLess(ulong* left, ulong* right, nuint count)
    {
        ulong borrow = 0ul;
        for (nuint i = 0u; i < count; i++)
        {
            ulong x = left[i];
            ulong y = right[i];
            ulong difference = x - y - borrow;
            borrow = ((~x & y) | ((~x | y) & difference)) >> 63;
        }
        return MaskFromBit(borrow);
    }

    /// All ones when `value` is exactly one.
    static ulong MaskIfOne(ulong* value, nuint count)
    {
        ulong any = value[0u] ^ 1ul;
        for (nuint i = 1u; i < count; i++)
            any |= value[i];
        return MaskIfZero(any);
    }

    // ------------------------------------------------------------ moving

    static void Copy(ulong* to, ulong* from, nuint count) =>
        memmove((byte*)to, (byte*)from, count * sizeof(ulong));

    static void Clear(ulong* to, nuint count)
    {
        for (nuint i = 0u; i < count; i++)
            to[i] = 0ul;
    }

    /// `whenSet` where `mask` is all ones and `whenClear` where it is zero.
    /// `result` MAY be either input.
    static void Select(ulong* result, ulong mask, ulong* whenSet, ulong* whenClear, nuint count)
    {
        for (nuint i = 0u; i < count; i++)
            result[i] = (whenSet[i] & mask) | (whenClear[i] & ~mask);
    }

    // ------------------------------------------------------------ adding

    /// `left + right` into `result`, answering the carry out. `result` MAY
    /// be either input.
    static ulong Add(ulong* result, ulong* left, ulong* right, nuint count)
    {
        ulong carry = 0ul;
        for (nuint i = 0u; i < count; i++)
        {
            ulong x = left[i];
            ulong y = right[i];
            ulong sum = x + y + carry;
            carry = ((x & y) | ((x | y) & ~sum)) >> 63;
            result[i] = sum;
        }
        return carry;
    }

    /// `left - right` into `result`, answering the borrow out. `result` MAY
    /// be either input.
    static ulong Subtract(ulong* result, ulong* left, ulong* right, nuint count)
    {
        ulong borrow = 0ul;
        for (nuint i = 0u; i < count; i++)
        {
            ulong x = left[i];
            ulong y = right[i];
            ulong difference = x - y - borrow;
            borrow = ((~x & y) | ((~x | y) & difference)) >> 63;
            result[i] = difference;
        }
        return borrow;
    }

    /// Adds a one-limb `value` into `result`, answering the carry out.
    static ulong AddLimb(ulong* result, ulong value, nuint count)
    {
        ulong carry = value;
        for (nuint i = 0u; i < count; i++)
        {
            ulong x = result[i];
            ulong sum = x + carry;
            carry = ((x & carry) | ((x | carry) & ~sum)) >> 63;
            result[i] = sum;
        }
        return carry;
    }

    /// Subtracts a one-limb `value` from `result`, answering the borrow out.
    static ulong SubtractLimb(ulong* result, ulong value, nuint count)
    {
        ulong borrow = value;
        for (nuint i = 0u; i < count; i++)
        {
            ulong x = result[i];
            ulong difference = x - borrow;
            borrow = ((~x & borrow) | ((~x | borrow) & difference)) >> 63;
            result[i] = difference;
        }
        return borrow;
    }

    /// `left + right` modulo `modulus`, for inputs already below it.
    /// `scratch` holds `count` limbs.
    static void AddModular(ulong* result, ulong* left, ulong* right, ulong* modulus, nuint count,
                           ulong* scratch)
    {
        ulong carry = Add(result, left, right, count);
        ulong borrow = Subtract(scratch, result, modulus, count);
        Select(result, MaskFromBit(carry | (borrow ^ 1ul)), scratch, result, count);
    }

    /// `left - right` modulo `modulus`, for inputs already below it.
    static void SubtractModular(ulong* result, ulong* left, ulong* right, ulong* modulus,
                                nuint count, ulong* scratch)
    {
        ulong borrow = Subtract(result, left, right, count);
        Add(scratch, result, modulus, count);
        Select(result, MaskFromBit(borrow), scratch, result, count);
    }

    // ------------------------------------------------------------ shifting

    /// Halves `value` where `mask` is all ones, bringing `carry` in at the top.
    static void ShiftRightOneMasked(ulong* value, ulong mask, ulong carry, nuint count)
    {
        for (nuint i = 0u; i < count; i++)
        {
            ulong above = i + 1u < count ? value[i + 1u] : carry;
            ulong shifted = (value[i] >> 1) | (above << 63);
            value[i] = (shifted & mask) | (value[i] & ~mask);
        }
    }

    /// Shifts `value` right by a secret `shift`, below `64 * count`, one
    /// stage per bit of the shift.
    static void ShiftRightSecret(ulong* value, ulong shift, nuint count, ulong* scratch)
    {
        nuint bits = count * 64u;
        int power = 0;
        for (nuint stage = 1u; stage < bits; stage *= 2u)
        {
            ulong mask = MaskFromBit((shift >> power) & 1ul);
            power++;
            nuint limbShift = stage / 64u;
            int bitShift = (int)(stage % 64u);
            for (nuint i = 0u; i < count; i++)
            {
                nuint from = i + limbShift;
                ulong low = from < count ? value[from] : 0ul;
                ulong high = from + 1u < count ? value[from + 1u] : 0ul;
                ulong shifted = low;
                if (bitShift != 0)
                    shifted = (low >> bitShift) | (high << (64 - bitShift));
                scratch[i] = shifted;
            }
            Select(value, mask, scratch, value, count);
        }
    }

    // ------------------------------------------------------------ multiplying

    /// The whole product of `left` and `right`, into `leftCount + rightCount`
    /// limbs of `result`, which MUST NOT overlap either input.
    static void Multiply(ulong* result, ulong* left, nuint leftCount, ulong* right,
                         nuint rightCount)
    {
        Clear(result, leftCount + rightCount);
        for (nuint i = 0u; i < rightCount; i++)
        {
            ulong factor = right[i];
            ulong carry = 0ul;
            for (nuint j = 0u; j < leftCount; j++)
            {
                ulong x = left[j];
                ulong low = x * factor;
                ulong high = MultiplyHigh(x, factor);
                ulong before = result[i + j];
                ulong sum = low + before;
                high += ((low & before) | ((low | before) & ~sum)) >> 63;
                ulong total = sum + carry;
                high += ((sum & carry) | ((sum | carry) & ~total)) >> 63;
                result[i + j] = total;
                carry = high;
            }
            result[i + leftCount] = carry;
        }
    }

    /// `left * right / R mod modulus`, where `R` is `2^(64 * count)`: the
    /// Montgomery product, by coarsely integrated operand scanning.
    ///
    /// `left` MUST be below `R` and `right` below `modulus`, which MUST be
    /// odd. `inverse` is `-modulus^-1 mod 2^64`. `scratch` holds `count + 2`
    /// limbs. `result` MAY be either input.
    static void MultiplyMontgomery(ulong* result, ulong* left, ulong* right, ulong* modulus,
                                   ulong inverse, nuint count, ulong* scratch)
    {
        ulong* t = scratch;
        Clear(t, count + 2u);

        for (nuint i = 0u; i < count; i++)
        {
            ulong factor = right[i];
            ulong carry = 0ul;
            for (nuint j = 0u; j < count; j++)
            {
                ulong x = left[j];
                ulong low = x * factor;
                ulong high = MultiplyHigh(x, factor);
                ulong before = t[j];
                ulong sum = low + before;
                high += ((low & before) | ((low | before) & ~sum)) >> 63;
                ulong total = sum + carry;
                high += ((sum & carry) | ((sum | carry) & ~total)) >> 63;
                t[j] = total;
                carry = high;
            }
            ulong above = t[count];
            ulong top = above + carry;
            t[count + 1u] = ((above & carry) | ((above | carry) & ~top)) >> 63;
            t[count] = top;

            ulong reducer = t[0u] * inverse;
            ulong lowFirst = reducer * modulus[0u];
            ulong highFirst = MultiplyHigh(reducer, modulus[0u]);
            ulong first = lowFirst + t[0u];
            carry = highFirst + (((lowFirst & t[0u]) | ((lowFirst | t[0u]) & ~first)) >> 63);
            for (nuint j = 1u; j < count; j++)
            {
                ulong y = modulus[j];
                ulong low = reducer * y;
                ulong high = MultiplyHigh(reducer, y);
                ulong before = t[j];
                ulong sum = low + before;
                high += ((low & before) | ((low | before) & ~sum)) >> 63;
                ulong total = sum + carry;
                high += ((sum & carry) | ((sum | carry) & ~total)) >> 63;
                t[j - 1u] = total;
                carry = high;
            }
            ulong highest = t[count];
            ulong last = highest + carry;
            t[count - 1u] = last;
            t[count] = t[count + 1u] + (((highest & carry) | ((highest | carry) & ~last)) >> 63);
        }

        // Below twice the modulus; one subtraction settles it.
        ulong borrow = Subtract(result, t, modulus, count);
        Select(result, MaskFromBit(t[count] | (borrow ^ 1ul)), result, t, count);
    }

    // ------------------------------------------------------------ dividing

    /// `numerator` divided by `divisor`, one bit at a time: the remainder into
    /// `remainder` and, when `quotient` is not null, the quotient into it.
    ///
    /// Takes `64 * numeratorCount` steps of `divisorCount` limbs whatever the
    /// values. `divisor` MUST NOT be zero. `quotient` holds `numeratorCount`
    /// limbs, `remainder` and `scratch` hold `divisorCount`.
    static void DivideConstantTime(ulong* quotient, ulong* remainder, ulong* numerator,
                                   nuint numeratorCount, ulong* divisor, nuint divisorCount,
                                   ulong* scratch)
    {
        Clear(remainder, divisorCount);
        if (quotient != null)
            Clear(quotient, numeratorCount);

        nuint bit = numeratorCount * 64u;
        while (bit > 0u)
        {
            bit--;
            nuint limb = bit / 64u;
            int within = (int)(bit % 64u);
            ulong incoming = (numerator[limb] >> within) & 1ul;

            ulong overflow = remainder[divisorCount - 1u] >> 63;
            for (nuint i = divisorCount - 1u; i > 0u; i--)
                remainder[i] = (remainder[i] << 1) | (remainder[i - 1u] >> 63);
            remainder[0u] = (remainder[0u] << 1) | incoming;

            ulong borrow = Subtract(scratch, remainder, divisor, divisorCount);
            ulong take = overflow | (borrow ^ 1ul);
            Select(remainder, MaskFromBit(take), scratch, remainder, divisorCount);
            if (quotient != null)
                quotient[limb] |= take << within;
        }
    }

    // ------------------------------------------------------------ inverting

    /// The greatest common divisor of `left` and `right`, both `count` limbs,
    /// as an odd part into `left` and a power of two, answered.
    ///
    /// Stein's algorithm run for a fixed `128 * count` steps. `right` is
    /// destroyed; `scratch` holds `count` limbs.
    static ulong FindGreatestCommonDivisor(ulong* left, ulong* right, nuint count, ulong* scratch)
    {
        ulong shift = 0ul;
        nuint steps = count * 128u;
        for (nuint i = 0u; i < steps; i++)
        {
            ulong bothOdd = MaskFromBit(left[0u] & right[0u] & 1ul);

            // Both odd: the smaller comes off the larger.
            ulong leftLess = MaskFromBit(Subtract(scratch, left, right, count));
            Select(left, bothOdd & ~leftLess, scratch, left, count);
            Subtract(scratch, right, left, count);
            Select(right, bothOdd & leftLess, scratch, right, count);

            // Now at least one is even; both even is a common factor of two.
            ulong leftEven = (left[0u] & 1ul) ^ 1ul;
            ulong rightEven = (right[0u] & 1ul) ^ 1ul;
            shift += leftEven & rightEven;
            ShiftRightOneMasked(left, MaskFromBit(leftEven), 0ul, count);
            ShiftRightOneMasked(right, MaskFromBit(rightEven), 0ul, count);
        }

        // One of them is zero, and which is not settled.
        for (nuint i = 0u; i < count; i++)
            left[i] |= right[i];
        return shift;
    }

    /// `value^-1 mod modulus`, into `result`, and whether there is one.
    ///
    /// Stein's algorithm with its Bezout coefficients kept, run for a fixed
    /// `128 * count` steps. `value` MUST be below `modulus`, and one of the
    /// two MUST be odd. All are `count` limbs; `scratch` holds `8 * count`.
    static bool InvertConstantTime(ulong* result, ulong* value, ulong* modulus, nuint count,
                                   ulong* scratch)
    {
        // u = A*value - B*modulus and v = D*modulus - C*value throughout.
        ulong* u = scratch;
        ulong* v = scratch + count;
        ulong* a = scratch + 2u * count;
        ulong* b = scratch + 3u * count;
        ulong* c = scratch + 4u * count;
        ulong* d = scratch + 5u * count;
        ulong* temporary = scratch + 6u * count;
        ulong* other = scratch + 7u * count;

        Copy(u, value, count);
        Copy(v, modulus, count);
        Clear(a, count);
        a[0u] = 1ul;
        Clear(b, count);
        Clear(c, count);
        Clear(d, count);
        d[0u] = 1ul;

        nuint steps = count * 128u;
        for (nuint i = 0u; i < steps; i++)
        {
            ulong bothOdd = MaskFromBit(u[0u] & v[0u] & 1ul);

            ulong vLess = MaskFromBit(Subtract(temporary, v, u, count));
            Select(v, bothOdd & ~vLess, temporary, v, count);
            Subtract(temporary, u, v, count);
            Select(u, bothOdd & vLess, temporary, u, count);

            // Whichever of u and v moved, its coefficients take the other's.
            ulong carry = Add(temporary, a, c, count);
            carry -= Subtract(other, temporary, modulus, count);
            Select(temporary, carry, temporary, other, count);
            Select(a, bothOdd & vLess, temporary, a, count);
            Select(c, bothOdd & ~vLess, temporary, c, count);

            Add(temporary, b, d, count);
            Subtract(other, temporary, value, count);
            Select(temporary, carry, temporary, other, count);
            Select(b, bothOdd & vLess, temporary, b, count);
            Select(d, bothOdd & ~vLess, temporary, d, count);

            // Exactly one of u and v is even now; halve it, and its
            // coefficients with it, adding the moduli first to keep them whole.
            ulong uEven = MaskFromBit((u[0u] & 1ul) ^ 1ul);
            ulong vEven = MaskFromBit((v[0u] & 1ul) ^ 1ul);

            ShiftRightOneMasked(u, uEven, 0ul, count);
            ulong abOdd = MaskFromBit((a[0u] | b[0u]) & 1ul) & uEven;
            ulong aCarry = AddMasked(a, abOdd, modulus, temporary, count);
            ulong bCarry = AddMasked(b, abOdd, value, temporary, count);
            ShiftRightOneMasked(a, uEven, aCarry, count);
            ShiftRightOneMasked(b, uEven, bCarry, count);

            ShiftRightOneMasked(v, vEven, 0ul, count);
            ulong cdOdd = MaskFromBit((c[0u] | d[0u]) & 1ul) & vEven;
            ulong cCarry = AddMasked(c, cdOdd, modulus, temporary, count);
            ulong dCarry = AddMasked(d, cdOdd, value, temporary, count);
            ShiftRightOneMasked(c, vEven, cCarry, count);
            ShiftRightOneMasked(d, vEven, dCarry, count);
        }

        Copy(result, a, count);
        return MaskIfOne(u, count) != 0ul;
    }

    /// Adds `addend` into `value` where `mask` is all ones, answering the
    /// carry out, which is zero where it is not.
    static ulong AddMasked(ulong* value, ulong mask, ulong* addend, ulong* scratch, nuint count)
    {
        ulong carry = Add(scratch, value, addend, count);
        Select(value, mask, scratch, value, count);
        return carry & mask & 1ul;
    }

    // ------------------------------------------------------------ public values

    /// -1, 0 or 1 as `left` is below, equal to or above `right`. Its time
    /// depends on where they first differ.
    static int CompareVariableTime(ulong* left, ulong* right, nuint count)
    {
        nuint i = count;
        while (i > 0u)
        {
            i--;
            if (left[i] != right[i])
                return left[i] < right[i] ? -1 : 1;
        }
        return 0;
    }

    /// How many bits `value` needs. Its time depends on the value.
    static nuint CountBitsVariableTime(ulong* value, nuint count)
    {
        nuint i = count;
        while (i > 0u)
        {
            i--;
            if (value[i] != 0ul)
                return i * 64u + (nuint)(64 - LeadingZeroCount(value[i]));
        }
        return 0u;
    }

    // ------------------------------------------------------------ bytes

    /// `bytes`, big-endian, as `count` limbs. Whatever does not fit is
    /// dropped; a caller MUST check first that nothing does.
    static ulong[] FromBigEndian(ReadOnlySpan<byte> bytes, nuint count)
    {
        ulong[] limbs = new ulong[count];
        nuint length = bytes.Length;
        for (nuint i = 0u; i < length; i++)
        {
            nuint position = length - 1u - i;
            nuint limb = i / 8u;
            if (limb < count)
                limbs[limb] |= (ulong)bytes[position] << (int)(8u * (i % 8u));
        }
        return limbs;
    }

    /// The low `length` bytes of `limbs`, big-endian.
    static byte[] ToBigEndian(ulong[] limbs, nuint length)
    {
        byte[] bytes = new byte[length];
        for (nuint i = 0u; i < length; i++)
        {
            nuint limb = i / 8u;
            if (limb < limbs.Length)
                bytes[length - 1u - i] = (byte)((limbs[limb] >> (int)(8u * (i % 8u))) & 0xFFul);
        }
        return bytes;
    }

    /// How many limbs `bits` bits take.
    static nuint CountLimbsForBits(nuint bits) => (bits + 63u) / 64u;

    /// How many significant bits a big-endian `bytes` holds, leading zeros
    /// not counted. Every byte is read, whatever the value.
    static nuint CountBits(ReadOnlySpan<byte> bytes)
    {
        ulong bits = 0ul;
        ulong found = 0ul;
        for (nuint i = 0u; i < bytes.Length; i++)
        {
            ulong value = (ulong)bytes[i];
            ulong first = ~MaskIfZero(value) & ~found;
            ulong here = (ulong)(bytes.Length - 1u - i) * 8ul +
                         (ulong)(64 - LeadingZeroCount(value | 1ul));
            bits = (here & first) | (bits & ~first);
            found |= first;
        }
        return (nuint)bits;
    }

    /// Overwrites `limbs` with zeros.
    static void ZeroMemory(ulong[] limbs)
    {
        for (nuint i = 0u; i < limbs.Length; i++)
            limbs[i] = 0ul;
    }
}
