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

/*
 * A function that does not come back.
 *
 * Every abort path in this header carries it, which is how the header answers
 * "can this be recovered from" without anyone having to read the body: it
 * cannot, the process is gone, and nothing written after the call runs.
 */
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
#  define SL_NORETURN _Noreturn
#elif defined(__GNUC__) || defined(__clang__)
#  define SL_NORETURN __attribute__((noreturn))
#elif defined(_MSC_VER)
#  define SL_NORETURN __declspec(noreturn)
#else
#  define SL_NORETURN
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

    /*
     * What an array's elements are, for a field of kind SL_KIND_ARRAY. Zero,
     * NULL and zero for everything else.
     *
     * Appended rather than inserted, as `base` and `vtable` were to
     * SlTypeInfo: every offset already issued keeps meaning what it meant, so
     * a library compiled before this still reads correctly.
     *
     * `elementSize` is the stride, which is what makes indexing possible
     * without knowing the element type at compile time -- a walk over an array
     * is the address of its data plus this, times the index.
     */
    uint32_t           elementKind;
    const SlTypeInfo  *elementType;
    size_t             elementSize;

    /*
     * SL_FIELD_* below. Appended for the same reason the element columns were.
     *
     * The bit that matters is SL_FIELD_PROPERTY: an automatic property's
     * storage is an ordinary field named after the property, so without this a
     * walk over the field table cannot tell `Left` the storage from `Left` the
     * property, and writing it goes straight past the setter.
     */
    uint32_t           flags;
} SlFieldInfo;

/* The storage behind an automatic property, rather than a field of its own. */
#define SL_FIELD_PROPERTY 1u

/*
 * A property, which is a pair of functions rather than a place.
 *
 * This exists because writing a field is not the same as setting a property.
 * A serializer filling plain data is right to write the storage directly, and
 * that is what the field table is for; a form loader setting `Left` on a
 * control is not, because the setter is what re-runs the layout. So the two
 * are described separately and a caller chooses.
 *
 * `getter` and `setter` are the accessors, or NULL where the property does not
 * have one. Their C signature follows `kind` -- `int32_t (*)(void *)` for an
 * int, `void (*)(void *, double)` for a double -- and sl_property_get_* below
 * is where that switch lives, once, so that no caller has to guess.
 *
 * Indexers and static properties are deliberately absent: an indexer's
 * accessors take arguments this cannot supply, and a static one has no
 * instance to pass.
 */
typedef struct SlPropertyInfo {
    const char        *name;
    uint32_t           kind;
    const SlTypeInfo  *type;        /* for aggregates; NULL for primitives */
    const void        *getter;      /* NULL for a write-only property */
    const void        *setter;      /* NULL for a read-only one */
    size_t             attributeCount;
    const SlAttribute *attributes;
} SlPropertyInfo;

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

    /*
     * Property metadata, emitted alongside the fields for a [Reflect] type.
     * Appended after `com` on the same terms as everything before it.
     */
    size_t                  propertyCount;
    const SlPropertyInfo   *properties;
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

/* Reports a fatal runtime condition and aborts. Never returns.
 *
 * SL_NORETURN is the header's answer to the question every one of these
 * raises: none of them comes back, so a caller has nothing to handle and
 * nothing after the call is reached. Saying so lets the C compiler drop the
 * unreachable tail and warn about anything written there. */
SL_API SL_NORETURN void sl_fail(const char *message);

/* The integer divisions LLVM leaves undefined. Neither returns. */
SL_API SL_NORETURN void sl_divide_by_zero(void);
SL_API SL_NORETURN void sl_divide_overflow(void);
SL_API SL_NORETURN void sl_arithmetic_overflow(void);

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
SL_API SL_NORETURN void sl_cast_failed(const void *object, const char *wanted);

/* -------------------------------------------------------------------- COM */

/*
 * COM is a calling convention, not a Windows service.
 *
 * An interface reference points at a vtable pointer, and slots 0, 1 and 2 of
 * that vtable are always QueryInterface, AddRef and Release. Nothing in that
 * needs an operating system, which is why com.c has no #ifdef in it: the
 * Windows part of COM is activation, and activation is not here.
 */

/*
 * The convention every COM method is called with.
 *
 * On x86 it is __stdcall: the callee removes the arguments, and that is what
 * every COM vtable on that architecture holds -- on Windows because Microsoft
 * defined it that way, and anywhere else because a vtable that disagreed would
 * not be COM. There is one convention on every 64-bit target, so this is empty
 * there and the whole of the difference is the line below.
 *
 * It belongs on the function pointers as much as on the functions: a call
 * through a vtable slot is where a caller and a callee disagreeing about who
 * pops the arguments would unbalance the stack, and nothing would say so.
 */
#if defined(__i386__) || defined(_M_IX86)
#  if defined(_MSC_VER) || defined(__clang__)
#    define SL_COM_METHOD __stdcall
#  else
#    define SL_COM_METHOD __attribute__((stdcall))
#  endif
#else
#  define SL_COM_METHOD
#endif

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
    int32_t  (SL_COM_METHOD *QueryInterface)(void *self, const SlGuid *iid, void **result);
    uint32_t (SL_COM_METHOD *AddRef)(void *self);
    uint32_t (SL_COM_METHOD *Release)(void *self);
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
SL_API SL_NORETURN void sl_com_cast_failed(const char *from, const char *to);

SL_API int   sl_guid_equals(const SlGuid *left, const SlGuid *right);

/* The IUnknown a `com class` gets for free. Every generated vtable puts these
   three in slots 0 to 2, so the object's own methods start at slot 3 -- and
   they go in a vtable, so they carry the convention the rest of it does. */
SL_API int32_t  SL_COM_METHOD sl_com_object_query(
    void *self, const SlGuid *iid, void **result);
SL_API uint32_t SL_COM_METHOD sl_com_object_add_ref(void *self);
SL_API uint32_t SL_COM_METHOD sl_com_object_release(void *self);

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

/*
 * One code point as UTF-8, into a caller's buffer of at least four bytes,
 * answering how many it wrote. Anything that is not a scalar becomes U+FFFD.
 */
SL_API size_t sl_utf8_encode(uint32_t codePoint, uint8_t *into);
SL_API void  *sl_string_from_null_terminated(const char *text);
SL_API void  *sl_string_from_integer(long long value);
SL_API void  *sl_string_from_unsigned(unsigned long long value);
SL_API void  *sl_string_from_double(double value);
SL_API void  *sl_string_from_bool(_Bool value);

/* The shortest text that reads back as exactly this double, written into
 * `buffer` and returning its length.
 *
 * Shared because there are two callers -- a String and a StringBuilder -- and
 * a number that prints one way in one of them and another way in the other is
 * the kind of difference nobody looks for. */
SL_API size_t sl_format_double(char *buffer, size_t size, double value);

/* The double `count` bytes at `text` spell, correctly rounded.
 *
 * The caller decides what is well formed; this only says what the digits are
 * worth. Reading them by hand -- ten times the running total, or a tenth of a
 * running scale -- compounds a rounding error per digit, so a number written
 * by sl_format_double did not read back as itself. */
SL_API double sl_parse_double(const uint8_t *text, size_t count);

/* One code point as the UTF-8 that spells it. Anything that is not one --
 * past the maximum, or a surrogate -- becomes U+FFFD, so a String's bytes
 * stay valid UTF-8 by construction. */
SL_API void  *sl_string_from_char(uint32_t codePoint);

SL_API const uint8_t *sl_string_pointer(void *pointer);
SL_API size_t sl_string_byte_length(void *pointer);
SL_API _Bool  sl_string_is_empty(void *pointer);
SL_API size_t sl_string_code_point_count(void *pointer);
SL_API void  *sl_string_concat(void *left, void *right);

/* Several strings into one, in a single allocation: what an interpolated
 * string lowers to. A null part contributes nothing. */
SL_API void  *sl_string_join(void *const *parts, size_t count);
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
SL_API void   sl_string_builder_append_byte(void *builder, uint8_t value);
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

/* Reports an out-of-range index and aborts. Neither returns. */
SL_API SL_NORETURN void sl_array_bounds_fail(size_t index, size_t length);
SL_API SL_NORETURN void sl_slice_bounds_fail(size_t from, size_t to, size_t length);

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
SL_API uint32_t sl_field_element_kind(const void *field);
SL_API const void *sl_field_element_type(const void *field);
SL_API size_t   sl_field_element_size(const void *field);

/*
 * Reading and writing at an address of a known kind, rather than at a field of
 * an instance. It is what walking an array needs: the element has a kind and a
 * stride and no SlFieldInfo of its own.
 */
SL_API int64_t  sl_read_at_integer(const void *address, uint32_t kind);
SL_API double   sl_read_at_double(const void *address, uint32_t kind);
SL_API _Bool    sl_read_at_bool(const void *address);
SL_API void    *sl_read_at_reference(const void *address);

SL_API void     sl_write_at_integer(void *address, uint32_t kind, int64_t value);
SL_API void     sl_write_at_double(void *address, uint32_t kind, double value);
SL_API void     sl_write_at_bool(void *address, _Bool value);
SL_API void     sl_write_at_text(void *address, const void *bytes, size_t length);

/* The elements of an array object, and how many there are. */
SL_API void    *sl_array_data(void *array);

SL_API int64_t  sl_read_integer(const void *instance, const void *field);
SL_API double   sl_read_double(const void *instance, const void *field);
SL_API _Bool    sl_read_bool(const void *instance, const void *field);
SL_API void    *sl_read_reference(const void *instance, const void *field);

/*
 * Writing. Each of these narrows to the field's recorded width, so a caller
 * that has checked the kind cannot write past the field it named.
 *
 * The reference writers are here rather than in the standard library because
 * they are the only part that has to touch a reference count, and doing it in
 * C keeps the one place that can get it wrong down to four lines.
 */
SL_API void sl_write_integer(void *instance, const void *field, int64_t value);
SL_API void sl_write_double(void *instance, const void *field, double value);
SL_API void sl_write_bool(void *instance, const void *field, _Bool value);
SL_API void sl_write_text(void *instance, const void *field,
                          const void *bytes, size_t length);
SL_API void sl_write_reference(void *instance, const void *field, void *value);

/* SL_FIELD_* -- whether this field is an automatic property's storage. */
SL_API uint32_t sl_field_flags(const void *field);

/* ---------------------------------------------------------- properties */

SL_API size_t      sl_type_property_count(const void *type);
SL_API const void *sl_type_property(const void *type, size_t index);

SL_API const char *sl_property_name(const void *property);
SL_API uint32_t    sl_property_kind(const void *property);
SL_API const void *sl_property_type(const void *property);
SL_API _Bool       sl_property_can_read(const void *property);
SL_API _Bool       sl_property_can_write(const void *property);
SL_API size_t      sl_property_attribute_count(const void *property);
SL_API const void *sl_property_attribute(const void *property, size_t index);

/*
 * Calling an accessor, which is the whole point of the property table.
 *
 * Each of these switches on the property's kind and casts the stored function
 * pointer to the prototype that kind implies. That switch is the unsafe part
 * of reflection and it is written once here, rather than at every call site
 * that would otherwise have to guess -- a getter returning int32_t called
 * through an int64_t prototype reads four bytes of whatever follows.
 *
 * Reading a property whose kind does not match the reader, or one with no
 * accessor, answers zero rather than calling anything.
 */
SL_API int64_t sl_property_get_integer(void *instance, const void *property);
SL_API double  sl_property_get_double(void *instance, const void *property);
SL_API _Bool   sl_property_get_bool(void *instance, const void *property);
SL_API void   *sl_property_get_reference(void *instance, const void *property);

SL_API void sl_property_set_integer(void *instance, const void *property, int64_t value);
SL_API void sl_property_set_double(void *instance, const void *property, double value);
SL_API void sl_property_set_bool(void *instance, const void *property, _Bool value);

/*
 * Setting a reference property. The setter takes ownership of a reference of
 * its own, so this retains before the call and the caller keeps theirs -- the
 * same bargain sl_write_reference makes for a field.
 */
SL_API void sl_property_set_reference(void *instance, const void *property, void *value);

/* --------------------------------------------------- finding a type by name */

/*
 * One binary's worth of reflected types, sorted by qualified name.
 *
 * A document that says "App.Button" has to reach a TypeInfo, and nothing in a
 * compiled binary looks types up: `typeof` is resolved to a constant. So each
 * module emits its own block and links it in before main runs, and the runtime
 * keeps the chain.
 *
 * `next` is written by sl_types_register and is the only mutable word in the
 * whole reflection ABI. The block itself is emitted by the compiler, so
 * registration allocates nothing and cannot fail -- which matters because it
 * happens before anything has had a chance to handle a failure.
 */
typedef struct SlTypeBlock {
    size_t                    count;
    const SlTypeInfo *const  *types;
    struct SlTypeBlock       *next;
} SlTypeBlock;

/* Links a block in. Called from a module initializer, before main. */
SL_API void sl_types_register(SlTypeBlock *block);

/*
 * The type of that qualified name -- "App.Button" -- or NULL.
 *
 * Only types marked [Reflect] are in the chain: a program that could name any
 * type at run time would be a program whose linker could drop nothing.
 */
SL_API const void *sl_type_find(const char *name);

/* Allocates a zeroed instance of a reflected type, for a deserializer. */
SL_API void *sl_type_make(const void *type);

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

/* --------------------------------------------------------- other programs */

/*
 * Starting another program, waiting for it, and reading what it wrote.
 *
 * The arguments are collected one at a time rather than passed as an array:
 * the two platforms want different things from the same list -- a vector on
 * POSIX and one quoted command line on Windows -- and collecting first lets
 * each build its own without the array's layout being known in two places.
 *
 * Every call answers with a code from the `ProcessError` in Standard.Process:
 * 0 for success, then not-found, denied, no-resource, failed.
 */
SL_API void  *sl_process_args_new(void);
SL_API _Bool  sl_process_args_add(void *handle, void *text);
SL_API void   sl_process_args_free(void *handle);

/* Runs to completion, appending both streams to the builders given. */
SL_API int    sl_process_run(void *args, void *input, void *outText, void *errText, int *exitCode);

/* Starts one and does not wait; its streams are this process's. */
SL_API void  *sl_process_start(void *args, int *error);
SL_API long   sl_process_id(void *handle);
SL_API int    sl_process_wait(void *handle, int *exitCode);

/* 1 when it has finished, 0 while it runs, -1 when it could not be asked. */
SL_API int    sl_process_poll(void *handle, int *exitCode);
SL_API _Bool  sl_process_signal(void *handle, _Bool force);
SL_API void   sl_process_release(void *handle);

/*
 * Interrupts, asked for rather than delivered.
 *
 * A signal handler runs between two instructions of whatever was executing, so
 * almost nothing is legal inside one -- no allocation, no locks, and therefore
 * no Stainless at all. A store to a flag is legal, so that is all the handler
 * does, and a program reads the flag where it can actually act on it.
 */
SL_API _Bool  sl_signals_watch(void);
SL_API _Bool  sl_signals_interrupted(void);
SL_API void   sl_signals_clear(void);

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
 *
 * Counted in `long long` rather than in pointers, because a pthread primitive
 * is not a row of pointers and does not shrink with one. glibc's i386
 * pthread_cond_t is 48 bytes on a machine whose pointer is four, so counting
 * pointers made the 32-bit storage half the size it had to be -- which is what
 * thread.c's assertions caught the first time a 32-bit Linux build ran.
 */

typedef struct SlMutex     { long long opaque[5]; } SlMutex;     /* 40 bytes */
typedef struct SlCondition { long long opaque[6]; } SlCondition; /* 48 bytes */

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
