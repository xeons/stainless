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

/// Backs off in a loop that is waiting for something another core will do very
/// soon -- spinning at first, then yielding once it is clear this will take a
/// while.
///
/// Spinning is right only when the wait is shorter than a context switch, and
/// wrong every other time. If what you are waiting on takes a lock, does I/O,
/// or might not happen at all, use a `Monitor` or an event and let the
/// scheduler have the core back.
///
///     var spin = new SpinWait();
///     while (!ready.Read()) { spin.SpinOnce(); }
public class SpinWait
{
    nuint _spins;

    /// A fresh backoff, having spun zero times.
    public SpinWait() => _spins = 0u;

    /// One step of backing off.
    public void SpinOnce()
    {
        _spins++;

        // Ten pause instructions before the first yield, then a yield every
        // time: long enough for a neighbouring core to finish a short critical
        // section, short enough not to burn a slice on anything longer.
        if (_spins <= 10u)
        {
            sl_cpu_pause();
            return;
        }

        sl_thread_yield();
    }

    /// How many times `SpinOnce` has been called.
    public nuint Count => _spins;

    /// Starts over, for a loop that is being reused.
    public void Reset() => _spins = 0u;
}
