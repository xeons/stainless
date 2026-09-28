# Standard.Collections

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Reducing a sequence to one value: LINQ's `Sum`, `Average`, `Min`, `Max`,
`MinBy`, `MaxBy` and the `Aggregate` that takes no seed.

`Sum` and `Average` are written once per numeric type -- `int`, `long`,
`float` and `double` -- as C#'s are, since there is no constraint that says
"a number". An integer `Sum` is `checked` and aborts on overflow, where
C#'s throws; an `Average` of nothing aborts, as C#'s throws, and a `Sum` of
nothing is zero. `Min` and `Max` of nothing abort.

## Contents

**Types** &nbsp; [Dictionary&lt;TKey, TValue&gt;](#dictionarytkey-tvalue-class) &middot; [DictionaryEnumerator&lt;TKey, TValue&gt;](#dictionaryenumeratortkey-tvalue-class) &middot; [Enumerable](#enumerable-class) &middot; [Grouping&lt;TKey, TElement&gt;](#groupingtkey-telement-class) &middot; [HashSet&lt;T&gt;](#hashsett-class) &middot; [HashSetEnumerator&lt;T&gt;](#hashsetenumeratort-class) &middot; [IComparable&lt;T&gt;](#icomparablet-interface) &middot; [IEnumerable&lt;T&gt;](#ienumerablet-interface) &middot; [IEnumerator&lt;T&gt;](#ienumeratort-interface) &middot; [IEquatable&lt;T&gt;](#iequatablet-interface) &middot; [IHashable](#ihashable-interface) &middot; [IList&lt;T&gt;](#ilistt-interface) &middot; [IReadOnlyList&lt;T&gt;](#ireadonlylistt-interface) &middot; [KeyValuePair&lt;TKey, TValue&gt;](#keyvaluepairtkey-tvalue-class) &middot; [LinkedList&lt;T&gt;](#linkedlistt-class) &middot; [LinkedListEnumerator&lt;T&gt;](#linkedlistenumeratort-class) &middot; [List&lt;T&gt;](#listt-class) &middot; [ListEnumerator&lt;T&gt;](#listenumeratort-class) &middot; [OrderedDictionary&lt;TKey, TValue&gt;](#ordereddictionarytkey-tvalue-class) &middot; [OrderedList&lt;T&gt;](#orderedlistt-class) &middot; [Queue&lt;T&gt;](#queuet-class) &middot; [QueueEnumerator&lt;T&gt;](#queueenumeratort-class) &middot; [SortedList&lt;TKey, TValue&gt;](#sortedlisttkey-tvalue-class) &middot; [SortedListEnumerator&lt;TKey, TValue&gt;](#sortedlistenumeratortkey-tvalue-class) &middot; [Stack&lt;T&gt;](#stackt-class) &middot; [StackEnumerator&lt;T&gt;](#stackenumeratort-class)

**Functions** &nbsp; [Aggregate](#aggregate-function) &middot; [Aggregate](#aggregate-function) &middot; [Aggregate](#aggregate-function) &middot; [Aggregate](#aggregate-function) &middot; [All](#all-function) &middot; [All](#all-function) &middot; [Any](#any-function) &middot; [Any](#any-function) &middot; [Any](#any-function) &middot; [Any](#any-function) &middot; [Append](#append-function) &middot; [Append](#append-function) &middot; [Average](#average-function) &middot; [Average](#average-function) &middot; [Average](#average-function) &middot; [Average](#average-function) &middot; [Average](#average-function) &middot; [Average](#average-function) &middot; [Average](#average-function) &middot; [Average](#average-function) &middot; [Average](#average-function) &middot; [Average](#average-function) &middot; [Average](#average-function) &middot; [Average](#average-function) &middot; [Average](#average-function) &middot; [Average](#average-function) &middot; [Average](#average-function) &middot; [Average](#average-function) &middot; [BinarySearch](#binarysearch-function) &middot; [Chunk](#chunk-function) &middot; [Chunk](#chunk-function) &middot; [CommonPrefixLength](#commonprefixlength-function) &middot; [Concat](#concat-function) &middot; [Concat](#concat-function) &middot; [Contains](#contains-function) &middot; [Contains](#contains-function) &middot; [Contains](#contains-function) &middot; [ContainsAny](#containsany-function) &middot; [ContainsAny](#containsany-function) &middot; [ContainsAny](#containsany-function) &middot; [ContainsAnyExcept](#containsanyexcept-function) &middot; [ContainsAnyExcept](#containsanyexcept-function) &middot; [ContainsAnyExcept](#containsanyexcept-function) &middot; [ContainsAnyExcept](#containsanyexcept-function) &middot; [ContainsAnyExceptInRange](#containsanyexceptinrange-function) &middot; [ContainsAnyInRange](#containsanyinrange-function) &middot; [Count](#count-function) &middot; [Count](#count-function) &middot; [Count](#count-function) &middot; [Count](#count-function) &middot; [Count](#count-function) &middot; [Distinct](#distinct-function) &middot; [Distinct](#distinct-function) &middot; [DistinctBy](#distinctby-function) &middot; [DistinctBy](#distinctby-function) &middot; [ElementAt](#elementat-function) &middot; [ElementAt](#elementat-function) &middot; [ElementAtOrDefault](#elementatordefault-function) &middot; [ElementAtOrDefault](#elementatordefault-function) &middot; [EndsWith](#endswith-function) &middot; [EndsWith](#endswith-function) &middot; [Except](#except-function) &middot; [Except](#except-function) &middot; [ExceptBy](#exceptby-function) &middot; [ExceptBy](#exceptby-function) &middot; [Find](#find-function) &middot; [FindIndex](#findindex-function) &middot; [FindLowerBound](#findlowerbound-function) &middot; [First](#first-function) &middot; [First](#first-function) &middot; [First](#first-function) &middot; [First](#first-function) &middot; [FirstOrDefault](#firstordefault-function) &middot; [FirstOrDefault](#firstordefault-function) &middot; [FirstOrDefault](#firstordefault-function) &middot; [FirstOrDefault](#firstordefault-function) &middot; [ForEach](#foreach-function) &middot; [ForEach](#foreach-function) &middot; [GroupBy](#groupby-function) &middot; [GroupBy](#groupby-function) &middot; [GroupBy](#groupby-function) &middot; [GroupBy](#groupby-function) &middot; [IndexOf](#indexof-function) &middot; [IndexOf](#indexof-function) &middot; [IndexOf](#indexof-function) &middot; [IndexOfAny](#indexofany-function) &middot; [IndexOfAny](#indexofany-function) &middot; [IndexOfAny](#indexofany-function) &middot; [IndexOfAnyExcept](#indexofanyexcept-function) &middot; [IndexOfAnyExcept](#indexofanyexcept-function) &middot; [IndexOfAnyExcept](#indexofanyexcept-function) &middot; [IndexOfAnyExcept](#indexofanyexcept-function) &middot; [IndexOfAnyExceptInRange](#indexofanyexceptinrange-function) &middot; [IndexOfAnyInRange](#indexofanyinrange-function) &middot; [Intersect](#intersect-function) &middot; [Intersect](#intersect-function) &middot; [IntersectBy](#intersectby-function) &middot; [IntersectBy](#intersectby-function) &middot; [Last](#last-function) &middot; [Last](#last-function) &middot; [Last](#last-function) &middot; [Last](#last-function) &middot; [LastIndexOf](#lastindexof-function) &middot; [LastIndexOf](#lastindexof-function) &middot; [LastIndexOf](#lastindexof-function) &middot; [LastIndexOfAny](#lastindexofany-function) &middot; [LastIndexOfAny](#lastindexofany-function) &middot; [LastIndexOfAny](#lastindexofany-function) &middot; [LastIndexOfAnyExcept](#lastindexofanyexcept-function) &middot; [LastIndexOfAnyExcept](#lastindexofanyexcept-function) &middot; [LastIndexOfAnyExcept](#lastindexofanyexcept-function) &middot; [LastIndexOfAnyExcept](#lastindexofanyexcept-function) &middot; [LastIndexOfAnyExceptInRange](#lastindexofanyexceptinrange-function) &middot; [LastIndexOfAnyInRange](#lastindexofanyinrange-function) &middot; [LastOrDefault](#lastordefault-function) &middot; [LastOrDefault](#lastordefault-function) &middot; [LastOrDefault](#lastordefault-function) &middot; [LastOrDefault](#lastordefault-function) &middot; [Max](#max-function) &middot; [Max](#max-function) &middot; [Max](#max-function) &middot; [Max](#max-function) &middot; [Max](#max-function) &middot; [MaxBy](#maxby-function) &middot; [MaxBy](#maxby-function) &middot; [Min](#min-function) &middot; [Min](#min-function) &middot; [Min](#min-function) &middot; [Min](#min-function) &middot; [Min](#min-function) &middot; [MinBy](#minby-function) &middot; [MinBy](#minby-function) &middot; [Order](#order-function) &middot; [Order](#order-function) &middot; [OrderBy](#orderby-function) &middot; [OrderBy](#orderby-function) &middot; [OrderBy](#orderby-function) &middot; [OrderBy](#orderby-function) &middot; [OrderByDescending](#orderbydescending-function) &middot; [OrderByDescending](#orderbydescending-function) &middot; [OrderDescending](#orderdescending-function) &middot; [OrderDescending](#orderdescending-function) &middot; [Prepend](#prepend-function) &middot; [Prepend](#prepend-function) &middot; [RemoveFirst](#removefirst-function) &middot; [RemoveWhere](#removewhere-function) &middot; [Replace](#replace-function) &middot; [Replace](#replace-function) &middot; [Reverse](#reverse-function) &middot; [Select](#select-function) &middot; [Select](#select-function) &middot; [SelectMany](#selectmany-function) &middot; [SelectMany](#selectmany-function) &middot; [SequenceCompareTo](#sequencecompareto-function) &middot; [SequenceEqual](#sequenceequal-function) &middot; [SequenceEqual](#sequenceequal-function) &middot; [Single](#single-function) &middot; [Single](#single-function) &middot; [Single](#single-function) &middot; [Single](#single-function) &middot; [SingleOrDefault](#singleordefault-function) &middot; [SingleOrDefault](#singleordefault-function) &middot; [SingleOrDefault](#singleordefault-function) &middot; [SingleOrDefault](#singleordefault-function) &middot; [Skip](#skip-function) &middot; [Skip](#skip-function) &middot; [SkipLast](#skiplast-function) &middot; [SkipLast](#skiplast-function) &middot; [SkipWhile](#skipwhile-function) &middot; [SkipWhile](#skipwhile-function) &middot; [Sort](#sort-function) &middot; [Sort](#sort-function) &middot; [Sort](#sort-function) &middot; [Sort](#sort-function) &middot; [Sort](#sort-function) &middot; [Sort](#sort-function) &middot; [StartsWith](#startswith-function) &middot; [StartsWith](#startswith-function) &middot; [Sum](#sum-function) &middot; [Sum](#sum-function) &middot; [Sum](#sum-function) &middot; [Sum](#sum-function) &middot; [Sum](#sum-function) &middot; [Sum](#sum-function) &middot; [Sum](#sum-function) &middot; [Sum](#sum-function) &middot; [Sum](#sum-function) &middot; [Sum](#sum-function) &middot; [Sum](#sum-function) &middot; [Sum](#sum-function) &middot; [Sum](#sum-function) &middot; [Sum](#sum-function) &middot; [Sum](#sum-function) &middot; [Sum](#sum-function) &middot; [Take](#take-function) &middot; [Take](#take-function) &middot; [TakeLast](#takelast-function) &middot; [TakeLast](#takelast-function) &middot; [TakeWhile](#takewhile-function) &middot; [TakeWhile](#takewhile-function) &middot; [ThenBy](#thenby-function) &middot; [ThenBy](#thenby-function) &middot; [ThenByDescending](#thenbydescending-function) &middot; [ToArray](#toarray-function) &middot; [ToArray](#toarray-function) &middot; [ToDictionary](#todictionary-function) &middot; [ToDictionary](#todictionary-function) &middot; [ToDictionary](#todictionary-function) &middot; [ToDictionary](#todictionary-function) &middot; [ToHashSet](#tohashset-function) &middot; [ToHashSet](#tohashset-function) &middot; [ToList](#tolist-function) &middot; [ToList](#tolist-function) &middot; [Trim](#trim-function) &middot; [Trim](#trim-function) &middot; [Trim](#trim-function) &middot; [Trim](#trim-function) &middot; [TrimEnd](#trimend-function) &middot; [TrimEnd](#trimend-function) &middot; [TrimEnd](#trimend-function) &middot; [TrimEnd](#trimend-function) &middot; [TrimStart](#trimstart-function) &middot; [TrimStart](#trimstart-function) &middot; [TrimStart](#trimstart-function) &middot; [TrimStart](#trimstart-function) &middot; [Union](#union-function) &middot; [Union](#union-function) &middot; [UnionBy](#unionby-function) &middot; [UnionBy](#unionby-function) &middot; [Where](#where-function) &middot; [Where](#where-function) &middot; [Zip](#zip-function) &middot; [Zip](#zip-function) &middot; [Zip](#zip-function) &middot; [Zip](#zip-function)

## Types

### Dictionary&lt;TKey, TValue&gt; *class*

```
class Dictionary<TKey, TValue> : IEnumerable<KeyValuePair<TKey, TValue>>
    where TKey : IEquatable<TKey>, IHashable
```

A map from keys to values.

`TKey` has to be equatable and hashable. A primitive, an enum and a String all
are without saying so, so `Dictionary<String, int>` needs nothing extra; a
class says so by implementing `IEquatable<T>` and `IHashable`.

**Type parameters**

- `TKey` — what an entry is found by: equatable and hashable, and the two must agree, since a probe hashes to a slot and then compares
- `TValue` — what an entry holds; nothing is asked of it

<sub>[stdlib/Collections/Dictionary.sl:53](../../stdlib/Collections/Dictionary.sl#L53)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many entries there are. O(1) -- it is a counter, not a scan.

<sub>[stdlib/Collections/Dictionary.sl:72](../../stdlib/Collections/Dictionary.sl#L72)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when there are no entries.

<sub>[stdlib/Collections/Dictionary.sl:75](../../stdlib/Collections/Dictionary.sl#L75)</sub>

#### Capacity *property*

```
nuint Capacity { get; }
```

The number of slots the table has. Always a power of two, so the hash is
reduced with a mask rather than a division.

<sub>[stdlib/Collections/Dictionary.sl:79](../../stdlib/Collections/Dictionary.sl#L79)</sub>

#### ContainsKey *method*

```
bool ContainsKey(TKey key)
```

Whether `key` is there.

One probe, but reach for `TryGetValue` when the value is what is wanted:
`ContainsKey` and then `GetValue` probes twice for one answer.

**See also** &nbsp; [Dictionary.TryGetValue](#trygetvalue-method)

<sub>[stdlib/Collections/Dictionary.sl:103](../../stdlib/Collections/Dictionary.sl#L103)</sub>

#### TryGetValue *method*

```
Optional<TValue> TryGetValue(TKey key)
```

The value for `key`, or `None` when there is none.

**This is the one to reach for.** A key is data -- it arrives from a
file, a socket or a user -- so a key that is not there is an ordinary
outcome and not a mistake in the program, which is the line §2.6 draws
between a value to return and a reason to stop. The answer is read the
way any other variant is:

    if (settings.TryGetValue(name) is Some value) { Use(value); }

One probe, where `ContainsKey` followed by `GetValue` is two, and no sentinel
to collide with a real value the way `GetValueOrDefault` has.

**See also** &nbsp; [Dictionary.GetValue](#getvalue-method) &middot; [Dictionary.GetValueOrDefault](#getvalueordefault-method)

<sub>[stdlib/Collections/Dictionary.sl:120](../../stdlib/Collections/Dictionary.sl#L120)</sub>

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

**See also** &nbsp; [Dictionary.TryGetValue](#trygetvalue-method)

<sub>[stdlib/Collections/Dictionary.sl:138](../../stdlib/Collections/Dictionary.sl#L138)</sub>

#### GetValueOrDefault *method*

```
TValue GetValueOrDefault(TKey key, TValue fallback)
```

The value for `key`, or `fallback` when there is none.

**See also** &nbsp; [Dictionary.TryGetValue](#trygetvalue-method)

<sub>[stdlib/Collections/Dictionary.sl:149](../../stdlib/Collections/Dictionary.sl#L149)</sub>

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

**See also** &nbsp; [Dictionary.TryGetValue](#trygetvalue-method) &middot; [Dictionary.SetValue](#setvalue-method)

<sub>[stdlib/Collections/Dictionary.sl:185](../../stdlib/Collections/Dictionary.sl#L185)</sub>

#### SetValue *method*

```
void SetValue(TKey key, TValue value)
```

Adds the key or replaces what it maps to.

**See also** &nbsp; [Dictionary.Add](#add-method)

<sub>[stdlib/Collections/Dictionary.sl:204](../../stdlib/Collections/Dictionary.sl#L204)</sub>

#### Add *method*

```
bool Add(TKey key, TValue value)
```

Adds the key, or reports that it was already there and changes nothing.

**Returns** &nbsp; true when the entry was added, false when the key was already there

**See also** &nbsp; [Dictionary.SetValue](#setvalue-method) &middot; [Dictionary.Remove](#remove-method)

<sub>[stdlib/Collections/Dictionary.sl:232](../../stdlib/Collections/Dictionary.sl#L232)</sub>

#### Remove *method*

```
bool Remove(TKey key)
```

Removes the key, reporting whether it was there.

**See also** &nbsp; [Dictionary.Add](#add-method)

<sub>[stdlib/Collections/Dictionary.sl:243](../../stdlib/Collections/Dictionary.sl#L243)</sub>

#### Clear *method*

```
void Clear()
```

Drops every entry. The arrays are replaced rather than blanked, so
anything they held is released now.

<sub>[stdlib/Collections/Dictionary.sl:284](../../stdlib/Collections/Dictionary.sl#L284)</sub>

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

<sub>[stdlib/Collections/Dictionary.sl:300](../../stdlib/Collections/Dictionary.sl#L300)</sub>

#### GetValues *method*

```
List<TValue> GetValues()
```

Every value, in the same order `GetKeys` gives.

Values are not distinct: a value stored under two keys appears twice.

**See also** &nbsp; [Dictionary.GetKeys](#getkeys-method)

<sub>[stdlib/Collections/Dictionary.sl:316](../../stdlib/Collections/Dictionary.sl#L316)</sub>

#### GetEnumerator *method*

```
IEnumerator<KeyValuePair<TKey, TValue>> GetEnumerator()
```

A cursor over the entries, for `foreach`.

The order is the table's and is not insertion order; it changes when
the table grows. `Standard.Collections.OrderedDictionary` is the one
that keeps an order. Adding or removing during a walk invalidates the
cursor.

**See also** &nbsp; [DictionaryEnumerator](#dictionaryenumeratortkey-tvalue-class) &middot; [OrderedDictionary](#ordereddictionarytkey-tvalue-class)

<sub>[stdlib/Collections/Dictionary.sl:336](../../stdlib/Collections/Dictionary.sl#L336)</sub>

### DictionaryEnumerator&lt;TKey, TValue&gt; *class*

```
class DictionaryEnumerator<TKey, TValue> : IEnumerator<KeyValuePair<TKey, TValue>>
    where TKey : IEquatable<TKey>, IHashable
```

Walks a dictionary's slots, skipping the empty ones.

The order is the table's own and says nothing about insertion order; adding
or removing during a walk invalidates it, as it does in C#.

**Type parameters**

- `TKey` — the key type of the dictionary being walked, equatable and hashable as that dictionary requires
- `TValue` — its value type

**See also** &nbsp; [Dictionary.GetEnumerator](#getenumerator-method)

<sub>[stdlib/Collections/DictionaryEnumerator.sl:33](../../stdlib/Collections/DictionaryEnumerator.sl#L33)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances to the next occupied slot, answering false at the end. Each
call skips however many empty slots lie between, so a walk costs
O(capacity) overall rather than O(count).

<sub>[stdlib/Collections/DictionaryEnumerator.sl:53](../../stdlib/Collections/DictionaryEnumerator.sl#L53)</sub>

#### Current *property*

```
KeyValuePair<TKey, TValue> Current { get; }
```

The entry the last `MoveNext` landed on, as a freshly built `KeyValuePair`.

<sub>[stdlib/Collections/DictionaryEnumerator.sl:66](../../stdlib/Collections/DictionaryEnumerator.sl#L66)</sub>

### Enumerable *class*

```
class Enumerable
```

Sequences made from nothing: C#'s `Enumerable.Range`, `Repeat` and `Empty`.

    foreach (int i in Enumerable.Range(1, 10)) { ... }

Each answers with a list, as everything here does.

<sub>[stdlib/Collections/Enumerable.sl:29](../../stdlib/Collections/Enumerable.sl#L29)</sub>

#### Range *method*

```
static List<int> Range(int start, int count)
```

`count` integers counting up from `start`. Aborts when the last would
not fit in an `int`.

**Parameters**

- `start` — the first integer
- `count` — how many there are

<sub>[stdlib/Collections/Enumerable.sl:36](../../stdlib/Collections/Enumerable.sl#L36)</sub>

#### Repeat *method*

```
static List<T> Repeat<T>(T element, nuint count)
```

`element`, `count` times over.

**Parameters**

- `element` — what is repeated
- `count` — how many times

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Enumerable.sl:49](../../stdlib/Collections/Enumerable.sl#L49)</sub>

#### Empty *method*

```
static List<T> Empty<T>()
```

A list of nothing.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Enumerable.sl:60](../../stdlib/Collections/Enumerable.sl#L60)</sub>

### Grouping&lt;TKey, TElement&gt; *class*

```
class Grouping<TKey, TElement> : IEnumerable<TElement>
```

The elements `GroupBy` put together under one key: C#'s `IGrouping`.

    foreach (var group in GroupBy(people, (p) => p.City))
        Console.WriteLine(group.Key + ": " + Text.FromInteger((int)group.Count));

A sequence of its own, so every operator here works on one.

**Type parameters**

- `TKey` — what the elements share
- `TElement` — what was grouped

<sub>[stdlib/Collections/Grouping.sl:33](../../stdlib/Collections/Grouping.sl#L33)</sub>

#### Key *property*

```
TKey Key { get; }
```

What every element here was grouped by.

<sub>[stdlib/Collections/Grouping.sl:44](../../stdlib/Collections/Grouping.sl#L44)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many elements share the key.

<sub>[stdlib/Collections/Grouping.sl:47](../../stdlib/Collections/Grouping.sl#L47)</sub>

#### this[] *indexer*

```
TElement this[nuint index] { get; }
```

The element at `index`, in the order they were met, aborting past the end.

<sub>[stdlib/Collections/Grouping.sl:50](../../stdlib/Collections/Grouping.sl#L50)</sub>

#### GetEnumerator *method*

```
IEnumerator<TElement> GetEnumerator()
```

Walks the elements in the order they were met.

<sub>[stdlib/Collections/Grouping.sl:53](../../stdlib/Collections/Grouping.sl#L53)</sub>

### HashSet&lt;T&gt; *class*

```
class HashSet<T> : IEnumerable<T>
    where T : IEquatable<T>, IHashable
```

A set of distinct values, with membership in constant time.

The same table as `Dictionary`, without the values.

**Type parameters**

- `T` — what the set holds: equatable and hashable, and the two must agree, since membership is a hash to a slot and a comparison

<sub>[stdlib/Collections/HashSet.sl:34](../../stdlib/Collections/HashSet.sl#L34)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many distinct items there are. O(1).

<sub>[stdlib/Collections/HashSet.sl:49](../../stdlib/Collections/HashSet.sl#L49)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when there is nothing in it.

<sub>[stdlib/Collections/HashSet.sl:52](../../stdlib/Collections/HashSet.sl#L52)</sub>

#### Capacity *property*

```
nuint Capacity { get; }
```

The number of slots the table has. Always a power of two, so the hash
is reduced with a mask rather than a division.

<sub>[stdlib/Collections/HashSet.sl:56](../../stdlib/Collections/HashSet.sl#L56)</sub>

#### Contains *method*

```
bool Contains(T item)
```

Whether `item` is in the set. One probe, and the question the whole
collection exists to answer.

**See also** &nbsp; [HashSet.Add](#add-method)

<sub>[stdlib/Collections/HashSet.sl:76](../../stdlib/Collections/HashSet.sl#L76)</sub>

#### Add *method*

```
bool Add(T item)
```

Adds the item, reporting whether it was new.

**See also** &nbsp; [HashSet.Remove](#remove-method) &middot; [HashSet.Contains](#contains-method)

<sub>[stdlib/Collections/HashSet.sl:82](../../stdlib/Collections/HashSet.sl#L82)</sub>

#### Remove *method*

```
bool Remove(T item)
```

Removes the item, reporting whether it was there.

**See also** &nbsp; [HashSet.Add](#add-method)

<sub>[stdlib/Collections/HashSet.sl:103](../../stdlib/Collections/HashSet.sl#L103)</sub>

#### Clear *method*

```
void Clear()
```

Drops every item. The arrays are replaced rather than blanked, so
anything they held is released now.

<sub>[stdlib/Collections/HashSet.sl:135](../../stdlib/Collections/HashSet.sl#L135)</sub>

#### UnionWith *method*

```
void UnionWith(IReadOnlyList<T> other)
```

Adds everything in `other` that is not here already.

**See also** &nbsp; [HashSet.ExceptWith](#exceptwith-method) &middot; [HashSet.IntersectWith](#intersectwith-method)

<sub>[stdlib/Collections/HashSet.sl:146](../../stdlib/Collections/HashSet.sl#L146)</sub>

#### ExceptWith *method*

```
void ExceptWith(IReadOnlyList<T> other)
```

Removes everything in `other`.

**See also** &nbsp; [HashSet.UnionWith](#unionwith-method) &middot; [HashSet.IntersectWith](#intersectwith-method)

<sub>[stdlib/Collections/HashSet.sl:156](../../stdlib/Collections/HashSet.sl#L156)</sub>

#### IntersectWith *method*

```
void IntersectWith(HashSet<T> other)
```

Keeps only what is also in `other`.

**See also** &nbsp; [HashSet.UnionWith](#unionwith-method) &middot; [HashSet.ExceptWith](#exceptwith-method)

<sub>[stdlib/Collections/HashSet.sl:166](../../stdlib/Collections/HashSet.sl#L166)</sub>

#### ToList *method*

```
List<T> ToList()
```

Every item, in the table's own order -- which is not insertion order
and changes when the table grows.

A fresh list, and building it scans every slot: O(capacity), not
O(count). `foreach` walks the set without building one.

**See also** &nbsp; [HashSet.GetEnumerator](#getenumerator-method)

<sub>[stdlib/Collections/HashSet.sl:185](../../stdlib/Collections/HashSet.sl#L185)</sub>

#### GetEnumerator *method*

```
IEnumerator<T> GetEnumerator()
```

A cursor over the items, for `foreach`. Allocates nothing beyond the
cursor itself, unlike `ToList`. Adding or removing during a walk
invalidates it.

**See also** &nbsp; [HashSetEnumerator](#hashsetenumeratort-class) &middot; [HashSet.ToList](#tolist-method)

<sub>[stdlib/Collections/HashSet.sl:208](../../stdlib/Collections/HashSet.sl#L208)</sub>

### HashSetEnumerator&lt;T&gt; *class*

```
class HashSetEnumerator<T> : IEnumerator<T>
    where T : IEquatable<T>, IHashable
```

Walks a set's table, skipping the empty slots.

The same shape as `DictionaryEnumerator`, and for the same reason: the
materialising version built a whole `List<T>` before the first `MoveNext`,
so iterating a set allocated as much again as the set held.

**Type parameters**

- `T` — the item type of the set being walked, equatable and hashable as that set requires

**See also** &nbsp; [HashSet.GetEnumerator](#getenumerator-method) &middot; [DictionaryEnumerator](#dictionaryenumeratortkey-tvalue-class)

<sub>[stdlib/Collections/HashSetEnumerator.sl:34](../../stdlib/Collections/HashSetEnumerator.sl#L34)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances to the next occupied slot, answering false at the end.

<sub>[stdlib/Collections/HashSetEnumerator.sl:50](../../stdlib/Collections/HashSetEnumerator.sl#L50)</sub>

#### Current *property*

```
T Current { get; }
```

The item the last `MoveNext` landed on.

<sub>[stdlib/Collections/HashSetEnumerator.sl:63](../../stdlib/Collections/HashSetEnumerator.sl#L63)</sub>

### IComparable&lt;T&gt; *interface*

```
interface IComparable<in T>
```

Returns a negative number, zero, or a positive number when this value orders
before, with, or after `other`.

**Type parameters**

- `T` — what a value is ordered against, which is normally the type implementing this

<sub>[stdlib/Collections/IComparable.sl:29](../../stdlib/Collections/IComparable.sl#L29)</sub>

#### CompareTo *method*

```
int CompareTo(T other)
```

Negative when this orders before `other`, zero when they order
together, positive when after. The sign is all that is read -- the
magnitude means nothing, so returning a subtraction is fine as long as
it cannot overflow.

<sub>[stdlib/Collections/IComparable.sl:35](../../stdlib/Collections/IComparable.sl#L35)</sub>

### IEnumerable&lt;T&gt; *interface*

```
interface IEnumerable<out T>
```

Something that can be walked from the start, once per enumerator.

`foreach` does not need this interface -- it finds `GetEnumerator` by name
-- so implementing it is about being passable as a sequence, not about
being iterable.

**Type parameters**

- `T` — what the sequence yields; nothing is asked of it

<sub>[stdlib/Collections/IEnumerable.sl:31](../../stdlib/Collections/IEnumerable.sl#L31)</sub>

#### GetEnumerator *method*

```
IEnumerator<T> GetEnumerator()
```

A fresh cursor positioned before the first item. Each call gives an
independent one, so a sequence can be walked twice; what is not
promised is that the two walks see the same items, since a collection
changed in between will say something different.

<sub>[stdlib/Collections/IEnumerable.sl:37](../../stdlib/Collections/IEnumerable.sl#L37)</sub>

### IEnumerator&lt;T&gt; *interface*

```
interface IEnumerator<out T>
```

A cursor over a sequence. `MoveNext` advances and reports whether there was
anything to advance to; `Current` returns what it landed on.

`foreach` does not require this interface -- it looks for the methods by
name, so any type with a `GetEnumerator()` can be iterated. Naming the shape
is still worth doing, because it lets a sequence be passed around.

**Type parameters**

- `T` — what the cursor lands on; nothing is asked of it

<sub>[stdlib/Collections/IEnumerator.sl:42](../../stdlib/Collections/IEnumerator.sl#L42)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances to the next item and reports whether there was one. Must be
called before the first `Current`: a fresh enumerator sits before the
start rather than on the first item.

<sub>[stdlib/Collections/IEnumerator.sl:47](../../stdlib/Collections/IEnumerator.sl#L47)</sub>

#### Current *property*

```
T Current { get; }
```

What the last `MoveNext` landed on. Calling this before the first
`MoveNext`, or after one that answered false, is a mistake the
enumerator is not required to catch.

<sub>[stdlib/Collections/IEnumerator.sl:52](../../stdlib/Collections/IEnumerator.sl#L52)</sub>

### IEquatable&lt;T&gt; *interface*

```
interface IEquatable<in T>
```

A value that can be asked whether it equals another of its type.

`Equals` has to be an equivalence -- a value equals itself, equality runs
both ways, and two things equal to a third are equal to each other --
because the containers assume all three and none of them checks. A type
used as a dictionary key implements `IHashable` alongside this, and the two
must agree: equal values must hash alike.

**Type parameters**

- `T` — what a value is compared against, which is normally the type implementing this

<sub>[stdlib/Collections/IEquatable.sl:36](../../stdlib/Collections/IEquatable.sl#L36)</sub>

#### Equals *method*

```
bool Equals(T other)
```

True when this value and `other` are the same value. Implementations
should answer without allocating; this runs once per probe.

<sub>[stdlib/Collections/IEquatable.sl:40](../../stdlib/Collections/IEquatable.sl#L40)</sub>

### IHashable *interface*

```
interface IHashable
```

A value that can be a key in a hash table.

Two values that are `Equals` each other must return the same `GetHashCode`;
two that are not may still collide, and the table handles it. A type that
implements this should implement `IEquatable<T>` as well, since a hash on
its own only narrows the search.

<sub>[stdlib/Collections/IHashable.sl:30](../../stdlib/Collections/IHashable.sl#L30)</sub>

#### GetHashCode *method*

```
nuint GetHashCode()
```

A number standing in for this value. The same value must give the same
number for as long as it is a key in a table, which means hashing only
the parts a key is not going to have changed under it.

<sub>[stdlib/Collections/IHashable.sl:35](../../stdlib/Collections/IHashable.sl#L35)</sub>

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

<sub>[stdlib/Collections/IList.sl:30](../../stdlib/Collections/IList.sl#L30)</sub>

#### this[] *indexer*

```
T this[nuint index] { get; set; }
```

The item at `index`, readable and writable. Redeclared because an
interface cannot widen an inherited member from get-only to get-set.

<sub>[stdlib/Collections/IList.sl:34](../../stdlib/Collections/IList.sl#L34)</sub>

#### Add *method*

```
void Add(T item)
```

Appends to the end.

<sub>[stdlib/Collections/IList.sl:37](../../stdlib/Collections/IList.sl#L37)</sub>

#### RemoveAt *method*

```
void RemoveAt(nuint index)
```

Removes the item at `index`, closing the gap.

<sub>[stdlib/Collections/IList.sl:40](../../stdlib/Collections/IList.sl#L40)</sub>

#### Clear *method*

```
void Clear()
```

Drops every item, leaving a length of zero.

<sub>[stdlib/Collections/IList.sl:43](../../stdlib/Collections/IList.sl#L43)</sub>

### IReadOnlyList&lt;T&gt; *interface*

```
interface IReadOnlyList<out T> : IEnumerable<T>
```

A sequence that knows its length and can be indexed, and cannot be changed
through this reference.

Read-only is about what this interface offers, not about the object: the
list behind it may well be a `List<T>` that someone else is still adding
to. Take this as a parameter type where a function reads and does not
write, which says so in the signature.

It is a sequence too, as C#'s is, so anything that walks one walks this --
and a function taking an `IReadOnlyList<T>` is the closer fit for a list
than one taking an `IEnumerable<T>`.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [IList](#ilistt-interface)

<sub>[stdlib/Collections/IReadOnlyList.sl:40](../../stdlib/Collections/IReadOnlyList.sl#L40)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many items there are.

<sub>[stdlib/Collections/IReadOnlyList.sl:43](../../stdlib/Collections/IReadOnlyList.sl#L43)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether there are none.

<sub>[stdlib/Collections/IReadOnlyList.sl:46](../../stdlib/Collections/IReadOnlyList.sl#L46)</sub>

#### this[] *indexer*

```
T this[nuint index] { get; }
```

The item at `index`, counting from zero. An index at or past `Count`
aborts with the same message an array overrun gives.

<sub>[stdlib/Collections/IReadOnlyList.sl:50](../../stdlib/Collections/IReadOnlyList.sl#L50)</sub>

### KeyValuePair&lt;TKey, TValue&gt; *class*

```
class KeyValuePair<TKey, TValue>
```

One key and one value. What a dictionary yields when it is iterated.

**Type parameters**

- `TKey` — the key half's type; nothing is asked of it, since a pair is looked at rather than looked in
- `TValue` — the value half's type; nothing is asked of it

<sub>[stdlib/Collections/KeyValuePair.sl:31](../../stdlib/Collections/KeyValuePair.sl#L31)</sub>

#### Key *property*

```
TKey Key { get; }
```

The key half.

<sub>[stdlib/Collections/KeyValuePair.sl:34](../../stdlib/Collections/KeyValuePair.sl#L34)</sub>

#### Value *property*

```
TValue Value { get; }
```

The value half.

<sub>[stdlib/Collections/KeyValuePair.sl:37](../../stdlib/Collections/KeyValuePair.sl#L37)</sub>

#### Deconstruct *method*

```
void Deconstruct(out TKey key, out TValue value)
```

Takes the pair apart, which is what lets
`foreach (var (key, value) in dictionary)` name both halves.

<sub>[stdlib/Collections/KeyValuePair.sl:49](../../stdlib/Collections/KeyValuePair.sl#L49)</sub>

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

<sub>[stdlib/Collections/LinkedList.sl:52](../../stdlib/Collections/LinkedList.sl#L52)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many nodes are linked in. O(1), and not the size of the pool --
recycled slots are not counted.

<sub>[stdlib/Collections/LinkedList.sl:79](../../stdlib/Collections/LinkedList.sl#L79)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when nothing is linked in.

<sub>[stdlib/Collections/LinkedList.sl:82](../../stdlib/Collections/LinkedList.sl#L82)</sub>

#### First *property*

```
nint First { get; }
```

A handle to the first node, or -1 when the list is empty.

**See also** &nbsp; [LinkedList.Last](#last-property)

<sub>[stdlib/Collections/LinkedList.sl:87](../../stdlib/Collections/LinkedList.sl#L87)</sub>

#### Last *property*

```
nint Last { get; }
```

A handle to the last node, or -1 when the list is empty.

**See also** &nbsp; [LinkedList.First](#first-property)

<sub>[stdlib/Collections/LinkedList.sl:92](../../stdlib/Collections/LinkedList.sl#L92)</sub>

#### GetNext *method*

```
nint GetNext(nint handle)
```

The node after `handle`, or -1 at the end.

**See also** &nbsp; [LinkedList.GetPrevious](#getprevious-method)

<sub>[stdlib/Collections/LinkedList.sl:97](../../stdlib/Collections/LinkedList.sl#L97)</sub>

#### GetPrevious *method*

```
nint GetPrevious(nint handle)
```

The node before `handle`, or -1 at the start.

**See also** &nbsp; [LinkedList.GetNext](#getnext-method)

<sub>[stdlib/Collections/LinkedList.sl:102](../../stdlib/Collections/LinkedList.sl#L102)</sub>

#### GetValueAt *method*

```
T GetValueAt(nint handle)
```

The value in a node.

`handle` must be live: one this list handed out and has not had
`RemoveAt` called on. A stale or `-1` handle is not checked and reads
whatever the pool slot now holds, so test `at >= 0` before walking.

**See also** &nbsp; [LinkedList.SetValueAt](#setvalueat-method)

<sub>[stdlib/Collections/LinkedList.sl:111](../../stdlib/Collections/LinkedList.sl#L111)</sub>

#### SetValueAt *method*

```
void SetValueAt(nint handle, T value)
```

Replaces the value in a node, leaving the links alone. Same
requirement on `handle` as `GetValueAt`.

**See also** &nbsp; [LinkedList.GetValueAt](#getvalueat-method)

<sub>[stdlib/Collections/LinkedList.sl:117](../../stdlib/Collections/LinkedList.sl#L117)</sub>

#### AddFirst *method*

```
nint AddFirst(T item)
```

Links a new node at the front and answers its handle. Constant time.

**See also** &nbsp; [LinkedList.AddLast](#addlast-method) &middot; [LinkedList.RemoveFirst](#removefirst-method)

<sub>[stdlib/Collections/LinkedList.sl:123](../../stdlib/Collections/LinkedList.sl#L123)</sub>

#### AddLast *method*

```
nint AddLast(T item)
```

Links a new node at the back and answers its handle. Constant time --
the tail is kept, so this does not walk the list.

**See also** &nbsp; [LinkedList.AddFirst](#addfirst-method) &middot; [LinkedList.RemoveLast](#removelast-method)

<sub>[stdlib/Collections/LinkedList.sl:149](../../stdlib/Collections/LinkedList.sl#L149)</sub>

#### InsertAfter *method*

```
nint InsertAfter(nint handle, T item)
```

Links a new node just after `handle` and answers its handle. Constant
time, and the reason to choose this over a `List<T>`. Inserting after
the last node appends.

**See also** &nbsp; [LinkedList.InsertBefore](#insertbefore-method)

<sub>[stdlib/Collections/LinkedList.sl:175](../../stdlib/Collections/LinkedList.sl#L175)</sub>

#### InsertBefore *method*

```
nint InsertBefore(nint handle, T item)
```

Links a new node just before `handle` and answers its handle.
Inserting before the first node prepends.

**See also** &nbsp; [LinkedList.InsertAfter](#insertafter-method)

<sub>[stdlib/Collections/LinkedList.sl:195](../../stdlib/Collections/LinkedList.sl#L195)</sub>

#### RemoveAt *method*

```
void RemoveAt(nint handle)
```

Unlinks a node and recycles its slot. The handle is dead afterwards.

**See also** &nbsp; [LinkedList.RemoveFirst](#removefirst-method) &middot; [LinkedList.RemoveLast](#removelast-method)

<sub>[stdlib/Collections/LinkedList.sl:207](../../stdlib/Collections/LinkedList.sl#L207)</sub>

#### RemoveFirst *method*

```
T RemoveFirst()
```

Removes and returns the first item. Aborts when the list is empty.

**See also** &nbsp; [LinkedList.AddFirst](#addfirst-method) &middot; [LinkedList.RemoveLast](#removelast-method)

<sub>[stdlib/Collections/LinkedList.sl:241](../../stdlib/Collections/LinkedList.sl#L241)</sub>

#### RemoveLast *method*

```
T RemoveLast()
```

Removes and returns the last item. Aborts when the list is empty.

**See also** &nbsp; [LinkedList.AddLast](#addlast-method)

<sub>[stdlib/Collections/LinkedList.sl:254](../../stdlib/Collections/LinkedList.sl#L254)</sub>

#### Clear *method*

```
void Clear()
```

Drops every node and the pool with it. Every handle previously handed
out is dead afterwards.

<sub>[stdlib/Collections/LinkedList.sl:266](../../stdlib/Collections/LinkedList.sl#L266)</sub>

#### ToList *method*

```
List<T> ToList()
```

The values, head first, as a fresh list. O(n), following the links.

**See also** &nbsp; [LinkedList.GetEnumerator](#getenumerator-method)

<sub>[stdlib/Collections/LinkedList.sl:281](../../stdlib/Collections/LinkedList.sl#L281)</sub>

#### GetEnumerator *method*

```
IEnumerator<T> GetEnumerator()
```

A cursor over the values, head first, for `foreach`. Follows the links
and keeps its place, so a whole walk is O(n). Adding or removing during
a walk invalidates it.

**See also** &nbsp; [LinkedListEnumerator](#linkedlistenumeratort-class)

<sub>[stdlib/Collections/LinkedList.sl:300](../../stdlib/Collections/LinkedList.sl#L300)</sub>

### LinkedListEnumerator&lt;T&gt; *class*

```
class LinkedListEnumerator<T> : IEnumerator<T>
```

Walks a linked list head first, following the links rather than flattening
them. `At` is O(n) from the head, so a cursor that used it would make
iterating O(n squared); this keeps the node it reached.

**Type parameters**

- `T` — the value type of the list being walked

**See also** &nbsp; [LinkedList.GetEnumerator](#getenumerator-method)

<sub>[stdlib/Collections/LinkedListEnumerator.sl:30](../../stdlib/Collections/LinkedListEnumerator.sl#L30)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Follows one link, answering false past the tail.

<sub>[stdlib/Collections/LinkedListEnumerator.sl:45](../../stdlib/Collections/LinkedListEnumerator.sl#L45)</sub>

#### Current *property*

```
T Current { get; }
```

The value in the node the last `MoveNext` reached.

<sub>[stdlib/Collections/LinkedListEnumerator.sl:61](../../stdlib/Collections/LinkedListEnumerator.sl#L61)</sub>

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

<sub>[stdlib/Collections/List.sl:52](../../stdlib/Collections/List.sl#L52)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many items are in the list -- not how many it has room for, which
is `Capacity`.

<sub>[stdlib/Collections/List.sl:77](../../stdlib/Collections/List.sl#L77)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether there is nothing in it.

<sub>[stdlib/Collections/List.sl:80](../../stdlib/Collections/List.sl#L80)</sub>

#### Capacity *property*

```
nuint Capacity { get; set; }
```

The number of items this list can hold before it must grow again.

Settable, as in .NET: assigning reallocates to exactly that size. A
value below `Count` is ignored rather than truncating, because losing
items is not what anyone means by reserving room.

<sub>[stdlib/Collections/List.sl:87](../../stdlib/Collections/List.sl#L87)</sub>

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

<sub>[stdlib/Collections/List.sl:107](../../stdlib/Collections/List.sl#L107)</sub>

#### Add *method*

```
void Add(T item)
```

Appends to the end, growing the backing array when it is full.

Doubling, so a run of appends costs constant time each on average; a
single one can cost a copy of everything so far.

**See also** &nbsp; [List.RemoveAt](#removeat-method) &middot; [List.AddRange](#addrange-method)

<sub>[stdlib/Collections/List.sl:130](../../stdlib/Collections/List.sl#L130)</sub>

#### AddRange *method*

```
void AddRange(IEnumerable<T> items)
```

Appends every item of another sequence, in its order.

The items are collected before any is added, so a list given itself
doubles rather than chasing its own growing end.

**See also** &nbsp; [List.InsertRange](#insertrange-method)

<sub>[stdlib/Collections/List.sl:144](../../stdlib/Collections/List.sl#L144)</sub>

#### AddRange *method*

```
void AddRange(ReadOnlySpan<T> items)
```

Appends every element of a span, in its order: one copy, and a
`memmove` for elements that hold no counted reference.

**See also** &nbsp; [List.InsertRange](#insertrange-method)

<sub>[stdlib/Collections/List.sl:150](../../stdlib/Collections/List.sl#L150)</sub>

#### Insert *method*

```
void Insert(nuint index, T item)
```

Inserts at a position, moving everything after it up one.

`index == Count` appends, which is what makes a loop that inserts in
order need no special case at the end.

<sub>[stdlib/Collections/List.sl:156](../../stdlib/Collections/List.sl#L156)</sub>

#### RemoveAt *method*

```
void RemoveAt(nuint index)
```

Removes the item at a position, closing the gap.

The vacated slot is cleared rather than left holding what moved out of
it: a list of references would otherwise keep the last one alive past
its removal, which is a leak that only shows up under a profiler.

**See also** &nbsp; [List.Add](#add-method) &middot; [List.RemoveRange](#removerange-method)

<sub>[stdlib/Collections/List.sl:176](../../stdlib/Collections/List.sl#L176)</sub>

#### RemoveRange *method*

```
void RemoveRange(nuint index, nuint count)
```

Removes `count` items from `index` onwards.

**See also** &nbsp; [List.RemoveAt](#removeat-method)

<sub>[stdlib/Collections/List.sl:189](../../stdlib/Collections/List.sl#L189)</sub>

#### RemoveAll *method*

```
nuint RemoveAll(Predicate<T> matches)
```

Removes every item the predicate accepts, and answers how many went.

One pass that compacts in place, so removing half a list costs one
traversal rather than one shuffle per removal.

<sub>[stdlib/Collections/List.sl:206](../../stdlib/Collections/List.sl#L206)</sub>

#### Reverse *method*

```
void Reverse()
```

Reverses the list in place.

<sub>[stdlib/Collections/List.sl:226](../../stdlib/Collections/List.sl#L226)</sub>

#### ToArray *method*

```
T[] ToArray()
```

The items as a new array, which the caller owns.

**See also** &nbsp; [List.CopyTo](#copyto-method)

<sub>[stdlib/Collections/List.sl:239](../../stdlib/Collections/List.sl#L239)</sub>

#### CopyTo *method*

```
void CopyTo(T[] into, nuint at)
```

Copies the items into `into`, starting at `at`.

**See also** &nbsp; [List.ToArray](#toarray-method)

<sub>[stdlib/Collections/List.sl:244](../../stdlib/Collections/List.sl#L244)</sub>

#### GetRange *method*

```
List<T> GetRange(nuint index, nuint count)
```

A new list holding `count` items from `index` onwards.

**See also** &nbsp; [List.Slice](#slice-method)

<sub>[stdlib/Collections/List.sl:254](../../stdlib/Collections/List.sl#L254)</sub>

#### Find *method*

```
Optional<T> Find(Predicate<T> matches)
```

The first item the predicate accepts, or `None`.

**An `Optional<T>`, where .NET answers `default(T)`.** A `T` that is
never null has no default to answer with, and one that has a default
cannot tell "not found" from "found the zero".

**See also** &nbsp; [List.FindIndex](#findindex-method) &middot; [List.FindLast](#findlast-method)

<sub>[stdlib/Collections/List.sl:273](../../stdlib/Collections/List.sl#L273)</sub>

#### FindLast *method*

```
Optional<T> FindLast(Predicate<T> matches)
```

The last item the predicate accepts, or `None`.

**See also** &nbsp; [List.Find](#find-method)

<sub>[stdlib/Collections/List.sl:286](../../stdlib/Collections/List.sl#L286)</sub>

#### FindAll *method*

```
List<T> FindAll(Predicate<T> matches)
```

Every item the predicate accepts, in order.

**See also** &nbsp; [List.Find](#find-method)

<sub>[stdlib/Collections/List.sl:299](../../stdlib/Collections/List.sl#L299)</sub>

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

<sub>[stdlib/Collections/List.sl:320](../../stdlib/Collections/List.sl#L320)</sub>

#### FindLastIndex *method*

```
Optional<nuint> FindLastIndex(Predicate<T> matches)
```

Where the last item the predicate accepts is, or `None`.

**See also** &nbsp; [List.FindIndex](#findindex-method)

<sub>[stdlib/Collections/List.sl:333](../../stdlib/Collections/List.sl#L333)</sub>

#### Exists *method*

```
bool Exists(Predicate<T> matches)
```

Whether any item is accepted by the predicate.

**See also** &nbsp; [List.TrueForAll](#trueforall-method)

<sub>[stdlib/Collections/List.sl:346](../../stdlib/Collections/List.sl#L346)</sub>

#### TrueForAll *method*

```
bool TrueForAll(Predicate<T> matches)
```

Whether every item is.

**See also** &nbsp; [List.Exists](#exists-method)

<sub>[stdlib/Collections/List.sl:351](../../stdlib/Collections/List.sl#L351)</sub>

#### ForEach *method*

```
void ForEach(Action<T> action)
```

Runs `action` over each item, in order.

The list is read as it goes, so an action that adds to it is a loop
that does not end. .NET throws for this; there is nothing to throw
here, and saying so is the whole of what can be done about it.

<sub>[stdlib/Collections/List.sl:366](../../stdlib/Collections/List.sl#L366)</sub>

#### EnsureCapacity *method*

```
nuint EnsureCapacity(nuint capacity)
```

Makes sure there is room for `capacity` items, and answers the capacity
afterwards. Never shrinks.

**See also** &nbsp; [List.TrimExcess](#trimexcess-method) &middot; [List.Capacity](#capacity-property)

<sub>[stdlib/Collections/List.sl:379](../../stdlib/Collections/List.sl#L379)</sub>

#### TrimExcess *method*

```
void TrimExcess()
```

Gives back the room past `Count`.

**See also** &nbsp; [List.EnsureCapacity](#ensurecapacity-method)

<sub>[stdlib/Collections/List.sl:389](../../stdlib/Collections/List.sl#L389)</sub>

#### Slice *method*

```
List<T> Slice(nuint index, nuint count)
```

`count` items from `index`, as a new list. .NET's name for `GetRange`
since ranges arrived, and the two are the same call.

**See also** &nbsp; [List.GetRange](#getrange-method)

<sub>[stdlib/Collections/List.sl:399](../../stdlib/Collections/List.sl#L399)</sub>

#### InsertRange *method*

```
void InsertRange(nuint index, IEnumerable<T> items)
```

Inserts every item of another sequence at `index`, in its order.

Collected first, for the reason `AddRange` gives, and then moved into
place with one shift of the tail rather than one per item. Another
`List<T>` is copied from directly rather than walked.

**See also** &nbsp; [List.AddRange](#addrange-method)

<sub>[stdlib/Collections/List.sl:408](../../stdlib/Collections/List.sl#L408)</sub>

#### InsertRange *method*

```
void InsertRange(nuint index, ReadOnlySpan<T> items)
```

Inserts every element of a span at `index`, in its order. A span over
this list's own storage is copied out first.

**See also** &nbsp; [List.AddRange](#addrange-method)

<sub>[stdlib/Collections/List.sl:429](../../stdlib/Collections/List.sl#L429)</sub>

#### AsReadOnly *method*

```
IReadOnlyList<T> AsReadOnly()
```

This list seen as something that cannot be changed through it.

**The same object, not a copy.** .NET answers a `ReadOnlyCollection<T>`
wrapper for the same reason this answers an interface: what it buys is a
signature that says "I will not write to this", and neither stops the
owner writing to it meanwhile.

<sub>[stdlib/Collections/List.sl:456](../../stdlib/Collections/List.sl#L456)</sub>

#### GetEnumerator *method*

```
IEnumerator<T> GetEnumerator()
```

A cursor over this list, for `foreach` and for passing it on as a
sequence. The cursor reads the list as it goes rather than taking a
copy, so changing the list during a walk changes what the walk sees.

**See also** &nbsp; [ListEnumerator](#listenumeratort-class)

<sub>[stdlib/Collections/List.sl:463](../../stdlib/Collections/List.sl#L463)</sub>

#### Clear *method*

```
void Clear()
```

Drops every item. The backing array is replaced rather than merely
forgotten, so any references it held are released now instead of
lingering until the slots are overwritten.

<sub>[stdlib/Collections/List.sl:468](../../stdlib/Collections/List.sl#L468)</sub>

### ListEnumerator&lt;T&gt; *class*

```
class ListEnumerator<T> : IEnumerator<T>
```

Walks anything that can be counted and indexed, so one enumerator serves
every list rather than each list writing its own.

**Type parameters**

- `T` — the element type of the list being walked

<sub>[stdlib/Collections/ListEnumerator.sl:28](../../stdlib/Collections/ListEnumerator.sl#L28)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances, answering false at the end.

<sub>[stdlib/Collections/ListEnumerator.sl:46](../../stdlib/Collections/ListEnumerator.sl#L46)</sub>

#### Current *property*

```
T Current { get; }
```

The item the last `MoveNext` landed on.

<sub>[stdlib/Collections/ListEnumerator.sl:55](../../stdlib/Collections/ListEnumerator.sl#L55)</sub>

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

<sub>[stdlib/Collections/OrderedDictionary.sl:45](../../stdlib/Collections/OrderedDictionary.sl#L45)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many entries there are. Entries rather than distinct keys: `Add`
keeps a repeated key, so this can exceed the number of different keys.

<sub>[stdlib/Collections/OrderedDictionary.sl:59](../../stdlib/Collections/OrderedDictionary.sl#L59)</sub>

#### GetKeyAt *method*

```
TKey GetKeyAt(nuint index)
```

The key at a position, in insertion order.

<sub>[stdlib/Collections/OrderedDictionary.sl:62](../../stdlib/Collections/OrderedDictionary.sl#L62)</sub>

#### GetValueAt *method*

```
TValue GetValueAt(nuint index)
```

The value at a position, in insertion order.

**See also** &nbsp; [OrderedDictionary.GetKeyAt](#getkeyat-method)

<sub>[stdlib/Collections/OrderedDictionary.sl:67](../../stdlib/Collections/OrderedDictionary.sl#L67)</sub>

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

<sub>[stdlib/Collections/OrderedDictionary.sl:77](../../stdlib/Collections/OrderedDictionary.sl#L77)</sub>

#### ContainsKey *method*

```
bool ContainsKey(TKey key)
```

Whether the key is there at all. A scan, like everything else here, so
`IndexOf` once beats `ContainsKey` followed by a lookup.

**See also** &nbsp; [OrderedDictionary.IndexOf](#indexof-method)

<sub>[stdlib/Collections/OrderedDictionary.sl:91](../../stdlib/Collections/OrderedDictionary.sl#L91)</sub>

#### Add *method*

```
void Add(TKey key, TValue value)
```

Appends, without looking for the key first.

A repeated key is kept rather than replaced, because a document that
contains one said so and dropping either half would be this collection
deciding what the document meant. `SetValue` is the one that replaces.

**See also** &nbsp; [OrderedDictionary.SetValue](#setvalue-method) &middot; [OrderedDictionary.Remove](#remove-method)

<sub>[stdlib/Collections/OrderedDictionary.sl:101](../../stdlib/Collections/OrderedDictionary.sl#L101)</sub>

#### SetValue *method*

```
void SetValue(TKey key, TValue value)
```

Replaces the value of a key, or appends it. A replaced key keeps the
position it had, which is the point of the collection.

**See also** &nbsp; [OrderedDictionary.Add](#add-method)

<sub>[stdlib/Collections/OrderedDictionary.sl:111](../../stdlib/Collections/OrderedDictionary.sl#L111)</sub>

#### GetValueOrDefault *method*

```
TValue GetValueOrDefault(TKey key, TValue fallback)
```

The value of a key, or the fallback. There is no overload that aborts:
a caller that wants to know writes `IndexOf`.

**See also** &nbsp; [OrderedDictionary.IndexOf](#indexof-method)

<sub>[stdlib/Collections/OrderedDictionary.sl:127](../../stdlib/Collections/OrderedDictionary.sl#L127)</sub>

#### Remove *method*

```
bool Remove(TKey key)
```

Removes the first entry with that key, closing the gap. Answers whether
there was one.

**See also** &nbsp; [OrderedDictionary.Add](#add-method)

<sub>[stdlib/Collections/OrderedDictionary.sl:138](../../stdlib/Collections/OrderedDictionary.sl#L138)</sub>

#### Clear *method*

```
void Clear()
```

Drops every entry, leaving a count of zero.

<sub>[stdlib/Collections/OrderedDictionary.sl:150](../../stdlib/Collections/OrderedDictionary.sl#L150)</sub>

### OrderedList&lt;T&gt; *class*

```
class OrderedList<T> : List<T>
```

A list `OrderBy` made, which remembers the order so that `ThenBy` can
break its ties: C#'s `IOrderedEnumerable`.

    var sorted = ThenBy(OrderBy(people, (p) => p.Surname), (p) => p.Given);

It is a `List<T>`, and anything that takes one takes it.

**Type parameters**

- `T` — the element type

<sub>[stdlib/Collections/OrderedList.sl:32](../../stdlib/Collections/OrderedList.sl#L32)</sub>

#### Order *property*

```
Comparison<T> Order { get; }
```

The order the elements are in.

<sub>[stdlib/Collections/OrderedList.sl:42](../../stdlib/Collections/OrderedList.sl#L42)</sub>

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

<sub>[stdlib/Collections/Queue.sl:35](../../stdlib/Collections/Queue.sl#L35)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many items are waiting. O(1).

<sub>[stdlib/Collections/Queue.sl:50](../../stdlib/Collections/Queue.sl#L50)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when there is nothing to dequeue. Check this before `Dequeue` or
`Peek`, both of which abort on an empty queue.

**See also** &nbsp; [Queue.Dequeue](#dequeue-method) &middot; [Queue.Peek](#peek-method)

<sub>[stdlib/Collections/Queue.sl:57](../../stdlib/Collections/Queue.sl#L57)</sub>

#### Capacity *property*

```
nuint Capacity { get; }
```

The number of slots the ring has. Always a power of two, so wrapping is
a mask rather than a division.

<sub>[stdlib/Collections/Queue.sl:61](../../stdlib/Collections/Queue.sl#L61)</sub>

#### Enqueue *method*

```
void Enqueue(T item)
```

Adds to the back, growing the ring when it is full.

Constant time, and amortised constant when it grows. Growing moves
every item once, which is the only time anything is copied.

**See also** &nbsp; [Queue.Dequeue](#dequeue-method)

<sub>[stdlib/Collections/Queue.sl:69](../../stdlib/Collections/Queue.sl#L69)</sub>

#### Dequeue *method*

```
T Dequeue()
```

Removes and returns the oldest item. Aborts when the queue is empty.

**See also** &nbsp; [Queue.Enqueue](#enqueue-method) &middot; [Queue.Peek](#peek-method)

<sub>[stdlib/Collections/Queue.sl:81](../../stdlib/Collections/Queue.sl#L81)</sub>

#### Peek *method*

```
T Peek()
```

The oldest item, without removing it. Aborts when the queue is empty.

**See also** &nbsp; [Queue.Dequeue](#dequeue-method)

<sub>[stdlib/Collections/Queue.sl:99](../../stdlib/Collections/Queue.sl#L99)</sub>

#### Clear *method*

```
void Clear()
```

Drops everything. The ring is replaced rather than blanked, so
anything it held is released now.

<sub>[stdlib/Collections/Queue.sl:108](../../stdlib/Collections/Queue.sl#L108)</sub>

#### ToList *method*

```
List<T> ToList()
```

The items, oldest first.

**See also** &nbsp; [Queue.GetEnumerator](#getenumerator-method)

<sub>[stdlib/Collections/Queue.sl:118](../../stdlib/Collections/Queue.sl#L118)</sub>

#### GetEnumerator *method*

```
IEnumerator<T> GetEnumerator()
```

A cursor over the items, oldest first, for `foreach`. Walks the ring
in place rather than copying, unlike `ToList`. Enqueueing or dequeueing
during a walk invalidates it.

**See also** &nbsp; [QueueEnumerator](#queueenumeratort-class) &middot; [Queue.ToList](#tolist-method)

<sub>[stdlib/Collections/Queue.sl:137](../../stdlib/Collections/Queue.sl#L137)</sub>

### QueueEnumerator&lt;T&gt; *class*

```
class QueueEnumerator<T> : IEnumerator<T>
```

Walks a queue oldest first, without copying it.

The materialising version this replaced built a whole `List<T>` before the
first `MoveNext`, so iterating a queue allocated as much again as the queue
held. A cursor over the ring costs nothing.

**Type parameters**

- `T` — the element type of the queue being walked

**See also** &nbsp; [Queue.GetEnumerator](#getenumerator-method)

<sub>[stdlib/Collections/QueueEnumerator.sl:32](../../stdlib/Collections/QueueEnumerator.sl#L32)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances, answering false at the end.

<sub>[stdlib/Collections/QueueEnumerator.sl:45](../../stdlib/Collections/QueueEnumerator.sl#L45)</sub>

#### Current *property*

```
T Current { get; }
```

The item the last `MoveNext` landed on.

<sub>[stdlib/Collections/QueueEnumerator.sl:54](../../stdlib/Collections/QueueEnumerator.sl#L54)</sub>

### SortedList&lt;TKey, TValue&gt; *class*

```
class SortedList<TKey, TValue> : IEnumerable<KeyValuePair<TKey, TValue>>
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

<sub>[stdlib/Collections/SortedList.sl:39](../../stdlib/Collections/SortedList.sl#L39)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many entries there are. O(1).

<sub>[stdlib/Collections/SortedList.sl:55](../../stdlib/Collections/SortedList.sl#L55)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when there are no entries.

<sub>[stdlib/Collections/SortedList.sl:58](../../stdlib/Collections/SortedList.sl#L58)</sub>

#### IndexOfKey *method*

```
nint IndexOfKey(TKey key)
```

The index `key` is at, or the index it would be inserted at, negated and
offset by one so the two cases stay apart: a result below zero means
"not found, and `-result - 1` is where it goes".

**See also** &nbsp; [SortedList.TryGetValue](#trygetvalue-method)

<sub>[stdlib/Collections/SortedList.sl:65](../../stdlib/Collections/SortedList.sl#L65)</sub>

#### ContainsKey *method*

```
bool ContainsKey(TKey key)
```

Whether `key` is there. A binary search, O(log n). Reach for `TryGetValue`
when the value is what is wanted, rather than searching twice.

**See also** &nbsp; [SortedList.TryGetValue](#trygetvalue-method)

<sub>[stdlib/Collections/SortedList.sl:94](../../stdlib/Collections/SortedList.sl#L94)</sub>

#### GetKeyAt *method*

```
TKey GetKeyAt(nuint index)
```

The key at a position in the ordering, counting from the smallest.

**See also** &nbsp; [SortedList.GetValueAt](#getvalueat-method)

<sub>[stdlib/Collections/SortedList.sl:99](../../stdlib/Collections/SortedList.sl#L99)</sub>

#### GetValueAt *method*

```
TValue GetValueAt(nuint index)
```

The value at a position in the ordering, paired with `GetKeyAt` at the
same index. Aborts past the end.

**See also** &nbsp; [SortedList.GetKeyAt](#getkeyat-method)

<sub>[stdlib/Collections/SortedList.sl:110](../../stdlib/Collections/SortedList.sl#L110)</sub>

#### TryGetValue *method*

```
Optional<TValue> TryGetValue(TKey key)
```

The value for `key`, or `None` when there is none. The one to reach
for, for the reason `Dictionary.TryGetValue` gives: a key is data, so a key
that is not there is an outcome rather than a mistake.

**See also** &nbsp; [SortedList.GetValue](#getvalue-method) &middot; [SortedList.GetValueOrDefault](#getvalueordefault-method)

<sub>[stdlib/Collections/SortedList.sl:123](../../stdlib/Collections/SortedList.sl#L123)</sub>

#### GetValue *method*

```
TValue GetValue(TKey key)
```

The value for `key`, aborting when there is none.

The asserting form, for a key that is there by construction. `TryGetValue` is
the question where it might not be, and `GetValueOrDefault` where a default will do.

**See also** &nbsp; [SortedList.TryGetValue](#trygetvalue-method) &middot; [SortedList.GetValueOrDefault](#getvalueordefault-method)

<sub>[stdlib/Collections/SortedList.sl:138](../../stdlib/Collections/SortedList.sl#L138)</sub>

#### GetValueOrDefault *method*

```
TValue GetValueOrDefault(TKey key, TValue fallback)
```

The value for `key`, or `fallback` when there is none.

Allocates nothing, at the cost of not distinguishing an absent key from
one whose stored value equals the fallback. `TryGetValue` is the one that
tells them apart.

**See also** &nbsp; [SortedList.TryGetValue](#trygetvalue-method)

<sub>[stdlib/Collections/SortedList.sl:153](../../stdlib/Collections/SortedList.sl#L153)</sub>

#### SetValue *method*

```
void SetValue(TKey key, TValue value)
```

Sets the value of a key, adding it in order if it is new.

An existing key costs a search. A new one costs the search plus a shift
of everything after it -- O(n) -- which is what makes this collection a
poor choice for a map that is written in a loop.

**See also** &nbsp; [SortedList.Remove](#remove-method)

<sub>[stdlib/Collections/SortedList.sl:168](../../stdlib/Collections/SortedList.sl#L168)</sub>

#### Remove *method*

```
bool Remove(TKey key)
```

Removes a key, answering whether it was there. Closes the gap, so it
is O(n) like `SetValue` on a new key.

**See also** &nbsp; [SortedList.SetValue](#setvalue-method)

<sub>[stdlib/Collections/SortedList.sl:198](../../stdlib/Collections/SortedList.sl#L198)</sub>

#### Clear *method*

```
void Clear()
```

Drops every entry. The arrays are replaced rather than blanked, so
anything they held is released now.

<sub>[stdlib/Collections/SortedList.sl:221](../../stdlib/Collections/SortedList.sl#L221)</sub>

#### GetKeys *method*

```
List<TKey> GetKeys()
```

Every key, smallest first, as a fresh list.

**See also** &nbsp; [SortedList.GetValues](#getvalues-method)

<sub>[stdlib/Collections/SortedList.sl:231](../../stdlib/Collections/SortedList.sl#L231)</sub>

#### GetValues *method*

```
List<TValue> GetValues()
```

Every value, in key order, pairing with `GetKeys` position for position.

**See also** &nbsp; [SortedList.GetKeys](#getkeys-method)

<sub>[stdlib/Collections/SortedList.sl:242](../../stdlib/Collections/SortedList.sl#L242)</sub>

#### GetEnumerator *method*

```
IEnumerator<KeyValuePair<TKey, TValue>> GetEnumerator()
```

A cursor over the entries in key order, for `foreach` -- the ordering
a `Dictionary` cannot give. One `KeyValuePair` is built per step. Writing to
the map during a walk invalidates it.

**See also** &nbsp; [SortedListEnumerator](#sortedlistenumeratortkey-tvalue-class)

<sub>[stdlib/Collections/SortedList.sl:259](../../stdlib/Collections/SortedList.sl#L259)</sub>

### SortedListEnumerator&lt;TKey, TValue&gt; *class*

```
class SortedListEnumerator<TKey, TValue> : IEnumerator<KeyValuePair<TKey, TValue>>
    where TKey : IComparable<TKey>
```

Walks a sorted list in key order.

One `KeyValuePair` is built per step, as the materialising version built one per
entry before the walk began -- the difference is that a loop that stops
early now stops allocating too.

**Type parameters**

- `TKey` — the key type of the map being walked, comparable as that map requires
- `TValue` — its value type

**See also** &nbsp; [SortedList.GetEnumerator](#getenumerator-method)

<sub>[stdlib/Collections/SortedListEnumerator.sl:34](../../stdlib/Collections/SortedListEnumerator.sl#L34)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances to the next key in order, answering false at the end.

<sub>[stdlib/Collections/SortedListEnumerator.sl:48](../../stdlib/Collections/SortedListEnumerator.sl#L48)</sub>

#### Current *property*

```
KeyValuePair<TKey, TValue> Current { get; }
```

The entry the last `MoveNext` landed on, as a freshly built `KeyValuePair`.

<sub>[stdlib/Collections/SortedListEnumerator.sl:57](../../stdlib/Collections/SortedListEnumerator.sl#L57)</sub>

### Stack&lt;T&gt; *class*

```
class Stack<T> : IEnumerable<T>
```

Last in, first out. The top is the end of the array, so nothing moves.

**Type parameters**

- `T` — what the stack holds; nothing is asked of it

<sub>[stdlib/Collections/Stack.sl:31](../../stdlib/Collections/Stack.sl#L31)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many items are on the stack. O(1).

<sub>[stdlib/Collections/Stack.sl:44](../../stdlib/Collections/Stack.sl#L44)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when there is nothing to pop. Check this before `Pop` or `Peek`,
both of which abort on an empty stack.

**See also** &nbsp; [Stack.Pop](#pop-method) &middot; [Stack.Peek](#peek-method)

<sub>[stdlib/Collections/Stack.sl:51](../../stdlib/Collections/Stack.sl#L51)</sub>

#### Capacity *property*

```
nuint Capacity { get; }
```

The number of slots the backing array has.

<sub>[stdlib/Collections/Stack.sl:54](../../stdlib/Collections/Stack.sl#L54)</sub>

#### Push *method*

```
void Push(T item)
```

Pushes onto the top, growing when full. Amortised constant time.

**See also** &nbsp; [Stack.Pop](#pop-method)

<sub>[stdlib/Collections/Stack.sl:59](../../stdlib/Collections/Stack.sl#L59)</sub>

#### Pop *method*

```
T Pop()
```

Removes and returns the top. Aborts when the stack is empty.

**See also** &nbsp; [Stack.Push](#push-method) &middot; [Stack.Peek](#peek-method)

<sub>[stdlib/Collections/Stack.sl:71](../../stdlib/Collections/Stack.sl#L71)</sub>

#### Peek *method*

```
T Peek()
```

The top, without removing it. Aborts when the stack is empty.

**See also** &nbsp; [Stack.Pop](#pop-method)

<sub>[stdlib/Collections/Stack.sl:85](../../stdlib/Collections/Stack.sl#L85)</sub>

#### Clear *method*

```
void Clear()
```

Drops everything. The array is replaced rather than blanked, so
anything it held is released now.

<sub>[stdlib/Collections/Stack.sl:94](../../stdlib/Collections/Stack.sl#L94)</sub>

#### ToList *method*

```
List<T> ToList()
```

The items, top first, which is the order they would be popped in.

**See also** &nbsp; [Stack.GetEnumerator](#getenumerator-method)

<sub>[stdlib/Collections/Stack.sl:103](../../stdlib/Collections/Stack.sl#L103)</sub>

#### GetEnumerator *method*

```
IEnumerator<T> GetEnumerator()
```

A cursor over the items, top first -- the order `Pop` would give them
back in. Pushing or popping during a walk invalidates it.

**See also** &nbsp; [StackEnumerator](#stackenumeratort-class) &middot; [Stack.ToList](#tolist-method)

<sub>[stdlib/Collections/Stack.sl:119](../../stdlib/Collections/Stack.sl#L119)</sub>

### StackEnumerator&lt;T&gt; *class*

```
class StackEnumerator<T> : IEnumerator<T>
```

Walks a stack top first, matching the order `Pop` would hand things back.

**Type parameters**

- `T` — the element type of the stack being walked

**See also** &nbsp; [Stack.GetEnumerator](#getenumerator-method)

<sub>[stdlib/Collections/StackEnumerator.sl:28](../../stdlib/Collections/StackEnumerator.sl#L28)</sub>

#### MoveNext *method*

```
bool MoveNext()
```

Advances towards the bottom, answering false at the end.

<sub>[stdlib/Collections/StackEnumerator.sl:41](../../stdlib/Collections/StackEnumerator.sl#L41)</sub>

#### Current *property*

```
T Current { get; }
```

The item the last `MoveNext` landed on.

<sub>[stdlib/Collections/StackEnumerator.sl:50](../../stdlib/Collections/StackEnumerator.sl#L50)</sub>

## Functions

### Aggregate *function*

```
T Aggregate<T>(ReadOnlySpan<T> items, Func<T, T, T> combine)
```

Folds the elements from the first, aborting when there are none: the
first element is the seed, and `combine` takes it and each one after.

**Type parameters**

- `T` — the element type; `combine` does the work

<sub>[stdlib/Collections/Aggregates.sl:732](../../stdlib/Collections/Aggregates.sl#L732)</sub>

### Aggregate *function*

```
T Aggregate<T>(IEnumerable<T> items, Func<T, T, T> combine)
```

Folds the elements from the first, aborting when there are none: the
first element is the seed, and `combine` takes it and each one after.

**Type parameters**

- `T` — the element type; `combine` does the work

<sub>[stdlib/Collections/Aggregates.sl:747](../../stdlib/Collections/Aggregates.sl#L747)</sub>

### Aggregate *function*

```
TAccumulate Aggregate<T, TAccumulate>(ReadOnlySpan<T> items, TAccumulate seed, Fold<TAccumulate, T> combine)
```

Everything folded into one value, left to right. The seed decides the
result type, so `TAccumulate` is settled before the lambda is looked at.

    long total = Aggregate(numbers, (long)0, (sum, n) => sum + (long)n);

**Type parameters**

- `T` — the element type, which the fold is given one of at a time
- `TAccumulate` — what is carried along and answered, taken from the seed

<sub>[stdlib/Collections/Functional.sl:93](../../stdlib/Collections/Functional.sl#L93)</sub>

### Aggregate *function*

```
TAccumulate Aggregate<T, TAccumulate>(IEnumerable<T> items, TAccumulate seed, Fold<TAccumulate, T> combine)
```

Everything folded into one value, left to right, over any sequence.

**Type parameters**

- `T` — the element type, which the fold is given one of at a time
- `TAccumulate` — what is carried along and answered, taken from the seed

<sub>[stdlib/Collections/Functional.sl:273](../../stdlib/Collections/Functional.sl#L273)</sub>

### All *function*

```
bool All<T>(ReadOnlySpan<T> items, Predicate<T> test)
```

Whether every element does. Stops at the first that does not, and is true
of an empty input.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Any](#any-function)

<sub>[stdlib/Collections/Functional.sl:121](../../stdlib/Collections/Functional.sl#L121)</sub>

### All *function*

```
bool All<T>(IEnumerable<T> items, Predicate<T> test)
```

Whether every element does, over any sequence. Stops at the first that
does not, and is true of an empty sequence.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Any](#any-function)

<sub>[stdlib/Collections/Functional.sl:302](../../stdlib/Collections/Functional.sl#L302)</sub>

### Any *function*

```
bool Any<T>(ReadOnlySpan<T> items)
```

Whether there are any elements at all.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:176](../../stdlib/Collections/Elements.sl#L176)</sub>

### Any *function*

```
bool Any<T>(IEnumerable<T> items)
```

Whether there are any elements at all.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:294](../../stdlib/Collections/Elements.sl#L294)</sub>

### Any *function*

```
bool Any<T>(ReadOnlySpan<T> items, Predicate<T> test)
```

Whether any element satisfies the predicate. Stops at the first that does.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.All](#all-function)

<sub>[stdlib/Collections/Functional.sl:106](../../stdlib/Collections/Functional.sl#L106)</sub>

### Any *function*

```
bool Any<T>(IEnumerable<T> items, Predicate<T> test)
```

Whether any element satisfies the predicate, over any sequence. Stops at
the first that does, so the rest of the sequence is never walked.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.All](#all-function)

<sub>[stdlib/Collections/Functional.sl:287](../../stdlib/Collections/Functional.sl#L287)</sub>

### Append *function*

```
List<T> Append<T>(ReadOnlySpan<T> items, T element)
```

The elements, then `element`.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Combining.sl:50](../../stdlib/Collections/Combining.sl#L50)</sub>

### Append *function*

```
List<T> Append<T>(IEnumerable<T> items, T element)
```

The elements, then `element`.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Combining.sl:297](../../stdlib/Collections/Combining.sl#L297)</sub>

### Average *function*

```
double Average(ReadOnlySpan<int> items)
```

The mean of the elements, aborting when there are none.

<sub>[stdlib/Collections/Aggregates.sl:55](../../stdlib/Collections/Aggregates.sl#L55)</sub>

### Average *function*

```
double Average<T>(ReadOnlySpan<T> items, Func<T, int> selector)
```

The mean of what `selector` gives for each element, aborting when there
are none.

**Type parameters**

- `T` — the element type; the selector reads the number off it

<sub>[stdlib/Collections/Aggregates.sl:73](../../stdlib/Collections/Aggregates.sl#L73)</sub>

### Average *function*

```
double Average(IEnumerable<int> items)
```

The mean of the elements, aborting when there are none.

<sub>[stdlib/Collections/Aggregates.sl:108](../../stdlib/Collections/Aggregates.sl#L108)</sub>

### Average *function*

```
double Average<T>(IEnumerable<T> items, Func<T, int> selector)
```

The mean of what `selector` gives for each element, aborting when there
are none.

**Type parameters**

- `T` — the element type; the selector reads the number off it

<sub>[stdlib/Collections/Aggregates.sl:126](../../stdlib/Collections/Aggregates.sl#L126)</sub>

### Average *function*

```
double Average(ReadOnlySpan<long> items)
```

The mean of the elements, aborting when there are none.

<sub>[stdlib/Collections/Aggregates.sl:161](../../stdlib/Collections/Aggregates.sl#L161)</sub>

### Average *function*

```
double Average<T>(ReadOnlySpan<T> items, Func<T, long> selector)
```

The mean of what `selector` gives for each element, aborting when there
are none.

**Type parameters**

- `T` — the element type; the selector reads the number off it

<sub>[stdlib/Collections/Aggregates.sl:179](../../stdlib/Collections/Aggregates.sl#L179)</sub>

### Average *function*

```
double Average(IEnumerable<long> items)
```

The mean of the elements, aborting when there are none.

<sub>[stdlib/Collections/Aggregates.sl:214](../../stdlib/Collections/Aggregates.sl#L214)</sub>

### Average *function*

```
double Average<T>(IEnumerable<T> items, Func<T, long> selector)
```

The mean of what `selector` gives for each element, aborting when there
are none.

**Type parameters**

- `T` — the element type; the selector reads the number off it

<sub>[stdlib/Collections/Aggregates.sl:232](../../stdlib/Collections/Aggregates.sl#L232)</sub>

### Average *function*

```
float Average(ReadOnlySpan<float> items)
```

The mean of the elements, aborting when there are none.

<sub>[stdlib/Collections/Aggregates.sl:267](../../stdlib/Collections/Aggregates.sl#L267)</sub>

### Average *function*

```
float Average<T>(ReadOnlySpan<T> items, Func<T, float> selector)
```

The mean of what `selector` gives for each element, aborting when there
are none.

**Type parameters**

- `T` — the element type; the selector reads the number off it

<sub>[stdlib/Collections/Aggregates.sl:285](../../stdlib/Collections/Aggregates.sl#L285)</sub>

### Average *function*

```
float Average(IEnumerable<float> items)
```

The mean of the elements, aborting when there are none.

<sub>[stdlib/Collections/Aggregates.sl:320](../../stdlib/Collections/Aggregates.sl#L320)</sub>

### Average *function*

```
float Average<T>(IEnumerable<T> items, Func<T, float> selector)
```

The mean of what `selector` gives for each element, aborting when there
are none.

**Type parameters**

- `T` — the element type; the selector reads the number off it

<sub>[stdlib/Collections/Aggregates.sl:338](../../stdlib/Collections/Aggregates.sl#L338)</sub>

### Average *function*

```
double Average(ReadOnlySpan<double> items)
```

The mean of the elements, aborting when there are none.

<sub>[stdlib/Collections/Aggregates.sl:373](../../stdlib/Collections/Aggregates.sl#L373)</sub>

### Average *function*

```
double Average<T>(ReadOnlySpan<T> items, Func<T, double> selector)
```

The mean of what `selector` gives for each element, aborting when there
are none.

**Type parameters**

- `T` — the element type; the selector reads the number off it

<sub>[stdlib/Collections/Aggregates.sl:391](../../stdlib/Collections/Aggregates.sl#L391)</sub>

### Average *function*

```
double Average(IEnumerable<double> items)
```

The mean of the elements, aborting when there are none.

<sub>[stdlib/Collections/Aggregates.sl:426](../../stdlib/Collections/Aggregates.sl#L426)</sub>

### Average *function*

```
double Average<T>(IEnumerable<T> items, Func<T, double> selector)
```

The mean of what `selector` gives for each element, aborting when there
are none.

**Type parameters**

- `T` — the element type; the selector reads the number off it

<sub>[stdlib/Collections/Aggregates.sl:444](../../stdlib/Collections/Aggregates.sl#L444)</sub>

### BinarySearch *function*

```
Optional<nuint> BinarySearch<T>(ReadOnlySpan<T> items, T wanted)
    where T : IComparable<T>
```

Where `wanted` is in an already-ordered slice, if it is there at all.

`FindLowerBound` answers where it would go instead: a caller that wants the
insertion point usually does not want the search, and the other way round.

**Type parameters**

- `T` — the element type, which must order itself

**See also** &nbsp; [Collections.FindLowerBound](#findlowerbound-function) &middot; [Collections.Sort](#sort-function)

<sub>[stdlib/Collections/Collections.sl:356](../../stdlib/Collections/Collections.sl#L356)</sub>

### Chunk *function*

```
List<T[]> Chunk<T>(ReadOnlySpan<T> items, nuint size)
```

The elements in arrays of `size`, the last holding what is left. Aborts
when `size` is zero.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Combining.sl:99](../../stdlib/Collections/Combining.sl#L99)</sub>

### Chunk *function*

```
List<T[]> Chunk<T>(IEnumerable<T> items, nuint size)
```

The elements in arrays of `size`, the last holding what is left. Aborts
when `size` is zero.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Combining.sl:346](../../stdlib/Collections/Combining.sl#L346)</sub>

### CommonPrefixLength *function*

```
nuint CommonPrefixLength<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> other)
    where T : IEquatable<T>
```

How many elements at the start the two have in common.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:211](../../stdlib/Collections/Spans.sl#L211)</sub>

### Concat *function*

```
List<T> Concat<T>(ReadOnlySpan<T> first, ReadOnlySpan<T> second)
```

The elements of `first`, then those of `second`.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Combining.sl:37](../../stdlib/Collections/Combining.sl#L37)</sub>

### Concat *function*

```
List<T> Concat<T>(IEnumerable<T> first, IEnumerable<T> second)
```

The elements of `first`, then those of `second`.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Combining.sl:284](../../stdlib/Collections/Combining.sl#L284)</sub>

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

<sub>[stdlib/Collections/Collections.sl:104](../../stdlib/Collections/Collections.sl#L104)</sub>

### Contains *function*

```
bool Contains<T>(IEnumerable<T> items, T value)
    where T : IEquatable<T>
```

Whether any element equals `value`.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Elements.sl:315](../../stdlib/Collections/Elements.sl#L315)</sub>

### Contains *function*

```
bool Contains<T>(ReadOnlySpan<T> span, T value)
    where T : IEquatable<T>
```

Whether any element equals `value`.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:71](../../stdlib/Collections/Spans.sl#L71)</sub>

### ContainsAny *function*

```
bool ContainsAny<T>(ReadOnlySpan<T> span, T first, T second)
    where T : IEquatable<T>
```

Whether any element equals either value.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:354](../../stdlib/Collections/Spans.sl#L354)</sub>

### ContainsAny *function*

```
bool ContainsAny<T>(ReadOnlySpan<T> span, T first, T second, T third)
    where T : IEquatable<T>
```

Whether any element equals any of the three.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:360](../../stdlib/Collections/Spans.sl#L360)</sub>

### ContainsAny *function*

```
bool ContainsAny<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> values)
    where T : IEquatable<T>
```

Whether any element equals any of `values`.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:367](../../stdlib/Collections/Spans.sl#L367)</sub>

### ContainsAnyExcept *function*

```
bool ContainsAnyExcept<T>(ReadOnlySpan<T> span, T value)
    where T : IEquatable<T>
```

Whether any element is other than `value`.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:373](../../stdlib/Collections/Spans.sl#L373)</sub>

### ContainsAnyExcept *function*

```
bool ContainsAnyExcept<T>(ReadOnlySpan<T> span, T first, T second)
    where T : IEquatable<T>
```

Whether any element equals neither value.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:379](../../stdlib/Collections/Spans.sl#L379)</sub>

### ContainsAnyExcept *function*

```
bool ContainsAnyExcept<T>(ReadOnlySpan<T> span, T first, T second, T third)
    where T : IEquatable<T>
```

Whether any element equals none of the three.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:386](../../stdlib/Collections/Spans.sl#L386)</sub>

### ContainsAnyExcept *function*

```
bool ContainsAnyExcept<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> values)
    where T : IEquatable<T>
```

Whether any element equals none of `values`.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:393](../../stdlib/Collections/Spans.sl#L393)</sub>

### ContainsAnyExceptInRange *function*

```
bool ContainsAnyExceptInRange<T>(ReadOnlySpan<T> span, T low, T high)
    where T : IComparable<T>
```

Whether any element is outside `low` to `high`.

**Type parameters**

- `T` — the element type, which must order itself

<sub>[stdlib/Collections/Spans.sl:470](../../stdlib/Collections/Spans.sl#L470)</sub>

### ContainsAnyInRange *function*

```
bool ContainsAnyInRange<T>(ReadOnlySpan<T> span, T low, T high)
    where T : IComparable<T>
```

Whether any element is between `low` and `high`, both included.

**Type parameters**

- `T` — the element type, which must order itself

<sub>[stdlib/Collections/Spans.sl:464](../../stdlib/Collections/Spans.sl#L464)</sub>

### Count *function*

```
nuint Count<T>(IEnumerable<T> items)
```

How many elements there are, walking them to find out.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:304](../../stdlib/Collections/Elements.sl#L304)</sub>

### Count *function*

```
nuint Count<T>(ReadOnlySpan<T> items, Predicate<T> test)
```

How many satisfy the predicate.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Where](#where-function)

<sub>[stdlib/Collections/Functional.sl:135](../../stdlib/Collections/Functional.sl#L135)</sub>

### Count *function*

```
nuint Count<T>(IEnumerable<T> items, Predicate<T> test)
```

How many satisfy the predicate, over any sequence. Walks all of it.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Where](#where-function)

<sub>[stdlib/Collections/Functional.sl:316](../../stdlib/Collections/Functional.sl#L316)</sub>

### Count *function*

```
nuint Count<T>(ReadOnlySpan<T> span, T value)
    where T : IEquatable<T>
```

How many elements equal `value`.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:77](../../stdlib/Collections/Spans.sl#L77)</sub>

### Count *function*

```
nuint Count<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> value)
    where T : IEquatable<T>
```

How many times `value` appears as a run of elements, counting runs that
do not overlap. An empty `value` appears nowhere.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:132](../../stdlib/Collections/Spans.sl#L132)</sub>

### Distinct *function*

```
List<T> Distinct<T>(ReadOnlySpan<T> items)
    where T : IEquatable<T>
```

The elements, in order, with later repeats left out.

O(n²) in comparisons, which is what asking nothing of `T` but `IEquatable`
costs. A `HashSet<T>` does it in one pass and wants `IHashable` as well;
this is the one to reach for at the sizes a chain works at.

**Type parameters**

- `T` — the element type, which must answer whether it equals another; that alone is what makes this O(n squared)

**See also** &nbsp; [HashSet](#hashsett-class)

<sub>[stdlib/Collections/Functional.sl:421](../../stdlib/Collections/Functional.sl#L421)</sub>

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

<sub>[stdlib/Collections/Functional.sl:437](../../stdlib/Collections/Functional.sl#L437)</sub>

### DistinctBy *function*

```
List<T> DistinctBy<T, TKey>(ReadOnlySpan<T> items, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
```

The first element of each key `keySelector` gives, in order.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which a `HashSet` must be able to hold

<sub>[stdlib/Collections/Combining.sl:186](../../stdlib/Collections/Combining.sl#L186)</sub>

### DistinctBy *function*

```
List<T> DistinctBy<T, TKey>(IEnumerable<T> items, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
```

The first element of each key `keySelector` gives, in order.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which a `HashSet` must be able to hold

<sub>[stdlib/Collections/Combining.sl:433](../../stdlib/Collections/Combining.sl#L433)</sub>

### ElementAt *function*

```
T ElementAt<T>(ReadOnlySpan<T> items, nuint index)
```

The element at `index`, aborting past the end.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:165](../../stdlib/Collections/Elements.sl#L165)</sub>

### ElementAt *function*

```
T ElementAt<T>(IEnumerable<T> items, nuint index)
```

The element at `index`, aborting past the end.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:264](../../stdlib/Collections/Elements.sl#L264)</sub>

### ElementAtOrDefault *function*

```
T ElementAtOrDefault<T>(ReadOnlySpan<T> items, nuint index, T fallback)
```

The element at `index`, or `fallback` past the end.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:170](../../stdlib/Collections/Elements.sl#L170)</sub>

### ElementAtOrDefault *function*

```
T ElementAtOrDefault<T>(IEnumerable<T> items, nuint index, T fallback)
```

The element at `index`, or `fallback` past the end.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:279](../../stdlib/Collections/Elements.sl#L279)</sub>

### EndsWith *function*

```
bool EndsWith<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> value)
    where T : IEquatable<T>
```

Whether `span` ends with the elements of `value`.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:199](../../stdlib/Collections/Spans.sl#L199)</sub>

### EndsWith *function*

```
bool EndsWith<T>(ReadOnlySpan<T> span, T value)
    where T : IEquatable<T>
```

Whether the last element equals `value`.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:205](../../stdlib/Collections/Spans.sl#L205)</sub>

### Except *function*

```
List<T> Except<T>(ReadOnlySpan<T> first, ReadOnlySpan<T> second)
    where T : IEquatable<T>, IHashable
```

The distinct elements of `first` that are not in `second`.

**Type parameters**

- `T` — the element type, which a `HashSet` must be able to hold

<sub>[stdlib/Collections/Combining.sl:256](../../stdlib/Collections/Combining.sl#L256)</sub>

### Except *function*

```
List<T> Except<T>(IEnumerable<T> first, IEnumerable<T> second)
    where T : IEquatable<T>, IHashable
```

The distinct elements of `first` that are not in `second`.

**Type parameters**

- `T` — the element type, which a `HashSet` must be able to hold

<sub>[stdlib/Collections/Combining.sl:503](../../stdlib/Collections/Combining.sl#L503)</sub>

### ExceptBy *function*

```
List<T> ExceptBy<T, TKey>(ReadOnlySpan<T> first, ReadOnlySpan<TKey> keys, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
```

The distinct elements of `first` whose key is not among `keys`.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which a `HashSet` must be able to hold

<sub>[stdlib/Collections/Combining.sl:263](../../stdlib/Collections/Combining.sl#L263)</sub>

### ExceptBy *function*

```
List<T> ExceptBy<T, TKey>(IEnumerable<T> first, IEnumerable<TKey> keys, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
```

The distinct elements of `first` whose key is not among `keys`.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which a `HashSet` must be able to hold

<sub>[stdlib/Collections/Combining.sl:510](../../stdlib/Collections/Combining.sl#L510)</sub>

### Find *function*

```
Optional<T> Find<T>(ReadOnlySpan<T> items, Predicate<T> test)
```

The first element satisfying the predicate, if there is one.

    if (Find(people, (p) => p.Age > 65) is Some found) { ... }

An `Optional<T>` rather than a fallback: a struct has no null to stand for
"none" (§2.5), and inventing a value that means it is how a caller comes to
treat a real answer as a miss.

**Type parameters**

- `T` — the element type, which the `Optional` holds; nothing is asked of it

**See also** &nbsp; [Collections.FirstOrDefault](#firstordefault-function) &middot; [Collections.FindIndex](#findindex-function)

<sub>[stdlib/Collections/Functional.sl:177](../../stdlib/Collections/Functional.sl#L177)</sub>

### FindIndex *function*

```
Optional<nuint> FindIndex<T>(ReadOnlySpan<T> items, Predicate<T> test)
```

Where the first element satisfying the predicate is, if it is there.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Find](#find-function)

<sub>[stdlib/Collections/Functional.sl:191](../../stdlib/Collections/Functional.sl#L191)</sub>

### FindLowerBound *function*

```
nuint FindLowerBound<T>(ReadOnlySpan<T> items, T wanted)
    where T : IComparable<T>
```

The first index at which `wanted` could be inserted and leave the slice
ordered: the length when it belongs at the end, and the index of the first
equal element when there is one.

**Type parameters**

- `T` — the element type, which must order itself

**See also** &nbsp; [Collections.BinarySearch](#binarysearch-function)

<sub>[stdlib/Collections/Collections.sl:387](../../stdlib/Collections/Collections.sl#L387)</sub>

### First *function*

```
T First<T>(ReadOnlySpan<T> items)
```

The first element, aborting when there is none.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.FirstOrDefault](#firstordefault-function)

<sub>[stdlib/Collections/Elements.sl:39](../../stdlib/Collections/Elements.sl#L39)</sub>

### First *function*

```
T First<T>(ReadOnlySpan<T> items, Predicate<T> test)
```

The first element the predicate accepts, aborting when there is none.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Find](#find-function)

<sub>[stdlib/Collections/Elements.sl:50](../../stdlib/Collections/Elements.sl#L50)</sub>

### First *function*

```
T First<T>(IEnumerable<T> items)
```

The first element, aborting when there is none.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.FirstOrDefault](#firstordefault-function)

<sub>[stdlib/Collections/Elements.sl:184](../../stdlib/Collections/Elements.sl#L184)</sub>

### First *function*

```
T First<T>(IEnumerable<T> items, Predicate<T> test)
```

The first element the predicate accepts, aborting when there is none.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Find](#find-function)

<sub>[stdlib/Collections/Elements.sl:195](../../stdlib/Collections/Elements.sl#L195)</sub>

### FirstOrDefault *function*

```
T FirstOrDefault<T>(ReadOnlySpan<T> items, T fallback)
```

The first element, or `fallback` when there is none.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:63](../../stdlib/Collections/Elements.sl#L63)</sub>

### FirstOrDefault *function*

```
T FirstOrDefault<T>(IEnumerable<T> items, T fallback)
```

The first element, or `fallback` when there is none.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:208](../../stdlib/Collections/Elements.sl#L208)</sub>

### FirstOrDefault *function*

```
T FirstOrDefault<T>(ReadOnlySpan<T> items, Predicate<T> test, T fallback)
```

The first element satisfying the predicate, or `fallback` if none does.

The reader that needs no check, because it supplies its own answer. `Find`
is the one to reach for when "there was none" is a different outcome rather
than a different value.

**Type parameters**

- `T` — the element type, which is also the fallback's; nothing is asked of it

**See also** &nbsp; [Collections.Find](#find-function)

<sub>[stdlib/Collections/Functional.sl:155](../../stdlib/Collections/Functional.sl#L155)</sub>

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

<sub>[stdlib/Collections/Functional.sl:335](../../stdlib/Collections/Functional.sl#L335)</sub>

### ForEach *function*

```
void ForEach<T>(ReadOnlySpan<T> items, Action<T> body)
```

Runs the action over every element.

**Type parameters**

- `T` — the element type, which the action is handed one of at a time

**See also** &nbsp; [List.ForEach](#foreach-method)

<sub>[stdlib/Collections/Functional.sl:205](../../stdlib/Collections/Functional.sl#L205)</sub>

### ForEach *function*

```
void ForEach<T>(IEnumerable<T> items, Action<T> body)
```

Runs the action over every element of any sequence.

**Type parameters**

- `T` — the element type, which the action is handed one of at a time

**See also** &nbsp; [List.ForEach](#foreach-method)

<sub>[stdlib/Collections/Functional.sl:349](../../stdlib/Collections/Functional.sl#L349)</sub>

### GroupBy *function*

```
List<Grouping<TKey, T>> GroupBy<T, TKey>(ReadOnlySpan<T> items, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
```

The elements put together by the key `keySelector` gives each, the groups
in the order their keys were first met.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which a `Dictionary` must be able to hold

<sub>[stdlib/Collections/Grouping.sl:63](../../stdlib/Collections/Grouping.sl#L63)</sub>

### GroupBy *function*

```
List<Grouping<TKey, TElement>> GroupBy<T, TKey, TElement>(ReadOnlySpan<T> items, Func<T, TKey> keySelector, Func<T, TElement> elementSelector)
    where TKey : IEquatable<TKey>, IHashable
```

What `elementSelector` makes of each element, put together by the key
`keySelector` gives it.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which a `Dictionary` must be able to hold
- `TElement` — what is grouped

<sub>[stdlib/Collections/Grouping.sl:73](../../stdlib/Collections/Grouping.sl#L73)</sub>

### GroupBy *function*

```
List<Grouping<TKey, T>> GroupBy<T, TKey>(IEnumerable<T> items, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
```

The elements put together by the key `keySelector` gives each, the groups
in the order their keys were first met.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which a `Dictionary` must be able to hold

<sub>[stdlib/Collections/Grouping.sl:139](../../stdlib/Collections/Grouping.sl#L139)</sub>

### GroupBy *function*

```
List<Grouping<TKey, TElement>> GroupBy<T, TKey, TElement>(IEnumerable<T> items, Func<T, TKey> keySelector, Func<T, TElement> elementSelector)
    where TKey : IEquatable<TKey>, IHashable
```

What `elementSelector` makes of each element, put together by the key
`keySelector` gives it.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which a `Dictionary` must be able to hold
- `TElement` — what is grouped

<sub>[stdlib/Collections/Grouping.sl:149](../../stdlib/Collections/Grouping.sl#L149)</sub>

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

<sub>[stdlib/Collections/Collections.sl:89](../../stdlib/Collections/Collections.sl#L89)</sub>

### IndexOf *function*

```
Optional<nuint> IndexOf<T>(ReadOnlySpan<T> span, T value)
    where T : IEquatable<T>
```

Where the first element equal to `value` is, if there is one.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

**See also** &nbsp; [Collections.LastIndexOf](#lastindexof-function)

<sub>[stdlib/Collections/Spans.sl:44](../../stdlib/Collections/Spans.sl#L44)</sub>

### IndexOf *function*

```
Optional<nuint> IndexOf<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> value)
    where T : IEquatable<T>
```

Where `value` first appears as a run of elements. An empty `value`
appears at the start.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

**See also** &nbsp; [Collections.LastIndexOf](#lastindexof-function)

<sub>[stdlib/Collections/Spans.sl:95](../../stdlib/Collections/Spans.sl#L95)</sub>

### IndexOfAny *function*

```
Optional<nuint> IndexOfAny<T>(ReadOnlySpan<T> span, T first, T second)
    where T : IEquatable<T>
```

Where the first element equal to either value is.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:228](../../stdlib/Collections/Spans.sl#L228)</sub>

### IndexOfAny *function*

```
Optional<nuint> IndexOfAny<T>(ReadOnlySpan<T> span, T first, T second, T third)
    where T : IEquatable<T>
```

Where the first element equal to any of the three is.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:235](../../stdlib/Collections/Spans.sl#L235)</sub>

### IndexOfAny *function*

```
Optional<nuint> IndexOfAny<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> values)
    where T : IEquatable<T>
```

Where the first element equal to any of `values` is.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:242](../../stdlib/Collections/Spans.sl#L242)</sub>

### IndexOfAnyExcept *function*

```
Optional<nuint> IndexOfAnyExcept<T>(ReadOnlySpan<T> span, T value)
    where T : IEquatable<T>
```

Where the first element other than `value` is.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:284](../../stdlib/Collections/Spans.sl#L284)</sub>

### IndexOfAnyExcept *function*

```
Optional<nuint> IndexOfAnyExcept<T>(ReadOnlySpan<T> span, T first, T second)
    where T : IEquatable<T>
```

Where the first element equal to neither value is.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:291](../../stdlib/Collections/Spans.sl#L291)</sub>

### IndexOfAnyExcept *function*

```
Optional<nuint> IndexOfAnyExcept<T>(ReadOnlySpan<T> span, T first, T second, T third)
    where T : IEquatable<T>
```

Where the first element equal to none of the three is.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:298](../../stdlib/Collections/Spans.sl#L298)</sub>

### IndexOfAnyExcept *function*

```
Optional<nuint> IndexOfAnyExcept<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> values)
    where T : IEquatable<T>
```

Where the first element equal to none of `values` is.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:305](../../stdlib/Collections/Spans.sl#L305)</sub>

### IndexOfAnyExceptInRange *function*

```
Optional<nuint> IndexOfAnyExceptInRange<T>(ReadOnlySpan<T> span, T low, T high)
    where T : IComparable<T>
```

Where the first element outside `low` to `high` is.

**Type parameters**

- `T` — the element type, which must order itself

<sub>[stdlib/Collections/Spans.sl:422](../../stdlib/Collections/Spans.sl#L422)</sub>

### IndexOfAnyInRange *function*

```
Optional<nuint> IndexOfAnyInRange<T>(ReadOnlySpan<T> span, T low, T high)
    where T : IComparable<T>
```

Where the first element between `low` and `high`, both included, is.

**Type parameters**

- `T` — the element type, which must order itself

<sub>[stdlib/Collections/Spans.sl:408](../../stdlib/Collections/Spans.sl#L408)</sub>

### Intersect *function*

```
List<T> Intersect<T>(ReadOnlySpan<T> first, ReadOnlySpan<T> second)
    where T : IEquatable<T>, IHashable
```

The distinct elements of `first` that are also in `second`.

**Type parameters**

- `T` — the element type, which a `HashSet` must be able to hold

<sub>[stdlib/Collections/Combining.sl:230](../../stdlib/Collections/Combining.sl#L230)</sub>

### Intersect *function*

```
List<T> Intersect<T>(IEnumerable<T> first, IEnumerable<T> second)
    where T : IEquatable<T>, IHashable
```

The distinct elements of `first` that are also in `second`.

**Type parameters**

- `T` — the element type, which a `HashSet` must be able to hold

<sub>[stdlib/Collections/Combining.sl:477](../../stdlib/Collections/Combining.sl#L477)</sub>

### IntersectBy *function*

```
List<T> IntersectBy<T, TKey>(ReadOnlySpan<T> first, ReadOnlySpan<TKey> keys, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
```

The distinct elements of `first` whose key is among `keys`.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which a `HashSet` must be able to hold

<sub>[stdlib/Collections/Combining.sl:237](../../stdlib/Collections/Combining.sl#L237)</sub>

### IntersectBy *function*

```
List<T> IntersectBy<T, TKey>(IEnumerable<T> first, IEnumerable<TKey> keys, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
```

The distinct elements of `first` whose key is among `keys`.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which a `HashSet` must be able to hold

<sub>[stdlib/Collections/Combining.sl:484](../../stdlib/Collections/Combining.sl#L484)</sub>

### Last *function*

```
T Last<T>(ReadOnlySpan<T> items)
```

The last element, aborting when there is none.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:69](../../stdlib/Collections/Elements.sl#L69)</sub>

### Last *function*

```
T Last<T>(ReadOnlySpan<T> items, Predicate<T> test)
```

The last element the predicate accepts, aborting when there is none.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:79](../../stdlib/Collections/Elements.sl#L79)</sub>

### Last *function*

```
T Last<T>(IEnumerable<T> items)
```

The last element, aborting when there is none.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:218](../../stdlib/Collections/Elements.sl#L218)</sub>

### Last *function*

```
T Last<T>(IEnumerable<T> items, Predicate<T> test)
```

The last element the predicate accepts, aborting when there is none.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:223](../../stdlib/Collections/Elements.sl#L223)</sub>

### LastIndexOf *function*

```
Optional<nuint> LastIndexOf<T>(IReadOnlyList<T> items, T wanted)
    where T : IEquatable<T>
```

Where the *last* item equal to `wanted` is, if it is there at all.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

**See also** &nbsp; [Collections.IndexOf](#indexof-function)

<sub>[stdlib/Collections/Collections.sl:113](../../stdlib/Collections/Collections.sl#L113)</sub>

### LastIndexOf *function*

```
Optional<nuint> LastIndexOf<T>(ReadOnlySpan<T> span, T value)
    where T : IEquatable<T>
```

Where the last element equal to `value` is, if there is one.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

**See also** &nbsp; [Collections.IndexOf](#indexof-function)

<sub>[stdlib/Collections/Spans.sl:58](../../stdlib/Collections/Spans.sl#L58)</sub>

### LastIndexOf *function*

```
Optional<nuint> LastIndexOf<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> value)
    where T : IEquatable<T>
```

Where `value` last appears as a run of elements. An empty `value`
appears at the end.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

**See also** &nbsp; [Collections.IndexOf](#indexof-function)

<sub>[stdlib/Collections/Spans.sl:114](../../stdlib/Collections/Spans.sl#L114)</sub>

### LastIndexOfAny *function*

```
Optional<nuint> LastIndexOfAny<T>(ReadOnlySpan<T> span, T first, T second)
    where T : IEquatable<T>
```

Where the last element equal to either value is.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:256](../../stdlib/Collections/Spans.sl#L256)</sub>

### LastIndexOfAny *function*

```
Optional<nuint> LastIndexOfAny<T>(ReadOnlySpan<T> span, T first, T second, T third)
    where T : IEquatable<T>
```

Where the last element equal to any of the three is.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:263](../../stdlib/Collections/Spans.sl#L263)</sub>

### LastIndexOfAny *function*

```
Optional<nuint> LastIndexOfAny<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> values)
    where T : IEquatable<T>
```

Where the last element equal to any of `values` is.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:270](../../stdlib/Collections/Spans.sl#L270)</sub>

### LastIndexOfAnyExcept *function*

```
Optional<nuint> LastIndexOfAnyExcept<T>(ReadOnlySpan<T> span, T value)
    where T : IEquatable<T>
```

Where the last element other than `value` is.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:319](../../stdlib/Collections/Spans.sl#L319)</sub>

### LastIndexOfAnyExcept *function*

```
Optional<nuint> LastIndexOfAnyExcept<T>(ReadOnlySpan<T> span, T first, T second)
    where T : IEquatable<T>
```

Where the last element equal to neither value is.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:326](../../stdlib/Collections/Spans.sl#L326)</sub>

### LastIndexOfAnyExcept *function*

```
Optional<nuint> LastIndexOfAnyExcept<T>(ReadOnlySpan<T> span, T first, T second, T third)
    where T : IEquatable<T>
```

Where the last element equal to none of the three is.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:333](../../stdlib/Collections/Spans.sl#L333)</sub>

### LastIndexOfAnyExcept *function*

```
Optional<nuint> LastIndexOfAnyExcept<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> values)
    where T : IEquatable<T>
```

Where the last element equal to none of `values` is.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:340](../../stdlib/Collections/Spans.sl#L340)</sub>

### LastIndexOfAnyExceptInRange *function*

```
Optional<nuint> LastIndexOfAnyExceptInRange<T>(ReadOnlySpan<T> span, T low, T high)
    where T : IComparable<T>
```

Where the last element outside `low` to `high` is.

**Type parameters**

- `T` — the element type, which must order itself

<sub>[stdlib/Collections/Spans.sl:450](../../stdlib/Collections/Spans.sl#L450)</sub>

### LastIndexOfAnyInRange *function*

```
Optional<nuint> LastIndexOfAnyInRange<T>(ReadOnlySpan<T> span, T low, T high)
    where T : IComparable<T>
```

Where the last element between `low` and `high`, both included, is.

**Type parameters**

- `T` — the element type, which must order itself

<sub>[stdlib/Collections/Spans.sl:436](../../stdlib/Collections/Spans.sl#L436)</sub>

### LastOrDefault *function*

```
T LastOrDefault<T>(ReadOnlySpan<T> items, T fallback)
```

The last element, or `fallback` when there is none.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:92](../../stdlib/Collections/Elements.sl#L92)</sub>

### LastOrDefault *function*

```
T LastOrDefault<T>(ReadOnlySpan<T> items, Predicate<T> test, T fallback)
```

The last element the predicate accepts, or `fallback` when there is none.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:98](../../stdlib/Collections/Elements.sl#L98)</sub>

### LastOrDefault *function*

```
T LastOrDefault<T>(IEnumerable<T> items, T fallback)
```

The last element, or `fallback` when there is none.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:228](../../stdlib/Collections/Elements.sl#L228)</sub>

### LastOrDefault *function*

```
T LastOrDefault<T>(IEnumerable<T> items, Predicate<T> test, T fallback)
```

The last element the predicate accepts, or `fallback` when there is none.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:233](../../stdlib/Collections/Elements.sl#L233)</sub>

### Max *function*

```
T Max<T>(ReadOnlySpan<T> items)
    where T : IComparable<T>
```

The largest element, by its own ordering, aborting when there are none. The
first of equals wins.

**Type parameters**

- `T` — the element type, which must order itself

<sub>[stdlib/Collections/Aggregates.sl:528](../../stdlib/Collections/Aggregates.sl#L528)</sub>

### Max *function*

```
TResult Max<T, TResult>(ReadOnlySpan<T> items, Func<T, TResult> selector)
    where TResult : IComparable<TResult>
```

The largest of what `selector` gives for each element, aborting when there
are none.

**Type parameters**

- `T` — the element type; the selector reads the value off it
- `TResult` — what is compared, which must order itself

<sub>[stdlib/Collections/Aggregates.sl:547](../../stdlib/Collections/Aggregates.sl#L547)</sub>

### Max *function*

```
T Max<T>(IEnumerable<T> items)
    where T : IComparable<T>
```

The largest element, by its own ordering, aborting when there are none. The
first of equals wins.

**Type parameters**

- `T` — the element type, which must order itself

<sub>[stdlib/Collections/Aggregates.sl:661](../../stdlib/Collections/Aggregates.sl#L661)</sub>

### Max *function*

```
TResult Max<T, TResult>(IEnumerable<T> items, Func<T, TResult> selector)
    where TResult : IComparable<TResult>
```

The largest of what `selector` gives for each element, aborting when there
are none.

**Type parameters**

- `T` — the element type; the selector reads the value off it
- `TResult` — what is compared, which must order itself

<sub>[stdlib/Collections/Aggregates.sl:682](../../stdlib/Collections/Aggregates.sl#L682)</sub>

### Max *function*

```
T Max<T>(IReadOnlyList<T> items)
    where T : IComparable<T>
```

The largest item, by its own ordering. The list must not be empty.

**Type parameters**

- `T` — the element type, which must order itself

**See also** &nbsp; [Collections.Min](#min-function)

<sub>[stdlib/Collections/Collections.sl:45](../../stdlib/Collections/Collections.sl#L45)</sub>

### MaxBy *function*

```
Optional<T> MaxBy<T, TKey>(ReadOnlySpan<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey>
```

The element whose key is the largest, or none when there are no elements.
The first of equal keys wins.

**Type parameters**

- `T` — the element type; the key selector reads the key off it
- `TKey` — the key, which must order itself

<sub>[stdlib/Collections/Aggregates.sl:568](../../stdlib/Collections/Aggregates.sl#L568)</sub>

### MaxBy *function*

```
Optional<T> MaxBy<T, TKey>(IEnumerable<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey>
```

The element whose key is the largest, or none when there are no elements.
The first of equal keys wins.

**Type parameters**

- `T` — the element type; the key selector reads the key off it
- `TKey` — the key, which must order itself

<sub>[stdlib/Collections/Aggregates.sl:704](../../stdlib/Collections/Aggregates.sl#L704)</sub>

### Min *function*

```
T Min<T>(ReadOnlySpan<T> items)
    where T : IComparable<T>
```

The smallest element, by its own ordering, aborting when there are none. The
first of equals wins.

**Type parameters**

- `T` — the element type, which must order itself

<sub>[stdlib/Collections/Aggregates.sl:464](../../stdlib/Collections/Aggregates.sl#L464)</sub>

### Min *function*

```
TResult Min<T, TResult>(ReadOnlySpan<T> items, Func<T, TResult> selector)
    where TResult : IComparable<TResult>
```

The smallest of what `selector` gives for each element, aborting when there
are none.

**Type parameters**

- `T` — the element type; the selector reads the value off it
- `TResult` — what is compared, which must order itself

<sub>[stdlib/Collections/Aggregates.sl:483](../../stdlib/Collections/Aggregates.sl#L483)</sub>

### Min *function*

```
T Min<T>(IEnumerable<T> items)
    where T : IComparable<T>
```

The smallest element, by its own ordering, aborting when there are none. The
first of equals wins.

**Type parameters**

- `T` — the element type, which must order itself

<sub>[stdlib/Collections/Aggregates.sl:592](../../stdlib/Collections/Aggregates.sl#L592)</sub>

### Min *function*

```
TResult Min<T, TResult>(IEnumerable<T> items, Func<T, TResult> selector)
    where TResult : IComparable<TResult>
```

The smallest of what `selector` gives for each element, aborting when there
are none.

**Type parameters**

- `T` — the element type; the selector reads the value off it
- `TResult` — what is compared, which must order itself

<sub>[stdlib/Collections/Aggregates.sl:613](../../stdlib/Collections/Aggregates.sl#L613)</sub>

### Min *function*

```
T Min<T>(IReadOnlyList<T> items)
    where T : IComparable<T>
```

The smallest item, by its own ordering. The list must not be empty.

**Type parameters**

- `T` — the element type, which must order itself

**See also** &nbsp; [Collections.Max](#max-function)

<sub>[stdlib/Collections/Collections.sl:63](../../stdlib/Collections/Collections.sl#L63)</sub>

### MinBy *function*

```
Optional<T> MinBy<T, TKey>(ReadOnlySpan<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey>
```

The element whose key is the smallest, or none when there are no elements.
The first of equal keys wins.

**Type parameters**

- `T` — the element type; the key selector reads the key off it
- `TKey` — the key, which must order itself

<sub>[stdlib/Collections/Aggregates.sl:504](../../stdlib/Collections/Aggregates.sl#L504)</sub>

### MinBy *function*

```
Optional<T> MinBy<T, TKey>(IEnumerable<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey>
```

The element whose key is the smallest, or none when there are no elements.
The first of equal keys wins.

**Type parameters**

- `T` — the element type; the key selector reads the key off it
- `TKey` — the key, which must order itself

<sub>[stdlib/Collections/Aggregates.sl:635](../../stdlib/Collections/Aggregates.sl#L635)</sub>

### Order *function*

```
OrderedList<T> Order<T>(ReadOnlySpan<T> items)
    where T : IComparable<T>
```

The elements by their own ordering, smallest first, stably.

**Type parameters**

- `T` — the element type, which must order itself

<sub>[stdlib/Collections/OrderedList.sl:107](../../stdlib/Collections/OrderedList.sl#L107)</sub>

### Order *function*

```
OrderedList<T> Order<T>(IEnumerable<T> items)
    where T : IComparable<T>
```

The elements by their own ordering, smallest first, stably.

**Type parameters**

- `T` — the element type, which must order itself

<sub>[stdlib/Collections/OrderedList.sl:136](../../stdlib/Collections/OrderedList.sl#L136)</sub>

### OrderBy *function*

```
OrderedList<T> OrderBy<T>(ReadOnlySpan<T> items, Comparison<T> order)
```

The elements ordered by what `order` says, leaving the input alone.

`Sort` orders in place, which a chain cannot use: what is being chained
from is usually somebody else's array. This copies first, and is stable for
the reason `Sort` is.

**Type parameters**

- `T` — the element type; the comparer orders it, so nothing is asked of it

**See also** &nbsp; [Collections.Sort](#sort-function)

<sub>[stdlib/Collections/Functional.sl:457](../../stdlib/Collections/Functional.sl#L457)</sub>

### OrderBy *function*

```
OrderedList<T> OrderBy<T>(IEnumerable<T> items, Comparison<T> order)
```

The elements ordered by what `order` says, over any sequence, leaving the
input alone. Copies into an array first, so it costs one.

**Type parameters**

- `T` — the element type; the comparer orders it, so nothing is asked of it

**See also** &nbsp; [Collections.Sort](#sort-function)

<sub>[stdlib/Collections/Functional.sl:466](../../stdlib/Collections/Functional.sl#L466)</sub>

### OrderBy *function*

```
OrderedList<T> OrderBy<T, TKey>(ReadOnlySpan<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey>
```

The elements by the key `keySelector` gives, smallest first, stably.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which must order itself

**See also** &nbsp; [Collections.ThenBy](#thenby-function)

<sub>[stdlib/Collections/OrderedList.sl:92](../../stdlib/Collections/OrderedList.sl#L92)</sub>

### OrderBy *function*

```
OrderedList<T> OrderBy<T, TKey>(IEnumerable<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey>
```

The elements by the key `keySelector` gives, smallest first, stably.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which must order itself

**See also** &nbsp; [Collections.ThenBy](#thenby-function)

<sub>[stdlib/Collections/OrderedList.sl:121](../../stdlib/Collections/OrderedList.sl#L121)</sub>

### OrderByDescending *function*

```
OrderedList<T> OrderByDescending<T, TKey>(ReadOnlySpan<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey>
```

The elements by the key `keySelector` gives, largest first, stably.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which must order itself

<sub>[stdlib/Collections/OrderedList.sl:100](../../stdlib/Collections/OrderedList.sl#L100)</sub>

### OrderByDescending *function*

```
OrderedList<T> OrderByDescending<T, TKey>(IEnumerable<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey>
```

The elements by the key `keySelector` gives, largest first, stably.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which must order itself

<sub>[stdlib/Collections/OrderedList.sl:129](../../stdlib/Collections/OrderedList.sl#L129)</sub>

### OrderDescending *function*

```
OrderedList<T> OrderDescending<T>(ReadOnlySpan<T> items)
    where T : IComparable<T>
```

The elements by their own ordering, largest first, stably.

**Type parameters**

- `T` — the element type, which must order itself

<sub>[stdlib/Collections/OrderedList.sl:113](../../stdlib/Collections/OrderedList.sl#L113)</sub>

### OrderDescending *function*

```
OrderedList<T> OrderDescending<T>(IEnumerable<T> items)
    where T : IComparable<T>
```

The elements by their own ordering, largest first, stably.

**Type parameters**

- `T` — the element type, which must order itself

<sub>[stdlib/Collections/OrderedList.sl:142](../../stdlib/Collections/OrderedList.sl#L142)</sub>

### Prepend *function*

```
List<T> Prepend<T>(ReadOnlySpan<T> items, T element)
```

`element`, then the elements.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Combining.sl:60](../../stdlib/Collections/Combining.sl#L60)</sub>

### Prepend *function*

```
List<T> Prepend<T>(IEnumerable<T> items, T element)
```

`element`, then the elements.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Combining.sl:307](../../stdlib/Collections/Combining.sl#L307)</sub>

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

<sub>[stdlib/Collections/Collections.sl:134](../../stdlib/Collections/Collections.sl#L134)</sub>

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

<sub>[stdlib/Collections/Collections.sl:158](../../stdlib/Collections/Collections.sl#L158)</sub>

### Replace *function*

```
void Replace<T>(Span<T> span, T oldValue, T newValue)
    where T : IEquatable<T>
```

Replaces every element equal to `oldValue` with `newValue`, in place.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:479](../../stdlib/Collections/Spans.sl#L479)</sub>

### Replace *function*

```
void Replace<T>(ReadOnlySpan<T> source, Span<T> destination, T oldValue, T newValue)
    where T : IEquatable<T>
```

Copies `source` into the start of `destination` with every element equal
to `oldValue` replaced by `newValue`, aborting when `destination` is
shorter.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:493](../../stdlib/Collections/Spans.sl#L493)</sub>

### Reverse *function*

```
void Reverse<T>(Span<T> items)
```

Reverses part of an array in place.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [List.Reverse](#reverse-method)

<sub>[stdlib/Collections/Collections.sl:412](../../stdlib/Collections/Collections.sl#L412)</sub>

### Select *function*

```
List<TResult> Select<T, TResult>(ReadOnlySpan<T> items, Func<T, TResult> transform)
```

Every element put through the transform.

    var spelled = Select(numbers, n => Text.FromInteger((long)n));

`R` appears nowhere but in the transform's result, so working it out means
binding the lambda's body -- which cannot happen until `T` has given the
lambda its parameter type. The compiler does the two in that order.

**Type parameters**

- `T` — the element type, which settles the transform's parameter
- `TResult` — what the transform answers, and so what the result holds

**See also** &nbsp; [Collections.Where](#where-function)

<sub>[stdlib/Collections/Functional.sl:78](../../stdlib/Collections/Functional.sl#L78)</sub>

### Select *function*

```
List<TResult> Select<T, TResult>(IEnumerable<T> items, Func<T, TResult> transform)
```

Every element put through the transform, over any sequence.

**Type parameters**

- `T` — the element type, which settles the transform's parameter
- `TResult` — what the transform answers, and so what the result holds

**See also** &nbsp; [Collections.Where](#where-function)

<sub>[stdlib/Collections/Functional.sl:261](../../stdlib/Collections/Functional.sl#L261)</sub>

### SelectMany *function*

```
List<TResult> SelectMany<T, TResult>(ReadOnlySpan<T> items, Func<T, IEnumerable<TResult>> select)
```

Every element of what `select` makes of each element, one after another.

**Type parameters**

- `T` — the element type
- `TResult` — the element type of what `select` makes

<sub>[stdlib/Collections/Combining.sl:171](../../stdlib/Collections/Combining.sl#L171)</sub>

### SelectMany *function*

```
List<TResult> SelectMany<T, TResult>(IEnumerable<T> items, Func<T, IEnumerable<TResult>> select)
```

Every element of what `select` makes of each element, one after another.

**Type parameters**

- `T` — the element type
- `TResult` — the element type of what `select` makes

<sub>[stdlib/Collections/Combining.sl:418](../../stdlib/Collections/Combining.sl#L418)</sub>

### SequenceCompareTo *function*

```
int SequenceCompareTo<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> other)
    where T : IComparable<T>
```

How the two order element by element: negative when `span` comes first,
zero when they are equal, positive when `other` does. A span that runs out
first comes first.

**Type parameters**

- `T` — the element type, which must order itself

<sub>[stdlib/Collections/Spans.sl:168](../../stdlib/Collections/Spans.sl#L168)</sub>

### SequenceEqual *function*

```
bool SequenceEqual<T>(IEnumerable<T> first, IEnumerable<T> second)
    where T : IEquatable<T>
```

Whether the two hold equal elements in the same order.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Elements.sl:328](../../stdlib/Collections/Elements.sl#L328)</sub>

### SequenceEqual *function*

```
bool SequenceEqual<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> other)
    where T : IEquatable<T>
```

Whether the two hold equal elements in the same order.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:150](../../stdlib/Collections/Spans.sl#L150)</sub>

### Single *function*

```
T Single<T>(ReadOnlySpan<T> items)
```

The only element, aborting when there is not exactly one.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:111](../../stdlib/Collections/Elements.sl#L111)</sub>

### Single *function*

```
T Single<T>(ReadOnlySpan<T> items, Predicate<T> test)
```

The only element the predicate accepts, aborting when there is not
exactly one.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:122](../../stdlib/Collections/Elements.sl#L122)</sub>

### Single *function*

```
T Single<T>(IEnumerable<T> items)
```

The only element, aborting when there is not exactly one.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:239](../../stdlib/Collections/Elements.sl#L239)</sub>

### Single *function*

```
T Single<T>(IEnumerable<T> items, Predicate<T> test)
```

The only element the predicate accepts, aborting when there is not
exactly one.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:245](../../stdlib/Collections/Elements.sl#L245)</sub>

### SingleOrDefault *function*

```
T SingleOrDefault<T>(ReadOnlySpan<T> items, T fallback)
```

The only element, `fallback` when there is none, and an abort when there
is more than one.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:133](../../stdlib/Collections/Elements.sl#L133)</sub>

### SingleOrDefault *function*

```
T SingleOrDefault<T>(ReadOnlySpan<T> items, Predicate<T> test, T fallback)
```

The only element the predicate accepts, `fallback` when there is none,
and an abort when there is more than one.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:144](../../stdlib/Collections/Elements.sl#L144)</sub>

### SingleOrDefault *function*

```
T SingleOrDefault<T>(IEnumerable<T> items, T fallback)
```

The only element, `fallback` when there is none, and an abort when there
is more than one.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:251](../../stdlib/Collections/Elements.sl#L251)</sub>

### SingleOrDefault *function*

```
T SingleOrDefault<T>(IEnumerable<T> items, Predicate<T> test, T fallback)
```

The only element the predicate accepts, `fallback` when there is none,
and an abort when there is more than one.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Elements.sl:258](../../stdlib/Collections/Elements.sl#L258)</sub>

### Skip *function*

```
List<T> Skip<T>(ReadOnlySpan<T> items, nuint count)
```

Everything after the first `count` elements, or nothing if there are fewer.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Take](#take-function)

<sub>[stdlib/Collections/Functional.sl:228](../../stdlib/Collections/Functional.sl#L228)</sub>

### Skip *function*

```
List<T> Skip<T>(IEnumerable<T> items, nuint count)
```

Everything after the first `count`.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Take](#take-function)

<sub>[stdlib/Collections/Functional.sl:489](../../stdlib/Collections/Functional.sl#L489)</sub>

### SkipLast *function*

```
List<T> SkipLast<T>(ReadOnlySpan<T> items, nuint count)
```

All but the last `count` elements, or nothing if there are fewer.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Combining.sl:160](../../stdlib/Collections/Combining.sl#L160)</sub>

### SkipLast *function*

```
List<T> SkipLast<T>(IEnumerable<T> items, nuint count)
```

All but the last `count` elements, or nothing if there are fewer.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Combining.sl:407](../../stdlib/Collections/Combining.sl#L407)</sub>

### SkipWhile *function*

```
List<T> SkipWhile<T>(ReadOnlySpan<T> items, Predicate<T> skip)
```

The elements from the first the predicate refuses.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Combining.sl:133](../../stdlib/Collections/Combining.sl#L133)</sub>

### SkipWhile *function*

```
List<T> SkipWhile<T>(IEnumerable<T> items, Predicate<T> skip)
```

The elements from the first the predicate refuses.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Combining.sl:380](../../stdlib/Collections/Combining.sl#L380)</sub>

### Sort *function*

```
void Sort<T>(Span<T> items)
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

<sub>[stdlib/Collections/Collections.sl:196](../../stdlib/Collections/Collections.sl#L196)</sub>

### Sort *function*

```
void Sort<T>(Span<T> items, Comparison<T> order)
```

The same, ordered by a comparer rather than by the type itself.

This is the overload that sorts descending, sorts by a field, or sorts a
type that implements nothing at all:

    Sort(people, (a, b) => a.Age - b.Age);

**Type parameters**

- `T` — the element type; the comparer orders it, so nothing is asked of it

**See also** &nbsp; [Collections.OrderBy](#orderby-function)

<sub>[stdlib/Collections/Collections.sl:280](../../stdlib/Collections/Collections.sl#L280)</sub>

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

<sub>[stdlib/Collections/Collections.sl:438](../../stdlib/Collections/Collections.sl#L438)</sub>

### Sort *function*

```
void Sort<T>(IList<T> items, Comparison<T> order)
```

The same, ordered by a comparer.

**Type parameters**

- `T` — the element type; the comparer orders it, so nothing is asked of it

<sub>[stdlib/Collections/Collections.sl:456](../../stdlib/Collections/Collections.sl#L456)</sub>

### Sort *function*

```
void Sort<TKey, TValue>(Span<TKey> keys, Span<TValue> items)
    where TKey : IComparable<TKey>
```

Orders `keys` in place, smallest first, and moves each element of `items`
to where its key went. The two MUST be the same length.

**Type parameters**

- `TKey` — the key type, which must order itself
- `TValue` — the item type; nothing is asked of it

<sub>[stdlib/Collections/Spans.sl:506](../../stdlib/Collections/Spans.sl#L506)</sub>

### Sort *function*

```
void Sort<TKey, TValue>(Span<TKey> keys, Span<TValue> items, Comparison<TKey> order)
```

Orders `keys` in place by `order` and moves each element of `items` to
where its key went. Stable. The two MUST be the same length.

**Type parameters**

- `TKey` — the key type
- `TValue` — the item type; nothing is asked of it

<sub>[stdlib/Collections/Spans.sl:514](../../stdlib/Collections/Spans.sl#L514)</sub>

### StartsWith *function*

```
bool StartsWith<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> value)
    where T : IEquatable<T>
```

Whether `span` begins with the elements of `value`.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:187](../../stdlib/Collections/Spans.sl#L187)</sub>

### StartsWith *function*

```
bool StartsWith<T>(ReadOnlySpan<T> span, T value)
    where T : IEquatable<T>
```

Whether the first element equals `value`.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:193](../../stdlib/Collections/Spans.sl#L193)</sub>

### Sum *function*

```
int Sum(ReadOnlySpan<int> items)
```

The total of the elements; zero when there are none.

<sub>[stdlib/Collections/Aggregates.sl:35](../../stdlib/Collections/Aggregates.sl#L35)</sub>

### Sum *function*

```
int Sum<T>(ReadOnlySpan<T> items, Func<T, int> selector)
```

The total of what `selector` gives for each element; zero when there are none.

**Type parameters**

- `T` — the element type; the selector reads the number off it

<sub>[stdlib/Collections/Aggregates.sl:46](../../stdlib/Collections/Aggregates.sl#L46)</sub>

### Sum *function*

```
int Sum(IEnumerable<int> items)
```

The total of the elements; zero when there are none.

<sub>[stdlib/Collections/Aggregates.sl:88](../../stdlib/Collections/Aggregates.sl#L88)</sub>

### Sum *function*

```
int Sum<T>(IEnumerable<T> items, Func<T, int> selector)
```

The total of what `selector` gives for each element; zero when there are none.

**Type parameters**

- `T` — the element type; the selector reads the number off it

<sub>[stdlib/Collections/Aggregates.sl:99](../../stdlib/Collections/Aggregates.sl#L99)</sub>

### Sum *function*

```
long Sum(ReadOnlySpan<long> items)
```

The total of the elements; zero when there are none.

<sub>[stdlib/Collections/Aggregates.sl:141](../../stdlib/Collections/Aggregates.sl#L141)</sub>

### Sum *function*

```
long Sum<T>(ReadOnlySpan<T> items, Func<T, long> selector)
```

The total of what `selector` gives for each element; zero when there are none.

**Type parameters**

- `T` — the element type; the selector reads the number off it

<sub>[stdlib/Collections/Aggregates.sl:152](../../stdlib/Collections/Aggregates.sl#L152)</sub>

### Sum *function*

```
long Sum(IEnumerable<long> items)
```

The total of the elements; zero when there are none.

<sub>[stdlib/Collections/Aggregates.sl:194](../../stdlib/Collections/Aggregates.sl#L194)</sub>

### Sum *function*

```
long Sum<T>(IEnumerable<T> items, Func<T, long> selector)
```

The total of what `selector` gives for each element; zero when there are none.

**Type parameters**

- `T` — the element type; the selector reads the number off it

<sub>[stdlib/Collections/Aggregates.sl:205](../../stdlib/Collections/Aggregates.sl#L205)</sub>

### Sum *function*

```
float Sum(ReadOnlySpan<float> items)
```

The total of the elements; zero when there are none.

<sub>[stdlib/Collections/Aggregates.sl:247](../../stdlib/Collections/Aggregates.sl#L247)</sub>

### Sum *function*

```
float Sum<T>(ReadOnlySpan<T> items, Func<T, float> selector)
```

The total of what `selector` gives for each element; zero when there are none.

**Type parameters**

- `T` — the element type; the selector reads the number off it

<sub>[stdlib/Collections/Aggregates.sl:258](../../stdlib/Collections/Aggregates.sl#L258)</sub>

### Sum *function*

```
float Sum(IEnumerable<float> items)
```

The total of the elements; zero when there are none.

<sub>[stdlib/Collections/Aggregates.sl:300](../../stdlib/Collections/Aggregates.sl#L300)</sub>

### Sum *function*

```
float Sum<T>(IEnumerable<T> items, Func<T, float> selector)
```

The total of what `selector` gives for each element; zero when there are none.

**Type parameters**

- `T` — the element type; the selector reads the number off it

<sub>[stdlib/Collections/Aggregates.sl:311](../../stdlib/Collections/Aggregates.sl#L311)</sub>

### Sum *function*

```
double Sum(ReadOnlySpan<double> items)
```

The total of the elements; zero when there are none.

<sub>[stdlib/Collections/Aggregates.sl:353](../../stdlib/Collections/Aggregates.sl#L353)</sub>

### Sum *function*

```
double Sum<T>(ReadOnlySpan<T> items, Func<T, double> selector)
```

The total of what `selector` gives for each element; zero when there are none.

**Type parameters**

- `T` — the element type; the selector reads the number off it

<sub>[stdlib/Collections/Aggregates.sl:364](../../stdlib/Collections/Aggregates.sl#L364)</sub>

### Sum *function*

```
double Sum(IEnumerable<double> items)
```

The total of the elements; zero when there are none.

<sub>[stdlib/Collections/Aggregates.sl:406](../../stdlib/Collections/Aggregates.sl#L406)</sub>

### Sum *function*

```
double Sum<T>(IEnumerable<T> items, Func<T, double> selector)
```

The total of what `selector` gives for each element; zero when there are none.

**Type parameters**

- `T` — the element type; the selector reads the number off it

<sub>[stdlib/Collections/Aggregates.sl:417](../../stdlib/Collections/Aggregates.sl#L417)</sub>

### Take *function*

```
List<T> Take<T>(ReadOnlySpan<T> items, nuint count)
```

The first `count` elements, or all of them if there are fewer.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Skip](#skip-function)

<sub>[stdlib/Collections/Functional.sl:215](../../stdlib/Collections/Functional.sl#L215)</sub>

### Take *function*

```
List<T> Take<T>(IEnumerable<T> items, nuint count)
```

The first `count` elements, or all of them if there are fewer.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.Skip](#skip-function)

<sub>[stdlib/Collections/Functional.sl:473](../../stdlib/Collections/Functional.sl#L473)</sub>

### TakeLast *function*

```
List<T> TakeLast<T>(ReadOnlySpan<T> items, nuint count)
```

The last `count` elements, or all of them if there are fewer.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Combining.sl:150](../../stdlib/Collections/Combining.sl#L150)</sub>

### TakeLast *function*

```
List<T> TakeLast<T>(IEnumerable<T> items, nuint count)
```

The last `count` elements, or all of them if there are fewer.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Combining.sl:397](../../stdlib/Collections/Combining.sl#L397)</sub>

### TakeWhile *function*

```
List<T> TakeWhile<T>(ReadOnlySpan<T> items, Predicate<T> keep)
```

The elements up to the first the predicate refuses.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Combining.sl:118](../../stdlib/Collections/Combining.sl#L118)</sub>

### TakeWhile *function*

```
List<T> TakeWhile<T>(IEnumerable<T> items, Predicate<T> keep)
```

The elements up to the first the predicate refuses.

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Collections/Combining.sl:365](../../stdlib/Collections/Combining.sl#L365)</sub>

### ThenBy *function*

```
OrderedList<T> ThenBy<T, TKey>(OrderedList<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey>
```

The elements of an ordered list, ties broken by the key `keySelector`
gives, smallest first.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which must order itself

<sub>[stdlib/Collections/OrderedList.sl:68](../../stdlib/Collections/OrderedList.sl#L68)</sub>

### ThenBy *function*

```
OrderedList<T> ThenBy<T>(OrderedList<T> items, Comparison<T> order)
```

The elements of an ordered list, ties broken by `order`.

**Type parameters**

- `T` — the element type; the comparison orders it

<sub>[stdlib/Collections/OrderedList.sl:84](../../stdlib/Collections/OrderedList.sl#L84)</sub>

### ThenByDescending *function*

```
OrderedList<T> ThenByDescending<T, TKey>(OrderedList<T> items, Func<T, TKey> keySelector)
    where TKey : IComparable<TKey>
```

The elements of an ordered list, ties broken by the key `keySelector`
gives, largest first.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which must order itself

<sub>[stdlib/Collections/OrderedList.sl:77](../../stdlib/Collections/OrderedList.sl#L77)</sub>

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

<sub>[stdlib/Collections/Functional.sl:397](../../stdlib/Collections/Functional.sl#L397)</sub>

### ToArray *function*

```
T[] ToArray<T>(ReadOnlySpan<T> items)
```

The same for a slice, which is not an `IEnumerable` and so does not collide.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.ToList](#tolist-function)

<sub>[stdlib/Collections/Functional.sl:407](../../stdlib/Collections/Functional.sl#L407)</sub>

### ToDictionary *function*

```
Dictionary<TKey, T> ToDictionary<T, TKey>(ReadOnlySpan<T> items, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
```

A dictionary from the key `keySelector` gives each element to the element,
aborting on a key given twice.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which a `Dictionary` must be able to hold

<sub>[stdlib/Collections/Grouping.sl:100](../../stdlib/Collections/Grouping.sl#L100)</sub>

### ToDictionary *function*

```
Dictionary<TKey, TValue> ToDictionary<T, TKey, TValue>(ReadOnlySpan<T> items, Func<T, TKey> keySelector, Func<T, TValue> valueSelector)
    where TKey : IEquatable<TKey>, IHashable
```

A dictionary from the key `keySelector` gives each element to what
`valueSelector` makes of it, aborting on a key given twice.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which a `Dictionary` must be able to hold
- `TValue` — the value

<sub>[stdlib/Collections/Grouping.sl:110](../../stdlib/Collections/Grouping.sl#L110)</sub>

### ToDictionary *function*

```
Dictionary<TKey, T> ToDictionary<T, TKey>(IEnumerable<T> items, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
```

A dictionary from the key `keySelector` gives each element to the element,
aborting on a key given twice.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which a `Dictionary` must be able to hold

<sub>[stdlib/Collections/Grouping.sl:176](../../stdlib/Collections/Grouping.sl#L176)</sub>

### ToDictionary *function*

```
Dictionary<TKey, TValue> ToDictionary<T, TKey, TValue>(IEnumerable<T> items, Func<T, TKey> keySelector, Func<T, TValue> valueSelector)
    where TKey : IEquatable<TKey>, IHashable
```

A dictionary from the key `keySelector` gives each element to what
`valueSelector` makes of it, aborting on a key given twice.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which a `Dictionary` must be able to hold
- `TValue` — the value

<sub>[stdlib/Collections/Grouping.sl:186](../../stdlib/Collections/Grouping.sl#L186)</sub>

### ToHashSet *function*

```
HashSet<T> ToHashSet<T>(ReadOnlySpan<T> items)
    where T : IEquatable<T>, IHashable
```

The distinct elements, as a set.

**Type parameters**

- `T` — the element type, which a `HashSet` must be able to hold

<sub>[stdlib/Collections/Grouping.sl:126](../../stdlib/Collections/Grouping.sl#L126)</sub>

### ToHashSet *function*

```
HashSet<T> ToHashSet<T>(IEnumerable<T> items)
    where T : IEquatable<T>, IHashable
```

The distinct elements, as a set.

**Type parameters**

- `T` — the element type, which a `HashSet` must be able to hold

<sub>[stdlib/Collections/Grouping.sl:202](../../stdlib/Collections/Grouping.sl#L202)</sub>

### ToList *function*

```
List<T> ToList<T>(IEnumerable<T> items)
```

Everything in the sequence, as a list. The one that makes a `Queue` or a
`HashSet` usable with the array overloads above.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.ToArray](#toarray-function)

<sub>[stdlib/Collections/Functional.sl:360](../../stdlib/Collections/Functional.sl#L360)</sub>

### ToList *function*

```
List<T> ToList<T>(ReadOnlySpan<T> items)
```

And a slice, which an array converts to. Not an overload of the above by
accident: a slice is not an `IEnumerable`, so nothing is ever both.

**Type parameters**

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Collections.ToArray](#toarray-function)

<sub>[stdlib/Collections/Functional.sl:373](../../stdlib/Collections/Functional.sl#L373)</sub>

### Trim *function*

```
ReadOnlySpan<T> Trim<T>(ReadOnlySpan<T> span, T value)
    where T : IEquatable<T>
```

Without the elements equal to `value` at either end.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:564](../../stdlib/Collections/Spans.sl#L564)</sub>

### Trim *function*

```
ReadOnlySpan<T> Trim<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> trimElements)
    where T : IEquatable<T>
```

Without the elements equal to any of `trimElements` at either end.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:570](../../stdlib/Collections/Spans.sl#L570)</sub>

### Trim *function*

```
Span<T> Trim<T>(Span<T> span, T value)
    where T : IEquatable<T>
```

Without the elements equal to `value` at either end, still writable.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:612](../../stdlib/Collections/Spans.sl#L612)</sub>

### Trim *function*

```
Span<T> Trim<T>(Span<T> span, ReadOnlySpan<T> trimElements)
    where T : IEquatable<T>
```

Without the elements equal to any of `trimElements` at either end, still
writable.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:618](../../stdlib/Collections/Spans.sl#L618)</sub>

### TrimEnd *function*

```
ReadOnlySpan<T> TrimEnd<T>(ReadOnlySpan<T> span, T value)
    where T : IEquatable<T>
```

Without the elements equal to `value` at the end.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:596](../../stdlib/Collections/Spans.sl#L596)</sub>

### TrimEnd *function*

```
ReadOnlySpan<T> TrimEnd<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> trimElements)
    where T : IEquatable<T>
```

Without the elements equal to any of `trimElements` at the end.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:602](../../stdlib/Collections/Spans.sl#L602)</sub>

### TrimEnd *function*

```
Span<T> TrimEnd<T>(Span<T> span, T value)
    where T : IEquatable<T>
```

Without the elements equal to `value` at the end, still writable.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:643](../../stdlib/Collections/Spans.sl#L643)</sub>

### TrimEnd *function*

```
Span<T> TrimEnd<T>(Span<T> span, ReadOnlySpan<T> trimElements)
    where T : IEquatable<T>
```

Without the elements equal to any of `trimElements` at the end, still
writable.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:649](../../stdlib/Collections/Spans.sl#L649)</sub>

### TrimStart *function*

```
ReadOnlySpan<T> TrimStart<T>(ReadOnlySpan<T> span, T value)
    where T : IEquatable<T>
```

Without the elements equal to `value` at the start.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:580](../../stdlib/Collections/Spans.sl#L580)</sub>

### TrimStart *function*

```
ReadOnlySpan<T> TrimStart<T>(ReadOnlySpan<T> span, ReadOnlySpan<T> trimElements)
    where T : IEquatable<T>
```

Without the elements equal to any of `trimElements` at the start.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:586](../../stdlib/Collections/Spans.sl#L586)</sub>

### TrimStart *function*

```
Span<T> TrimStart<T>(Span<T> span, T value)
    where T : IEquatable<T>
```

Without the elements equal to `value` at the start, still writable.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:627](../../stdlib/Collections/Spans.sl#L627)</sub>

### TrimStart *function*

```
Span<T> TrimStart<T>(Span<T> span, ReadOnlySpan<T> trimElements)
    where T : IEquatable<T>
```

Without the elements equal to any of `trimElements` at the start, still
writable.

**Type parameters**

- `T` — the element type, which must answer whether it equals another

<sub>[stdlib/Collections/Spans.sl:634](../../stdlib/Collections/Spans.sl#L634)</sub>

### Union *function*

```
List<T> Union<T>(ReadOnlySpan<T> first, ReadOnlySpan<T> second)
    where T : IEquatable<T>, IHashable
```

The distinct elements of both, first's first.

**Type parameters**

- `T` — the element type, which a `HashSet` must be able to hold

<sub>[stdlib/Collections/Combining.sl:202](../../stdlib/Collections/Combining.sl#L202)</sub>

### Union *function*

```
List<T> Union<T>(IEnumerable<T> first, IEnumerable<T> second)
    where T : IEquatable<T>, IHashable
```

The distinct elements of both, first's first.

**Type parameters**

- `T` — the element type, which a `HashSet` must be able to hold

<sub>[stdlib/Collections/Combining.sl:449](../../stdlib/Collections/Combining.sl#L449)</sub>

### UnionBy *function*

```
List<T> UnionBy<T, TKey>(ReadOnlySpan<T> first, ReadOnlySpan<T> second, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
```

The distinct elements of both, by key, first's first.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which a `HashSet` must be able to hold

<sub>[stdlib/Collections/Combining.sl:209](../../stdlib/Collections/Combining.sl#L209)</sub>

### UnionBy *function*

```
List<T> UnionBy<T, TKey>(IEnumerable<T> first, IEnumerable<T> second, Func<T, TKey> keySelector)
    where TKey : IEquatable<TKey>, IHashable
```

The distinct elements of both, by key, first's first.

**Type parameters**

- `T` — the element type; nothing is asked of it
- `TKey` — the key, which a `HashSet` must be able to hold

<sub>[stdlib/Collections/Combining.sl:456](../../stdlib/Collections/Combining.sl#L456)</sub>

### Where *function*

```
List<T> Where<T>(ReadOnlySpan<T> items, Predicate<T> keep)
```

The elements the predicate keeps, in the order they were in.

An array converts to a slice of the whole of itself, so this takes both.

**Type parameters**

- `T` — the element type; the predicate does the deciding, so nothing is asked of it

**See also** &nbsp; [Collections.Select](#select-function) &middot; [Collections.Count](#count-function)

<sub>[stdlib/Collections/Functional.sl:56](../../stdlib/Collections/Functional.sl#L56)</sub>

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

<sub>[stdlib/Collections/Functional.sl:245](../../stdlib/Collections/Functional.sl#L245)</sub>

### Zip *function*

```
List<(TFirst, TSecond)> Zip<TFirst, TSecond>(ReadOnlySpan<TFirst> first, ReadOnlySpan<TSecond> second)
```

Pairs of elements at the same position, as long as the shorter lasts.

**Type parameters**

- `TFirst` — the first sequence's element type
- `TSecond` — the second's

<sub>[stdlib/Collections/Combining.sl:73](../../stdlib/Collections/Combining.sl#L73)</sub>

### Zip *function*

```
List<TResult> Zip<TFirst, TSecond, TResult>(ReadOnlySpan<TFirst> first, ReadOnlySpan<TSecond> second, Func<TFirst, TSecond, TResult> combine)
```

What `combine` makes of the elements at each position, as long as the
shorter lasts.

**Type parameters**

- `TFirst` — the first sequence's element type
- `TSecond` — the second's
- `TResult` — what `combine` makes

<sub>[stdlib/Collections/Combining.sl:82](../../stdlib/Collections/Combining.sl#L82)</sub>

### Zip *function*

```
List<(TFirst, TSecond)> Zip<TFirst, TSecond>(IEnumerable<TFirst> first, IEnumerable<TSecond> second)
```

Pairs of elements at the same position, as long as the shorter lasts.

**Type parameters**

- `TFirst` — the first sequence's element type
- `TSecond` — the second's

<sub>[stdlib/Collections/Combining.sl:320](../../stdlib/Collections/Combining.sl#L320)</sub>

### Zip *function*

```
List<TResult> Zip<TFirst, TSecond, TResult>(IEnumerable<TFirst> first, IEnumerable<TSecond> second, Func<TFirst, TSecond, TResult> combine)
```

What `combine` makes of the elements at each position, as long as the
shorter lasts.

**Type parameters**

- `TFirst` — the first sequence's element type
- `TSecond` — the second's
- `TResult` — what `combine` makes

<sub>[stdlib/Collections/Combining.sl:329](../../stdlib/Collections/Combining.sl#L329)</sub>

