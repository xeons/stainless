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
    sizeof(SlStringBuilder), sl_string_builder_destroy, "Standard.Text.StringBuilder", NULL
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

/* Snapshots the builder; the builder stays usable afterwards. */
void *sl_string_builder_to_string(void *pointer)
{
    SlStringBuilder *builder = (SlStringBuilder *)pointer;
    return sl_string_from_bytes(builder->bytes, builder->length);
}
