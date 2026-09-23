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

    /// Counts one off. Returns true if that was the last one, and false for a
    /// signal after the count had already reached zero.
    ///
    /// @see CountdownEvent.Wait
    public bool Signal()
    {
        sl_mutex_lock(_handle);

        bool done = false;
        if (_remaining > 0)
        {
            _remaining--;
            done = _remaining == 0;
            if (done)
                sl_condition_broadcast(_signal);
        }

        sl_mutex_unlock(_handle);
        return done;
    }

    /// Adds work before it is started. Adding after the count reaches zero is
    /// a race nobody wins, so it is refused rather than reopening the latch.
    ///
    /// A negative `count` counts that many off at once, stopping at zero and
    /// opening the latch there as `Signal` would.
    public bool TryAddCount(long count)
    {
        sl_mutex_lock(_handle);
        bool added = _remaining > 0;
        if (added)
        {
            if (count < 0 && count <= -_remaining)
            {
                _remaining = 0;
                sl_condition_broadcast(_signal);
            }
            else
            {
                _remaining += count;
            }
        }
        sl_mutex_unlock(_handle);
        return added;
    }

    /// Blocks until the count reaches zero. Every waiter passes, and a later
    /// `Wait` returns at once -- the latch does not re-arm.
    ///
    /// The calling thread blocks rather than helping: this is not a `parallel`
    /// block, so there is no queue for it to work off.
    ///
    /// @see CountdownEvent.Signal
    public void Wait()
    {
        sl_mutex_lock(_handle);
        while (_remaining > 0)
            sl_condition_wait(_signal, _handle);
        sl_mutex_unlock(_handle);
    }

    /// The same with a deadline. Answers whether the count reached zero.
    ///
    /// @param milliseconds  how long to wait at most, measured from the call rather than from
    ///                      the last wake
    public bool WaitFor(ulong milliseconds)
    {
        long deadline = ComputeDeadlineAfter(milliseconds);
        sl_mutex_lock(_handle);
        while (_remaining > 0)
        {
            if (!WaitBeforeDeadline(_signal, _handle, deadline))
            {
                sl_mutex_unlock(_handle);
                return false;
            }
        }
        sl_mutex_unlock(_handle);
        return true;
    }

    /// How many signals are still outstanding. A snapshot, and stale the
    /// moment you have it.
    public long CurrentCount
    {
        get
        {
            sl_mutex_lock(_handle);
            long count = _remaining;
            sl_mutex_unlock(_handle);
            return count;
        }
    }
}
