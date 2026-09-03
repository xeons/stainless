// Stainless - an experimental systems language.
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

// Locks, atomics and the job pool.
//
// This is step 2 of docs/concurrency.md: the library surface over the runtime
// primitives, with no new syntax. `spawn` and `parallel` are step 3, and the
// move and sendability analysis that makes any of this checkable is step 6 --
// so for now the rules in that document are conventions the compiler does not
// yet enforce.
//
// The one rule that matters most: threads share plain data and frozen data,
// and move ownership of everything else. Reference counts are not atomic, and
// nothing here makes them atomic.
module Standard.Threading;

extern "C" {
    byte* sl_mutex_new();
    void  sl_mutex_free(byte* mutex);
    void  sl_mutex_lock(byte* mutex);
    bool  sl_mutex_try_lock(byte* mutex);
    void  sl_mutex_unlock(byte* mutex);

    long sl_atomic_load(long* cell);
    void sl_atomic_store(long* cell, long value);
    long sl_atomic_add(long* cell, long delta);
    long sl_atomic_exchange(long* cell, long value);
    bool sl_atomic_compare_exchange(long* cell, long* expected, long desired);

    byte* sl_scope_begin();
    void  sl_scope_submit(byte* scope, Job job, byte* argument);
    void  sl_scope_end(byte* scope);

    void  sl_pool_start(nuint workers);
    nuint sl_pool_worker_count();
    nuint sl_cpu_count();
}

// ------------------------------------------------------------------ sharing

/// Marks a type as safe for more than one thread to hold at once.
///
/// It is an assertion by the author, not something the compiler checks: it says
/// that every operation on this type synchronizes itself, so two threads
/// reaching it cannot corrupt it. Without it a class may not cross a thread
/// boundary at all, because reference counts are not atomic and nothing would
/// report the race.
///
/// Put it on a type whose state lives behind a lock or an atomic, and nowhere
/// else. `Mutex`, `AtomicLong` and `AtomicBool` carry it because that is what
/// they are; `Guard` and `TaskScope` do not, because both belong to one thread.
public attribute Shared { }

// ------------------------------------------------------------------ locking

/// A value and the lock that guards it, as one thing.
///
/// Tying the two together is the whole point: there is no way to reach the
/// value without holding the lock, and no way to forget which lock guards
/// what. Compare `lock (obj) { }`, which would put a lock word in every object
/// header and charge every single-threaded program for it.
///
/// Unlocking is a destructor, so ARC already does it -- including on an early
/// `return`, and including when a `Guard` is dropped in a branch you forgot
/// about.
///
///     var guard = registry.Lock();
///     guard.Value().Add(name);
///     // ~Guard() unlocks here
///
/// **Known hole.** `Value()` hands out what the lock protects, and nothing yet
/// stops you storing it somewhere and using it after the guard has gone. C#
/// has the same hole and worse; Rust closes it with lifetimes. Stainless
/// closes it when the analysis in step 6 of docs/concurrency.md lands, and not
/// before. Until then this is a discipline, not a guarantee.
///
/// **Unsound when `T` is a class, and used from more than one thread.**
/// Returning the guarded object from `Value()` retains it, and dropping the
/// result releases it -- so two threads locking in turn still perform an
/// unsynchronized read-modify-write on that object's reference count. The lock
/// protects the contents; nothing protects the count. It drifts down, and the
/// object is eventually destroyed while the mutex still holds it.
///
/// `Mutex<long>` and other plain values are unaffected, because a plain value
/// is never retained. For a shared *object*, keep it in a field and never hand
/// it out -- which is what every container in Standard.Concurrent does, and why
/// none of them is built on this type.
///
/// Closing this properly means atomic reference counts for `[Shared]` types.
/// That is a decision about the ARC model rather than a bug in this file.
[Shared]
public class Mutex<T> {
    T value;
    byte* handle;

    public Mutex(T initial) {
        value = initial;
        handle = sl_mutex_new();
    }

    ~Mutex() { sl_mutex_free(handle); }

    /// Blocks until the lock is free, then returns the guard that holds it.
    ///
    /// Keep the result in a variable. `registry.Lock();` on its own locks and
    /// then immediately unlocks, because the guard is a temporary and dies at
    /// the end of the statement.
    public Guard<T> Lock() {
        sl_mutex_lock(handle);
        return new Guard<T>(this);
    }

    /// Takes the lock only if it is free. Returns null rather than blocking.
    public Guard<T>? TryLock() {
        if (sl_mutex_try_lock(handle)) { return new Guard<T>(this); }
        return null;
    }

    // Reached through a Guard, which is the only thing that holds the lock.
    T Read() { return value; }
    void Write(T updated) { value = updated; }
    void Unlock() { sl_mutex_unlock(handle); }
}

/// Proof that a lock is held, and the only route to what it guards.
///
/// A guard keeps its mutex alive, so the lock cannot be freed while it is
/// held. Releasing is the destructor's job; there is no `Unlock` to forget.
public class Guard<T> {
    Mutex<T> owner;

    Guard(Mutex<T> held) { owner = held; }

    ~Guard() { owner.Unlock(); }

    public T Value() { return owner.Read(); }

    public void Set(T updated) { owner.Write(updated); }
}

// ------------------------------------------------------------------ atomics

/// A 64-bit counter that several threads may touch at once.
///
/// Every operation is sequentially consistent. Weaker orderings are worth
/// having only once something measures as too slow, and getting them wrong is
/// invisible until it is expensive.
///
/// It is `long` rather than generic because atomics are not: `Atomic<T>` would
/// need a constraint saying T is an integer, and Stainless constrains by
/// interface only. A shared counter wants 64 bits anyway.
[Shared]
public class AtomicLong {
    long cell;

    public AtomicLong(long initial) { cell = initial; }

    public long Load() { return sl_atomic_load(&cell); }

    public void Store(long value) { sl_atomic_store(&cell, value); }

    /// Adds and returns the new value, so two threads never see the same result.
    public long Add(long delta) { return sl_atomic_add(&cell, delta); }

    public long Increment() { return sl_atomic_add(&cell, 1); }

    public long Decrement() { return sl_atomic_add(&cell, -1); }

    /// Stores `value` and returns what was there before.
    public long Exchange(long value) { return sl_atomic_exchange(&cell, value); }

    /// Stores `desired` only if the current value is `expected`, and reports
    /// whether it did. The building block for anything lock-free.
    public bool CompareExchange(long expected, long desired) {
        long witness = expected;
        return sl_atomic_compare_exchange(&cell, &witness, desired);
    }
}

/// A flag several threads may set and read. One-way latches -- "has this
/// started", "should this stop" -- are what it is for.
[Shared]
public class AtomicBool {
    long cell;

    public AtomicBool(bool initial) {
        cell = 0;
        if (initial) { cell = 1; }
    }

    public bool Load() { return sl_atomic_load(&cell) != 0; }

    public void Store(bool value) {
        long raw = 0;
        if (value) { raw = 1; }
        sl_atomic_store(&cell, raw);
    }

    /// Sets the flag and returns what it was, which is how one thread wins a race.
    public bool Exchange(bool value) {
        long raw = 0;
        if (value) { raw = 1; }
        return sl_atomic_exchange(&cell, raw) != 0;
    }
}

// -------------------------------------------------------------------- tasks

/// The work a pool thread runs. It is a plain function pointer, so whatever it
/// needs arrives as the argument -- usually an object cast to `byte*`, which
/// the job casts back.
public delegate void Job(byte* argument);

/// A set of jobs that must all finish before the scope does.
///
/// This is the join counter behind `parallel`, exposed as a class until the
/// syntax exists. `Join` does not return until every job submitted to this
/// scope has run, and the calling thread runs queued work while it waits
/// rather than idling.
///
/// **Nothing is checked yet.** A job receives a raw pointer, so keeping the
/// object it points at alive across the join is on you -- holding it in a
/// local of the function that owns the scope is enough, since the scope joins
/// before that function returns. Step 6 of docs/concurrency.md is what turns
/// this from a convention into a rule.
public class TaskScope {
    byte* handle;

    public TaskScope() { handle = sl_scope_begin(); }

    /// Queues a job. It may already be running when this returns.
    public void Run(Job job, byte* argument) {
        sl_scope_submit(handle, job, argument);
    }

    /// Waits for every job submitted so far. Doing it twice is harmless, which
    /// is what lets the destructor be a backstop for a scope nobody joined.
    public void Join() {
        if (handle != null) {
            sl_scope_end(handle);
            handle = null;
        }
    }

    ~TaskScope() { Join(); }
}

/// How many threads the pool is running. Zero until the first scope starts it.
public nuint WorkerCount() { return sl_pool_worker_count(); }

/// How many hardware threads the machine reports.
public nuint ProcessorCount() { return sl_cpu_count(); }

/// Starts the pool with a chosen number of workers, before any scope does it
/// automatically. Passing zero sizes it from the processor count.
public void StartPool(nuint workers) { sl_pool_start(workers); }
