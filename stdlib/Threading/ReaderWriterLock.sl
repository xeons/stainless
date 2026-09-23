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
///
/// @typeparam T  what the lock guards. Nothing is required of it, and nothing stops a reader
///               mutating one through `ReadGuard.Value`; see the note there.
public threadsafe class ReaderWriterLock<T>
{
    T _value;
    byte* _handle;

    /// A lock holding `initial`, unheld.
    public ReaderWriterLock(T initial)
    {
        _value = initial;
        _handle = sl_rwlock_new();
    }

    ~ReaderWriterLock() { sl_rwlock_free(_handle); }

    /// Blocks until no writer holds the lock. Other readers are welcome.
    public ReadGuard<T> EnterReadLock()
    {
        sl_rwlock_read_lock(_handle);
        return new ReadGuard<T>(this);
    }

    /// Takes a read guard only if no writer holds the lock. Answers null
    /// rather than blocking.
    public ReadGuard<T>? TryEnterReadLock()
    {
        if (sl_rwlock_try_read_lock(_handle))
            return new ReadGuard<T>(this);
        return null;
    }

    /// Blocks until nothing holds the lock at all.
    public WriteGuard<T> EnterWriteLock()
    {
        sl_rwlock_write_lock(_handle);
        return new WriteGuard<T>(this);
    }

    /// Takes a write guard only if nothing holds the lock at all. Answers
    /// null rather than blocking.
    public WriteGuard<T>? TryEnterWriteLock()
    {
        if (sl_rwlock_try_write_lock(_handle))
            return new WriteGuard<T>(this);
        return null;
    }

    T Held => _value;
    void StoreValue(T updated) => _value = updated;
    void ExitReadLock() => sl_rwlock_read_unlock(_handle);
    void ExitWriteLock() => sl_rwlock_write_unlock(_handle);
}
