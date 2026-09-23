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
    public int Read() => sl_atomic_load32(&_cell);

    /// Overwrites the value, losing whatever was there.
    public void Write(int value) => sl_atomic_store32(&_cell, value);

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
