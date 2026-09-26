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
 * Array storage.
 *
 * An array is an ordinary reference counted object whose elements live inline,
 * after a length -- the same shape String uses for its bytes. The element type
 * is deliberately not recorded here: the compiler emits one TypeInfo per array
 * type, and its destroy hook already knows whether the elements need releasing
 * and how to walk them.
 */

#include "stainless.h"

#include <stdio.h>
#include <stdlib.h>

void *sl_array_alloc(const SlTypeInfo *type, size_t length, size_t elementSize)
{
    /* Guard the multiply: a huge length must fail cleanly rather than wrap. */
    if (elementSize != 0 && length > (SIZE_MAX - sizeof(SlArray)) / elementSize)
        sl_fail("array is too large to allocate");

    SlArray *array = (SlArray *)calloc(1, sizeof(SlArray) + length * elementSize);
    if (array == NULL) sl_fail("out of memory");

    sl_object_init(array, type);
    SL_LEAK_RECORD(array, sizeof(SlArray) + length * elementSize);
    array->length = length;
    return array;
}

/*
 * The end of an array the compiler placed in a caller's frame, for the
 * elements of a `params T[:]` call. Its header was initialised as one fresh
 * from sl_array_alloc, so a count above one is a reference that would outlive
 * the frame: the program stops rather than keep it.
 */
void sl_array_end_on_stack(void *pointer)
{
    SlObject *object = (SlObject *)pointer;

    if (object->strong != 1 || object->weak != 1)
        sl_fail("a 'params' slice was kept past the call it was made for; its elements "
                "live in the caller's frame. Copy them into an array to keep them");

    if (object->type != NULL && object->type->destroy != NULL)
        object->type->destroy(object);
}

size_t sl_array_length(void *pointer)
{
    return ((SlArray *)pointer)->length;
}

void sl_array_bounds_fail(size_t index, size_t length)
{
    char buffer[128];
    snprintf(buffer, sizeof buffer,
             "index %zu is outside the bounds of an array of length %zu", index, length);
    sl_fail(buffer);
}

/*
 * An index counted from the end says so: `^4` of three elements is reported as
 * that, rather than as the word the subtraction wrapped to.
 */
void sl_index_bounds_fail(size_t value, int from_end, size_t length)
{
    char buffer[128];

    if (!from_end)
        sl_array_bounds_fail(value, length);

    snprintf(buffer, sizeof buffer,
             "^%zu is outside the bounds of an array of length %zu", value, length);
    sl_fail(buffer);
}

/*
 * A slice's two bounds are wrong in two different ways, and saying which one it
 * was costs a comparison here and nothing at all where it did not happen.
 */
void sl_slice_bounds_fail(size_t from, size_t to, size_t length)
{
    char buffer[160];

    if (from > to)
        snprintf(buffer, sizeof buffer,
                 "a slice from %zu to %zu runs backwards", from, to);
    else
        snprintf(buffer, sizeof buffer,
                 "a slice from %zu to %zu is outside the bounds of a length of %zu",
                 from, to, length);

    sl_fail(buffer);
}
