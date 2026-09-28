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

/// An odd modulus above one, with what Montgomery multiplication modulo it
/// needs worked out once.
///
/// Every number is `LimbCount` limbs, and `R` is `2^(64 * LimbCount)`. What
/// takes and answers a number here takes and answers it below the modulus
/// and in ordinary form unless its name says `Montgomery`.
///
/// **Constant time throughout**, except `PowerVariableTime`, whose time
/// depends on its exponent and on nothing else. The object is not changed
/// after construction, so one MAY be used from several threads at once.
class MontgomeryModulus
{
    private ulong[] _modulus;
    private nuint _count;
    private ulong _inverse;
    private ulong[] _one;
    private ulong[] _rSquared;

    /// `modulus` MUST be odd and above one, and is kept rather than copied.
    MontgomeryModulus(ulong[] modulus)
    {
        _modulus = modulus;
        _count = modulus.Length;

        // Newton's iteration doubles the correct low bits from the three an
        // odd number is its own inverse to.
        ulong low = modulus[0u];
        ulong inverse = low;
        for (int i = 0; i < 5; i++)
            inverse *= 2ul - low * inverse;
        _inverse = 0ul - inverse;

        // R and then R^2, by doubling one.
        nuint count = _count;
        ulong[] value = new ulong[count];
        ulong[] scratch = new ulong[count];
        value[0u] = 1ul;
        ulong* v = &value[0u];
        ulong* s = &scratch[0u];
        ulong* m = &_modulus[0u];
        _one = new ulong[count];
        for (nuint i = 0u; i < 128u * count; i++)
        {
            ulong overflow = v[count - 1u] >> 63;
            for (nuint j = count - 1u; j > 0u; j--)
                v[j] = (v[j] << 1) | (v[j - 1u] >> 63);
            v[0u] = v[0u] << 1;
            ulong borrow = Limbs.Subtract(s, v, m, count);
            Limbs.Select(v, Limbs.MaskFromBit(overflow | (borrow ^ 1ul)), s, v, count);

            if (i + 1u == 64u * count)
                Limbs.Copy(&_one[0u], v, count);
        }
        _rSquared = value;
    }

    /// How many limbs every number modulo this one has.
    nuint LimbCount => _count;

    /// The modulus itself.
    ulong[] Modulus => _modulus;

    /// A number of `LimbCount` limbs, zero.
    ulong[] CreateNumber() => new ulong[_count];

    /// `value * R mod m`, for any `value` below `R`.
    ulong[] ConvertToMontgomery(ulong[] value)
    {
        ulong[] result = new ulong[_count];
        ulong[] scratch = new ulong[_count + 2u];
        Limbs.MultiplyMontgomery(&result[0u], &value[0u], &_rSquared[0u], &_modulus[0u], _inverse,
                                 _count, &scratch[0u]);
        return result;
    }

    /// `value / R mod m`: a Montgomery form back to an ordinary one.
    ulong[] ConvertFromMontgomery(ulong[] value)
    {
        ulong[] result = new ulong[_count];
        ulong[] unit = new ulong[_count];
        ulong[] scratch = new ulong[_count + 2u];
        unit[0u] = 1ul;
        Limbs.MultiplyMontgomery(&result[0u], &value[0u], &unit[0u], &_modulus[0u], _inverse,
                                 _count, &scratch[0u]);
        return result;
    }

    /// `left * right mod m`, for `left` below `R` and `right` below the
    /// modulus.
    ulong[] MultiplyModular(ulong[] left, ulong[] right)
    {
        ulong[] result = new ulong[_count];
        ulong[] scratch = new ulong[_count + 2u];
        ulong* r = &result[0u];
        ulong* m = &_modulus[0u];
        ulong* s = &scratch[0u];
        Limbs.MultiplyMontgomery(r, &left[0u], &_rSquared[0u], m, _inverse, _count, s);
        Limbs.MultiplyMontgomery(r, r, &right[0u], m, _inverse, _count, s);
        return result;
    }

    /// `left - right mod m`.
    ulong[] SubtractModular(ulong[] left, ulong[] right)
    {
        ulong[] result = new ulong[_count];
        ulong[] scratch = new ulong[_count];
        Limbs.SubtractModular(&result[0u], &left[0u], &right[0u], &_modulus[0u], _count,
                              &scratch[0u]);
        return result;
    }

    /// `value mod m`, for a `value` of any number of limbs.
    ///
    /// Horner's rule over chunks of `LimbCount` limbs, from the top, each
    /// step a Montgomery product by `R^2`; its time depends on the lengths.
    ulong[] Reduce(ulong[] value)
    {
        nuint count = _count;
        nuint chunks = (value.Length + count - 1u) / count;
        ulong[] accumulator = new ulong[count];
        ulong[] chunk = new ulong[count];
        ulong[] term = new ulong[count];
        ulong[] scratch = new ulong[count + 2u];
        ulong* a = &accumulator[0u];
        ulong* c = &chunk[0u];
        ulong* t = &term[0u];
        ulong* s = &scratch[0u];
        ulong* m = &_modulus[0u];
        ulong* square = &_rSquared[0u];

        nuint index = chunks;
        while (index > 0u)
        {
            index--;
            Limbs.MultiplyMontgomery(a, a, square, m, _inverse, count, s);
            for (nuint i = 0u; i < count; i++)
            {
                nuint from = index * count + i;
                c[i] = from < value.Length ? value[from] : 0ul;
            }
            Limbs.MultiplyMontgomery(t, c, square, m, _inverse, count, s);
            Limbs.AddModular(a, a, t, m, count, s);
        }

        Limbs.ZeroMemory(chunk);
        Limbs.ZeroMemory(term);
        return ConvertFromMontgomery(accumulator);
    }

    /// `value^exponent mod m`, in time that depends on the lengths alone.
    ///
    /// A fixed window of four bits: every window is four squarings and one
    /// multiplication by an entry of a sixteen-entry table, and the entry is
    /// found by reading all sixteen under a mask. Every bit of `exponent`'s
    /// limbs is a step, leading zeros included.
    ///
    /// @param value     below the modulus
    /// @param exponent  any number of limbs, all of them used
    ulong[] Power(ulong[] value, ulong[] exponent)
    {
        nuint count = _count;
        ulong[] table = new ulong[16u * count];
        ulong[] scratch = new ulong[count + 2u];
        ulong[] accumulator = new ulong[count];
        ulong[] chosen = new ulong[count];
        ulong* t = &table[0u];
        ulong* s = &scratch[0u];
        ulong* a = &accumulator[0u];
        ulong* pick = &chosen[0u];
        ulong* m = &_modulus[0u];
        ulong* e = &exponent[0u];
        ulong inverse = _inverse;

        Limbs.Copy(t, &_one[0u], count);
        Limbs.MultiplyMontgomery(t + count, &value[0u], &_rSquared[0u], m, inverse, count, s);
        for (nuint k = 2u; k < 16u; k++)
            Limbs.MultiplyMontgomery(t + k * count, t + (k - 1u) * count, t + count, m, inverse,
                                     count, s);

        Limbs.Copy(a, &_one[0u], count);
        nuint bit = exponent.Length * 64u;
        while (bit > 0u)
        {
            bit -= 4u;
            for (int k = 0; k < 4; k++)
                Limbs.MultiplyMontgomery(a, a, a, m, inverse, count, s);

            ulong window = (e[bit / 64u] >> (int)(bit % 64u)) & 15ul;
            Limbs.Clear(pick, count);
            for (nuint k = 0u; k < 16u; k++)
            {
                ulong mask = Limbs.MaskIfEqual((ulong)k, window);
                ulong* entry = t + k * count;
                for (nuint j = 0u; j < count; j++)
                    pick[j] |= entry[j] & mask;
            }
            Limbs.MultiplyMontgomery(a, a, pick, m, inverse, count, s);
        }

        Limbs.ZeroMemory(table);
        Limbs.ZeroMemory(chosen);
        return ConvertFromMontgomery(accumulator);
    }

    /// `value^exponent mod m` by square and multiply, for an exponent that
    /// is public. Its time depends on the exponent's bits; `value` may be a
    /// secret.
    ulong[] PowerVariableTime(ulong[] value, ulong[] exponent)
    {
        nuint count = _count;
        ulong[] scratch = new ulong[count + 2u];
        ulong* s = &scratch[0u];
        ulong* m = &_modulus[0u];
        ulong inverse = _inverse;

        ulong[] converted = ConvertToMontgomery(value);
        ulong[] accumulator = new ulong[count];
        ulong* b = &converted[0u];
        ulong* a = &accumulator[0u];
        Limbs.Copy(a, &_one[0u], count);

        nuint bits = Limbs.CountBitsVariableTime(&exponent[0u], exponent.Length);
        nuint bit = bits;
        while (bit > 0u)
        {
            bit--;
            Limbs.MultiplyMontgomery(a, a, a, m, inverse, count, s);
            if (((exponent[bit / 64u] >> (int)(bit % 64u)) & 1ul) != 0ul)
                Limbs.MultiplyMontgomery(a, a, b, m, inverse, count, s);
        }

        Limbs.ZeroMemory(converted);
        return ConvertFromMontgomery(accumulator);
    }
}
