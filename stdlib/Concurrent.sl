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

/// Collections more than one thread may hold at once.
///
/// Each one owns an ordinary collection from Standard.Collections, keeps it in a
/// field, and never lets a reference to it out. That last part is not a style
/// choice, it is the correctness argument:
///
/// **A caller who keeps what it was lent outlives the lock.** A lock protects
/// what it guards for as long as it is held, and nothing stops a caller storing
/// the object it was handed and using it after the guard is gone. Keeping the
/// collection in a field avoids that entirely: reading a field to call a method
/// on it borrows, and a borrow that never leaves cannot outlive anything.
///
/// This began as a stronger argument still, because reference counts were not
/// atomic and handing an object out of a lock corrupted its count. Counts are
/// atomic now, so that half is closed; the lifetime half is not, and it is the
/// half this design was already the answer to.
///
/// So these types lock a raw mutex directly rather than using `Mutex<T>` from
/// Standard.Threading, whose `Guard.Value()` is exactly the hand-out that
/// cannot be made safe this way. See the note there.
///
/// The API differs from the single-threaded one in one further way, and it is
/// the important one: nothing here can be asked a question whose answer is
/// stale before it is read. There is no `Peek` and then `Dequeue`, because
/// between the two another thread may have taken it. Every operation that can
/// fail says so in its result.
module Standard.Concurrent;

import Standard.Collections;
import Standard.Threading;

extern "C"
{
    byte* sl_mutex_new();
    void  sl_mutex_free(byte* mutex);
    void  sl_mutex_lock(byte* mutex);
    void  sl_mutex_unlock(byte* mutex);

    byte* sl_condition_new();
    void  sl_condition_free(byte* condition);
    void  sl_condition_wait(byte* condition, byte* mutex);
    void  sl_condition_signal(byte* condition);
    void  sl_condition_broadcast(byte* condition);
}

// ------------------------------------------------------------------ results

/// What a take returned: whether there was anything, and what it was.
///
/// `Value` means nothing when `Ok` is false -- it holds whatever a zeroed slot
/// holds. Check `Ok` first. The pair exists because a concurrent container
/// cannot answer "is it empty?" and "give me the front" as two questions.
public class Taken<T>
{
    /// Whether there was anything to take. Read this before `Value`.
    public bool Ok { get; }

    /// What was taken, meaningful only when `Ok` is true. Otherwise it is
    /// whatever a zeroed slot holds -- null for a reference, zero for a
    /// number -- and not a value the container ever contained.
    public T Value { get; }

    /// Builds an answer. The containers make these; a caller reads them.
    public Taken(bool ok, T value)
    {
        Ok = ok;
        Value = value;
    }
}

// ------------------------------------------------------------------- queue

/// A first-in, first-out queue several threads may use at once.
public threadsafe class ConcurrentQueue<T>
{
    Queue<T> _items;
    byte* _gate;
    T[] _blank;

    /// An empty queue, with its own mutex. The mutex is freed when the queue
    /// is, so there is nothing to dispose.
    public ConcurrentQueue()
    {
        _items = new Queue<T>();
        _gate = sl_mutex_new();
        _blank = new T[1];
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
    public Taken<T> TryDequeue()
    {
        sl_mutex_lock(_gate);

        if (_items.IsEmpty())
        {
            sl_mutex_unlock(_gate);
            return new Taken<T>(false, _blank[0]);
        }

        var item = _items.Dequeue();
        sl_mutex_unlock(_gate);
        return new Taken<T>(true, item);
    }

    /// Takes the front item, or `fallback` when there is none. The same as
    /// `TryDequeue` without the allocation, for when a sentinel will do.
    public T DequeueOr(T fallback)
    {
        sl_mutex_lock(_gate);

        if (_items.IsEmpty())
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
    public nuint Count()
    {
        sl_mutex_lock(_gate);
        nuint result = _items.Count();
        sl_mutex_unlock(_gate);
        return result;
    }

    /// Whether it is empty *now*. Another thread may enqueue before you act on
    /// the answer, so a true here does not mean the next `TryDequeue` fails.
    /// Reach for `TryDequeue` and read its `Ok` instead.
    public bool IsEmpty() => Count() == 0;

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

// ------------------------------------------------------------------- stack

/// A last-in, first-out stack several threads may use at once.
public threadsafe class ConcurrentStack<T>
{
    Stack<T> _items;
    byte* _gate;
    T[] _blank;

    /// An empty stack, with its own mutex.
    public ConcurrentStack()
    {
        _items = new Stack<T>();
        _gate = sl_mutex_new();
        _blank = new T[1];
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
    public Taken<T> TryPop()
    {
        sl_mutex_lock(_gate);

        if (_items.IsEmpty())
        {
            sl_mutex_unlock(_gate);
            return new Taken<T>(false, _blank[0]);
        }

        var item = _items.Pop();
        sl_mutex_unlock(_gate);
        return new Taken<T>(true, item);
    }

    /// Takes the top item, or `fallback` when there is none. The same as
    /// `TryPop` without the allocation, for when a sentinel will do -- which
    /// it will not if `fallback` is a value the stack might hold.
    public T PopOr(T fallback)
    {
        sl_mutex_lock(_gate);

        if (_items.IsEmpty())
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
    public nuint Count()
    {
        sl_mutex_lock(_gate);
        nuint result = _items.Count();
        sl_mutex_unlock(_gate);
        return result;
    }

    /// Whether it is empty *now*, with the same caveat as `Count`.
    public bool IsEmpty() => Count() == 0;

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

// -------------------------------------------------------------- dictionary

/// A map several threads may use at once.
public threadsafe class ConcurrentDictionary<K, V> where K : IEquatable<K>, IHashable
{
    Dictionary<K, V> _entries;
    byte* _gate;
    V[] _blank;

    /// An empty map, with its own mutex.
    public ConcurrentDictionary()
    {
        _entries = new Dictionary<K, V>();
        _gate = sl_mutex_new();
        _blank = new V[1];
    }

    ~ConcurrentDictionary() { sl_mutex_free(_gate); }

    /// Sets the value of a key, whether or not it was there. `Add` is the one
    /// that refuses to overwrite.
    public void Set(K key, V value)
    {
        sl_mutex_lock(_gate);
        _entries.Set(key, value);
        sl_mutex_unlock(_gate);
    }

    /// Adds the key only if it is absent, reporting whether it did. This is the
    /// operation `ContainsKey` followed by `Set` cannot be: between those two
    /// another thread can insert.
    public bool Add(K key, V value)
    {
        sl_mutex_lock(_gate);
        bool added = _entries.Add(key, value);
        sl_mutex_unlock(_gate);
        return added;
    }

    /// The value for `key` if it is there. One lock rather than two, which is
    /// what makes it different from `ContainsKey` followed by a lookup:
    /// between those two another thread can remove the key.
    public Taken<V> TryGet(K key)
    {
        sl_mutex_lock(_gate);

        if (!_entries.ContainsKey(key))
        {
            sl_mutex_unlock(_gate);
            return new Taken<V>(false, _blank[0]);
        }

        var value = _entries.Get(key);
        sl_mutex_unlock(_gate);
        return new Taken<V>(true, value);
    }

    /// The value for `key`, or `fallback` when it is absent. No allocation,
    /// at the cost of being unable to tell an absent key from one whose value
    /// happens to equal the fallback.
    public V GetOr(K key, V fallback)
    {
        sl_mutex_lock(_gate);
        var value = _entries.GetOr(key, fallback);
        sl_mutex_unlock(_gate);
        return value;
    }

    /// Whether the key is there *now*. True here does not mean the next
    /// `TryGet` succeeds -- another thread may remove it in between -- so this
    /// is for reporting, and `TryGet` is for acting.
    public bool ContainsKey(K key)
    {
        sl_mutex_lock(_gate);
        bool present = _entries.ContainsKey(key);
        sl_mutex_unlock(_gate);
        return present;
    }

    /// Removes a key, answering whether it was there. The answer is exact:
    /// exactly one of several threads racing to remove the same key gets true.
    public bool Remove(K key)
    {
        sl_mutex_lock(_gate);
        bool removed = _entries.Remove(key);
        sl_mutex_unlock(_gate);
        return removed;
    }

    /// Drops every entry, under one lock.
    public void Clear()
    {
        sl_mutex_lock(_gate);
        _entries.Clear();
        sl_mutex_unlock(_gate);
    }

    /// How many entries there are *now*. For reporting rather than deciding.
    public nuint Count()
    {
        sl_mutex_lock(_gate);
        nuint result = _entries.Count();
        sl_mutex_unlock(_gate);
        return result;
    }

    /// Whether it is empty *now*, with the same caveat as `Count`.
    public bool IsEmpty() => Count() == 0;

    /// A snapshot of the keys. Out of date the moment it is returned, which is
    /// why it is a copy rather than a view.
    public List<K> Keys()
    {
        sl_mutex_lock(_gate);
        var copy = _entries.Keys();
        sl_mutex_unlock(_gate);
        return copy;
    }

    /// A snapshot of the values, in the same order as `Keys` when neither is
    /// interleaved with a write. Out of date the moment it is returned, and
    /// pairing the two lists after the fact is not safe -- iterate the map if
    /// the pairing matters.
    public List<V> Values()
    {
        sl_mutex_lock(_gate);
        var copy = _entries.Values();
        sl_mutex_unlock(_gate);
        return copy;
    }
}

// ---------------------------------------------------------------- hand-off

/// A queue whose taker waits rather than spinning: the producer-consumer
/// hand-off.
///
/// `Take` blocks until something arrives or the channel is closed, which is
/// what separates this from `ConcurrentQueue`. Closing is how consumers are
/// told there will be no more: every waiter wakes, what was already sent is
/// still delivered, and once it is drained every `Take` returns at once with
/// `Ok` false.
///
///     var channel = new Channel<String>();
///     // producer:  channel.Send(line);  ... channel.Close();
///     // consumer:  var got = channel.Take();
///     //            while (got.Ok) { use(got.Value); got = channel.Take(); }
public threadsafe class Channel<T>
{
    Queue<T> _items;
    byte* _gate;
    byte* _arrived;
    T[] _blank;
    bool _closed;

    /// An open, empty channel. Unbounded: `Send` never blocks waiting for a
    /// consumer, so a producer that outruns its consumers grows the queue
    /// rather than being slowed by it.
    public Channel()
    {
        _items = new Queue<T>();
        _gate = sl_mutex_new();
        _arrived = sl_condition_new();
        _blank = new T[1];
        _closed = false;
    }

    ~Channel()
    {
        sl_condition_free(_arrived);
        sl_mutex_free(_gate);
    }

    /// Adds an item and wakes one waiter. Sending to a closed channel changes
    /// nothing and reports false.
    public bool Send(T item)
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

    /// Waits for an item. Returns `Ok` false once the channel is closed and
    /// drained, and not before.
    public Taken<T> Take()
    {
        sl_mutex_lock(_gate);

        // A wait can return without a signal, so the condition is re-tested in
        // a loop rather than assumed. That is true of every condition variable
        // on every platform.
        while (_items.IsEmpty() && !_closed)
        {
            sl_condition_wait(_arrived, _gate);
        }

        if (_items.IsEmpty())
        {
            sl_mutex_unlock(_gate);
            return new Taken<T>(false, _blank[0]);
        }

        var item = _items.Dequeue();
        sl_mutex_unlock(_gate);
        return new Taken<T>(true, item);
    }

    /// Takes an item if one is there already, without waiting.
    public Taken<T> TryTake()
    {
        sl_mutex_lock(_gate);

        if (_items.IsEmpty())
        {
            sl_mutex_unlock(_gate);
            return new Taken<T>(false, _blank[0]);
        }

        var item = _items.Dequeue();
        sl_mutex_unlock(_gate);
        return new Taken<T>(true, item);
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
    /// taken. `Take`'s `Ok` is what answers that.
    public bool IsClosed()
    {
        sl_mutex_lock(_gate);
        bool result = _closed;
        sl_mutex_unlock(_gate);
        return result;
    }

    /// How many items are waiting *now* -- the producer's backlog. For
    /// reporting rather than for deciding; a consumer should call `Take`.
    public nuint Count()
    {
        sl_mutex_lock(_gate);
        nuint result = _items.Count();
        sl_mutex_unlock(_gate);
        return result;
    }
}
