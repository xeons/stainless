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
 * COM, as a calling convention rather than as a Windows service.
 *
 * A COM interface reference points at a vtable pointer, and the first three
 * slots of every such vtable are QueryInterface, AddRef and Release. That is
 * the whole of the binary contract, and none of it is Windows-specific: it is
 * a pointer, an array of function pointers, and the platform C calling
 * convention. vkd3d-proton and DXVK run D3D12's COM interfaces on Linux
 * without any of Windows present, which is the same observation.
 *
 * So this file has no #ifdef _WIN32 in it and must not grow one. What is
 * Windows-only is activation -- CoCreateInstance, the registry, apartments,
 * marshalling -- and none of that is here. See docs/com.md.
 *
 * These four exist so the compiler emits one call rather than a null test and
 * two loads at every place ARC touches a COM reference.
 */

#include "stainless.h"

#include <stdio.h>
#include <string.h>

/* ------------------------------------------------------------------- ARC */

void sl_com_retain(void *pointer)
{
    SlComObject *object = (SlComObject *)pointer;
    if (object == NULL) return;

    object->vtable->AddRef(object);
}

void sl_com_release(void *pointer)
{
    SlComObject *object = (SlComObject *)pointer;
    if (object == NULL) return;

    object->vtable->Release(object);
}

/* --------------------------------------------------------- QueryInterface */

/*
 * The reference for `iid`, or NULL.
 *
 * QueryInterface adds a reference on success, so what comes back is owned and
 * the caller releases it -- which is what the compiler's cast emits.
 */
void *sl_com_query(void *pointer, const SlGuid *iid)
{
    SlComObject *object = (SlComObject *)pointer;
    void *result = NULL;

    if (object == NULL) return NULL;
    if (object->vtable->QueryInterface(object, iid, &result) < 0) return NULL;

    return result;
}

/*
 * Whether the object also answers to `iid`.
 *
 * A successful QueryInterface has added a reference that nothing is going to
 * keep, so this drops it again: `x is IFoo` yields a bool and holds nothing.
 */
int sl_com_is(void *pointer, const SlGuid *iid)
{
    void *found = sl_com_query(pointer, iid);
    if (found == NULL) return 0;

    sl_com_release(found);
    return 1;
}

/*
 * The failure of a checked cast.
 *
 * Distinct from sl_cast_failed, whose message is about a class hierarchy the
 * compiler could see. Here the object decides, at run time, in code that may
 * not be ours.
 */
void sl_com_cast_failed(const char *from, const char *to)
{
    char message[256];
    snprintf(message, sizeof(message),
             "cast failed: the object behind this '%s' does not answer "
             "QueryInterface for '%s'", from, to);
    sl_fail(message);
}

/* ------------------------------------------------------------- utilities */

int sl_guid_equals(const SlGuid *left, const SlGuid *right)
{
    return memcmp(left, right, sizeof(SlGuid)) == 0;
}

/*
 * The IUnknown implementation shared by every `com class`.
 *
 * A com class is an ordinary Stainless object -- header, fields, TypeInfo, a
 * destructor -- with one tear-off per interface it presents laid out after the
 * fields. A tear-off is a vtable pointer followed by its own distance back to
 * the object, so a call arriving through any interface can find the header by
 * subtracting, which is what the three below do.
 */

static SlObject *sl_com_owner(void *self)
{
    SlComTearOff *tearOff = (SlComTearOff *)self;
    return (SlObject *)((uint8_t *)self - tearOff->ownerOffset);
}

uint32_t sl_com_object_add_ref(void *self)
{
    SlObject *object = sl_com_owner(self);
    sl_retain(object);
    return (uint32_t)object->strong;
}

uint32_t sl_com_object_release(void *self)
{
    SlObject *object = sl_com_owner(self);

    /*
     * The count after the drop, which is what Release returns -- read before
     * releasing, because after it the object may be gone and reading its
     * header would be a use after free.
     */
    uint32_t remaining = (uint32_t)object->strong - 1;
    sl_release(object);
    return remaining;
}

/*
 * QueryInterface over the object's own tear-offs.
 *
 * A linear scan: QueryInterface is called when a reference changes hands and
 * not in a loop, and a class presenting more than a handful of interfaces is
 * rare enough that a table would cost more than it saves.
 */
int32_t sl_com_object_query(void *self, const SlGuid *iid, void **result)
{
    SlObject *object;
    const SlComLayout *layout;
    size_t i;

    if (result == NULL) return SL_COM_E_POINTER;
    *result = NULL;
    if (iid == NULL) return SL_COM_E_POINTER;

    object = sl_com_owner(self);
    layout = (const SlComLayout *)object->type->com;
    if (layout == NULL) return SL_COM_E_NOINTERFACE;

    for (i = 0; i < layout->count; i++) {
        if (!sl_guid_equals(iid, layout->entries[i].iid)) continue;

        *result = (uint8_t *)object + layout->entries[i].offset;
        sl_retain(object);
        return SL_COM_S_OK;
    }

    /*
     * IUnknown itself, which every COM object answers to and which no
     * interface list mentions. The first tear-off is the canonical one: COM
     * requires that QueryInterface for IUnknown return the same pointer every
     * time, so that two references can be compared for object identity.
     */
    if (sl_guid_equals(iid, &sl_iid_unknown)) {
        *result = (uint8_t *)object + layout->entries[0].offset;
        sl_retain(object);
        return SL_COM_S_OK;
    }

    return SL_COM_E_NOINTERFACE;
}

const SlGuid sl_iid_unknown = {
    0x00000000, 0x0000, 0x0000,
    { 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 }
};
