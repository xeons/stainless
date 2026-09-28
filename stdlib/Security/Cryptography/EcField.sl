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
import Standard.Convert;

// ================================================== arithmetic modulo a prime

/// A number below a modulus of at most 384 bits, in 64-bit limbs, least
/// significant first. Limbs at or past the modulus's `Count` are zero.
///
/// It is held inline rather than on the heap, so passing one costs a copy and
/// no reference count.
struct EcElement
{
    public ulong[6] Limbs;
}

/// An odd modulus, and what Montgomery multiplication by it needs.
///
/// A number `a` is held in Montgomery form as `a * R mod m`, where `R` is
/// `2^(64 * Count)`.
struct EcModulus
{
    public EcElement Value;

    /// `R mod m`, which is one in Montgomery form.
    public EcElement One;

    /// `R^2 mod m`. Multiplying by it takes a number into Montgomery form.
    public EcElement RSquared;

    /// `-m^-1 mod 2^64`.
    public ulong Inverse;

    /// How many limbs a number takes: four or six.
    public nuint Count;
}

/// The modulus written in `hexadecimal`, big-endian, and its constants.
EcModulus CreateEcModulus(String hexadecimal)
{
    EcModulus modulus;
    modulus.Value = ParseEcElementHexadecimal(hexadecimal);
    modulus.Count = hexadecimal.ByteLength() / 16u;

    // Newton's iteration doubles the correct low bits each step, and an odd
    // number is its own inverse modulo 8.
    ulong low = modulus.Value.Limbs[0u];
    ulong inverse = low;
    for (nuint i = 0u; i < 5u; i++)
        inverse *= 2u - low * inverse;
    modulus.Inverse = 0u - inverse;

    EcElement power;
    power.Limbs[0u] = 1u;
    for (nuint i = 0u; i < 64u * modulus.Count; i++)
        power = AddEcElements(power, power, ref modulus);
    modulus.One = power;
    for (nuint i = 0u; i < 64u * modulus.Count; i++)
        power = AddEcElements(power, power, ref modulus);
    modulus.RSquared = power;
    return modulus;
}

/// A constant written big-endian in hexadecimal, sixteen digits to a limb.
EcElement ParseEcElementHexadecimal(String hexadecimal)
{
    byte[] bytes = Convert.FromHexString(hexadecimal).GetValueOrDefault(new byte[0u]);
    return ReadEcElement(bytes);
}

// ------------------------------------------------------------------ carries

/// The carry out of `left + right + c`, where `sum` is that sum modulo 2^64
/// and `c` is zero or one. Arithmetic rather than a comparison, so nothing
/// can become a branch.
ulong ComputeEcCarry(ulong left, ulong right, ulong sum) =>
    ((left & right) | ((left | right) & ~sum)) >> 63;

/// The borrow out of `left - right - b`, where `difference` is that difference
/// modulo 2^64 and `b` is zero or one.
ulong ComputeEcBorrow(ulong left, ulong right, ulong difference) =>
    ((~left & right) | (~(left ^ right) & difference)) >> 63;

/// All ones when `value` is zero, and zero otherwise.
ulong ComputeEcZeroMask(ulong value) => OpaqueCopy(((value | (0u - value)) >> 63) - 1u);

/// `whenSet` where `mask` is all ones and `whenClear` where it is zero.
EcElement SelectEcElement(ulong mask, EcElement whenSet, EcElement whenClear)
{
    EcElement chosen;
    for (nuint i = 0u; i < 6u; i++)
        chosen.Limbs[i] = (whenSet.Limbs[i] & mask) | (whenClear.Limbs[i] & ~mask);
    return chosen;
}

/// All ones when `value` is zero, and zero otherwise, in time that does not
/// depend on `value`.
ulong ComputeEcElementZeroMask(EcElement value)
{
    ulong any = 0u;
    for (nuint i = 0u; i < 6u; i++)
        any |= value.Limbs[i];
    return ComputeEcZeroMask(any);
}

/// All ones when `left` and `right` are equal, in time that does not depend
/// on either.
ulong ComputeEcElementEqualMask(EcElement left, EcElement right)
{
    ulong difference = 0u;
    for (nuint i = 0u; i < 6u; i++)
        difference |= left.Limbs[i] ^ right.Limbs[i];
    return ComputeEcZeroMask(difference);
}

/// One when `value` is below `bound`, and zero otherwise, in time that does
/// not depend on either.
ulong ComputeEcElementBelow(EcElement value, EcElement bound)
{
    ulong borrow = 0u;
    for (nuint i = 0u; i < 6u; i++)
    {
        ulong left = value.Limbs[i];
        ulong right = bound.Limbs[i];
        ulong difference = left - right - borrow;
        borrow = ComputeEcBorrow(left, right, difference);
    }
    return borrow;
}

// ---------------------------------------------------------------- arithmetic

/// `left + right mod m`, for two numbers already below `m`.
EcElement AddEcElements(EcElement left, EcElement right, ref EcModulus modulus)
{
    nuint count = modulus.Count;
    EcElement sum;
    ulong carry = 0u;
    for (nuint i = 0u; i < count; i++)
    {
        ulong a = left.Limbs[i];
        ulong b = right.Limbs[i];
        ulong total = a + b + carry;
        carry = ComputeEcCarry(a, b, total);
        sum.Limbs[i] = total;
    }

    EcElement reduced;
    ulong borrow = 0u;
    for (nuint i = 0u; i < count; i++)
    {
        ulong a = sum.Limbs[i];
        ulong b = modulus.Value.Limbs[i];
        ulong difference = a - b - borrow;
        borrow = ComputeEcBorrow(a, b, difference);
        reduced.Limbs[i] = difference;
    }

    // The sum stands when it neither carried nor reached `m`.
    ulong keepSum = OpaqueCopy(0u - (borrow & (carry ^ 1u)));
    return SelectEcElement(keepSum, sum, reduced);
}

/// `left - right mod m`, for two numbers already below `m`.
EcElement SubtractEcElements(EcElement left, EcElement right, ref EcModulus modulus)
{
    nuint count = modulus.Count;
    EcElement difference;
    ulong borrow = 0u;
    for (nuint i = 0u; i < count; i++)
    {
        ulong a = left.Limbs[i];
        ulong b = right.Limbs[i];
        ulong each = a - b - borrow;
        borrow = ComputeEcBorrow(a, b, each);
        difference.Limbs[i] = each;
    }

    ulong addBack = OpaqueCopy(0u - borrow);
    ulong carry = 0u;
    for (nuint i = 0u; i < count; i++)
    {
        ulong a = difference.Limbs[i];
        ulong b = modulus.Value.Limbs[i] & addBack;
        ulong total = a + b + carry;
        carry = ComputeEcCarry(a, b, total);
        difference.Limbs[i] = total;
    }
    return difference;
}

/// `left * right / R mod m`: the Montgomery product, which is the product of
/// two numbers in Montgomery form kept in Montgomery form.
///
/// Coarsely integrated operand scanning, one limb of `left` at a time. Every
/// step runs whatever the operands are; the last subtraction is a mask.
EcElement MultiplyEcElements(EcElement left, EcElement right, ref EcModulus modulus)
{
    nuint count = modulus.Count;
    ulong[8] t;

    for (nuint i = 0u; i < count; i++)
    {
        ulong multiplier = left.Limbs[i];
        ulong carry = 0u;
        for (nuint j = 0u; j < count; j++)
        {
            ulong factor = right.Limbs[j];
            ulong high = MultiplyHigh(multiplier, factor);
            ulong low = multiplier * factor;
            ulong partial = low + t[j];
            high += ComputeEcCarry(low, t[j], partial);
            ulong sum = partial + carry;
            high += ComputeEcCarry(partial, carry, sum);
            t[j] = sum;
            carry = high;
        }

        ulong top = t[count] + carry;
        t[count + 1u] = ComputeEcCarry(t[count], carry, top);
        t[count] = top;

        // Add the multiple of `m` that clears the low limb, and shift it out.
        ulong reducer = t[0u] * modulus.Inverse;
        ulong first = modulus.Value.Limbs[0u];
        ulong lowest = reducer * first;
        carry = MultiplyHigh(reducer, first) + ComputeEcCarry(lowest, t[0u], lowest + t[0u]);
        for (nuint j = 1u; j < count; j++)
        {
            ulong factor = modulus.Value.Limbs[j];
            ulong high = MultiplyHigh(reducer, factor);
            ulong low = reducer * factor;
            ulong partial = low + t[j];
            high += ComputeEcCarry(low, t[j], partial);
            ulong sum = partial + carry;
            high += ComputeEcCarry(partial, carry, sum);
            t[j - 1u] = sum;
            carry = high;
        }

        top = t[count] + carry;
        ulong overflow = ComputeEcCarry(t[count], carry, top);
        t[count - 1u] = top;
        t[count] = t[count + 1u] + overflow;
    }

    // What is left is below 2m, with its top bit in t[count].
    EcElement product;
    EcElement reduced;
    ulong borrow = 0u;
    for (nuint j = 0u; j < count; j++)
    {
        ulong a = t[j];
        ulong b = modulus.Value.Limbs[j];
        ulong difference = a - b - borrow;
        borrow = ComputeEcBorrow(a, b, difference);
        product.Limbs[j] = a;
        reduced.Limbs[j] = difference;
    }

    ulong keepProduct = OpaqueCopy(0u - (borrow & (t[count] ^ 1u)));
    return SelectEcElement(keepProduct, product, reduced);
}

/// `value` into Montgomery form.
EcElement ConvertEcElementToMontgomery(EcElement value, ref EcModulus modulus) =>
    MultiplyEcElements(value, modulus.RSquared, ref modulus);

/// `value` out of Montgomery form.
EcElement ConvertEcElementFromMontgomery(EcElement value, ref EcModulus modulus)
{
    EcElement one;
    one.Limbs[0u] = 1u;
    return MultiplyEcElements(value, one, ref modulus);
}

/// `value` raised to `exponent`, in Montgomery form in and out.
///
/// **The exponent MUST be public**: which multiplications happen depends on
/// its digits. The base may be secret, since nothing depends on it.
EcElement RaiseEcElementToPublicPower(EcElement value, EcElement exponent, ref EcModulus modulus)
{
    EcElement[16] table;
    table[0u] = modulus.One;
    table[1u] = value;
    for (nuint i = 2u; i < 16u; i++)
        table[i] = MultiplyEcElements(table[i - 1u], value, ref modulus);

    EcElement result = modulus.One;
    bool started = false;
    for (nuint window = modulus.Count * 16u; window > 0u; window--)
    {
        nuint at = window - 1u;
        if (started)
        {
            for (nuint i = 0u; i < 4u; i++)
                result = MultiplyEcElements(result, result, ref modulus);
        }

        nuint digit = (nuint)((exponent.Limbs[at / 16u] >> (uint)(4u * (at % 16u))) & 15u);
        if (digit != 0u)
        {
            result = MultiplyEcElements(result, table[digit], ref modulus);
            started = true;
        }
    }
    return result;
}

/// `value^-1 mod m`, by Fermat's little theorem, in Montgomery form in and
/// out. Zero answers zero. `m` MUST be prime.
EcElement InvertEcElement(EcElement value, ref EcModulus modulus)
{
    EcElement two;
    two.Limbs[0u] = 2u;
    EcElement exponent = SubtractEcElementsUnreduced(modulus.Value, two, modulus.Count);
    return RaiseEcElementToPublicPower(value, exponent, ref modulus);
}

/// `left - right` with no reduction, for `left` at least `right`.
EcElement SubtractEcElementsUnreduced(EcElement left, EcElement right, nuint count)
{
    EcElement difference;
    ulong borrow = 0u;
    for (nuint i = 0u; i < count; i++)
    {
        ulong a = left.Limbs[i];
        ulong b = right.Limbs[i];
        ulong each = a - b - borrow;
        borrow = ComputeEcBorrow(a, b, each);
        difference.Limbs[i] = each;
    }
    return difference;
}

/// `value mod m` for a `value` below `2m`, in time that does not depend on
/// it.
EcElement ReduceEcElementOnce(EcElement value, ref EcModulus modulus)
{
    nuint count = modulus.Count;
    EcElement reduced;
    ulong borrow = 0u;
    for (nuint i = 0u; i < count; i++)
    {
        ulong a = value.Limbs[i];
        ulong b = modulus.Value.Limbs[i];
        ulong difference = a - b - borrow;
        borrow = ComputeEcBorrow(a, b, difference);
        reduced.Limbs[i] = difference;
    }
    return SelectEcElement(OpaqueCopy(0u - borrow), value, reduced);
}

// ------------------------------------------------------------------- bytes

/// A big-endian number of eight bytes to a limb, at most 48 bytes, as limbs.
EcElement ReadEcElement(ReadOnlySpan<byte> bytes)
{
    EcElement value;
    nuint count = bytes.Length / 8u;
    for (nuint limb = 0u; limb < count; limb++)
    {
        nuint at = bytes.Length - 8u * (limb + 1u);
        ulong word = 0u;
        for (nuint i = 0u; i < 8u; i++)
            word = (word << 8) | (ulong)bytes[at + i];
        value.Limbs[limb] = word;
    }
    return value;
}

/// `value` as `size` big-endian bytes, into `into` from `at`.
void WriteEcElement(EcElement value, nuint size, byte[] into, nuint at)
{
    for (nuint limb = 0u; limb < size / 8u; limb++)
    {
        ulong word = value.Limbs[limb];
        nuint end = at + size - 8u * limb;
        for (nuint i = 1u; i <= 8u; i++)
        {
            into[end - i] = (byte)(word & 0xFFu);
            word >>= 8;
        }
    }
}
