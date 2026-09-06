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

/* ------------------------------------------------------------------- types */

const char *sl_type_name(const void *type)
{
    return ((const SlTypeInfo *)type)->name;
}

size_t sl_type_size(const void *type)
{
    return ((const SlTypeInfo *)type)->size;
}

size_t sl_type_field_count(const void *type)
{
    return ((const SlTypeInfo *)type)->fieldCount;
}

const void *sl_type_field(const void *type, size_t index)
{
    const SlTypeInfo *info = (const SlTypeInfo *)type;
    if (index >= info->fieldCount) sl_array_bounds_fail(index, info->fieldCount);
    return &info->fields[index];
}

size_t sl_type_attribute_count(const void *type)
{
    return ((const SlTypeInfo *)type)->attributeCount;
}

const void *sl_type_attribute(const void *type, size_t index)
{
    const SlTypeInfo *info = (const SlTypeInfo *)type;
    if (index >= info->attributeCount) sl_array_bounds_fail(index, info->attributeCount);
    return &info->attributes[index];
}

/* ------------------------------------------------------------------ fields */

const char *sl_field_name(const void *field)
{
    return ((const SlFieldInfo *)field)->name;
}

size_t sl_field_offset(const void *field)
{
    return ((const SlFieldInfo *)field)->offset;
}

uint32_t sl_field_kind(const void *field)
{
    return ((const SlFieldInfo *)field)->kind;
}

const void *sl_field_type(const void *field)
{
    return ((const SlFieldInfo *)field)->type;
}

size_t sl_field_attribute_count(const void *field)
{
    return ((const SlFieldInfo *)field)->attributeCount;
}

const void *sl_field_attribute(const void *field, size_t index)
{
    const SlFieldInfo *info = (const SlFieldInfo *)field;
    if (index >= info->attributeCount) sl_array_bounds_fail(index, info->attributeCount);
    return &info->attributes[index];
}

/* -------------------------------------------------------------- attributes */

const char *sl_attribute_name(const void *attribute)
{
    return ((const SlAttribute *)attribute)->name;
}

size_t sl_attribute_value_count(const void *attribute)
{
    return ((const SlAttribute *)attribute)->valueCount;
}

static const SlAttributeValue *sl_attribute_value(const void *attribute, size_t index)
{
    const SlAttribute *info = (const SlAttribute *)attribute;
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

/*
 * Reading a field is address arithmetic and a load of the recorded width. The
 * caller is expected to have checked the kind first; Standard.Reflection does.
 */
static const void *sl_field_address(const void *instance, const void *field)
{
    return (const uint8_t *)instance + ((const SlFieldInfo *)field)->offset;
}

int64_t sl_read_integer(const void *instance, const void *field)
{
    const void *address = sl_field_address(instance, field);

    switch (((const SlFieldInfo *)field)->kind) {
        case SL_KIND_SBYTE:  return *(const int8_t   *)address;
        case SL_KIND_SHORT:  return *(const int16_t  *)address;
        case SL_KIND_INT:    return *(const int32_t  *)address;
        case SL_KIND_LONG:
        case SL_KIND_NINT:   return *(const int64_t  *)address;
        case SL_KIND_CHAR:
        case SL_KIND_BYTE:   return *(const uint8_t  *)address;
        case SL_KIND_USHORT: return *(const uint16_t *)address;
        case SL_KIND_UINT:   return *(const uint32_t *)address;
        case SL_KIND_ULONG:
        case SL_KIND_NUINT:  return (int64_t)*(const uint64_t *)address;
        default:             return 0;
    }
}

double sl_read_double(const void *instance, const void *field)
{
    const void *address = sl_field_address(instance, field);

    switch (((const SlFieldInfo *)field)->kind) {
        case SL_KIND_FLOAT:  return *(const float  *)address;
        case SL_KIND_DOUBLE: return *(const double *)address;
        default:             return 0.0;
    }
}

_Bool sl_read_bool(const void *instance, const void *field)
{
    return *(const _Bool *)sl_field_address(instance, field);
}

/* Borrowed: the instance still owns it, so the caller must retain to keep it. */
void *sl_read_reference(const void *instance, const void *field)
{
    return *(void *const *)sl_field_address(instance, field);
}

/* ----------------------------------------------------------------- writing */

static void *sl_field_slot(void *instance, const void *field)
{
    return (uint8_t *)instance + ((const SlFieldInfo *)field)->offset;
}

/*
 * Narrowed to the field's own width, so a value too large for it wraps there
 * rather than writing over the field beside it. That is C's rule for an
 * assignment of the same shape, and the alternative -- writing eight bytes
 * whatever the field is -- would corrupt the object silently.
 */
void sl_write_integer(void *instance, const void *field, int64_t value)
{
    void *address = sl_field_slot(instance, field);

    switch (((const SlFieldInfo *)field)->kind) {
        case SL_KIND_SBYTE:  *(int8_t   *)address = (int8_t)value;   break;
        case SL_KIND_SHORT:  *(int16_t  *)address = (int16_t)value;  break;
        case SL_KIND_INT:    *(int32_t  *)address = (int32_t)value;  break;
        case SL_KIND_LONG:
        case SL_KIND_NINT:   *(int64_t  *)address = value;           break;
        case SL_KIND_CHAR:
        case SL_KIND_BYTE:   *(uint8_t  *)address = (uint8_t)value;  break;
        case SL_KIND_CHAR16:
        case SL_KIND_USHORT: *(uint16_t *)address = (uint16_t)value; break;
        case SL_KIND_CHAR32:
        case SL_KIND_UINT:   *(uint32_t *)address = (uint32_t)value; break;
        case SL_KIND_ULONG:
        case SL_KIND_NUINT:  *(uint64_t *)address = (uint64_t)value; break;
        default:                                                     break;
    }
}

void sl_write_double(void *instance, const void *field, double value)
{
    void *address = sl_field_slot(instance, field);

    switch (((const SlFieldInfo *)field)->kind) {
        case SL_KIND_FLOAT:  *(float  *)address = (float)value; break;
        case SL_KIND_DOUBLE: *(double *)address = value;        break;
        default:                                                break;
    }
}

void sl_write_bool(void *instance, const void *field, _Bool value)
{
    if (((const SlFieldInfo *)field)->kind != SL_KIND_BOOL) { return; }
    *(_Bool *)sl_field_slot(instance, field) = value;
}

/*
 * Retain before release, for the reason every owning store in the emitter does
 * it: writing a field back to itself must not destroy the value on the way.
 */
void sl_write_reference(void *instance, const void *field, void *value)
{
    void **slot = (void **)sl_field_slot(instance, field);

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
    if (((const SlFieldInfo *)field)->kind != SL_KIND_STRING) { return; }

    void *text = sl_string_from_bytes((const uint8_t *)bytes, length);
    sl_write_reference(instance, field, text);
    sl_release(text);
}

/*
 * A zeroed instance, for a deserializer that has a type and no constructor to
 * call. Every reference field starts null, so what comes back is only safe to
 * hand out once the caller has filled the ones that may not be.
 */
void *sl_type_make(const void *type)
{
    return sl_alloc((const SlTypeInfo *)type);
}

/* ------------------------------------------------------ array elements */

uint32_t sl_field_element_kind(const void *field)
{
    return ((const SlFieldInfo *)field)->elementKind;
}

const void *sl_field_element_type(const void *field)
{
    return ((const SlFieldInfo *)field)->elementType;
}

size_t sl_field_element_size(const void *field)
{
    return ((const SlFieldInfo *)field)->elementSize;
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
        case SL_KIND_LONG:
        case SL_KIND_NINT:   return *(const int64_t  *)address;
        case SL_KIND_CHAR:
        case SL_KIND_BYTE:   return *(const uint8_t  *)address;
        case SL_KIND_CHAR16:
        case SL_KIND_USHORT: return *(const uint16_t *)address;
        case SL_KIND_CHAR32:
        case SL_KIND_UINT:   return *(const uint32_t *)address;
        case SL_KIND_ULONG:
        case SL_KIND_NUINT:  return (int64_t)*(const uint64_t *)address;
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

_Bool sl_read_at_bool(const void *address)
{
    return *(const _Bool *)address;
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
        case SL_KIND_LONG:
        case SL_KIND_NINT:   *(int64_t  *)address = value;           break;
        case SL_KIND_CHAR:
        case SL_KIND_BYTE:   *(uint8_t  *)address = (uint8_t)value;  break;
        case SL_KIND_CHAR16:
        case SL_KIND_USHORT: *(uint16_t *)address = (uint16_t)value; break;
        case SL_KIND_CHAR32:
        case SL_KIND_UINT:   *(uint32_t *)address = (uint32_t)value; break;
        case SL_KIND_ULONG:
        case SL_KIND_NUINT:  *(uint64_t *)address = (uint64_t)value; break;
        default:                                                     break;
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

/* Retain before release, as sl_write_reference does and for the same reason. */
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
    return ((const SlFieldInfo *)field)->flags;
}

size_t sl_type_property_count(const void *type)
{
    return ((const SlTypeInfo *)type)->propertyCount;
}

const void *sl_type_property(const void *type, size_t index)
{
    const SlTypeInfo *info = (const SlTypeInfo *)type;
    if (index >= info->propertyCount) sl_array_bounds_fail(index, info->propertyCount);
    return &info->properties[index];
}

const char *sl_property_name(const void *property)
{
    return ((const SlPropertyInfo *)property)->name;
}

uint32_t sl_property_kind(const void *property)
{
    return ((const SlPropertyInfo *)property)->kind;
}

const void *sl_property_type(const void *property)
{
    return ((const SlPropertyInfo *)property)->type;
}

_Bool sl_property_can_read(const void *property)
{
    return ((const SlPropertyInfo *)property)->getter != NULL;
}

_Bool sl_property_can_write(const void *property)
{
    return ((const SlPropertyInfo *)property)->setter != NULL;
}

size_t sl_property_attribute_count(const void *property)
{
    return ((const SlPropertyInfo *)property)->attributeCount;
}

const void *sl_property_attribute(const void *property, size_t index)
{
    const SlPropertyInfo *info = (const SlPropertyInfo *)property;
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
    const SlPropertyInfo *info = (const SlPropertyInfo *)property;
    const void *getter = info->getter;
    if (getter == NULL) return 0;

    switch (info->kind) {
        case SL_KIND_SBYTE:  return ((int8_t   (*)(void *))getter)(instance);
        case SL_KIND_SHORT:  return ((int16_t  (*)(void *))getter)(instance);
        case SL_KIND_INT:    return ((int32_t  (*)(void *))getter)(instance);
        case SL_KIND_LONG:
        case SL_KIND_NINT:   return ((int64_t  (*)(void *))getter)(instance);
        case SL_KIND_CHAR:
        case SL_KIND_BYTE:   return ((uint8_t  (*)(void *))getter)(instance);
        case SL_KIND_CHAR16:
        case SL_KIND_USHORT: return ((uint16_t (*)(void *))getter)(instance);
        case SL_KIND_CHAR32:
        case SL_KIND_UINT:   return ((uint32_t (*)(void *))getter)(instance);
        case SL_KIND_ULONG:
        case SL_KIND_NUINT:  return (int64_t)((uint64_t (*)(void *))getter)(instance);
        default:             return 0;
    }
}

double sl_property_get_double(void *instance, const void *property)
{
    const SlPropertyInfo *info = (const SlPropertyInfo *)property;
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
    const SlPropertyInfo *info = (const SlPropertyInfo *)property;
    if (info->getter == NULL || info->kind != SL_KIND_BOOL) return 0;

    return ((_Bool (*)(void *))info->getter)(instance);
}

/*
 * A String, a class, an interface or an array. The reference comes back
 * borrowed: the getter answered with the object the property holds and did not
 * add a count, so a caller keeping it must retain it.
 */
void *sl_property_get_reference(void *instance, const void *property)
{
    const SlPropertyInfo *info = (const SlPropertyInfo *)property;
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
    const SlPropertyInfo *info = (const SlPropertyInfo *)property;
    const void *setter = info->setter;
    if (setter == NULL) return;

    /* Narrowed to the property's own width, as sl_write_integer is. */
    switch (info->kind) {
        case SL_KIND_SBYTE:  ((void (*)(void *, int8_t  ))setter)(instance, (int8_t  )value); break;
        case SL_KIND_SHORT:  ((void (*)(void *, int16_t ))setter)(instance, (int16_t )value); break;
        case SL_KIND_INT:    ((void (*)(void *, int32_t ))setter)(instance, (int32_t )value); break;
        case SL_KIND_LONG:
        case SL_KIND_NINT:   ((void (*)(void *, int64_t ))setter)(instance, value);           break;
        case SL_KIND_CHAR:
        case SL_KIND_BYTE:   ((void (*)(void *, uint8_t ))setter)(instance, (uint8_t )value); break;
        case SL_KIND_CHAR16:
        case SL_KIND_USHORT: ((void (*)(void *, uint16_t))setter)(instance, (uint16_t)value); break;
        case SL_KIND_CHAR32:
        case SL_KIND_UINT:   ((void (*)(void *, uint32_t))setter)(instance, (uint32_t)value); break;
        case SL_KIND_ULONG:
        case SL_KIND_NUINT:  ((void (*)(void *, uint64_t))setter)(instance, (uint64_t)value); break;
        default:                                                                              break;
    }
}

void sl_property_set_double(void *instance, const void *property, double value)
{
    const SlPropertyInfo *info = (const SlPropertyInfo *)property;
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
    const SlPropertyInfo *info = (const SlPropertyInfo *)property;
    if (info->setter == NULL || info->kind != SL_KIND_BOOL) return;

    ((void (*)(void *, _Bool))info->setter)(instance, value);
}

/*
 * Retained before the call, because a setter takes a reference of its own --
 * it releases what the property held and keeps what it was given. Without this
 * the caller's reference would be the one consumed.
 */
void sl_property_set_reference(void *instance, const void *property, void *value)
{
    const SlPropertyInfo *info = (const SlPropertyInfo *)property;
    const void *setter = info->setter;
    if (setter == NULL) return;

    switch (info->kind) {
        case SL_KIND_STRING:
        case SL_KIND_CLASS:
        case SL_KIND_INTERFACE:
        case SL_KIND_ARRAY:
            sl_retain(value);
            ((void (*)(void *, void *))setter)(instance, value);
            break;

        default:
            break;
    }
}
