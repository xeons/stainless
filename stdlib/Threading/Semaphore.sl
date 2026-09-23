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
    ///
    /// @see Semaphore.Release
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
            _permits--;
        sl_mutex_unlock(_handle);
        return took;
    }

    /// Blocks for at most `milliseconds`. Returns whether it got a permit.
    ///
    /// @param milliseconds  how long to wait at most. The deadline is taken once, so a wake
    ///                      that finds no permit does not start the wait again.
    public bool WaitFor(ulong milliseconds)
    {
        long deadline = ComputeDeadlineAfter(milliseconds);
        sl_mutex_lock(_handle);

        // Re-checked in a loop because a spurious wake and a real one look the
        // same, and because another thread may take the permit first. A waiter
        // whose time is up still takes a permit that is there, so a wake sent
        // to it is not lost.
        while (_permits <= 0)
        {
            if (!WaitBeforeDeadline(_signal, _handle, deadline))
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
    ///
    /// @see Semaphore.Wait
    public void Release() => Release(1);

    /// Puts several back at once, waking as many waiters as could proceed.
    public void Release(long count)
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
    public long CurrentCount
    {
        get
        {
            sl_mutex_lock(_handle);
            long count = _permits;
            sl_mutex_unlock(_handle);
            return count;
        }
    }
}
