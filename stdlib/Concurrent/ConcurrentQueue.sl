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

module Standard.Concurrent;

import Standard.Collections;
import Standard.Threading;

// ------------------------------------------------------------------- queue

/// A first-in, first-out queue several threads may use at once.
///
/// @typeparam T  what the queue holds; nothing is required of it, and nothing yet checks that
///               two threads may safely hold one at once
public threadsafe class ConcurrentQueue<T>
{
    Queue<T> _items;
    byte* _gate;

    /// An empty queue, with its own mutex. The mutex is freed when the queue
    /// is, so there is nothing to dispose.
    public ConcurrentQueue()
    {
        _items = new Queue<T>();
        _gate = sl_mutex_new();
    }

    ~ConcurrentQueue() { sl_mutex_free(_gate); }

    /// Adds to the back. Blocks only for as long as the lock is held, which is
    /// the enqueue itself; there is no bound on the queue, so this never waits
    /// for a consumer.
    public void Enqueue(T item)
    {
        sl_mutex_lock(_gate);
        _items.Enqueue(item);
        sl_mutex_unlock(_gate);
    }

    /// Takes the front item if there is one. The answer and the item come back
    /// together, because asking twice would race.
    public Optional<T> TryDequeue()
    {
        sl_mutex_lock(_gate);

        if (_items.IsEmpty)
        {
            sl_mutex_unlock(_gate);
            return None;
        }

        var item = _items.Dequeue();
        sl_mutex_unlock(_gate);
        return Some(item);
    }

    /// Takes the front item, or `fallback` when there is none. `TryDequeue`
    /// for the caller that must tell an empty queue from a stored `fallback`.
    public T DequeueOrDefault(T fallback)
    {
        sl_mutex_lock(_gate);

        if (_items.IsEmpty)
        {
            sl_mutex_unlock(_gate);
            return fallback;
        }

        var item = _items.Dequeue();
        sl_mutex_unlock(_gate);
        return item;
    }

    /// How many items there are *now*. Another thread may change it before you
    /// act on it, so this is for reporting rather than for deciding.
    public nuint Count
    {
        get
        {
            sl_mutex_lock(_gate);
            nuint result = _items.Count;
            sl_mutex_unlock(_gate);
            return result;
        }
    }

    /// Whether it is empty *now*. Another thread may enqueue before you act on
    /// the answer, so a true here does not mean the next `TryDequeue` fails.
    /// Reach for `TryDequeue` and match on what it answers instead.
    public bool IsEmpty => Count == 0;

    /// A snapshot, oldest first. Consistent with itself, and out of date the
    /// moment it is returned.
    public List<T> ToList()
    {
        sl_mutex_lock(_gate);
        var copy = _items.ToList();
        sl_mutex_unlock(_gate);
        return copy;
    }
}
