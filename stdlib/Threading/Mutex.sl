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

module Standard.Threading;

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
///     var guard = registry.Enter();
///     guard.Value.Add(name);
///     // ~Guard() unlocks here
///
/// **Known hole.** `Value` hands out what the lock protects, and nothing yet
/// stops you storing it somewhere and using it after the guard has gone. C#
/// has the same hole and worse; Rust closes it with lifetimes. Stainless
/// closes it when the analysis in step 6 of docs/concurrency.md lands, and not
/// before. Until then this is a discipline, not a guarantee.
///
/// It used to be unsound for a class `T`: `Value` retains what it hands out
/// and the caller releases it, often outside the lock, so two threads performed
/// an unsynchronized read-modify-write on that object's count. The count drifted
/// down and the object was freed while the mutex still held it. Reference counts
/// are atomic now, which closes that; what remains is the lifetime hole above,
/// which is about how long a borrowed thing lives rather than about counting.
///
/// @typeparam T  what the lock guards. Nothing is required of it: safety comes from the lock
///               rather than from the type, and a `T` reached any other way is unguarded.
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
    /// Keep the result in a variable. `registry.Enter();` on its own locks and
    /// then immediately unlocks, because the guard is a temporary and dies at
    /// the end of the statement.
    ///
    /// @see Mutex.TryEnter
    public Guard<T> Enter()
    {
        sl_mutex_lock(_handle);
        return new Guard<T>(this);
    }

    /// Takes the lock only if it is free. Returns null rather than blocking.
    ///
    /// @see Mutex.Enter
    public Guard<T>? TryEnter()
    {
        if (sl_mutex_try_lock(_handle))
            return new Guard<T>(this);
        return null;
    }

    // Reached through a Guard, which is the only thing that holds the lock.
    T ReadValue() => _value;
    void WriteValue(T updated) => _value = updated;
    void Exit() => sl_mutex_unlock(_handle);
}
