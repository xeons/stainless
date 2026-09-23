# Standard.Concurrent

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Collections more than one thread may hold at once.

Each one owns an ordinary collection from Standard.Collections, keeps it in a
field, and never lets a reference to it out. That last part is not a style
choice, it is the correctness argument:

**A caller who keeps what it was lent outlives the lock.** A lock protects
what it guards for as long as it is held, and nothing stops a caller storing
the object it was handed and using it after the guard is gone. Keeping the
collection in a field avoids that entirely: reading a field to call a method
on it borrows, and a borrow that never leaves cannot outlive anything.

This began as a stronger argument still, because reference counts were not
atomic and handing an object out of a lock corrupted its count. Counts are
atomic now, so that half is closed; the lifetime half is not, and it is the
half this design was already the answer to.

So these types lock a raw mutex directly rather than using `Mutex<T>` from
Standard.Threading, whose `Guard.Value` is exactly the hand-out that
cannot be made safe this way. See the note there.

The API differs from the single-threaded one in one further way, and it is
the important one: nothing here can be asked a question whose answer is
stale before it is read. There is no `Peek` and then `Dequeue`, because
between the two another thread may have taken it. Every operation that can
fail says so in its result.

## Contents

**Types** &nbsp; [Channel&lt;T&gt;](#channelt-class) &middot; [ConcurrentDictionary&lt;TKey, TValue&gt;](#concurrentdictionarytkey-tvalue-class) &middot; [ConcurrentQueue&lt;T&gt;](#concurrentqueuet-class) &middot; [ConcurrentStack&lt;T&gt;](#concurrentstackt-class)

## Types

### Channel&lt;T&gt; *class*

```
threadsafe class Channel<T>
```

A queue whose taker waits rather than spinning: the producer-consumer
hand-off.

`Take` blocks until something arrives or the channel is closed, which is
what separates this from `ConcurrentQueue`. Closing is how consumers are
told there will be no more: every waiter wakes, what was already sent is
still delivered, and once it is drained every `Take` returns at once with
`None`.

    var channel = new Channel<String>();
    // producer:  channel.Add(line);  ... channel.Close();
    // consumer:  while (channel.Take() is Some got) { Handle(got.Value); }

**Type parameters**

- `T` — what is sent through it; nothing is required of it, and nothing yet checks that the sender is done with what it sent

<sub>[stdlib/Concurrent/Channel.sl:44](../../stdlib/Concurrent/Channel.sl#L44)</sub>

#### Add *method*

```
bool Add(T item)
```

Adds an item and wakes one waiter. Adding to a closed channel changes
nothing and reports false.

<sub>[stdlib/Concurrent/Channel.sl:70](../../stdlib/Concurrent/Channel.sl#L70)</sub>

#### Take *method*

```
Optional<T> Take()
```

Waits for an item. Answers `None` once the channel is closed and
drained, and not before.

<sub>[stdlib/Concurrent/Channel.sl:88](../../stdlib/Concurrent/Channel.sl#L88)</sub>

#### TryTake *method*

```
Optional<T> TryTake()
```

Takes an item if one is there already, without waiting.

<sub>[stdlib/Concurrent/Channel.sl:112](../../stdlib/Concurrent/Channel.sl#L112)</sub>

#### Close *method*

```
void Close()
```

Says there will be no more, and wakes everyone waiting. Idempotent.

<sub>[stdlib/Concurrent/Channel.sl:128](../../stdlib/Concurrent/Channel.sl#L128)</sub>

#### IsClosed *property*

```
bool IsClosed { get; }
```

Whether `Close` has been called. A closed channel may still have items
in it: this answers whether more can be sent, not whether more can be
taken. What `Take` answers with is what says that.

<sub>[stdlib/Concurrent/Channel.sl:139](../../stdlib/Concurrent/Channel.sl#L139)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many items are waiting *now* -- the producer's backlog. For
reporting rather than for deciding; a consumer should call `Take`.

<sub>[stdlib/Concurrent/Channel.sl:152](../../stdlib/Concurrent/Channel.sl#L152)</sub>

### ConcurrentDictionary&lt;TKey, TValue&gt; *class*

```
threadsafe class ConcurrentDictionary<TKey, TValue>
    where TKey : IEquatable<TKey>, IHashable
```

A map several threads may use at once.

**Type parameters**

- `TKey` — what entries are found by. It is compared and hashed on every lookup, so it must implement both `IEquatable<TKey>` and `IHashable`.
- `TValue` — what is stored against a key; nothing is required of it

<sub>[stdlib/Concurrent/ConcurrentDictionary.sl:34](../../stdlib/Concurrent/ConcurrentDictionary.sl#L34)</sub>

#### SetValue *method*

```
void SetValue(TKey key, TValue value)
```

Sets the value of a key, whether or not it was there. `Add` is the one
that refuses to overwrite.

<sub>[stdlib/Concurrent/ConcurrentDictionary.sl:50](../../stdlib/Concurrent/ConcurrentDictionary.sl#L50)</sub>

#### TryAdd *method*

```
bool TryAdd(TKey key, TValue value)
```

Adds the key only if it is absent, reporting whether it did. This is the
operation `ContainsKey` followed by `SetValue` cannot be: between those two
another thread can insert.

<sub>[stdlib/Concurrent/ConcurrentDictionary.sl:60](../../stdlib/Concurrent/ConcurrentDictionary.sl#L60)</sub>

#### TryGetValue *method*

```
Optional<TValue> TryGetValue(TKey key)
```

The value for `key` if it is there. One lock rather than two, which is
what makes it different from `ContainsKey` followed by a lookup:
between those two another thread can remove the key.

<sub>[stdlib/Concurrent/ConcurrentDictionary.sl:71](../../stdlib/Concurrent/ConcurrentDictionary.sl#L71)</sub>

#### GetValueOrDefault *method*

```
TValue GetValueOrDefault(TKey key, TValue fallback)
```

The value for `key`, or `fallback` when it is absent. No allocation,
at the cost of being unable to tell an absent key from one whose value
happens to equal the fallback.

<sub>[stdlib/Concurrent/ConcurrentDictionary.sl:89](../../stdlib/Concurrent/ConcurrentDictionary.sl#L89)</sub>

#### ContainsKey *method*

```
bool ContainsKey(TKey key)
```

Whether the key is there *now*. True here does not mean the next
`TryGetValue` succeeds -- another thread may remove it in between -- so this
is for reporting, and `TryGetValue` is for acting.

<sub>[stdlib/Concurrent/ConcurrentDictionary.sl:100](../../stdlib/Concurrent/ConcurrentDictionary.sl#L100)</sub>

#### TryRemove *method*

```
bool TryRemove(TKey key)
```

Removes a key, answering whether it was there. The answer is exact:
exactly one of several threads racing to remove the same key gets true.

<sub>[stdlib/Concurrent/ConcurrentDictionary.sl:110](../../stdlib/Concurrent/ConcurrentDictionary.sl#L110)</sub>

#### Clear *method*

```
void Clear()
```

Drops every entry, under one lock.

<sub>[stdlib/Concurrent/ConcurrentDictionary.sl:119](../../stdlib/Concurrent/ConcurrentDictionary.sl#L119)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many entries there are *now*. For reporting rather than deciding.

<sub>[stdlib/Concurrent/ConcurrentDictionary.sl:127](../../stdlib/Concurrent/ConcurrentDictionary.sl#L127)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether it is empty *now*, with the same caveat as `Count`.

<sub>[stdlib/Concurrent/ConcurrentDictionary.sl:139](../../stdlib/Concurrent/ConcurrentDictionary.sl#L139)</sub>

#### GetKeys *method*

```
List<TKey> GetKeys()
```

A snapshot of the keys. Out of date the moment it is returned, which is
why it is a copy rather than a view.

<sub>[stdlib/Concurrent/ConcurrentDictionary.sl:143](../../stdlib/Concurrent/ConcurrentDictionary.sl#L143)</sub>

#### GetValues *method*

```
List<TValue> GetValues()
```

A snapshot of the values, in the same order as `GetKeys` when neither is
interleaved with a write. Out of date the moment it is returned, and
pairing the two lists after the fact is not safe -- iterate the map if
the pairing matters.

<sub>[stdlib/Concurrent/ConcurrentDictionary.sl:155](../../stdlib/Concurrent/ConcurrentDictionary.sl#L155)</sub>

### ConcurrentQueue&lt;T&gt; *class*

```
threadsafe class ConcurrentQueue<T>
```

A first-in, first-out queue several threads may use at once.

**Type parameters**

- `T` — what the queue holds; nothing is required of it, and nothing yet checks that two threads may safely hold one at once

<sub>[stdlib/Concurrent/ConcurrentQueue.sl:33](../../stdlib/Concurrent/ConcurrentQueue.sl#L33)</sub>

#### Enqueue *method*

```
void Enqueue(T item)
```

Adds to the back. Blocks only for as long as the lock is held, which is
the enqueue itself; there is no bound on the queue, so this never waits
for a consumer.

<sub>[stdlib/Concurrent/ConcurrentQueue.sl:51](../../stdlib/Concurrent/ConcurrentQueue.sl#L51)</sub>

#### TryDequeue *method*

```
Optional<T> TryDequeue()
```

Takes the front item if there is one. The answer and the item come back
together, because asking twice would race.

<sub>[stdlib/Concurrent/ConcurrentQueue.sl:60](../../stdlib/Concurrent/ConcurrentQueue.sl#L60)</sub>

#### DequeueOrDefault *method*

```
T DequeueOrDefault(T fallback)
```

Takes the front item, or `fallback` when there is none. `TryDequeue`
for the caller that must tell an empty queue from a stored `fallback`.

<sub>[stdlib/Concurrent/ConcurrentQueue.sl:77](../../stdlib/Concurrent/ConcurrentQueue.sl#L77)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many items there are *now*. Another thread may change it before you
act on it, so this is for reporting rather than for deciding.

<sub>[stdlib/Concurrent/ConcurrentQueue.sl:94](../../stdlib/Concurrent/ConcurrentQueue.sl#L94)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether it is empty *now*. Another thread may enqueue before you act on
the answer, so a true here does not mean the next `TryDequeue` fails.
Reach for `TryDequeue` and match on what it answers instead.

<sub>[stdlib/Concurrent/ConcurrentQueue.sl:108](../../stdlib/Concurrent/ConcurrentQueue.sl#L108)</sub>

#### ToList *method*

```
List<T> ToList()
```

A snapshot, oldest first. Consistent with itself, and out of date the
moment it is returned.

<sub>[stdlib/Concurrent/ConcurrentQueue.sl:112](../../stdlib/Concurrent/ConcurrentQueue.sl#L112)</sub>

### ConcurrentStack&lt;T&gt; *class*

```
threadsafe class ConcurrentStack<T>
```

A last-in, first-out stack several threads may use at once.

**Type parameters**

- `T` — what the stack holds; nothing is required of it, and nothing yet checks that two threads may safely hold one at once

<sub>[stdlib/Concurrent/ConcurrentStack.sl:33](../../stdlib/Concurrent/ConcurrentStack.sl#L33)</sub>

#### Push *method*

```
void Push(T item)
```

Adds to the top. Never waits for a consumer -- the stack is unbounded.

<sub>[stdlib/Concurrent/ConcurrentStack.sl:48](../../stdlib/Concurrent/ConcurrentStack.sl#L48)</sub>

#### TryPop *method*

```
Optional<T> TryPop()
```

Takes the top item if there is one. The answer and the item come back
together, because asking whether it is empty and then popping would
race with every other thread.

<sub>[stdlib/Concurrent/ConcurrentStack.sl:58](../../stdlib/Concurrent/ConcurrentStack.sl#L58)</sub>

#### PopOrDefault *method*

```
T PopOrDefault(T fallback)
```

Takes the top item, or `fallback` when there is none. A sentinel will
do here only if `fallback` is a value the stack cannot hold; `TryPop`
is the one that tells the two apart.

<sub>[stdlib/Concurrent/ConcurrentStack.sl:76](../../stdlib/Concurrent/ConcurrentStack.sl#L76)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many items there are *now*. For reporting rather than for
deciding: another thread may change it before you act on it.

<sub>[stdlib/Concurrent/ConcurrentStack.sl:93](../../stdlib/Concurrent/ConcurrentStack.sl#L93)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether it is empty *now*, with the same caveat as `Count`.

<sub>[stdlib/Concurrent/ConcurrentStack.sl:105](../../stdlib/Concurrent/ConcurrentStack.sl#L105)</sub>

#### ToList *method*

```
List<T> ToList()
```

A snapshot, top first. Consistent with itself, and out of date the
moment it is returned.

<sub>[stdlib/Concurrent/ConcurrentStack.sl:109](../../stdlib/Concurrent/ConcurrentStack.sl#L109)</sub>

