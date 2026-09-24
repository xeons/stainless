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
 * What was allocated and never freed, counted.
 *
 * Reference counting frees an object the moment its last reference goes, so
 * anything still allocated when the program ends was never let go of. With a
 * collector this would prove nothing -- the collector simply had not run --
 * and that is what makes the question worth asking here: the answer is exact.
 *
 * **A cycle is what this is really for.** ARC cannot collect one, which the
 * language says outright, so a form holding a button whose event holds a
 * closure holding the form is a leak nothing reports and nothing crashes on.
 * It shows up here as objects alive at exit and nowhere else.
 *
 * **A `readonly` static is alive at exit on purpose.** What a mutable one
 * holds is released before this runs, in reverse order of initialization, so
 * the number is an exact count of what leaked. A `readonly` one is made
 * immortal as it is stored and nothing releases an immortal object, so what
 * one holds is counted here and is not a leak.
 *
 * Off unless SL_LEAK_CHECK is defined, and the calls compile to nothing when
 * it is not, so a release build is byte for byte what it was.
 */

#include "stainless.h"

#ifdef SL_LEAK_CHECK

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * A side table rather than two more fields in SlObject.
 *
 * The header is three words and the compiler emits every field offset from
 * that, so widening it here would move every field in the program while the
 * code reading them kept the old numbers. The table costs a hash per
 * allocation instead, which a diagnostic build can afford.
 */
typedef struct SlLiveEntry {
    void             *object;       /* NULL for an empty slot */
    const SlTypeInfo *type;
    size_t            bytes;
    size_t            serial;       /* allocation order, for reading a report */
} SlLiveEntry;

static SlLiveEntry *sl_live;
static size_t       sl_live_capacity;   /* a power of two, or zero */
static size_t       sl_live_count;
static size_t       sl_live_serial;
static size_t       sl_live_untracked;  /* freed without having been recorded */
static SlMutex     *sl_live_gate;
static int          sl_live_reporting;

static size_t sl_live_slot(size_t capacity, const void *object)
{
    /* The pointer's low bits are the allocator's alignment and say nothing, so
     * the address is mixed before it is used as an index. splitmix64's
     * finalizer, as Standard's own hashing uses. */
    uint64_t value = (uint64_t)(uintptr_t)object;
    value += 0x9E3779B97F4A7C15ull;
    value = (value ^ (value >> 30)) * 0xBF58476D1CE4E5B9ull;
    value = (value ^ (value >> 27)) * 0x94D049BB133111EBull;
    value ^= value >> 31;

    return (size_t)value & (capacity - 1);
}

/* Called with the lock held, and never while the table is full. */
static void sl_live_put(SlLiveEntry entry)
{
    size_t at = sl_live_slot(sl_live_capacity, entry.object);

    while (sl_live[at].object != NULL) {
        if (sl_live[at].object == entry.object) break;    /* re-recorded: replace */
        at = (at + 1) & (sl_live_capacity - 1);
    }

    if (sl_live[at].object == NULL) sl_live_count++;
    sl_live[at] = entry;
}

/* Called with the lock held. */
static void sl_live_grow(void)
{
    size_t wanted = sl_live_capacity == 0 ? 1024 : sl_live_capacity * 2;

    SlLiveEntry *old = sl_live;
    size_t oldCapacity = sl_live_capacity;

    SlLiveEntry *grown = (SlLiveEntry *)calloc(wanted, sizeof(SlLiveEntry));
    if (grown == NULL) sl_fail("out of memory growing the leak table");

    sl_live = grown;
    sl_live_capacity = wanted;
    sl_live_count = 0;

    for (size_t i = 0; i < oldCapacity; i++)
        if (old[i].object != NULL) sl_live_put(old[i]);

    free(old);
}

static void sl_leak_report(void);

/*
 * Registered before main rather than at the first allocation, for two reasons.
 *
 * A program that allocates nothing would otherwise print nothing, and "clean"
 * would be indistinguishable from "the tracker was never compiled in" -- which
 * is exactly the confusion a checking build exists to remove.
 *
 * And the lazy form had a race: two threads reaching their first allocation
 * together would both see a null gate and both make one.
 */
__attribute__((constructor))
static void sl_leak_start(void)
{
    sl_live_gate = (SlMutex *)sl_mutex_new();
    atexit(sl_leak_report);
}

void sl_leak_record(void *object, size_t bytes)
{
    if (object == NULL || sl_live_gate == NULL) return;

    sl_mutex_lock(sl_live_gate);

    if ((sl_live_count + 1) * 4 >= sl_live_capacity * 3) sl_live_grow();

    SlLiveEntry entry;
    entry.object = object;
    entry.type   = ((SlObject *)object)->type;
    entry.bytes  = bytes;
    entry.serial = ++sl_live_serial;
    sl_live_put(entry);

    sl_mutex_unlock(sl_live_gate);
}

void sl_leak_forget(void *object)
{
    if (object == NULL || sl_live_gate == NULL) return;

    sl_mutex_lock(sl_live_gate);

    size_t at = sl_live_slot(sl_live_capacity, object);
    size_t probed = 0;

    while (sl_live[at].object != NULL && sl_live[at].object != object) {
        at = (at + 1) & (sl_live_capacity - 1);
        if (++probed > sl_live_capacity) break;
    }

    if (sl_live[at].object != object) {
        /* Freed without having been recorded, which means an allocation site
         * this file does not know about. Counted rather than ignored: a
         * missing hook would otherwise show up as nothing at all. */
        sl_live_untracked++;
        sl_mutex_unlock(sl_live_gate);
        return;
    }

    /* Backward-shift deletion rather than a tombstone, so a long-running
     * program's table does not fill with markers only a rehash can clear. */
    sl_live[at].object = NULL;
    sl_live_count--;

    size_t hole = at;
    size_t next = (at + 1) & (sl_live_capacity - 1);

    while (sl_live[next].object != NULL) {
        size_t home = sl_live_slot(sl_live_capacity, sl_live[next].object);

        /* Movable when the hole lies between its home and where it sits. */
        size_t fromHome = (next - home) & (sl_live_capacity - 1);
        size_t holeFromHome = (hole - home) & (sl_live_capacity - 1);

        if (holeFromHome <= fromHome) {
            sl_live[hole] = sl_live[next];
            sl_live[next].object = NULL;
            hole = next;
        }

        next = (next + 1) & (sl_live_capacity - 1);
    }

    sl_mutex_unlock(sl_live_gate);
}

/* Tallies one line of the report: a type, how many of it, and how many bytes. */
typedef struct SlLeakTally {
    const char *name;
    size_t      count;
    size_t      bytes;
    size_t      earliest;
} SlLeakTally;

static int sl_leak_worst_first(const void *left, const void *right)
{
    const SlLeakTally *a = (const SlLeakTally *)left;
    const SlLeakTally *b = (const SlLeakTally *)right;

    if (a->bytes != b->bytes) return a->bytes < b->bytes ? 1 : -1;
    if (a->count != b->count) return a->count < b->count ? 1 : -1;
    return a->earliest < b->earliest ? -1 : a->earliest > b->earliest;
}

/*
 * Written to stderr, after everything the program wrote, for the reason
 * sl_fail flushes first: a report that lands in the middle of the output it is
 * about is harder to read than one that follows it.
 *
 * The first line is the one a script reads. The rest is for a person.
 */
static void sl_leak_report(void)
{
    if (sl_live_reporting) return;      /* exit called from an atexit handler */
    sl_live_reporting = 1;

    fflush(NULL);

    size_t live = sl_live_count;
    size_t bytes = 0;

    SlLeakTally *tally = NULL;
    size_t kinds = 0;

    if (live > 0) {
        tally = (SlLeakTally *)calloc(live, sizeof(SlLeakTally));

        for (size_t i = 0; i < sl_live_capacity; i++) {
            if (sl_live[i].object == NULL) continue;

            bytes += sl_live[i].bytes;
            if (tally == NULL) continue;

            const char *name = sl_live[i].type != NULL && sl_live[i].type->name != NULL
                             ? sl_live[i].type->name : "(no type)";

            size_t found = kinds;
            for (size_t k = 0; k < kinds; k++)
                if (strcmp(tally[k].name, name) == 0) { found = k; break; }

            if (found == kinds) {
                tally[kinds].name = name;
                tally[kinds].earliest = sl_live[i].serial;
                kinds++;
            }

            tally[found].count++;
            tally[found].bytes += sl_live[i].bytes;
            if (sl_live[i].serial < tally[found].earliest)
                tally[found].earliest = sl_live[i].serial;
        }
    }

    fprintf(stderr, "stainless-leak: live=%zu bytes=%zu allocated=%zu untracked=%zu\n",
            live, bytes, sl_live_serial, sl_live_untracked);

    if (tally != NULL) {
        qsort(tally, kinds, sizeof(SlLeakTally), sl_leak_worst_first);

        /* The earliest serial says *when*: "the 12th object this program
         * allocated is still here" narrows a search that a type name alone
         * does not. */
        for (size_t k = 0; k < kinds; k++)
            fprintf(stderr, "  %8zu  %-40s %zu bytes, first at #%zu\n",
                    tally[k].count, tally[k].name, tally[k].bytes, tally[k].earliest);

        free(tally);
    }

    fflush(stderr);
}

#endif /* SL_LEAK_CHECK */
