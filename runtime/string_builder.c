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
 * StringBuilder: the mutable counterpart to String.
 *
 * Unlike String, the bytes are a separate growable allocation, because the
 * object must outlive any particular capacity. Appending is amortised O(1),
 * which is the whole reason this type exists: building text by repeated String
 * concatenation is O(n^2).
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
    sizeof(SlStringBuilder), sl_string_builder_destroy, "Standard.Text.StringBuilder", NULL,
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
    if (builder->length + extra <= builder->capacity) return;

    size_t capacity = builder->capacity == 0 ? 32 : builder->capacity;
    while (capacity < builder->length + extra) capacity *= 2;

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

void sl_string_builder_append(void *pointer, void *stringPointer)
{
    SlString *string = (SlString *)stringPointer;
    if (string == NULL) return;
    sl_string_builder_append_bytes(pointer, sl_string_data(string), string->byteLength);
}

void sl_string_builder_append_line(void *pointer, void *stringPointer)
{
    static const uint8_t newline = 0x0A;
    sl_string_builder_append(pointer, stringPointer);
    sl_string_builder_append_bytes(pointer, &newline, 1);
}

void sl_string_builder_append_integer(void *pointer, long long value)
{
    char buffer[32];
    int  written = snprintf(buffer, sizeof buffer, "%lld", value);
    if (written > 0) sl_string_builder_append_bytes(pointer, (const uint8_t *)buffer, (size_t)written);
}

void sl_string_builder_append_double(void *pointer, double value)
{
    char buffer[64];
    int  written = snprintf(buffer, sizeof buffer, "%g", value);
    if (written > 0) sl_string_builder_append_bytes(pointer, (const uint8_t *)buffer, (size_t)written);
}

size_t sl_string_builder_byte_length(void *pointer)
{
    return ((SlStringBuilder *)pointer)->length;
}

_Bool sl_string_builder_is_empty(void *pointer)
{
    return ((SlStringBuilder *)pointer)->length == 0;
}

void sl_string_builder_clear(void *pointer)
{
    ((SlStringBuilder *)pointer)->length = 0;
}

/*
 * Reading and editing what has been built.
 *
 * The bytes are a growable allocation that moves, so nothing here hands one
 * out: a `byte*` into a builder would dangle at the next append, which is the
 * one thing String's own pointer can never do. A call per byte is the price,
 * and a builder is not where a program spends its time reading.
 */
uint8_t sl_string_builder_byte_at(void *pointer, size_t index)
{
    SlStringBuilder *builder = (SlStringBuilder *)pointer;
    if (index >= builder->length) sl_array_bounds_fail(index, builder->length);
    return builder->bytes[index];
}

void sl_string_builder_set_byte_at(void *pointer, size_t index, uint8_t value)
{
    SlStringBuilder *builder = (SlStringBuilder *)pointer;
    if (index >= builder->length) sl_array_bounds_fail(index, builder->length);
    builder->bytes[index] = value;
}

/* Inserting at the length is appending, which is why `at == length` is legal. */
void sl_string_builder_insert(void *pointer, size_t at, void *stringPointer)
{
    SlStringBuilder *builder = (SlStringBuilder *)pointer;
    SlString *string = (SlString *)stringPointer;

    if (string == NULL || string->byteLength == 0) return;
    if (at > builder->length) sl_array_bounds_fail(at, builder->length + 1);

    size_t count = string->byteLength;
    sl_string_builder_reserve(builder, count);

    memmove(builder->bytes + at + count, builder->bytes + at, builder->length - at);
    memcpy(builder->bytes + at, sl_string_data(string), count);
    builder->length += count;
}

/* Removing more than is there removes to the end rather than failing. */
void sl_string_builder_remove(void *pointer, size_t at, size_t count)
{
    SlStringBuilder *builder = (SlStringBuilder *)pointer;

    if (at >= builder->length || count == 0) return;
    if (count > builder->length - at) count = builder->length - at;

    memmove(builder->bytes + at, builder->bytes + at + count,
            builder->length - at - count);
    builder->length -= count;
}

/* Snapshots the builder; the builder stays usable afterwards. */
void *sl_string_builder_to_string(void *pointer)
{
    SlStringBuilder *builder = (SlStringBuilder *)pointer;
    return sl_string_from_bytes(builder->bytes, builder->length);
}
