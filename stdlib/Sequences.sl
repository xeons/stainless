// Stainless - an experimental systems language.
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
public class Queue<T> : IEnumerable<T> {
    T[] items;
    T[] blank;
    nuint head;
    nuint count;

    /// An empty queue with room for a few items before it first grows.
    public Queue() {
        items = new T[8];
        blank = new T[1];
        head = 0;
        count = 0;
    }

    /// How many items are waiting. O(1).
    public nuint Count() { return count; }

    /// True when there is nothing to dequeue. Check this before `Dequeue` or
    /// `Peek`, both of which abort on an empty queue.
    public bool IsEmpty() { return count == 0; }

    /// The number of slots the ring has. Always a power of two, so wrapping is
    /// a mask rather than a division.
    public nuint Capacity() { return items.Length; }

    /// Adds to the back, growing the ring when it is full.
    ///
    /// Constant time, and amortised constant when it grows. Growing moves
    /// every item once, which is the only time anything is copied.
    public void Enqueue(T item) {
        if (count == items.Length) { Grow(); }
        items[(head + count) & (items.Length - 1)] = item;
        count++;
    }

    /// Removes and returns the oldest item. Aborts when the queue is empty.
    public T Dequeue() {
        if (count == 0) { sl_fail("Queue.Dequeue: the queue is empty"); }

        var item = items[head];

        // Blanked rather than left behind, so a reference is released now and
        // not when the slot is eventually written over.
        items[head] = blank[0];
        head = (head + 1) & (items.Length - 1);
        count--;
        return item;
    }

    /// The oldest item, without removing it. Aborts when the queue is empty.
    public T Peek() {
        if (count == 0) { sl_fail("Queue.Peek: the queue is empty"); }
        return items[head];
    }

    /// Drops everything. The ring is replaced rather than blanked, so
    /// anything it held is released now.
    public void Clear() {
        items = new T[8];
        head = 0;
        count = 0;
    }

    /// The items, oldest first.
    public List<T> ToList() {
        var result = new List<T>();
        for (nuint i = 0; i < count; i++) {
            result.Add(items[(head + i) & (items.Length - 1)]);
        }
        return result;
    }

    /// The item `index` places behind the front, counting from zero. Used by
    /// the cursor; a queue is not an indexable thing in its own right.
    T At(nuint index) { return items[(head + index) & (items.Length - 1)]; }

    /// A cursor over the items, oldest first, for `foreach`. Walks the ring
    /// in place rather than copying, unlike `ToList`. Enqueueing or dequeueing
    /// during a walk invalidates it.
    public IEnumerator<T> GetEnumerator() { return new QueueCursor<T>(this); }

    void Grow() {
        var bigger = new T[items.Length * 2];
        for (nuint i = 0; i < count; i++) {
            bigger[i] = items[(head + i) & (items.Length - 1)];
        }
        items = bigger;
        head = 0;
    }
}

// ------------------------------------------------------------------- stack

/// Last in, first out. The top is the end of the array, so nothing moves.
public class Stack<T> : IEnumerable<T> {
    T[] items;
    T[] blank;
    nuint count;

    /// An empty stack with room for a few items before it first grows.
    public Stack() {
        items = new T[8];
        blank = new T[1];
        count = 0;
    }

    /// How many items are on the stack. O(1).
    public nuint Count() { return count; }

    /// True when there is nothing to pop. Check this before `Pop` or `Peek`,
    /// both of which abort on an empty stack.
    public bool IsEmpty() { return count == 0; }

    /// The number of slots the backing array has.
    public nuint Capacity() { return items.Length; }

    /// Pushes onto the top, growing when full. Amortised constant time.
    public void Push(T item) {
        if (count == items.Length) { Grow(); }
        items[count] = item;
        count++;
    }

    /// Removes and returns the top. Aborts when the stack is empty.
    public T Pop() {
        if (count == 0) { sl_fail("Stack.Pop: the stack is empty"); }

        count--;
        var item = items[count];
        items[count] = blank[0];
        return item;
    }

    /// The top, without removing it. Aborts when the stack is empty.
    public T Peek() {
        if (count == 0) { sl_fail("Stack.Peek: the stack is empty"); }
        return items[count - 1];
    }

    /// Drops everything. The array is replaced rather than blanked, so
    /// anything it held is released now.
    public void Clear() {
        items = new T[8];
        count = 0;
    }

    /// The items, top first, which is the order they would be popped in.
    public List<T> ToList() {
        var result = new List<T>();
        for (nuint i = 0; i < count; i++) { result.Add(items[count - 1 - i]); }
        return result;
    }

    /// The item `depth` places below the top, counting from zero.
    T FromTop(nuint depth) { return items[count - 1 - depth]; }

    /// A cursor over the items, top first -- the order `Pop` would give them
    /// back in. Pushing or popping during a walk invalidates it.
    public IEnumerator<T> GetEnumerator() { return new StackCursor<T>(this); }

    void Grow() {
        var bigger = new T[items.Length * 2];
        for (nuint i = 0; i < count; i++) { bigger[i] = items[i]; }
        items = bigger;
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
/// for (nint at = line.First(); at >= 0; at = line.After(at)) {
///     Console.WriteLine(line.ValueAt(at));
/// }
/// ```
///
/// Removed nodes are recycled, so a list that is added to and removed from
/// steadily does not grow without bound.
public class LinkedList<T> : IEnumerable<T> {
    T[] items;
    nint[] next;
    nint[] previous;
    T[] blank;

    nint head;
    nint tail;
    nint free;          // head of the chain of recycled nodes, through `next`
    nuint used;         // how much of the pool has ever been handed out
    nuint count;

    /// An empty list with a small pool, grown as nodes are needed.
    public LinkedList() {
        items = new T[8];
        next = new nint[8];
        previous = new nint[8];
        blank = new T[1];
        head = -1;
        tail = -1;
        free = -1;
        used = 0;
        count = 0;
    }

    /// How many nodes are linked in. O(1), and not the size of the pool --
    /// recycled slots are not counted.
    public nuint Count() { return count; }

    /// True when nothing is linked in.
    public bool IsEmpty() { return count == 0; }

    /// A handle to the first node, or -1 when the list is empty.
    public nint First() { return head; }

    /// A handle to the last node, or -1 when the list is empty.
    public nint Last() { return tail; }

    /// The node after `handle`, or -1 at the end.
    public nint After(nint handle) { return next[(nuint)handle]; }

    /// The node before `handle`, or -1 at the start.
    public nint Before(nint handle) { return previous[(nuint)handle]; }

    /// The value in a node.
    ///
    /// `handle` must be live: one this list handed out and has not had
    /// `RemoveAt` called on. A stale or `-1` handle is not checked and reads
    /// whatever the pool slot now holds, so test `at >= 0` before walking.
    public T ValueAt(nint handle) { return items[(nuint)handle]; }

    /// Replaces the value in a node, leaving the links alone. Same
    /// requirement on `handle` as `ValueAt`.
    public void SetAt(nint handle, T value) { items[(nuint)handle] = value; }

    /// Links a new node at the front and answers its handle. Constant time.
    public nint AddFirst(T item) {
        nint node = Take(item);

        next[(nuint)node] = head;
        previous[(nuint)node] = -1;

        if (head >= 0) { previous[(nuint)head] = node; }
        else { tail = node; }

        head = node;
        count++;
        return node;
    }

    /// Links a new node at the back and answers its handle. Constant time --
    /// the tail is kept, so this does not walk the list.
    public nint AddLast(T item) {
        nint node = Take(item);

        previous[(nuint)node] = tail;
        next[(nuint)node] = -1;

        if (tail >= 0) { next[(nuint)tail] = node; }
        else { head = node; }

        tail = node;
        count++;
        return node;
    }

    /// Links a new node just after `handle` and answers its handle. Constant
    /// time, and the reason to choose this over a `List<T>`. Inserting after
    /// the last node appends.
    public nint InsertAfter(nint handle, T item) {
        nint after = next[(nuint)handle];
        if (after < 0) { return AddLast(item); }

        nint node = Take(item);
        previous[(nuint)node] = handle;
        next[(nuint)node] = after;
        next[(nuint)handle] = node;
        previous[(nuint)after] = node;

        count++;
        return node;
    }

    /// Links a new node just before `handle` and answers its handle.
    /// Inserting before the first node prepends.
    public nint InsertBefore(nint handle, T item) {
        nint before = previous[(nuint)handle];
        if (before < 0) { return AddFirst(item); }
        return InsertAfter(before, item);
    }

    /// Unlinks a node and recycles its slot. The handle is dead afterwards.
    public void RemoveAt(nint handle) {
        nuint at = (nuint)handle;
        nint before = previous[at];
        nint after = next[at];

        if (before >= 0) { next[(nuint)before] = after; } else { head = after; }
        if (after >= 0) { previous[(nuint)after] = before; } else { tail = before; }

        items[at] = blank[0];
        previous[at] = -1;
        next[at] = free;
        free = handle;
        count--;
    }

    /// Removes and returns the first item. Aborts when the list is empty.
    public T RemoveFirst() {
        if (head < 0) { sl_fail("LinkedList.RemoveFirst: the list is empty"); }

        var item = items[(nuint)head];
        RemoveAt(head);
        return item;
    }

    /// Removes and returns the last item. Aborts when the list is empty.
    public T RemoveLast() {
        if (tail < 0) { sl_fail("LinkedList.RemoveLast: the list is empty"); }

        var item = items[(nuint)tail];
        RemoveAt(tail);
        return item;
    }

    /// Drops every node and the pool with it. Every handle previously handed
    /// out is dead afterwards.
    public void Clear() {
        items = new T[8];
        next = new nint[8];
        previous = new nint[8];
        head = -1;
        tail = -1;
        free = -1;
        used = 0;
        count = 0;
    }

    /// The values, head first, as a fresh list. O(n), following the links.
    public List<T> ToList() {
        var result = new List<T>();
        for (nint at = head; at >= 0; at = next[(nuint)at]) { result.Add(items[(nuint)at]); }
        return result;
    }

    /// The three a cursor needs to walk the links. A node is an index into the
    /// pool, and -1 is the end -- which is why these are nint and not nuint.
    nint FirstNode() { return head; }
    nint NodeAfter(nint node) { return next[(nuint)node]; }
    T NodeValue(nint node) { return items[(nuint)node]; }

    /// A cursor over the values, head first, for `foreach`. Follows the links
    /// and keeps its place, so a whole walk is O(n). Adding or removing during
    /// a walk invalidates it.
    public IEnumerator<T> GetEnumerator() { return new LinkedListCursor<T>(this); }

    /// A slot for one more node: a recycled one if there is one, else the next
    /// unused one, growing the pool when it runs out.
    nint Take(T item) {
        if (free >= 0) {
            nint node = free;
            free = next[(nuint)node];
            items[(nuint)node] = item;
            return node;
        }

        if (used == items.Length) { Grow(); }

        nint fresh = (nint)used;
        used++;
        items[(nuint)fresh] = item;
        return fresh;
    }

    void Grow() {
        nuint size = items.Length * 2;

        var biggerItems = new T[size];
        var biggerNext = new nint[size];
        var biggerPrevious = new nint[size];

        for (nuint i = 0; i < used; i++) {
            biggerItems[i] = items[i];
            biggerNext[i] = next[i];
            biggerPrevious[i] = previous[i];
        }

        items = biggerItems;
        next = biggerNext;
        previous = biggerPrevious;
    }
}

// ------------------------------------------------------------- sorted list

/// A map kept in key order, over two parallel arrays.
///
/// Lookup is a binary search and iteration is in order, which is what a
/// `Dictionary` cannot do. Insertion moves the tail of the arrays, so this is
/// for maps that are read far more than they are written -- a lookup table
/// built once, rather than a counter updated in a loop.
public class SortedList<K, V> : IEnumerable<Pair<K, V>> where K : IComparable<K> {
    K[] keys;
    V[] values;
    nuint count;

    /// An empty map with room for a few entries before it first grows.
    public SortedList() {
        keys = new K[8];
        values = new V[8];
        count = 0;
    }

    /// How many entries there are. O(1).
    public nuint Count() { return count; }

    /// True when there are no entries.
    public bool IsEmpty() { return count == 0; }

    /// The index `key` is at, or the index it would be inserted at, negated and
    /// offset by one so the two cases stay apart: a result below zero means
    /// "not found, and `-result - 1` is where it goes".
    public nint IndexOfKey(K key) {
        nuint low = 0;
        nuint high = count;

        while (low < high) {
            nuint middle = low + (high - low) / 2;
            int order = keys[middle].CompareTo(key);

            if (order == 0) { return (nint)middle; }
            if (order < 0) { low = middle + 1; } else { high = middle; }
        }

        return -((nint)low) - 1;
    }

    /// Whether `key` is there. A binary search, O(log n). Reach for `Find`
    /// when the value is what is wanted, rather than searching twice.
    public bool ContainsKey(K key) { return IndexOfKey(key) >= 0; }

    /// The key at a position in the ordering, counting from the smallest.
    public K KeyAt(nuint index) {
        if (index >= count) { sl_array_bounds_fail(index, count); }
        return keys[index];
    }

    /// The value at a position in the ordering, paired with `KeyAt` at the
    /// same index. Aborts past the end.
    public V ValueAt(nuint index) {
        if (index >= count) { sl_array_bounds_fail(index, count); }
        return values[index];
    }

    /// The value for `key`, or `None` when there is none. The one to reach
    /// for, for the reason `Dictionary.Find` gives: a key is data, so a key
    /// that is not there is an outcome rather than a mistake.
    public Optional<V> Find(K key) {
        nint at = IndexOfKey(key);
        if (at < 0) { return None; }
        return Some(values[(nuint)at]);
    }

    /// The value for `key`, aborting when there is none.
    ///
    /// The asserting form, for a key that is there by construction. `Find` is
    /// the question where it might not be, and `GetOr` where a default will do.
    public V Get(K key) {
        nint at = IndexOfKey(key);
        if (at < 0) { sl_fail("SortedList.Get: no such key"); }
        return values[(nuint)at];
    }

    /// The value for `key`, or `fallback` when there is none.
    ///
    /// Allocates nothing, at the cost of not distinguishing an absent key from
    /// one whose stored value equals the fallback. `Find` is the one that
    /// tells them apart.
    public V GetOr(K key, V fallback) {
        nint at = IndexOfKey(key);
        if (at < 0) { return fallback; }
        return values[(nuint)at];
    }

    /// Sets the value of a key, adding it in order if it is new.
    ///
    /// An existing key costs a search. A new one costs the search plus a shift
    /// of everything after it -- O(n) -- which is what makes this collection a
    /// poor choice for a map that is written in a loop.
    public void Set(K key, V value) {
        nint at = IndexOfKey(key);
        if (at >= 0) {
            values[(nuint)at] = value;
            return;
        }

        nuint slot = (nuint)(-at - 1);
        if (count == keys.Length) { Grow(); }

        // Shift the tail up by one. Counted down from the end so that no slot
        // is written before it has been copied.
        for (nuint i = count; i > slot; i--) {
            keys[i] = keys[i - 1];
            values[i] = values[i - 1];
        }

        keys[slot] = key;
        values[slot] = value;
        count++;
    }

    /// Removes a key, answering whether it was there. Closes the gap, so it
    /// is O(n) like `Set` on a new key.
    public bool Remove(K key) {
        nint at = IndexOfKey(key);
        if (at < 0) { return false; }

        for (nuint i = (nuint)at; i + 1 < count; i++) {
            keys[i] = keys[i + 1];
            values[i] = values[i + 1];
        }

        count--;

        // The vacated slot still refers to the last entry; blanking it releases
        // that reference now rather than at the next insertion.
        var noKeys = new K[1];
        var noValues = new V[1];
        keys[count] = noKeys[0];
        values[count] = noValues[0];
        return true;
    }

    /// Drops every entry. The arrays are replaced rather than blanked, so
    /// anything they held is released now.
    public void Clear() {
        keys = new K[8];
        values = new V[8];
        count = 0;
    }

    /// Every key, smallest first, as a fresh list.
    public List<K> Keys() {
        var result = new List<K>();
        for (nuint i = 0; i < count; i++) { result.Add(keys[i]); }
        return result;
    }

    /// Every value, in key order, pairing with `Keys` position for position.
    public List<V> Values() {
        var result = new List<V>();
        for (nuint i = 0; i < count; i++) { result.Add(values[i]); }
        return result;
    }

    /// The entry at a position, in key order. What the cursor walks.
    Pair<K, V> PairAt(nuint index) { return new Pair<K, V>(keys[index], values[index]); }

    /// A cursor over the entries in key order, for `foreach` -- the ordering
    /// a `Dictionary` cannot give. One `Pair` is built per step. Writing to
    /// the map during a walk invalidates it.
    public IEnumerator<Pair<K, V>> GetEnumerator() {
        return new SortedListCursor<K, V>(this);
    }

    void Grow() {
        var biggerKeys = new K[keys.Length * 2];
        var biggerValues = new V[values.Length * 2];

        for (nuint i = 0; i < count; i++) {
            biggerKeys[i] = keys[i];
            biggerValues[i] = values[i];
        }

        keys = biggerKeys;
        values = biggerValues;
    }
}

/// Walks a queue oldest first, without copying it.
///
/// The materialising version this replaced built a whole `List<T>` before the
/// first `MoveNext`, so iterating a queue allocated as much again as the queue
/// held. A cursor over the ring costs nothing.
public class QueueCursor<T> : IEnumerator<T> {
    Queue<T> source;
    nuint next;

    /// A cursor over `queue`, positioned before the oldest item.
    public QueueCursor(Queue<T> queue) {
        source = queue;
        next = 0;
    }

    /// Advances, answering false at the end.
    public bool MoveNext() {
        if (next >= source.Count()) { return false; }
        next++;
        return true;
    }

    /// The item the last `MoveNext` landed on.
    public T Current() { return source.At(next - 1); }
}

/// Walks a stack top first, matching the order `Pop` would hand things back.
public class StackCursor<T> : IEnumerator<T> {
    Stack<T> source;
    nuint next;

    /// A cursor over `stack`, positioned above the top.
    public StackCursor(Stack<T> stack) {
        source = stack;
        next = 0;
    }

    /// Advances towards the bottom, answering false at the end.
    public bool MoveNext() {
        if (next >= source.Count()) { return false; }
        next++;
        return true;
    }

    /// The item the last `MoveNext` landed on.
    public T Current() { return source.FromTop(next - 1); }
}

/// Walks a linked list head first, following the links rather than flattening
/// them. `At` is O(n) from the head, so a cursor that used it would make
/// iterating O(n squared); this keeps the node it reached.
public class LinkedListCursor<T> : IEnumerator<T> {
    LinkedList<T> source;
    nint at;
    bool started;

    /// A cursor over `list`, positioned before the head.
    public LinkedListCursor(LinkedList<T> list) {
        source = list;
        at = -1;
        started = false;
    }

    /// Follows one link, answering false past the tail.
    public bool MoveNext() {
        if (!started) {
            started = true;
            at = source.FirstNode();
        } else if (at >= 0) {
            at = source.NodeAfter(at);
        }

        return at >= 0;
    }

    /// The value in the node the last `MoveNext` reached.
    public T Current() { return source.NodeValue(at); }
}

/// Walks a sorted list in key order.
///
/// One `Pair` is built per step, as the materialising version built one per
/// entry before the walk began -- the difference is that a loop that stops
/// early now stops allocating too.
public class SortedListCursor<K, V> : IEnumerator<Pair<K, V>> where K : IComparable<K> {
    SortedList<K, V> source;
    nuint next;

    /// A cursor over `list`, positioned before the smallest key.
    public SortedListCursor(SortedList<K, V> list) {
        source = list;
        next = 0;
    }

    /// Advances to the next key in order, answering false at the end.
    public bool MoveNext() {
        if (next >= source.Count()) { return false; }
        next++;
        return true;
    }

    /// The entry the last `MoveNext` landed on, as a freshly built `Pair`.
    public Pair<K, V> Current() { return source.PairAt(next - 1); }
}
