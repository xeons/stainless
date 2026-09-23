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
    ///
    /// @param milliseconds  how long to wait at most, measured from the call rather than from
    ///                      the last wake
    public bool WaitFor(ulong milliseconds)
    {
        long deadline = ComputeDeadlineAfter(milliseconds);
        sl_mutex_lock(_handle);
        while (!_ready)
        {
            if (!WaitBeforeDeadline(_signal, _handle, deadline))
            {
                sl_mutex_unlock(_handle);
                return false;
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
