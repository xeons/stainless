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
 * Reference counting.
 *
 * A live object holds one weak reference on itself. That is what lets a weak
 * reference keep the *allocation* alive after the object is destroyed, so
 * sl_weak_load can safely read the strong count instead of reading freed
 * memory.
 */

#include "stainless.h"

#include <stdio.h>
#include <stdlib.h>

void sl_fail(const char *message)
{
    fputs("stainless: ", stderr);
    fputs(message, stderr);
    fputc('\n', stderr);
    abort();
}

void sl_object_init(void *pointer, const SlTypeInfo *type)
{
    SlObject *object = (SlObject *)pointer;
    object->strong = 1;
    object->weak   = 1;
    object->type   = type;
}

void sl_make_immortal(void *pointer)
{
    SlObject *object = (SlObject *)pointer;
    if (object == NULL) return;

    /*
     * Already immortal is the common case, not an edge one: a string literal
     * lives in read-only storage, so storing the marker again would fault
     * rather than be harmless.
     */
    if (object->strong == SL_IMMORTAL) return;

    object->strong = SL_IMMORTAL;
}

void *sl_alloc(const SlTypeInfo *type)
{
    SlObject *object = (SlObject *)calloc(1, type->size);
    if (object == NULL) sl_fail("out of memory");

    sl_object_init(object, type);
    return object;
}

void sl_retain(void *pointer)
{
    SlObject *object = (SlObject *)pointer;
    if (object == NULL || object->strong == SL_IMMORTAL) return;
    object->strong += 1;
}

void sl_weak_retain(void *pointer)
{
    SlObject *object = (SlObject *)pointer;
    if (object == NULL || object->strong == SL_IMMORTAL) return;
    object->weak += 1;
}

void sl_weak_release(void *pointer)
{
    SlObject *object = (SlObject *)pointer;
    if (object == NULL || object->strong == SL_IMMORTAL) return;
    if (--object->weak == 0) free(object);
}

void sl_release(void *pointer)
{
    SlObject *object = (SlObject *)pointer;
    if (object == NULL || object->strong == SL_IMMORTAL) return;

    if (--object->strong == 0) {
        if (object->type != NULL && object->type->destroy != NULL)
            object->type->destroy(object);
        sl_weak_release(object);        /* drops the object's own weak reference */
    }
}

/* Returns a +1 strong reference, or NULL if the object is already gone. */
void *sl_weak_load(void *pointer)
{
    SlObject *object = (SlObject *)pointer;
    if (object == NULL) return NULL;
    if (object->strong == SL_IMMORTAL) return object;
    if (object->strong == 0) return NULL;

    object->strong += 1;
    return object;
}
