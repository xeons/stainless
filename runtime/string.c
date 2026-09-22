/*
 * Stainless - an experimental general-purpose language.
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
 * String: immutable, reference counted, UTF-8.
 *
 * The text is stored inline, immediately after the header. One allocation,
 * header and bytes in the same cache line, an O(1) length, and a trailing NUL
 * that makes handing the text to C free rather than a copy.
 *
 * The compiler emits string literals in exactly this shape as static constants
 * with a strong count of SL_IMMORTAL.
 */

#include "stainless.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void sl_string_destroy(void *object) { (void)object; }

const SlTypeInfo sl_string_type_info = {
    sizeof(SlString), sl_string_destroy, "Standard.Text.String", NULL, 0, NULL, 0, NULL
};

uint8_t *sl_string_data(SlString *string)
{
    return (uint8_t *)string + sizeof(SlString);
}

/* Allocates a +1 String with room for byteLength bytes plus the NUL. */
SlString *sl_string_new(size_t byteLength)
{
    /* Guard the addition, as the array allocator guards its multiply: a length
     * near the top of the range would wrap to a small request, and the copy
     * that follows would run off the end of what was actually allocated. It
     * takes an unreachable amount of text to get here, which is exactly why it
     * would never be noticed if it were. */
    if (byteLength > SIZE_MAX - sizeof(SlString) - 1)
        sl_fail("string is too large to allocate");

    SlString *string = (SlString *)calloc(1, sizeof(SlString) + byteLength + 1);
    if (string == NULL) sl_fail("out of memory");

    sl_object_init(string, &sl_string_type_info);
    string->byteLength = byteLength;
    return string;
}

void *sl_string_from_bytes(const uint8_t *data, size_t byteLength)
{
    SlString *string = sl_string_new(byteLength);
    if (byteLength > 0 && data != NULL) memcpy(sl_string_data(string), data, byteLength);
    return string;
}

void *sl_string_from_null_terminated(const char *text)
{
    if (text == NULL) return sl_string_new(0);
    return sl_string_from_bytes((const uint8_t *)text, strlen(text));
}

const uint8_t *sl_string_pointer(void *pointer)
{
    return sl_string_data((SlString *)pointer);
}

size_t sl_string_byte_length(void *pointer)
{
    return ((SlString *)pointer)->byteLength;
}

_Bool sl_string_is_empty(void *pointer)
{
    return ((SlString *)pointer)->byteLength == 0;
}

/*
 * Unicode's Table 3-7. The lead narrows the second byte's range, which is what
 * rules out overlong forms, surrogates and values past U+10FFFF. String's
 * WellFormedWidth in stdlib/Text.sl MUST give the same answers.
 */
size_t sl_utf8_well_formed_width(const uint8_t *bytes, size_t length, size_t index)
{
    uint8_t lead = bytes[index];
    if (lead < 0x80) return 1;
    if (lead < 0xC2 || lead > 0xF4) return 0;

    size_t width = lead < 0xE0 ? 2 : lead < 0xF0 ? 3 : 4;
    if (length - index < width) return 0;

    uint8_t low  = 0x80;
    uint8_t high = 0xBF;
    switch (lead) {
    case 0xE0: low  = 0xA0; break;
    case 0xED: high = 0x9F; break;
    case 0xF0: low  = 0x90; break;
    case 0xF4: high = 0x8F; break;
    }

    uint8_t second = bytes[index + 1];
    if (second < low || second > high) return 0;

    for (size_t i = 2; i < width; i++)
        if ((bytes[index + i] & 0xC0) != 0x80) return 0;

    return width;
}

/* Counts the steps String.NextCodePoint takes: one per well-formed sequence,
 * and one per byte of anything else. */
size_t sl_string_code_point_count(void *pointer)
{
    SlString      *string = (SlString *)pointer;
    const uint8_t *bytes  = sl_string_data(string);
    size_t         length = string->byteLength;
    size_t         count  = 0;

    for (size_t i = 0; i < length; count++) {
        size_t width = sl_utf8_well_formed_width(bytes, length, i);
        i += width == 0 ? 1 : width;
    }

    return count;
}

/*
 * One code point, as the UTF-8 that spells it.
 *
 * What `$"{c}"` writes. Printing the number instead would be the wrong answer
 * in the one place a char is being shown to somebody, and the cast to say
 * "the number, please" is right there for when it is not.
 *
 * A value that is not a code point -- past the maximum, or in the surrogate
 * range, which UTF-8 must not encode -- becomes U+FFFD. That is the
 * replacement character's job, and it keeps a String's bytes valid UTF-8 by
 * construction.
 */
/*
 * One code point as UTF-8. Lifted out of sl_string_from_char so that the
 * string builder appends a character through the same four branches rather
 * than carrying a second copy of them.
 */
size_t sl_utf8_encode(uint32_t codePoint, uint8_t *bytes)
{
    if (codePoint > 0x10FFFF || (codePoint >= 0xD800 && codePoint <= 0xDFFF))
        codePoint = 0xFFFD;

    if (codePoint < 0x80) {
        bytes[0] = (uint8_t)codePoint;
        return 1;
    }

    if (codePoint < 0x800) {
        bytes[0] = (uint8_t)(0xC0 | (codePoint >> 6));
        bytes[1] = (uint8_t)(0x80 | (codePoint & 0x3F));
        return 2;
    }

    if (codePoint < 0x10000) {
        bytes[0] = (uint8_t)(0xE0 | (codePoint >> 12));
        bytes[1] = (uint8_t)(0x80 | ((codePoint >> 6) & 0x3F));
        bytes[2] = (uint8_t)(0x80 | (codePoint & 0x3F));
        return 3;
    }

    bytes[0] = (uint8_t)(0xF0 | (codePoint >> 18));
    bytes[1] = (uint8_t)(0x80 | ((codePoint >> 12) & 0x3F));
    bytes[2] = (uint8_t)(0x80 | ((codePoint >> 6) & 0x3F));
    bytes[3] = (uint8_t)(0x80 | (codePoint & 0x3F));
    return 4;
}

void *sl_string_from_char(uint32_t codePoint)
{
    uint8_t bytes[4];
    size_t length = sl_utf8_encode(codePoint, bytes);
    return sl_string_from_bytes(bytes, length);
}

/*
 * Several strings into one, in a single allocation.
 *
 * What an interpolated string lowers to. Chaining sl_string_concat would
 * allocate once per operator and throw all but the last away -- five calls and
 * four dead strings for `$"a{b}c{d}e"` -- so the whole length is measured
 * first and the bytes copied once.
 *
 * A null part contributes nothing, which lets a caller skip a piece it knows
 * is empty without a special case here.
 */
void *sl_string_join(void *const *parts, size_t count)
{
    size_t total = 0;
    for (size_t i = 0; i < count; i += 1) {
        if (parts[i] == NULL) continue;

        size_t part = ((SlString *)parts[i])->byteLength;
        if (total > SIZE_MAX - part) sl_fail("string is too large to allocate");
        total += part;
    }

    SlString *joined = sl_string_new(total);
    uint8_t *at = sl_string_data(joined);

    for (size_t i = 0; i < count; i += 1) {
        if (parts[i] == NULL) continue;

        SlString *part = (SlString *)parts[i];
        memcpy(at, sl_string_data(part), part->byteLength);
        at += part->byteLength;
    }

    return joined;
}

void *sl_string_concat(void *leftPointer, void *rightPointer)
{
    SlString *left  = (SlString *)leftPointer;
    SlString *right = (SlString *)rightPointer;

    size_t    total  = left->byteLength + right->byteLength;
    SlString *result = sl_string_new(total);
    uint8_t  *data   = sl_string_data(result);

    memcpy(data, sl_string_data(left), left->byteLength);
    memcpy(data + left->byteLength, sl_string_data(right), right->byteLength);
    return result;
}

_Bool sl_string_equals(void *leftPointer, void *rightPointer)
{
    SlString *left  = (SlString *)leftPointer;
    SlString *right = (SlString *)rightPointer;

    if (left == right) return 1;
    if (left == NULL || right == NULL) return 0;
    if (left->byteLength != right->byteLength) return 0;

    return memcmp(sl_string_data(left), sl_string_data(right), left->byteLength) == 0;
}

/* Byte-based, clamped to the end of the string rather than trapping. */
void *sl_string_substring(void *pointer, size_t start, size_t length)
{
    SlString *string = (SlString *)pointer;

    if (start >= string->byteLength) return sl_string_new(0);
    if (length > string->byteLength - start) length = string->byteLength - start;

    return sl_string_from_bytes(sl_string_data(string) + start, length);
}

void *sl_string_from_integer(long long value)
{
    char buffer[32];
    int  written = snprintf(buffer, sizeof buffer, "%lld", value);
    return sl_string_from_bytes((const uint8_t *)buffer, (size_t)(written < 0 ? 0 : written));
}

/*
 * The same for an unsigned value, which is a separate entry point because it
 * has to be: a `nuint` or a `ulong` past 2^63 read through "%lld" prints as a
 * negative number, and every length, index and hash in the language is one of
 * those types.
 */
void *sl_string_from_unsigned(unsigned long long value)
{
    char buffer[32];
    int  written = snprintf(buffer, sizeof buffer, "%llu", value);
    return sl_string_from_bytes((const uint8_t *)buffer, (size_t)(written < 0 ? 0 : written));
}

/*
 * A `nuint`, which is a `size_t` and so four bytes on a 32-bit target. It
 * cannot be the entry point above under another declaration: a caller passing
 * four bytes to a function that reads eight prints the next thing on the stack
 * as the high half.
 */
void *sl_string_from_size(size_t value)
{
    return sl_string_from_unsigned((unsigned long long)value);
}

/*
 * The shortest text that reads back as exactly this double.
 *
 * Plain "%g" is six significant digits, which is not a rounding so much as a
 * different number: pi printed as 3.14159, a 64-bit identifier in a JSON
 * document as 9.22337e+18, and nothing at all survived being written and read
 * back. A program that writes measurements to a file lost them, quietly, and
 * the only sign was that the file was shorter than it should have been.
 *
 * Seventeen digits always round-trips and is what "%.17g" gives, but it also
 * gives 0.10000000000000001 for a tenth, which is correct and unreadable. So
 * the shortest *text* that reads back as the same value wins -- every
 * precision from one to seventeen is tried and the shortest kept.
 *
 * The shortest text and the shortest precision are not the same thing, which
 * is the trap here and was worth one wrong answer to learn: "%.1g" of 60 is
 * "6e+01", which round-trips perfectly and is five characters where "%.2g"
 * gives "60". "%g" turns exponential once the precision drops below the
 * decimal exponent, so stopping at the first precision that round-trips turns
 * every round number into scientific notation. All seventeen are cheap --
 * a snprintf and a strtod each -- and printing a number is not a hot path.
 *
 * NaN never equals itself, so nothing round-trips and it falls through to the
 * full-precision spelling, which prints "nan". Infinity compares equal and is
 * found at the first precision.
 */
size_t sl_format_double(char *buffer, size_t size, double value)
{
    char   shortest[64];
    size_t best = 0;

    for (int digits = 1; digits <= 17; digits++)
    {
        char candidate[64];
        int  written = snprintf(candidate, sizeof candidate, "%.*g", digits, value);

        if (written <= 0 || (size_t)written >= sizeof candidate) continue;
        if (strtod(candidate, NULL) != value) continue;

        if (best != 0)
        {
            /* Shorter wins, and on a tie the one without an exponent does:
             * "7e+04" and "70000" are both five characters and only one of
             * them is what anybody meant by seventy thousand. */
            _Bool shorter = (size_t)written < best;
            _Bool plainer = (size_t)written == best &&
                            strchr(shortest, 'e') != NULL &&
                            strchr(candidate, 'e') == NULL;

            if (!shorter && !plainer) continue;
        }

        memcpy(shortest, candidate, (size_t)written + 1);
        best = (size_t)written;
    }

    if (best == 0 || best >= size)
    {
        int written = snprintf(buffer, size, "%.17g", value);
        return (size_t)(written < 0 ? 0 : written);
    }

    memcpy(buffer, shortest, best);
    return best;
}

void *sl_string_from_double(double value)
{
    char   buffer[64];
    size_t written = sl_format_double(buffer, sizeof buffer, value);
    return sl_string_from_bytes((const uint8_t *)buffer, written);
}

/*
 * The value some digits spell, correctly rounded.
 *
 * The caller has already decided the text is well formed -- which spellings a
 * number may have is the library's rule and not this one's -- so all that is
 * wanted here is the arithmetic, and the arithmetic is the part that is hard
 * to do by hand. Ten times a running total loses a bit per digit and a running
 * scale of a tenth loses more, because a tenth is not a binary fraction; a
 * number written at full precision then did not read back as itself.
 *
 * A copy is made because the bytes are a String's and are not terminated.
 * Anything longer than the buffer cannot name a distinct double anyway: a
 * double carries seventeen significant digits and an exponent of three.
 */
double sl_parse_double(const uint8_t *text, size_t count)
{
    char buffer[512];

    if (count >= sizeof buffer) count = sizeof buffer - 1;
    memcpy(buffer, text, count);
    buffer[count] = '\0';

    return strtod(buffer, NULL);
}

void *sl_string_from_bool(_Bool value)
{
    return value ? sl_string_from_bytes((const uint8_t *)"true", 4)
                 : sl_string_from_bytes((const uint8_t *)"false", 5);
}
