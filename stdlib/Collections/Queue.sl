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

module Standard.Collections;

// ------------------------------------------------------------------- queue

/// First in, first out, over a circular buffer.
///
/// `Enqueue` and `Dequeue` are both constant time, and neither moves the other
/// items -- which is the whole reason not to use a `List<T>` and remove from
/// the front of it.
///
/// @typeparam T  what the queue holds; nothing is asked of it
public class Queue<T> : IEnumerable<T>
{
    T[] _items;
    T[] _blank;
    nuint _head;
    nuint _count;

    /// An empty queue with room for a few items before it first grows.
    public Queue()
    {
        _items = new T[8];
        _blank = new T[1];
        _head = 0;
        _count = 0;
    }

    /// How many items are waiting. O(1).
    public nuint Count => _count;

    /// True when there is nothing to dequeue. Check this before `Dequeue` or
    /// `Peek`, both of which abort on an empty queue.
    ///
    /// @see Queue.Dequeue
    /// @seealso Queue.Peek
    public bool IsEmpty => _count == 0;

    /// The number of slots the ring has. Always a power of two, so wrapping is
    /// a mask rather than a division.
    public nuint Capacity => _items.Length;

    /// Adds to the back, growing the ring when it is full.
    ///
    /// Constant time, and amortised constant when it grows. Growing moves
    /// every item once, which is the only time anything is copied.
    ///
    /// @see Queue.Dequeue
    public void Enqueue(T item)
    {
        if (_count == _items.Length)
            GrowStorage();
        _items[(_head + _count) & (_items.Length - 1)] = item;
        _count++;
    }

    /// Removes and returns the oldest item. Aborts when the queue is empty.
    ///
    /// @see Queue.Enqueue
    /// @seealso Queue.Peek
    public T Dequeue()
    {
        if (_count == 0)
            sl_fail("Queue.Dequeue: the queue is empty");

        var item = _items[_head];

        // Blanked rather than left behind, so a reference is released now and
        // not when the slot is eventually written over.
        _items[_head] = _blank[0];
        _head = (_head + 1) & (_items.Length - 1);
        _count--;
        return item;
    }

    /// The oldest item, without removing it. Aborts when the queue is empty.
    ///
    /// @see Queue.Dequeue
    public T Peek()
    {
        if (_count == 0)
            sl_fail("Queue.Peek: the queue is empty");
        return _items[_head];
    }

    /// Drops everything. The ring is replaced rather than blanked, so
    /// anything it held is released now.
    public void Clear()
    {
        _items = new T[8];
        _head = 0;
        _count = 0;
    }

    /// The items, oldest first.
    ///
    /// @see Queue.GetEnumerator
    public List<T> ToList()
    {
        var result = new List<T>();
        for (nuint i = 0; i < _count; i++)
        {
            result.Add(_items[(_head + i) & (_items.Length - 1)]);
        }
        return result;
    }

    /// The item `index` places behind the front, counting from zero. Used by
    /// the cursor; a queue is not an indexable thing in its own right.
    T GetItemAt(nuint index) => _items[(_head + index) & (_items.Length - 1)];

    /// A cursor over the items, oldest first, for `foreach`. Walks the ring
    /// in place rather than copying, unlike `ToList`. Enqueueing or dequeueing
    /// during a walk invalidates it.
    ///
    /// @see QueueEnumerator
    /// @seealso Queue.ToList
    public IEnumerator<T> GetEnumerator() => new QueueEnumerator<T>(this);

    void GrowStorage()
    {
        var bigger = new T[_items.Length * 2];
        for (nuint i = 0; i < _count; i++)
        {
            bigger[i] = _items[(_head + i) & (_items.Length - 1)];
        }
        _items = bigger;
        _head = 0;
    }
}
