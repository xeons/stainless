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
    ///
    /// @see AtomicLong.CompareExchange
    public long Read() => sl_atomic_load(&_cell);

    /// Overwrites the value, losing whatever was there. `Exchange` is the one
    /// that tells you what it replaced.
    ///
    /// @see AtomicLong.Exchange
    public void Write(long value) => sl_atomic_store(&_cell, value);

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
    ///
    /// @param mask  the bits to keep; every bit outside it is cleared
    public long And(long mask) => sl_atomic_and(&_cell, mask);

    /// Sets the bits in `mask`, returning the new value.
    public long Or(long mask) => sl_atomic_or(&_cell, mask);

    /// Flips the bits in `mask`, returning the new value.
    public long Xor(long mask) => sl_atomic_xor(&_cell, mask);
}
