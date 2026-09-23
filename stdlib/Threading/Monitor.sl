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
///     var held = queue.Enter();
///     while (held.Value.IsEmpty) { held.Wait(); }
///     var item = held.Value.Dequeue();
///
/// @typeparam T  what the monitor guards, and what a waiter's condition is about
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
    public MonitorGuard<T> Enter()
    {
        sl_mutex_lock(_handle);
        return new MonitorGuard<T>(this);
    }

    // Reached through a MonitorGuard, which is the only thing holding the lock.
    T ReadValue() => _value;
    void WriteValue(T updated) => _value = updated;
    void Exit() => sl_mutex_unlock(_handle);
    void WaitForSignal() => sl_condition_wait(_signal, _handle);
    bool WaitForSignalFor(ulong milliseconds)
    {
        return sl_condition_wait_for(_signal, _handle, milliseconds);
    }
    void SignalOne() => sl_condition_signal(_signal);
    void SignalAll() => sl_condition_broadcast(_signal);
}
