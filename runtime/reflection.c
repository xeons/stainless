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
