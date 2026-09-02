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
