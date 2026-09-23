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

/// A rendezvous a fixed number of threads reach together, over and over.
///
/// Every participant calls `SignalAndWait`; none returns until all have
/// arrived, and then the barrier re-arms for the next round. Phase-by-phase
/// simulation is what it is for -- everyone finishes step N before anyone
/// starts step N+1.
///
/// The phase number is what makes it reusable: a thread released from round 3
/// that loops straight back in cannot be counted into round 3 a second time,
/// because the number it is waiting on has already moved.
public threadsafe class Barrier
{
    nuint _participants;
    nuint _waiting;
    long _phase;
    byte* _handle;
    byte* _signal;

    /// A barrier for exactly `count` participants.
    ///
    /// The number is fixed for the life of the barrier. Fewer threads than
    /// that calling `SignalAndWait` blocks all of them for ever, which is the
    /// failure to look for when a phase never ends.
    public Barrier(nuint count)
    {
        _participants = count;
        _waiting = 0u;
        _phase = 0;
        _handle = sl_mutex_new();
        _signal = sl_condition_new();
    }

    ~Barrier()
    {
        sl_condition_free(_signal);
        sl_mutex_free(_handle);
    }

    /// Blocks until every participant has arrived. Returns the number of the
    /// phase that just finished.
    public long SignalAndWait()
    {
        sl_mutex_lock(_handle);

        long round = _phase;
        _waiting++;

        if (_waiting >= _participants)
        {
            _waiting = 0u;
            _phase++;
            sl_condition_broadcast(_signal);
            sl_mutex_unlock(_handle);
            return round;
        }

        while (_phase == round)
            sl_condition_wait(_signal, _handle);

        sl_mutex_unlock(_handle);
        return round;
    }

    /// How many participants the barrier was made for. Fixed, so unlike most
    /// readings here it cannot be stale.
    public nuint ParticipantCount => _participants;
}
