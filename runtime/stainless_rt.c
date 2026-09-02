/*
 * The Stainless runtime.
 *
 * This is the entire thing. There is no collector, no scheduler, no metadata
 * tables and no startup hook -- just reference counting over a 24-byte object
 * header, which is why a Stainless binary starts as fast as a C one.
 *
 * See docs/abi.md for the header layout this file and the compiler agree on.
 */

#include <stdlib.h>
#include <stddef.h>

typedef struct SlTypeInfo {
    size_t       size;          /* header + fields, in bytes            */
    void       (*destroy)(void *);
    const char  *name;
} SlTypeInfo;

typedef struct SlObject {
    size_t              strong;
    size_t              weak;
    const SlTypeInfo   *type;
} SlObject;

/*
 * A live object holds one weak reference on itself. That is what lets a weak
 * reference keep the *allocation* alive after the object is destroyed, so
 * sl_weak_load can safely look at the strong count and report the truth
 * instead of reading freed memory.
 */
void *sl_alloc(const SlTypeInfo *type)
{
    SlObject *object = (SlObject *)calloc(1, type->size);
    if (object == NULL) abort();

    object->strong = 1;
    object->weak   = 1;
    object->type   = type;
    return object;
}

void sl_retain(void *pointer)
{
    if (pointer != NULL) ((SlObject *)pointer)->strong += 1;
}

void sl_weak_retain(void *pointer)
{
    if (pointer != NULL) ((SlObject *)pointer)->weak += 1;
}

void sl_weak_release(void *pointer)
{
    SlObject *object = (SlObject *)pointer;
    if (object == NULL) return;
    if (--object->weak == 0) free(object);
}

void sl_release(void *pointer)
{
    SlObject *object = (SlObject *)pointer;
    if (object == NULL) return;

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
    if (object == NULL || object->strong == 0) return NULL;

    object->strong += 1;
    return object;
}
