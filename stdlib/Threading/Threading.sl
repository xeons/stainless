// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

/// Locks, atomics and the job pool.
///
/// This is step 2 of docs/concurrency.md: the library surface over the runtime
/// primitives, with no new syntax. `spawn` and `parallel` are step 3, and the
/// move and sendability analysis that makes any of this checkable is step 6 --
/// so for now the rules in that document are conventions the compiler does not
/// yet enforce.
///
/// The one rule that matters most: threads share plain data and frozen data,
/// and move ownership of everything else. Reference counts are atomic, so
/// sharing an object no longer corrupts its count; what the rule protects is
/// the object's *contents*, which nothing synchronizes on its behalf.
module Standard.Threading;

extern "C"
{
    byte* sl_mutex_new();
    void  sl_mutex_free(byte* mutex);
    void  sl_mutex_lock(byte* mutex);
    bool  sl_mutex_try_lock(byte* mutex);
    void  sl_mutex_unlock(byte* mutex);

    byte* sl_condition_new();
    void  sl_condition_free(byte* condition);
    void  sl_condition_wait(byte* condition, byte* mutex);
    bool  sl_condition_wait_for(byte* condition, byte* mutex, ulong milliseconds);
    void  sl_condition_signal(byte* condition);
    void  sl_condition_broadcast(byte* condition);

    byte* sl_rwlock_new();
    void  sl_rwlock_free(byte* lock);
    void  sl_rwlock_read_lock(byte* lock);
    bool  sl_rwlock_try_read_lock(byte* lock);
    void  sl_rwlock_read_unlock(byte* lock);
    void  sl_rwlock_write_lock(byte* lock);
    bool  sl_rwlock_try_write_lock(byte* lock);
    void  sl_rwlock_write_unlock(byte* lock);

    long sl_atomic_load(long* cell);
    void sl_atomic_store(long* cell, long value);
    long sl_atomic_add(long* cell, long delta);
    long sl_atomic_exchange(long* cell, long value);
    bool sl_atomic_compare_exchange(long* cell, long* expected, long desired);
    long sl_atomic_and(long* cell, long mask);
    long sl_atomic_or(long* cell, long mask);
    long sl_atomic_xor(long* cell, long mask);

    int  sl_atomic_load32(int* cell);
    void sl_atomic_store32(int* cell, int value);
    int  sl_atomic_add32(int* cell, int delta);
    int  sl_atomic_exchange32(int* cell, int value);
    bool sl_atomic_compare_exchange32(int* cell, int* expected, int desired);

    void  sl_retain(byte* pointer);
    void  sl_release(byte* pointer);

    byte* sl_thread_start(Job body, byte* argument);
    void  sl_thread_join(byte* thread);
    void  sl_thread_detach(byte* thread);
    void  sl_thread_yield();
    void  sl_thread_sleep(ulong milliseconds);
    nuint sl_thread_current_id();
    void  sl_cpu_pause();

    byte* sl_scope_begin();
    void  sl_scope_submit(byte* scope, Job job, byte* argument);
    void  sl_scope_end(byte* scope);

    void  sl_pool_start(nuint workers);
    nuint sl_pool_worker_count();
    nuint sl_cpu_count();

    long  sl_time_monotonic();
}

// A deadline `milliseconds` from now on the monotonic clock, in nanoseconds.
// A span too long to represent saturates.
long ComputeDeadlineAfter(ulong milliseconds)
{
    long now = sl_time_monotonic();
    ulong limit = (ulong)(9223372036854775807 - now) / 1000000u;
    if (milliseconds >= limit)
        return 9223372036854775807;
    return now + (long)milliseconds * 1000000;
}

// Whole milliseconds left before `deadline`, rounded up so a wait does not end
// early. Zero once it has passed.
ulong GetMillisecondsBeforeDeadline(long deadline)
{
    long left = deadline - sl_time_monotonic();
    if (left <= 0)
        return 0u;
    return ((ulong)left + 999999u) / 1000000u;
}

// One timed wait toward `deadline`. False when the deadline has passed; the
// caller MUST re-check its condition before treating that as a timeout, since
// a wake and the deadline can arrive together.
bool WaitBeforeDeadline(byte* signal, byte* mutex, long deadline)
{
    ulong left = GetMillisecondsBeforeDeadline(deadline);
    if (left == 0u)
        return false;
    sl_condition_wait_for(signal, mutex, left);
    return true;
}

// -------------------------------------------------------------------- tasks

/// The work a pool thread runs. It is a plain function pointer, so whatever it
/// needs arrives as the argument -- usually an object cast to `byte*`, which
/// the job casts back.
public delegate void Job(byte* argument);

// ------------------------------------------------------------------ threads

/// Work with nothing to pass in and nothing to hand back: what a `Thread` runs.
///
/// A closure rather than a delegate, because the point of it is to carry what
/// it captured -- and capture is by value, so it may outlive the scope that
/// built it. That is the whole reason a closure is safe here where a pointer to
/// a local is not.
public closure void Action();

/// A closure with an address.
///
/// The runtime starts a thread from a `Job` and a `byte*`, which is C's shape
/// and cannot hold a receiver. Boxing the closure in an object gives it one,
/// and the object's address is the `byte*`. One non-generic base serves both
/// `Thread` and `Future<T>`, so there is one trampoline rather than one per
/// instantiation.
///
/// **The box owns a reference, and the trampoline drops it.** The starter
/// retains the box and hands that count to the thread; `RunBoxed` releases it
/// when the body returns. Nothing else keeps it alive -- which is what makes
/// `Detach` safe, since the box outlives the `Thread` object rather than
/// belonging to it.
class Boxed
{
    public virtual void Run() { }
}

class Running : Boxed
{
    Action _body;
    public Running(Action body) => _body = body;
    public override void Run() => _body();
}

void RunBoxed(byte* argument)
{
    var boxed = (Boxed)argument;
    boxed.Run();
    sl_release(argument);
}

/// Boxes `work`, hands the box's count to a new thread, and answers the handle.
byte* StartBoxed(Boxed work)
{
    sl_retain((byte*)work);
    return sl_thread_start(RunBoxed, (byte*)work);
}

/// Stops the calling thread for at least this long. It may be longer: this is
/// the scheduler's floor, not a timer.
public void Sleep(ulong milliseconds) => sl_thread_sleep(milliseconds);

/// Offers the rest of this thread's slice to anything else that is ready.
public void Yield() => sl_thread_yield();

/// An identifier for the calling thread, unique among those running. It is the
/// OS's number and means nothing across a restart.
public nuint CurrentId() => sl_thread_current_id();

class Pending<T> : Boxed
{
    IProducer<T> _body;
    Future<T> _target;

    public Pending(IProducer<T> body, Future<T> target)
    {
        _body = body;
        _target = target;
    }

    public override void Run() => _target.SetResult(_body.Invoke());
}

// -------------------------------------------------------------------- pool

/// How many threads the pool is running. Zero until the first scope starts it.
///
/// @see Threading.StartPool
public nuint WorkerCount() => sl_pool_worker_count();

/// How many hardware threads the machine reports.
public nuint ProcessorCount() => sl_cpu_count();

/// Starts the pool with a chosen number of workers, before any scope does it
/// automatically. Passing zero sizes it from the processor count.
///
/// @see Threading.ProcessorCount
public void StartPool(nuint workers) => sl_pool_start(workers);
