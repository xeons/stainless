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

/// Queues, stacks, linked lists and sorted maps.
///
/// All four are backed by arrays, which is not the usual choice for the last
/// two. It is the right one here: ARC cannot collect a cycle, so a doubly linked
/// list of objects would leak unless every back-link were weak, and a weak
/// reference is not usable without a way to prove it is still there. Links as
/// indices into a pool have neither problem, and are faster besides.
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
    /// @see QueueCursor
    /// @seealso Queue.ToList
    public IEnumerator<T> GetEnumerator() => new QueueCursor<T>(this);

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

// ------------------------------------------------------------------- stack

/// Last in, first out. The top is the end of the array, so nothing moves.
///
/// @typeparam T  what the stack holds; nothing is asked of it
public class Stack<T> : IEnumerable<T>
{
    T[] _items;
    T[] _blank;
    nuint _count;

    /// An empty stack with room for a few items before it first grows.
    public Stack()
    {
        _items = new T[8];
        _blank = new T[1];
        _count = 0;
    }

    /// How many items are on the stack. O(1).
    public nuint Count => _count;

    /// True when there is nothing to pop. Check this before `Pop` or `Peek`,
    /// both of which abort on an empty stack.
    ///
    /// @see Stack.Pop
    /// @seealso Stack.Peek
    public bool IsEmpty => _count == 0;

    /// The number of slots the backing array has.
    public nuint Capacity => _items.Length;

    /// Pushes onto the top, growing when full. Amortised constant time.
    ///
    /// @see Stack.Pop
    public void Push(T item)
    {
        if (_count == _items.Length)
            GrowStorage();
        _items[_count] = item;
        _count++;
    }

    /// Removes and returns the top. Aborts when the stack is empty.
    ///
    /// @see Stack.Push
    /// @seealso Stack.Peek
    public T Pop()
    {
        if (_count == 0)
            sl_fail("Stack.Pop: the stack is empty");

        _count--;
        var item = _items[_count];
        _items[_count] = _blank[0];
        return item;
    }

    /// The top, without removing it. Aborts when the stack is empty.
    ///
    /// @see Stack.Pop
    public T Peek()
    {
        if (_count == 0)
            sl_fail("Stack.Peek: the stack is empty");
        return _items[_count - 1];
    }

    /// Drops everything. The array is replaced rather than blanked, so
    /// anything it held is released now.
    public void Clear()
    {
        _items = new T[8];
        _count = 0;
    }

    /// The items, top first, which is the order they would be popped in.
    ///
    /// @see Stack.GetEnumerator
    public List<T> ToList()
    {
        var result = new List<T>();
        for (nuint i = 0; i < _count; i++)
            result.Add(_items[_count - 1 - i]);
        return result;
    }

    /// The item `depth` places below the top, counting from zero.
    T GetItemFromTop(nuint depth) => _items[_count - 1 - depth];

    /// A cursor over the items, top first -- the order `Pop` would give them
    /// back in. Pushing or popping during a walk invalidates it.
    ///
    /// @see StackCursor
    /// @seealso Stack.ToList
    public IEnumerator<T> GetEnumerator() => new StackCursor<T>(this);

    void GrowStorage()
    {
        var bigger = new T[_items.Length * 2];
        for (nuint i = 0; i < _count; i++)
            bigger[i] = _items[i];
        _items = bigger;
    }
}

// ------------------------------------------------------------- linked list

/// A doubly linked list whose links are indices into a pool rather than
/// references.
///
/// A node is named by a **handle**: a `nint` that stays valid until that node is
/// removed, and is `-1` for "no node". Handles are what make the middle of the
/// list reachable in constant time, which is the only reason to choose this
/// over a `List<T>`:
///
/// ```csharp
/// var line = new LinkedList<String>();
/// var first = line.AddLast("a");
/// line.AddLast("c");
/// line.InsertAfter(first, "b");
///
/// for (nint at = line.First; at >= 0; at = line.GetNext(at)) {
///     Console.WriteLine(line.GetValueAt(at));
/// }
/// ```
///
/// Removed nodes are recycled, so a list that is added to and removed from
/// steadily does not grow without bound.
///
/// @typeparam T  what a node holds; nothing is asked of it, and a node is
///               named by its handle rather than by its value
public class LinkedList<T> : IEnumerable<T>
{
    T[] _items;
    nint[] _next;
    nint[] _previous;
    T[] _blank;

    nint _head;
    nint _tail;
    nint _free;          // head of the chain of recycled nodes, through `next`
    nuint _used;         // how much of the pool has ever been handed out
    nuint _count;

    /// An empty list with a small pool, grown as nodes are needed.
    public LinkedList()
    {
        _items = new T[8];
        _next = new nint[8];
        _previous = new nint[8];
        _blank = new T[1];
        _head = -1;
        _tail = -1;
        _free = -1;
        _used = 0;
        _count = 0;
    }

    /// How many nodes are linked in. O(1), and not the size of the pool --
    /// recycled slots are not counted.
    public nuint Count => _count;

    /// True when nothing is linked in.
    public bool IsEmpty => _count == 0;

    /// A handle to the first node, or -1 when the list is empty.
    ///
    /// @see LinkedList.Last
    public nint First => _head;

    /// A handle to the last node, or -1 when the list is empty.
    ///
    /// @see LinkedList.First
    public nint Last => _tail;

    /// The node after `handle`, or -1 at the end.
    ///
    /// @see LinkedList.GetPrevious
    public nint GetNext(nint handle) => _next[(nuint)handle];

    /// The node before `handle`, or -1 at the start.
    ///
    /// @see LinkedList.GetNext
    public nint GetPrevious(nint handle) => _previous[(nuint)handle];

    /// The value in a node.
    ///
    /// `handle` must be live: one this list handed out and has not had
    /// `RemoveAt` called on. A stale or `-1` handle is not checked and reads
    /// whatever the pool slot now holds, so test `at >= 0` before walking.
    ///
    /// @see LinkedList.SetValueAt
    public T GetValueAt(nint handle) => _items[(nuint)handle];

    /// Replaces the value in a node, leaving the links alone. Same
    /// requirement on `handle` as `GetValueAt`.
    ///
    /// @see LinkedList.GetValueAt
    public void SetValueAt(nint handle, T value) => _items[(nuint)handle] = value;

    /// Links a new node at the front and answers its handle. Constant time.
    ///
    /// @see LinkedList.AddLast
    /// @seealso LinkedList.RemoveFirst
    public nint AddFirst(T item)
    {
        nint node = AllocateNode(item);

        _next[(nuint)node] = _head;
        _previous[(nuint)node] = -1;

        if (_head >= 0)
        {
            _previous[(nuint)_head] = node;
        }
        else
        {
            _tail = node;
        }

        _head = node;
        _count++;
        return node;
    }

    /// Links a new node at the back and answers its handle. Constant time --
    /// the tail is kept, so this does not walk the list.
    ///
    /// @see LinkedList.AddFirst
    /// @seealso LinkedList.RemoveLast
    public nint AddLast(T item)
    {
        nint node = AllocateNode(item);

        _previous[(nuint)node] = _tail;
        _next[(nuint)node] = -1;

        if (_tail >= 0)
        {
            _next[(nuint)_tail] = node;
        }
        else
        {
            _head = node;
        }

        _tail = node;
        _count++;
        return node;
    }

    /// Links a new node just after `handle` and answers its handle. Constant
    /// time, and the reason to choose this over a `List<T>`. Inserting after
    /// the last node appends.
    ///
    /// @see LinkedList.InsertBefore
    public nint InsertAfter(nint handle, T item)
    {
        nint after = _next[(nuint)handle];
        if (after < 0)
            return AddLast(item);

        nint node = AllocateNode(item);
        _previous[(nuint)node] = handle;
        _next[(nuint)node] = after;
        _next[(nuint)handle] = node;
        _previous[(nuint)after] = node;

        _count++;
        return node;
    }

    /// Links a new node just before `handle` and answers its handle.
    /// Inserting before the first node prepends.
    ///
    /// @see LinkedList.InsertAfter
    public nint InsertBefore(nint handle, T item)
    {
        nint before = _previous[(nuint)handle];
        if (before < 0)
            return AddFirst(item);
        return InsertAfter(before, item);
    }

    /// Unlinks a node and recycles its slot. The handle is dead afterwards.
    ///
    /// @see LinkedList.RemoveFirst
    /// @seealso LinkedList.RemoveLast
    public void RemoveAt(nint handle)
    {
        nuint at = (nuint)handle;
        nint before = _previous[at];
        nint after = _next[at];

        if (before >= 0)
        {
            _next[(nuint)before] = after;
        }
        else
        {
            _head = after;
        }
        if (after >= 0)
        {
            _previous[(nuint)after] = before;
        }
        else
        {
            _tail = before;
        }

        _items[at] = _blank[0];
        _previous[at] = -1;
        _next[at] = _free;
        _free = handle;
        _count--;
    }

    /// Removes and returns the first item. Aborts when the list is empty.
    ///
    /// @see LinkedList.AddFirst
    /// @seealso LinkedList.RemoveLast
    public T RemoveFirst()
    {
        if (_head < 0)
            sl_fail("LinkedList.RemoveFirst: the list is empty");

        var item = _items[(nuint)_head];
        RemoveAt(_head);
        return item;
    }

    /// Removes and returns the last item. Aborts when the list is empty.
    ///
    /// @see LinkedList.AddLast
    public T RemoveLast()
    {
        if (_tail < 0)
            sl_fail("LinkedList.RemoveLast: the list is empty");

        var item = _items[(nuint)_tail];
        RemoveAt(_tail);
        return item;
    }

    /// Drops every node and the pool with it. Every handle previously handed
    /// out is dead afterwards.
    public void Clear()
    {
        _items = new T[8];
        _next = new nint[8];
        _previous = new nint[8];
        _head = -1;
        _tail = -1;
        _free = -1;
        _used = 0;
        _count = 0;
    }

    /// The values, head first, as a fresh list. O(n), following the links.
    ///
    /// @see LinkedList.GetEnumerator
    public List<T> ToList()
    {
        var result = new List<T>();
        for (nint at = _head; at >= 0; at = _next[(nuint)at])
            result.Add(_items[(nuint)at]);
        return result;
    }

    /// The three a cursor needs to walk the links. A node is an index into the
    /// pool, and -1 is the end -- which is why these are nint and not nuint.
    nint FirstNode => _head;
    nint GetNodeAfter(nint node) => _next[(nuint)node];
    T GetNodeValue(nint node) => _items[(nuint)node];

    /// A cursor over the values, head first, for `foreach`. Follows the links
    /// and keeps its place, so a whole walk is O(n). Adding or removing during
    /// a walk invalidates it.
    ///
    /// @see LinkedListCursor
    public IEnumerator<T> GetEnumerator() => new LinkedListCursor<T>(this);

    /// A slot for one more node: a recycled one if there is one, else the next
    /// unused one, growing the pool when it runs out.
    nint AllocateNode(T item)
    {
        if (_free >= 0)
        {
            nint node = _free;
            _free = _next[(nuint)node];
            _items[(nuint)node] = item;
            return node;
        }

        if (_used == _items.Length)
            GrowPool();

        nint fresh = (nint)_used;
        _used++;
        _items[(nuint)fresh] = item;
        return fresh;
    }

    void GrowPool()
    {
        nuint size = _items.Length * 2;

        var biggerItems = new T[size];
        var biggerNext = new nint[size];
        var biggerPrevious = new nint[size];

        for (nuint i = 0; i < _used; i++)
        {
            biggerItems[i] = _items[i];
            biggerNext[i] = _next[i];
            biggerPrevious[i] = _previous[i];
        }

        _items = biggerItems;
        _next = biggerNext;
        _previous = biggerPrevious;
    }
}

// ------------------------------------------------------------- sorted list

/// A map kept in key order, over two parallel arrays.
///
/// Lookup is a binary search and iteration is in order, which is what a
/// `Dictionary` cannot do. Insertion moves the tail of the arrays, so this is
/// for maps that are read far more than they are written -- a lookup table
/// built once, rather than a counter updated in a loop.
///
/// @typeparam TKey    what an entry is found by, and what the order is over:
///                    comparable, since a lookup is a binary search
/// @typeparam TValue  what an entry holds; nothing is asked of it
/// @see Dictionary
public class SortedList<TKey, TValue> : IEnumerable<Pair<TKey, TValue>> where TKey : IComparable<TKey>
{
    TKey[] _keys;
    TValue[] _values;
    nuint _count;

    /// An empty map with room for a few entries before it first grows.
    public SortedList()
    {
        _keys = new TKey[8];
        _values = new TValue[8];
        _count = 0;
    }

    /// How many entries there are. O(1).
    public nuint Count => _count;

    /// True when there are no entries.
    public bool IsEmpty => _count == 0;

    /// The index `key` is at, or the index it would be inserted at, negated and
    /// offset by one so the two cases stay apart: a result below zero means
    /// "not found, and `-result - 1` is where it goes".
    ///
    /// @see SortedList.Find
    public nint IndexOfKey(TKey key)
    {
        nuint low = 0;
        nuint high = _count;

        while (low < high)
        {
            nuint middle = low + (high - low) / 2;
            int order = _keys[middle].CompareTo(key);

            if (order == 0)
                return (nint)middle;
            if (order < 0)
            {
                low = middle + 1;
            }
            else
            {
                high = middle;
            }
        }

        return -((nint)low) - 1;
    }

    /// Whether `key` is there. A binary search, O(log n). Reach for `Find`
    /// when the value is what is wanted, rather than searching twice.
    ///
    /// @see SortedList.Find
    public bool ContainsKey(TKey key) => IndexOfKey(key) >= 0;

    /// The key at a position in the ordering, counting from the smallest.
    ///
    /// @see SortedList.GetValueAt
    public TKey GetKeyAt(nuint index)
    {
        if (index >= _count)
            sl_array_bounds_fail(index, _count);
        return _keys[index];
    }

    /// The value at a position in the ordering, paired with `GetKeyAt` at the
    /// same index. Aborts past the end.
    ///
    /// @see SortedList.GetKeyAt
    public TValue GetValueAt(nuint index)
    {
        if (index >= _count)
            sl_array_bounds_fail(index, _count);
        return _values[index];
    }

    /// The value for `key`, or `None` when there is none. The one to reach
    /// for, for the reason `Dictionary.Find` gives: a key is data, so a key
    /// that is not there is an outcome rather than a mistake.
    ///
    /// @see SortedList.GetValue
    /// @seealso SortedList.GetValueOrDefault
    public Optional<TValue> Find(TKey key)
    {
        nint at = IndexOfKey(key);
        if (at < 0)
            return None;
        return Some(_values[(nuint)at]);
    }

    /// The value for `key`, aborting when there is none.
    ///
    /// The asserting form, for a key that is there by construction. `Find` is
    /// the question where it might not be, and `GetValueOrDefault` where a default will do.
    ///
    /// @see SortedList.Find
    /// @seealso SortedList.GetValueOrDefault
    public TValue GetValue(TKey key)
    {
        nint at = IndexOfKey(key);
        if (at < 0)
            sl_fail("SortedList.GetValue: no such key");
        return _values[(nuint)at];
    }

    /// The value for `key`, or `fallback` when there is none.
    ///
    /// Allocates nothing, at the cost of not distinguishing an absent key from
    /// one whose stored value equals the fallback. `Find` is the one that
    /// tells them apart.
    ///
    /// @see SortedList.Find
    public TValue GetValueOrDefault(TKey key, TValue fallback)
    {
        nint at = IndexOfKey(key);
        if (at < 0)
            return fallback;
        return _values[(nuint)at];
    }

    /// Sets the value of a key, adding it in order if it is new.
    ///
    /// An existing key costs a search. A new one costs the search plus a shift
    /// of everything after it -- O(n) -- which is what makes this collection a
    /// poor choice for a map that is written in a loop.
    ///
    /// @see SortedList.Remove
    public void SetValue(TKey key, TValue value)
    {
        nint at = IndexOfKey(key);
        if (at >= 0)
        {
            _values[(nuint)at] = value;
            return;
        }

        nuint slot = (nuint)(-at - 1);
        if (_count == _keys.Length)
            GrowStorage();

        // Shift the tail up by one. Counted down from the end so that no slot
        // is written before it has been copied.
        for (nuint i = _count; i > slot; i--)
        {
            _keys[i] = _keys[i - 1];
            _values[i] = _values[i - 1];
        }

        _keys[slot] = key;
        _values[slot] = value;
        _count++;
    }

    /// Removes a key, answering whether it was there. Closes the gap, so it
    /// is O(n) like `SetValue` on a new key.
    ///
    /// @see SortedList.SetValue
    public bool Remove(TKey key)
    {
        nint at = IndexOfKey(key);
        if (at < 0)
            return false;

        for (nuint i = (nuint)at; i + 1 < _count; i++)
        {
            _keys[i] = _keys[i + 1];
            _values[i] = _values[i + 1];
        }

        _count--;

        // The vacated slot still refers to the last entry; blanking it releases
        // that reference now rather than at the next insertion.
        var noKeys = new TKey[1];
        var noValues = new TValue[1];
        _keys[_count] = noKeys[0];
        _values[_count] = noValues[0];
        return true;
    }

    /// Drops every entry. The arrays are replaced rather than blanked, so
    /// anything they held is released now.
    public void Clear()
    {
        _keys = new TKey[8];
        _values = new TValue[8];
        _count = 0;
    }

    /// Every key, smallest first, as a fresh list.
    ///
    /// @see SortedList.GetValues
    public List<TKey> GetKeys()
    {
        var result = new List<TKey>();
        for (nuint i = 0; i < _count; i++)
            result.Add(_keys[i]);
        return result;
    }

    /// Every value, in key order, pairing with `GetKeys` position for position.
    ///
    /// @see SortedList.GetKeys
    public List<TValue> GetValues()
    {
        var result = new List<TValue>();
        for (nuint i = 0; i < _count; i++)
            result.Add(_values[i]);
        return result;
    }

    /// The entry at a position, in key order. What the cursor walks.
    Pair<TKey, TValue> GetPairAt(nuint index) => new Pair<TKey, TValue>(_keys[index], _values[index]);

    /// A cursor over the entries in key order, for `foreach` -- the ordering
    /// a `Dictionary` cannot give. One `Pair` is built per step. Writing to
    /// the map during a walk invalidates it.
    ///
    /// @see SortedListCursor
    public IEnumerator<Pair<TKey, TValue>> GetEnumerator()
    {
        return new SortedListCursor<TKey, TValue>(this);
    }

    void GrowStorage()
    {
        var biggerKeys = new TKey[_keys.Length * 2];
        var biggerValues = new TValue[_values.Length * 2];

        for (nuint i = 0; i < _count; i++)
        {
            biggerKeys[i] = _keys[i];
            biggerValues[i] = _values[i];
        }

        _keys = biggerKeys;
        _values = biggerValues;
    }
}

/// Walks a queue oldest first, without copying it.
///
/// The materialising version this replaced built a whole `List<T>` before the
/// first `MoveNext`, so iterating a queue allocated as much again as the queue
/// held. A cursor over the ring costs nothing.
///
/// @typeparam T  the element type of the queue being walked
/// @see Queue.GetEnumerator
public class QueueCursor<T> : IEnumerator<T>
{
    Queue<T> _source;
    nuint _next;

    /// A cursor over `queue`, positioned before the oldest item.
    public QueueCursor(Queue<T> queue)
    {
        _source = queue;
        _next = 0;
    }

    /// Advances, answering false at the end.
    public bool MoveNext()
    {
        if (_next >= _source.Count)
            return false;
        _next++;
        return true;
    }

    /// The item the last `MoveNext` landed on.
    public T Current => _source.GetItemAt(_next - 1);
}

/// Walks a stack top first, matching the order `Pop` would hand things back.
///
/// @typeparam T  the element type of the stack being walked
/// @see Stack.GetEnumerator
public class StackCursor<T> : IEnumerator<T>
{
    Stack<T> _source;
    nuint _next;

    /// A cursor over `stack`, positioned above the top.
    public StackCursor(Stack<T> stack)
    {
        _source = stack;
        _next = 0;
    }

    /// Advances towards the bottom, answering false at the end.
    public bool MoveNext()
    {
        if (_next >= _source.Count)
            return false;
        _next++;
        return true;
    }

    /// The item the last `MoveNext` landed on.
    public T Current => _source.GetItemFromTop(_next - 1);
}

/// Walks a linked list head first, following the links rather than flattening
/// them. `At` is O(n) from the head, so a cursor that used it would make
/// iterating O(n squared); this keeps the node it reached.
///
/// @typeparam T  the value type of the list being walked
/// @see LinkedList.GetEnumerator
public class LinkedListCursor<T> : IEnumerator<T>
{
    LinkedList<T> _source;
    nint _at;
    bool _started;

    /// A cursor over `list`, positioned before the head.
    public LinkedListCursor(LinkedList<T> list)
    {
        _source = list;
        _at = -1;
        _started = false;
    }

    /// Follows one link, answering false past the tail.
    public bool MoveNext()
    {
        if (!_started)
        {
            _started = true;
            _at = _source.FirstNode;
        }
        else if (_at >= 0)
        {
            _at = _source.GetNodeAfter(_at);
        }

        return _at >= 0;
    }

    /// The value in the node the last `MoveNext` reached.
    public T Current => _source.GetNodeValue(_at);
}

/// Walks a sorted list in key order.
///
/// One `Pair` is built per step, as the materialising version built one per
/// entry before the walk began -- the difference is that a loop that stops
/// early now stops allocating too.
///
/// @typeparam TKey    the key type of the map being walked, comparable as that
///                    map requires
/// @typeparam TValue  its value type
/// @see SortedList.GetEnumerator
public class SortedListCursor<TKey, TValue> : IEnumerator<Pair<TKey, TValue>> where TKey : IComparable<TKey>
{
    SortedList<TKey, TValue> _source;
    nuint _next;

    /// A cursor over `list`, positioned before the smallest key.
    public SortedListCursor(SortedList<TKey, TValue> list)
    {
        _source = list;
        _next = 0;
    }

    /// Advances to the next key in order, answering false at the end.
    public bool MoveNext()
    {
        if (_next >= _source.Count)
            return false;
        _next++;
        return true;
    }

    /// The entry the last `MoveNext` landed on, as a freshly built `Pair`.
    public Pair<TKey, TValue> Current => _source.GetPairAt(_next - 1);
}
