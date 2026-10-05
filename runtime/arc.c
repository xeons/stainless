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
 * Reference counting.
 *
 * A live object holds one weak reference on itself. That is what lets a weak
 * reference keep the *allocation* alive after the object is destroyed, so
 * sl_weak_load can safely read the strong count instead of reading freed
 * memory.
 *
 * The counts are atomic, and every count is: a lock protects what it guards
 * and not the count of what it guards, so a reference handed out of a lock is
 * retained by one thread while another releases it. Counting only the types
 * marked [Shared] would not reach that -- Mutex<List<T>> guards a List, and a
 * List is not [Shared].
 *
 * A retain is relaxed: the caller already holds a reference, so nothing is
 * being published by incrementing. A release is acq_rel, so everything written
 * through the last reference happens-before the destructor that reads it.
 *
 * It costs about 5.7ns per retain/release pair over the plain version. Most of
 * that is traffic the compiler should not be emitting at all: retain/release
 * around a borrow is redundant, and the +0/+1 pass that removes it matters
 * considerably more now than it did.
 */

#include "stainless.h"

#include <stdio.h>
#include <stdlib.h>

/*
 * Reports why the program is stopping, and stops it.
 *
 * Everything the program has already written is flushed first, and that is not
 * a nicety: `abort` does not flush, so a buffered stdout is discarded, and
 * what a reader saw was the message and nothing else -- not the output that
 * led up to it, not even a line printed immediately before. The one moment a
 * program's own account of itself is worth most is the moment it stops, and it
 * was the one moment that threw it away.
 *
 * fflush(NULL) rather than stdout, because a log the program was writing is
 * evidence on the same terms. Then the message, then stderr again, so the
 * explanation lands after the output it explains.
 */
void sl_fail(const char *message)
{
    fflush(NULL);

    fputs("stainless: ", stderr);
    fputs(message, stderr);
    fputc('\n', stderr);
    fflush(stderr);

    abort();
}

/*
 * The two integer divisions LLVM calls undefined. Left unguarded the optimiser
 * is entitled to fold the whole expression to anything at all, which is how a
 * division by zero comes to return a number and let the program carry on.
 */
void sl_divide_by_zero(void)
{
    sl_fail("integer division by zero");
}

/*
 * A switch expression that names every member of an enum needs no `_`, and a
 * value that is none of them is the one it has no arm for.
 */
void sl_switch_unmatched(const char *type)
{
    char message[256];
    snprintf(message, sizeof message,
             "a switch expression over '%s' was given a value that is none of its members",
             type);
    sl_fail(message);
}

/*
 * A class is its own type and every one it derives from. The chain is short by
 * construction -- single inheritance, and nothing generated -- so this is a walk
 * rather than a table of ancestors, and it costs a compare per level.
 */
int sl_is_instance(const void *object, const SlTypeInfo *type)
{
    const SlObject *header = (const SlObject *)object;
    const SlTypeInfo *current;

    if (object == NULL || type == NULL) return 0;

    for (current = header->type; current != NULL; current = current->base)
        if (current == type) return 1;

    return 0;
}

int sl_implements(const void *object, size_t interfaceId)
{
    const SlObject *header = (const SlObject *)object;

    if (object == NULL) return 0;
    if (header->type == NULL || header->type->interfaces == NULL) return 0;

    return header->type->interfaces[interfaceId] != NULL;
}

void sl_slot_empty(const char *slot)
{
    fflush(NULL);

    fprintf(stderr, "stainless: a %s was read while it was empty\n", slot);
    fflush(stderr);

    abort();
}

void sl_foreign_null(const char *function, const char *type)
{
    fflush(NULL);

    fprintf(stderr, "stainless: '%s' returned null, and a %s is never null\n", function, type);
    fflush(stderr);

    abort();
}

void sl_objc_nil(const char *message, const char *type)
{
    fflush(NULL);

    fprintf(stderr, "stainless: '%s' answered nil, and a %s is never nil\n", message, type);
    fflush(stderr);

    abort();
}

void sl_objc_unanswered(const char *message)
{
    fflush(NULL);

    fprintf(stderr, "stainless: '%s' is optional, and this object does not answer it\n", message);
    fflush(stderr);

    abort();
}

void sl_objc_nil_argument(const char *message, const char *parameter, const char *type)
{
    fflush(NULL);

    fprintf(stderr, "stainless: '%s' was sent nil for '%s', and a %s is never nil\n",
            message, parameter, type);
    fflush(stderr);

    abort();
}

/*
 * A weak reference to an Objective-C object. A Stainless weak reference is a
 * count in the object's header, which an Objective-C object has not got, so
 * it is a box instead: a counted Stainless object holding one __weak slot,
 * which the Objective-C runtime clears when the object goes. Copying the
 * reference shares the box, and the last release of it destroys the slot.
 *
 * libobjc is looked up rather than linked, as the autorelease pools are, so
 * the runtime asks nothing of it; a program that makes a box sends messages,
 * and so has it loaded.
 */
typedef struct SlObjCWeakBox {
    SlObject header;
    void    *slot;
} SlObjCWeakBox;

#if defined(__APPLE__)
#  include <dlfcn.h>

static void *(*objc_init_weak)(void **, void *);
static void *(*objc_load_weak_retained)(void **);
static void (*objc_destroy_weak)(void **);

static void sl_objc_weak_resolve(void)
{
    if (objc_destroy_weak != NULL) return;
    objc_init_weak = (void *(*)(void **, void *))dlsym(RTLD_DEFAULT, "objc_initWeak");
    objc_load_weak_retained = (void *(*)(void **))dlsym(RTLD_DEFAULT, "objc_loadWeakRetained");
    __atomic_store_n(&objc_destroy_weak,
        (void (*)(void **))dlsym(RTLD_DEFAULT, "objc_destroyWeak"), __ATOMIC_RELEASE);
}

static void sl_objc_weak_box_destroy(void *pointer)
{
    objc_destroy_weak(&((SlObjCWeakBox *)pointer)->slot);
}

static const SlTypeInfo sl_objc_weak_box_type = {
    .size = sizeof(SlObjCWeakBox), .destroy = sl_objc_weak_box_destroy, .name = "ObjCWeakReference",
};

/* A +1 box holding `object` weakly, or NULL for a nil object. */
void *sl_objc_weak_new(void *object)
{
    if (object == NULL) return NULL;

    sl_objc_weak_resolve();
    SlObjCWeakBox *box = (SlObjCWeakBox *)sl_alloc(&sl_objc_weak_box_type);
    objc_init_weak(&box->slot, object);
    return box;
}

/* A +1 reference to the object, or NULL once it has gone. */
void *sl_objc_weak_load(void *pointer)
{
    if (pointer == NULL) return NULL;
    return objc_load_weak_retained(&((SlObjCWeakBox *)pointer)->slot);
}
#else
void *sl_objc_weak_new(void *object)
{
    (void)object;
    sl_fail("an Objective-C weak reference exists only on Apple's systems");
}

void *sl_objc_weak_load(void *pointer)
{
    (void)pointer;
    sl_fail("an Objective-C weak reference exists only on Apple's systems");
}
#endif

/* A constructor's superclass init answered with something other than the
   object alloc made, which the constructor holds as `this`. */
void sl_objc_init_replaced(const char *message, const void *answered)
{
    fflush(NULL);

    if (answered == NULL)
        fprintf(stderr, "stainless: '%s' answered nil, so the object could not be made\n", message);
    else
        fprintf(stderr, "stainless: '%s' answered with another object, and a constructor "
                        "goes on with the one it was given\n", message);
    fflush(stderr);

    abort();
}

/* Called from the landing pad of a method a class defined in Stainless
   answers. An exception that got this far unwound through Stainless frames
   without releasing what they held, so nothing after it can be trusted.
   `reason` is an Objective-C exception's own account, or null for an
   exception that is not one or gave none. */
void sl_objc_exception(const char *message, const char *reason)
{
    fflush(NULL);

    fprintf(stderr, "stainless: an exception reached '%s'\n", message);
    if (reason != NULL)
        fprintf(stderr, "stainless: it said: %s\n", reason);
    fflush(stderr);

    abort();
}

/* The class name is asked of the Objective-C runtime by the program, so the
   runtime here needs nothing of libobjc. */
void sl_objc_cast_failed(const char *actual, const char *wanted)
{
    fflush(NULL);

    fprintf(stderr, "stainless: cast failed: a %s is not a %s\n", actual, wanted);
    fflush(stderr);

    abort();
}

/* A late field read before anything gave it a value. */
void sl_late_unset(const char *field)
{
    fflush(NULL);

    fprintf(stderr, "stainless: '%s' was read before it was given a value\n", field);
    fflush(stderr);

    abort();
}

void sl_cast_failed(const void *object, const char *wanted)
{
    const SlObject *header = (const SlObject *)object;
    const char *actual = "null";

    if (object != NULL && header->type != NULL && header->type->name != NULL)
        actual = header->type->name;

    /* The program's own output first, for the reason sl_fail gives. */
    fflush(NULL);

    fprintf(stderr, "stainless: cast failed: a %s is not a %s\n", actual, wanted);
    fflush(stderr);

    abort();
}

void sl_divide_overflow(void)
{
    sl_fail("integer division overflows: the smallest value divided by -1");
}

/*
 * Reached only from inside `checked`. Addition, subtraction and multiplication
 * wrap by default and that is defined, so this is what the program asked for
 * rather than something it fell into.
 */
void sl_arithmetic_overflow(void)
{
    sl_fail("checked arithmetic overflowed");
}

/*
 * Runs `hook` when the program ends, however it ends.
 *
 * atexit rather than a call after main returns, because a program that calls
 * exit() has still ended and its statics still hold what they hold. The
 * ordering that matters is with the allocation tracker's own report, and it
 * comes out right for free: the tracker registers before main and this
 * registers from the static initializer, so the C runtime -- which runs these
 * in reverse -- tears the statics down first and reports afterwards.
 */
void sl_run_at_exit(void (*hook)(void))
{
    if (hook != NULL) atexit(hook);
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

/*
 * Zeroed storage of `size` bytes whose byte `at` is on an `alignment`
 * boundary: an object's start, or an array's first element. malloc's own
 * pointer is kept in the word before the object, for sl_free_object.
 */
void *sl_alloc_aligned_at(size_t size, size_t alignment, size_t at)
{
    size_t extra = alignment + sizeof(void *);
    if (size > SIZE_MAX - extra) sl_fail("out of memory");

    char *raw = (char *)calloc(1, size + extra);
    if (raw == NULL) sl_fail("out of memory");

    uintptr_t first = (uintptr_t)raw + sizeof(void *) + at;
    uintptr_t aligned = (first + alignment - 1) & ~(uintptr_t)(alignment - 1);
    char *object = (char *)(aligned - at);
    ((void **)object)[-1] = raw;
    return object;
}

/* Frees what sl_alloc or sl_array_alloc made, however it was placed. */
static void sl_free_object(SlObject *object)
{
    if (object->type != NULL && object->type->alignment > SL_MALLOC_ALIGNMENT)
        free(((void **)object)[-1]);
    else
        free(object);
}

void *sl_alloc(const SlTypeInfo *type)
{
    SlObject *object = type->alignment > SL_MALLOC_ALIGNMENT
        ? (SlObject *)sl_alloc_aligned_at(type->size, type->alignment, 0)
        : (SlObject *)calloc(1, type->size);
    if (object == NULL) sl_fail("out of memory");

    sl_object_init(object, type);
    SL_LEAK_RECORD(object, type->size);
    return object;
}

/* True for an object in static storage, which has no reference traffic at all. */
static int sl_is_immortal(const SlObject *object)
{
    return __atomic_load_n(&object->strong, __ATOMIC_RELAXED) == SL_IMMORTAL;
}

void sl_retain(void *pointer)
{
    SL_LEAK_RETAIN();

    SlObject *object = (SlObject *)pointer;
    if (object == NULL || sl_is_immortal(object)) return;

    __atomic_fetch_add(&object->strong, 1, __ATOMIC_RELAXED);
}

void sl_weak_retain(void *pointer)
{
    SlObject *object = (SlObject *)pointer;
    if (object == NULL || sl_is_immortal(object)) return;

    __atomic_fetch_add(&object->weak, 1, __ATOMIC_RELAXED);
}

void sl_weak_release(void *pointer)
{
    SlObject *object = (SlObject *)pointer;
    if (object == NULL || sl_is_immortal(object)) return;

    if (__atomic_fetch_sub(&object->weak, 1, __ATOMIC_ACQ_REL) == 1) {
        SL_LEAK_FORGET(object);
        sl_free_object(object);
    }
}

void sl_release(void *pointer)
{
    SL_LEAK_RELEASE();

    SlObject *object = (SlObject *)pointer;
    if (object == NULL || sl_is_immortal(object)) return;

    if (__atomic_fetch_sub(&object->strong, 1, __ATOMIC_ACQ_REL) == 1) {
        if (object->type != NULL && object->type->destroy != NULL)
            object->type->destroy(object);
        sl_weak_release(object);        /* drops the object's own weak reference */
    }
}

/*
 * Returns a +1 strong reference, or NULL if the object is already gone.
 *
 * The count cannot be read and then incremented: another thread may drop it to
 * zero in between, and the reference handed back would name an object already
 * destroyed. The compare-exchange makes the two one step, and retries when
 * somebody else got there first.
 */
void *sl_weak_load(void *pointer)
{
    SlObject *object = (SlObject *)pointer;
    if (object == NULL) return NULL;

    size_t current = __atomic_load_n(&object->strong, __ATOMIC_RELAXED);

    for (;;) {
        if (current == SL_IMMORTAL) return object;
        if (current == 0) return NULL;

        if (__atomic_compare_exchange_n(&object->strong, &current, current + 1,
                                        1, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED))
            return object;
    }
}

/*
 * A subscription that does not keep its subscriber alive.
 *
 * An object subscribing itself to an event of something it owns -- a form to
 * its own button -- would otherwise be a cycle: the form holds the button, the
 * button's event holds the closure, the closure holds the form. The event holds
 * one of these instead, as the receiver of a closure whose function is a thunk
 * the compiler writes per event: the thunk loads the subscriber through the
 * cell, calls the method it names if the subscriber is alive, and does nothing
 * if it is not.
 *
 * The target is held weakly, so its memory outlives it for as long as the cell
 * does. That is what lets `sl_weak_cell_matches` compare addresses without the
 * address ever naming something else.
 */
typedef struct SlWeakCell {
    SlObject header;
    void    *function;
    void    *target;
} SlWeakCell;

static void sl_weak_cell_destroy(void *pointer)
{
    SlWeakCell *cell = (SlWeakCell *)pointer;
    sl_weak_release(cell->target);
}

static const SlTypeInfo sl_weak_cell_type = {
    .size = sizeof(SlWeakCell), .destroy = sl_weak_cell_destroy, .name = "WeakSubscription",
};

void *sl_weak_cell_new(void *function, void *target)
{
    SlWeakCell *cell = (SlWeakCell *)sl_alloc(&sl_weak_cell_type);
    cell->function = function;
    cell->target = target;
    sl_weak_retain(target);
    return cell;
}

/* A +1 reference to the subscriber, or NULL once it has gone. */
void *sl_weak_cell_load(void *pointer, void **function)
{
    SlWeakCell *cell = (SlWeakCell *)pointer;
    *function = cell->function;
    return sl_weak_load(cell->target);
}

int32_t sl_weak_cell_matches(void *pointer, void *function, void *target)
{
    SlWeakCell *cell = (SlWeakCell *)pointer;
    return cell->function == function && cell->target == target;
}

int32_t sl_weak_cell_is_dead(void *pointer)
{
    SlWeakCell *cell = (SlWeakCell *)pointer;
    if (cell->target == NULL) return 0;

    SlObject *target = (SlObject *)cell->target;
    return __atomic_load_n(&target->strong, __ATOMIC_RELAXED) == 0;
}
