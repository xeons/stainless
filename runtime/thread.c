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
 * Threads, locks and the job pool.
 *
 * This is the foundation for docs/concurrency.md, and deliberately nothing
 * more: the language cannot reach any of it yet. Reference counting stays
 * non-atomic, which is only correct because the model above this layer never
 * lets two threads touch one object. The barrier that makes the handoff safe
 * is the scope mutex -- everything a job did happens-before the sl_scope_end
 * that observed its completion.
 *
 * The pool is one shared queue behind one mutex. Work stealing would scale
 * further under contention, and is the obvious next change if a benchmark ever
 * asks for it; a single queue is easier to be sure of, and being sure matters
 * more right now.
 */

#include "stainless.h"

#include <stdlib.h>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#else
#  include <pthread.h>
#  include <sched.h>
#  include <unistd.h>
#endif

/* The opaque storage in the header has to actually fit the platform type. */
#ifdef _WIN32
_Static_assert(sizeof(SRWLOCK) <= sizeof(SlMutex), "SlMutex too small");
_Static_assert(sizeof(CONDITION_VARIABLE) <= sizeof(SlCondition), "SlCondition too small");
#else
_Static_assert(sizeof(pthread_mutex_t) <= sizeof(SlMutex), "SlMutex too small");
_Static_assert(sizeof(pthread_cond_t) <= sizeof(SlCondition), "SlCondition too small");
#endif

/* ------------------------------------------------------------------ locks */

/*
 * SRWLOCK rather than CRITICAL_SECTION: it is one pointer, needs no destroy
 * call, and is faster uncontended. Neither it nor the pthread default is
 * recursive, which is the behaviour to want -- a recursive lock usually means
 * an ownership question went unanswered.
 */

#ifdef _WIN32
#  define AS_MUTEX(m)     ((SRWLOCK *)(m)->opaque)
#  define AS_CONDITION(c) ((CONDITION_VARIABLE *)(c)->opaque)
#else
#  define AS_MUTEX(m)     ((pthread_mutex_t *)(m)->opaque)
#  define AS_CONDITION(c) ((pthread_cond_t *)(c)->opaque)
#endif

void sl_mutex_init(SlMutex *mutex)
{
#ifdef _WIN32
    InitializeSRWLock(AS_MUTEX(mutex));
#else
    if (pthread_mutex_init(AS_MUTEX(mutex), NULL) != 0)
        sl_fail("could not create a mutex");
#endif
}

void sl_mutex_destroy(SlMutex *mutex)
{
#ifdef _WIN32
    (void)mutex;            /* an SRWLOCK holds no resources */
#else
    pthread_mutex_destroy(AS_MUTEX(mutex));
#endif
}

void *sl_mutex_new(void)
{
    SlMutex *mutex = (SlMutex *)calloc(1, sizeof(SlMutex));
    if (mutex == NULL) sl_fail("out of memory");

    sl_mutex_init(mutex);
    return mutex;
}

void sl_mutex_free(void *mutex)
{
    if (mutex == NULL) return;

    sl_mutex_destroy((SlMutex *)mutex);
    free(mutex);
}

/*
 * The same pair for a condition variable, so that Stainless can own one. A
 * condition is a value the caller has to find room for, and Stainless has no
 * way to make room for an opaque struct; a handle it can hold in a byte* does.
 */
void *sl_condition_new(void)
{
    SlCondition *condition = (SlCondition *)calloc(1, sizeof(SlCondition));
    if (condition == NULL) sl_fail("out of memory");

    sl_condition_init(condition);
    return condition;
}

void sl_condition_free(void *condition)
{
    if (condition == NULL) return;

    sl_condition_destroy((SlCondition *)condition);
    free(condition);
}

void sl_mutex_lock(SlMutex *mutex)
{
#ifdef _WIN32
    AcquireSRWLockExclusive(AS_MUTEX(mutex));
#else
    pthread_mutex_lock(AS_MUTEX(mutex));
#endif
}

_Bool sl_mutex_try_lock(SlMutex *mutex)
{
#ifdef _WIN32
    return TryAcquireSRWLockExclusive(AS_MUTEX(mutex)) != 0;
#else
    return pthread_mutex_trylock(AS_MUTEX(mutex)) == 0;
#endif
}

void sl_mutex_unlock(SlMutex *mutex)
{
#ifdef _WIN32
    ReleaseSRWLockExclusive(AS_MUTEX(mutex));
#else
    pthread_mutex_unlock(AS_MUTEX(mutex));
#endif
}

void sl_condition_init(SlCondition *condition)
{
#ifdef _WIN32
    InitializeConditionVariable(AS_CONDITION(condition));
#else
    if (pthread_cond_init(AS_CONDITION(condition), NULL) != 0)
        sl_fail("could not create a condition variable");
#endif
}

void sl_condition_destroy(SlCondition *condition)
{
#ifdef _WIN32
    (void)condition;
#else
    pthread_cond_destroy(AS_CONDITION(condition));
#endif
}

void sl_condition_wait(SlCondition *condition, SlMutex *mutex)
{
#ifdef _WIN32
    SleepConditionVariableSRW(AS_CONDITION(condition), AS_MUTEX(mutex), INFINITE, 0);
#else
    pthread_cond_wait(AS_CONDITION(condition), AS_MUTEX(mutex));
#endif
}

void sl_condition_signal(SlCondition *condition)
{
#ifdef _WIN32
    WakeConditionVariable(AS_CONDITION(condition));
#else
    pthread_cond_signal(AS_CONDITION(condition));
#endif
}

void sl_condition_broadcast(SlCondition *condition)
{
#ifdef _WIN32
    WakeAllConditionVariable(AS_CONDITION(condition));
#else
    pthread_cond_broadcast(AS_CONDITION(condition));
#endif
}

/* --------------------------------------------------------------- atomics */

/*
 * Sequentially consistent throughout. Weaker orderings are worth having only
 * once something measures as too slow, and getting them wrong is invisible
 * until it is expensive.
 */

long long sl_atomic_load(const long long *cell)
{
    return __atomic_load_n(cell, __ATOMIC_SEQ_CST);
}

void sl_atomic_store(long long *cell, long long value)
{
    __atomic_store_n(cell, value, __ATOMIC_SEQ_CST);
}

long long sl_atomic_add(long long *cell, long long delta)
{
    return __atomic_add_fetch(cell, delta, __ATOMIC_SEQ_CST);
}

long long sl_atomic_exchange(long long *cell, long long value)
{
    return __atomic_exchange_n(cell, value, __ATOMIC_SEQ_CST);
}

_Bool sl_atomic_compare_exchange(long long *cell, long long *expected, long long desired)
{
    return __atomic_compare_exchange_n(
        cell, expected, desired, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
}

/* --------------------------------------------------------------- threads */

struct SlThread {
    void (*entry)(void *);
    void  *argument;
#ifdef _WIN32
    HANDLE handle;
#else
    pthread_t handle;
#endif
};

#ifdef _WIN32
static DWORD WINAPI thread_trampoline(LPVOID parameter)
{
    SlThread *thread = (SlThread *)parameter;
    thread->entry(thread->argument);
    return 0;
}
#else
static void *thread_trampoline(void *parameter)
{
    SlThread *thread = (SlThread *)parameter;
    thread->entry(thread->argument);
    return NULL;
}
#endif

SlThread *sl_thread_start(void (*entry)(void *), void *argument)
{
    SlThread *thread = (SlThread *)calloc(1, sizeof(SlThread));
    if (thread == NULL) sl_fail("out of memory");

    thread->entry    = entry;
    thread->argument = argument;

#ifdef _WIN32
    thread->handle = CreateThread(NULL, 0, thread_trampoline, thread, 0, NULL);
    if (thread->handle == NULL) sl_fail("could not start a thread");
#else
    if (pthread_create(&thread->handle, NULL, thread_trampoline, thread) != 0)
        sl_fail("could not start a thread");
#endif

    return thread;
}

void sl_thread_join(SlThread *thread)
{
    if (thread == NULL) return;

#ifdef _WIN32
    WaitForSingleObject(thread->handle, INFINITE);
    CloseHandle(thread->handle);
#else
    pthread_join(thread->handle, NULL);
#endif

    free(thread);
}

void sl_thread_yield(void)
{
#ifdef _WIN32
    SwitchToThread();
#else
    sched_yield();
#endif
}

size_t sl_thread_current_id(void)
{
#ifdef _WIN32
    return (size_t)GetCurrentThreadId();
#else
    return (size_t)pthread_self();
#endif
}

size_t sl_cpu_count(void)
{
#ifdef _WIN32
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    return info.dwNumberOfProcessors > 0 ? (size_t)info.dwNumberOfProcessors : 1;
#else
    long count = sysconf(_SC_NPROCESSORS_ONLN);
    return count > 0 ? (size_t)count : 1;
#endif
}

/* ------------------------------------------------------------- the queue */

struct SlScope {
    SlMutex     mutex;
    SlCondition drained;
    size_t      pending;
};

typedef struct SlTask {
    SlJob    job;
    void    *argument;
    SlScope *scope;
} SlTask;

static struct {
    SlMutex     mutex;
    SlCondition arrived;        /* a task was queued, or the pool is stopping */

    SlTask     *tasks;          /* circular buffer */
    size_t      capacity;
    size_t      head;           /* index of the next task to run */
    size_t      count;

    SlThread  **workers;
    size_t      workerCount;

    _Bool       running;
    _Bool       stopping;
} pool;

/*
 * Guards the one-time start. It is a raw platform lock rather than an SlMutex
 * because it has to be usable before anything has run to initialise it, and
 * both platforms offer a static initialiser for exactly this case.
 */
#ifdef _WIN32
static SRWLOCK startupLock = SRWLOCK_INIT;
#  define STARTUP_LOCK()   AcquireSRWLockExclusive(&startupLock)
#  define STARTUP_UNLOCK() ReleaseSRWLockExclusive(&startupLock)
#else
static pthread_mutex_t startupLock = PTHREAD_MUTEX_INITIALIZER;
#  define STARTUP_LOCK()   pthread_mutex_lock(&startupLock)
#  define STARTUP_UNLOCK() pthread_mutex_unlock(&startupLock)
#endif

/* Caller holds pool.mutex. */
static void queue_push(SlTask task)
{
    if (pool.count == pool.capacity) {
        size_t capacity = pool.capacity == 0 ? 64 : pool.capacity * 2;
        SlTask *tasks = (SlTask *)calloc(capacity, sizeof(SlTask));
        if (tasks == NULL) sl_fail("out of memory");

        /* Unroll the ring into the new buffer, oldest first. */
        for (size_t i = 0; i < pool.count; i += 1)
            tasks[i] = pool.tasks[(pool.head + i) % pool.capacity];

        free(pool.tasks);
        pool.tasks    = tasks;
        pool.capacity = capacity;
        pool.head     = 0;
    }

    pool.tasks[(pool.head + pool.count) % pool.capacity] = task;
    pool.count += 1;
}

/* Caller holds pool.mutex. Returns false when the queue is empty. */
static _Bool queue_pop(SlTask *task)
{
    if (pool.count == 0) return 0;

    *task     = pool.tasks[pool.head];
    pool.head = (pool.head + 1) % pool.capacity;
    pool.count -= 1;
    return 1;
}

static void run_task(SlTask task)
{
    task.job(task.argument);

    /*
     * Completing under the scope lock is what publishes the job's writes to
     * whoever is waiting in sl_scope_end. This is the barrier the non-atomic
     * reference counts depend on.
     */
    SlScope *scope = task.scope;
    sl_mutex_lock(&scope->mutex);
    scope->pending -= 1;
    if (scope->pending == 0) sl_condition_broadcast(&scope->drained);
    sl_mutex_unlock(&scope->mutex);
}

static void worker_main(void *argument)
{
    (void)argument;

    for (;;) {
        SlTask task;

        sl_mutex_lock(&pool.mutex);
        while (pool.count == 0 && !pool.stopping)
            sl_condition_wait(&pool.arrived, &pool.mutex);

        if (pool.count == 0 && pool.stopping) {
            sl_mutex_unlock(&pool.mutex);
            return;
        }

        queue_pop(&task);
        sl_mutex_unlock(&pool.mutex);

        run_task(task);
    }
}

/* Caller holds startupLock. */
static void pool_start_locked(size_t workers)
{
    if (pool.running) return;

    if (workers == 0) {
        /*
         * One short of the CPU count, because the thread that calls
         * sl_scope_end does not idle -- it runs queued work while it waits.
         * That thread is the missing worker.
         */
        size_t cpus = sl_cpu_count();
        workers = cpus > 1 ? cpus - 1 : 1;
    }

    sl_mutex_init(&pool.mutex);
    sl_condition_init(&pool.arrived);

    pool.workers = (SlThread **)calloc(workers, sizeof(SlThread *));
    if (pool.workers == NULL) sl_fail("out of memory");

    pool.workerCount = workers;
    pool.stopping    = 0;
    pool.running     = 1;

    for (size_t i = 0; i < workers; i += 1)
        pool.workers[i] = sl_thread_start(worker_main, NULL);
}

void sl_pool_start(size_t workers)
{
    STARTUP_LOCK();
    pool_start_locked(workers);
    STARTUP_UNLOCK();
}

void sl_pool_shutdown(void)
{
    STARTUP_LOCK();

    if (!pool.running) {
        STARTUP_UNLOCK();
        return;
    }

    sl_mutex_lock(&pool.mutex);
    pool.stopping = 1;
    sl_condition_broadcast(&pool.arrived);
    sl_mutex_unlock(&pool.mutex);

    for (size_t i = 0; i < pool.workerCount; i += 1)
        sl_thread_join(pool.workers[i]);

    free(pool.workers);
    free(pool.tasks);

    sl_condition_destroy(&pool.arrived);
    sl_mutex_destroy(&pool.mutex);

    pool.workers     = NULL;
    pool.workerCount = 0;
    pool.tasks       = NULL;
    pool.capacity    = 0;
    pool.head        = 0;
    pool.count       = 0;
    pool.running     = 0;
    pool.stopping    = 0;

    STARTUP_UNLOCK();
}

size_t sl_pool_worker_count(void)
{
    return pool.workerCount;
}

/* --------------------------------------------------------------- scopes */

SlScope *sl_scope_begin(void)
{
    STARTUP_LOCK();
    pool_start_locked(0);
    STARTUP_UNLOCK();

    SlScope *scope = (SlScope *)calloc(1, sizeof(SlScope));
    if (scope == NULL) sl_fail("out of memory");

    sl_mutex_init(&scope->mutex);
    sl_condition_init(&scope->drained);
    scope->pending = 0;
    return scope;
}

void sl_scope_submit(SlScope *scope, SlJob job, void *argument)
{
    sl_mutex_lock(&scope->mutex);
    scope->pending += 1;
    sl_mutex_unlock(&scope->mutex);

    SlTask task = { job, argument, scope };

    sl_mutex_lock(&pool.mutex);
    queue_push(task);
    sl_condition_signal(&pool.arrived);
    sl_mutex_unlock(&pool.mutex);
}

/*
 * Several chunks per worker rather than exactly one: a chunk that finishes
 * early lets its thread pick up another, so an uneven body does not leave
 * threads idle waiting for the slowest chunk.
 */
#define SL_CHUNKS_PER_WORKER 4

typedef struct SlRangeTask {
    SlRangeJob job;
    void      *capture;
    size_t     start;
    size_t     end;
} SlRangeTask;

static void range_trampoline(void *argument)
{
    SlRangeTask *task = (SlRangeTask *)argument;
    task->job(task->capture, task->start, task->end);
    free(task);
}

void sl_parallel_range(SlScope *scope, size_t count, SlRangeJob job, void *capture)
{
    if (count == 0) return;

    size_t workers = pool.workerCount > 0 ? pool.workerCount : sl_cpu_count();
    size_t chunks  = workers * SL_CHUNKS_PER_WORKER;
    if (chunks > count) chunks = count;
    if (chunks == 0) chunks = 1;

    /* Ceiling division, so the last chunk is the short one rather than a stray. */
    size_t span = (count + chunks - 1) / chunks;

    for (size_t start = 0; start < count; start += span) {
        size_t end = start + span;
        if (end > count) end = count;

        SlRangeTask *task = (SlRangeTask *)calloc(1, sizeof(SlRangeTask));
        if (task == NULL) sl_fail("out of memory");

        task->job     = job;
        task->capture = capture;
        task->start   = start;
        task->end     = end;

        sl_scope_submit(scope, range_trampoline, task);
    }
}

/*
 * Waits for every job submitted to this scope, and runs queued work rather
 * than idling while it does.
 *
 * Helping is not an optimisation, it is what keeps nested `parallel` blocks
 * from deadlocking: a worker that blocks here while its own jobs sit unclaimed
 * in the queue would be waiting on itself. Because a thread only ever sleeps
 * when the queue is empty, anything still pending is already running somewhere
 * and will signal.
 */
void sl_scope_end(SlScope *scope)
{
    for (;;) {
        SlTask task;
        _Bool  helped = 0;

        sl_mutex_lock(&pool.mutex);
        helped = queue_pop(&task);
        sl_mutex_unlock(&pool.mutex);

        if (helped) {
            run_task(task);
            continue;
        }

        sl_mutex_lock(&scope->mutex);
        if (scope->pending == 0) {
            sl_mutex_unlock(&scope->mutex);
            break;
        }
        sl_condition_wait(&scope->drained, &scope->mutex);
        sl_mutex_unlock(&scope->mutex);
    }

    sl_condition_destroy(&scope->drained);
    sl_mutex_destroy(&scope->mutex);
    free(scope);
}
