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

/* Counts scalars, not bytes: every byte that is not a UTF-8 continuation byte. */
size_t sl_string_code_point_count(void *pointer)
{
    SlString      *string = (SlString *)pointer;
    const uint8_t *bytes  = sl_string_data(string);
    size_t         count  = 0;

    for (size_t i = 0; i < string->byteLength; i++)
        if ((bytes[i] & 0xC0) != 0x80) count += 1;

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
void *sl_string_from_char(uint32_t codePoint)
{
    if (codePoint > 0x10FFFF || (codePoint >= 0xD800 && codePoint <= 0xDFFF))
        codePoint = 0xFFFD;

    uint8_t bytes[4];
    size_t length;

    if (codePoint < 0x80) {
        bytes[0] = (uint8_t)codePoint;
        length = 1;
    } else if (codePoint < 0x800) {
        bytes[0] = (uint8_t)(0xC0 | (codePoint >> 6));
        bytes[1] = (uint8_t)(0x80 | (codePoint & 0x3F));
        length = 2;
    } else if (codePoint < 0x10000) {
        bytes[0] = (uint8_t)(0xE0 | (codePoint >> 12));
        bytes[1] = (uint8_t)(0x80 | ((codePoint >> 6) & 0x3F));
        bytes[2] = (uint8_t)(0x80 | (codePoint & 0x3F));
        length = 3;
    } else {
        bytes[0] = (uint8_t)(0xF0 | (codePoint >> 18));
        bytes[1] = (uint8_t)(0x80 | ((codePoint >> 12) & 0x3F));
        bytes[2] = (uint8_t)(0x80 | ((codePoint >> 6) & 0x3F));
        bytes[3] = (uint8_t)(0x80 | (codePoint & 0x3F));
        length = 4;
    }

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
    for (size_t i = 0; i < count; i += 1)
        if (parts[i] != NULL) total += ((SlString *)parts[i])->byteLength;

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

void *sl_string_from_double(double value)
{
    char buffer[64];
    int  written = snprintf(buffer, sizeof buffer, "%g", value);
    return sl_string_from_bytes((const uint8_t *)buffer, (size_t)(written < 0 ? 0 : written));
}

void *sl_string_from_bool(_Bool value)
{
    return value ? sl_string_from_bytes((const uint8_t *)"true", 4)
                 : sl_string_from_bytes((const uint8_t *)"false", 5);
}
