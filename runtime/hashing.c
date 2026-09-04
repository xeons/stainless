/*
 * Stainless - an experimental systems language.
 * Copyright (C) 2026 Brandon Scott
 *
 * This file is part of the Stainless runtime library. It is free
 * software: you can redistribute it and/or modify it under the terms of
 * the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any
 * later version.
 *
 * It is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * for more details.
 *
 * As an additional permission under section 7 of that License, compiling
 * a program with Stainless does not by itself place that program under
 * the GNU General Public License. See LICENSE.RUNTIME.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

/*
 * Ordering and hashing for the types that cannot implement an interface.
 *
 * A primitive is not a class, so `int` cannot be declared to implement
 * IComparable<int>. The compiler instead recognises CompareTo, EqualTo and
 * HashCode on a primitive, an enum or a String and lowers each to one of the
 * calls below -- which is why `Sort(numbers)` works on a List<int> without the
 * language growing operator constraints.
 *
 * Equality is not here: the compiler already lowers `a == b` for every one of
 * these types, so EqualTo lowers to that and costs nothing.
 */

#include "stainless.h"

#include <string.h>

/* ------------------------------------------------------------- comparison */

int32_t sl_compare_long(int64_t left, int64_t right)
{
    return left < right ? -1 : left > right ? 1 : 0;
}

int32_t sl_compare_ulong(uint64_t left, uint64_t right)
{
    return left < right ? -1 : left > right ? 1 : 0;
}

/*
 * Ordering doubles has to answer for NaN, which compares false against
 * everything including itself. Sorting needs a total order or it loops, so NaN
 * is placed before every number and equal to itself -- the rule .NET settled on
 * for the same reason.
 */
int32_t sl_compare_double(double left, double right)
{
    if (left < right) return -1;
    if (left > right) return 1;
    if (left == right) return 0;

    /* At least one is NaN. */
    _Bool leftIsNan = left != left;
    _Bool rightIsNan = right != right;
    if (leftIsNan && rightIsNan) return 0;
    return leftIsNan ? -1 : 1;
}

int32_t sl_string_compare(void *left, void *right)
{
    SlString *a = (SlString *)left;
    SlString *b = (SlString *)right;

    if (a == b) return 0;

    /* Ordinal, by byte. UTF-8 sorts its code points in the same order as its
       bytes, so this orders code points too -- but it is not a collation, and
       is not meant to be shown to a person as one. */
    size_t shared = a->byteLength < b->byteLength ? a->byteLength : b->byteLength;
    int    result = memcmp(sl_string_data(a), sl_string_data(b), shared);
    if (result != 0) return result < 0 ? -1 : 1;

    if (a->byteLength == b->byteLength) return 0;
    return a->byteLength < b->byteLength ? -1 : 1;
}

/* ---------------------------------------------------------------- hashing */

/*
 * splitmix64's finalizer. Every input bit affects every output bit, which is
 * what a table indexed by the low bits needs: without it, keys 0, 8, 16 land in
 * the same bucket of an 8-slot table.
 */
size_t sl_hash_integer(uint64_t value)
{
    value += 0x9E3779B97F4A7C15ull;
    value = (value ^ (value >> 30)) * 0xBF58476D1CE4E5B9ull;
    value = (value ^ (value >> 27)) * 0x94D049BB133111EBull;
    return (size_t)(value ^ (value >> 31));
}

/*
 * Doubles that compare equal must hash equal, so the two values that break
 * that are normalised first: -0.0 == 0.0, and every NaN is equal to every
 * other under sl_compare_double above.
 */
size_t sl_hash_double(double value)
{
    uint64_t bits;

    if (value == 0.0) return sl_hash_integer(0);
    if (value != value) return sl_hash_integer(0x7FF8000000000000ull);

    memcpy(&bits, &value, sizeof(bits));
    return sl_hash_integer(bits);
}

/* FNV-1a over the bytes. Short, no table, and good enough for a hash table. */
size_t sl_string_hash(void *pointer)
{
    SlString      *string = (SlString *)pointer;
    const uint8_t *bytes = sl_string_data(string);

    uint64_t hash = 0xCBF29CE484222325ull;
    for (size_t i = 0; i < string->byteLength; i++)
    {
        hash ^= bytes[i];
        hash *= 0x100000001B3ull;
    }

    /* Mixed again, because FNV's low bits are the weakest part of it. */
    return sl_hash_integer(hash);
}
