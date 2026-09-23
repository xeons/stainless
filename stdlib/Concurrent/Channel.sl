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

// ---------------------------------------------------------------- hand-off

/// A queue whose taker waits rather than spinning: the producer-consumer
/// hand-off.
///
/// `Take` blocks until something arrives or the channel is closed, which is
/// what separates this from `ConcurrentQueue`. Closing is how consumers are
/// told there will be no more: every waiter wakes, what was already sent is
/// still delivered, and once it is drained every `Take` returns at once with
/// `None`.
///
///     var channel = new Channel<String>();
///     // producer:  channel.Add(line);  ... channel.Close();
///     // consumer:  while (channel.Take() is Some got) { Handle(got.Value); }
///
/// @typeparam T  what is sent through it; nothing is required of it, and nothing yet checks
///               that the sender is done with what it sent
public threadsafe class Channel<T>
{
    Queue<T> _items;
    byte* _gate;
    byte* _arrived;
    bool _closed;

    /// An open, empty channel. Unbounded: `Send` never blocks waiting for a
    /// consumer, so a producer that outruns its consumers grows the queue
    /// rather than being slowed by it.
    public Channel()
    {
        _items = new Queue<T>();
        _gate = sl_mutex_new();
        _arrived = sl_condition_new();
        _closed = false;
    }

    ~Channel()
    {
        sl_condition_free(_arrived);
        sl_mutex_free(_gate);
    }

    /// Adds an item and wakes one waiter. Adding to a closed channel changes
    /// nothing and reports false.
    public bool Add(T item)
    {
        sl_mutex_lock(_gate);

        if (_closed)
        {
            sl_mutex_unlock(_gate);
            return false;
        }

        _items.Enqueue(item);
        sl_condition_signal(_arrived);
        sl_mutex_unlock(_gate);
        return true;
    }

    /// Waits for an item. Answers `None` once the channel is closed and
    /// drained, and not before.
    public Optional<T> Take()
    {
        sl_mutex_lock(_gate);

        // A wait can return without a signal, so the condition is re-tested in
        // a loop rather than assumed. That is true of every condition variable
        // on every platform.
        while (_items.IsEmpty && !_closed)
        {
            sl_condition_wait(_arrived, _gate);
        }

        if (_items.IsEmpty)
        {
            sl_mutex_unlock(_gate);
            return None;
        }

        var item = _items.Dequeue();
        sl_mutex_unlock(_gate);
        return Some(item);
    }

    /// Takes an item if one is there already, without waiting.
    public Optional<T> TryTake()
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

    /// Says there will be no more, and wakes everyone waiting. Idempotent.
    public void Close()
    {
        sl_mutex_lock(_gate);
        _closed = true;
        sl_condition_broadcast(_arrived);
        sl_mutex_unlock(_gate);
    }

    /// Whether `Close` has been called. A closed channel may still have items
    /// in it: this answers whether more can be sent, not whether more can be
    /// taken. What `Take` answers with is what says that.
    public bool IsClosed
    {
        get
        {
            sl_mutex_lock(_gate);
            bool result = _closed;
            sl_mutex_unlock(_gate);
            return result;
        }
    }

    /// How many items are waiting *now* -- the producer's backlog. For
    /// reporting rather than for deciding; a consumer should call `Take`.
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
}
