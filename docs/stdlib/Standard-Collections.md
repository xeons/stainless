# Standard.Collections

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

The Stainless standard collections.

Unlike Standard.Text, nothing here needs runtime support: it is ordinary
Stainless, compiled alongside your program. Generic declarations cost nothing
until they are instantiated, so importing this module and using none of it
emits no code at all.

Interfaces are named with a leading I, as in C#.

## Contents

**Types** &nbsp; [Dictionary&lt;TKey, TValue&gt;](#dictionarytkey-tvalue-class) &middot; [DictionaryEnumerator&lt;TKey, TValue&gt;](#dictionaryenumeratortkey-tvalue-class) &middot; [HashSet&lt;T&gt;](#hashsett-class) &middot; [HashSetCursor&lt;T&gt;](#hashsetcursort-class) &middot; [IComparable&lt;T&gt;](#icomparablet-interface) &middot; [IEnumerable&lt;T&gt;](#ienumerablet-interface) &middot; [IEnumerator&lt;T&gt;](#ienumeratort-interface) &middot; [IEquatable&lt;T&gt;](#iequatablet-interface) &middot; [IHashable](#ihashable-interface) &middot; [IList&lt;T&gt;](#ilistt-interface) &middot; [IReadOnlyList&lt;T&gt;](#ireadonlylistt-interface) &middot; [LinkedList&lt;T&gt;](#linkedlistt-class) &middot; [LinkedListCursor&lt;T&gt;](#linkedlistcursort-class) &middot; [List&lt;T&gt;](#listt-class) &middot; [ListEnumerator&lt;T&gt;](#listenumeratort-class) &middot; [OrderedDictionary&lt;TKey, TValue&gt;](#ordereddictionarytkey-tvalue-class) &middot; [Pair&lt;TKey, TValue&gt;](#pairtkey-tvalue-class) &middot; [Queue&lt;T&gt;](#queuet-class) &middot; [QueueCursor&lt;T&gt;](#queuecursort-class) &middot; [SortedList&lt;TKey, TValue&gt;](#sortedlisttkey-tvalue-class) &middot; [SortedListCursor&lt;TKey, TValue&gt;](#sortedlistcursortkey-tvalue-class) &middot; [Stack&lt;T&gt;](#stackt-class) &middot; [StackCursor&lt;T&gt;](#stackcursort-class)

**Functions** &nbsp; [Aggregate](#aggregate-function) &middot; [Aggregate](#aggregate-function) &middot; [All](#all-function) &middot; [All](#all-function) &middot; [Any](#any-function) &middot; [Any](#any-function) &middot; [BinarySearch](#binarysearch-function) &middot; [Contains](#contains-function) &middot; [Count](#count-function) &middot; [Count](#count-function) &middot; [Distinct](#distinct-function) &middot; [Distinct](#distinct-function) &middot; [Find](#find-function) &middot; [FindIndex](#findindex-function) &middot; [FindLowerBound](#findlowerbound-function) &middot; [FirstOrDefault](#firstordefault-function) &middot; [FirstOrDefault](#firstordefault-function) &middot; [ForEach](#foreach-function) &middot; [ForEach](#foreach-function) &middot; [IndexOf](#indexof-function) &middot; [LastIndexOf](#lastindexof-function) &middot; [Max](#max-function) &middot; [Min](#min-function) &middot; [OrderBy](#orderby-function) &middot; [OrderBy](#orderby-function) &middot; [RemoveFirst](#removefirst-function) &middot; [RemoveWhere](#removewhere-function) &middot; [Reverse](#reverse-function) &middot; [Select](#select-function) &middot; [Select](#select-function) &middot; [Skip](#skip-function) &middot; [Skip](#skip-function) &middot; [Sort](#sort-function) &middot; [Sort](#sort-function) &middot; [Sort](#sort-function) &middot; [Sort](#sort-function) &middot; [Take](#take-function) &middot; [Take](#take-function) &middot; [ToArray](#toarray-function) &middot; [ToArray](#toarray-function) &middot; [ToList](#tolist-function) &middot; [ToList](#tolist-function) &middot; [Where](#where-function) &middot; [Where](#where-function)

## Types

### Dictionary&lt;TKey, TValue&gt; *class*

```
class Dictionary<TKey, TValue> : IEnumerable<Pair<TKey, TValue>>
    where TKey : IEquatable<TKey>, IHashable
```

A map from keys to values.

`K` has to be equatable and hashable. A primitive, an enum and a String all
are without saying so, so `Dictionary<String, int>` needs nothing extra; a
class says so by implementing `IEquatable<T>` and `IHashable`.

<sub>[stdlib/Dictionary.sl:65](../../stdlib/Dictionary.sl#L65)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many entries there are. O(1) -- it is a counter, not a scan.

<sub>[stdlib/Dictionary.sl:84](../../stdlib/Dictionary.sl#L84)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when there are no entries.

<sub>[stdlib/Dictionary.sl:87](../../stdlib/Dictionary.sl#L87)</sub>

#### Capacity *property*

```
nuint Capacity { get; }
```

The number of slots the table has. Always a power of two, so the hash is
reduced with a mask rather than a division.

<sub>[stdlib/Dictionary.sl:91](../../stdlib/Dictionary.sl#L91)</sub>

#### ContainsKey *method*

```
bool ContainsKey(TKey key)
```

Whether `key` is there.

One probe, but reach for `Find` when the value is what is wanted:
`ContainsKey` and then `GetValue` probes twice for one answer.

<sub>[stdlib/Dictionary.sl:113](../../stdlib/Dictionary.sl#L113)</sub>

#### Find *method*

```
Optional<TValue> Find(TKey key)
```

The value for `key`, or `None` when there is none.

**This is the one to reach for.** A key is data -- it arrives from a
file, a socket or a user -- so a key that is not there is an ordinary
outcome and not a mistake in the program, which is the line §2.6 draws
between a value to return and a reason to stop. The answer is read the
way any other variant is:

    if (settings.Find(name) is Some value) { Use(value); }

One probe, where `ContainsKey` followed by `GetValue` is two, and no sentinel
to collide with a real value the way `GetValueOrDefault` has.

<sub>[stdlib/Dictionary.sl:127](../../stdlib/Dictionary.sl#L127)</sub>

#### GetValue *method*

```
TValue GetValue(TKey key)
```

The value for `key`, aborting when there is none.

The asserting form, and it asserts: use it only where the key is there
by construction -- one set two lines above, or a name this code chose
itself. `GetValue` means the same thing here as on `Optional`, which is that
the caller is claiming the value exists and would rather stop than
carry on if it does not. For a key that came from anywhere else, `Find`
is the question and this is not.

<sub>[stdlib/Dictionary.sl:143](../../stdlib/Dictionary.sl#L143)</sub>

#### GetValueOrDefault *method*

```
TValue GetValueOrDefault(TKey key, TValue fallback)
```

The value for `key`, or `fallback` when there is none.

<sub>[stdlib/Dictionary.sl:152](../../stdlib/Dictionary.sl#L152)</sub>

#### this[] *indexer*

```
Optional<TValue> this[TKey key] { get; set; }
```

`map[key]`, which answers `Optional<TValue>` and never stops the program.

Swift's design, and it is the right one for the same reason: a key is
data rather than a position, so a lookup that misses is an answer. An
indexer returning `TValue` would have to abort on a miss, and `map[key]`
carries no verb to warn anyone that it might -- which is exactly the
shape a reader trusts without thinking.

    if (settings["timeout"] is Some found) { Use(found.Value); }
    int port = settings["port"].GetValueOrDefault(8080);

A getter and a setter share one type (§7.5), so the setter takes an
`Optional<TValue>` too -- and that turns out to say something rather than
being a cost. A value promotes to the optional holding it, so an
ordinary write reads as one; and `None` is the absence of a value,
which is what removing a key means.

    settings["retries"] = 3;            // set
    settings["retries"] = None;         // remove

What this cannot do is `map[key] += 1`, because there is no value to
add to when the key is absent. That is not a limitation so much as the
question being asked out loud: `map[key] = map[key].GetValueOrDefault(0) + 1`
says what should happen, and Swift's `dict[key, default: 0] += 1`
exists for the same reason.

<sub>[stdlib/Dictionary.sl:185](../../stdlib/Dictionary.sl#L185)</sub>

#### SetValue *method*

```
void SetValue(TKey key, TValue value)
```

Adds the key or replaces what it maps to.

<sub>[stdlib/Dictionary.sl:202](../../stdlib/Dictionary.sl#L202)</sub>

#### Add *method*

```
bool Add(TKey key, TValue value)
```

Adds the key, or reports that it was already there and changes nothing.

<sub>[stdlib/Dictionary.sl:225](../../stdlib/Dictionary.sl#L225)</sub>

#### Remove *method*

```
bool Remove(TKey key)
```

Removes the key, reporting whether it was there.

<sub>[stdlib/Dictionary.sl:234](../../stdlib/Dictionary.sl#L234)</sub>

#### Clear *method*

```
void Clear()
```

Drops every entry. The arrays are replaced rather than blanked, so
anything they held is released now.

<sub>[stdlib/Dictionary.sl:275](../../stdlib/Dictionary.sl#L275)</sub>

#### GetKeys *method*

```
List<TKey> GetKeys()
```

Every key, in the table's own order.

A fresh list, so changing it changes nothing here, and building it is a
scan of every slot rather than of every entry -- O(capacity), not
O(count). Pairs with `GetValues` position for position as long as nothing
is written in between.

<sub>[stdlib/Dictionary.sl:289](../../stdlib/Dictionary.sl#L289)</sub>

#### GetValues *method*

```
List<TValue> GetValues()
```

Every value, in the same order `GetKeys` gives.

Values are not distinct: a value stored under two keys appears twice.

<sub>[stdlib/Dictionary.sl:303](../../stdlib/Dictionary.sl#L303)</sub>

#### GetEnumerator *method*

```
IEnumerator<Pair<TKey, TValue>> GetEnumerator()
```

A cursor over the entries, for `foreach`.

The order is the table's and is not insertion order; it changes when
the table grows. `Standard.Collections.OrderedDictionary` is the one
that keeps an order. Adding or removing during a walk invalidates the
cursor.

<sub>[stdlib/Dictionary.sl:320](../../stdlib/Dictionary.sl#L320)</sub>

### DictionaryEnumerator&lt;TKey, TValue&gt; *class*

```
class DictionaryEnumerator<TKey, TValue> : IEnumerator<Pair<TKey, TValue>>
    where TKey : IEquatable<TKey>, IHashable
```

Walks a dictionary's slots, skipping the empty ones.

The order is the table's own and says nothing about insertion order; adding
or removing during a walk invalidates it, as it does in C#.

<sub>[stdlib/Dictionary.sl:361](../../stdlib/Dictionary.sl#L361)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances to the next occupied slot, answering false at the end. Each
call skips however many empty slots lie between, so a walk costs
O(capacity) overall rather than O(count).

<sub>[stdlib/Dictionary.sl:381](../../stdlib/Dictionary.sl#L381)</sub>

#### Current *property*

```
Pair<TKey, TValue> Current { get; }
```

The entry the last `MoveNext` landed on, as a freshly built `Pair`.

<sub>[stdlib/Dictionary.sl:394](../../stdlib/Dictionary.sl#L394)</sub>

### HashSet&lt;T&gt; *class*

```
class HashSet<T> : IEnumerable<T>
    where T : IEquatable<T>, IHashable
```

A set of distinct values, with membership in constant time.

The same table as `Dictionary`, without the values.

<sub>[stdlib/Dictionary.sl:402](../../stdlib/Dictionary.sl#L402)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many distinct items there are. O(1).

<sub>[stdlib/Dictionary.sl:419](../../stdlib/Dictionary.sl#L419)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when there is nothing in it.

<sub>[stdlib/Dictionary.sl:422](../../stdlib/Dictionary.sl#L422)</sub>

#### Capacity *property*

```
nuint Capacity { get; }
```

The number of slots the table has. Always a power of two, so the hash
is reduced with a mask rather than a division.

<sub>[stdlib/Dictionary.sl:426](../../stdlib/Dictionary.sl#L426)</sub>

#### Contains *method*

```
bool Contains(T item)
```

Whether `item` is in the set. One probe, and the question the whole
collection exists to answer.

<sub>[stdlib/Dictionary.sl:444](../../stdlib/Dictionary.sl#L444)</sub>

#### Add *method*

```
bool Add(T item)
```

Adds the item, reporting whether it was new.

<sub>[stdlib/Dictionary.sl:447](../../stdlib/Dictionary.sl#L447)</sub>

#### Remove *method*

```
bool Remove(T item)
```

Removes the item, reporting whether it was there.

<sub>[stdlib/Dictionary.sl:466](../../stdlib/Dictionary.sl#L466)</sub>

#### Clear *method*

```
void Clear()
```

Drops every item. The arrays are replaced rather than blanked, so
anything they held is released now.

<sub>[stdlib/Dictionary.sl:498](../../stdlib/Dictionary.sl#L498)</sub>

#### UnionWith *method*

```
void UnionWith(IReadOnlyList<T> other)
```

Adds everything in `other` that is not here already.

<sub>[stdlib/Dictionary.sl:506](../../stdlib/Dictionary.sl#L506)</sub>

#### ExceptWith *method*

```
void ExceptWith(IReadOnlyList<T> other)
```

Removes everything in `other`.

<sub>[stdlib/Dictionary.sl:513](../../stdlib/Dictionary.sl#L513)</sub>

#### IntersectWith *method*

```
void IntersectWith(HashSet<T> other)
```

Keeps only what is also in `other`.

<sub>[stdlib/Dictionary.sl:520](../../stdlib/Dictionary.sl#L520)</sub>

#### ToList *method*

```
List<T> ToList()
```

Every item, in the table's own order -- which is not insertion order
and changes when the table grows.

A fresh list, and building it scans every slot: O(capacity), not
O(count). `foreach` walks the set without building one.

<sub>[stdlib/Dictionary.sl:537](../../stdlib/Dictionary.sl#L537)</sub>

#### GetEnumerator *method*

```
IEnumerator<T> GetEnumerator()
```

A cursor over the items, for `foreach`. Allocates nothing beyond the
cursor itself, unlike `ToList`. Adding or removing during a walk
invalidates it.

<sub>[stdlib/Dictionary.sl:557](../../stdlib/Dictionary.sl#L557)</sub>

### HashSetCursor&lt;T&gt; *class*

```
class HashSetCursor<T> : IEnumerator<T>
    where T : IEquatable<T>, IHashable
```

Walks a set's table, skipping the empty slots.

The same shape as `DictionaryEnumerator`, and for the same reason: the
materialising version built a whole `List<T>` before the first `MoveNext`,
so iterating a set allocated as much again as the set held.

<sub>[stdlib/Dictionary.sl:586](../../stdlib/Dictionary.sl#L586)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances to the next occupied slot, answering false at the end.

<sub>[stdlib/Dictionary.sl:602](../../stdlib/Dictionary.sl#L602)</sub>

#### Current *property*

```
T Current { get; }
```

The item the last `MoveNext` landed on.

<sub>[stdlib/Dictionary.sl:615](../../stdlib/Dictionary.sl#L615)</sub>

### IComparable&lt;T&gt; *interface*

```
interface IComparable<T>
```

Returns a negative number, zero, or a positive number when this value orders
before, with, or after `other`.

<sub>[stdlib/Collections.sl:54](../../stdlib/Collections.sl#L54)</sub>

#### CompareTo *method*

```
int CompareTo(T other)
```

Negative when this orders before `other`, zero when they order
together, positive when after. The sign is all that is read -- the
magnitude means nothing, so returning a subtraction is fine as long as
it cannot overflow.

<sub>[stdlib/Collections.sl:60](../../stdlib/Collections.sl#L60)</sub>

### IEnumerable&lt;T&gt; *interface*

```
interface IEnumerable<T>
```

Something that can be walked from the start, once per enumerator.

`foreach` does not need this interface -- it finds `GetEnumerator` by name
-- so implementing it is about being passable as a sequence, not about
being iterable.

<sub>[stdlib/Collections.sl:113](../../stdlib/Collections.sl#L113)</sub>

#### GetEnumerator *method*

```
IEnumerator<T> GetEnumerator()
```

A fresh cursor positioned before the first item. Each call gives an
independent one, so a sequence can be walked twice; what is not
promised is that the two walks see the same items, since a collection
changed in between will say something different.

<sub>[stdlib/Collections.sl:119](../../stdlib/Collections.sl#L119)</sub>

### IEnumerator&lt;T&gt; *interface*

```
interface IEnumerator<T>
```

A cursor over a sequence. `MoveNext` advances and reports whether there was
anything to advance to; `Current` returns what it landed on.

`foreach` does not require this interface -- it looks for the methods by
name, so any type with a `GetEnumerator()` can be iterated. Naming the shape
is still worth doing, because it lets a sequence be passed around.

<sub>[stdlib/Collections.sl:95](../../stdlib/Collections.sl#L95)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances to the next item and reports whether there was one. Must be
called before the first `Current`: a fresh enumerator sits before the
start rather than on the first item.

<sub>[stdlib/Collections.sl:100](../../stdlib/Collections.sl#L100)</sub>

#### Current *property*

```
T Current { get; }
```

What the last `MoveNext` landed on. Calling this before the first
`MoveNext`, or after one that answered false, is a mistake the
enumerator is not required to catch.

<sub>[stdlib/Collections.sl:105](../../stdlib/Collections.sl#L105)</sub>

### IEquatable&lt;T&gt; *interface*

```
interface IEquatable<T>
```

A value that can be asked whether it equals another of its type.

`EqualTo` has to be an equivalence -- a value equals itself, equality runs
both ways, and two things equal to a third are equal to each other --
because the containers assume all three and none of them checks. A type
used as a dictionary key implements `IHashable` alongside this, and the two
must agree: equal values must hash alike.

<sub>[stdlib/Collections.sl:45](../../stdlib/Collections.sl#L45)</sub>

#### EqualTo *method*

```
bool EqualTo(T other)
```

True when this value and `other` are the same value. Implementations
should answer without allocating; this runs once per probe.

<sub>[stdlib/Collections.sl:49](../../stdlib/Collections.sl#L49)</sub>

### IHashable *interface*

```
interface IHashable
```

A value that can be a key in a hash table.

Two values that are `EqualTo` each other must return the same `HashCode`;
two that are not may still collide, and the table handles it. A type that
implements this should implement `IEquatable<T>` as well, since a hash on
its own only narrows the search.

<sub>[stdlib/Collections.sl:69](../../stdlib/Collections.sl#L69)</sub>

#### HashCode *method*

```
nuint HashCode()
```

A number standing in for this value. The same value must give the same
number for as long as it is a key in a table, which means hashing only
the parts a key is not going to have changed under it.

<sub>[stdlib/Collections.sl:74](../../stdlib/Collections.sl#L74)</sub>

### IList&lt;T&gt; *interface*

```
interface IList<T> : IReadOnlyList<T>
```

Everything a read-only list offers, plus mutation. A value of this type can
be passed anywhere an IReadOnlyList is wanted, at no cost: an interface
reference is a plain pointer, and the object carries a table for both.

<sub>[stdlib/Collections.sl:179](../../stdlib/Collections.sl#L179)</sub>

#### this[] *indexer*

```
T this[nuint index] { get; set; }
```

The item at `index`, readable and writable. Redeclared because an
interface cannot widen an inherited member from get-only to get-set.

<sub>[stdlib/Collections.sl:183](../../stdlib/Collections.sl#L183)</sub>

#### Add *method*

```
void Add(T item)
```

Appends to the end.

<sub>[stdlib/Collections.sl:186](../../stdlib/Collections.sl#L186)</sub>

#### RemoveAt *method*

```
void RemoveAt(nuint index)
```

Removes the item at `index`, closing the gap.

<sub>[stdlib/Collections.sl:189](../../stdlib/Collections.sl#L189)</sub>

#### Clear *method*

```
void Clear()
```

Drops every item, leaving a length of zero.

<sub>[stdlib/Collections.sl:192](../../stdlib/Collections.sl#L192)</sub>

### IReadOnlyList&lt;T&gt; *interface*

```
interface IReadOnlyList<T>
```

A sequence that knows its length and can be indexed, and cannot be changed
through this reference.

Read-only is about what this interface offers, not about the object: the
list behind it may well be a `List<T>` that someone else is still adding
to. Take this as a parameter type where a function reads and does not
write, which says so in the signature.

<sub>[stdlib/Collections.sl:163](../../stdlib/Collections.sl#L163)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many items there are.

<sub>[stdlib/Collections.sl:166](../../stdlib/Collections.sl#L166)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether there are none.

<sub>[stdlib/Collections.sl:169](../../stdlib/Collections.sl#L169)</sub>

#### this[] *indexer*

```
T this[nuint index] { get; }
```

The item at `index`, counting from zero. An index at or past `Count`
aborts with the same message an array overrun gives.

<sub>[stdlib/Collections.sl:173](../../stdlib/Collections.sl#L173)</sub>

### LinkedList&lt;T&gt; *class*

```
class LinkedList<T> : IEnumerable<T>
```

A doubly linked list whose links are indices into a pool rather than
references.

A node is named by a **handle**: a `nint` that stays valid until that node is
removed, and is `-1` for "no node". Handles are what make the middle of the
list reachable in constant time, which is the only reason to choose this
over a `List<T>`:

```csharp
var line = new LinkedList<String>();
var first = line.AddLast("a");
line.AddLast("c");
line.InsertAfter(first, "b");

for (nint at = line.First; at >= 0; at = line.GetNext(at)) {
    Console.WriteLine(line.GetValueAt(at));
}
```

Removed nodes are recycled, so a list that is added to and removed from
steadily does not grow without bound.

<sub>[stdlib/Sequences.sl:254](../../stdlib/Sequences.sl#L254)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many nodes are linked in. O(1), and not the size of the pool --
recycled slots are not counted.

<sub>[stdlib/Sequences.sl:283](../../stdlib/Sequences.sl#L283)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when nothing is linked in.

<sub>[stdlib/Sequences.sl:286](../../stdlib/Sequences.sl#L286)</sub>

#### First *property*

```
nint First { get; }
```

A handle to the first node, or -1 when the list is empty.

<sub>[stdlib/Sequences.sl:289](../../stdlib/Sequences.sl#L289)</sub>

#### Last *property*

```
nint Last { get; }
```

A handle to the last node, or -1 when the list is empty.

<sub>[stdlib/Sequences.sl:292](../../stdlib/Sequences.sl#L292)</sub>

#### GetNext *method*

```
nint GetNext(nint handle)
```

The node after `handle`, or -1 at the end.

<sub>[stdlib/Sequences.sl:295](../../stdlib/Sequences.sl#L295)</sub>

#### GetPrevious *method*

```
nint GetPrevious(nint handle)
```

The node before `handle`, or -1 at the start.

<sub>[stdlib/Sequences.sl:298](../../stdlib/Sequences.sl#L298)</sub>

#### GetValueAt *method*

```
T GetValueAt(nint handle)
```

The value in a node.

`handle` must be live: one this list handed out and has not had
`RemoveAt` called on. A stale or `-1` handle is not checked and reads
whatever the pool slot now holds, so test `at >= 0` before walking.

<sub>[stdlib/Sequences.sl:305](../../stdlib/Sequences.sl#L305)</sub>

#### SetValueAt *method*

```
void SetValueAt(nint handle, T value)
```

Replaces the value in a node, leaving the links alone. Same
requirement on `handle` as `GetValueAt`.

<sub>[stdlib/Sequences.sl:309](../../stdlib/Sequences.sl#L309)</sub>

#### AddFirst *method*

```
nint AddFirst(T item)
```

Links a new node at the front and answers its handle. Constant time.

<sub>[stdlib/Sequences.sl:312](../../stdlib/Sequences.sl#L312)</sub>

#### AddLast *method*

```
nint AddLast(T item)
```

Links a new node at the back and answers its handle. Constant time --
the tail is kept, so this does not walk the list.

<sub>[stdlib/Sequences.sl:335](../../stdlib/Sequences.sl#L335)</sub>

#### InsertAfter *method*

```
nint InsertAfter(nint handle, T item)
```

Links a new node just after `handle` and answers its handle. Constant
time, and the reason to choose this over a `List<T>`. Inserting after
the last node appends.

<sub>[stdlib/Sequences.sl:359](../../stdlib/Sequences.sl#L359)</sub>

#### InsertBefore *method*

```
nint InsertBefore(nint handle, T item)
```

Links a new node just before `handle` and answers its handle.
Inserting before the first node prepends.

<sub>[stdlib/Sequences.sl:377](../../stdlib/Sequences.sl#L377)</sub>

#### RemoveAt *method*

```
void RemoveAt(nint handle)
```

Unlinks a node and recycles its slot. The handle is dead afterwards.

<sub>[stdlib/Sequences.sl:386](../../stdlib/Sequences.sl#L386)</sub>

#### RemoveFirst *method*

```
T RemoveFirst()
```

Removes and returns the first item. Aborts when the list is empty.

<sub>[stdlib/Sequences.sl:417](../../stdlib/Sequences.sl#L417)</sub>

#### RemoveLast *method*

```
T RemoveLast()
```

Removes and returns the last item. Aborts when the list is empty.

<sub>[stdlib/Sequences.sl:428](../../stdlib/Sequences.sl#L428)</sub>

#### Clear *method*

```
void Clear()
```

Drops every node and the pool with it. Every handle previously handed
out is dead afterwards.

<sub>[stdlib/Sequences.sl:440](../../stdlib/Sequences.sl#L440)</sub>

#### ToList *method*

```
List<T> ToList()
```

The values, head first, as a fresh list. O(n), following the links.

<sub>[stdlib/Sequences.sl:453](../../stdlib/Sequences.sl#L453)</sub>

#### GetEnumerator *method*

```
IEnumerator<T> GetEnumerator()
```

A cursor over the values, head first, for `foreach`. Follows the links
and keeps its place, so a whole walk is O(n). Adding or removing during
a walk invalidates it.

<sub>[stdlib/Sequences.sl:470](../../stdlib/Sequences.sl#L470)</sub>

### LinkedListCursor&lt;T&gt; *class*

```
class LinkedListCursor<T> : IEnumerator<T>
```

Walks a linked list head first, following the links rather than flattening
them. `At` is O(n) from the head, so a cursor that used it would make
iterating O(n squared); this keeps the node it reached.

<sub>[stdlib/Sequences.sl:796](../../stdlib/Sequences.sl#L796)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Follows one link, answering false past the tail.

<sub>[stdlib/Sequences.sl:811](../../stdlib/Sequences.sl#L811)</sub>

#### Current *property*

```
T Current { get; }
```

The value in the node the last `MoveNext` reached.

<sub>[stdlib/Sequences.sl:827](../../stdlib/Sequences.sl#L827)</sub>

### List&lt;T&gt; *class*

```
class List<T> : IList<T>, IEnumerable<T>
```

A growable list backed by a single array, doubling when it fills.

**The shape is .NET's `List<T>`.** A standard library that renames what
everyone already knows charges for it at every lookup, so the members here
are spelled the way C# spells them and mean what C# means.

Two deliberate differences, both stated rather than discovered:

- **`IsEmpty` is a property and .NET has no such member at all.** It reads
  better than `Count == 0` at the point of use, and
  [docs/style.md](docs/style.md) is the reason it is a property and not a
  method: a zero-argument side-effect-free getter is a property here.
- **The members that compare two `T`s are free functions below**, not
  methods. `Contains`, `IndexOf`, `RemoveFirst`, `Sort` and `BinarySearch` all
  need `T : IEquatable<T>` or `IComparable<T>`, and this class constrains
  `T` not at all -- a `List<Control>` has to stay possible. A class cannot
  demand of one method's type parameter what it does not demand of every
  element. .NET reaches them through `EqualityComparer<T>.Default`, which is
  a runtime lookup this language has no equivalent of.

The members taking a predicate need no constraint, so those are methods,
exactly as in .NET.

<sub>[stdlib/Collections.sl:217](../../stdlib/Collections.sl#L217)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many items are in the list -- not how many it has room for, which
is `Capacity`.

<sub>[stdlib/Collections.sl:240](../../stdlib/Collections.sl#L240)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether there is nothing in it.

<sub>[stdlib/Collections.sl:243](../../stdlib/Collections.sl#L243)</sub>

#### Capacity *property*

```
nuint Capacity { get; set; }
```

The number of items this list can hold before it must grow again.

Settable, as in .NET: assigning reallocates to exactly that size. A
value below `Count` is ignored rather than truncating, because losing
items is not what anyone means by reserving room.

<sub>[stdlib/Collections.sl:250](../../stdlib/Collections.sl#L250)</sub>

#### this[] *indexer*

```
T this[nuint index] { get; set; }
```

The item at `index`, aborting past the end.

Checked against `Count` rather than against the backing array, so a
slot that exists but holds nothing is out of range and says so.

**This is the only way to reach an item.** There were `At` and `Set`
methods beside it and they are gone: two spellings of one operation is
how a codebase ends up using the longer one everywhere, which is what
had happened here.

<sub>[stdlib/Collections.sl:270](../../stdlib/Collections.sl#L270)</sub>

#### Add *method*

```
void Add(T item)
```

Appends to the end, growing the backing array when it is full.

Doubling, so a run of appends costs constant time each on average; a
single one can cost a copy of everything so far.

<sub>[stdlib/Collections.sl:290](../../stdlib/Collections.sl#L290)</sub>

#### AddRange *method*

```
void AddRange(IEnumerable<T> items)
```

Appends every item of another sequence, in its order.

The items are collected before any is added, so a list given itself
doubles rather than chasing its own growing end.

<sub>[stdlib/Collections.sl:302](../../stdlib/Collections.sl#L302)</sub>

#### Insert *method*

```
void Insert(nuint index, T item)
```

Inserts at a position, moving everything after it up one.

`index == Count` appends, which is what makes a loop that inserts in
order need no special case at the end.

<sub>[stdlib/Collections.sl:308](../../stdlib/Collections.sl#L308)</sub>

#### RemoveAt *method*

```
void RemoveAt(nuint index)
```

Removes the item at a position, closing the gap.

The vacated slot is cleared rather than left holding what moved out of
it: a list of references would otherwise keep the last one alive past
its removal, which is a leak that only shows up under a profiler.

<sub>[stdlib/Collections.sl:328](../../stdlib/Collections.sl#L328)</sub>

#### RemoveRange *method*

```
void RemoveRange(nuint index, nuint count)
```

Removes `count` items from `index` onwards.

<sub>[stdlib/Collections.sl:341](../../stdlib/Collections.sl#L341)</sub>

#### RemoveAll *method*

```
nuint RemoveAll(Predicate<T> matches)
```

Removes every item the predicate accepts, and answers how many went.

One pass that compacts in place, so removing half a list costs one
traversal rather than one shuffle per removal.

<sub>[stdlib/Collections.sl:360](../../stdlib/Collections.sl#L360)</sub>

#### Reverse *method*

```
void Reverse()
```

Reverses the list in place.

<sub>[stdlib/Collections.sl:380](../../stdlib/Collections.sl#L380)</sub>

#### ToArray *method*

```
T[] ToArray()
```

The items as a new array, which the caller owns.

<sub>[stdlib/Collections.sl:391](../../stdlib/Collections.sl#L391)</sub>

#### CopyTo *method*

```
void CopyTo(T[] into, nuint at)
```

Copies the items into `into`, starting at `at`.

<sub>[stdlib/Collections.sl:400](../../stdlib/Collections.sl#L400)</sub>

#### GetRange *method*

```
List<T> GetRange(nuint index, nuint count)
```

A new list holding `count` items from `index` onwards.

<sub>[stdlib/Collections.sl:409](../../stdlib/Collections.sl#L409)</sub>

#### Find *method*

```
T Find(Predicate<T> matches)
```

The first item the predicate accepts, or `default(T)` when there is
none -- which is `null` for a reference type, as it is in .NET.

<sub>[stdlib/Collections.sl:422](../../stdlib/Collections.sl#L422)</sub>

#### FindLast *method*

```
T FindLast(Predicate<T> matches)
```

The last item the predicate accepts, or `default(T)`.

<sub>[stdlib/Collections.sl:433](../../stdlib/Collections.sl#L433)</sub>

#### FindAll *method*

```
List<T> FindAll(Predicate<T> matches)
```

Every item the predicate accepts, in order.

<sub>[stdlib/Collections.sl:444](../../stdlib/Collections.sl#L444)</sub>

#### FindIndex *method*

```
Optional<nuint> FindIndex(Predicate<T> matches)
```

Where the first item the predicate accepts is, or `None`.

**An `Optional<nuint>`, where .NET answers -1.** The sentinel is the
thing `Optional<T>` exists to retire, `IndexOf` below already answers
this way, and an index that is a `nuint` cannot hold -1 at all. This is
the one place the shape deliberately departs from C#, and it departs
because C#'s shape is a workaround for a type it does not have.

<sub>[stdlib/Collections.sl:462](../../stdlib/Collections.sl#L462)</sub>

#### FindLastIndex *method*

```
Optional<nuint> FindLastIndex(Predicate<T> matches)
```

Where the last item the predicate accepts is, or `None`.

<sub>[stdlib/Collections.sl:473](../../stdlib/Collections.sl#L473)</sub>

#### Exists *method*

```
bool Exists(Predicate<T> matches)
```

Whether any item is accepted by the predicate.

<sub>[stdlib/Collections.sl:484](../../stdlib/Collections.sl#L484)</sub>

#### TrueForAll *method*

```
bool TrueForAll(Predicate<T> matches)
```

Whether every item is.

<sub>[stdlib/Collections.sl:487](../../stdlib/Collections.sl#L487)</sub>

#### ForEach *method*

```
void ForEach(Action<T> action)
```

Runs `action` over each item, in order.

The list is read as it goes, so an action that adds to it is a loop
that does not end. .NET throws for this; there is nothing to throw
here, and saying so is the whole of what can be done about it.

<sub>[stdlib/Collections.sl:502](../../stdlib/Collections.sl#L502)</sub>

#### EnsureCapacity *method*

```
nuint EnsureCapacity(nuint capacity)
```

Makes sure there is room for `capacity` items, and answers the capacity
afterwards. Never shrinks.

<sub>[stdlib/Collections.sl:512](../../stdlib/Collections.sl#L512)</sub>

#### TrimExcess *method*

```
void TrimExcess()
```

Gives back the room past `Count`.

<sub>[stdlib/Collections.sl:520](../../stdlib/Collections.sl#L520)</sub>

#### Slice *method*

```
List<T> Slice(nuint index, nuint count)
```

`count` items from `index`, as a new list. .NET's name for `GetRange`
since ranges arrived, and the two are the same call.

<sub>[stdlib/Collections.sl:528](../../stdlib/Collections.sl#L528)</sub>

#### InsertRange *method*

```
void InsertRange(nuint index, IEnumerable<T> items)
```

Inserts every item of another sequence at `index`, in its order.

Collected first, for the reason `AddRange` gives, and then moved into
place with one shift of the tail rather than one per item.

<sub>[stdlib/Collections.sl:534](../../stdlib/Collections.sl#L534)</sub>

#### AsReadOnly *method*

```
IReadOnlyList<T> AsReadOnly()
```

This list seen as something that cannot be changed through it.

**The same object, not a copy.** .NET answers a `ReadOnlyCollection<T>`
wrapper for the same reason this answers an interface: what it buys is a
signature that says "I will not write to this", and neither stops the
owner writing to it meanwhile.

<sub>[stdlib/Collections.sl:567](../../stdlib/Collections.sl#L567)</sub>

#### GetEnumerator *method*

```
IEnumerator<T> GetEnumerator()
```

A cursor over this list, for `foreach` and for passing it on as a
sequence. The cursor reads the list as it goes rather than taking a
copy, so changing the list during a walk changes what the walk sees.

<sub>[stdlib/Collections.sl:572](../../stdlib/Collections.sl#L572)</sub>

#### Clear *method*

```
void Clear()
```

Drops every item. The backing array is replaced rather than merely
forgotten, so any references it held are released now instead of
lingering until the slots are overwritten.

<sub>[stdlib/Collections.sl:577](../../stdlib/Collections.sl#L577)</sub>

### ListEnumerator&lt;T&gt; *class*

```
class ListEnumerator<T> : IEnumerator<T>
```

Walks anything that can be counted and indexed, so one enumerator serves
every list rather than each list writing its own.

<sub>[stdlib/Collections.sl:124](../../stdlib/Collections.sl#L124)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances, answering false at the end.

<sub>[stdlib/Collections.sl:142](../../stdlib/Collections.sl#L142)</sub>

#### Current *property*

```
T Current { get; }
```

The item the last `MoveNext` landed on.

<sub>[stdlib/Collections.sl:151](../../stdlib/Collections.sl#L151)</sub>

### OrderedDictionary&lt;TKey, TValue&gt; *class*

```
class OrderedDictionary<TKey, TValue>
    where TKey : IEquatable<TKey>
```

A dictionary that remembers the order its keys were added in.

`Dictionary<K, V>` finds a key by hashing and has no order to give back;
this keeps the order and finds a key by scanning. The trade is the whole of
the difference, and it is the right one wherever the order is part of the
data: a parsed document read back the way it was written, a configuration a
person edits, a header list that has to go out as it came in.

**It is a scan.** Lookup is O(n), so this is for the sizes documents
actually are -- a handful of members to a few hundred -- and a program
holding something large enough for that to hurt wants a `Dictionary` beside
it as an index. That is a real limit rather than a temporary one: keeping a
hash index in step with an order would double the storage and every write,
which is not what the collection is for.

<sub>[stdlib/Collections.sl:1001](../../stdlib/Collections.sl#L1001)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many entries there are. Entries rather than distinct keys: `Add`
keeps a repeated key, so this can exceed the number of different keys.

<sub>[stdlib/Collections.sl:1015](../../stdlib/Collections.sl#L1015)</sub>

#### GetKeyAt *method*

```
TKey GetKeyAt(nuint index)
```

The key at a position, in insertion order.

<sub>[stdlib/Collections.sl:1018](../../stdlib/Collections.sl#L1018)</sub>

#### GetValueAt *method*

```
TValue GetValueAt(nuint index)
```

The value at a position, in insertion order.

<sub>[stdlib/Collections.sl:1021](../../stdlib/Collections.sl#L1021)</sub>

#### IndexOf *method*

```
Optional<nuint> IndexOf(TKey key)
```

Where a key is, or `None`.

The one lookup a caller needs: asking whether a key is there and then
asking for its value walks the collection twice. An `Optional` rather
than a sentinel, because a position that means "no position" is a rule
every caller has to know and none can be made to.

<sub>[stdlib/Collections.sl:1029](../../stdlib/Collections.sl#L1029)</sub>

#### ContainsKey *method*

```
bool ContainsKey(TKey key)
```

Whether the key is there at all. A scan, like everything else here, so
`IndexOf` once beats `ContainsKey` followed by a lookup.

<sub>[stdlib/Collections.sl:1041](../../stdlib/Collections.sl#L1041)</sub>

#### Add *method*

```
void Add(TKey key, TValue value)
```

Appends, without looking for the key first.

A repeated key is kept rather than replaced, because a document that
contains one said so and dropping either half would be this collection
deciding what the document meant. `SetValue` is the one that replaces.

<sub>[stdlib/Collections.sl:1048](../../stdlib/Collections.sl#L1048)</sub>

#### SetValue *method*

```
void SetValue(TKey key, TValue value)
```

Replaces the value of a key, or appends it. A replaced key keeps the
position it had, which is the point of the collection.

<sub>[stdlib/Collections.sl:1056](../../stdlib/Collections.sl#L1056)</sub>

#### GetValueOrDefault *method*

```
TValue GetValueOrDefault(TKey key, TValue fallback)
```

The value of a key, or the fallback. There is no overload that aborts:
a caller that wants to know writes `IndexOf`.

<sub>[stdlib/Collections.sl:1070](../../stdlib/Collections.sl#L1070)</sub>

#### Remove *method*

```
bool Remove(TKey key)
```

Removes the first entry with that key, closing the gap. Answers whether
there was one.

<sub>[stdlib/Collections.sl:1079](../../stdlib/Collections.sl#L1079)</sub>

#### Clear *method*

```
void Clear()
```

Drops every entry, leaving a count of zero.

<sub>[stdlib/Collections.sl:1091](../../stdlib/Collections.sl#L1091)</sub>

### Pair&lt;TKey, TValue&gt; *class*

```
class Pair<TKey, TValue>
```

One key and one value. What a dictionary yields when it is iterated.

<sub>[stdlib/Dictionary.sl:41](../../stdlib/Dictionary.sl#L41)</sub>

#### Key *property*

```
TKey Key { get; }
```

The key half.

<sub>[stdlib/Dictionary.sl:44](../../stdlib/Dictionary.sl#L44)</sub>

#### Value *property*

```
TValue Value { get; }
```

The value half.

<sub>[stdlib/Dictionary.sl:47](../../stdlib/Dictionary.sl#L47)</sub>

### Queue&lt;T&gt; *class*

```
class Queue<T> : IEnumerable<T>
```

First in, first out, over a circular buffer.

`Enqueue` and `Dequeue` are both constant time, and neither moves the other
items -- which is the whole reason not to use a `List<T>` and remove from
the front of it.

<sub>[stdlib/Sequences.sl:38](../../stdlib/Sequences.sl#L38)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many items are waiting. O(1).

<sub>[stdlib/Sequences.sl:55](../../stdlib/Sequences.sl#L55)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when there is nothing to dequeue. Check this before `Dequeue` or
`Peek`, both of which abort on an empty queue.

<sub>[stdlib/Sequences.sl:59](../../stdlib/Sequences.sl#L59)</sub>

#### Capacity *property*

```
nuint Capacity { get; }
```

The number of slots the ring has. Always a power of two, so wrapping is
a mask rather than a division.

<sub>[stdlib/Sequences.sl:63](../../stdlib/Sequences.sl#L63)</sub>

#### Enqueue *method*

```
void Enqueue(T item)
```

Adds to the back, growing the ring when it is full.

Constant time, and amortised constant when it grows. Growing moves
every item once, which is the only time anything is copied.

<sub>[stdlib/Sequences.sl:69](../../stdlib/Sequences.sl#L69)</sub>

#### Dequeue *method*

```
T Dequeue()
```

Removes and returns the oldest item. Aborts when the queue is empty.

<sub>[stdlib/Sequences.sl:78](../../stdlib/Sequences.sl#L78)</sub>

#### Peek *method*

```
T Peek()
```

The oldest item, without removing it. Aborts when the queue is empty.

<sub>[stdlib/Sequences.sl:94](../../stdlib/Sequences.sl#L94)</sub>

#### Clear *method*

```
void Clear()
```

Drops everything. The ring is replaced rather than blanked, so
anything it held is released now.

<sub>[stdlib/Sequences.sl:103](../../stdlib/Sequences.sl#L103)</sub>

#### ToList *method*

```
List<T> ToList()
```

The items, oldest first.

<sub>[stdlib/Sequences.sl:111](../../stdlib/Sequences.sl#L111)</sub>

#### GetEnumerator *method*

```
IEnumerator<T> GetEnumerator()
```

A cursor over the items, oldest first, for `foreach`. Walks the ring
in place rather than copying, unlike `ToList`. Enqueueing or dequeueing
during a walk invalidates it.

<sub>[stdlib/Sequences.sl:128](../../stdlib/Sequences.sl#L128)</sub>

### QueueCursor&lt;T&gt; *class*

```
class QueueCursor<T> : IEnumerator<T>
```

Walks a queue oldest first, without copying it.

The materialising version this replaced built a whole `List<T>` before the
first `MoveNext`, so iterating a queue allocated as much again as the queue
held. A cursor over the ring costs nothing.

<sub>[stdlib/Sequences.sl:742](../../stdlib/Sequences.sl#L742)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances, answering false at the end.

<sub>[stdlib/Sequences.sl:755](../../stdlib/Sequences.sl#L755)</sub>

#### Current *property*

```
T Current { get; }
```

The item the last `MoveNext` landed on.

<sub>[stdlib/Sequences.sl:764](../../stdlib/Sequences.sl#L764)</sub>

### SortedList&lt;TKey, TValue&gt; *class*

```
class SortedList<TKey, TValue> : IEnumerable<Pair<TKey, TValue>>
    where TKey : IComparable<TKey>
```

A map kept in key order, over two parallel arrays.

Lookup is a binary search and iteration is in order, which is what a
`Dictionary` cannot do. Insertion moves the tail of the arrays, so this is
for maps that are read far more than they are written -- a lookup table
built once, rather than a counter updated in a loop.

<sub>[stdlib/Sequences.sl:522](../../stdlib/Sequences.sl#L522)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many entries there are. O(1).

<sub>[stdlib/Sequences.sl:537](../../stdlib/Sequences.sl#L537)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when there are no entries.

<sub>[stdlib/Sequences.sl:540](../../stdlib/Sequences.sl#L540)</sub>

#### IndexOfKey *method*

```
nint IndexOfKey(TKey key)
```

The index `key` is at, or the index it would be inserted at, negated and
offset by one so the two cases stay apart: a result below zero means
"not found, and `-result - 1` is where it goes".

<sub>[stdlib/Sequences.sl:545](../../stdlib/Sequences.sl#L545)</sub>

#### ContainsKey *method*

```
bool ContainsKey(TKey key)
```

Whether `key` is there. A binary search, O(log n). Reach for `Find`
when the value is what is wanted, rather than searching twice.

<sub>[stdlib/Sequences.sl:572](../../stdlib/Sequences.sl#L572)</sub>

#### GetKeyAt *method*

```
TKey GetKeyAt(nuint index)
```

The key at a position in the ordering, counting from the smallest.

<sub>[stdlib/Sequences.sl:575](../../stdlib/Sequences.sl#L575)</sub>

#### GetValueAt *method*

```
TValue GetValueAt(nuint index)
```

The value at a position in the ordering, paired with `GetKeyAt` at the
same index. Aborts past the end.

<sub>[stdlib/Sequences.sl:584](../../stdlib/Sequences.sl#L584)</sub>

#### Find *method*

```
Optional<TValue> Find(TKey key)
```

The value for `key`, or `None` when there is none. The one to reach
for, for the reason `Dictionary.Find` gives: a key is data, so a key
that is not there is an outcome rather than a mistake.

<sub>[stdlib/Sequences.sl:594](../../stdlib/Sequences.sl#L594)</sub>

#### GetValue *method*

```
TValue GetValue(TKey key)
```

The value for `key`, aborting when there is none.

The asserting form, for a key that is there by construction. `Find` is
the question where it might not be, and `GetValueOrDefault` where a default will do.

<sub>[stdlib/Sequences.sl:606](../../stdlib/Sequences.sl#L606)</sub>

#### GetValueOrDefault *method*

```
TValue GetValueOrDefault(TKey key, TValue fallback)
```

The value for `key`, or `fallback` when there is none.

Allocates nothing, at the cost of not distinguishing an absent key from
one whose stored value equals the fallback. `Find` is the one that
tells them apart.

<sub>[stdlib/Sequences.sl:619](../../stdlib/Sequences.sl#L619)</sub>

#### SetValue *method*

```
void SetValue(TKey key, TValue value)
```

Sets the value of a key, adding it in order if it is new.

An existing key costs a search. A new one costs the search plus a shift
of everything after it -- O(n) -- which is what makes this collection a
poor choice for a map that is written in a loop.

<sub>[stdlib/Sequences.sl:632](../../stdlib/Sequences.sl#L632)</sub>

#### Remove *method*

```
bool Remove(TKey key)
```

Removes a key, answering whether it was there. Closes the gap, so it
is O(n) like `SetValue` on a new key.

<sub>[stdlib/Sequences.sl:660](../../stdlib/Sequences.sl#L660)</sub>

#### Clear *method*

```
void Clear()
```

Drops every entry. The arrays are replaced rather than blanked, so
anything they held is released now.

<sub>[stdlib/Sequences.sl:685](../../stdlib/Sequences.sl#L685)</sub>

#### GetKeys *method*

```
List<TKey> GetKeys()
```

Every key, smallest first, as a fresh list.

<sub>[stdlib/Sequences.sl:693](../../stdlib/Sequences.sl#L693)</sub>

#### GetValues *method*

```
List<TValue> GetValues()
```

Every value, in key order, pairing with `GetKeys` position for position.

<sub>[stdlib/Sequences.sl:702](../../stdlib/Sequences.sl#L702)</sub>

#### GetEnumerator *method*

```
IEnumerator<Pair<TKey, TValue>> GetEnumerator()
```

A cursor over the entries in key order, for `foreach` -- the ordering
a `Dictionary` cannot give. One `Pair` is built per step. Writing to
the map during a walk invalidates it.

<sub>[stdlib/Sequences.sl:716](../../stdlib/Sequences.sl#L716)</sub>

### SortedListCursor&lt;TKey, TValue&gt; *class*

```
class SortedListCursor<TKey, TValue> : IEnumerator<Pair<TKey, TValue>>
    where TKey : IComparable<TKey>
```

Walks a sorted list in key order.

One `Pair` is built per step, as the materialising version built one per
entry before the walk began -- the difference is that a loop that stops
early now stops allocating too.

<sub>[stdlib/Sequences.sl:835](../../stdlib/Sequences.sl#L835)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances to the next key in order, answering false at the end.

<sub>[stdlib/Sequences.sl:848](../../stdlib/Sequences.sl#L848)</sub>

#### Current *property*

```
Pair<TKey, TValue> Current { get; }
```

The entry the last `MoveNext` landed on, as a freshly built `Pair`.

<sub>[stdlib/Sequences.sl:857](../../stdlib/Sequences.sl#L857)</sub>

### Stack&lt;T&gt; *class*

```
class Stack<T> : IEnumerable<T>
```

Last in, first out. The top is the end of the array, so nothing moves.

<sub>[stdlib/Sequences.sl:145](../../stdlib/Sequences.sl#L145)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many items are on the stack. O(1).

<sub>[stdlib/Sequences.sl:160](../../stdlib/Sequences.sl#L160)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when there is nothing to pop. Check this before `Pop` or `Peek`,
both of which abort on an empty stack.

<sub>[stdlib/Sequences.sl:164](../../stdlib/Sequences.sl#L164)</sub>

#### Capacity *property*

```
nuint Capacity { get; }
```

The number of slots the backing array has.

<sub>[stdlib/Sequences.sl:167](../../stdlib/Sequences.sl#L167)</sub>

#### Push *method*

```
void Push(T item)
```

Pushes onto the top, growing when full. Amortised constant time.

<sub>[stdlib/Sequences.sl:170](../../stdlib/Sequences.sl#L170)</sub>

#### Pop *method*

```
T Pop()
```

Removes and returns the top. Aborts when the stack is empty.

<sub>[stdlib/Sequences.sl:179](../../stdlib/Sequences.sl#L179)</sub>

#### Peek *method*

```
T Peek()
```

The top, without removing it. Aborts when the stack is empty.

<sub>[stdlib/Sequences.sl:191](../../stdlib/Sequences.sl#L191)</sub>

#### Clear *method*

```
void Clear()
```

Drops everything. The array is replaced rather than blanked, so
anything it held is released now.

<sub>[stdlib/Sequences.sl:200](../../stdlib/Sequences.sl#L200)</sub>

#### ToList *method*

```
List<T> ToList()
```

The items, top first, which is the order they would be popped in.

<sub>[stdlib/Sequences.sl:207](../../stdlib/Sequences.sl#L207)</sub>

#### GetEnumerator *method*

```
IEnumerator<T> GetEnumerator()
```

A cursor over the items, top first -- the order `Pop` would give them
back in. Pushing or popping during a walk invalidates it.

<sub>[stdlib/Sequences.sl:220](../../stdlib/Sequences.sl#L220)</sub>

### StackCursor&lt;T&gt; *class*

```
class StackCursor<T> : IEnumerator<T>
```

Walks a stack top first, matching the order `Pop` would hand things back.

<sub>[stdlib/Sequences.sl:768](../../stdlib/Sequences.sl#L768)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances towards the bottom, answering false at the end.

<sub>[stdlib/Sequences.sl:781](../../stdlib/Sequences.sl#L781)</sub>

#### Current *property*

```
T Current { get; }
```

The item the last `MoveNext` landed on.

<sub>[stdlib/Sequences.sl:790](../../stdlib/Sequences.sl#L790)</sub>

## Functions

### Aggregate *function*

```
A Aggregate<T, A>(T[:] items, A seed, Fold<A, T> combine)
```

Everything folded into one value, left to right. The seed decides the
result type, so `A` is settled before the lambda is looked at.

    long total = Aggregate(numbers, (long)0, (sum, n) => sum + (long)n);

<sub>[stdlib/Functional.sl:81](../../stdlib/Functional.sl#L81)</sub>

### Aggregate *function*

```
A Aggregate<T, A>(IEnumerable<T> items, A seed, Fold<A, T> combine)
```

Everything folded into one value, left to right, over any sequence.

<sub>[stdlib/Functional.sl:219](../../stdlib/Functional.sl#L219)</sub>

### All *function*

```
bool All<T>(T[:] items, Predicate<T> test)
```

Whether every element does. Stops at the first that does not, and is true
of an empty input.

<sub>[stdlib/Functional.sl:102](../../stdlib/Functional.sl#L102)</sub>

### All *function*

```
bool All<T>(IEnumerable<T> items, Predicate<T> test)
```

Whether every element does, over any sequence. Stops at the first that
does not, and is true of an empty sequence.

<sub>[stdlib/Functional.sl:241](../../stdlib/Functional.sl#L241)</sub>

### Any *function*

```
bool Any<T>(T[:] items, Predicate<T> test)
```

Whether any element satisfies the predicate. Stops at the first that does.

<sub>[stdlib/Functional.sl:90](../../stdlib/Functional.sl#L90)</sub>

### Any *function*

```
bool Any<T>(IEnumerable<T> items, Predicate<T> test)
```

Whether any element satisfies the predicate, over any sequence. Stops at
the first that does, so the rest of the sequence is never walked.

<sub>[stdlib/Functional.sl:229](../../stdlib/Functional.sl#L229)</sub>

### BinarySearch *function*

```
nuint BinarySearch<T>(T[:] items, T wanted)
    where T : IComparable<T>
```

Where `wanted` is in an already-ordered slice, or the length when it is not
there.

Two functions rather than one with a found flag, because the language has
no `out` and a caller that wants the insertion point usually does not want
the search, and the other way round.

<sub>[stdlib/Collections.sl:878](../../stdlib/Collections.sl#L878)</sub>

### Contains *function*

```
bool Contains<T>(IReadOnlyList<T> items, T wanted)
    where T : IEquatable<T>
```

Whether `wanted` is in the list at all. `List<T>.Contains` in .NET, and a
free function here for the reason `IndexOf` is.

<sub>[stdlib/Collections.sl:646](../../stdlib/Collections.sl#L646)</sub>

### Count *function*

```
nuint Count<T>(T[:] items, Predicate<T> test)
```

How many satisfy the predicate.

<sub>[stdlib/Functional.sl:113](../../stdlib/Functional.sl#L113)</sub>

### Count *function*

```
nuint Count<T>(IEnumerable<T> items, Predicate<T> test)
```

How many satisfy the predicate, over any sequence. Walks all of it.

<sub>[stdlib/Functional.sl:252](../../stdlib/Functional.sl#L252)</sub>

### Distinct *function*

```
List<T> Distinct<T>(T[:] items)
    where T : IEquatable<T>
```

The elements, in order, with later repeats left out.

O(n²) in comparisons, which is what asking nothing of `T` but `IEquatable`
costs. A `HashSet<T>` does it in one pass and wants `IHashable` as well;
this is the one to reach for at the sizes a chain works at.

<sub>[stdlib/Functional.sl:340](../../stdlib/Functional.sl#L340)</sub>

### Distinct *function*

```
List<T> Distinct<T>(IEnumerable<T> items)
    where T : IEquatable<T>
```

The elements, in order, with later repeats left out, over any sequence.
O(n squared) in comparisons, as the slice overload is.

<sub>[stdlib/Functional.sl:353](../../stdlib/Functional.sl#L353)</sub>

### Find *function*

```
Optional<T> Find<T>(T[:] items, Predicate<T> test)
```

The first element satisfying the predicate, if there is one.

    if (Find(people, (p) => p.Age > 65) is Some found) { ... }

An `Optional<T>` rather than a fallback: a struct has no null to stand for
"none" (§2.5), and inventing a value that means it is how a caller comes to
treat a real answer as a miss.

<sub>[stdlib/Functional.sl:146](../../stdlib/Functional.sl#L146)</sub>

### FindIndex *function*

```
Optional<nuint> FindIndex<T>(T[:] items, Predicate<T> test)
```

Where the first element satisfying the predicate is, if it is there.

<sub>[stdlib/Functional.sl:157](../../stdlib/Functional.sl#L157)</sub>

### FindLowerBound *function*

```
nuint FindLowerBound<T>(T[:] items, T wanted)
    where T : IComparable<T>
```

The first index at which `wanted` could be inserted and leave the slice
ordered: the length when it belongs at the end, and the index of the first
equal element when there is one.

<sub>[stdlib/Collections.sl:906](../../stdlib/Collections.sl#L906)</sub>

### FirstOrDefault *function*

```
T FirstOrDefault<T>(T[:] items, Predicate<T> test, T fallback)
```

The first element satisfying the predicate, or `fallback` if none does.

The reader that needs no check, because it supplies its own answer. `Find`
is the one to reach for when "there was none" is a different outcome rather
than a different value.

<sub>[stdlib/Functional.sl:129](../../stdlib/Functional.sl#L129)</sub>

### FirstOrDefault *function*

```
T FirstOrDefault<T>(IEnumerable<T> items, Predicate<T> test, T fallback)
```

The first element satisfying the predicate, or `fallback` if none does,
over any sequence. A fallback equal to a real element is indistinguishable
from a miss; `Find` is the overload that tells them apart, and it takes a
slice rather than a sequence.

<sub>[stdlib/Functional.sl:267](../../stdlib/Functional.sl#L267)</sub>

### ForEach *function*

```
void ForEach<T>(T[:] items, Action<T> body)
```

Runs the action over every element.

<sub>[stdlib/Functional.sl:168](../../stdlib/Functional.sl#L168)</sub>

### ForEach *function*

```
void ForEach<T>(IEnumerable<T> items, Action<T> body)
```

Runs the action over every element of any sequence.

<sub>[stdlib/Functional.sl:278](../../stdlib/Functional.sl#L278)</sub>

### IndexOf *function*

```
Optional<nuint> IndexOf<T>(IReadOnlyList<T> items, T wanted)
    where T : IEquatable<T>
```

Where the first item equal to `wanted` is, if it is there at all.

    if (IndexOf(names, "beta") is Some at) { names.RemoveAt(at.Value); }

An `Optional<nuint>` rather than the length standing in for "no": the
sentinel is the thing `Optional<T>` was added to retire, and its own
documentation names this function as the example. `OrderedDictionary.IndexOf`
has always answered this way; now they agree.

<sub>[stdlib/Collections.sl:634](../../stdlib/Collections.sl#L634)</sub>

### LastIndexOf *function*

```
Optional<nuint> LastIndexOf<T>(IReadOnlyList<T> items, T wanted)
    where T : IEquatable<T>
```

Where the *last* item equal to `wanted` is, if it is there at all.

<sub>[stdlib/Collections.sl:652](../../stdlib/Collections.sl#L652)</sub>

### Max *function*

```
T Max<T>(IReadOnlyList<T> items)
    where T : IComparable<T>
```

The largest item, by its own ordering. The list must not be empty.

<sub>[stdlib/Collections.sl:597](../../stdlib/Collections.sl#L597)</sub>

### Min *function*

```
T Min<T>(IReadOnlyList<T> items)
    where T : IComparable<T>
```

The smallest item, by its own ordering. The list must not be empty.

<sub>[stdlib/Collections.sl:612](../../stdlib/Collections.sl#L612)</sub>

### OrderBy *function*

```
List<T> OrderBy<T>(T[:] items, Comparer<T> order)
```

The elements ordered by what `order` says, leaving the input alone.

`Sort` orders in place, which a chain cannot use: what is being chained
from is usually somebody else's array. This copies first, and is stable for
the reason `Sort` is.

<sub>[stdlib/Functional.sl:369](../../stdlib/Functional.sl#L369)</sub>

### OrderBy *function*

```
List<T> OrderBy<T>(IEnumerable<T> items, Comparer<T> order)
```

The elements ordered by what `order` says, over any sequence, leaving the
input alone. Copies into an array first, so it costs one.

<sub>[stdlib/Functional.sl:381](../../stdlib/Functional.sl#L381)</sub>

### RemoveFirst *function*

```
bool RemoveFirst<T>(List<T> items, T wanted)
    where T : IEquatable<T>
```

Removes the first item equal to `wanted`, answering whether there was one.

This is `List<T>.Remove` under another name, and it is a free function
rather than a method because it needs `T : IEquatable<T>` and a class
cannot constrain one method's type parameter to something the class itself
does not demand of every element.

<sub>[stdlib/Collections.sl:669](../../stdlib/Collections.sl#L669)</sub>

### RemoveWhere *function*

```
nuint RemoveWhere<T>(List<T> items, Predicate<T> match)
```

Removes every item the predicate accepts, and answers how many went.

    RemoveWhere(handlers, (h) => h == leaving);

A predicate rather than a value, which is what makes it work for a `T` that
implements nothing -- a `closure` is not `IEquatable`, so a list of
callbacks could not be removed from at all before this.

Walked from the end, so an index already passed cannot move.

<sub>[stdlib/Collections.sl:688](../../stdlib/Collections.sl#L688)</sub>

### Reverse *function*

```
void Reverse<T>(T[:] items)
```

Reverses part of an array in place.

<sub>[stdlib/Collections.sl:928](../../stdlib/Collections.sl#L928)</sub>

### Select *function*

```
List<R> Select<T, R>(T[:] items, Func<T, R> transform)
```

Every element put through the transform.

    var spelled = Select(numbers, n => Text.FromInteger((long)n));

`R` appears nowhere but in the transform's result, so working it out means
binding the lambda's body -- which cannot happen until `T` has given the
lambda its parameter type. The compiler does the two in that order.

<sub>[stdlib/Functional.sl:69](../../stdlib/Functional.sl#L69)</sub>

### Select *function*

```
List<R> Select<T, R>(IEnumerable<T> items, Func<T, R> transform)
```

Every element put through the transform, over any sequence.

<sub>[stdlib/Functional.sl:210](../../stdlib/Functional.sl#L210)</sub>

### Skip *function*

```
List<T> Skip<T>(T[:] items, nuint count)
```

Everything after the first `count` elements, or nothing if there are fewer.

<sub>[stdlib/Functional.sl:185](../../stdlib/Functional.sl#L185)</sub>

### Skip *function*

```
List<T> Skip<T>(IEnumerable<T> items, nuint count)
```

Everything after the first `count`.

<sub>[stdlib/Functional.sl:402](../../stdlib/Functional.sl#L402)</sub>

### Sort *function*

```
void Sort<T>(T[:] items)
    where T : IComparable<T>
```

Orders part of an array in place, smallest first.

An array converts to a slice of the whole of itself, so `Sort(numbers)`
reaches this and `Sort(numbers[2:5])` orders three of them and leaves the
rest alone. Nothing is copied either way: a slice is a view.

**Stable, and O(n log n).** Merge sort, bottom-up, with insertion sort for
short runs. Stability is the property worth paying for -- sorting by one
key and then another is how a multi-key order gets built, and it only works
if the second sort leaves equal elements where the first put them. The
price is one scratch array as long as the input; an in-place quicksort
would avoid it and would not be stable.

<sub>[stdlib/Collections.sl:722](../../stdlib/Collections.sl#L722)</sub>

### Sort *function*

```
void Sort<T>(T[:] items, Comparer<T> order)
```

The same, ordered by a comparer rather than by the type itself.

This is the overload that sorts descending, sorts by a field, or sorts a
type that implements nothing at all:

    Sort(people, (a, b) => a.Age - b.Age);

<sub>[stdlib/Collections.sl:803](../../stdlib/Collections.sl#L803)</sub>

### Sort *function*

```
void Sort<T>(IList<T> items)
    where T : IComparable<T>
```

Orders a list in place, smallest first.

Copied into an array, sorted there and copied back, rather than merge-sorted
through the interface. Every `At` and `Set` on an `IList<T>` is a virtual
call, and a sort makes O(n log n) of them; two linear passes to escape that
is the cheaper trade, and it gets the array version's stability for free.

<sub>[stdlib/Collections.sl:952](../../stdlib/Collections.sl#L952)</sub>

### Sort *function*

```
void Sort<T>(IList<T> items, Comparer<T> order)
```

The same, ordered by a comparer.

<sub>[stdlib/Collections.sl:969](../../stdlib/Collections.sl#L969)</sub>

### Take *function*

```
List<T> Take<T>(T[:] items, nuint count)
```

The first `count` elements, or all of them if there are fewer.

<sub>[stdlib/Functional.sl:175](../../stdlib/Functional.sl#L175)</sub>

### Take *function*

```
List<T> Take<T>(IEnumerable<T> items, nuint count)
```

The first `count` elements, or all of them if there are fewer.

<sub>[stdlib/Functional.sl:389](../../stdlib/Functional.sl#L389)</sub>

### ToArray *function*

```
T[] ToArray<T>(IEnumerable<T> items)
```

Everything in the sequence, as an array.

One `IEnumerable` overload rather than an `IReadOnlyList` one as well: a
`List<T>` is both, so a pair would be ambiguous at exactly the type a chain
hands over. That is why `ToList` takes only the sequence too.

<sub>[stdlib/Functional.sl:317](../../stdlib/Functional.sl#L317)</sub>

### ToArray *function*

```
T[] ToArray<T>(T[:] items)
```

The same for a slice, which is not an `IEnumerable` and so does not collide.

<sub>[stdlib/Functional.sl:327](../../stdlib/Functional.sl#L327)</sub>

### ToList *function*

```
List<T> ToList<T>(IEnumerable<T> items)
```

Everything in the sequence, as a list. The one that makes a `Queue` or a
`HashSet` usable with the array overloads above.

<sub>[stdlib/Functional.sl:286](../../stdlib/Functional.sl#L286)</sub>

### ToList *function*

```
List<T> ToList<T>(T[:] items)
```

And a slice, which an array converts to. Not an overload of the above by
accident: a slice is not an `IEnumerable`, so nothing is ever both.

<sub>[stdlib/Functional.sl:296](../../stdlib/Functional.sl#L296)</sub>

### Where *function*

```
List<T> Where<T>(T[:] items, Predicate<T> keep)
```

The elements the predicate keeps, in the order they were in.

An array converts to a slice of the whole of itself, so this takes both.

<sub>[stdlib/Functional.sl:51](../../stdlib/Functional.sl#L51)</sub>

### Where *function*

```
List<T> Where<T>(IEnumerable<T> items, Predicate<T> keep)
```

The same, for anything with a `GetEnumerator()` that names its shape --
`List<T>`, `Queue<T>`, `Stack<T>`, `LinkedList<T>`, `HashSet<T>` and
`SortedList<K, V>` all do.

<sub>[stdlib/Functional.sl:198](../../stdlib/Functional.sl#L198)</sub>

