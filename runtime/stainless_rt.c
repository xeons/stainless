/*
 * The Stainless runtime.
 *
 * Reference counting over a 24-byte object header, plus the String type. There
 * is no collector, no scheduler, no metadata tables and no startup hook, which
 * is why a Stainless binary starts as fast as a C one.
 *
 * See docs/abi.md for the header layout this file and the compiler agree on.
 */

#include <stdlib.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct SlTypeInfo {
    size_t       size;          /* header + fields, in bytes            */
    void       (*destroy)(void *);
    const char  *name;
} SlTypeInfo;

typedef struct SlObject {
    size_t              strong;
    size_t              weak;
    const SlTypeInfo   *type;
} SlObject;

/*
 * A strong count of SL_IMMORTAL marks an object the compiler placed in static
 * storage -- string literals, above all. Retain and release skip such objects
 * entirely, so a literal costs no allocation and no reference traffic.
 */
#define SL_IMMORTAL ((size_t)-1)

/*
 * A live object holds one weak reference on itself. That is what lets a weak
 * reference keep the *allocation* alive after the object is destroyed, so
 * sl_weak_load can safely read the strong count instead of reading freed memory.
 */
void *sl_alloc(const SlTypeInfo *type)
{
    SlObject *object = (SlObject *)calloc(1, type->size);
    if (object == NULL) abort();

    object->strong = 1;
    object->weak   = 1;
    object->type   = type;
    return object;
}

void sl_retain(void *pointer)
{
    SlObject *object = (SlObject *)pointer;
    if (object == NULL || object->strong == SL_IMMORTAL) return;
    object->strong += 1;
}

void sl_weak_retain(void *pointer)
{
    SlObject *object = (SlObject *)pointer;
    if (object == NULL || object->strong == SL_IMMORTAL) return;
    object->weak += 1;
}

void sl_weak_release(void *pointer)
{
    SlObject *object = (SlObject *)pointer;
    if (object == NULL || object->strong == SL_IMMORTAL) return;
    if (--object->weak == 0) free(object);
}

void sl_release(void *pointer)
{
    SlObject *object = (SlObject *)pointer;
    if (object == NULL || object->strong == SL_IMMORTAL) return;

    if (--object->strong == 0) {
        if (object->type != NULL && object->type->destroy != NULL)
            object->type->destroy(object);
        sl_weak_release(object);        /* drops the object's own weak reference */
    }
}

/* Returns a +1 strong reference, or NULL if the object is already gone. */
void *sl_weak_load(void *pointer)
{
    SlObject *object = (SlObject *)pointer;
    if (object == NULL) return NULL;
    if (object->strong == SL_IMMORTAL) return object;
    if (object->strong == 0) return NULL;

    object->strong += 1;
    return object;
}

/* ------------------------------------------------------------------ String */

/*
 * A String is an ordinary reference counted object whose text is stored inline,
 * immediately after the header. One allocation, header and bytes in the same
 * cache line, an O(1) length, and a trailing NUL that makes handing the text to
 * C free rather than a copy.
 *
 *   offset 0   strong
 *   offset 8   weak
 *   offset 16  type
 *   offset 24  byteLength          not counting the NUL
 *   offset 32  bytes[byteLength+1] UTF-8, NUL terminated
 *
 * The compiler emits string literals in exactly this shape as static constants
 * with a strong count of SL_IMMORTAL.
 */
typedef struct SlString {
    SlObject base;
    size_t   byteLength;
} SlString;

static void sl_string_destroy(void *object) { (void)object; }

const SlTypeInfo sl_string_type_info = {
    sizeof(SlString), sl_string_destroy, "Standard.Text.String"
};

static uint8_t *sl_string_data(SlString *string)
{
    return (uint8_t *)string + sizeof(SlString);
}

/* Allocates a +1 String with room for byteLength bytes plus the NUL. */
static SlString *sl_string_new(size_t byteLength)
{
    SlString *string = (SlString *)calloc(1, sizeof(SlString) + byteLength + 1);
    if (string == NULL) abort();

    string->base.strong = 1;
    string->base.weak   = 1;
    string->base.type   = &sl_string_type_info;
    string->byteLength  = byteLength;
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

/* ------------------------------------------------------------ Utf16String */

/*
 * The same shape as String, holding UTF-16 code units. It exists only so that
 * platform APIs expecting wide text can be called; nothing converts to it
 * implicitly.
 */
typedef struct SlUtf16String {
    SlObject base;
    size_t   unitCount;
} SlUtf16String;

static void sl_utf16_string_destroy(void *object) { (void)object; }

const SlTypeInfo sl_utf16_string_type_info = {
    sizeof(SlUtf16String), sl_utf16_string_destroy, "Standard.Text.Utf16String"
};

static uint16_t *sl_utf16_data(SlUtf16String *string)
{
    return (uint16_t *)((uint8_t *)string + sizeof(SlUtf16String));
}

static SlUtf16String *sl_utf16_new(size_t unitCount)
{
    SlUtf16String *string =
        (SlUtf16String *)calloc(1, sizeof(SlUtf16String) + (unitCount + 1) * sizeof(uint16_t));
    if (string == NULL) abort();

    string->base.strong = 1;
    string->base.weak   = 1;
    string->base.type   = &sl_utf16_string_type_info;
    string->unitCount   = unitCount;
    return string;
}

/* Decodes one UTF-8 scalar, replacing anything malformed with U+FFFD. */
static uint32_t sl_utf8_next(const uint8_t *bytes, size_t length, size_t *index)
{
    uint8_t  lead      = bytes[*index];
    size_t   remaining = length - *index;
    uint32_t scalar;
    size_t   extra;

    if (lead < 0x80)             { *index += 1; return lead; }
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

/* ----------------------------------------------------------------- Console */

void sl_console_write(void *pointer)
{
    SlString *string = (SlString *)pointer;
    fwrite(sl_string_data(string), 1, string->byteLength, stdout);
}

void sl_console_write_line(void *pointer)
{
    sl_console_write(pointer);
    fputc('\n', stdout);
}

void sl_console_write_error(void *pointer)
{
    SlString *string = (SlString *)pointer;
    fwrite(sl_string_data(string), 1, string->byteLength, stderr);
    fputc('\n', stderr);
}
