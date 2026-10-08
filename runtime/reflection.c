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
 * Reading the metadata the compiler emitted.
 *
 * There is no machinery here at all: the tables are `const` data laid down at
 * compile time, and these are accessors over them. Reflection in a native
 * language is not a runtime feature, it is a layout agreement.
 *
 * A type carries tables only when it is marked [Reflect]; everything else has a
 * count of zero, and nothing in this file is reached.
 */

#include "stainless.h"
#include <string.h>

/*
 * What a handle that found nothing reads as: a type, a field, a property and
 * an attribute with no name and nothing in them. Every accessor goes through
 * these, so a missing type answers that it has no members, a missing property
 * that it cannot be read or written, and an index into either fails its bounds
 * check -- rather than any of them reading through null.
 */
static const SlTypeInfo     sl_no_type      = { .name = "" };
static const SlFieldInfo    sl_no_field     = { .name = "" };
static const SlPropertyInfo sl_no_property  = { .name = "" };
static const SlAttribute    sl_no_attribute = { .name = "" };

static const SlTypeInfo *sl_type_info(const void *type)
{
    return type != NULL ? (const SlTypeInfo *)type : &sl_no_type;
}

static const SlFieldInfo *sl_field_info(const void *field)
{
    return field != NULL ? (const SlFieldInfo *)field : &sl_no_field;
}

static const SlPropertyInfo *sl_property_info(const void *property)
{
    return property != NULL ? (const SlPropertyInfo *)property : &sl_no_property;
}

static const SlAttribute *sl_attribute_info(const void *attribute)
{
    return attribute != NULL ? (const SlAttribute *)attribute : &sl_no_attribute;
}

/* The kinds a field holds a counted reference in. */
static _Bool sl_kind_is_counted(uint32_t kind)
{
    switch (kind) {
        case SL_KIND_STRING:
        case SL_KIND_CLASS:
        case SL_KIND_INTERFACE:
        case SL_KIND_ARRAY:
            return 1;
        default:
            return 0;
    }
}

/* ------------------------------------------------------------------- types */

const char *sl_type_name(const void *type)
{
    return sl_type_info(type)->name;
}

size_t sl_type_size(const void *type)
{
    return sl_type_info(type)->size;
}

size_t sl_type_field_count(const void *type)
{
    return sl_type_info(type)->fieldCount;
}

const void *sl_type_field(const void *type, size_t index)
{
    const SlTypeInfo *info = sl_type_info(type);
    if (index >= info->fieldCount) sl_array_bounds_fail(index, info->fieldCount);
    return &info->fields[index];
}

size_t sl_type_attribute_count(const void *type)
{
    return sl_type_info(type)->attributeCount;
}

const void *sl_type_attribute(const void *type, size_t index)
{
    const SlTypeInfo *info = sl_type_info(type);
    if (index >= info->attributeCount) sl_array_bounds_fail(index, info->attributeCount);
    return &info->attributes[index];
}

/* ------------------------------------------------------------------ fields */

const char *sl_field_name(const void *field)
{
    return sl_field_info(field)->name;
}

size_t sl_field_offset(const void *field)
{
    return sl_field_info(field)->offset;
}

uint32_t sl_field_kind(const void *field)
{
    return sl_field_info(field)->kind;
}

const void *sl_field_type(const void *field)
{
    return sl_field_info(field)->type;
}

size_t sl_field_attribute_count(const void *field)
{
    return sl_field_info(field)->attributeCount;
}

const void *sl_field_attribute(const void *field, size_t index)
{
    const SlFieldInfo *info = sl_field_info(field);
    if (index >= info->attributeCount) sl_array_bounds_fail(index, info->attributeCount);
    return &info->attributes[index];
}

/* -------------------------------------------------------------- attributes */

const char *sl_attribute_name(const void *attribute)
{
    return sl_attribute_info(attribute)->name;
}

size_t sl_attribute_value_count(const void *attribute)
{
    return sl_attribute_info(attribute)->valueCount;
}

static const SlAttributeValue *sl_attribute_value(const void *attribute, size_t index)
{
    const SlAttribute *info = sl_attribute_info(attribute);
    if (index >= info->valueCount) sl_array_bounds_fail(index, info->valueCount);
    return &info->values[index];
}

uint32_t sl_attribute_value_kind(const void *attribute, size_t index)
{
    return sl_attribute_value(attribute, index)->kind;
}

int64_t sl_attribute_value_number(const void *attribute, size_t index)
{
    return sl_attribute_value(attribute, index)->number;
}

const char *sl_attribute_value_text(const void *attribute, size_t index)
{
    return sl_attribute_value(attribute, index)->text;
}

/* --------------------------------------------------------------- instances */

int64_t sl_read_at_integer(const void *address, uint32_t kind);
double  sl_read_at_double(const void *address, uint32_t kind);
_Bool   sl_read_at_bool(const void *address);
void    sl_write_at_integer(void *address, uint32_t kind, int64_t value);
void    sl_write_at_double(void *address, uint32_t kind, double value);

/*
 * Reading a field is address arithmetic and a load of the recorded width. A
 * kind that does not match the reader answers zero.
 */
static const void *sl_field_address(const void *instance, const void *field)
{
    return (const uint8_t *)instance + sl_field_info(field)->offset;
}

int64_t sl_read_integer(const void *instance, const void *field)
{
    return sl_read_at_integer(sl_field_address(instance, field),
                              sl_field_info(field)->kind);
}

double sl_read_double(const void *instance, const void *field)
{
    return sl_read_at_double(sl_field_address(instance, field),
                             sl_field_info(field)->kind);
}

_Bool sl_read_bool(const void *instance, const void *field)
{
    if (sl_field_info(field)->kind != SL_KIND_BOOL) return 0;
    return sl_read_at_bool(sl_field_address(instance, field));
}

/* Borrowed: the instance still owns it, so the caller must retain to keep it.
   Null for a field that holds no counted reference. */
void *sl_read_reference(const void *instance, const void *field)
{
    if (!sl_kind_is_counted(sl_field_info(field)->kind)) return NULL;
    return *(void *const *)sl_field_address(instance, field);
}

/* ----------------------------------------------------------------- writing */

static void *sl_field_slot(void *instance, const void *field)
{
    return (uint8_t *)instance + sl_field_info(field)->offset;
}

/*
 * Narrowed to the field's own width, so a value too large for it wraps there
 * rather than writing over the field beside it. That is C's rule for an
 * assignment of the same shape, and the alternative -- writing eight bytes
 * whatever the field is -- would corrupt the object silently.
 */
void sl_write_integer(void *instance, const void *field, int64_t value)
{
    sl_write_at_integer(sl_field_slot(instance, field),
                        sl_field_info(field)->kind, value);
}

void sl_write_double(void *instance, const void *field, double value)
{
    sl_write_at_double(sl_field_slot(instance, field),
                       sl_field_info(field)->kind, value);
}

void sl_write_bool(void *instance, const void *field, _Bool value)
{
    if (sl_field_info(field)->kind != SL_KIND_BOOL) { return; }
    *(_Bool *)sl_field_slot(instance, field) = value;
}

/*
 * Whether `value` may be stored where a reference of `kind` and `type` goes.
 *
 * Every argument here is untyped, so nothing else stops a String going into a
 * field of some class, where the next call through it would read the text as
 * a dispatch table. A String MUST go where a String goes and nowhere else, and
 * an object into a class slot MUST be that class or derive from it. An
 * interface or an array slot is checked only against a String: what else would
 * fit is not described here.
 */
static _Bool sl_reference_fits(uint32_t kind, const SlTypeInfo *type, const void *value)
{
    if (value == NULL) return 1;

    _Bool text = ((const SlObject *)value)->type == &sl_string_type_info;

    switch (kind) {
        case SL_KIND_STRING:    return text;
        case SL_KIND_CLASS:     return type != NULL ? sl_is_instance(value, type) != 0 : !text;
        case SL_KIND_INTERFACE:
        case SL_KIND_ARRAY:     return !text;
        default:                return 0;
    }
}

/*
 * Retain before release, for the reason every owning store in the emitter does
 * it: writing a field back to itself must not destroy the value on the way.
 * A null for a field that is never null is refused, leaving the field as it was,
 * and so is a value of the wrong type.
 */
void sl_write_reference(void *instance, const void *field, void *value)
{
    const SlFieldInfo *info = sl_field_info(field);

    /* Anything else would be retained, released and stored over bytes that
       are not a reference. */
    if (!sl_kind_is_counted(info->kind)) return;
    if (value == NULL && (info->flags & SL_FIELD_NO_ZERO)) return;
    if (!sl_reference_fits(info->kind, info->type, value)) return;

    sl_write_at_reference(sl_field_slot(instance, field), value);
}

void sl_write_at_reference(void *address, void *value)
{
    void **slot = (void **)address;

    sl_retain(value);
    sl_release(*slot);
    *slot = value;
}

/*
 * The bytes rather than the String, which is what keeps a counted reference out
 * of this ABI -- the same bargain the read side makes by handing back bytes for
 * the caller to copy. The String made here is owned by the field, and the
 * retain inside sl_write_reference is what pays for it, so the +1 this starts
 * with is released immediately after.
 */
void sl_write_text(void *instance, const void *field,
                   const void *bytes, size_t length)
{
    if (sl_field_info(field)->kind != SL_KIND_STRING) { return; }

    void *text = sl_string_from_bytes((const uint8_t *)bytes, length);
    sl_write_reference(instance, field, text);
    sl_release(text);
}

void *sl_type_create(const void *type)
{
    const SlTypeInfo *info = sl_type_info(type);
    if (info == NULL || info->create == NULL) return NULL;
    return info->create();
}

_Bool sl_type_can_create(const void *type)
{
    return type != NULL && sl_type_info(type)->create != NULL;
}

/*
 * Whether storage of this kind holds a value. A reference is asked whether it
 * is null; a struct with metadata is asked field by field, none of which any
 * constructor wrote; anything else with no zero value cannot be seen into.
 */
static _Bool sl_slot_is_complete(const uint8_t *address, uint32_t kind,
                                 uint32_t noZero, const SlTypeInfo *type)
{
    size_t i;

    if (!noZero) return 1;

    switch (kind) {
        case SL_KIND_STRING:
        case SL_KIND_CLASS:
        case SL_KIND_INTERFACE:
        case SL_KIND_ARRAY:
            return *(void *const *)address != NULL;

        case SL_KIND_STRUCT:
            if (type == NULL || type->fieldCount == 0) return 0;
            for (i = 0; i < type->fieldCount; i++) {
                const SlFieldInfo *inner = &type->fields[i];
                if (!sl_slot_is_complete(address + inner->offset, inner->kind,
                                         inner->flags & SL_FIELD_NO_ZERO, inner->type))
                    return 0;
            }
            return 1;

        default:
            return 0;
    }
}

/*
 * A field the constructor did not leave to the maker was written by it, as
 * §2.16 requires of every constructor, so only the required ones are asked.
 */
_Bool sl_type_is_complete(const void *type, const void *instance)
{
    const SlTypeInfo *info = sl_type_info(type);
    size_t i;

    for (i = 0; i < info->fieldCount; i++) {
        const SlFieldInfo *field = &info->fields[i];
        if (!(field->flags & SL_FIELD_REQUIRED)) continue;
        if (!sl_slot_is_complete((const uint8_t *)instance + field->offset, field->kind,
                                 field->flags & SL_FIELD_NO_ZERO, field->type))
            return 0;
    }
    return 1;
}

_Bool sl_field_element_is_complete(const void *field, const void *address)
{
    const SlFieldInfo *info = sl_field_info(field);
    return sl_slot_is_complete((const uint8_t *)address, info->elementKind,
                               info->flags & SL_FIELD_ELEMENT_NO_ZERO, info->elementType);
}

/* ------------------------------------------------------ array elements */

uint32_t sl_field_element_kind(const void *field)
{
    return sl_field_info(field)->elementKind;
}

const void *sl_field_element_type(const void *field)
{
    return sl_field_info(field)->elementType;
}

size_t sl_field_element_size(const void *field)
{
    return sl_field_info(field)->elementSize;
}

/*
 * A new array for an array-typed field, of a length nothing knew at compile
 * time.
 *
 * This is the one thing reflection could not do about an array. Elements could
 * be read and written, and the stride made that possible without knowing the
 * element type -- but there was no way to *make* one, so a document that said
 * how many elements it had could only be read into an array that already
 * happened to be the right length. That is why Standard.Json could round-trip
 * an array and not fill one.
 *
 * Everything it takes was already here. The field's own record carries the
 * array type -- the same record sl_array_alloc takes when the compiler emits a
 * `new T[n]` -- and the stride beside it, and the type's destroy hook already
 * knows whether the elements are references and how to walk them. So this adds
 * no knowledge, only an entry point: nothing about the header, the layout or
 * the lifetime is decided here.
 *
 * Null when the field is not an array, or is one the compiler recorded no type
 * for. The caller writes the result through sl_write_reference, which retains
 * it, so the array is owned by the object it was written into.
 *
 * The elements are zero bytes. For an element type with no zero value the
 * caller MUST fill every one before the array is reachable, which
 * Standard.Reflection checks with sl_field_element_is_complete.
 */
void *sl_field_new_array(const void *field, size_t length)
{
    const SlFieldInfo *info = sl_field_info(field);

    if (info->kind != SL_KIND_ARRAY || info->type == NULL) return NULL;

    return sl_array_alloc(info->type, length, info->elementSize);
}

/* The elements begin immediately after the header, as sl_array_alloc lays them out. */
void *sl_array_data(void *array)
{
    if (array == NULL) { return NULL; }
    return (uint8_t *)array + sizeof(SlArray);
}

/*
 * Reading and writing at an address of a stated kind. The field versions above
 * are these with the offset already applied; an array element has a kind and a
 * stride and no SlFieldInfo of its own, which is why these exist.
 */
int64_t sl_read_at_integer(const void *address, uint32_t kind)
{
    switch (kind) {
        case SL_KIND_SBYTE:  return *(const int8_t   *)address;
        case SL_KIND_SHORT:  return *(const int16_t  *)address;
        case SL_KIND_INT:    return *(const int32_t  *)address;
        case SL_KIND_LONG:   return *(const int64_t  *)address;
        case SL_KIND_NINT:   return *(const intptr_t *)address;
        case SL_KIND_CHAR:
        case SL_KIND_BYTE:   return *(const uint8_t  *)address;
        case SL_KIND_CHAR16:
        case SL_KIND_USHORT: return *(const uint16_t *)address;
        case SL_KIND_CHAR32:
        case SL_KIND_UINT:   return *(const uint32_t *)address;
        case SL_KIND_ULONG:  return (int64_t)*(const uint64_t *)address;
        case SL_KIND_NUINT:  return (int64_t)*(const uintptr_t *)address;
        default:             return 0;
    }
}

double sl_read_at_double(const void *address, uint32_t kind)
{
    switch (kind) {
        case SL_KIND_FLOAT:  return *(const float  *)address;
        case SL_KIND_DOUBLE: return *(const double *)address;
        default:             return 0.0;
    }
}

/* Read as a byte, so storage holding neither 0 nor 1 is not loaded as a _Bool. */
_Bool sl_read_at_bool(const void *address)
{
    return *(const uint8_t *)address != 0;
}

void *sl_read_at_reference(const void *address)
{
    return *(void *const *)address;
}

void sl_write_at_integer(void *address, uint32_t kind, int64_t value)
{
    switch (kind) {
        case SL_KIND_SBYTE:  *(int8_t   *)address = (int8_t)value;   break;
        case SL_KIND_SHORT:  *(int16_t  *)address = (int16_t)value;  break;
        case SL_KIND_INT:    *(int32_t  *)address = (int32_t)value;  break;
        case SL_KIND_LONG:   *(int64_t   *)address = value;            break;
        case SL_KIND_NINT:   *(intptr_t  *)address = (intptr_t)value;  break;
        case SL_KIND_CHAR:
        case SL_KIND_BYTE:   *(uint8_t   *)address = (uint8_t)value;   break;
        case SL_KIND_CHAR16:
        case SL_KIND_USHORT: *(uint16_t  *)address = (uint16_t)value;  break;
        case SL_KIND_CHAR32:
        case SL_KIND_UINT:   *(uint32_t  *)address = (uint32_t)value;  break;
        case SL_KIND_ULONG:  *(uint64_t  *)address = (uint64_t)value;  break;
        case SL_KIND_NUINT:  *(uintptr_t *)address = (uintptr_t)value; break;
        default:                                                       break;
    }
}

void sl_write_at_double(void *address, uint32_t kind, double value)
{
    switch (kind) {
        case SL_KIND_FLOAT:  *(float  *)address = (float)value; break;
        case SL_KIND_DOUBLE: *(double *)address = value;        break;
        default:                                                break;
    }
}

void sl_write_at_bool(void *address, _Bool value)
{
    *(_Bool *)address = value;
}

/* The new String is +1 and the slot takes that count. */
void sl_write_at_text(void *address, const void *bytes, size_t length)
{
    void **slot = (void **)address;
    void  *text = sl_string_from_bytes((const uint8_t *)bytes, length);

    sl_release(*slot);
    *slot = text;
}

/* ----------------------------------------------------------- properties */

uint32_t sl_field_flags(const void *field)
{
    return sl_field_info(field)->flags;
}

_Bool sl_type_is_enum(const void *type)
{
    return sl_type_info(type)->enumeration != NULL;
}

size_t sl_type_enum_count(const void *type)
{
    const SlEnumInfo *members = sl_type_info(type)->enumeration;
    return members == NULL ? 0 : members->count;
}

const char *sl_type_enum_name(const void *type, size_t index)
{
    size_t count = sl_type_enum_count(type);
    if (index >= count) sl_array_bounds_fail(index, count);
    return sl_type_info(type)->enumeration->names[index];
}

int64_t sl_type_enum_value(const void *type, size_t index)
{
    size_t count = sl_type_enum_count(type);
    if (index >= count) sl_array_bounds_fail(index, count);
    return sl_type_info(type)->enumeration->values[index];
}

size_t sl_type_event_count(const void *type)
{
    return sl_type_info(type)->eventCount;
}

const char *sl_type_event_name(const void *type, size_t index)
{
    const SlTypeInfo *info = sl_type_info(type);
    if (index >= info->eventCount) sl_array_bounds_fail(index, info->eventCount);
    return info->events[index].name;
}

const char *sl_type_event_handler_type(const void *type, size_t index)
{
    const SlTypeInfo *info = sl_type_info(type);
    if (index >= info->eventCount) sl_array_bounds_fail(index, info->eventCount);
    return info->events[index].handlerType;
}

uint32_t sl_property_flags(const void *property)
{
    return sl_property_info(property)->flags;
}

size_t sl_type_property_count(const void *type)
{
    return sl_type_info(type)->propertyCount;
}

const void *sl_type_property(const void *type, size_t index)
{
    const SlTypeInfo *info = sl_type_info(type);
    if (index >= info->propertyCount) sl_array_bounds_fail(index, info->propertyCount);
    return &info->properties[index];
}

const char *sl_property_name(const void *property)
{
    return sl_property_info(property)->name;
}

uint32_t sl_property_kind(const void *property)
{
    return sl_property_info(property)->kind;
}

const void *sl_property_type(const void *property)
{
    return sl_property_info(property)->type;
}

_Bool sl_property_can_read(const void *property)
{
    return sl_property_info(property)->getter != NULL;
}

_Bool sl_property_can_write(const void *property)
{
    return sl_property_info(property)->setter != NULL;
}

size_t sl_property_attribute_count(const void *property)
{
    return sl_property_info(property)->attributeCount;
}

const void *sl_property_attribute(const void *property, size_t index)
{
    const SlPropertyInfo *info = sl_property_info(property);
    if (index >= info->attributeCount) sl_array_bounds_fail(index, info->attributeCount);
    return &info->attributes[index];
}

/*
 * The unsafe half of reflection, written once.
 *
 * A getter's C prototype follows the property's kind, and calling one through
 * the wrong prototype is not a mistake anything reports: an int32_t returned
 * through an int64_t signature carries four bytes of whatever the ABI left in
 * the upper half. So every cast lives in these six functions and nowhere else.
 */
int64_t sl_property_get_integer(void *instance, const void *property)
{
    const SlPropertyInfo *info = sl_property_info(property);
    const void *getter = info->getter;
    if (getter == NULL) return 0;

    switch (info->kind) {
        case SL_KIND_SBYTE:  return ((int8_t   (*)(void *))getter)(instance);
        case SL_KIND_SHORT:  return ((int16_t  (*)(void *))getter)(instance);
        case SL_KIND_INT:    return ((int32_t  (*)(void *))getter)(instance);
        case SL_KIND_LONG:   return ((int64_t  (*)(void *))getter)(instance);
        case SL_KIND_NINT:   return ((intptr_t (*)(void *))getter)(instance);
        case SL_KIND_CHAR:
        case SL_KIND_BYTE:   return ((uint8_t  (*)(void *))getter)(instance);
        case SL_KIND_CHAR16:
        case SL_KIND_USHORT: return ((uint16_t (*)(void *))getter)(instance);
        case SL_KIND_CHAR32:
        case SL_KIND_UINT:   return ((uint32_t (*)(void *))getter)(instance);
        case SL_KIND_ULONG:  return (int64_t)((uint64_t  (*)(void *))getter)(instance);
        case SL_KIND_NUINT:  return (int64_t)((uintptr_t (*)(void *))getter)(instance);
        default:             return 0;
    }
}

double sl_property_get_double(void *instance, const void *property)
{
    const SlPropertyInfo *info = sl_property_info(property);
    const void *getter = info->getter;
    if (getter == NULL) return 0.0;

    switch (info->kind) {
        case SL_KIND_FLOAT:  return ((float  (*)(void *))getter)(instance);
        case SL_KIND_DOUBLE: return ((double (*)(void *))getter)(instance);
        default:             return 0.0;
    }
}

_Bool sl_property_get_bool(void *instance, const void *property)
{
    const SlPropertyInfo *info = sl_property_info(property);
    if (info->getter == NULL || info->kind != SL_KIND_BOOL) return 0;

    return ((_Bool (*)(void *))info->getter)(instance);
}

/*
 * A String, a class, an interface, an array or a raw pointer. A getter returns
 * owned, as every function does, so a counted reference comes back +1 and the
 * caller MUST release it. A raw pointer carries no count.
 */
void *sl_property_get_reference(void *instance, const void *property)
{
    const SlPropertyInfo *info = sl_property_info(property);
    const void *getter = info->getter;
    if (getter == NULL) return NULL;

    switch (info->kind) {
        case SL_KIND_STRING:
        case SL_KIND_CLASS:
        case SL_KIND_INTERFACE:
        case SL_KIND_ARRAY:
        case SL_KIND_POINTER: return ((void *(*)(void *))getter)(instance);
        default:              return NULL;
    }
}

void sl_property_set_integer(void *instance, const void *property, int64_t value)
{
    const SlPropertyInfo *info = sl_property_info(property);
    const void *setter = info->setter;
    if (setter == NULL) return;

    /* Narrowed to the property's own width, as sl_write_integer is. */
    switch (info->kind) {
        case SL_KIND_SBYTE:  ((void (*)(void *, int8_t  ))setter)(instance, (int8_t  )value); break;
        case SL_KIND_SHORT:  ((void (*)(void *, int16_t ))setter)(instance, (int16_t )value); break;
        case SL_KIND_INT:    ((void (*)(void *, int32_t ))setter)(instance, (int32_t )value); break;
        case SL_KIND_LONG:   ((void (*)(void *, int64_t ))setter)(instance, value);           break;
        case SL_KIND_NINT:   ((void (*)(void *, intptr_t))setter)(instance, (intptr_t)value); break;
        case SL_KIND_CHAR:
        case SL_KIND_BYTE:   ((void (*)(void *, uint8_t ))setter)(instance, (uint8_t )value); break;
        case SL_KIND_CHAR16:
        case SL_KIND_USHORT: ((void (*)(void *, uint16_t))setter)(instance, (uint16_t)value); break;
        case SL_KIND_CHAR32:
        case SL_KIND_UINT:   ((void (*)(void *, uint32_t))setter)(instance, (uint32_t)value); break;
        case SL_KIND_ULONG:  ((void (*)(void *, uint64_t ))setter)(instance, (uint64_t)value);  break;
        case SL_KIND_NUINT:  ((void (*)(void *, uintptr_t))setter)(instance, (uintptr_t)value); break;
        default:                                                                                break;
    }
}

void sl_property_set_double(void *instance, const void *property, double value)
{
    const SlPropertyInfo *info = sl_property_info(property);
    const void *setter = info->setter;
    if (setter == NULL) return;

    switch (info->kind) {
        case SL_KIND_FLOAT:  ((void (*)(void *, float ))setter)(instance, (float)value); break;
        case SL_KIND_DOUBLE: ((void (*)(void *, double))setter)(instance, value);        break;
        default:                                                                        break;
    }
}

void sl_property_set_bool(void *instance, const void *property, _Bool value)
{
    const SlPropertyInfo *info = sl_property_info(property);
    if (info->setter == NULL || info->kind != SL_KIND_BOOL) return;

    ((void (*)(void *, _Bool))info->setter)(instance, value);
}

uint32_t sl_property_element_kind(const void *property)
{
    return sl_property_info(property)->elementKind;
}

void sl_property_get_struct(void *instance, const void *property, void *value)
{
    const SlPropertyInfo *info = sl_property_info(property);
    if (info->getter == NULL || info->kind != SL_KIND_STRUCT) return;

    ((void (*)(void *, void *))info->getter)(instance, value);
}

void sl_property_set_struct(void *instance, const void *property, const void *value)
{
    const SlPropertyInfo *info = sl_property_info(property);
    if (info->setter == NULL || info->kind != SL_KIND_STRUCT) return;

    ((void (*)(void *, const void *))info->setter)(instance, value);
}

/*
 * A setter borrows its argument, as every function does, and retains what it
 * stores. So nothing is retained here, and the caller still owns `value`. A
 * value of the wrong type is refused, as sl_write_reference refuses one.
 */
void sl_property_set_reference(void *instance, const void *property, void *value)
{
    const SlPropertyInfo *info = sl_property_info(property);
    const void *setter = info->setter;
    if (setter == NULL) return;
    if (value == NULL && (info->flags & SL_PROPERTY_NO_ZERO)) return;
    if (!sl_reference_fits(info->kind, info->type, value)) return;

    ((void (*)(void *, void *))setter)(instance, value);
}

/* ------------------------------------------------------ finding by name */

/*
 * The registered blocks, newest first. Written only from module initializers,
 * which run single-threaded before main, so there is no lock here and no need
 * of one: by the time a second thread can exist the chain is complete.
 */
static SlTypeBlock *sl_type_blocks = NULL;

void sl_types_register(SlTypeBlock *block)
{
    if (block == NULL || block->count == 0) return;

    block->next = sl_type_blocks;
    sl_type_blocks = block;
}

/*
 * Binary search within a block, linear across them.
 *
 * Each block is sorted by the compiler, and there is one block per binary --
 * a program plus whatever libraries it loaded -- so the outer walk is over a
 * handful and the inner over everything.
 */
static const SlTypeInfo *sl_block_find(const SlTypeBlock *block, const char *name)
{
    size_t low = 0;
    size_t high = block->count;

    while (low < high) {
        size_t middle = low + (high - low) / 2;
        int order = strcmp(block->types[middle]->name, name);

        if (order == 0) return block->types[middle];
        if (order < 0) low = middle + 1;
        else           high = middle;
    }

    return NULL;
}

const void *sl_type_find(const char *name)
{
    if (name == NULL) return NULL;

    for (const SlTypeBlock *block = sl_type_blocks; block != NULL; block = block->next) {
        const SlTypeInfo *found = sl_block_find(block, name);
        if (found != NULL) return found;
    }

    return NULL;
}
