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
// and move ownership of everything else. Reference counts are atomic, so
// sharing an object no longer corrupts its count; what the rule protects is
// the object's *contents*, which nothing synchronizes on its behalf.
module Standard.Threading;

extern "C" {
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
}

// ------------------------------------------------------------------ sharing

/// Marks a type as safe for more than one thread to hold at once.
///
/// It is an assertion by the author, not something the compiler checks: it says
/// that every operation on this type synchronizes itself, so two threads
/// reaching it cannot corrupt it. Without it a class may not cross a thread
/// boundary at all: reference counts are atomic, but nothing synchronizes the
/// fields behind them, and a race there is one nothing would report.
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
/// It used to be unsound for a class `T`: `Value()` retains what it hands out
/// and the caller releases it, often outside the lock, so two threads performed
/// an unsynchronized read-modify-write on that object's count. The count drifted
/// down and the object was freed while the mutex still held it. Reference counts
/// are atomic now, which closes that; what remains is the lifetime hole above,
/// which is about how long a borrowed thing lives rather than about counting.
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

// ----------------------------------------------------------------- monitors

/// A `Mutex<T>` that can also be waited on -- C#'s `Monitor`, with the same
/// `Wait`, `Pulse` and `PulseAll`, and with the lock and the data still tied
/// together.
///
/// A monitor is what you want when a thread has to wait for a *condition* on
/// the guarded value rather than just for the lock. `Wait` releases the lock,
/// sleeps, and takes it again before returning, so a waiter never misses a
/// pulse that lands while it is going to sleep.
///
/// **Always wait in a loop.** Both platforms permit a spurious wake, and the
/// pulse says only "the value changed", never "it changed the way you want":
///
///     var held = queue.Lock();
///     while (held.Value().IsEmpty()) { held.Wait(); }
///     var item = held.Value().Take();
[Shared]
public class Monitor<T> {
    T value;
    byte* handle;
    byte* signal;

    public Monitor(T initial) {
        value = initial;
        handle = sl_mutex_new();
        signal = sl_condition_new();
    }

    ~Monitor() {
        sl_condition_free(signal);
        sl_mutex_free(handle);
    }

    /// Blocks until the lock is free. Keep the result in a variable -- a
    /// temporary unlocks at the end of the statement.
    public MonitorGuard<T> Lock() {
        sl_mutex_lock(handle);
        return new MonitorGuard<T>(this);
    }

    // Reached through a MonitorGuard, which is the only thing holding the lock.
    T Read() { return value; }
    void Write(T updated) { value = updated; }
    void Unlock() { sl_mutex_unlock(handle); }
    void Sleep() { sl_condition_wait(signal, handle); }
    bool SleepFor(ulong milliseconds) {
        return sl_condition_wait_for(signal, handle, milliseconds);
    }
    void Wake() { sl_condition_signal(signal); }
    void WakeAll() { sl_condition_broadcast(signal); }
}

/// Proof that a monitor is held, and the only route to what it guards.
public class MonitorGuard<T> {
    Monitor<T> owner;

    MonitorGuard(Monitor<T> held) { owner = held; }

    ~MonitorGuard() { owner.Unlock(); }

    public T Value() { return owner.Read(); }

    public void Set(T updated) { owner.Write(updated); }

    /// Releases the lock, waits for a pulse, and takes the lock again. Call it
    /// in a loop that re-checks what you are waiting for.
    public void Wait() { owner.Sleep(); }

    /// The same with a deadline. Returns false if the time ran out -- and the
    /// lock is held either way, because the predicate still has to be checked.
    public bool WaitFor(ulong milliseconds) { return owner.SleepFor(milliseconds); }

    /// Wakes one waiter. It cannot run until this guard is dropped.
    public void Pulse() { owner.Wake(); }

    /// Wakes every waiter. Use it when more than one could make progress, or
    /// when waiters are waiting for different conditions on the same value.
    public void PulseAll() { owner.WakeAll(); }
}

// ------------------------------------------------------- reader/writer locks

/// A value that many may read at once, or one may write.
///
/// Worth it only when reads greatly outnumber writes and each one is long
/// enough to pay for the extra bookkeeping -- a reader/writer lock is slower
/// uncontended than a plain mutex. Reach for `Mutex<T>` first and change to
/// this when a measurement says to.
///
/// **A reader cannot upgrade to a writer.** Neither platform's primitive
/// offers it, and neither should: two readers upgrading at once is a deadlock
/// with no way out. Drop the read guard, take a write guard, and re-check what
/// you read -- it may have changed in between.
[Shared]
public class RwLock<T> {
    T value;
    byte* handle;

    public RwLock(T initial) {
        value = initial;
        handle = sl_rwlock_new();
    }

    ~RwLock() { sl_rwlock_free(handle); }

    /// Blocks until no writer holds the lock. Other readers are welcome.
    public ReadGuard<T> Read() {
        sl_rwlock_read_lock(handle);
        return new ReadGuard<T>(this);
    }

    public ReadGuard<T>? TryRead() {
        if (sl_rwlock_try_read_lock(handle)) { return new ReadGuard<T>(this); }
        return null;
    }

    /// Blocks until nothing holds the lock at all.
    public WriteGuard<T> Write() {
        sl_rwlock_write_lock(handle);
        return new WriteGuard<T>(this);
    }

    public WriteGuard<T>? TryWrite() {
        if (sl_rwlock_try_write_lock(handle)) { return new WriteGuard<T>(this); }
        return null;
    }

    T Held() { return value; }
    void Store(T updated) { value = updated; }
    void ReadUnlock() { sl_rwlock_read_unlock(handle); }
    void WriteUnlock() { sl_rwlock_write_unlock(handle); }
}

/// Shared access. There is no `Set`, which is the point.
public class ReadGuard<T> {
    RwLock<T> owner;

    ReadGuard(RwLock<T> held) { owner = held; }

    ~ReadGuard() { owner.ReadUnlock(); }

    public T Value() { return owner.Held(); }
}

/// Exclusive access.
public class WriteGuard<T> {
    RwLock<T> owner;

    WriteGuard(RwLock<T> held) { owner = held; }

    ~WriteGuard() { owner.WriteUnlock(); }

    public T Value() { return owner.Held(); }

    public void Set(T updated) { owner.Store(updated); }
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

    /// Bitwise, for a set of flags several threads maintain. Each returns the
    /// new value, as `Add` does.
    public long And(long mask) { return sl_atomic_and(&cell, mask); }

    public long Or(long mask) { return sl_atomic_or(&cell, mask); }

    public long Xor(long mask) { return sl_atomic_xor(&cell, mask); }
}

/// The same counter in 32 bits, for a cell that has to stay an `int` -- one
/// shared with C, usually. Prefer `AtomicLong` when the width is your choice:
/// it is the same speed on any machine this targets and cannot wrap in
/// practice.
[Shared]
public class AtomicInt {
    int cell;

    public AtomicInt(int initial) { cell = initial; }

    public int Load() { return sl_atomic_load32(&cell); }

    public void Store(int value) { sl_atomic_store32(&cell, value); }

    public int Add(int delta) { return sl_atomic_add32(&cell, delta); }

    public int Increment() { return sl_atomic_add32(&cell, 1); }

    public int Decrement() { return sl_atomic_add32(&cell, -1); }

    public int Exchange(int value) { return sl_atomic_exchange32(&cell, value); }

    public bool CompareExchange(int expected, int desired) {
        int witness = expected;
        return sl_atomic_compare_exchange32(&cell, &witness, desired);
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

// ----------------------------------------------------------------- signals

/// A permit counter: `Wait` takes one and blocks while there are none,
/// `Release` puts one back.
///
/// A semaphore with one permit is a mutex you can unlock from a different
/// thread than locked it, which is occasionally what you want and usually a
/// sign that `Mutex<T>` was the right answer. Its real use is a limit -- at
/// most eight downloads at once, at most one writer per file.
[Shared]
public class Semaphore {
    long permits;
    byte* handle;
    byte* signal;

    public Semaphore(long initial) {
        permits = initial;
        handle = sl_mutex_new();
        signal = sl_condition_new();
    }

    ~Semaphore() {
        sl_condition_free(signal);
        sl_mutex_free(handle);
    }

    /// Blocks until a permit is available, and takes it.
    public void Wait() {
        sl_mutex_lock(handle);
        while (permits <= 0) { sl_condition_wait(signal, handle); }
        permits -= 1;
        sl_mutex_unlock(handle);
    }

    /// Takes a permit only if one is free right now.
    public bool TryWait() {
        sl_mutex_lock(handle);
        bool took = permits > 0;
        if (took) { permits -= 1; }
        sl_mutex_unlock(handle);
        return took;
    }

    /// Blocks for at most `milliseconds`. Returns whether it got a permit.
    public bool WaitFor(ulong milliseconds) {
        sl_mutex_lock(handle);

        // Re-checked in a loop because a spurious wake and a real one look the
        // same, and because another thread may take the permit first.
        while (permits <= 0) {
            if (!sl_condition_wait_for(signal, handle, milliseconds)) {
                sl_mutex_unlock(handle);
                return false;
            }
        }

        permits -= 1;
        sl_mutex_unlock(handle);
        return true;
    }

    /// Puts one permit back and wakes a waiter.
    public void Release() { ReleaseMany(1); }

    /// Puts several back at once, waking as many waiters as could proceed.
    public void ReleaseMany(long count) {
        sl_mutex_lock(handle);
        permits += count;
        if (count == 1) { sl_condition_signal(signal); }
        else { sl_condition_broadcast(signal); }
        sl_mutex_unlock(handle);
    }

    /// How many permits are free. A snapshot, and stale the moment you have it.
    public long Available() {
        sl_mutex_lock(handle);
        long count = permits;
        sl_mutex_unlock(handle);
        return count;
    }
}

/// A latch that stays open once opened: every waiter passes, and every later
/// `Wait` returns at once until something calls `Reset`.
///
/// "Is the server up yet" is the shape it fits.
[Shared]
public class ManualResetEvent {
    bool open;
    byte* handle;
    byte* signal;

    public ManualResetEvent(bool signalled) {
        open = signalled;
        handle = sl_mutex_new();
        signal = sl_condition_new();
    }

    ~ManualResetEvent() {
        sl_condition_free(signal);
        sl_mutex_free(handle);
    }

    public void Wait() {
        sl_mutex_lock(handle);
        while (!open) { sl_condition_wait(signal, handle); }
        sl_mutex_unlock(handle);
    }

    public bool WaitFor(ulong milliseconds) {
        sl_mutex_lock(handle);
        while (!open) {
            if (!sl_condition_wait_for(signal, handle, milliseconds)) {
                bool passed = open;
                sl_mutex_unlock(handle);
                return passed;
            }
        }
        sl_mutex_unlock(handle);
        return true;
    }

    /// Opens the latch and releases everybody waiting.
    public void Set() {
        sl_mutex_lock(handle);
        open = true;
        sl_condition_broadcast(signal);
        sl_mutex_unlock(handle);
    }

    /// Closes it again, so the next `Wait` blocks.
    public void Reset() {
        sl_mutex_lock(handle);
        open = false;
        sl_mutex_unlock(handle);
    }

    public bool IsSet() {
        sl_mutex_lock(handle);
        bool state = open;
        sl_mutex_unlock(handle);
        return state;
    }
}

/// A turnstile: `Set` lets exactly one waiter through, and closes behind it.
///
/// A signal with no waiter is remembered, so the next `Wait` passes straight
/// away -- one signal, one pass, whichever order they happen in. A second
/// `Set` before anyone waits is *not* remembered, which is the difference
/// between this and a `Semaphore`.
[Shared]
public class AutoResetEvent {
    bool ready;
    byte* handle;
    byte* signal;

    public AutoResetEvent(bool signalled) {
        ready = signalled;
        handle = sl_mutex_new();
        signal = sl_condition_new();
    }

    ~AutoResetEvent() {
        sl_condition_free(signal);
        sl_mutex_free(handle);
    }

    public void Wait() {
        sl_mutex_lock(handle);
        while (!ready) { sl_condition_wait(signal, handle); }
        ready = false;
        sl_mutex_unlock(handle);
    }

    public bool WaitFor(ulong milliseconds) {
        sl_mutex_lock(handle);
        while (!ready) {
            if (!sl_condition_wait_for(signal, handle, milliseconds)) {
                if (!ready) {
                    sl_mutex_unlock(handle);
                    return false;
                }
            }
        }
        ready = false;
        sl_mutex_unlock(handle);
        return true;
    }

    /// Lets one waiter through, or arms the next one.
    public void Set() {
        sl_mutex_lock(handle);
        ready = true;
        sl_condition_signal(signal);
        sl_mutex_unlock(handle);
    }
}

/// Counts down to zero, and opens when it gets there.
///
/// The join half of fork-join, for work that `parallel` cannot bracket --
/// jobs handed to threads that outlive the function that started them.
/// Inside a `parallel` block the closing brace already does this.
[Shared]
public class CountdownEvent {
    long remaining;
    byte* handle;
    byte* signal;

    public CountdownEvent(long count) {
        remaining = count;
        handle = sl_mutex_new();
        signal = sl_condition_new();
    }

    ~CountdownEvent() {
        sl_condition_free(signal);
        sl_mutex_free(handle);
    }

    /// Counts one off. Returns true if that was the last one.
    public bool Signal() {
        sl_mutex_lock(handle);

        if (remaining > 0) { remaining -= 1; }
        bool done = remaining == 0;
        if (done) { sl_condition_broadcast(signal); }

        sl_mutex_unlock(handle);
        return done;
    }

    /// Adds work before it is started. Adding after the count reaches zero is
    /// a race nobody wins, so it is refused rather than reopening the latch.
    public bool TryAddCount(long count) {
        sl_mutex_lock(handle);
        bool added = remaining > 0;
        if (added) { remaining += count; }
        sl_mutex_unlock(handle);
        return added;
    }

    public void Wait() {
        sl_mutex_lock(handle);
        while (remaining > 0) { sl_condition_wait(signal, handle); }
        sl_mutex_unlock(handle);
    }

    public bool WaitFor(ulong milliseconds) {
        sl_mutex_lock(handle);
        while (remaining > 0) {
            if (!sl_condition_wait_for(signal, handle, milliseconds)) {
                bool done = remaining == 0;
                sl_mutex_unlock(handle);
                return done;
            }
        }
        sl_mutex_unlock(handle);
        return true;
    }

    public long CurrentCount() {
        sl_mutex_lock(handle);
        long count = remaining;
        sl_mutex_unlock(handle);
        return count;
    }
}

/// A rendezvous a fixed number of threads reach together, over and over.
///
/// Every participant calls `SignalAndWait`; none returns until all have
/// arrived, and then the barrier re-arms for the next round. Phase-by-phase
/// simulation is what it is for -- everyone finishes step N before anyone
/// starts step N+1.
///
/// The phase number is what makes it reusable: a thread released from round 3
/// that loops straight back in cannot be counted into round 3 a second time,
/// because the number it is waiting on has already moved.
[Shared]
public class Barrier {
    nuint participants;
    nuint waiting;
    long phase;
    byte* handle;
    byte* signal;

    public Barrier(nuint count) {
        participants = count;
        waiting = 0u;
        phase = 0;
        handle = sl_mutex_new();
        signal = sl_condition_new();
    }

    ~Barrier() {
        sl_condition_free(signal);
        sl_mutex_free(handle);
    }

    /// Blocks until every participant has arrived. Returns the number of the
    /// phase that just finished.
    public long SignalAndWait() {
        sl_mutex_lock(handle);

        long round = phase;
        waiting += 1u;

        if (waiting >= participants) {
            waiting = 0u;
            phase += 1;
            sl_condition_broadcast(signal);
            sl_mutex_unlock(handle);
            return round;
        }

        while (phase == round) { sl_condition_wait(signal, handle); }

        sl_mutex_unlock(handle);
        return round;
    }

    public nuint ParticipantCount() { return participants; }
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

// ------------------------------------------------------------------ threads

/// One OS thread, started and joinable.
///
/// This is the unstructured option, and it is deliberately second: `parallel`
/// and `spawn` cover the common case with no handle to lose, no join to
/// forget, and a compiler check that a job cannot outlive the frame it
/// borrows. Reach for a `Thread` when the work has no lexical scope -- a
/// listener that runs for the life of the program, a background writer draining
/// a queue.
///
/// **The ownership rule is different, and it is the whole difference.** A
/// `spawn`ed job *borrows* the parent's frame, which is sound because the
/// closing brace cannot be passed until the job has finished. A thread has no
/// such brace, so whatever it touches has to outlive it: a `[Shared]` object
/// held in a `static readonly`, or a block the thread frees itself. Passing a
/// pointer to a local and returning is a use-after-free the compiler does not
/// yet catch.
///
/// **The destructor joins.** A `Thread` that goes out of scope unjoined blocks
/// there until its thread finishes, which is C++'s `jthread` and is the safe
/// default: the alternative is a thread still running against storage that has
/// gone. Say `Detach()` when you mean to let it run loose.
public class Thread {
    byte* handle;

    /// Starts a thread running `body(argument)`. Stainless has no static
    /// methods -- a module is the static class -- so the constructor is the
    /// place this goes.
    public Thread(Job body, byte* argument) {
        handle = sl_thread_start(body, argument);
    }

    /// Waits for it to finish. Doing it twice is harmless, which is what lets
    /// the destructor be a backstop.
    public void Join() {
        if (handle != null) {
            sl_thread_join(handle);
            handle = null;
        }
    }

    /// Gives up the handle without waiting. The thread runs on and cleans up
    /// after itself; nothing can join it afterwards.
    public void Detach() {
        if (handle != null) {
            sl_thread_detach(handle);
            handle = null;
        }
    }

    /// Whether this handle still refers to a thread -- false after `Join` or
    /// `Detach`. It does not say whether the thread is still running.
    public bool IsJoinable() { return handle != null; }

    ~Thread() { Join(); }
}

/// Stops the calling thread for at least this long. It may be longer: this is
/// the scheduler's floor, not a timer.
public void Sleep(ulong milliseconds) { sl_thread_sleep(milliseconds); }

/// Offers the rest of this thread's slice to anything else that is ready.
public void Yield() { sl_thread_yield(); }

/// An identifier for the calling thread, unique among those running. It is the
/// OS's number and means nothing across a restart.
public nuint CurrentId() { return sl_thread_current_id(); }

/// Backs off in a loop that is waiting for something another core will do very
/// soon -- spinning at first, then yielding once it is clear this will take a
/// while.
///
/// Spinning is right only when the wait is shorter than a context switch, and
/// wrong every other time. If what you are waiting on takes a lock, does I/O,
/// or might not happen at all, use a `Monitor` or an event and let the
/// scheduler have the core back.
///
///     var spin = new SpinWait();
///     while (!ready.Load()) { spin.Once(); }
public class SpinWait {
    nuint spins;

    public SpinWait() { spins = 0u; }

    /// One step of backing off.
    public void Once() {
        spins += 1u;

        // Ten pause instructions before the first yield, then a yield every
        // time: long enough for a neighbouring core to finish a short critical
        // section, short enough not to burn a slice on anything longer.
        if (spins <= 10u) {
            sl_cpu_pause();
            return;
        }

        sl_thread_yield();
    }

    /// How many times `Once` has been called.
    public nuint Count() { return spins; }

    /// Starts over, for a loop that is being reused.
    public void Reset() { spins = 0u; }
}

// -------------------------------------------------------------------- pool

/// How many threads the pool is running. Zero until the first scope starts it.
public nuint WorkerCount() { return sl_pool_worker_count(); }

/// How many hardware threads the machine reports.
public nuint ProcessorCount() { return sl_cpu_count(); }

/// Starts the pool with a chosen number of workers, before any scope does it
/// automatically. Passing zero sizes it from the processor count.
public void StartPool(nuint workers) { sl_pool_start(workers); }
