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
public threadsafe class Mutex<T>
{
    T _value;
    byte* _handle;

    /// A mutex holding `initial`, unlocked. The value goes in here and comes
    /// out only through a guard; there is no way to hand it over afterwards.
    public Mutex(T initial)
    {
        _value = initial;
        _handle = sl_mutex_new();
    }

    ~Mutex() { sl_mutex_free(_handle); }

    /// Blocks until the lock is free, then returns the guard that holds it.
    ///
    /// Keep the result in a variable. `registry.Lock();` on its own locks and
    /// then immediately unlocks, because the guard is a temporary and dies at
    /// the end of the statement.
    public Guard<T> Lock()
    {
        sl_mutex_lock(_handle);
        return new Guard<T>(this);
    }

    /// Takes the lock only if it is free. Returns null rather than blocking.
    public Guard<T>? TryLock()
    {
        if (sl_mutex_try_lock(_handle))
            return new Guard<T>(this);
        return null;
    }

    // Reached through a Guard, which is the only thing that holds the lock.
    T Read() => _value;
    void Write(T updated) => _value = updated;
    void Unlock() => sl_mutex_unlock(_handle);
}

/// Proof that a lock is held, and the only route to what it guards.
///
/// A guard keeps its mutex alive, so the lock cannot be freed while it is
/// held. Releasing is the destructor's job; there is no `Unlock` to forget.
public class Guard<T>
{
    Mutex<T> _owner;

    Guard(Mutex<T> held) => _owner = held;

    ~Guard() { _owner.Unlock(); }

    /// What the lock guards.
    ///
    /// See the hole described on `Mutex`: what this hands back must not
    /// outlive the guard, and nothing yet enforces it.
    public T Value() => _owner.Read();

    /// Replaces the guarded value. For a class `T` this swaps which object is
    /// guarded; mutating the one `Value` gave back is the usual thing.
    public void Set(T updated) => _owner.Write(updated);
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
public threadsafe class Monitor<T>
{
    T _value;
    byte* _handle;
    byte* _signal;

    /// A monitor holding `initial`, unlocked and with nobody waiting.
    public Monitor(T initial)
    {
        _value = initial;
        _handle = sl_mutex_new();
        _signal = sl_condition_new();
    }

    ~Monitor()
    {
        sl_condition_free(_signal);
        sl_mutex_free(_handle);
    }

    /// Blocks until the lock is free. Keep the result in a variable -- a
    /// temporary unlocks at the end of the statement.
    public MonitorGuard<T> Lock()
    {
        sl_mutex_lock(_handle);
        return new MonitorGuard<T>(this);
    }

    // Reached through a MonitorGuard, which is the only thing holding the lock.
    T Read() => _value;
    void Write(T updated) => _value = updated;
    void Unlock() => sl_mutex_unlock(_handle);
    void Sleep() => sl_condition_wait(_signal, _handle);
    bool SleepFor(ulong milliseconds)
    {
        return sl_condition_wait_for(_signal, _handle, milliseconds);
    }
    void Wake() => sl_condition_signal(_signal);
    void WakeAll() => sl_condition_broadcast(_signal);
}

/// Proof that a monitor is held, and the only route to what it guards.
public class MonitorGuard<T>
{
    Monitor<T> _owner;

    MonitorGuard(Monitor<T> held) => _owner = held;

    ~MonitorGuard() { _owner.Unlock(); }

    /// What the monitor guards, with the same lifetime caveat as `Guard`.
    public T Value() => _owner.Read();

    /// Replaces the guarded value. Pulse afterwards if anyone is waiting on a
    /// condition this changed -- nothing wakes on its own.
    public void Set(T updated) => _owner.Write(updated);

    /// Releases the lock, waits for a pulse, and takes the lock again. Call it
    /// in a loop that re-checks what you are waiting for.
    public void Wait() => _owner.Sleep();

    /// The same with a deadline. Returns false if the time ran out -- and the
    /// lock is held either way, because the predicate still has to be checked.
    public bool WaitFor(ulong milliseconds) => _owner.SleepFor(milliseconds);

    /// Wakes one waiter. It cannot run until this guard is dropped.
    public void Pulse() => _owner.Wake();

    /// Wakes every waiter. Use it when more than one could make progress, or
    /// when waiters are waiting for different conditions on the same value.
    public void PulseAll() => _owner.WakeAll();
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
public threadsafe class RwLock<T>
{
    T _value;
    byte* _handle;

    /// A lock holding `initial`, unheld.
    public RwLock(T initial)
    {
        _value = initial;
        _handle = sl_rwlock_new();
    }

    ~RwLock() { sl_rwlock_free(_handle); }

    /// Blocks until no writer holds the lock. Other readers are welcome.
    public ReadGuard<T> Read()
    {
        sl_rwlock_read_lock(_handle);
        return new ReadGuard<T>(this);
    }

    /// Takes a read guard only if no writer holds the lock. Answers null
    /// rather than blocking.
    public ReadGuard<T>? TryRead()
    {
        if (sl_rwlock_try_read_lock(_handle))
            return new ReadGuard<T>(this);
        return null;
    }

    /// Blocks until nothing holds the lock at all.
    public WriteGuard<T> Write()
    {
        sl_rwlock_write_lock(_handle);
        return new WriteGuard<T>(this);
    }

    /// Takes a write guard only if nothing holds the lock at all. Answers
    /// null rather than blocking.
    public WriteGuard<T>? TryWrite()
    {
        if (sl_rwlock_try_write_lock(_handle))
            return new WriteGuard<T>(this);
        return null;
    }

    T Held() => _value;
    void Store(T updated) => _value = updated;
    void ReadUnlock() => sl_rwlock_read_unlock(_handle);
    void WriteUnlock() => sl_rwlock_write_unlock(_handle);
}

/// Shared access. There is no `Set`, which is the point.
public class ReadGuard<T>
{
    RwLock<T> _owner;

    ReadGuard(RwLock<T> held) => _owner = held;

    ~ReadGuard() { _owner.ReadUnlock(); }

    /// What the lock guards, shared with every other reader. Treat it as
    /// read-only: nothing stops a `T` with mutating methods being mutated
    /// through this, and doing so races with the other readers.
    public T Value() => _owner.Held();
}

/// Exclusive access.
public class WriteGuard<T>
{
    RwLock<T> _owner;

    WriteGuard(RwLock<T> held) => _owner = held;

    ~WriteGuard() { _owner.WriteUnlock(); }

    /// What the lock guards, exclusively. Safe to mutate through.
    public T Value() => _owner.Held();

    /// Replaces the guarded value.
    public void Set(T updated) => _owner.Store(updated);
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
public threadsafe class AtomicLong
{
    long _cell;

    /// A counter starting at `initial`.
    public AtomicLong(long initial) => _cell = initial;

    /// The value now. A read of a moving counter is stale the moment it is
    /// returned, so this is for reporting; `Add` and `CompareExchange` are
    /// what a decision is built on.
    public long Load() => sl_atomic_load(&_cell);

    /// Overwrites the value, losing whatever was there. `Exchange` is the one
    /// that tells you what it replaced.
    public void Store(long value) => sl_atomic_store(&_cell, value);

    /// Adds and returns the new value, so two threads never see the same result.
    public long Add(long delta) => sl_atomic_add(&_cell, delta);

    /// Adds one and returns the new value, so two threads never see the same
    /// number. Note that this is not C's `++`, which answers the old one.
    public long Increment() => sl_atomic_add(&_cell, 1);

    /// Subtracts one and returns the new value. A reference count reaching
    /// zero is exactly one thread's result.
    public long Decrement() => sl_atomic_add(&_cell, -1);

    /// Stores `value` and returns what was there before.
    public long Exchange(long value) => sl_atomic_exchange(&_cell, value);

    /// Stores `desired` only if the current value is `expected`, and reports
    /// whether it did. The building block for anything lock-free.
    public bool CompareExchange(long expected, long desired)
    {
        long witness = expected;
        return sl_atomic_compare_exchange(&_cell, &witness, desired);
    }

    /// Bitwise, for a set of flags several threads maintain. Each returns the
    /// new value, as `Add` does.
    public long And(long mask) => sl_atomic_and(&_cell, mask);

    /// Sets the bits in `mask`, returning the new value.
    public long Or(long mask) => sl_atomic_or(&_cell, mask);

    /// Flips the bits in `mask`, returning the new value.
    public long Xor(long mask) => sl_atomic_xor(&_cell, mask);
}

/// The same counter in 32 bits, for a cell that has to stay an `int` -- one
/// shared with C, usually. Prefer `AtomicLong` when the width is your choice:
/// it is the same speed on any machine this targets and cannot wrap in
/// practice.
public threadsafe class AtomicInt
{
    int _cell;

    /// A counter starting at `initial`.
    public AtomicInt(int initial) => _cell = initial;

    /// The value now, stale the moment it is returned.
    public int Load() => sl_atomic_load32(&_cell);

    /// Overwrites the value, losing whatever was there.
    public void Store(int value) => sl_atomic_store32(&_cell, value);

    /// Adds and returns the new value. Wraps at 32 bits, silently, which is
    /// the reason to prefer `AtomicLong` where the width is a free choice.
    public int Add(int delta) => sl_atomic_add32(&_cell, delta);

    /// Adds one and returns the new value.
    public int Increment() => sl_atomic_add32(&_cell, 1);

    /// Subtracts one and returns the new value.
    public int Decrement() => sl_atomic_add32(&_cell, -1);

    /// Stores `value` and returns what was there before.
    public int Exchange(int value) => sl_atomic_exchange32(&_cell, value);

    /// Stores `desired` only if the current value is `expected`, and reports
    /// whether it did. A false answer means somebody else got there first --
    /// re-read and try again, which is the shape of every lock-free loop.
    public bool CompareExchange(int expected, int desired)
    {
        int witness = expected;
        return sl_atomic_compare_exchange32(&_cell, &witness, desired);
    }
}

/// A flag several threads may set and read. One-way latches -- "has this
/// started", "should this stop" -- are what it is for.
public threadsafe class AtomicBool
{
    long _cell;

    /// A flag starting at `initial`.
    public AtomicBool(bool initial)
    {
        _cell = 0;
        if (initial)
            _cell = 1;
    }

    /// The flag now. Cheap enough to read in a spin loop's condition.
    public bool Load() => sl_atomic_load(&_cell) != 0;

    /// Sets the flag, losing whatever it was. `Exchange` is the one to use
    /// when exactly one thread must win.
    public void Store(bool value)
    {
        long raw = 0;
        if (value)
            raw = 1;
        sl_atomic_store(&_cell, raw);
    }

    /// Sets the flag and returns what it was, which is how one thread wins a race.
    public bool Exchange(bool value)
    {
        long raw = 0;
        if (value)
            raw = 1;
        return sl_atomic_exchange(&_cell, raw) != 0;
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
public threadsafe class Semaphore
{
    long _permits;
    byte* _handle;
    byte* _signal;

    /// A semaphore with `initial` permits -- the number of things allowed to
    /// proceed at once. Zero is a valid start, and makes every `Wait` block
    /// until something calls `Release`.
    public Semaphore(long initial)
    {
        _permits = initial;
        _handle = sl_mutex_new();
        _signal = sl_condition_new();
    }

    ~Semaphore()
    {
        sl_condition_free(_signal);
        sl_mutex_free(_handle);
    }

    /// Blocks until a permit is available, and takes it.
    public void Wait()
    {
        sl_mutex_lock(_handle);
        while (_permits <= 0)
            sl_condition_wait(_signal, _handle);
        _permits--;
        sl_mutex_unlock(_handle);
    }

    /// Takes a permit only if one is free right now.
    public bool TryWait()
    {
        sl_mutex_lock(_handle);
        bool took = _permits > 0;
        if (took)
            _permits -= 1;
        sl_mutex_unlock(_handle);
        return took;
    }

    /// Blocks for at most `milliseconds`. Returns whether it got a permit.
    public bool WaitFor(ulong milliseconds)
    {
        sl_mutex_lock(_handle);

        // Re-checked in a loop because a spurious wake and a real one look the
        // same, and because another thread may take the permit first.
        while (_permits <= 0)
        {
            if (!sl_condition_wait_for(_signal, _handle, milliseconds))
            {
                sl_mutex_unlock(_handle);
                return false;
            }
        }

        _permits--;
        sl_mutex_unlock(_handle);
        return true;
    }

    /// Puts one permit back and wakes a waiter.
    public void Release() => ReleaseMany(1);

    /// Puts several back at once, waking as many waiters as could proceed.
    public void ReleaseMany(long count)
    {
        sl_mutex_lock(_handle);
        _permits += count;
        if (count == 1)
        {
            sl_condition_signal(_signal);
        }
        else
        {
            sl_condition_broadcast(_signal);
        }
        sl_mutex_unlock(_handle);
    }

    /// How many permits are free. A snapshot, and stale the moment you have it.
    public long Available()
    {
        sl_mutex_lock(_handle);
        long count = _permits;
        sl_mutex_unlock(_handle);
        return count;
    }
}

/// A latch that stays open once opened: every waiter passes, and every later
/// `Wait` returns at once until something calls `Reset`.
///
/// "Is the server up yet" is the shape it fits.
public threadsafe class ManualResetEvent
{
    bool _open;
    byte* _handle;
    byte* _signal;

    /// A latch, open when `signalled` is true. Start it closed when waiters
    /// must not pass until something has happened.
    public ManualResetEvent(bool signalled)
    {
        _open = signalled;
        _handle = sl_mutex_new();
        _signal = sl_condition_new();
    }

    ~ManualResetEvent()
    {
        sl_condition_free(_signal);
        sl_mutex_free(_handle);
    }

    /// Blocks until the latch is open, and returns at once if it already is.
    /// Every waiter passes -- the latch is not consumed.
    public void Wait()
    {
        sl_mutex_lock(_handle);
        while (!_open)
            sl_condition_wait(_signal, _handle);
        sl_mutex_unlock(_handle);
    }

    /// The same with a deadline. Answers whether the latch was open, so a
    /// false means the time ran out.
    public bool WaitFor(ulong milliseconds)
    {
        sl_mutex_lock(_handle);
        while (!_open)
        {
            if (!sl_condition_wait_for(_signal, _handle, milliseconds))
            {
                bool passed = _open;
                sl_mutex_unlock(_handle);
                return passed;
            }
        }
        sl_mutex_unlock(_handle);
        return true;
    }

    /// Opens the latch and releases everybody waiting.
    public void Set()
    {
        sl_mutex_lock(_handle);
        _open = true;
        sl_condition_broadcast(_signal);
        sl_mutex_unlock(_handle);
    }

    /// Closes it again, so the next `Wait` blocks.
    public void Reset()
    {
        sl_mutex_lock(_handle);
        _open = false;
        sl_mutex_unlock(_handle);
    }

    /// Whether the latch is open *now*. `Reset` can close it before you act
    /// on the answer, so this is for reporting rather than for deciding.
    public bool IsSet()
    {
        sl_mutex_lock(_handle);
        bool state = _open;
        sl_mutex_unlock(_handle);
        return state;
    }
}

/// A turnstile: `Set` lets exactly one waiter through, and closes behind it.
///
/// A signal with no waiter is remembered, so the next `Wait` passes straight
/// away -- one signal, one pass, whichever order they happen in. A second
/// `Set` before anyone waits is *not* remembered, which is the difference
/// between this and a `Semaphore`.
public threadsafe class AutoResetEvent
{
    bool _ready;
    byte* _handle;
    byte* _signal;

    /// A turnstile, armed when `signalled` is true -- so the first `Wait`
    /// passes straight through.
    public AutoResetEvent(bool signalled)
    {
        _ready = signalled;
        _handle = sl_mutex_new();
        _signal = sl_condition_new();
    }

    ~AutoResetEvent()
    {
        sl_condition_free(_signal);
        sl_mutex_free(_handle);
    }

    /// Blocks until the turnstile is armed, then passes and closes it behind.
    /// Exactly one waiter passes per `Set`.
    public void Wait()
    {
        sl_mutex_lock(_handle);
        while (!_ready)
            sl_condition_wait(_signal, _handle);
        _ready = false;
        sl_mutex_unlock(_handle);
    }

    /// The same with a deadline. Answers whether it got through; a false
    /// leaves the turnstile as it found it.
    public bool WaitFor(ulong milliseconds)
    {
        sl_mutex_lock(_handle);
        while (!_ready)
        {
            if (!sl_condition_wait_for(_signal, _handle, milliseconds))
            {
                if (!_ready)
                {
                    sl_mutex_unlock(_handle);
                    return false;
                }
            }
        }
        _ready = false;
        sl_mutex_unlock(_handle);
        return true;
    }

    /// Lets one waiter through, or arms the next one.
    public void Set()
    {
        sl_mutex_lock(_handle);
        _ready = true;
        sl_condition_signal(_signal);
        sl_mutex_unlock(_handle);
    }
}

/// Counts down to zero, and opens when it gets there.
///
/// The join half of fork-join, for work that `parallel` cannot bracket --
/// jobs handed to threads that outlive the function that started them.
/// Inside a `parallel` block the closing brace already does this.
public threadsafe class CountdownEvent
{
    long _remaining;
    byte* _handle;
    byte* _signal;

    /// A latch that opens once `count` things have signalled. A count of zero
    /// starts open, and `TryAddCount` will refuse to reopen it.
    public CountdownEvent(long count)
    {
        _remaining = count;
        _handle = sl_mutex_new();
        _signal = sl_condition_new();
    }

    ~CountdownEvent()
    {
        sl_condition_free(_signal);
        sl_mutex_free(_handle);
    }

    /// Counts one off. Returns true if that was the last one.
    public bool Signal()
    {
        sl_mutex_lock(_handle);

        if (_remaining > 0)
            _remaining -= 1;
        bool done = _remaining == 0;
        if (done)
            sl_condition_broadcast(_signal);

        sl_mutex_unlock(_handle);
        return done;
    }

    /// Adds work before it is started. Adding after the count reaches zero is
    /// a race nobody wins, so it is refused rather than reopening the latch.
    public bool TryAddCount(long count)
    {
        sl_mutex_lock(_handle);
        bool added = _remaining > 0;
        if (added)
            _remaining += count;
        sl_mutex_unlock(_handle);
        return added;
    }

    /// Blocks until the count reaches zero. Every waiter passes, and a later
    /// `Wait` returns at once -- the latch does not re-arm.
    ///
    /// The calling thread blocks rather than helping: this is not a `parallel`
    /// block, so there is no queue for it to work off.
    public void Wait()
    {
        sl_mutex_lock(_handle);
        while (_remaining > 0)
            sl_condition_wait(_signal, _handle);
        sl_mutex_unlock(_handle);
    }

    /// The same with a deadline. Answers whether the count reached zero.
    public bool WaitFor(ulong milliseconds)
    {
        sl_mutex_lock(_handle);
        while (_remaining > 0)
        {
            if (!sl_condition_wait_for(_signal, _handle, milliseconds))
            {
                bool done = _remaining == 0;
                sl_mutex_unlock(_handle);
                return done;
            }
        }
        sl_mutex_unlock(_handle);
        return true;
    }

    /// How many signals are still outstanding. A snapshot, and stale the
    /// moment you have it.
    public long CurrentCount()
    {
        sl_mutex_lock(_handle);
        long count = _remaining;
        sl_mutex_unlock(_handle);
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
public threadsafe class Barrier
{
    nuint _participants;
    nuint _waiting;
    long _phase;
    byte* _handle;
    byte* _signal;

    /// A barrier for exactly `count` participants.
    ///
    /// The number is fixed for the life of the barrier. Fewer threads than
    /// that calling `SignalAndWait` blocks all of them for ever, which is the
    /// failure to look for when a phase never ends.
    public Barrier(nuint count)
    {
        _participants = count;
        _waiting = 0u;
        _phase = 0;
        _handle = sl_mutex_new();
        _signal = sl_condition_new();
    }

    ~Barrier()
    {
        sl_condition_free(_signal);
        sl_mutex_free(_handle);
    }

    /// Blocks until every participant has arrived. Returns the number of the
    /// phase that just finished.
    public long SignalAndWait()
    {
        sl_mutex_lock(_handle);

        long round = _phase;
        _waiting++;

        if (_waiting >= _participants)
        {
            _waiting = 0u;
            _phase++;
            sl_condition_broadcast(_signal);
            sl_mutex_unlock(_handle);
            return round;
        }

        while (_phase == round)
            sl_condition_wait(_signal, _handle);

        sl_mutex_unlock(_handle);
        return round;
    }

    /// How many participants the barrier was made for. Fixed, so unlike most
    /// readings here it cannot be stale.
    public nuint ParticipantCount() => _participants;
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
public class TaskScope
{
    byte* _handle;

    /// Opens a scope. Starts the thread pool if this is the first one, which
    /// is what `StartPool` can do earlier and with a chosen size.
    public TaskScope() => _handle = sl_scope_begin();

    /// Queues a job. It may already be running when this returns.
    public void Run(Job job, byte* argument)
    {
        sl_scope_submit(_handle, job, argument);
    }

    /// Waits for every job submitted so far. Doing it twice is harmless, which
    /// is what lets the destructor be a backstop for a scope nobody joined.
    public void Join()
    {
        if (_handle != null)
        {
            sl_scope_end(_handle);
            _handle = null;
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
/// such brace, so whatever it touches has to outlive it: a `threadsafe` object
/// held in a `static readonly`, or a block the thread frees itself. Passing a
/// pointer to a local and returning is a use-after-free the compiler does not
/// yet catch.
///
/// **The destructor joins.** A `Thread` that goes out of scope unjoined blocks
/// there until its thread finishes, which is C++'s `jthread` and is the safe
/// default: the alternative is a thread still running against storage that has
/// gone. Say `Detach()` when you mean to let it run loose.
public class Thread
{
    byte* _handle;

    /// Starts a thread running `body(argument)`. Stainless has no static
    /// methods -- a module is the static class -- so the constructor is the
    /// place this goes.
    public Thread(Job body, byte* argument)
    {
        _handle = sl_thread_start(body, argument);
    }

    /// Waits for it to finish. Doing it twice is harmless, which is what lets
    /// the destructor be a backstop.
    public void Join()
    {
        if (_handle != null)
        {
            sl_thread_join(_handle);
            _handle = null;
        }
    }

    /// Gives up the handle without waiting. The thread runs on and cleans up
    /// after itself; nothing can join it afterwards.
    public void Detach()
    {
        if (_handle != null)
        {
            sl_thread_detach(_handle);
            _handle = null;
        }
    }

    /// Whether this handle still refers to a thread -- false after `Join` or
    /// `Detach`. It does not say whether the thread is still running.
    public bool IsJoinable() => _handle != null;

    ~Thread() { Join(); }
}

/// Stops the calling thread for at least this long. It may be longer: this is
/// the scheduler's floor, not a timer.
public void Sleep(ulong milliseconds) => sl_thread_sleep(milliseconds);

/// Offers the rest of this thread's slice to anything else that is ready.
public void Yield() => sl_thread_yield();

/// An identifier for the calling thread, unique among those running. It is the
/// OS's number and means nothing across a restart.
public nuint CurrentId() => sl_thread_current_id();

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
public class SpinWait
{
    nuint _spins;

    /// A fresh backoff, having spun zero times.
    public SpinWait() => _spins = 0u;

    /// One step of backing off.
    public void Once()
    {
        _spins++;

        // Ten pause instructions before the first yield, then a yield every
        // time: long enough for a neighbouring core to finish a short critical
        // section, short enough not to burn a slice on anything longer.
        if (_spins <= 10u)
        {
            sl_cpu_pause();
            return;
        }

        sl_thread_yield();
    }

    /// How many times `Once` has been called.
    public nuint Count() => _spins;

    /// Starts over, for a loop that is being reused.
    public void Reset() => _spins = 0u;
}

// -------------------------------------------------------------------- pool

/// How many threads the pool is running. Zero until the first scope starts it.
public nuint WorkerCount() => sl_pool_worker_count();

/// How many hardware threads the machine reports.
public nuint ProcessorCount() => sl_cpu_count();

/// Starts the pool with a chosen number of workers, before any scope does it
/// automatically. Passing zero sizes it from the processor count.
public void StartPool(nuint workers) => sl_pool_start(workers);
