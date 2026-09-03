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

/* ------------------------------------------------------------- reflection */

/*
 * What a field or attribute value holds. Kept in step with FieldKind in the
 * compiler and with Standard.Reflection.
 */
enum SlKind {
    SL_KIND_NONE = 0,
    SL_KIND_BOOL, SL_KIND_CHAR,
    SL_KIND_SBYTE, SL_KIND_SHORT, SL_KIND_INT, SL_KIND_LONG, SL_KIND_NINT,
    SL_KIND_BYTE, SL_KIND_USHORT, SL_KIND_UINT, SL_KIND_ULONG, SL_KIND_NUINT,
    SL_KIND_FLOAT, SL_KIND_DOUBLE,
    SL_KIND_POINTER, SL_KIND_STRING,
    SL_KIND_CLASS, SL_KIND_INTERFACE, SL_KIND_STRUCT, SL_KIND_ARRAY
};

/* An attribute argument. Constants only, so this is all a value can be. */
typedef struct SlAttributeValue {
    uint32_t    kind;
    int64_t     number;     /* the integer, or a double's bits */
    const char *text;
} SlAttributeValue;

typedef struct SlAttribute {
    const char             *name;
    size_t                  valueCount;
    const SlAttributeValue *values;
} SlAttribute;

typedef struct SlTypeInfo SlTypeInfo;

typedef struct SlFieldInfo {
    const char        *name;
    size_t             offset;      /* from the start of the object or value */
    uint32_t           kind;
    const SlTypeInfo  *type;        /* for aggregates; NULL for primitives */
    size_t             attributeCount;
    const SlAttribute *attributes;
} SlFieldInfo;

struct SlTypeInfo {
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

    /*
     * Field metadata, emitted only for a type marked [Reflect]. Everything else
     * carries a count of zero and pays nothing.
     */
    size_t              fieldCount;
    const SlFieldInfo  *fields;
    size_t              attributeCount;
    const SlAttribute  *attributes;
};

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

/*
 * Marks an object immortal, so retain and release skip it for the rest of the
 * program. Static storage uses this: a value that lives to process exit has no
 * reference traffic at all, and therefore none to race over.
 *
 * It does not make the object's contents immutable, which is why the compiler
 * only permits it for values that are immutable already.
 */
void  sl_make_immortal(void *pointer);

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

/* ------------------------------------------------- ordering and hashing */

/*
 * What a primitive, an enum or a String uses in place of implementing
 * IComparable and IHashable, which it cannot: the compiler recognises
 * CompareTo and HashCode on those types and lowers them to these. See
 * hashing.c.
 */
int32_t sl_compare_long(int64_t left, int64_t right);
int32_t sl_compare_ulong(uint64_t left, uint64_t right);
int32_t sl_compare_double(double left, double right);
int32_t sl_string_compare(void *left, void *right);

size_t sl_hash_integer(uint64_t value);
size_t sl_hash_double(double value);
size_t sl_string_hash(void *pointer);

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

/* ------------------------------------------------------------- reflection */

const char        *sl_type_name(const void *type);
size_t             sl_type_size(const void *type);
size_t             sl_type_field_count(const void *type);
const void        *sl_type_field(const void *type, size_t index);
size_t             sl_type_attribute_count(const void *type);
const void        *sl_type_attribute(const void *type, size_t index);

const char        *sl_field_name(const void *field);
size_t             sl_field_offset(const void *field);
uint32_t           sl_field_kind(const void *field);
const void        *sl_field_type(const void *field);
size_t             sl_field_attribute_count(const void *field);
const void        *sl_field_attribute(const void *field, size_t index);

const char        *sl_attribute_name(const void *attribute);
size_t             sl_attribute_value_count(const void *attribute);
uint32_t           sl_attribute_value_kind(const void *attribute, size_t index);
int64_t            sl_attribute_value_number(const void *attribute, size_t index);
const char        *sl_attribute_value_text(const void *attribute, size_t index);

/* Reading a field out of an instance, by its recorded offset. */
int64_t  sl_read_integer(const void *instance, const void *field);
double   sl_read_double(const void *instance, const void *field);
_Bool    sl_read_bool(const void *instance, const void *field);
void    *sl_read_reference(const void *instance, const void *field);

/* ---------------------------------------------------------------- Console */

void sl_console_write(void *pointer);
void sl_console_write_line(void *pointer);
void sl_console_write_error(void *pointer);

/* -------------------------------------------------------------- threading */

/*
 * See docs/concurrency.md for the model these primitives exist to serve.
 * Nothing here is reachable from Stainless yet: this is the layer the language
 * surface will be built on, not the surface.
 *
 * Reference counts remain non-atomic, and that stays correct because no two
 * threads ever touch one object. The scope handoff below is what supplies the
 * barrier that makes it so.
 *
 * The lock and condition types are opaque storage sized for the largest
 * platform primitive (glibc's pthread_mutex_t at 40 bytes, pthread_cond_t at
 * 48); Windows uses 8 bytes for each. thread.c asserts the sizes fit.
 */

typedef struct SlMutex     { void *opaque[5]; } SlMutex;
typedef struct SlCondition { void *opaque[6]; } SlCondition;

void  sl_mutex_init(SlMutex *mutex);
void  sl_mutex_destroy(SlMutex *mutex);

/*
 * A mutex on the heap, initialised and ready. Stainless reaches locking
 * through these: a class cannot embed an SlMutex, because its size is a
 * platform detail the language is not told.
 */
void *sl_mutex_new(void);
void  sl_mutex_free(void *mutex);
void  sl_mutex_lock(SlMutex *mutex);
_Bool sl_mutex_try_lock(SlMutex *mutex);
void  sl_mutex_unlock(SlMutex *mutex);

void  sl_condition_init(SlCondition *condition);
void  sl_condition_destroy(SlCondition *condition);
void  sl_condition_wait(SlCondition *condition, SlMutex *mutex);
void  sl_condition_signal(SlCondition *condition);
void  sl_condition_broadcast(SlCondition *condition);

/* Sequentially consistent. The language exposes these as Atomic<T>. */
long long sl_atomic_load(const long long *cell);
void      sl_atomic_store(long long *cell, long long value);
long long sl_atomic_add(long long *cell, long long delta);
long long sl_atomic_exchange(long long *cell, long long value);
_Bool     sl_atomic_compare_exchange(long long *cell, long long *expected, long long desired);

typedef struct SlThread SlThread;

SlThread *sl_thread_start(void (*entry)(void *), void *argument);
void      sl_thread_join(SlThread *thread);
void      sl_thread_yield(void);
size_t    sl_thread_current_id(void);
size_t    sl_cpu_count(void);

/* --------------------------------------------------------------- the pool */

typedef void (*SlJob)(void *argument);

/*
 * A scope is the join counter behind a `parallel` block. Jobs submitted to one
 * cannot outlive it: sl_scope_end does not return until every one has run.
 */
typedef struct SlScope SlScope;

/* Starts the shared pool. Passing 0 sizes it from the CPU count. Optional --
 * a scope starts the pool itself on first use. */
void   sl_pool_start(size_t workers);
void   sl_pool_shutdown(void);
size_t sl_pool_worker_count(void);

SlScope *sl_scope_begin(void);
void     sl_scope_submit(SlScope *scope, SlJob job, void *argument);
void     sl_scope_end(SlScope *scope);

/*
 * A job over half-open index range [start, end). What `parallel for` compiles
 * its body into.
 */
typedef void (*SlRangeJob)(void *capture, size_t start, size_t end);

/*
 * Splits [0, count) into chunks and submits one job per chunk.
 *
 * The split lives here rather than in emitted code because it depends on the
 * pool's size, which the compiler does not know, and because getting it wrong
 * is a performance question rather than a correctness one -- the right place
 * to change it later is one C function.
 */
void sl_parallel_range(SlScope *scope, size_t count, SlRangeJob job, void *capture);

#endif /* STAINLESS_RUNTIME_H */
