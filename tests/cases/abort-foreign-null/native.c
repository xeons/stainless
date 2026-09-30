/* SPDX-License-Identifier: 0BSD */
#include <stddef.h>

/* Declared on the Stainless side as returning a `String`, which is never null. */
void *c_find_name(int wanted)
{
    (void)wanted;
    return NULL;
}

/* Declared as returning a `String?`, which may be. */
void *c_find_maybe(int wanted)
{
    (void)wanted;
    return NULL;
}
