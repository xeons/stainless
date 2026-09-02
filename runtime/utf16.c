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
 * Utf16String: the same shape as String, holding UTF-16 code units.
 *
 * It exists only so that platform APIs expecting wide text can be called.
 * Nothing converts to it implicitly, which is the whole point: transcoding is
 * a cost, and a cost should be visible in the source.
 */

#include "stainless.h"

#include <stdlib.h>

static void sl_utf16_string_destroy(void *object) { (void)object; }

const SlTypeInfo sl_utf16_string_type_info = {
    sizeof(SlUtf16String), sl_utf16_string_destroy, "Standard.Text.Utf16String", NULL, 0, NULL, 0, NULL
};

static uint16_t *sl_utf16_data(SlUtf16String *string)
{
    return (uint16_t *)((uint8_t *)string + sizeof(SlUtf16String));
}

static SlUtf16String *sl_utf16_new(size_t unitCount)
{
    SlUtf16String *string =
        (SlUtf16String *)calloc(1, sizeof(SlUtf16String) + (unitCount + 1) * sizeof(uint16_t));
    if (string == NULL) sl_fail("out of memory");

    sl_object_init(string, &sl_utf16_string_type_info);
    string->unitCount = unitCount;
    return string;
}

/* Decodes one UTF-8 scalar, replacing anything malformed with U+FFFD. */
static uint32_t sl_utf8_next(const uint8_t *bytes, size_t length, size_t *index)
{
    uint8_t  lead      = bytes[*index];
    size_t   remaining = length - *index;
    uint32_t scalar;
    size_t   extra;

    if (lead < 0x80)                { *index += 1; return lead; }
    else if ((lead & 0xE0) == 0xC0) { scalar = lead & 0x1F; extra = 1; }
    else if ((lead & 0xF0) == 0xE0) { scalar = lead & 0x0F; extra = 2; }
    else if ((lead & 0xF8) == 0xF0) { scalar = lead & 0x07; extra = 3; }
    else                            { *index += 1; return 0xFFFD; }

    if (remaining <= extra) { *index = length; return 0xFFFD; }

    for (size_t i = 1; i <= extra; i++) {
        uint8_t continuation = bytes[*index + i];
        if ((continuation & 0xC0) != 0x80) { *index += 1; return 0xFFFD; }
        scalar = (scalar << 6) | (uint32_t)(continuation & 0x3F);
    }

    *index += extra + 1;
    return scalar > 0x10FFFF ? 0xFFFD : scalar;
}

void *sl_string_to_utf16(void *pointer)
{
    SlString      *string = (SlString *)pointer;
    const uint8_t *bytes  = sl_string_data(string);
    size_t         length = string->byteLength;

    /* One pass to size the result, a second to fill it. */
    size_t units = 0;
    for (size_t i = 0; i < length; ) {
        uint32_t scalar = sl_utf8_next(bytes, length, &i);
        units += scalar > 0xFFFF ? 2 : 1;
    }

    SlUtf16String *result = sl_utf16_new(units);
    uint16_t      *output = sl_utf16_data(result);

    size_t written = 0;
    for (size_t i = 0; i < length; ) {
        uint32_t scalar = sl_utf8_next(bytes, length, &i);
        if (scalar > 0xFFFF) {
            scalar -= 0x10000;
            output[written++] = (uint16_t)(0xD800 + (scalar >> 10));
            output[written++] = (uint16_t)(0xDC00 + (scalar & 0x3FF));
        } else {
            output[written++] = (uint16_t)scalar;
        }
    }

    return result;
}

const uint16_t *sl_utf16_pointer(void *pointer)
{
    return sl_utf16_data((SlUtf16String *)pointer);
}

size_t sl_utf16_unit_count(void *pointer)
{
    return ((SlUtf16String *)pointer)->unitCount;
}
