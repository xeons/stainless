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

// Collections more than one thread may hold at once.
//
// Each one owns an ordinary collection from Standard.Collections, keeps it in a
// field, and never lets a reference to it out. That last part is not a style
// choice, it is the correctness argument:
//
// **A caller who keeps what it was lent outlives the lock.** A lock protects
// what it guards for as long as it is held, and nothing stops a caller storing
// the object it was handed and using it after the guard is gone. Keeping the
// collection in a field avoids that entirely: reading a field to call a method
// on it borrows, and a borrow that never leaves cannot outlive anything.
//
// This began as a stronger argument still, because reference counts were not
// atomic and handing an object out of a lock corrupted its count. Counts are
// atomic now, so that half is closed; the lifetime half is not, and it is the
// half this design was already the answer to.
//
// So these types lock a raw mutex directly rather than using `Mutex<T>` from
// Standard.Threading, whose `Guard.Value()` is exactly the hand-out that
// cannot be made safe this way. See the note there.
//
// The API differs from the single-threaded one in one further way, and it is
// the important one: nothing here can be asked a question whose answer is
// stale before it is read. There is no `Peek` and then `Dequeue`, because
// between the two another thread may have taken it. Every operation that can
// fail says so in its result.
module Standard.Concurrent;

import Standard.Collections;
import Standard.Threading;      // for [Shared]

extern "C" {
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
public class Taken<T> {
    public bool Ok { get; }
    public T Value { get; }

    public Taken(bool ok, T value) {
        Ok = ok;
        Value = value;
    }
}

// ------------------------------------------------------------------- queue

/// A first-in, first-out queue several threads may use at once.
[Shared]
public class ConcurrentQueue<T> {
    Queue<T> items;
    byte* gate;
    T[] blank;

    public ConcurrentQueue() {
        items = new Queue<T>();
        gate = sl_mutex_new();
        blank = new T[1];
    }

    ~ConcurrentQueue() { sl_mutex_free(gate); }

    public void Enqueue(T item) {
        sl_mutex_lock(gate);
        items.Enqueue(item);
        sl_mutex_unlock(gate);
    }

    /// Takes the front item if there is one. The answer and the item come back
    /// together, because asking twice would race.
    public Taken<T> TryDequeue() {
        sl_mutex_lock(gate);

        if (items.IsEmpty()) {
            sl_mutex_unlock(gate);
            return new Taken<T>(false, blank[0]);
        }

        var item = items.Dequeue();
        sl_mutex_unlock(gate);
        return new Taken<T>(true, item);
    }

    /// Takes the front item, or `fallback` when there is none. The same as
    /// `TryDequeue` without the allocation, for when a sentinel will do.
    public T DequeueOr(T fallback) {
        sl_mutex_lock(gate);

        if (items.IsEmpty()) {
            sl_mutex_unlock(gate);
            return fallback;
        }

        var item = items.Dequeue();
        sl_mutex_unlock(gate);
        return item;
    }

    /// How many items there are *now*. Another thread may change it before you
    /// act on it, so this is for reporting rather than for deciding.
    public nuint Count() {
        sl_mutex_lock(gate);
        nuint result = items.Count();
        sl_mutex_unlock(gate);
        return result;
    }

    public bool IsEmpty() { return Count() == 0; }

    /// A snapshot, oldest first. Consistent with itself, and out of date the
    /// moment it is returned.
    public List<T> ToList() {
        sl_mutex_lock(gate);
        var copy = items.ToList();
        sl_mutex_unlock(gate);
        return copy;
    }
}

// ------------------------------------------------------------------- stack

/// A last-in, first-out stack several threads may use at once.
[Shared]
public class ConcurrentStack<T> {
    Stack<T> items;
    byte* gate;
    T[] blank;

    public ConcurrentStack() {
        items = new Stack<T>();
        gate = sl_mutex_new();
        blank = new T[1];
    }

    ~ConcurrentStack() { sl_mutex_free(gate); }

    public void Push(T item) {
        sl_mutex_lock(gate);
        items.Push(item);
        sl_mutex_unlock(gate);
    }

    public Taken<T> TryPop() {
        sl_mutex_lock(gate);

        if (items.IsEmpty()) {
            sl_mutex_unlock(gate);
            return new Taken<T>(false, blank[0]);
        }

        var item = items.Pop();
        sl_mutex_unlock(gate);
        return new Taken<T>(true, item);
    }

    public T PopOr(T fallback) {
        sl_mutex_lock(gate);

        if (items.IsEmpty()) {
            sl_mutex_unlock(gate);
            return fallback;
        }

        var item = items.Pop();
        sl_mutex_unlock(gate);
        return item;
    }

    public nuint Count() {
        sl_mutex_lock(gate);
        nuint result = items.Count();
        sl_mutex_unlock(gate);
        return result;
    }

    public bool IsEmpty() { return Count() == 0; }

    public List<T> ToList() {
        sl_mutex_lock(gate);
        var copy = items.ToList();
        sl_mutex_unlock(gate);
        return copy;
    }
}

// -------------------------------------------------------------- dictionary

/// A map several threads may use at once.
[Shared]
public class ConcurrentDictionary<K, V> where K : IEquatable<K>, IHashable {
    Dictionary<K, V> entries;
    byte* gate;
    V[] blank;

    public ConcurrentDictionary() {
        entries = new Dictionary<K, V>();
        gate = sl_mutex_new();
        blank = new V[1];
    }

    ~ConcurrentDictionary() { sl_mutex_free(gate); }

    public void Set(K key, V value) {
        sl_mutex_lock(gate);
        entries.Set(key, value);
        sl_mutex_unlock(gate);
    }

    /// Adds the key only if it is absent, reporting whether it did. This is the
    /// operation `ContainsKey` followed by `Set` cannot be: between those two
    /// another thread can insert.
    public bool Add(K key, V value) {
        sl_mutex_lock(gate);
        bool added = entries.Add(key, value);
        sl_mutex_unlock(gate);
        return added;
    }

    public Taken<V> TryGet(K key) {
        sl_mutex_lock(gate);

        if (!entries.ContainsKey(key)) {
            sl_mutex_unlock(gate);
            return new Taken<V>(false, blank[0]);
        }

        var value = entries.Get(key);
        sl_mutex_unlock(gate);
        return new Taken<V>(true, value);
    }

    public V GetOr(K key, V fallback) {
        sl_mutex_lock(gate);
        var value = entries.GetOr(key, fallback);
        sl_mutex_unlock(gate);
        return value;
    }

    public bool ContainsKey(K key) {
        sl_mutex_lock(gate);
        bool present = entries.ContainsKey(key);
        sl_mutex_unlock(gate);
        return present;
    }

    public bool Remove(K key) {
        sl_mutex_lock(gate);
        bool removed = entries.Remove(key);
        sl_mutex_unlock(gate);
        return removed;
    }

    public void Clear() {
        sl_mutex_lock(gate);
        entries.Clear();
        sl_mutex_unlock(gate);
    }

    public nuint Count() {
        sl_mutex_lock(gate);
        nuint result = entries.Count();
        sl_mutex_unlock(gate);
        return result;
    }

    public bool IsEmpty() { return Count() == 0; }

    /// A snapshot of the keys. Out of date the moment it is returned, which is
    /// why it is a copy rather than a view.
    public List<K> Keys() {
        sl_mutex_lock(gate);
        var copy = entries.Keys();
        sl_mutex_unlock(gate);
        return copy;
    }

    public List<V> Values() {
        sl_mutex_lock(gate);
        var copy = entries.Values();
        sl_mutex_unlock(gate);
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
[Shared]
public class Channel<T> {
    Queue<T> items;
    byte* gate;
    byte* arrived;
    T[] blank;
    bool closed;

    public Channel() {
        items = new Queue<T>();
        gate = sl_mutex_new();
        arrived = sl_condition_new();
        blank = new T[1];
        closed = false;
    }

    ~Channel() {
        sl_condition_free(arrived);
        sl_mutex_free(gate);
    }

    /// Adds an item and wakes one waiter. Sending to a closed channel changes
    /// nothing and reports false.
    public bool Send(T item) {
        sl_mutex_lock(gate);

        if (closed) {
            sl_mutex_unlock(gate);
            return false;
        }

        items.Enqueue(item);
        sl_condition_signal(arrived);
        sl_mutex_unlock(gate);
        return true;
    }

    /// Waits for an item. Returns `Ok` false once the channel is closed and
    /// drained, and not before.
    public Taken<T> Take() {
        sl_mutex_lock(gate);

        // A wait can return without a signal, so the condition is re-tested in
        // a loop rather than assumed. That is true of every condition variable
        // on every platform.
        while (items.IsEmpty() && !closed) {
            sl_condition_wait(arrived, gate);
        }

        if (items.IsEmpty()) {
            sl_mutex_unlock(gate);
            return new Taken<T>(false, blank[0]);
        }

        var item = items.Dequeue();
        sl_mutex_unlock(gate);
        return new Taken<T>(true, item);
    }

    /// Takes an item if one is there already, without waiting.
    public Taken<T> TryTake() {
        sl_mutex_lock(gate);

        if (items.IsEmpty()) {
            sl_mutex_unlock(gate);
            return new Taken<T>(false, blank[0]);
        }

        var item = items.Dequeue();
        sl_mutex_unlock(gate);
        return new Taken<T>(true, item);
    }

    /// Says there will be no more, and wakes everyone waiting. Idempotent.
    public void Close() {
        sl_mutex_lock(gate);
        closed = true;
        sl_condition_broadcast(arrived);
        sl_mutex_unlock(gate);
    }

    public bool IsClosed() {
        sl_mutex_lock(gate);
        bool result = closed;
        sl_mutex_unlock(gate);
        return result;
    }

    public nuint Count() {
        sl_mutex_lock(gate);
        nuint result = items.Count();
        sl_mutex_unlock(gate);
        return result;
    }
}
