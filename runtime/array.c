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
    array->length = length;
    return array;
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
