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
#include <stdlib.h>
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
 *
 * They go in a vtable, so they carry SL_COM_METHOD: on x86 that is __stdcall,
 * and a slot whose callee did not pop the arguments would unbalance the stack
 * of whatever called it. It is spelled on the architecture rather than on the
 * system, which is why it is not the #ifdef this file must not grow.
 */

static SlObject *sl_com_owner(void *self)
{
    SlComTearOff *tearOff = (SlComTearOff *)self;
    return (SlObject *)((uint8_t *)self - tearOff->ownerOffset);
}

uint32_t SL_COM_METHOD sl_com_object_add_ref(void *self)
{
    SlObject *object = sl_com_owner(self);
    sl_retain(object);
    return (uint32_t)object->strong;
}

uint32_t SL_COM_METHOD sl_com_object_release(void *self)
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
int32_t SL_COM_METHOD sl_com_object_query(void *self, const SlGuid *iid, void **result)
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

/* IClassFactory, fixed since 1993 like IUnknown's. */
const SlGuid sl_iid_class_factory = {
    0x00000001, 0x0000, 0x0000,
    { 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 }
};

/* ------------------------------------------------------------ activation */

/*
 * A class factory over one entry of the compiler's table.
 *
 * IClassFactory is IUnknown plus CreateInstance and LockServer, so its vtable
 * is five slots and the first three are the usual ones. This object is not a
 * Stainless object -- it has no header, no TypeInfo and no destructor --
 * because nothing in the language ever holds it: it exists between
 * DllGetClassObject and the caller's Release, and the caller is C++.
 */
typedef struct SlClassFactory {
    const void        *vtable;
    int32_t            refs;
    const SlComFactory *entry;
} SlClassFactory;

static int32_t SL_COM_METHOD factory_query(void *self, const SlGuid *iid, void **result)
{
    SlClassFactory *factory = (SlClassFactory *)self;

    if (result == NULL) return SL_COM_E_POINTER;
    *result = NULL;
    if (iid == NULL) return SL_COM_E_POINTER;

    if (!sl_guid_equals(iid, &sl_iid_unknown) &&
        !sl_guid_equals(iid, &sl_iid_class_factory))
        return SL_COM_E_NOINTERFACE;

    factory->refs++;
    *result = factory;
    return SL_COM_S_OK;
}

static uint32_t SL_COM_METHOD factory_add_ref(void *self)
{
    SlClassFactory *factory = (SlClassFactory *)self;
    return (uint32_t)++factory->refs;
}

static uint32_t SL_COM_METHOD factory_release(void *self)
{
    SlClassFactory *factory = (SlClassFactory *)self;
    int32_t remaining = --factory->refs;

    if (remaining == 0) free(factory);
    return (uint32_t)remaining;
}

/*
 * Make one, and hand back the interface asked for rather than the one made.
 *
 * create() returns the object's first tear-off with a +1 on it. That is an
 * IUnknown, and the caller may have asked for something else, so the +1 is
 * spent on a QueryInterface and released either way -- which is also what
 * turns "this class does not present that interface" into E_NOINTERFACE
 * rather than a wrong pointer.
 */
static int32_t SL_COM_METHOD factory_create(
    void *self, void *outer, const SlGuid *iid, void **result)
{
    SlClassFactory *factory = (SlClassFactory *)self;
    void *made;
    int32_t answer;

    if (result == NULL) return SL_COM_E_POINTER;
    *result = NULL;
    if (iid == NULL) return SL_COM_E_POINTER;

    /* Aggregation would need the object to delegate IUnknown to an outer one,
       and a com class's IUnknown is the compiler's. Refused rather than
       half-supported. */
    if (outer != NULL) return SL_COM_CLASS_E_NOAGGREGATION;

    made = factory->entry->create();
    if (made == NULL) return SL_COM_E_OUTOFMEMORY;

    answer = ((SlComObject *)made)->vtable->QueryInterface(made, iid, result);
    sl_com_release(made);
    return answer;
}

/*
 * LockServer, which this server does not need: it never unloads. Accepted
 * rather than refused, because a host is entitled to call it and a failure
 * here reads as a broken factory.
 */
static int32_t SL_COM_METHOD factory_lock(void *self, int32_t lock)
{
    (void)self;
    (void)lock;
    return SL_COM_S_OK;
}

static const void *sl_class_factory_vtable[5] = {
    (const void *)factory_query,
    (const void *)factory_add_ref,
    (const void *)factory_release,
    (const void *)factory_create,
    (const void *)factory_lock,
};

int32_t sl_com_get_class_object(
    const SlComFactoryTable *table,
    const SlGuid *clsid, const SlGuid *iid, void **result)
{
    size_t i;

    if (result == NULL) return SL_COM_E_POINTER;
    *result = NULL;
    if (clsid == NULL || iid == NULL) return SL_COM_E_INVALIDARG;
    if (table == NULL) return SL_COM_CLASS_E_CLASSNOTAVAILABLE;

    for (i = 0; i < table->count; i++) {
        SlClassFactory *factory;

        if (!sl_guid_equals(clsid, table->entries[i].clsid)) continue;

        factory = (SlClassFactory *)malloc(sizeof(SlClassFactory));
        if (factory == NULL) return SL_COM_E_OUTOFMEMORY;

        factory->vtable = sl_class_factory_vtable;
        factory->refs = 1;
        factory->entry = &table->entries[i];

        /* Through QueryInterface rather than straight out, so asking for
           something this factory is not gets E_NOINTERFACE and no leak. */
        {
            int32_t answer = factory_query(factory, iid, result);
            factory_release(factory);
            return answer;
        }
    }

    return SL_COM_CLASS_E_CLASSNOTAVAILABLE;
}

int32_t sl_com_can_unload_now(void)
{
    return SL_COM_S_FALSE;
}
