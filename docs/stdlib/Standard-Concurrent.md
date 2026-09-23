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

**Types** &nbsp; [Channel&lt;T&gt;](#channelt-class) &middot; [ConcurrentDictionary&lt;TKey, TValue&gt;](#concurrentdictionarytkey-tvalue-class) &middot; [ConcurrentQueue&lt;T&gt;](#concurrentqueuet-class) &middot; [ConcurrentStack&lt;T&gt;](#concurrentstackt-class) &middot; [Taken&lt;T&gt;](#takent-class)

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
`Ok` false.

    var channel = new Channel<String>();
    // producer:  channel.Send(line);  ... channel.Close();
    // consumer:  var got = channel.Take();
    //            while (got.Ok) { use(got.Value); got = channel.Take(); }

**Type parameters**

- `T` — what is sent through it; nothing is required of it, and nothing yet checks that the sender is done with what it sent

<sub>[stdlib/Concurrent.sl:440](../../stdlib/Concurrent.sl#L440)</sub>

#### Send *method*

```
bool Send(T item)
```

Adds an item and wakes one waiter. Sending to a closed channel changes
nothing and reports false.

<sub>[stdlib/Concurrent.sl:468](../../stdlib/Concurrent.sl#L468)</sub>

#### Take *method*

```
Taken<T> Take()
```

Waits for an item. Returns `Ok` false once the channel is closed and
drained, and not before.

<sub>[stdlib/Concurrent.sl:486](../../stdlib/Concurrent.sl#L486)</sub>

#### TryTake *method*

```
Taken<T> TryTake()
```

Takes an item if one is there already, without waiting.

<sub>[stdlib/Concurrent.sl:510](../../stdlib/Concurrent.sl#L510)</sub>

#### Close *method*

```
void Close()
```

Says there will be no more, and wakes everyone waiting. Idempotent.

<sub>[stdlib/Concurrent.sl:526](../../stdlib/Concurrent.sl#L526)</sub>

#### IsClosed *property*

```
bool IsClosed { get; }
```

Whether `Close` has been called. A closed channel may still have items
in it: this answers whether more can be sent, not whether more can be
taken. `Take`'s `Ok` is what answers that.

<sub>[stdlib/Concurrent.sl:537](../../stdlib/Concurrent.sl#L537)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many items are waiting *now* -- the producer's backlog. For
reporting rather than for deciding; a consumer should call `Take`.

<sub>[stdlib/Concurrent.sl:550](../../stdlib/Concurrent.sl#L550)</sub>

### ConcurrentDictionary&lt;TKey, TValue&gt; *class*

```
threadsafe class ConcurrentDictionary<TKey, TValue>
    where TKey : IEquatable<TKey>, IHashable
```

A map several threads may use at once.

**Type parameters**

- `TKey` — what entries are found by. It is compared and hashed on every lookup, so it must implement both `IEquatable<TKey>` and `IHashable`.
- `TValue` — what is stored against a key; nothing is required of it

<sub>[stdlib/Concurrent.sl:290](../../stdlib/Concurrent.sl#L290)</sub>

#### SetValue *method*

```
void SetValue(TKey key, TValue value)
```

Sets the value of a key, whether or not it was there. `Add` is the one
that refuses to overwrite.

<sub>[stdlib/Concurrent.sl:308](../../stdlib/Concurrent.sl#L308)</sub>

#### Add *method*

```
bool Add(TKey key, TValue value)
```

Adds the key only if it is absent, reporting whether it did. This is the
operation `ContainsKey` followed by `SetValue` cannot be: between those two
another thread can insert.

<sub>[stdlib/Concurrent.sl:318](../../stdlib/Concurrent.sl#L318)</sub>

#### TryGetValue *method*

```
Taken<TValue> TryGetValue(TKey key)
```

The value for `key` if it is there. One lock rather than two, which is
what makes it different from `ContainsKey` followed by a lookup:
between those two another thread can remove the key.

<sub>[stdlib/Concurrent.sl:329](../../stdlib/Concurrent.sl#L329)</sub>

#### GetValueOrDefault *method*

```
TValue GetValueOrDefault(TKey key, TValue fallback)
```

The value for `key`, or `fallback` when it is absent. No allocation,
at the cost of being unable to tell an absent key from one whose value
happens to equal the fallback.

<sub>[stdlib/Concurrent.sl:347](../../stdlib/Concurrent.sl#L347)</sub>

#### ContainsKey *method*

```
bool ContainsKey(TKey key)
```

Whether the key is there *now*. True here does not mean the next
`TryGetValue` succeeds -- another thread may remove it in between -- so this
is for reporting, and `TryGetValue` is for acting.

<sub>[stdlib/Concurrent.sl:358](../../stdlib/Concurrent.sl#L358)</sub>

#### Remove *method*

```
bool Remove(TKey key)
```

Removes a key, answering whether it was there. The answer is exact:
exactly one of several threads racing to remove the same key gets true.

<sub>[stdlib/Concurrent.sl:368](../../stdlib/Concurrent.sl#L368)</sub>

#### Clear *method*

```
void Clear()
```

Drops every entry, under one lock.

<sub>[stdlib/Concurrent.sl:377](../../stdlib/Concurrent.sl#L377)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many entries there are *now*. For reporting rather than deciding.

<sub>[stdlib/Concurrent.sl:385](../../stdlib/Concurrent.sl#L385)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether it is empty *now*, with the same caveat as `Count`.

<sub>[stdlib/Concurrent.sl:397](../../stdlib/Concurrent.sl#L397)</sub>

#### GetKeys *method*

```
List<TKey> GetKeys()
```

A snapshot of the keys. Out of date the moment it is returned, which is
why it is a copy rather than a view.

<sub>[stdlib/Concurrent.sl:401](../../stdlib/Concurrent.sl#L401)</sub>

#### GetValues *method*

```
List<TValue> GetValues()
```

A snapshot of the values, in the same order as `GetKeys` when neither is
interleaved with a write. Out of date the moment it is returned, and
pairing the two lists after the fact is not safe -- iterate the map if
the pairing matters.

<sub>[stdlib/Concurrent.sl:413](../../stdlib/Concurrent.sl#L413)</sub>

### ConcurrentQueue&lt;T&gt; *class*

```
threadsafe class ConcurrentQueue<T>
```

A first-in, first-out queue several threads may use at once.

**Type parameters**

- `T` — what the queue holds; nothing is required of it, and nothing yet checks that two threads may safely hold one at once

<sub>[stdlib/Concurrent.sl:100](../../stdlib/Concurrent.sl#L100)</sub>

#### Enqueue *method*

```
void Enqueue(T item)
```

Adds to the back. Blocks only for as long as the lock is held, which is
the enqueue itself; there is no bound on the queue, so this never waits
for a consumer.

<sub>[stdlib/Concurrent.sl:120](../../stdlib/Concurrent.sl#L120)</sub>

#### TryDequeue *method*

```
Taken<T> TryDequeue()
```

Takes the front item if there is one. The answer and the item come back
together, because asking twice would race.

<sub>[stdlib/Concurrent.sl:129](../../stdlib/Concurrent.sl#L129)</sub>

#### DequeueOrDefault *method*

```
T DequeueOrDefault(T fallback)
```

Takes the front item, or `fallback` when there is none. The same as
`TryDequeue` without the allocation, for when a sentinel will do.

<sub>[stdlib/Concurrent.sl:146](../../stdlib/Concurrent.sl#L146)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many items there are *now*. Another thread may change it before you
act on it, so this is for reporting rather than for deciding.

<sub>[stdlib/Concurrent.sl:163](../../stdlib/Concurrent.sl#L163)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether it is empty *now*. Another thread may enqueue before you act on
the answer, so a true here does not mean the next `TryDequeue` fails.
Reach for `TryDequeue` and read its `Ok` instead.

<sub>[stdlib/Concurrent.sl:177](../../stdlib/Concurrent.sl#L177)</sub>

#### ToList *method*

```
List<T> ToList()
```

A snapshot, oldest first. Consistent with itself, and out of date the
moment it is returned.

<sub>[stdlib/Concurrent.sl:181](../../stdlib/Concurrent.sl#L181)</sub>

### ConcurrentStack&lt;T&gt; *class*

```
threadsafe class ConcurrentStack<T>
```

A last-in, first-out stack several threads may use at once.

**Type parameters**

- `T` — what the stack holds; nothing is required of it, and nothing yet checks that two threads may safely hold one at once

<sub>[stdlib/Concurrent.sl:196](../../stdlib/Concurrent.sl#L196)</sub>

#### Push *method*

```
void Push(T item)
```

Adds to the top. Never waits for a consumer -- the stack is unbounded.

<sub>[stdlib/Concurrent.sl:213](../../stdlib/Concurrent.sl#L213)</sub>

#### TryPop *method*

```
Taken<T> TryPop()
```

Takes the top item if there is one. The answer and the item come back
together, because asking whether it is empty and then popping would
race with every other thread.

<sub>[stdlib/Concurrent.sl:223](../../stdlib/Concurrent.sl#L223)</sub>

#### PopOrDefault *method*

```
T PopOrDefault(T fallback)
```

Takes the top item, or `fallback` when there is none. The same as
`TryPop` without the allocation, for when a sentinel will do -- which
it will not if `fallback` is a value the stack might hold.

<sub>[stdlib/Concurrent.sl:241](../../stdlib/Concurrent.sl#L241)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many items there are *now*. For reporting rather than for
deciding: another thread may change it before you act on it.

<sub>[stdlib/Concurrent.sl:258](../../stdlib/Concurrent.sl#L258)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether it is empty *now*, with the same caveat as `Count`.

<sub>[stdlib/Concurrent.sl:270](../../stdlib/Concurrent.sl#L270)</sub>

#### ToList *method*

```
List<T> ToList()
```

A snapshot, top first. Consistent with itself, and out of date the
moment it is returned.

<sub>[stdlib/Concurrent.sl:274](../../stdlib/Concurrent.sl#L274)</sub>

### Taken&lt;T&gt; *class*

```
class Taken<T>
```

What a take returned: whether there was anything, and what it was.

`Value` means nothing when `Ok` is false -- it holds whatever a zeroed slot
holds. Check `Ok` first. The pair exists because a concurrent container
cannot answer "is it empty?" and "give me the front" as two questions.

**Type parameters**

- `T` — what the container holds, and so what a take can hand back

<sub>[stdlib/Concurrent.sl:76](../../stdlib/Concurrent.sl#L76)</sub>

#### Ok *property*

```
bool Ok { get; }
```

Whether there was anything to take. Read this before `Value`.

<sub>[stdlib/Concurrent.sl:79](../../stdlib/Concurrent.sl#L79)</sub>

#### Value *property*

```
T Value { get; }
```

What was taken, meaningful only when `Ok` is true. Otherwise it is
whatever a zeroed slot holds -- null for a reference, zero for a
number -- and not a value the container ever contained.

<sub>[stdlib/Concurrent.sl:84](../../stdlib/Concurrent.sl#L84)</sub>

