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
    ///
    /// @param milliseconds  how long to wait at most, measured from the call rather than from
    ///                      the last wake
    public bool WaitFor(ulong milliseconds)
    {
        long deadline = ComputeDeadlineAfter(milliseconds);
        sl_mutex_lock(_handle);
        while (!_open)
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

    /// Opens the latch and releases everybody waiting.
    ///
    /// @see ManualResetEvent.Reset
    public void Set()
    {
        sl_mutex_lock(_handle);
        _open = true;
        sl_condition_broadcast(_signal);
        sl_mutex_unlock(_handle);
    }

    /// Closes it again, so the next `Wait` blocks.
    ///
    /// @see ManualResetEvent.Set
    public void Reset()
    {
        sl_mutex_lock(_handle);
        _open = false;
        sl_mutex_unlock(_handle);
    }

    /// Whether the latch is open *now*. `Reset` can close it before you act
    /// on the answer, so this is for reporting rather than for deciding.
    public bool IsSet
    {
        get
        {
            sl_mutex_lock(_handle);
            bool state = _open;
            sl_mutex_unlock(_handle);
            return state;
        }
    }
}
