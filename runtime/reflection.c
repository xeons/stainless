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
