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

/// Proof that a monitor is held, and the only route to what it guards.
///
/// @typeparam T  what the monitor guards, taken from the monitor rather than chosen here
public class MonitorGuard<T>
{
    Monitor<T> _owner;

    MonitorGuard(Monitor<T> held) => _owner = held;

    ~MonitorGuard() { _owner.Exit(); }

    /// What the monitor guards, with the same lifetime caveat as `Guard`.
    public T Value => _owner.ReadValue();

    /// Replaces the guarded value. Pulse afterwards if anyone is waiting on a
    /// condition this changed -- nothing wakes on its own.
    public void SetValue(T updated) => _owner.WriteValue(updated);

    /// Releases the lock, waits for a pulse, and takes the lock again. Call it
    /// in a loop that re-checks what you are waiting for.
    public void Wait() => _owner.WaitForSignal();

    /// The same with a deadline. Returns false if the time ran out -- and the
    /// lock is held either way, because the predicate still has to be checked.
    ///
    /// **True means the wait did not time out, not that a pulse arrived.** A
    /// spurious wake reports success, which is the other reason the predicate
    /// is checked in a loop rather than read once.
    ///
    /// @param milliseconds  how long to wait for, from now
    public bool WaitFor(ulong milliseconds) => _owner.WaitForSignalFor(milliseconds);

    /// Wakes one waiter. It cannot run until this guard is dropped.
    public void Pulse() => _owner.SignalOne();

    /// Wakes every waiter. Use it when more than one could make progress, or
    /// when waiters are waiting for different conditions on the same value.
    public void PulseAll() => _owner.SignalAll();
}
