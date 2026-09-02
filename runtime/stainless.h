/*
 * The Stainless runtime, shared declarations.
 *
 * Everything the compiler links against lives behind this header. The whole
 * runtime is reference counting over a 24-byte object header plus the handful
 * of types that cannot be written in Stainless itself yet -- there is no
 * collector, no scheduler and no startup hook.
 *
 * See docs/abi.md for the layouts the compiler and this code agree on.
 */

#ifndef STAINLESS_RUNTIME_H
#define STAINLESS_RUNTIME_H

#include <stddef.h>
#include <stdint.h>

/* ---------------------------------------------------------------- objects */

typedef struct SlTypeInfo {
    size_t              size;   /* header + fields, in bytes            */
    void              (*destroy)(void *);
    const char         *name;
    const void *const  *interfaces;
    /*
     * interfaces[id] is the vtable this type provides for the interface with
     * that id, or NULL. Interface ids are assigned across the whole program, so
     * the array is directly indexed and a dispatch never searches. The compiler
     * builds these; NULL means the type implements none.
     */
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

/* arc.c */
void *sl_alloc(const SlTypeInfo *type);
void  sl_retain(void *pointer);
void  sl_release(void *pointer);
void  sl_weak_retain(void *pointer);
void  sl_weak_release(void *pointer);
void *sl_weak_load(void *pointer);

/* Initialises a header the runtime allocated itself, outside sl_alloc. */
void  sl_object_init(void *pointer, const SlTypeInfo *type);

/* Reports a fatal runtime condition and aborts. Never returns. */
void  sl_fail(const char *message);

/* ----------------------------------------------------------------- String */

/*
 *   offset 0   strong / 8 weak / 16 type
 *   offset 24  byteLength          not counting the NUL
 *   offset 32  bytes[byteLength+1] UTF-8, NUL terminated
 */
typedef struct SlString {
    SlObject base;
    size_t   byteLength;
} SlString;

extern const SlTypeInfo sl_string_type_info;

/* Shared with utf16.c, string_builder.c and console.c. */
uint8_t  *sl_string_data(SlString *string);
SlString *sl_string_new(size_t byteLength);

void  *sl_string_from_bytes(const uint8_t *data, size_t byteLength);
void  *sl_string_from_null_terminated(const char *text);
void  *sl_string_from_integer(long long value);
void  *sl_string_from_double(double value);
void  *sl_string_from_bool(_Bool value);

const uint8_t *sl_string_pointer(void *pointer);
size_t sl_string_byte_length(void *pointer);
_Bool  sl_string_is_empty(void *pointer);
size_t sl_string_code_point_count(void *pointer);
void  *sl_string_concat(void *left, void *right);
_Bool  sl_string_equals(void *left, void *right);
void  *sl_string_substring(void *pointer, size_t start, size_t length);

/* ------------------------------------------------------------ Utf16String */

typedef struct SlUtf16String {
    SlObject base;
    size_t   unitCount;
} SlUtf16String;

extern const SlTypeInfo sl_utf16_string_type_info;

void           *sl_string_to_utf16(void *pointer);
const uint16_t *sl_utf16_pointer(void *pointer);
size_t          sl_utf16_unit_count(void *pointer);

/* ---------------------------------------------------------- StringBuilder */

typedef struct SlStringBuilder {
    SlObject  base;
    uint8_t  *bytes;
    size_t    length;
    size_t    capacity;
} SlStringBuilder;

extern const SlTypeInfo sl_string_builder_type_info;

void  *sl_string_builder_new(void);
void   sl_string_builder_append(void *pointer, void *stringPointer);
void   sl_string_builder_append_line(void *pointer, void *stringPointer);
void   sl_string_builder_append_bytes(void *pointer, const uint8_t *data, size_t byteLength);
void   sl_string_builder_append_integer(void *pointer, long long value);
void   sl_string_builder_append_double(void *pointer, double value);
size_t sl_string_builder_byte_length(void *pointer);
_Bool  sl_string_builder_is_empty(void *pointer);
void   sl_string_builder_clear(void *pointer);
void  *sl_string_builder_to_string(void *pointer);

/* ------------------------------------------------------------------ Array */

/*
 *   offset 0   strong / 8 weak / 16 type
 *   offset 24  length              element count, not bytes
 *   offset 32  elements[length]
 *
 * The element type is not stored: the compiler emits one TypeInfo per array
 * type, whose destroy hook knows how to release the elements it holds.
 */
typedef struct SlArray {
    SlObject base;
    size_t   length;
} SlArray;

void  *sl_array_alloc(const SlTypeInfo *type, size_t length, size_t elementSize);
size_t sl_array_length(void *pointer);

/* Reports an out-of-range index and aborts. Never returns. */
void   sl_array_bounds_fail(size_t index, size_t length);

/* ---------------------------------------------------------------- Console */

void sl_console_write(void *pointer);
void sl_console_write_line(void *pointer);
void sl_console_write_error(void *pointer);

#endif /* STAINLESS_RUNTIME_H */
