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

/*
 * Whether a name leaves this library, and how a consumer reaches it.
 *
 * The runtime is built once as a shared library and linked by everything --
 * a program, and any Stainless library that program loads. That is what makes
 * one allocator, one set of reference counts and one stdio buffer serve all of
 * them: with a copy statically linked into each, an object made on one side of
 * a library boundary and released on the other would be counted twice, and the
 * `TypeInfo` a `String` carries would not be the one the other side compares
 * against.
 *
 * Windows needs the import side stated as well as the export side, because a
 * data symbol -- `sl_string_type_info`, above all -- is reached through the
 * import address table and the compiler has to know to emit that. Elsewhere
 * only the export side matters, and stating it lets everything else be hidden.
 */
#if defined(_WIN32)
#  if defined(STAINLESS_RUNTIME_BUILD)
#    define SL_API __declspec(dllexport)
#  elif defined(STAINLESS_RUNTIME_SHARED)
#    define SL_API __declspec(dllimport)
#  else
#    define SL_API
#  endif
#elif defined(STAINLESS_RUNTIME_BUILD)
#  define SL_API __attribute__((visibility("default")))
#else
#  define SL_API
#endif

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
    SL_KIND_CLASS, SL_KIND_INTERFACE, SL_KIND_STRUCT, SL_KIND_ARRAY,

    /* Appended rather than placed beside SL_KIND_CHAR: these numbers are
       written into every compiled library, so the ones already issued
       cannot move. */
    SL_KIND_CHAR16, SL_KIND_CHAR32
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

    /*
     * The class this one derives from, or NULL. A downcast walks this chain,
     * which is the only thing at run time that knows a hierarchy exists: an
     * upcast is the same pointer and needs nothing.
     */
    const SlTypeInfo   *base;

    /*
     * vtable[slot] is the implementation this class supplies for that slot,
     * inherited entries included. NULL for a class with no virtual methods.
     * Slots are assigned per family rather than per program, so a virtual call
     * is a load of this pointer and an index -- one load fewer than an
     * interface call, which has an id to look up first.
     */
    const void *const  *vtable;

    /*
     * For a `com class`, the tear-offs it presents: which interface each one
     * is for and how far into the object it sits. NULL for everything else.
     * Appended after `vtable` for the same reason `base` and `vtable` were
     * appended after `attributes` -- every offset already issued keeps meaning
     * what it meant, so a library compiled before this still reads correctly.
     */
    const void         *com;
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
SL_API void *sl_alloc(const SlTypeInfo *type);
SL_API void  sl_retain(void *pointer);
SL_API void  sl_release(void *pointer);
SL_API void  sl_weak_retain(void *pointer);
SL_API void  sl_weak_release(void *pointer);
SL_API void *sl_weak_load(void *pointer);

/* Initialises a header the runtime allocated itself, outside sl_alloc. */
SL_API void  sl_object_init(void *pointer, const SlTypeInfo *type);

/*
 * Marks an object immortal, so retain and release skip it for the rest of the
 * program. Static storage uses this: a value that lives to process exit has no
 * reference traffic at all, and therefore none to race over.
 *
 * It does not make the object's contents immutable, which is why the compiler
 * only permits it for values that are immutable already.
 */
SL_API void  sl_make_immortal(void *pointer);

/* Reports a fatal runtime condition and aborts. Never returns. */
SL_API void  sl_fail(const char *message);

/* The integer divisions LLVM leaves undefined. Neither returns. */
SL_API void  sl_divide_by_zero(void);
SL_API void  sl_divide_overflow(void);

/* ----------------------------------------------------------- inheritance */

/*
 * Whether `object` is a `type` -- that class or one deriving from it. NULL is
 * nothing's instance, which is what makes a cast from an optional a single
 * check rather than two.
 */
SL_API int   sl_is_instance(const void *object, const SlTypeInfo *type);

/* Whether `object`'s class supplies a dispatch table for that interface id. */
SL_API int   sl_implements(const void *object, size_t interfaceId);

/*
 * A checked downcast that did not hold. Names what the object really is, which
 * is the question the programmer is about to ask. Never returns.
 */
SL_API void  sl_cast_failed(const void *object, const char *wanted);

/* -------------------------------------------------------------------- COM */

/*
 * COM is a calling convention, not a Windows service.
 *
 * An interface reference points at a vtable pointer, and slots 0, 1 and 2 of
 * that vtable are always QueryInterface, AddRef and Release. Nothing in that
 * needs an operating system, which is why com.c has no #ifdef in it: the
 * Windows part of COM is activation, and activation is not here.
 */

/* 16 bytes, laid out as Windows lays a GUID out, which is what a wire format
   and every existing header agree on. */
typedef struct SlGuid {
    uint32_t data1;
    uint16_t data2;
    uint16_t data3;
    uint8_t  data4[8];
} SlGuid;

typedef struct SlComObject SlComObject;

/* The three slots every COM vtable starts with. A longer vtable is this
   followed by the interface's own methods, which is why a derived interface
   reference is usable as a base one with no conversion at all. */
typedef struct SlComVtable {
    int32_t  (*QueryInterface)(void *self, const SlGuid *iid, void **result);
    uint32_t (*AddRef)(void *self);
    uint32_t (*Release)(void *self);
} SlComVtable;

struct SlComObject {
    const SlComVtable *vtable;
};

/* HRESULT, to the extent this needs one: negative is failure. */
#define SL_COM_S_OK          ((int32_t)0)
#define SL_COM_E_NOINTERFACE ((int32_t)0x80004002)
#define SL_COM_E_POINTER     ((int32_t)0x80004003)

/*
 * What a `com class` puts in its object, once per interface it presents: the
 * vtable, and the distance back to the object's own header.
 *
 * The distance is what makes multiple interfaces work. A COM pointer must
 * point at a vtable pointer, so an object presenting three interfaces has
 * three of them at three addresses, and a Release arriving through any of them
 * has to find the one header. C++ generates adjustor thunks for this; storing
 * the offset beside each vtable pointer costs one word and no code.
 */
typedef struct SlComTearOff {
    const SlComVtable *vtable;
    size_t             ownerOffset;
} SlComTearOff;

typedef struct SlComEntry {
    const SlGuid *iid;
    size_t        offset;       /* of the tear-off, from the object's start */
} SlComEntry;

typedef struct SlComLayout {
    size_t            count;
    const SlComEntry *entries;
} SlComLayout;

SL_API extern const SlGuid sl_iid_unknown;

/* ARC for a COM reference: AddRef and Release, with the null test in one
   place rather than at every site the compiler would otherwise emit it. */
SL_API void  sl_com_retain(void *pointer);
SL_API void  sl_com_release(void *pointer);

/* QueryInterface. sl_com_query returns an owned reference or NULL; sl_com_is
   asks and drops what it was given. */
SL_API void *sl_com_query(void *pointer, const SlGuid *iid);
SL_API int   sl_com_is(void *pointer, const SlGuid *iid);
SL_API void  sl_com_cast_failed(const char *from, const char *to);

SL_API int   sl_guid_equals(const SlGuid *left, const SlGuid *right);

/* The IUnknown a `com class` gets for free. Every generated vtable puts these
   three in slots 0 to 2, so the object's own methods start at slot 3. */
SL_API int32_t  sl_com_object_query(void *self, const SlGuid *iid, void **result);
SL_API uint32_t sl_com_object_add_ref(void *self);
SL_API uint32_t sl_com_object_release(void *self);

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

SL_API extern const SlTypeInfo sl_string_type_info;

/* Shared with utf16.c, string_builder.c and console.c. */
SL_API uint8_t  *sl_string_data(SlString *string);
SL_API SlString *sl_string_new(size_t byteLength);

SL_API void  *sl_string_from_bytes(const uint8_t *data, size_t byteLength);
SL_API void  *sl_string_from_null_terminated(const char *text);
SL_API void  *sl_string_from_integer(long long value);
SL_API void  *sl_string_from_double(double value);
SL_API void  *sl_string_from_bool(_Bool value);

SL_API const uint8_t *sl_string_pointer(void *pointer);
SL_API size_t sl_string_byte_length(void *pointer);
SL_API _Bool  sl_string_is_empty(void *pointer);
SL_API size_t sl_string_code_point_count(void *pointer);
SL_API void  *sl_string_concat(void *left, void *right);
SL_API _Bool  sl_string_equals(void *left, void *right);
SL_API void  *sl_string_substring(void *pointer, size_t start, size_t length);

/*
 * UTF-8 to UTF-16 and back, on Windows only, into a buffer the caller frees.
 * NULL on failure, and on a NULL argument.
 *
 * Every Windows entry point that takes or returns text needs these: a String
 * is UTF-8 by definition, and the narrow API speaks the active code page, so a
 * name outside it would arrive as question marks rather than as itself.
 */
#ifdef _WIN32
SL_API wchar_t *sl_widen(const char *utf8);
SL_API char    *sl_narrow(const wchar_t *wide);
#endif

/* ------------------------------------------------------ files and paths */

/*
 * See io.c. Paths arrive as UTF-8 and are widened before they reach the
 * operating system; errors come back as the small stable enum Standard.IO
 * declares, rather than as errno.
 */
SL_API void   *sl_file_open(const uint8_t *path, int32_t mode, int32_t access, int32_t *error);
SL_API void    sl_file_close(void *handle);
SL_API size_t  sl_file_read(void *handle, uint8_t *buffer, size_t count, int32_t *error);
SL_API size_t  sl_file_write(void *handle, const uint8_t *buffer, size_t count, int32_t *error);
SL_API int64_t sl_file_seek(void *handle, int64_t offset, int32_t origin, int32_t *error);
SL_API int64_t sl_file_position(void *handle);
SL_API int64_t sl_file_length(void *handle);
SL_API void    sl_file_flush(void *handle);

SL_API _Bool   sl_path_exists(const uint8_t *path);
SL_API _Bool   sl_path_is_directory(const uint8_t *path);
SL_API int64_t sl_path_size(const uint8_t *path);
SL_API int64_t sl_path_modified(const uint8_t *path);

SL_API int32_t sl_file_delete(const uint8_t *path);
SL_API int32_t sl_file_rename(const uint8_t *from, const uint8_t *to);
SL_API int32_t sl_directory_create(const uint8_t *path);
SL_API int32_t sl_directory_delete(const uint8_t *path);

SL_API void          *sl_directory_open(const uint8_t *path);
SL_API const uint8_t *sl_directory_next(void *handle, _Bool *isDirectory);
SL_API void           sl_directory_close(void *handle);

/* ---------------------------------------------------------------- sockets */

/*
 * See socket.c. A socket crosses as a size_t because Winsock's INVALID_SOCKET
 * and a failed POSIX call are both all-ones once widened, so one sentinel does
 * for both platforms and there is nothing to allocate. Errors come back as the
 * small stable enum Standard.Net declares.
 */
SL_API size_t sl_socket_open(int32_t family, int32_t kind, int32_t *error);
SL_API void   sl_socket_close(size_t handle);
SL_API int32_t sl_socket_shutdown(size_t handle, int32_t how, int32_t *error);

SL_API int32_t sl_socket_bind(size_t handle, const char *host, uint16_t port,
                              int32_t family, int32_t kind, int32_t *error);
SL_API int32_t sl_socket_listen(size_t handle, int32_t backlog, int32_t *error);
SL_API size_t  sl_socket_accept(size_t handle, int32_t *error);
SL_API int32_t sl_socket_connect(size_t handle, const char *host, uint16_t port,
                                 int32_t family, int32_t kind, int32_t *error);

/*
 * Connecting is what decides the address family, so a client that has only a
 * name cannot open its socket first. This makes one per candidate address.
 */
SL_API size_t sl_socket_open_connected(const char *host, uint16_t port,
                                       int32_t family, int32_t kind, int32_t *error);

SL_API size_t sl_socket_send(size_t handle, const uint8_t *data, size_t count,
                             int32_t *error);
SL_API size_t sl_socket_receive(size_t handle, uint8_t *data, size_t count,
                                int32_t *error);
SL_API size_t sl_socket_send_to(size_t handle, const uint8_t *data, size_t count,
                                const char *host, uint16_t port, int32_t family,
                                int32_t *error);
SL_API size_t sl_socket_receive_from(size_t handle, uint8_t *data, size_t count,
                                     char *host, size_t hostSize, uint16_t *port,
                                     int32_t *error);

SL_API int32_t sl_socket_set_blocking(size_t handle, int32_t blocking, int32_t *error);
SL_API int32_t sl_socket_set_no_delay(size_t handle, int32_t on, int32_t *error);
SL_API int32_t sl_socket_set_reuse_address(size_t handle, int32_t on, int32_t *error);
SL_API int32_t sl_socket_set_broadcast(size_t handle, int32_t on, int32_t *error);
SL_API int32_t sl_socket_set_keep_alive(size_t handle, int32_t on, int32_t *error);
SL_API int32_t sl_socket_set_timeout(size_t handle, int32_t milliseconds,
                                     int32_t receiving, int32_t *error);

SL_API int32_t sl_socket_local(size_t handle, char *host, size_t size,
                               uint16_t *port, int32_t *error);
SL_API int32_t sl_socket_remote(size_t handle, char *host, size_t size,
                                uint16_t *port, int32_t *error);
SL_API int32_t sl_socket_resolve(const char *host, int32_t family, char *out,
                                 size_t size, int32_t *error);
SL_API int32_t sl_socket_wait(size_t handle, int32_t forWriting,
                              int32_t milliseconds, int32_t *error);

/* ------------------------------------------------- ordering and hashing */

/*
 * What a primitive, an enum or a String uses in place of implementing
 * IComparable and IHashable, which it cannot: the compiler recognises
 * CompareTo and HashCode on those types and lowers them to these. See
 * hashing.c.
 */
SL_API int32_t sl_compare_long(int64_t left, int64_t right);
SL_API int32_t sl_compare_ulong(uint64_t left, uint64_t right);
SL_API int32_t sl_compare_double(double left, double right);
SL_API int32_t sl_string_compare(void *left, void *right);

SL_API size_t sl_hash_integer(uint64_t value);
SL_API size_t sl_hash_double(double value);
SL_API size_t sl_string_hash(void *pointer);

/* ------------------------------------------------------------ Utf16String */

typedef struct SlUtf16String {
    SlObject base;
    size_t   unitCount;
} SlUtf16String;

SL_API extern const SlTypeInfo sl_utf16_string_type_info;

SL_API void           *sl_string_to_utf16(void *pointer);
SL_API const uint16_t *sl_utf16_pointer(void *pointer);
SL_API size_t          sl_utf16_unit_count(void *pointer);
SL_API void           *sl_string_from_utf16(const uint16_t *units, size_t unitCount);
SL_API void           *sl_string_from_null_terminated_utf16(const uint16_t *units);
SL_API void           *sl_utf16_to_string(void *pointer);

/* ---------------------------------------------------------- StringBuilder */

typedef struct SlStringBuilder {
    SlObject  base;
    uint8_t  *bytes;
    size_t    length;
    size_t    capacity;
} SlStringBuilder;

SL_API extern const SlTypeInfo sl_string_builder_type_info;

SL_API void  *sl_string_builder_new(void);
SL_API void   sl_string_builder_append(void *pointer, void *stringPointer);
SL_API void   sl_string_builder_append_line(void *pointer, void *stringPointer);
SL_API void   sl_string_builder_append_bytes(void *pointer, const uint8_t *data, size_t byteLength);
SL_API void   sl_string_builder_append_integer(void *pointer, long long value);
SL_API void   sl_string_builder_append_double(void *pointer, double value);
SL_API size_t sl_string_builder_byte_length(void *pointer);
SL_API _Bool  sl_string_builder_is_empty(void *pointer);
SL_API void   sl_string_builder_clear(void *pointer);
SL_API uint8_t sl_string_builder_byte_at(void *pointer, size_t index);
SL_API void   sl_string_builder_set_byte_at(void *pointer, size_t index, uint8_t value);
SL_API void   sl_string_builder_insert(void *pointer, size_t at, void *stringPointer);
SL_API void   sl_string_builder_remove(void *pointer, size_t at, size_t count);
SL_API void  *sl_string_builder_to_string(void *pointer);

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

SL_API void  *sl_array_alloc(const SlTypeInfo *type, size_t length, size_t elementSize);
SL_API size_t sl_array_length(void *pointer);

/* Reports an out-of-range index and aborts. Never returns. */
SL_API void   sl_array_bounds_fail(size_t index, size_t length);
SL_API void   sl_slice_bounds_fail(size_t from, size_t to, size_t length);

/* ------------------------------------------------------------- reflection */

SL_API const char        *sl_type_name(const void *type);
SL_API size_t             sl_type_size(const void *type);
SL_API size_t             sl_type_field_count(const void *type);
SL_API const void        *sl_type_field(const void *type, size_t index);
SL_API size_t             sl_type_attribute_count(const void *type);
SL_API const void        *sl_type_attribute(const void *type, size_t index);

SL_API const char        *sl_field_name(const void *field);
SL_API size_t             sl_field_offset(const void *field);
SL_API uint32_t           sl_field_kind(const void *field);
SL_API const void        *sl_field_type(const void *field);
SL_API size_t             sl_field_attribute_count(const void *field);
SL_API const void        *sl_field_attribute(const void *field, size_t index);

SL_API const char        *sl_attribute_name(const void *attribute);
SL_API size_t             sl_attribute_value_count(const void *attribute);
SL_API uint32_t           sl_attribute_value_kind(const void *attribute, size_t index);
SL_API int64_t            sl_attribute_value_number(const void *attribute, size_t index);
SL_API const char        *sl_attribute_value_text(const void *attribute, size_t index);

/* Reading a field out of an instance, by its recorded offset. */
SL_API int64_t  sl_read_integer(const void *instance, const void *field);
SL_API double   sl_read_double(const void *instance, const void *field);
SL_API _Bool    sl_read_bool(const void *instance, const void *field);
SL_API void    *sl_read_reference(const void *instance, const void *field);

/* ---------------------------------------------------------------- Console */

SL_API void sl_console_write(void *pointer);
SL_API void sl_console_write_line(void *pointer);
SL_API void sl_console_write_error(void *pointer);

/*
 * One line without its terminator, or NULL at end of input -- a blank line and
 * no line at all are different answers. Bytes are taken to be UTF-8.
 */
SL_API void *sl_console_read_line(void);
SL_API void *sl_console_read_all(void);
SL_API _Bool sl_console_at_end(void);

/* ------------------------------------------------------- the environment */

/*
 * What main() was handed. The entry point stores it before anything else runs;
 * argv[0] is the program's own name and is not counted among the arguments.
 */
SL_API void   sl_args_set(int count, char **values);
SL_API size_t sl_args_count(void);
SL_API void  *sl_args_at(size_t index);

/* Every argument as one String[]. The compiler passes the TypeInfo it built
 * for that array type, because the type tables belong to the program. */
SL_API void  *sl_args_array(const SlTypeInfo *arrayType);
SL_API void  *sl_args_program(void);

/* NULL for a variable that is not set, which is not the same as one set to
 * nothing. Windows goes through the wide API, so a value outside the active
 * code page survives. */
SL_API void  *sl_env_get(void *name);
SL_API _Bool  sl_env_set(void *name, void *value);

/* Every name, newline-separated, as one String -- the runtime has no tidy way
 * to build an array of references, and splitting is one line of Stainless. */
SL_API void  *sl_env_names(void);

SL_API void  *sl_env_current_directory(void);
SL_API _Bool  sl_env_set_current_directory(void *path);

/* ------------------------------------------------------------- the clocks */

/*
 * Nanoseconds, signed, which makes a difference ordinary subtraction.
 *
 * sl_time_now is the wall clock and can jump -- a user sets it, NTP corrects
 * it, a laptop wakes. Never subtract two readings of it to measure a duration;
 * sl_time_monotonic is the one that only goes forward, from an arbitrary zero.
 */
SL_API long long sl_time_now(void);
SL_API long long sl_time_monotonic(void);

/*
 * A moment as year, month (1-12), day, hour, minute, second, nanosecond,
 * weekday (0 = Sunday) and day of year (1-366) -- nine values, written through
 * the pointer. Returns whether the platform could name that instant.
 */
SL_API _Bool sl_time_parts(long long nanoseconds, _Bool local, long long *parts);

SL_API long long sl_time_from_parts(long long year, long long month, long long day,
                                    long long hour, long long minute, long long second,
                                    long long nanosecond, _Bool local);

/* How far ahead of UTC the local zone is at that moment, in seconds. */
SL_API long long sl_time_zone_offset(long long nanoseconds);

/* ------------------------------------------------------------- entropy */

/*
 * The platform's cryptographic source: BCryptGenRandom, or getrandom with
 * /dev/urandom behind it. Reports failure rather than falling back to a clock,
 * because a caller that wanted unpredictability and silently got the time is
 * worse off than one told it cannot have any.
 *
 * This seeds Standard.Random, which is a fast PRNG and is not itself
 * cryptographic.
 */
SL_API _Bool     sl_random_bytes(void *buffer, size_t length);
SL_API long long sl_random_seed(void);

/* -------------------------------------------------------------- threading */

/*
 * See docs/concurrency.md for the model these primitives exist to serve.
 *
 * Reference counts are atomic (arc.c), so an object two threads reach keeps an
 * accurate count. What is still checked by the compiler rather than the runtime
 * is whether an object may be reached by two threads at all, which is a
 * question about races on its contents.
 *
 * The lock and condition types are opaque storage sized for the largest
 * platform primitive (glibc's pthread_mutex_t at 40 bytes, pthread_cond_t at
 * 48); Windows uses 8 bytes for each. thread.c asserts the sizes fit.
 */

typedef struct SlMutex     { void *opaque[5]; } SlMutex;
typedef struct SlCondition { void *opaque[6]; } SlCondition;

SL_API void  sl_mutex_init(SlMutex *mutex);
SL_API void  sl_mutex_destroy(SlMutex *mutex);

/*
 * A mutex on the heap, initialised and ready. Stainless reaches locking
 * through these: a class cannot embed an SlMutex, because its size is a
 * platform detail the language is not told.
 */
SL_API void *sl_mutex_new(void);
SL_API void  sl_mutex_free(void *mutex);
SL_API void  sl_mutex_lock(SlMutex *mutex);
SL_API _Bool sl_mutex_try_lock(SlMutex *mutex);
SL_API void  sl_mutex_unlock(SlMutex *mutex);

SL_API void *sl_condition_new(void);
SL_API void  sl_condition_free(void *condition);

SL_API void  sl_condition_init(SlCondition *condition);
SL_API void  sl_condition_destroy(SlCondition *condition);
SL_API void  sl_condition_wait(SlCondition *condition, SlMutex *mutex);
SL_API void  sl_condition_signal(SlCondition *condition);
SL_API void  sl_condition_broadcast(SlCondition *condition);

/*
 * Waits with a deadline. Returns 1 if the condition was signalled and 0 if the
 * time ran out -- and a 0 still means the mutex is held, because the caller has
 * to re-check its predicate either way.
 */
SL_API _Bool sl_condition_wait_for(SlCondition *condition, SlMutex *mutex,
                                   unsigned long long milliseconds);

/*
 * A reader/writer lock, on the heap like a mutex and for the same reason: its
 * size is a platform detail the language is not told.
 *
 * Neither platform's primitive is upgradeable and neither is recursive, so a
 * reader that wants to write must let go first. That is the behaviour to want;
 * an upgrade path is a deadlock waiting for two threads to take it at once.
 */
typedef struct SlRwLock { void *opaque[8]; } SlRwLock;

SL_API void *sl_rwlock_new(void);
SL_API void  sl_rwlock_free(void *lock);
SL_API void  sl_rwlock_read_lock(void *lock);
SL_API _Bool sl_rwlock_try_read_lock(void *lock);
SL_API void  sl_rwlock_read_unlock(void *lock);
SL_API void  sl_rwlock_write_lock(void *lock);
SL_API _Bool sl_rwlock_try_write_lock(void *lock);
SL_API void  sl_rwlock_write_unlock(void *lock);

/*
 * A thread-local slot, identified by an integer the caller keeps. Every thread
 * sees its own value and starts at NULL.
 *
 * `releaseOnExit` installs sl_release as the slot's destructor, so an object
 * left in it is let go when its thread ends rather than leaking. Windows FLS
 * and pthread keys both run that callback; a slot without it is raw storage.
 */
SL_API size_t sl_tls_new(_Bool releaseOnExit);
SL_API void   sl_tls_free(size_t slot);
SL_API void  *sl_tls_get(size_t slot);
SL_API void   sl_tls_set(size_t slot, void *value);

/* Sequentially consistent. The language exposes these as Atomic<T>. */
SL_API long long sl_atomic_load(const long long *cell);
SL_API void      sl_atomic_store(long long *cell, long long value);
SL_API long long sl_atomic_add(long long *cell, long long delta);
SL_API long long sl_atomic_exchange(long long *cell, long long value);
SL_API _Bool     sl_atomic_compare_exchange(long long *cell, long long *expected, long long desired);

SL_API long long sl_atomic_and(long long *cell, long long mask);
SL_API long long sl_atomic_or(long long *cell, long long mask);
SL_API long long sl_atomic_xor(long long *cell, long long mask);

SL_API int   sl_atomic_load32(const int *cell);
SL_API void  sl_atomic_store32(int *cell, int value);
SL_API int   sl_atomic_add32(int *cell, int delta);
SL_API int   sl_atomic_exchange32(int *cell, int value);
SL_API _Bool sl_atomic_compare_exchange32(int *cell, int *expected, int desired);

SL_API void *sl_atomic_load_pointer(void *const *cell);
SL_API void  sl_atomic_store_pointer(void **cell, void *value);
SL_API void *sl_atomic_exchange_pointer(void **cell, void *value);
SL_API _Bool sl_atomic_compare_exchange_pointer(void **cell, void **expected, void *desired);

typedef struct SlThread SlThread;

SL_API SlThread *sl_thread_start(void (*entry)(void *), void *argument);
SL_API void      sl_thread_join(SlThread *thread);

/*
 * Gives up the handle without waiting. The thread keeps running and cleans
 * itself up; nothing can join it afterwards.
 */
SL_API void      sl_thread_detach(SlThread *thread);
SL_API void      sl_thread_yield(void);
SL_API void      sl_thread_sleep(unsigned long long milliseconds);
SL_API size_t    sl_thread_current_id(void);
SL_API size_t    sl_cpu_count(void);

/*
 * The CPU's "I am spinning" hint: a few cycles on x86, a yield on ARM, and
 * nothing anywhere else. It is not a scheduler call and does not sleep.
 */
SL_API void      sl_cpu_pause(void);

/* --------------------------------------------------------------- the pool */

typedef void (*SlJob)(void *argument);

/*
 * A scope is the join counter behind a `parallel` block. Jobs submitted to one
 * cannot outlive it: sl_scope_end does not return until every one has run.
 */
typedef struct SlScope SlScope;

/* Starts the shared pool. Passing 0 sizes it from the CPU count. Optional --
 * a scope starts the pool itself on first use. */
SL_API void   sl_pool_start(size_t workers);
SL_API void   sl_pool_shutdown(void);
SL_API size_t sl_pool_worker_count(void);

SL_API SlScope *sl_scope_begin(void);
SL_API void     sl_scope_submit(SlScope *scope, SlJob job, void *argument);
SL_API void     sl_scope_end(SlScope *scope);

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
SL_API void sl_parallel_range(SlScope *scope, size_t count, SlRangeJob job, void *capture);

#endif /* STAINLESS_RUNTIME_H */
