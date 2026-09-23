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
    /// @see LinkedListEnumerator
    public IEnumerator<T> GetEnumerator() => new LinkedListEnumerator<T>(this);

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
