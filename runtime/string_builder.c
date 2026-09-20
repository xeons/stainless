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
 * A growable byte buffer, for the runtime's own use.
 *
 * The bytes are a separate allocation from the object, because the object must
 * outlive any particular capacity. Appending is amortised O(1), which is the
 * whole reason the type exists: building text by repeated String concatenation
 * is O(n^2).
 *
 * `Standard.Text.StringBuilder` is not this. That one is Stainless, in
 * stdlib/Text.sl, and shares nothing with this but the idea. What is left here
 * is what env.c and process.c build their text with -- an environment block and
 * a Windows command line, both assembled before any Stainless code could run.
 */

#include "stainless.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void sl_string_builder_destroy(void *object)
{
    free(((SlStringBuilder *)object)->bytes);
}

const SlTypeInfo sl_string_builder_type_info = {
    sizeof(SlStringBuilder), sl_string_builder_destroy, "sl_string_builder", NULL,
    0, NULL, 0, NULL
};

void *sl_string_builder_new(void)
{
    SlStringBuilder *builder = (SlStringBuilder *)calloc(1, sizeof(SlStringBuilder));
    if (builder == NULL) sl_fail("out of memory");

    sl_object_init(builder, &sl_string_builder_type_info);
    return builder;
}

static void sl_string_builder_reserve(SlStringBuilder *builder, size_t extra)
{
    /* Both of these would wrap rather than fail: the wanted size, and the
     * doubling that reaches for it -- which on wrapping to zero would loop for
     * ever rather than merely allocate too little. */
    if (extra > SIZE_MAX - builder->length) sl_fail("string is too large to build");

    size_t wanted = builder->length + extra;
    if (wanted <= builder->capacity) return;

    size_t capacity = builder->capacity == 0 ? 32 : builder->capacity;
    while (capacity < wanted) {
        if (capacity > SIZE_MAX / 2) { capacity = wanted; break; }
        capacity *= 2;
    }

    uint8_t *bytes = (uint8_t *)realloc(builder->bytes, capacity);
    if (bytes == NULL) sl_fail("out of memory");

    builder->bytes    = bytes;
    builder->capacity = capacity;
}

void sl_string_builder_append_bytes(void *pointer, const uint8_t *data, size_t byteLength)
{
    SlStringBuilder *builder = (SlStringBuilder *)pointer;
    if (byteLength == 0 || data == NULL) return;

    sl_string_builder_reserve(builder, byteLength);
    memcpy(builder->bytes + builder->length, data, byteLength);
    builder->length += byteLength;
}

size_t sl_string_builder_byte_length(void *pointer)
{
    return ((SlStringBuilder *)pointer)->length;
}

/* Snapshots the builder; the builder stays usable afterwards. */
void *sl_string_builder_to_string(void *pointer)
{
    SlStringBuilder *builder = (SlStringBuilder *)pointer;
    return sl_string_from_bytes(builder->bytes, builder->length);
}
