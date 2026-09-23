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

`TKey` has to be equatable and hashable. A primitive, an enum and a String all
are without saying so, so `Dictionary<String, int>` needs nothing extra; a
class says so by implementing `IEquatable<T>` and `IHashable`.

**Type parameters**

- `TKey` — what an entry is found by: equatable and hashable, and the two must agree, since a probe hashes to a slot and then compares
- `TValue` — what an entry holds; nothing is asked of it

<sub>[stdlib/Dictionary.sl:74](../../stdlib/Dictionary.sl#L74)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many entries there are. O(1) -- it is a counter, not a scan.

<sub>[stdlib/Dictionary.sl:93](../../stdlib/Dictionary.sl#L93)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when there are no entries.

<sub>[stdlib/Dictionary.sl:96](../../stdlib/Dictionary.sl#L96)</sub>

#### Capacity *property*

```
nuint Capacity { get; }
```

The number of slots the table has. Always a power of two, so the hash is
reduced with a mask rather than a division.

<sub>[stdlib/Dictionary.sl:100](../../stdlib/Dictionary.sl#L100)</sub>

#### ContainsKey *method*

```
bool ContainsKey(TKey key)
```

Whether `key` is there.

One probe, but reach for `Find` when the value is what is wanted:
`ContainsKey` and then `GetValue` probes twice for one answer.

**See also** &nbsp; [Dictionary.Find](#find-method)

<sub>[stdlib/Dictionary.sl:124](../../stdlib/Dictionary.sl#L124)</sub>

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

**See also** &nbsp; [Dictionary.GetValue](#getvalue-method) &middot; [Dictionary.GetValueOrDefault](#getvalueordefault-method)

<sub>[stdlib/Dictionary.sl:141](../../stdlib/Dictionary.sl#L141)</sub>

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

**See also** &nbsp; [Dictionary.Find](#find-method)

<sub>[stdlib/Dictionary.sl:159](../../stdlib/Dictionary.sl#L159)</sub>

#### GetValueOrDefault *method*

```
TValue GetValueOrDefault(TKey key, TValue fallback)
```

The value for `key`, or `fallback` when there is none.

**See also** &nbsp; [Dictionary.Find](#find-method)

<sub>[stdlib/Dictionary.sl:170](../../stdlib/Dictionary.sl#L170)</sub>

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

**See also** &nbsp; [Dictionary.Find](#find-method) &middot; [Dictionary.SetValue](#setvalue-method)

<sub>[stdlib/Dictionary.sl:206](../../stdlib/Dictionary.sl#L206)</sub>

#### SetValue *method*

```
void SetValue(TKey key, TValue value)
```

Adds the key or replaces what it maps to.

**See also** &nbsp; [Dictionary.Add](#add-method)

<sub>[stdlib/Dictionary.sl:225](../../stdlib/Dictionary.sl#L225)</sub>

#### Add *method*

```
bool Add(TKey key, TValue value)
```

Adds the key, or reports that it was already there and changes nothing.

**Returns** &nbsp; true when the entry was added, false when the key was already there

**See also** &nbsp; [Dictionary.SetValue](#setvalue-method) &middot; [Dictionary.Remove](#remove-method)

<sub>[stdlib/Dictionary.sl:253](../../stdlib/Dictionary.sl#L253)</sub>

#### Remove *method*

```
bool Remove(TKey key)
```

Removes the key, reporting whether it was there.

**See also** &nbsp; [Dictionary.Add](#add-method)

<sub>[stdlib/Dictionary.sl:264](../../stdlib/Dictionary.sl#L264)</sub>

#### Clear *method*

```
void Clear()
```

Drops every entry. The arrays are replaced rather than blanked, so
anything they held is released now.

<sub>[stdlib/Dictionary.sl:305](../../stdlib/Dictionary.sl#L305)</sub>

#### GetKeys *method*

```
List<TKey> GetKeys()
```

Every key, in the table's own order.

A fresh list, so changing it changes nothing here, and building it is a
scan of every slot rather than of every entry -- O(capacity), not
O(count). Pairs with `GetValues` position for position as long as nothing
is written in between.

**See also** &nbsp; [Dictionary.GetValues](#getvalues-method)

<sub>[stdlib/Dictionary.sl:321](../../stdlib/Dictionary.sl#L321)</sub>

#### GetValues *method*

```
List<TValue> GetValues()
```

Every value, in the same order `GetKeys` gives.

Values are not distinct: a value stored under two keys appears twice.

**See also** &nbsp; [Dictionary.GetKeys](#getkeys-method)

<sub>[stdlib/Dictionary.sl:337](../../stdlib/Dictionary.sl#L337)</sub>

#### GetEnumerator *method*

```
IEnumerator<Pair<TKey, TValue>> GetEnumerator()
```

A cursor over the entries, for `foreach`.

The order is the table's and is not insertion order; it changes when
the table grows. `Standard.Collections.OrderedDictionary` is the one
that keeps an order. Adding or removing during a walk invalidates the
cursor.

**See also** &nbsp; [DictionaryEnumerator](#dictionaryenumeratortkey-tvalue-class) &middot; [OrderedDictionary](#ordereddictionarytkey-tvalue-class)

<sub>[stdlib/Dictionary.sl:357](../../stdlib/Dictionary.sl#L357)</sub>

### DictionaryEnumerator&lt;TKey, TValue&gt; *class*

```
class DictionaryEnumerator<TKey, TValue> : IEnumerator<Pair<TKey, TValue>>
    where TKey : IEquatable<TKey>, IHashable
```

Walks a dictionary's slots, skipping the empty ones.

The order is the table's own and says nothing about insertion order; adding
or removing during a walk invalidates it, as it does in C#.

**Type parameters**

- `TKey` — the key type of the dictionary being walked, equatable and hashable as that dictionary requires
- `TValue` — its value type

**See also** &nbsp; [Dictionary.GetEnumerator](#getenumerator-method)

<sub>[stdlib/Dictionary.sl:403](../../stdlib/Dictionary.sl#L403)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances to the next occupied slot, answering false at the end. Each
call skips however many empty slots lie between, so a walk costs
O(capacity) overall rather than O(count).

<sub>[stdlib/Dictionary.sl:423](../../stdlib/Dictionary.sl#L423)</sub>

#### Current *property*

```
Pair<TKey, TValue> Current { get; }
```

The entry the last `MoveNext` landed on, as a freshly built `Pair`.

<sub>[stdlib/Dictionary.sl:436](../../stdlib/Dictionary.sl#L436)</sub>

### HashSet&lt;T&gt; *class*

```
class HashSet<T> : IEnumerable<T>
    where T : IEquatable<T>, IHashable
```

A set of distinct values, with membership in constant time.

The same table as `Dictionary`, without the values.

**Type parameters**

- `T` — what the set holds: equatable and hashable, and the two must agree, since membership is a hash to a slot and a comparison

<sub>[stdlib/Dictionary.sl:447](../../stdlib/Dictionary.sl#L447)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many distinct items there are. O(1).

<sub>[stdlib/Dictionary.sl:464](../../stdlib/Dictionary.sl#L464)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when there is nothing in it.

<sub>[stdlib/Dictionary.sl:467](../../stdlib/Dictionary.sl#L467)</sub>

#### Capacity *property*

```
nuint Capacity { get; }
```

The number of slots the table has. Always a power of two, so the hash
is reduced with a mask rather than a division.

<sub>[stdlib/Dictionary.sl:471](../../stdlib/Dictionary.sl#L471)</sub>

#### Contains *method*

```
bool Contains(T item)
```

Whether `item` is in the set. One probe, and the question the whole
collection exists to answer.

**See also** &nbsp; [HashSet.Add](#add-method)

<sub>[stdlib/Dictionary.sl:491](../../stdlib/Dictionary.sl#L491)</sub>

#### Add *method*

```
bool Add(T item)
```

Adds the item, reporting whether it was new.

**See also** &nbsp; [HashSet.Remove](#remove-method) &middot; [HashSet.Contains](#contains-method)

<sub>[stdlib/Dictionary.sl:497](../../stdlib/Dictionary.sl#L497)</sub>

#### Remove *method*

```
bool Remove(T item)
```

Removes the item, reporting whether it was there.

**See also** &nbsp; [HashSet.Add](#add-method)

<sub>[stdlib/Dictionary.sl:518](../../stdlib/Dictionary.sl#L518)</sub>

#### Clear *method*

```
void Clear()
```

Drops every item. The arrays are replaced rather than blanked, so
anything they held is released now.

<sub>[stdlib/Dictionary.sl:550](../../stdlib/Dictionary.sl#L550)</sub>

#### UnionWith *method*

```
void UnionWith(IReadOnlyList<T> other)
```

Adds everything in `other` that is not here already.

**See also** &nbsp; [HashSet.ExceptWith](#exceptwith-method) &middot; [HashSet.IntersectWith](#intersectwith-method)

<sub>[stdlib/Dictionary.sl:561](../../stdlib/Dictionary.sl#L561)</sub>

#### ExceptWith *method*

```
void ExceptWith(IReadOnlyList<T> other)
```

Removes everything in `other`.

**See also** &nbsp; [HashSet.UnionWith](#unionwith-method) &middot; [HashSet.IntersectWith](#intersectwith-method)

<sub>[stdlib/Dictionary.sl:571](../../stdlib/Dictionary.sl#L571)</sub>

#### IntersectWith *method*

```
void IntersectWith(HashSet<T> other)
```

Keeps only what is also in `other`.

**See also** &nbsp; [HashSet.UnionWith](#unionwith-method) &middot; [HashSet.ExceptWith](#exceptwith-method)

<sub>[stdlib/Dictionary.sl:581](../../stdlib/Dictionary.sl#L581)</sub>

#### ToList *method*

```
List<T> ToList()
```

Every item, in the table's own order -- which is not insertion order
and changes when the table grows.

A fresh list, and building it scans every slot: O(capacity), not
O(count). `foreach` walks the set without building one.

**See also** &nbsp; [HashSet.GetEnumerator](#getenumerator-method)

<sub>[stdlib/Dictionary.sl:600](../../stdlib/Dictionary.sl#L600)</sub>

#### GetEnumerator *method*

```
IEnumerator<T> GetEnumerator()
```

A cursor over the items, for `foreach`. Allocates nothing beyond the
cursor itself, unlike `ToList`. Adding or removing during a walk
invalidates it.

**See also** &nbsp; [HashSetCursor](#hashsetcursort-class) &middot; [HashSet.ToList](#tolist-method)

<sub>[stdlib/Dictionary.sl:623](../../stdlib/Dictionary.sl#L623)</sub>

### HashSetCursor&lt;T&gt; *class*

```
class HashSetCursor<T> : IEnumerator<T>
    where T : IEquatable<T>, IHashable
```

Walks a set's table, skipping the empty slots.

The same shape as `DictionaryEnumerator`, and for the same reason: the
materialising version built a whole `List<T>` before the first `MoveNext`,
so iterating a set allocated as much again as the set held.

**Type parameters**

- `T` — the item type of the set being walked, equatable and hashable as that set requires

**See also** &nbsp; [HashSet.GetEnumerator](#getenumerator-method) &middot; [DictionaryEnumerator](#dictionaryenumeratortkey-tvalue-class)

<sub>[stdlib/Dictionary.sl:657](../../stdlib/Dictionary.sl#L657)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances to the next occupied slot, answering false at the end.

<sub>[stdlib/Dictionary.sl:673](../../stdlib/Dictionary.sl#L673)</sub>

#### Current *property*

```
T Current { get; }
```

The item the last `MoveNext` landed on.

<sub>[stdlib/Dictionary.sl:686](../../stdlib/Dictionary.sl#L686)</sub>

### IComparable&lt;T&gt; *interface*

```
interface IComparable<T>
```

Returns a negative number, zero, or a positive number when this value orders
before, with, or after `other`.

**Type parameters**

- `T` — what a value is ordered against, which is normally the type implementing this

<sub>[stdlib/Collections.sl:60](../../stdlib/Collections.sl#L60)</sub>

#### CompareTo *method*

```
int CompareTo(T other)
```

Negative when this orders before `other`, zero when they order
together, positive when after. The sign is all that is read -- the
magnitude means nothing, so returning a subtraction is fine as long as
it cannot overflow.

<sub>[stdlib/Collections.sl:66](../../stdlib/Collections.sl#L66)</sub>

### IEnumerable&lt;T&gt; *interface*

```
interface IEnumerable<T>
```

Something that can be walked from the start, once per enumerator.

`foreach` does not need this interface -- it finds `GetEnumerator` by name
-- so implementing it is about being passable as a sequence, not about
being iterable.

**Type parameters**

- `T` — what the sequence yields; nothing is asked of it

<sub>[stdlib/Collections.sl:123](../../stdlib/Collections.sl#L123)</sub>

#### GetEnumerator *method*

```
IEnumerator<T> GetEnumerator()
```

A fresh cursor positioned before the first item. Each call gives an
independent one, so a sequence can be walked twice; what is not
promised is that the two walks see the same items, since a collection
changed in between will say something different.

<sub>[stdlib/Collections.sl:129](../../stdlib/Collections.sl#L129)</sub>

### IEnumerator&lt;T&gt; *interface*

```
interface IEnumerator<T>
```

A cursor over a sequence. `MoveNext` advances and reports whether there was
anything to advance to; `Current` returns what it landed on.

`foreach` does not require this interface -- it looks for the methods by
name, so any type with a `GetEnumerator()` can be iterated. Naming the shape
is still worth doing, because it lets a sequence be passed around.

**Type parameters**

- `T` — what the cursor lands on; nothing is asked of it

<sub>[stdlib/Collections.sl:103](../../stdlib/Collections.sl#L103)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances to the next item and reports whether there was one. Must be
called before the first `Current`: a fresh enumerator sits before the
start rather than on the first item.

<sub>[stdlib/Collections.sl:108](../../stdlib/Collections.sl#L108)</sub>

#### Current *property*

```
T Current { get; }
```

What the last `MoveNext` landed on. Calling this before the first
`MoveNext`, or after one that answered false, is a mistake the
enumerator is not required to catch.

<sub>[stdlib/Collections.sl:113](../../stdlib/Collections.sl#L113)</sub>

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

**Type parameters**

- `T` — what a value is compared against, which is normally the type implementing this

<sub>[stdlib/Collections.sl:48](../../stdlib/Collections.sl#L48)</sub>

#### EqualTo *method*

```
bool EqualTo(T other)
```

True when this value and `other` are the same value. Implementations
should answer without allocating; this runs once per probe.

<sub>[stdlib/Collections.sl:52](../../stdlib/Collections.sl#L52)</sub>

### IHashable *interface*

```
interface IHashable
```

A value that can be a key in a hash table.

Two values that are `EqualTo` each other must return the same `HashCode`;
two that are not may still collide, and the table handles it. A type that
implements this should implement `IEquatable<T>` as well, since a hash on
its own only narrows the search.

<sub>[stdlib/Collections.sl:75](../../stdlib/Collections.sl#L75)</sub>

#### HashCode *method*

```
nuint HashCode()
```

A number standing in for this value. The same value must give the same
number for as long as it is a key in a table, which means hashing only
the parts a key is not going to have changed under it.

<sub>[stdlib/Collections.sl:80](../../stdlib/Collections.sl#L80)</sub>

### IList&lt;T&gt; *interface*

```
interface IList<T> : IReadOnlyList<T>
```

Everything a read-only list offers, plus mutation. A value of this type can
be passed anywhere an IReadOnlyList is wanted, at no cost: an interface
reference is a plain pointer, and the object carries a table for both.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [IReadOnlyList](#ireadonlylistt-interface)

<sub>[stdlib/Collections.sl:197](../../stdlib/Collections.sl#L197)</sub>

#### this[] *indexer*

```
T this[nuint index] { get; set; }
```

The item at `index`, readable and writable. Redeclared because an
interface cannot widen an inherited member from get-only to get-set.

<sub>[stdlib/Collections.sl:201](../../stdlib/Collections.sl#L201)</sub>

#### Add *method*

```
void Add(T item)
```

Appends to the end.

<sub>[stdlib/Collections.sl:204](../../stdlib/Collections.sl#L204)</sub>

#### RemoveAt *method*

```
void RemoveAt(nuint index)
```

Removes the item at `index`, closing the gap.

<sub>[stdlib/Collections.sl:207](../../stdlib/Collections.sl#L207)</sub>

#### Clear *method*

```
void Clear()
```

Drops every item, leaving a length of zero.

<sub>[stdlib/Collections.sl:210](../../stdlib/Collections.sl#L210)</sub>

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

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [IList](#ilistt-interface)

<sub>[stdlib/Collections.sl:178](../../stdlib/Collections.sl#L178)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many items there are.

<sub>[stdlib/Collections.sl:181](../../stdlib/Collections.sl#L181)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether there are none.

<sub>[stdlib/Collections.sl:184](../../stdlib/Collections.sl#L184)</sub>

#### this[] *indexer*

```
T this[nuint index] { get; }
```

The item at `index`, counting from zero. An index at or past `Count`
aborts with the same message an array overrun gives.

<sub>[stdlib/Collections.sl:188](../../stdlib/Collections.sl#L188)</sub>

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

**Type parameters**

- `T` — what a node holds; nothing is asked of it, and a node is named by its handle rather than by its value

<sub>[stdlib/Sequences.sl:291](../../stdlib/Sequences.sl#L291)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many nodes are linked in. O(1), and not the size of the pool --
recycled slots are not counted.

<sub>[stdlib/Sequences.sl:320](../../stdlib/Sequences.sl#L320)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when nothing is linked in.

<sub>[stdlib/Sequences.sl:323](../../stdlib/Sequences.sl#L323)</sub>

#### First *property*

```
nint First { get; }
```

A handle to the first node, or -1 when the list is empty.

**See also** &nbsp; [LinkedList.Last](#last-property)

<sub>[stdlib/Sequences.sl:328](../../stdlib/Sequences.sl#L328)</sub>

#### Last *property*

```
nint Last { get; }
```

A handle to the last node, or -1 when the list is empty.

**See also** &nbsp; [LinkedList.First](#first-property)

<sub>[stdlib/Sequences.sl:333](../../stdlib/Sequences.sl#L333)</sub>

#### GetNext *method*

```
nint GetNext(nint handle)
```

The node after `handle`, or -1 at the end.

**See also** &nbsp; [LinkedList.GetPrevious](#getprevious-method)

<sub>[stdlib/Sequences.sl:338](../../stdlib/Sequences.sl#L338)</sub>

#### GetPrevious *method*

```
nint GetPrevious(nint handle)
```

The node before `handle`, or -1 at the start.

**See also** &nbsp; [LinkedList.GetNext](#getnext-method)

<sub>[stdlib/Sequences.sl:343](../../stdlib/Sequences.sl#L343)</sub>

#### GetValueAt *method*

```
T GetValueAt(nint handle)
```

The value in a node.

`handle` must be live: one this list handed out and has not had
`RemoveAt` called on. A stale or `-1` handle is not checked and reads
whatever the pool slot now holds, so test `at >= 0` before walking.

**See also** &nbsp; [LinkedList.SetValueAt](#setvalueat-method)

<sub>[stdlib/Sequences.sl:352](../../stdlib/Sequences.sl#L352)</sub>

#### SetValueAt *method*

```
void SetValueAt(nint handle, T value)
```

Replaces the value in a node, leaving the links alone. Same
requirement on `handle` as `GetValueAt`.

**See also** &nbsp; [LinkedList.GetValueAt](#getvalueat-method)

<sub>[stdlib/Sequences.sl:358](../../stdlib/Sequences.sl#L358)</sub>

#### AddFirst *method*

```
nint AddFirst(T item)
```

Links a new node at the front and answers its handle. Constant time.

**See also** &nbsp; [LinkedList.AddLast](#addlast-method) &middot; [LinkedList.RemoveFirst](#removefirst-method)

<sub>[stdlib/Sequences.sl:364](../../stdlib/Sequences.sl#L364)</sub>

#### AddLast *method*

```
nint AddLast(T item)
```

Links a new node at the back and answers its handle. Constant time --
the tail is kept, so this does not walk the list.

**See also** &nbsp; [LinkedList.AddFirst](#addfirst-method) &middot; [LinkedList.RemoveLast](#removelast-method)

<sub>[stdlib/Sequences.sl:390](../../stdlib/Sequences.sl#L390)</sub>

#### InsertAfter *method*

```
nint InsertAfter(nint handle, T item)
```

Links a new node just after `handle` and answers its handle. Constant
time, and the reason to choose this over a `List<T>`. Inserting after
the last node appends.

**See also** &nbsp; [LinkedList.InsertBefore](#insertbefore-method)

<sub>[stdlib/Sequences.sl:416](../../stdlib/Sequences.sl#L416)</sub>

#### InsertBefore *method*

```
nint InsertBefore(nint handle, T item)
```

Links a new node just before `handle` and answers its handle.
Inserting before the first node prepends.

**See also** &nbsp; [LinkedList.InsertAfter](#insertafter-method)

<sub>[stdlib/Sequences.sl:436](../../stdlib/Sequences.sl#L436)</sub>

#### RemoveAt *method*

```
void RemoveAt(nint handle)
```

Unlinks a node and recycles its slot. The handle is dead afterwards.

**See also** &nbsp; [LinkedList.RemoveFirst](#removefirst-method) &middot; [LinkedList.RemoveLast](#removelast-method)

<sub>[stdlib/Sequences.sl:448](../../stdlib/Sequences.sl#L448)</sub>

#### RemoveFirst *method*

```
T RemoveFirst()
```

Removes and returns the first item. Aborts when the list is empty.

**See also** &nbsp; [LinkedList.AddFirst](#addfirst-method) &middot; [LinkedList.RemoveLast](#removelast-method)

<sub>[stdlib/Sequences.sl:482](../../stdlib/Sequences.sl#L482)</sub>

#### RemoveLast *method*

```
T RemoveLast()
```

Removes and returns the last item. Aborts when the list is empty.

**See also** &nbsp; [LinkedList.AddLast](#addlast-method)

<sub>[stdlib/Sequences.sl:495](../../stdlib/Sequences.sl#L495)</sub>

#### Clear *method*

```
void Clear()
```

Drops every node and the pool with it. Every handle previously handed
out is dead afterwards.

<sub>[stdlib/Sequences.sl:507](../../stdlib/Sequences.sl#L507)</sub>

#### ToList *method*

```
List<T> ToList()
```

The values, head first, as a fresh list. O(n), following the links.

**See also** &nbsp; [LinkedList.GetEnumerator](#getenumerator-method)

<sub>[stdlib/Sequences.sl:522](../../stdlib/Sequences.sl#L522)</sub>

#### GetEnumerator *method*

```
IEnumerator<T> GetEnumerator()
```

A cursor over the values, head first, for `foreach`. Follows the links
and keeps its place, so a whole walk is O(n). Adding or removing during
a walk invalidates it.

**See also** &nbsp; [LinkedListCursor](#linkedlistcursort-class)

<sub>[stdlib/Sequences.sl:541](../../stdlib/Sequences.sl#L541)</sub>

### LinkedListCursor&lt;T&gt; *class*

```
class LinkedListCursor<T> : IEnumerator<T>
```

Walks a linked list head first, following the links rather than flattening
them. `At` is O(n) from the head, so a cursor that used it would make
iterating O(n squared); this keeps the node it reached.

**Type parameters**

- `T` — the value type of the list being walked

**See also** &nbsp; [LinkedList.GetEnumerator](#getenumerator-method)

<sub>[stdlib/Sequences.sl:907](../../stdlib/Sequences.sl#L907)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Follows one link, answering false past the tail.

<sub>[stdlib/Sequences.sl:922](../../stdlib/Sequences.sl#L922)</sub>

#### Current *property*

```
T Current { get; }
```

The value in the node the last `MoveNext` reached.

<sub>[stdlib/Sequences.sl:938](../../stdlib/Sequences.sl#L938)</sub>

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

**Type parameters**

- `T` — the element type, constrained not at all so that a `List<Control>` stays possible

<sub>[stdlib/Collections.sl:238](../../stdlib/Collections.sl#L238)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many items are in the list -- not how many it has room for, which
is `Capacity`.

<sub>[stdlib/Collections.sl:261](../../stdlib/Collections.sl#L261)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether there is nothing in it.

<sub>[stdlib/Collections.sl:264](../../stdlib/Collections.sl#L264)</sub>

#### Capacity *property*

```
nuint Capacity { get; set; }
```

The number of items this list can hold before it must grow again.

Settable, as in .NET: assigning reallocates to exactly that size. A
value below `Count` is ignored rather than truncating, because losing
items is not what anyone means by reserving room.

<sub>[stdlib/Collections.sl:271](../../stdlib/Collections.sl#L271)</sub>

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

<sub>[stdlib/Collections.sl:291](../../stdlib/Collections.sl#L291)</sub>

#### Add *method*

```
void Add(T item)
```

Appends to the end, growing the backing array when it is full.

Doubling, so a run of appends costs constant time each on average; a
single one can cost a copy of everything so far.

**See also** &nbsp; [List.RemoveAt](#removeat-method) &middot; [List.AddRange](#addrange-method)

<sub>[stdlib/Collections.sl:314](../../stdlib/Collections.sl#L314)</sub>

#### AddRange *method*

```
void AddRange(IEnumerable<T> items)
```

Appends every item of another sequence, in its order.

The items are collected before any is added, so a list given itself
doubles rather than chasing its own growing end.

**See also** &nbsp; [List.InsertRange](#insertrange-method)

<sub>[stdlib/Collections.sl:328](../../stdlib/Collections.sl#L328)</sub>

#### Insert *method*

```
void Insert(nuint index, T item)
```

Inserts at a position, moving everything after it up one.

`index == Count` appends, which is what makes a loop that inserts in
order need no special case at the end.

<sub>[stdlib/Collections.sl:334](../../stdlib/Collections.sl#L334)</sub>

#### RemoveAt *method*

```
void RemoveAt(nuint index)
```

Removes the item at a position, closing the gap.

The vacated slot is cleared rather than left holding what moved out of
it: a list of references would otherwise keep the last one alive past
its removal, which is a leak that only shows up under a profiler.

**See also** &nbsp; [List.Add](#add-method) &middot; [List.RemoveRange](#removerange-method)

<sub>[stdlib/Collections.sl:357](../../stdlib/Collections.sl#L357)</sub>

#### RemoveRange *method*

```
void RemoveRange(nuint index, nuint count)
```

Removes `count` items from `index` onwards.

**See also** &nbsp; [List.RemoveAt](#removeat-method)

<sub>[stdlib/Collections.sl:372](../../stdlib/Collections.sl#L372)</sub>

#### RemoveAll *method*

```
nuint RemoveAll(Predicate<T> matches)
```

Removes every item the predicate accepts, and answers how many went.

One pass that compacts in place, so removing half a list costs one
traversal rather than one shuffle per removal.

<sub>[stdlib/Collections.sl:391](../../stdlib/Collections.sl#L391)</sub>

#### Reverse *method*

```
void Reverse()
```

Reverses the list in place.

<sub>[stdlib/Collections.sl:411](../../stdlib/Collections.sl#L411)</sub>

#### ToArray *method*

```
T[] ToArray()
```

The items as a new array, which the caller owns.

**See also** &nbsp; [List.CopyTo](#copyto-method)

<sub>[stdlib/Collections.sl:424](../../stdlib/Collections.sl#L424)</sub>

#### CopyTo *method*

```
void CopyTo(T[] into, nuint at)
```

Copies the items into `into`, starting at `at`.

**See also** &nbsp; [List.ToArray](#toarray-method)

<sub>[stdlib/Collections.sl:435](../../stdlib/Collections.sl#L435)</sub>

#### GetRange *method*

```
List<T> GetRange(nuint index, nuint count)
```

A new list holding `count` items from `index` onwards.

**See also** &nbsp; [List.Slice](#slice-method)

<sub>[stdlib/Collections.sl:446](../../stdlib/Collections.sl#L446)</sub>

#### Find *method*

```
T Find(Predicate<T> matches)
```

The first item the predicate accepts, or `default(T)` when there is
none -- which is `null` for a reference type, as it is in .NET.

**See also** &nbsp; [List.FindIndex](#findindex-method) &middot; [List.FindLast](#findlast-method)

<sub>[stdlib/Collections.sl:462](../../stdlib/Collections.sl#L462)</sub>

#### FindLast *method*

```
T FindLast(Predicate<T> matches)
```

The last item the predicate accepts, or `default(T)`.

**See also** &nbsp; [List.Find](#find-method)

<sub>[stdlib/Collections.sl:475](../../stdlib/Collections.sl#L475)</sub>

#### FindAll *method*

```
List<T> FindAll(Predicate<T> matches)
```

Every item the predicate accepts, in order.

**See also** &nbsp; [List.Find](#find-method)

<sub>[stdlib/Collections.sl:488](../../stdlib/Collections.sl#L488)</sub>

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

**See also** &nbsp; [List.FindLastIndex](#findlastindex-method) &middot; [Collections.IndexOf](#indexof-function)

<sub>[stdlib/Collections.sl:509](../../stdlib/Collections.sl#L509)</sub>

#### FindLastIndex *method*

```
Optional<nuint> FindLastIndex(Predicate<T> matches)
```

Where the last item the predicate accepts is, or `None`.

**See also** &nbsp; [List.FindIndex](#findindex-method)

<sub>[stdlib/Collections.sl:522](../../stdlib/Collections.sl#L522)</sub>

#### Exists *method*

```
bool Exists(Predicate<T> matches)
```

Whether any item is accepted by the predicate.

**See also** &nbsp; [List.TrueForAll](#trueforall-method)

<sub>[stdlib/Collections.sl:535](../../stdlib/Collections.sl#L535)</sub>

#### TrueForAll *method*

```
bool TrueForAll(Predicate<T> matches)
```

Whether every item is.

**See also** &nbsp; [List.Exists](#exists-method)

<sub>[stdlib/Collections.sl:540](../../stdlib/Collections.sl#L540)</sub>

#### ForEach *method*

```
void ForEach(Action<T> action)
```

Runs `action` over each item, in order.

The list is read as it goes, so an action that adds to it is a loop
that does not end. .NET throws for this; there is nothing to throw
here, and saying so is the whole of what can be done about it.

<sub>[stdlib/Collections.sl:555](../../stdlib/Collections.sl#L555)</sub>

#### EnsureCapacity *method*

```
nuint EnsureCapacity(nuint capacity)
```

Makes sure there is room for `capacity` items, and answers the capacity
afterwards. Never shrinks.

**See also** &nbsp; [List.TrimExcess](#trimexcess-method) &middot; [List.Capacity](#capacity-property)

<sub>[stdlib/Collections.sl:568](../../stdlib/Collections.sl#L568)</sub>

#### TrimExcess *method*

```
void TrimExcess()
```

Gives back the room past `Count`.

**See also** &nbsp; [List.EnsureCapacity](#ensurecapacity-method)

<sub>[stdlib/Collections.sl:578](../../stdlib/Collections.sl#L578)</sub>

#### Slice *method*

```
List<T> Slice(nuint index, nuint count)
```

`count` items from `index`, as a new list. .NET's name for `GetRange`
since ranges arrived, and the two are the same call.

**See also** &nbsp; [List.GetRange](#getrange-method)

<sub>[stdlib/Collections.sl:588](../../stdlib/Collections.sl#L588)</sub>

#### InsertRange *method*

```
void InsertRange(nuint index, IEnumerable<T> items)
```

Inserts every item of another sequence at `index`, in its order.

Collected first, for the reason `AddRange` gives, and then moved into
place with one shift of the tail rather than one per item.

**See also** &nbsp; [List.AddRange](#addrange-method)

<sub>[stdlib/Collections.sl:596](../../stdlib/Collections.sl#L596)</sub>

#### AsReadOnly *method*

```
IReadOnlyList<T> AsReadOnly()
```

This list seen as something that cannot be changed through it.

**The same object, not a copy.** .NET answers a `ReadOnlyCollection<T>`
wrapper for the same reason this answers an interface: what it buys is a
signature that says "I will not write to this", and neither stops the
owner writing to it meanwhile.

<sub>[stdlib/Collections.sl:629](../../stdlib/Collections.sl#L629)</sub>

#### GetEnumerator *method*

```
IEnumerator<T> GetEnumerator()
```

A cursor over this list, for `foreach` and for passing it on as a
sequence. The cursor reads the list as it goes rather than taking a
copy, so changing the list during a walk changes what the walk sees.

**See also** &nbsp; [ListEnumerator](#listenumeratort-class)

<sub>[stdlib/Collections.sl:636](../../stdlib/Collections.sl#L636)</sub>

#### Clear *method*

```
void Clear()
```

Drops every item. The backing array is replaced rather than merely
forgotten, so any references it held are released now instead of
lingering until the slots are overwritten.

<sub>[stdlib/Collections.sl:641](../../stdlib/Collections.sl#L641)</sub>

### ListEnumerator&lt;T&gt; *class*

```
class ListEnumerator<T> : IEnumerator<T>
```

Walks anything that can be counted and indexed, so one enumerator serves
every list rather than each list writing its own.

**Type parameters**

- `T` — the element type of the list being walked

<sub>[stdlib/Collections.sl:136](../../stdlib/Collections.sl#L136)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances, answering false at the end.

<sub>[stdlib/Collections.sl:154](../../stdlib/Collections.sl#L154)</sub>

#### Current *property*

```
T Current { get; }
```

The item the last `MoveNext` landed on.

<sub>[stdlib/Collections.sl:163](../../stdlib/Collections.sl#L163)</sub>

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

**Type parameters**

- `TKey` — what an entry is found by, which must answer whether it equals another: the lookup is a scan of the keys
- `TValue` — what an entry holds; nothing is asked of it

**See also** &nbsp; [Dictionary](#dictionarytkey-tvalue-class)

<sub>[stdlib/Collections.sl:1118](../../stdlib/Collections.sl#L1118)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many entries there are. Entries rather than distinct keys: `Add`
keeps a repeated key, so this can exceed the number of different keys.

<sub>[stdlib/Collections.sl:1132](../../stdlib/Collections.sl#L1132)</sub>

#### GetKeyAt *method*

```
TKey GetKeyAt(nuint index)
```

The key at a position, in insertion order.

<sub>[stdlib/Collections.sl:1135](../../stdlib/Collections.sl#L1135)</sub>

#### GetValueAt *method*

```
TValue GetValueAt(nuint index)
```

The value at a position, in insertion order.

**See also** &nbsp; [OrderedDictionary.GetKeyAt](#getkeyat-method)

<sub>[stdlib/Collections.sl:1140](../../stdlib/Collections.sl#L1140)</sub>

#### IndexOf *method*

```
Optional<nuint> IndexOf(TKey key)
```

Where a key is, or `None`.

The one lookup a caller needs: asking whether a key is there and then
asking for its value walks the collection twice. An `Optional` rather
than a sentinel, because a position that means "no position" is a rule
every caller has to know and none can be made to.

**See also** &nbsp; [OrderedDictionary.ContainsKey](#containskey-method)

<sub>[stdlib/Collections.sl:1150](../../stdlib/Collections.sl#L1150)</sub>

#### ContainsKey *method*

```
bool ContainsKey(TKey key)
```

Whether the key is there at all. A scan, like everything else here, so
`IndexOf` once beats `ContainsKey` followed by a lookup.

**See also** &nbsp; [OrderedDictionary.IndexOf](#indexof-method)

<sub>[stdlib/Collections.sl:1164](../../stdlib/Collections.sl#L1164)</sub>

#### Add *method*

```
void Add(TKey key, TValue value)
```

Appends, without looking for the key first.

A repeated key is kept rather than replaced, because a document that
contains one said so and dropping either half would be this collection
deciding what the document meant. `SetValue` is the one that replaces.

**See also** &nbsp; [OrderedDictionary.SetValue](#setvalue-method) &middot; [OrderedDictionary.Remove](#remove-method)

<sub>[stdlib/Collections.sl:1174](../../stdlib/Collections.sl#L1174)</sub>

#### SetValue *method*

```
void SetValue(TKey key, TValue value)
```

Replaces the value of a key, or appends it. A replaced key keeps the
position it had, which is the point of the collection.

**See also** &nbsp; [OrderedDictionary.Add](#add-method)

<sub>[stdlib/Collections.sl:1184](../../stdlib/Collections.sl#L1184)</sub>

#### GetValueOrDefault *method*

```
TValue GetValueOrDefault(TKey key, TValue fallback)
```

The value of a key, or the fallback. There is no overload that aborts:
a caller that wants to know writes `IndexOf`.

**See also** &nbsp; [OrderedDictionary.IndexOf](#indexof-method)

<sub>[stdlib/Collections.sl:1200](../../stdlib/Collections.sl#L1200)</sub>

#### Remove *method*

```
bool Remove(TKey key)
```

Removes the first entry with that key, closing the gap. Answers whether
there was one.

**See also** &nbsp; [OrderedDictionary.Add](#add-method)

<sub>[stdlib/Collections.sl:1211](../../stdlib/Collections.sl#L1211)</sub>

#### Clear *method*

```
void Clear()
```

Drops every entry, leaving a count of zero.

<sub>[stdlib/Collections.sl:1223](../../stdlib/Collections.sl#L1223)</sub>

### Pair&lt;TKey, TValue&gt; *class*

```
class Pair<TKey, TValue>
```

One key and one value. What a dictionary yields when it is iterated.

**Type parameters**

- `TKey` — the key half's type; nothing is asked of it, since a pair is looked at rather than looked in
- `TValue` — the value half's type; nothing is asked of it

<sub>[stdlib/Dictionary.sl:45](../../stdlib/Dictionary.sl#L45)</sub>

#### Key *property*

```
TKey Key { get; }
```

The key half.

<sub>[stdlib/Dictionary.sl:48](../../stdlib/Dictionary.sl#L48)</sub>

#### Value *property*

```
TValue Value { get; }
```

The value half.

<sub>[stdlib/Dictionary.sl:51](../../stdlib/Dictionary.sl#L51)</sub>

### Queue&lt;T&gt; *class*

```
class Queue<T> : IEnumerable<T>
```

First in, first out, over a circular buffer.

`Enqueue` and `Dequeue` are both constant time, and neither moves the other
items -- which is the whole reason not to use a `List<T>` and remove from
the front of it.

**Type parameters**

- `T` — what the queue holds; nothing is asked of it

<sub>[stdlib/Sequences.sl:40](../../stdlib/Sequences.sl#L40)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many items are waiting. O(1).

<sub>[stdlib/Sequences.sl:57](../../stdlib/Sequences.sl#L57)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when there is nothing to dequeue. Check this before `Dequeue` or
`Peek`, both of which abort on an empty queue.

**See also** &nbsp; [Queue.Dequeue](#dequeue-method) &middot; [Queue.Peek](#peek-method)

<sub>[stdlib/Sequences.sl:64](../../stdlib/Sequences.sl#L64)</sub>

#### Capacity *property*

```
nuint Capacity { get; }
```

The number of slots the ring has. Always a power of two, so wrapping is
a mask rather than a division.

<sub>[stdlib/Sequences.sl:68](../../stdlib/Sequences.sl#L68)</sub>

#### Enqueue *method*

```
void Enqueue(T item)
```

Adds to the back, growing the ring when it is full.

Constant time, and amortised constant when it grows. Growing moves
every item once, which is the only time anything is copied.

**See also** &nbsp; [Queue.Dequeue](#dequeue-method)

<sub>[stdlib/Sequences.sl:76](../../stdlib/Sequences.sl#L76)</sub>

#### Dequeue *method*

```
T Dequeue()
```

Removes and returns the oldest item. Aborts when the queue is empty.

**See also** &nbsp; [Queue.Enqueue](#enqueue-method) &middot; [Queue.Peek](#peek-method)

<sub>[stdlib/Sequences.sl:88](../../stdlib/Sequences.sl#L88)</sub>

#### Peek *method*

```
T Peek()
```

The oldest item, without removing it. Aborts when the queue is empty.

**See also** &nbsp; [Queue.Dequeue](#dequeue-method)

<sub>[stdlib/Sequences.sl:106](../../stdlib/Sequences.sl#L106)</sub>

#### Clear *method*

```
void Clear()
```

Drops everything. The ring is replaced rather than blanked, so
anything it held is released now.

<sub>[stdlib/Sequences.sl:115](../../stdlib/Sequences.sl#L115)</sub>

#### ToList *method*

```
List<T> ToList()
```

The items, oldest first.

**See also** &nbsp; [Queue.GetEnumerator](#getenumerator-method)

<sub>[stdlib/Sequences.sl:125](../../stdlib/Sequences.sl#L125)</sub>

#### GetEnumerator *method*

```
IEnumerator<T> GetEnumerator()
```

A cursor over the items, oldest first, for `foreach`. Walks the ring
in place rather than copying, unlike `ToList`. Enqueueing or dequeueing
during a walk invalidates it.

**See also** &nbsp; [QueueCursor](#queuecursort-class) &middot; [Queue.ToList](#tolist-method)

<sub>[stdlib/Sequences.sl:145](../../stdlib/Sequences.sl#L145)</sub>

### QueueCursor&lt;T&gt; *class*

```
class QueueCursor<T> : IEnumerator<T>
```

Walks a queue oldest first, without copying it.

The materialising version this replaced built a whole `List<T>` before the
first `MoveNext`, so iterating a queue allocated as much again as the queue
held. A cursor over the ring costs nothing.

**Type parameters**

- `T` — the element type of the queue being walked

**See also** &nbsp; [Queue.GetEnumerator](#getenumerator-method)

<sub>[stdlib/Sequences.sl:847](../../stdlib/Sequences.sl#L847)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances, answering false at the end.

<sub>[stdlib/Sequences.sl:860](../../stdlib/Sequences.sl#L860)</sub>

#### Current *property*

```
T Current { get; }
```

The item the last `MoveNext` landed on.

<sub>[stdlib/Sequences.sl:869](../../stdlib/Sequences.sl#L869)</sub>

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

**Type parameters**

- `TKey` — what an entry is found by, and what the order is over: comparable, since a lookup is a binary search
- `TValue` — what an entry holds; nothing is asked of it

**See also** &nbsp; [Dictionary](#dictionarytkey-tvalue-class)

<sub>[stdlib/Sequences.sl:598](../../stdlib/Sequences.sl#L598)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many entries there are. O(1).

<sub>[stdlib/Sequences.sl:613](../../stdlib/Sequences.sl#L613)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when there are no entries.

<sub>[stdlib/Sequences.sl:616](../../stdlib/Sequences.sl#L616)</sub>

#### IndexOfKey *method*

```
nint IndexOfKey(TKey key)
```

The index `key` is at, or the index it would be inserted at, negated and
offset by one so the two cases stay apart: a result below zero means
"not found, and `-result - 1` is where it goes".

**See also** &nbsp; [SortedList.Find](#find-method)

<sub>[stdlib/Sequences.sl:623](../../stdlib/Sequences.sl#L623)</sub>

#### ContainsKey *method*

```
bool ContainsKey(TKey key)
```

Whether `key` is there. A binary search, O(log n). Reach for `Find`
when the value is what is wanted, rather than searching twice.

**See also** &nbsp; [SortedList.Find](#find-method)

<sub>[stdlib/Sequences.sl:652](../../stdlib/Sequences.sl#L652)</sub>

#### GetKeyAt *method*

```
TKey GetKeyAt(nuint index)
```

The key at a position in the ordering, counting from the smallest.

**See also** &nbsp; [SortedList.GetValueAt](#getvalueat-method)

<sub>[stdlib/Sequences.sl:657](../../stdlib/Sequences.sl#L657)</sub>

#### GetValueAt *method*

```
TValue GetValueAt(nuint index)
```

The value at a position in the ordering, paired with `GetKeyAt` at the
same index. Aborts past the end.

**See also** &nbsp; [SortedList.GetKeyAt](#getkeyat-method)

<sub>[stdlib/Sequences.sl:668](../../stdlib/Sequences.sl#L668)</sub>

#### Find *method*

```
Optional<TValue> Find(TKey key)
```

The value for `key`, or `None` when there is none. The one to reach
for, for the reason `Dictionary.Find` gives: a key is data, so a key
that is not there is an outcome rather than a mistake.

**See also** &nbsp; [SortedList.GetValue](#getvalue-method) &middot; [SortedList.GetValueOrDefault](#getvalueordefault-method)

<sub>[stdlib/Sequences.sl:681](../../stdlib/Sequences.sl#L681)</sub>

#### GetValue *method*

```
TValue GetValue(TKey key)
```

The value for `key`, aborting when there is none.

The asserting form, for a key that is there by construction. `Find` is
the question where it might not be, and `GetValueOrDefault` where a default will do.

**See also** &nbsp; [SortedList.Find](#find-method) &middot; [SortedList.GetValueOrDefault](#getvalueordefault-method)

<sub>[stdlib/Sequences.sl:696](../../stdlib/Sequences.sl#L696)</sub>

#### GetValueOrDefault *method*

```
TValue GetValueOrDefault(TKey key, TValue fallback)
```

The value for `key`, or `fallback` when there is none.

Allocates nothing, at the cost of not distinguishing an absent key from
one whose stored value equals the fallback. `Find` is the one that
tells them apart.

**See also** &nbsp; [SortedList.Find](#find-method)

<sub>[stdlib/Sequences.sl:711](../../stdlib/Sequences.sl#L711)</sub>

#### SetValue *method*

```
void SetValue(TKey key, TValue value)
```

Sets the value of a key, adding it in order if it is new.

An existing key costs a search. A new one costs the search plus a shift
of everything after it -- O(n) -- which is what makes this collection a
poor choice for a map that is written in a loop.

**See also** &nbsp; [SortedList.Remove](#remove-method)

<sub>[stdlib/Sequences.sl:726](../../stdlib/Sequences.sl#L726)</sub>

#### Remove *method*

```
bool Remove(TKey key)
```

Removes a key, answering whether it was there. Closes the gap, so it
is O(n) like `SetValue` on a new key.

**See also** &nbsp; [SortedList.SetValue](#setvalue-method)

<sub>[stdlib/Sequences.sl:756](../../stdlib/Sequences.sl#L756)</sub>

#### Clear *method*

```
void Clear()
```

Drops every entry. The arrays are replaced rather than blanked, so
anything they held is released now.

<sub>[stdlib/Sequences.sl:781](../../stdlib/Sequences.sl#L781)</sub>

#### GetKeys *method*

```
List<TKey> GetKeys()
```

Every key, smallest first, as a fresh list.

**See also** &nbsp; [SortedList.GetValues](#getvalues-method)

<sub>[stdlib/Sequences.sl:791](../../stdlib/Sequences.sl#L791)</sub>

#### GetValues *method*

```
List<TValue> GetValues()
```

Every value, in key order, pairing with `GetKeys` position for position.

**See also** &nbsp; [SortedList.GetKeys](#getkeys-method)

<sub>[stdlib/Sequences.sl:802](../../stdlib/Sequences.sl#L802)</sub>

#### GetEnumerator *method*

```
IEnumerator<Pair<TKey, TValue>> GetEnumerator()
```

A cursor over the entries in key order, for `foreach` -- the ordering
a `Dictionary` cannot give. One `Pair` is built per step. Writing to
the map during a walk invalidates it.

**See also** &nbsp; [SortedListCursor](#sortedlistcursortkey-tvalue-class)

<sub>[stdlib/Sequences.sl:818](../../stdlib/Sequences.sl#L818)</sub>

### SortedListCursor&lt;TKey, TValue&gt; *class*

```
class SortedListCursor<TKey, TValue> : IEnumerator<Pair<TKey, TValue>>
    where TKey : IComparable<TKey>
```

Walks a sorted list in key order.

One `Pair` is built per step, as the materialising version built one per
entry before the walk began -- the difference is that a loop that stops
early now stops allocating too.

**Type parameters**

- `TKey` — the key type of the map being walked, comparable as that map requires
- `TValue` — its value type

**See also** &nbsp; [SortedList.GetEnumerator](#getenumerator-method)

<sub>[stdlib/Sequences.sl:951](../../stdlib/Sequences.sl#L951)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances to the next key in order, answering false at the end.

<sub>[stdlib/Sequences.sl:964](../../stdlib/Sequences.sl#L964)</sub>

#### Current *property*

```
Pair<TKey, TValue> Current { get; }
```

The entry the last `MoveNext` landed on, as a freshly built `Pair`.

<sub>[stdlib/Sequences.sl:973](../../stdlib/Sequences.sl#L973)</sub>

### Stack&lt;T&gt; *class*

```
class Stack<T> : IEnumerable<T>
```

Last in, first out. The top is the end of the array, so nothing moves.

**Type parameters**

- `T` — what the stack holds; nothing is asked of it

<sub>[stdlib/Sequences.sl:164](../../stdlib/Sequences.sl#L164)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many items are on the stack. O(1).

<sub>[stdlib/Sequences.sl:179](../../stdlib/Sequences.sl#L179)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when there is nothing to pop. Check this before `Pop` or `Peek`,
both of which abort on an empty stack.

**See also** &nbsp; [Stack.Pop](#pop-method) &middot; [Stack.Peek](#peek-method)

<sub>[stdlib/Sequences.sl:186](../../stdlib/Sequences.sl#L186)</sub>

#### Capacity *property*

```
nuint Capacity { get; }
```

The number of slots the backing array has.

<sub>[stdlib/Sequences.sl:189](../../stdlib/Sequences.sl#L189)</sub>

#### Push *method*

```
void Push(T item)
```

Pushes onto the top, growing when full. Amortised constant time.

**See also** &nbsp; [Stack.Pop](#pop-method)

<sub>[stdlib/Sequences.sl:194](../../stdlib/Sequences.sl#L194)</sub>

#### Pop *method*

```
T Pop()
```

Removes and returns the top. Aborts when the stack is empty.

**See also** &nbsp; [Stack.Push](#push-method) &middot; [Stack.Peek](#peek-method)

<sub>[stdlib/Sequences.sl:206](../../stdlib/Sequences.sl#L206)</sub>

#### Peek *method*

```
T Peek()
```

The top, without removing it. Aborts when the stack is empty.

**See also** &nbsp; [Stack.Pop](#pop-method)

<sub>[stdlib/Sequences.sl:220](../../stdlib/Sequences.sl#L220)</sub>

#### Clear *method*

```
void Clear()
```

Drops everything. The array is replaced rather than blanked, so
anything it held is released now.

<sub>[stdlib/Sequences.sl:229](../../stdlib/Sequences.sl#L229)</sub>

#### ToList *method*

```
List<T> ToList()
```

The items, top first, which is the order they would be popped in.

**See also** &nbsp; [Stack.GetEnumerator](#getenumerator-method)

<sub>[stdlib/Sequences.sl:238](../../stdlib/Sequences.sl#L238)</sub>

#### GetEnumerator *method*

```
IEnumerator<T> GetEnumerator()
```

A cursor over the items, top first -- the order `Pop` would give them
back in. Pushing or popping during a walk invalidates it.

**See also** &nbsp; [StackCursor](#stackcursort-class) &middot; [Stack.ToList](#tolist-method)

<sub>[stdlib/Sequences.sl:254](../../stdlib/Sequences.sl#L254)</sub>

### StackCursor&lt;T&gt; *class*

```
class StackCursor<T> : IEnumerator<T>
```

Walks a stack top first, matching the order `Pop` would hand things back.

**Type parameters**

- `T` — the element type of the stack being walked

**See also** &nbsp; [Stack.GetEnumerator](#getenumerator-method)

<sub>[stdlib/Sequences.sl:876](../../stdlib/Sequences.sl#L876)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances towards the bottom, answering false at the end.

<sub>[stdlib/Sequences.sl:889](../../stdlib/Sequences.sl#L889)</sub>

#### Current *property*

```
T Current { get; }
```

The item the last `MoveNext` landed on.

<sub>[stdlib/Sequences.sl:898](../../stdlib/Sequences.sl#L898)</sub>

## Functions

### Aggregate *function*

```
A Aggregate<T, A>(T[:] items, A seed, Fold<A, T> combine)
```

Everything folded into one value, left to right. The seed decides the
result type, so `A` is settled before the lambda is looked at.

    long total = Aggregate(numbers, (long)0, (sum, n) => sum + (long)n);

**Type parameters**

- `T` — the element type, which the fold is given one of at a time
- `A` — what is carried along and answered, taken from the seed

<sub>[stdlib/Functional.sl:93](../../stdlib/Functional.sl#L93)</sub>

### Aggregate *function*

```
A Aggregate<T, A>(IEnumerable<T> items, A seed, Fold<A, T> combine)
```

Everything folded into one value, left to right, over any sequence.

**Type parameters**

- `T` — the element type, which the fold is given one of at a time
- `A` — what is carried along and answered, taken from the seed

<sub>[stdlib/Functional.sl:272](../../stdlib/Functional.sl#L272)</sub>

### All *function*

```
bool All<T>(T[:] items, Predicate<T> test)
```

Whether every element does. Stops at the first that does not, and is true
of an empty input.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Any](#any-function)

<sub>[stdlib/Functional.sl:120](../../stdlib/Functional.sl#L120)</sub>

### All *function*

```
bool All<T>(IEnumerable<T> items, Predicate<T> test)
```

Whether every element does, over any sequence. Stops at the first that
does not, and is true of an empty sequence.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Any](#any-function)

<sub>[stdlib/Functional.sl:300](../../stdlib/Functional.sl#L300)</sub>

### Any *function*

```
bool Any<T>(T[:] items, Predicate<T> test)
```

Whether any element satisfies the predicate. Stops at the first that does.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.All](#all-function)

<sub>[stdlib/Functional.sl:105](../../stdlib/Functional.sl#L105)</sub>

### Any *function*

```
bool Any<T>(IEnumerable<T> items, Predicate<T> test)
```

Whether any element satisfies the predicate, over any sequence. Stops at
the first that does, so the rest of the sequence is never walked.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.All](#all-function)

<sub>[stdlib/Functional.sl:285](../../stdlib/Functional.sl#L285)</sub>

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

**Type parameters**

- `T` — the element type, which must order itself

**See also** &nbsp; [Collections.FindLowerBound](#findlowerbound-function) &middot; [Collections.Sort](#sort-function)

<sub>[stdlib/Collections.sl:979](../../stdlib/Collections.sl#L979)</sub>

### Contains *function*

```
bool Contains<T>(IReadOnlyList<T> items, T wanted)
    where T : IEquatable<T>
```

Whether `wanted` is in the list at all. `List<T>.Contains` in .NET, and a
free function here for the reason `IndexOf` is.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

**See also** &nbsp; [Collections.IndexOf](#indexof-function)

<sub>[stdlib/Collections.sl:723](../../stdlib/Collections.sl#L723)</sub>

### Count *function*

```
nuint Count<T>(T[:] items, Predicate<T> test)
```

How many satisfy the predicate.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Where](#where-function)

<sub>[stdlib/Functional.sl:134](../../stdlib/Functional.sl#L134)</sub>

### Count *function*

```
nuint Count<T>(IEnumerable<T> items, Predicate<T> test)
```

How many satisfy the predicate, over any sequence. Walks all of it.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Where](#where-function)

<sub>[stdlib/Functional.sl:314](../../stdlib/Functional.sl#L314)</sub>

### Distinct *function*

```
List<T> Distinct<T>(T[:] items)
    where T : IEquatable<T>
```

The elements, in order, with later repeats left out.

O(n²) in comparisons, which is what asking nothing of `T` but `IEquatable`
costs. A `HashSet<T>` does it in one pass and wants `IHashable` as well;
this is the one to reach for at the sizes a chain works at.

**Type parameters**

- `T` — the element type, which must answer whether it equals another; that alone is what makes this O(n squared)

**See also** &nbsp; [HashSet](#hashsett-class)

<sub>[stdlib/Functional.sl:425](../../stdlib/Functional.sl#L425)</sub>

### Distinct *function*

```
List<T> Distinct<T>(IEnumerable<T> items)
    where T : IEquatable<T>
```

The elements, in order, with later repeats left out, over any sequence.
O(n squared) in comparisons, as the slice overload is.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

**See also** &nbsp; [HashSet](#hashsett-class)

<sub>[stdlib/Functional.sl:441](../../stdlib/Functional.sl#L441)</sub>

### Find *function*

```
Optional<T> Find<T>(T[:] items, Predicate<T> test)
```

The first element satisfying the predicate, if there is one.

    if (Find(people, (p) => p.Age > 65) is Some found) { ... }

An `Optional<T>` rather than a fallback: a struct has no null to stand for
"none" (§2.5), and inventing a value that means it is how a caller comes to
treat a real answer as a miss.

**Type parameters**

- `T` — the element type, which the `Optional` holds; nothing is asked of it

**See also** &nbsp; [Collections.FirstOrDefault](#firstordefault-function) &middot; [Collections.FindIndex](#findindex-function)

<sub>[stdlib/Functional.sl:176](../../stdlib/Functional.sl#L176)</sub>

### FindIndex *function*

```
Optional<nuint> FindIndex<T>(T[:] items, Predicate<T> test)
```

Where the first element satisfying the predicate is, if it is there.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Find](#find-function)

<sub>[stdlib/Functional.sl:190](../../stdlib/Functional.sl#L190)</sub>

### FindLowerBound *function*

```
nuint FindLowerBound<T>(T[:] items, T wanted)
    where T : IComparable<T>
```

The first index at which `wanted` could be inserted and leave the slice
ordered: the length when it belongs at the end, and the index of the first
equal element when there is one.

**Type parameters**

- `T` — the element type, which must order itself

**See also** &nbsp; [Collections.BinarySearch](#binarysearch-function)

<sub>[stdlib/Collections.sl:1010](../../stdlib/Collections.sl#L1010)</sub>

### FirstOrDefault *function*

```
T FirstOrDefault<T>(T[:] items, Predicate<T> test, T fallback)
```

The first element satisfying the predicate, or `fallback` if none does.

The reader that needs no check, because it supplies its own answer. `Find`
is the one to reach for when "there was none" is a different outcome rather
than a different value.

**Type parameters**

- `T` — the element type, which is also the fallback's; nothing is asked of it

**See also** &nbsp; [Collections.Find](#find-function)

<sub>[stdlib/Functional.sl:154](../../stdlib/Functional.sl#L154)</sub>

### FirstOrDefault *function*

```
T FirstOrDefault<T>(IEnumerable<T> items, Predicate<T> test, T fallback)
```

The first element satisfying the predicate, or `fallback` if none does,
over any sequence. A fallback equal to a real element is indistinguishable
from a miss; `Find` is the overload that tells them apart, and it takes a
slice rather than a sequence.

**Type parameters**

- `T` — the element type, which is also the fallback's; nothing is asked of it

**See also** &nbsp; [Collections.Find](#find-function)

<sub>[stdlib/Functional.sl:333](../../stdlib/Functional.sl#L333)</sub>

### ForEach *function*

```
void ForEach<T>(T[:] items, Action<T> body)
```

Runs the action over every element.

**Type parameters**

- `T` — the element type, which the action is handed one of at a time

**See also** &nbsp; [List.ForEach](#foreach-method)

<sub>[stdlib/Functional.sl:204](../../stdlib/Functional.sl#L204)</sub>

### ForEach *function*

```
void ForEach<T>(IEnumerable<T> items, Action<T> body)
```

Runs the action over every element of any sequence.

**Type parameters**

- `T` — the element type, which the action is handed one of at a time

**See also** &nbsp; [List.ForEach](#foreach-method)

<sub>[stdlib/Functional.sl:347](../../stdlib/Functional.sl#L347)</sub>

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

**Type parameters**

- `T` — the element type, which must answer whether it equals another

**See also** &nbsp; [Collections.Contains](#contains-function) &middot; [OrderedDictionary.IndexOf](#indexof-method)

<sub>[stdlib/Collections.sl:708](../../stdlib/Collections.sl#L708)</sub>

### LastIndexOf *function*

```
Optional<nuint> LastIndexOf<T>(IReadOnlyList<T> items, T wanted)
    where T : IEquatable<T>
```

Where the *last* item equal to `wanted` is, if it is there at all.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

**See also** &nbsp; [Collections.IndexOf](#indexof-function)

<sub>[stdlib/Collections.sl:732](../../stdlib/Collections.sl#L732)</sub>

### Max *function*

```
T Max<T>(IReadOnlyList<T> items)
    where T : IComparable<T>
```

The largest item, by its own ordering. The list must not be empty.

**Type parameters**

- `T` — the element type, which must order itself

**See also** &nbsp; [Collections.Min](#min-function)

<sub>[stdlib/Collections.sl:664](../../stdlib/Collections.sl#L664)</sub>

### Min *function*

```
T Min<T>(IReadOnlyList<T> items)
    where T : IComparable<T>
```

The smallest item, by its own ordering. The list must not be empty.

**Type parameters**

- `T` — the element type, which must order itself

**See also** &nbsp; [Collections.Max](#max-function)

<sub>[stdlib/Collections.sl:682](../../stdlib/Collections.sl#L682)</sub>

### OrderBy *function*

```
List<T> OrderBy<T>(T[:] items, Comparer<T> order)
```

The elements ordered by what `order` says, leaving the input alone.

`Sort` orders in place, which a chain cannot use: what is being chained
from is usually somebody else's array. This copies first, and is stable for
the reason `Sort` is.

**Type parameters**

- `T` — the element type; the comparer orders it, so nothing is asked of it

**See also** &nbsp; [Collections.Sort](#sort-function)

<sub>[stdlib/Functional.sl:461](../../stdlib/Functional.sl#L461)</sub>

### OrderBy *function*

```
List<T> OrderBy<T>(IEnumerable<T> items, Comparer<T> order)
```

The elements ordered by what `order` says, over any sequence, leaving the
input alone. Copies into an array first, so it costs one.

**Type parameters**

- `T` — the element type; the comparer orders it, so nothing is asked of it

**See also** &nbsp; [Collections.Sort](#sort-function)

<sub>[stdlib/Functional.sl:477](../../stdlib/Functional.sl#L477)</sub>

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

**Type parameters**

- `T` — the element type, which must answer whether it equals another

**See also** &nbsp; [Collections.RemoveWhere](#removewhere-function) &middot; [List.RemoveAt](#removeat-method)

<sub>[stdlib/Collections.sl:753](../../stdlib/Collections.sl#L753)</sub>

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

**Type parameters**

- `T` — the element type; the predicate does the deciding, so nothing is asked of it

**See also** &nbsp; [Collections.RemoveFirst](#removefirst-function) &middot; [List.RemoveAll](#removeall-method)

<sub>[stdlib/Collections.sl:777](../../stdlib/Collections.sl#L777)</sub>

### Reverse *function*

```
void Reverse<T>(T[:] items)
```

Reverses part of an array in place.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [List.Reverse](#reverse-method)

<sub>[stdlib/Collections.sl:1035](../../stdlib/Collections.sl#L1035)</sub>

### Select *function*

```
List<R> Select<T, R>(T[:] items, Func<T, R> transform)
```

Every element put through the transform.

    var spelled = Select(numbers, n => Text.FromInteger((long)n));

`R` appears nowhere but in the transform's result, so working it out means
binding the lambda's body -- which cannot happen until `T` has given the
lambda its parameter type. The compiler does the two in that order.

**Type parameters**

- `T` — the element type, which settles the transform's parameter
- `R` — what the transform answers, and so what the result holds

**See also** &nbsp; [Collections.Where](#where-function)

<sub>[stdlib/Functional.sl:78](../../stdlib/Functional.sl#L78)</sub>

### Select *function*

```
List<R> Select<T, R>(IEnumerable<T> items, Func<T, R> transform)
```

Every element put through the transform, over any sequence.

**Type parameters**

- `T` — the element type, which settles the transform's parameter
- `R` — what the transform answers, and so what the result holds

**See also** &nbsp; [Collections.Where](#where-function)

<sub>[stdlib/Functional.sl:260](../../stdlib/Functional.sl#L260)</sub>

### Skip *function*

```
List<T> Skip<T>(T[:] items, nuint count)
```

Everything after the first `count` elements, or nothing if there are fewer.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Take](#take-function)

<sub>[stdlib/Functional.sl:227](../../stdlib/Functional.sl#L227)</sub>

### Skip *function*

```
List<T> Skip<T>(IEnumerable<T> items, nuint count)
```

Everything after the first `count`.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Take](#take-function)

<sub>[stdlib/Functional.sl:504](../../stdlib/Functional.sl#L504)</sub>

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

**Type parameters**

- `T` — the element type, which must order itself

**See also** &nbsp; [Collections.BinarySearch](#binarysearch-function) &middot; [Collections.FindLowerBound](#findlowerbound-function)

<sub>[stdlib/Collections.sl:815](../../stdlib/Collections.sl#L815)</sub>

### Sort *function*

```
void Sort<T>(T[:] items, Comparer<T> order)
```

The same, ordered by a comparer rather than by the type itself.

This is the overload that sorts descending, sorts by a field, or sorts a
type that implements nothing at all:

    Sort(people, (a, b) => a.Age - b.Age);

**Type parameters**

- `T` — the element type; the comparer orders it, so nothing is asked of it

**See also** &nbsp; [Collections.OrderBy](#orderby-function)

<sub>[stdlib/Collections.sl:900](../../stdlib/Collections.sl#L900)</sub>

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

**Type parameters**

- `T` — the element type, which must order itself

<sub>[stdlib/Collections.sl:1061](../../stdlib/Collections.sl#L1061)</sub>

### Sort *function*

```
void Sort<T>(IList<T> items, Comparer<T> order)
```

The same, ordered by a comparer.

**Type parameters**

- `T` — the element type; the comparer orders it, so nothing is asked of it

<sub>[stdlib/Collections.sl:1081](../../stdlib/Collections.sl#L1081)</sub>

### Take *function*

```
List<T> Take<T>(T[:] items, nuint count)
```

The first `count` elements, or all of them if there are fewer.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Skip](#skip-function)

<sub>[stdlib/Functional.sl:214](../../stdlib/Functional.sl#L214)</sub>

### Take *function*

```
List<T> Take<T>(IEnumerable<T> items, nuint count)
```

The first `count` elements, or all of them if there are fewer.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Skip](#skip-function)

<sub>[stdlib/Functional.sl:488](../../stdlib/Functional.sl#L488)</sub>

### ToArray *function*

```
T[] ToArray<T>(IEnumerable<T> items)
```

Everything in the sequence, as an array.

One `IEnumerable` overload rather than an `IReadOnlyList` one as well: a
`List<T>` is both, so a pair would be ambiguous at exactly the type a chain
hands over. That is why `ToList` takes only the sequence too.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.ToList](#tolist-function)

<sub>[stdlib/Functional.sl:395](../../stdlib/Functional.sl#L395)</sub>

### ToArray *function*

```
T[] ToArray<T>(T[:] items)
```

The same for a slice, which is not an `IEnumerable` and so does not collide.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.ToList](#tolist-function)

<sub>[stdlib/Functional.sl:408](../../stdlib/Functional.sl#L408)</sub>

### ToList *function*

```
List<T> ToList<T>(IEnumerable<T> items)
```

Everything in the sequence, as a list. The one that makes a `Queue` or a
`HashSet` usable with the array overloads above.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.ToArray](#toarray-function)

<sub>[stdlib/Functional.sl:358](../../stdlib/Functional.sl#L358)</sub>

### ToList *function*

```
List<T> ToList<T>(T[:] items)
```

And a slice, which an array converts to. Not an overload of the above by
accident: a slice is not an `IEnumerable`, so nothing is ever both.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.ToArray](#toarray-function)

<sub>[stdlib/Functional.sl:371](../../stdlib/Functional.sl#L371)</sub>

### Where *function*

```
List<T> Where<T>(T[:] items, Predicate<T> keep)
```

The elements the predicate keeps, in the order they were in.

An array converts to a slice of the whole of itself, so this takes both.

**Type parameters**

- `T` — the element type; the predicate does the deciding, so nothing is asked of it

**See also** &nbsp; [Collections.Select](#select-function) &middot; [Collections.Count](#count-function)

<sub>[stdlib/Functional.sl:56](../../stdlib/Functional.sl#L56)</sub>

### Where *function*

```
List<T> Where<T>(IEnumerable<T> items, Predicate<T> keep)
```

The same, for anything with a `GetEnumerator()` that names its shape --
`List<T>`, `Queue<T>`, `Stack<T>`, `LinkedList<T>`, `HashSet<T>` and
`SortedList<K, V>` all do.

**Type parameters**

- `T` — the element type; the predicate does the deciding, so nothing is asked of it

**See also** &nbsp; [Collections.Select](#select-function)

<sub>[stdlib/Functional.sl:244](../../stdlib/Functional.sl#L244)</sub>

