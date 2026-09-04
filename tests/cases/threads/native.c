/* SPDX-License-Identifier: 0BSD */

/*
 * Drives the Stainless job pool from C.
 *
 * The runtime functions are declared here by hand rather than included, which
 * is also the point: the pool is reachable from any C consumer with no header
 * and no glue, the same as the rest of the runtime.
 */

#include <stddef.h>

typedef struct SlScope SlScope;
typedef void (*SlJob)(void *argument);

SlScope  *sl_scope_begin(void);
void      sl_scope_submit(SlScope *scope, SlJob job, void *argument);
void      sl_scope_end(SlScope *scope);
long long sl_atomic_add(long long *cell, long long delta);
long long sl_atomic_load(const long long *cell);
size_t    sl_pool_worker_count(void);

/* Implemented in Stainless; allocates and destroys objects on this thread. */
int sl_worker(int seed);

static long long total;
static long long visits;

static void accumulate(void *argument)
{
    int seed = (int)(ptrdiff_t)argument;
    sl_atomic_add(&total, sl_worker(seed));
}

long long c_parallel_sum(long long count)
{
    total = 0;

    SlScope *scope = sl_scope_begin();
    for (long long i = 0; i < count; i += 1)
        sl_scope_submit(scope, accumulate, (void *)(ptrdiff_t)i);
    sl_scope_end(scope);

    return sl_atomic_load(&total);
}

/* Each job counts itself, then opens a scope of its own. A pool that could not
 * make progress while a worker waits on a nested scope would deadlock here. */
struct Fan { long long depth; long long branch; };
static struct Fan fan;

static void descend(void *argument)
{
    long long depth = (long long)(ptrdiff_t)argument;
    sl_atomic_add(&visits, 1);

    if (depth == 0) return;

    SlScope *scope = sl_scope_begin();
    for (long long i = 0; i < fan.branch; i += 1)
        sl_scope_submit(scope, descend, (void *)(ptrdiff_t)(depth - 1));
    sl_scope_end(scope);
}

long long c_nested_count(long long depth, long long branch)
{
    visits = 0;
    fan.depth = depth;
    fan.branch = branch;

    SlScope *scope = sl_scope_begin();
    sl_scope_submit(scope, descend, (void *)(ptrdiff_t)depth);
    sl_scope_end(scope);

    return sl_atomic_load(&visits);
}

long long c_worker_count(void)
{
    return (long long)sl_pool_worker_count();
}
