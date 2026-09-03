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
 *
 * The counts are atomic. They were not, and the rule above them was that
 * nothing two threads can both reach is ever retained -- which Mutex<T> broke:
 * a lock protects what it guards and not the count of what it guards, so a
 * reference handed out of a lock is retained by one thread while another
 * releases it, an update is lost, and the object is freed while still in use.
 *
 * Making only [Shared] types atomic would not have closed it. Mutex<List<T>>
 * guards a List, and a List is not [Shared]; what would have to be atomic is
 * everything reachable from a [Shared] type, which is most of the heap in any
 * program where the question arises. It could also be laundered through the
 * raw pointer a job takes its argument as.
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

void sl_fail(const char *message)
{
    fputs("stainless: ", stderr);
    fputs(message, stderr);
    fputc('\n', stderr);
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

void sl_divide_overflow(void)
{
    sl_fail("integer division overflows: the smallest value divided by -1");
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

/* True for an object in static storage, which has no reference traffic at all. */
static int sl_is_immortal(const SlObject *object)
{
    return __atomic_load_n(&object->strong, __ATOMIC_RELAXED) == SL_IMMORTAL;
}

void sl_retain(void *pointer)
{
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

    if (__atomic_fetch_sub(&object->weak, 1, __ATOMIC_ACQ_REL) == 1) free(object);
}

void sl_release(void *pointer)
{
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
