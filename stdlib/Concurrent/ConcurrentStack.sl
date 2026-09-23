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

// ------------------------------------------------------------------- stack

/// A last-in, first-out stack several threads may use at once.
///
/// @typeparam T  what the stack holds; nothing is required of it, and nothing yet checks that
///               two threads may safely hold one at once
public threadsafe class ConcurrentStack<T>
{
    Stack<T> _items;
    byte* _gate;

    /// An empty stack, with its own mutex.
    public ConcurrentStack()
    {
        _items = new Stack<T>();
        _gate = sl_mutex_new();
    }

    ~ConcurrentStack() { sl_mutex_free(_gate); }

    /// Adds to the top. Never waits for a consumer -- the stack is unbounded.
    public void Push(T item)
    {
        sl_mutex_lock(_gate);
        _items.Push(item);
        sl_mutex_unlock(_gate);
    }

    /// Takes the top item if there is one. The answer and the item come back
    /// together, because asking whether it is empty and then popping would
    /// race with every other thread.
    public Optional<T> TryPop()
    {
        sl_mutex_lock(_gate);

        if (_items.IsEmpty)
        {
            sl_mutex_unlock(_gate);
            return None;
        }

        var item = _items.Pop();
        sl_mutex_unlock(_gate);
        return Some(item);
    }

    /// Takes the top item, or `fallback` when there is none. A sentinel will
    /// do here only if `fallback` is a value the stack cannot hold; `TryPop`
    /// is the one that tells the two apart.
    public T PopOrDefault(T fallback)
    {
        sl_mutex_lock(_gate);

        if (_items.IsEmpty)
        {
            sl_mutex_unlock(_gate);
            return fallback;
        }

        var item = _items.Pop();
        sl_mutex_unlock(_gate);
        return item;
    }

    /// How many items there are *now*. For reporting rather than for
    /// deciding: another thread may change it before you act on it.
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

    /// Whether it is empty *now*, with the same caveat as `Count`.
    public bool IsEmpty => Count == 0;

    /// A snapshot, top first. Consistent with itself, and out of date the
    /// moment it is returned.
    public List<T> ToList()
    {
        sl_mutex_lock(_gate);
        var copy = _items.ToList();
        sl_mutex_unlock(_gate);
        return copy;
    }
}
