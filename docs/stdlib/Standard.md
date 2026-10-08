# Standard

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

The language's own vocabulary: the markers and types that are rules rather
than library features, and so need no import to reach.

## Contents

**Types** &nbsp; [Action](#action-closure) &middot; [Action&lt;T1, T2, T3, T4&gt;](#actiont1-t2-t3-t4-closure) &middot; [Action&lt;T1, T2, T3&gt;](#actiont1-t2-t3-closure) &middot; [Action&lt;T1, T2&gt;](#actiont1-t2-closure) &middot; [Action&lt;T&gt;](#actiont-closure) &middot; [Array](#array-class) &middot; [Buffer](#buffer-class) &middot; [Comparison&lt;T&gt;](#comparisont-closure) &middot; [Fold&lt;TAccumulate, TSource&gt;](#foldtaccumulate-tsource-closure) &middot; [ForeignException](#foreignexception-class) &middot; [ForeignExceptionKind](#foreignexceptionkind-enum) &middot; [Func&lt;T, TResult&gt;](#funct-tresult-closure) &middot; [Func&lt;T1, T2, T3, T4, TResult&gt;](#funct1-t2-t3-t4-tresult-closure) &middot; [Func&lt;T1, T2, T3, TResult&gt;](#funct1-t2-t3-tresult-closure) &middot; [Func&lt;T1, T2, TResult&gt;](#funct1-t2-tresult-closure) &middot; [Func&lt;TResult&gt;](#functresult-closure) &middot; [Guid](#guid-struct) &middot; [IDisposable](#idisposable-interface) &middot; [Index](#index-struct) &middot; [Lazy&lt;T&gt;](#lazyt-class) &middot; [LazyThreadSafetyMode](#lazythreadsafetymode-enum) &middot; [Optional&lt;T&gt;](#optionalt-variant) &middot; [ParseError](#parseerror-enum) &middot; [Predicate&lt;T&gt;](#predicatet-closure) &middot; [Range](#range-struct) &middot; [ReadOnlySpan&lt;T&gt;](#readonlyspant-struct) &middot; [Result&lt;T, TError&gt;](#resultt-terror-variant) &middot; [RuntimeHelpers](#runtimehelpers-class) &middot; [Slot&lt;T&gt;](#slott-struct) &middot; [Span&lt;T&gt;](#spant-struct) &middot; [Uri](#uri-class) &middot; [UriKind](#urikind-enum) &middot; [UriPartial](#uripartial-enum) &middot; [Version](#version-struct)

## Types

### Action *closure*

```
closure void Action()
```

Does something and returns nothing.

<sub>[stdlib/Standard/Standard.sl:80](../../stdlib/Standard/Standard.sl#L80)</sub>

### Action&lt;T1, T2, T3, T4&gt; *closure*

```
closure void Action<in T1, in T2, in T3, in T4>(T1 arg1, T2 arg2, T3 arg3, T4 arg4)
```

Does something with four values and returns nothing.

**Type parameters**

- `T1` -- the first thing handed to it
- `T2` -- the second
- `T3` -- the third
- `T4` -- the fourth

<sub>[stdlib/Standard/Standard.sl:101](../../stdlib/Standard/Standard.sl#L101)</sub>

### Action&lt;T1, T2, T3&gt; *closure*

```
closure void Action<in T1, in T2, in T3>(T1 arg1, T2 arg2, T3 arg3)
```

Does something with three values and returns nothing.

**Type parameters**

- `T1` -- the first thing handed to it
- `T2` -- the second
- `T3` -- the third

<sub>[stdlib/Standard/Standard.sl:93](../../stdlib/Standard/Standard.sl#L93)</sub>

### Action&lt;T1, T2&gt; *closure*

```
closure void Action<in T1, in T2>(T1 arg1, T2 arg2)
```

Does something with two values and returns nothing.

**Type parameters**

- `T1` -- the first thing handed to it
- `T2` -- the second

<sub>[stdlib/Standard/Standard.sl:86](../../stdlib/Standard/Standard.sl#L86)</sub>

### Action&lt;T&gt; *closure*

```
closure void Action<in T>(T value)
```

Does something with a T and returns nothing.

**Type parameters**

- `T` -- what is handed to it

<sub>[stdlib/Standard/Standard.sl:77](../../stdlib/Standard/Standard.sl#L77)</sub>

### Array *class*

```
class Array
```

Making, copying, searching and ordering arrays. C#'s `System.Array`.

    String[] names = Array.Create(count, (i) => $"item {i}");
    int[] zeros = Array.Repeat(0, 16);
    Array.Sort(names);

`new T[n]` starts every element as the zero of `T`, and a `T` holding a
reference that is never null has no zero (section 2.16). `Create` and
`Repeat` are what such an array is made with instead; an array literal,
`[a, b, c]`, is the other way, and a `List<T>` and its `ToArray` the way for
a count not known in advance.

**Where .NET differs.** Indices and counts are `nuint`. A search answers
with an `Optional` rather than -1, and `BinarySearch` rather than a negative
complement. `Sort` is stable. A range that runs past the array aborts, as an
index out of range does. `Clear` and the growing `Resize` need a `T` with a
zero value, and are absent for any other.

Most of these are the span functions of `Standard.Collections` under
.NET's names: an array converts to a span, so `Sort(numbers)` and
`Array.Sort(numbers)` are the same call.

<sub>[stdlib/Standard/Array.sl:47](../../stdlib/Standard/Array.sl#L47)</sub>

#### Create *method*

```
static T[] Create<T>(nuint count, Func<nuint, T> make)
```

`count` elements, the element at `i` being `make(i)`, called in order
from zero. No element is ever seen before it has its value.

**Parameters**

- `count` -- how many elements
- `make` -- the element at an index

**Type parameters**

- `T` -- the element type; nothing is asked of it

**Returns** &nbsp; the array

<sub>[stdlib/Standard/Array.sl:58](../../stdlib/Standard/Array.sl#L58)</sub>

#### Repeat *method*

```
static T[] Repeat<T>(T value, nuint count)
```

`count` copies of `value`.

**Parameters**

- `value` -- what each element is
- `count` -- how many elements

**Type parameters**

- `T` -- the element type; nothing is asked of it

**Returns** &nbsp; the array

<sub>[stdlib/Standard/Array.sl:66](../../stdlib/Standard/Array.sl#L66)</sub>

#### Empty *method*

```
static T[] Empty<T>()
```

An array of no elements. A new one each call: there is no per-type
static to cache it in, and it costs one small allocation.

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:72](../../stdlib/Standard/Array.sl#L72)</sub>

#### AsReadOnly *method*

```
static ReadOnlySpan<T> AsReadOnly<T>(T[] array)
```

The array as a view that cannot be written through. .NET answers with a
`ReadOnlyCollection<T>`; a `ReadOnlySpan<T>` holds the array it views,
so it may be stored and returned the same way.

**Parameters**

- `array` -- the array to view

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:80](../../stdlib/Standard/Array.sl#L80)</sub>

#### ConvertAll *method*

```
static TOutput[] ConvertAll<TInput, TOutput>(TInput[] array, Func<TInput, TOutput> converter)
```

A new array of each element of `array` passed through `converter`.

**Parameters**

- `array` -- the elements to convert
- `converter` -- what each element becomes

**Type parameters**

- `TInput` -- the element type of `array`
- `TOutput` -- the element type of the result

**Returns** &nbsp; the array, as long as `array`

<sub>[stdlib/Standard/Array.sl:89](../../stdlib/Standard/Array.sl#L89)</sub>

#### Resize *method*

```
static void Resize<T>(ref T[] array, nuint newSize)
    where T : zeroable
```

Gives `array` a new length, keeping the elements that fit. The elements
past the old length are the zero of `T`. The same length leaves the
array as it is; any other puts a new array in `array`, and whoever holds
the old one still holds it unchanged.

**Parameters**

- `array` -- the array, replaced by the resized one
- `newSize` -- the length it is to have

**Type parameters**

- `T` -- the element type, which must have a zero value

<sub>[stdlib/Standard/Array.sl:101](../../stdlib/Standard/Array.sl#L101)</sub>

#### Resize *method*

```
static void Resize<T>(ref T[] array, nuint newSize, T fill)
```

The same, with the elements past the old length set to `fill`. This is
the one for a `T` with no zero value, such as `String`.

**Parameters**

- `array` -- the array, replaced by the resized one
- `newSize` -- the length it is to have
- `fill` -- what each new element is

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:119](../../stdlib/Standard/Array.sl#L119)</sub>

#### Copy *method*

```
static void Copy<T>(T[] sourceArray, T[] destinationArray, nuint length)
```

Copies the first `length` elements of `sourceArray` to the start of
`destinationArray`. Aborts, before anything is written, when either is
shorter than `length`.

**Parameters**

- `sourceArray` -- where the elements come from
- `destinationArray` -- where they go
- `length` -- how many to copy

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:140](../../stdlib/Standard/Array.sl#L140)</sub>

#### Copy *method*

```
static void Copy<T>(T[] sourceArray, nuint sourceIndex, T[] destinationArray, nuint destinationIndex, nuint length)
```

Copies `length` elements from `sourceIndex` in `sourceArray` to
`destinationIndex` in `destinationArray`. The two may be the same array
and the ranges may overlap: the elements land as they were before the
copy began. Aborts, before anything is written, when either range runs
past its array. .NET's `ConstrainedCopy` promises no more than this.

**Parameters**

- `sourceArray` -- where the elements come from
- `sourceIndex` -- the first element copied
- `destinationArray` -- where they go
- `destinationIndex` -- where the first lands
- `length` -- how many to copy

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:155](../../stdlib/Standard/Array.sl#L155)</sub>

#### Clear *method*

```
static void Clear<T>(T[] array)
    where T : zeroable
```

Sets every element to the zero of `T`, releasing whatever they held.

Only for a `T` with a zero value: an array of `String` has no `Clear`,
since there is nothing its elements could be set to. `Fill` is the one
for that.

**Parameters**

- `array` -- the array to clear

**Type parameters**

- `T` -- the element type, which must have a zero value

<sub>[stdlib/Standard/Array.sl:167](../../stdlib/Standard/Array.sl#L167)</sub>

#### Clear *method*

```
static void Clear<T>(T[] array, nuint index, nuint length)
    where T : zeroable
```

Sets `length` elements from `index` to the zero of `T`. Aborts when they
run past the end.

**Parameters**

- `array` -- the array to clear part of
- `index` -- the first element cleared
- `length` -- how many to clear

**Type parameters**

- `T` -- the element type, which must have a zero value

<sub>[stdlib/Standard/Array.sl:180](../../stdlib/Standard/Array.sl#L180)</sub>

#### Fill *method*

```
static void Fill<T>(T[] array, T value)
```

Sets every element to `value`.

**Parameters**

- `array` -- the array to fill
- `value` -- what each element becomes

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:188](../../stdlib/Standard/Array.sl#L188)</sub>

#### Fill *method*

```
static void Fill<T>(T[] array, T value, nuint startIndex, nuint count)
```

Sets `count` elements from `startIndex` to `value`. Aborts when they run
past the end.

**Parameters**

- `array` -- the array to fill part of
- `value` -- what each element becomes
- `startIndex` -- the first element set
- `count` -- how many to set

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:202](../../stdlib/Standard/Array.sl#L202)</sub>

#### Reverse *method*

```
static void Reverse<T>(T[] array)
```

Reverses the order of the elements in place.

**Parameters**

- `array` -- the array to reverse

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:209](../../stdlib/Standard/Array.sl#L209)</sub>

#### Reverse *method*

```
static void Reverse<T>(T[] array, nuint index, nuint length)
```

Reverses `length` elements from `index` in place. Aborts when they run
past the end.

**Parameters**

- `array` -- the array to reverse part of
- `index` -- the first element of the part
- `length` -- how many elements it covers

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:218](../../stdlib/Standard/Array.sl#L218)</sub>

#### Sort *method*

```
static void Sort<T>(T[] array)
    where T : IComparable<T>
```

Orders the elements in place, smallest first. Stable, where .NET's is
not: equal elements keep the order they had.

**Parameters**

- `array` -- the array to order

**Type parameters**

- `T` -- the element type, which must order itself

**See also** &nbsp; [Collections.Sort](Standard-Collections.md#sort-function)

<sub>[stdlib/Standard/Array.sl:229](../../stdlib/Standard/Array.sl#L229)</sub>

#### Sort *method*

```
static void Sort<T>(T[] array, Comparison<T> comparison)
```

Orders the elements in place by `comparison`. Stable.

**Parameters**

- `array` -- the array to order
- `comparison` -- negative when its first argument comes first

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:237](../../stdlib/Standard/Array.sl#L237)</sub>

#### Sort *method*

```
static void Sort<T>(T[] array, nuint index, nuint length)
    where T : IComparable<T>
```

Orders `length` elements from `index` in place, smallest first, and
leaves the rest alone. Stable. Aborts when they run past the end.

**Parameters**

- `array` -- the array to order part of
- `index` -- the first element of the part
- `length` -- how many elements it covers

**Type parameters**

- `T` -- the element type, which must order itself

<sub>[stdlib/Standard/Array.sl:247](../../stdlib/Standard/Array.sl#L247)</sub>

#### Sort *method*

```
static void Sort<T>(T[] array, nuint index, nuint length, Comparison<T> comparison)
```

Orders `length` elements from `index` in place by `comparison`. Stable.
Aborts when they run past the end.

**Parameters**

- `array` -- the array to order part of
- `index` -- the first element of the part
- `length` -- how many elements it covers
- `comparison` -- negative when its first argument comes first

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:258](../../stdlib/Standard/Array.sl#L258)</sub>

#### Sort *method*

```
static void Sort<TKey, TValue>(TKey[] keys, TValue[] items)
    where TKey : IComparable<TKey>
```

Orders `keys` in place, smallest first, and moves each element of
`items` to where its key went. Stable. The two MUST be the same length;
the call aborts otherwise, where .NET allows `items` to be longer.

**Parameters**

- `keys` -- the keys to order by
- `items` -- the elements that go with them

**Type parameters**

- `TKey` -- the key type, which must order itself
- `TValue` -- the item type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:269](../../stdlib/Standard/Array.sl#L269)</sub>

#### Sort *method*

```
static void Sort<TKey, TValue>(TKey[] keys, TValue[] items, Comparison<TKey> comparison)
```

The same, with the keys ordered by `comparison`.

**Parameters**

- `keys` -- the keys to order by
- `items` -- the elements that go with them
- `comparison` -- negative when its first argument comes first

**Type parameters**

- `TKey` -- the key type; the comparison orders it
- `TValue` -- the item type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:280](../../stdlib/Standard/Array.sl#L280)</sub>

#### BinarySearch *method*

```
static Optional<nuint> BinarySearch<T>(T[] array, T value)
    where T : IComparable<T>
```

Where `value` is in an array already ordered smallest first, if it is
there. `Collections.FindLowerBound` answers where it would go instead,
which .NET folds into a negative result.

**Parameters**

- `array` -- the ordered array
- `value` -- what to look for

**Type parameters**

- `T` -- the element type, which must order itself

**Returns** &nbsp; the index of an equal element, or `None`

**See also** &nbsp; [Collections.FindLowerBound](Standard-Collections.md#findlowerbound-function)

<sub>[stdlib/Standard/Array.sl:293](../../stdlib/Standard/Array.sl#L293)</sub>

#### BinarySearch *method*

```
static Optional<nuint> BinarySearch<T>(T[] array, nuint index, nuint length, T value)
    where T : IComparable<T>
```

Where `value` is among `length` ordered elements from `index`, if it is
there. The answer counts from the start of the array. Aborts when the
range runs past the end.

**Parameters**

- `array` -- the array
- `index` -- the first element searched
- `length` -- how many elements are searched
- `value` -- what to look for

**Type parameters**

- `T` -- the element type, which must order itself

**Returns** &nbsp; the index of an equal element, or `None`

<sub>[stdlib/Standard/Array.sl:306](../../stdlib/Standard/Array.sl#L306)</sub>

#### IndexOf *method*

```
static Optional<nuint> IndexOf<T>(T[] array, T value)
    where T : IEquatable<T>
```

Where the first element equal to `value` is, if there is one.

**Parameters**

- `array` -- the array to search
- `value` -- what to look for

**Type parameters**

- `T` -- the element type, which must answer whether it equals another

<sub>[stdlib/Standard/Array.sl:317](../../stdlib/Standard/Array.sl#L317)</sub>

#### IndexOf *method*

```
static Optional<nuint> IndexOf<T>(T[] array, T value, nuint startIndex)
    where T : IEquatable<T>
```

Where the first element equal to `value` is, searching from
`startIndex` to the end. Aborts when `startIndex` is past the end.

**Parameters**

- `array` -- the array to search
- `value` -- what to look for
- `startIndex` -- the first element searched

**Type parameters**

- `T` -- the element type, which must answer whether it equals another

<sub>[stdlib/Standard/Array.sl:327](../../stdlib/Standard/Array.sl#L327)</sub>

#### IndexOf *method*

```
static Optional<nuint> IndexOf<T>(T[] array, T value, nuint startIndex, nuint count)
    where T : IEquatable<T>
```

Where the first element equal to `value` is among `count` elements from
`startIndex`. Aborts when they run past the end.

**Parameters**

- `array` -- the array to search
- `value` -- what to look for
- `startIndex` -- the first element searched
- `count` -- how many elements are searched

**Type parameters**

- `T` -- the element type, which must answer whether it equals another

<sub>[stdlib/Standard/Array.sl:339](../../stdlib/Standard/Array.sl#L339)</sub>

#### LastIndexOf *method*

```
static Optional<nuint> LastIndexOf<T>(T[] array, T value)
    where T : IEquatable<T>
```

Where the last element equal to `value` is, if there is one.

**Parameters**

- `array` -- the array to search
- `value` -- what to look for

**Type parameters**

- `T` -- the element type, which must answer whether it equals another

<sub>[stdlib/Standard/Array.sl:348](../../stdlib/Standard/Array.sl#L348)</sub>

#### LastIndexOf *method*

```
static Optional<nuint> LastIndexOf<T>(T[] array, T value, nuint startIndex)
    where T : IEquatable<T>
```

Where the last element equal to `value` is, searching backward from
`startIndex` to the start. Aborts when `startIndex` is past the end.

**Parameters**

- `array` -- the array to search
- `value` -- what to look for
- `startIndex` -- the last element searched, where the search begins

**Type parameters**

- `T` -- the element type, which must answer whether it equals another

<sub>[stdlib/Standard/Array.sl:358](../../stdlib/Standard/Array.sl#L358)</sub>

#### LastIndexOf *method*

```
static Optional<nuint> LastIndexOf<T>(T[] array, T value, nuint startIndex, nuint count)
    where T : IEquatable<T>
```

Where the last element equal to `value` is among the `count` elements
that end at `startIndex`, searching backward. Aborts when they run past
either end.

**Parameters**

- `array` -- the array to search
- `value` -- what to look for
- `startIndex` -- the last element searched, where the search begins
- `count` -- how many elements are searched

**Type parameters**

- `T` -- the element type, which must answer whether it equals another

<sub>[stdlib/Standard/Array.sl:371](../../stdlib/Standard/Array.sl#L371)</sub>

#### Exists *method*

```
static bool Exists<T>(T[] array, Predicate<T> match)
```

Whether any element satisfies `match`.

**Parameters**

- `array` -- the array to search
- `match` -- what an element must satisfy

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:383](../../stdlib/Standard/Array.sl#L383)</sub>

#### TrueForAll *method*

```
static bool TrueForAll<T>(T[] array, Predicate<T> match)
```

Whether every element satisfies `match`. True for an empty array.

**Parameters**

- `array` -- the array to test
- `match` -- what each element must satisfy

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:391](../../stdlib/Standard/Array.sl#L391)</sub>

#### Find *method*

```
static Optional<T> Find<T>(T[] array, Predicate<T> match)
```

The first element satisfying `match`, if there is one. An `Optional`
where .NET answers `default(T)`, which a `T` that is never null does not
have.

**Parameters**

- `array` -- the array to search
- `match` -- what the element must satisfy

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:401](../../stdlib/Standard/Array.sl#L401)</sub>

#### FindLast *method*

```
static Optional<T> FindLast<T>(T[] array, Predicate<T> match)
```

The last element satisfying `match`, if there is one.

**Parameters**

- `array` -- the array to search
- `match` -- what the element must satisfy

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:409](../../stdlib/Standard/Array.sl#L409)</sub>

#### FindAll *method*

```
static T[] FindAll<T>(T[] array, Predicate<T> match)
```

Every element satisfying `match`, in order, as a new array.

**Parameters**

- `array` -- the array to search
- `match` -- what an element must satisfy

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:424](../../stdlib/Standard/Array.sl#L424)</sub>

#### FindIndex *method*

```
static Optional<nuint> FindIndex<T>(T[] array, Predicate<T> match)
```

Where the first element satisfying `match` is, if there is one.

**Parameters**

- `array` -- the array to search
- `match` -- what the element must satisfy

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:432](../../stdlib/Standard/Array.sl#L432)</sub>

#### FindIndex *method*

```
static Optional<nuint> FindIndex<T>(T[] array, nuint startIndex, Predicate<T> match)
```

Where the first element satisfying `match` is, searching from
`startIndex` to the end. Aborts when `startIndex` is past the end.

**Parameters**

- `array` -- the array to search
- `startIndex` -- the first element searched
- `match` -- what the element must satisfy

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:442](../../stdlib/Standard/Array.sl#L442)</sub>

#### FindIndex *method*

```
static Optional<nuint> FindIndex<T>(T[] array, nuint startIndex, nuint count, Predicate<T> match)
```

Where the first element satisfying `match` is among `count` elements
from `startIndex`. Aborts when they run past the end.

**Parameters**

- `array` -- the array to search
- `startIndex` -- the first element searched
- `count` -- how many elements are searched
- `match` -- what the element must satisfy

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:453](../../stdlib/Standard/Array.sl#L453)</sub>

#### FindLastIndex *method*

```
static Optional<nuint> FindLastIndex<T>(T[] array, Predicate<T> match)
```

Where the last element satisfying `match` is, if there is one.

**Parameters**

- `array` -- the array to search
- `match` -- what the element must satisfy

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:462](../../stdlib/Standard/Array.sl#L462)</sub>

#### FindLastIndex *method*

```
static Optional<nuint> FindLastIndex<T>(T[] array, nuint startIndex, Predicate<T> match)
```

Where the last element satisfying `match` is, searching backward from
`startIndex` to the start. Aborts when `startIndex` is past the end.

**Parameters**

- `array` -- the array to search
- `startIndex` -- the last element searched, where the search begins
- `match` -- what the element must satisfy

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:472](../../stdlib/Standard/Array.sl#L472)</sub>

#### FindLastIndex *method*

```
static Optional<nuint> FindLastIndex<T>(T[] array, nuint startIndex, nuint count, Predicate<T> match)
```

Where the last element satisfying `match` is among the `count` elements
that end at `startIndex`, searching backward. Aborts when they run past
either end.

**Parameters**

- `array` -- the array to search
- `startIndex` -- the last element searched, where the search begins
- `count` -- how many elements are searched
- `match` -- what the element must satisfy

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:485](../../stdlib/Standard/Array.sl#L485)</sub>

#### ForEach *method*

```
static void ForEach<T>(T[] array, Action<T> action)
```

Runs `action` over every element, in order.

**Parameters**

- `array` -- the array to walk
- `action` -- what to do with each element

**Type parameters**

- `T` -- the element type; nothing is asked of it

<sub>[stdlib/Standard/Array.sl:502](../../stdlib/Standard/Array.sl#L502)</sub>

### Buffer *class*

```
class Buffer
```

Arrays of plain data as bytes. C#'s `System.Buffer`.

    short[] samples = [1, -1];
    var bytes = new byte[Buffer.ByteLength(samples)];
    Buffer.BlockCopy(samples, 0u, bytes, 0u, bytes.Length);

Every element type is `unmanaged` (section 4.3): a value with no counted
reference anywhere in it, so moving its bytes cannot put a count out of
step. .NET asks for an array of primitives and checks it as the program
runs; the constraint checks it as the program is compiled, and also admits
a struct of primitives.

Offsets and counts are in bytes and are `nuint`. Every range is checked
against the array before a byte moves, and one that runs past the end
aborts, as an index out of range does. The bytes are in the machine's own
order.

<sub>[stdlib/Standard/Buffer.sl:40](../../stdlib/Standard/Buffer.sl#L40)</sub>

#### BlockCopy *method*

```
static void BlockCopy<TSource, TDestination>(TSource[] src, nuint srcOffset, TDestination[] dst, nuint dstOffset, nuint count)
    where TSource : unmanaged
    where TDestination : unmanaged
```

Copies `count` bytes from `srcOffset` bytes into `src` to `dstOffset`
bytes into `dst`. The two arrays may be of different types, and may be
the same array with overlapping ranges: the bytes land as they were
before the copy began.

A byte copied into a `bool`, an enum or a pointer need not be one of its
values; the element types SHOULD be numbers or structs of them.

**Parameters**

- `src` -- where the bytes come from
- `srcOffset` -- the first byte copied, counted from the start of `src`
- `dst` -- where they go
- `dstOffset` -- where the first lands, counted from the start of `dst`
- `count` -- how many bytes to copy

**Type parameters**

- `TSource` -- the element type of `src`, which must be plain data
- `TDestination` -- the element type of `dst`, which must be plain data

<sub>[stdlib/Standard/Buffer.sl:57](../../stdlib/Standard/Buffer.sl#L57)</sub>

#### ByteLength *method*

```
static nuint ByteLength<T>(T[] array)
    where T : unmanaged
```

How many bytes the elements of `array` take.

**Parameters**

- `array` -- the array to measure

**Type parameters**

- `T` -- the element type, which must be plain data

**Returns** &nbsp; the length times the size of one element

<sub>[stdlib/Standard/Buffer.sl:79](../../stdlib/Standard/Buffer.sl#L79)</sub>

#### GetByte *method*

```
static byte GetByte<T>(T[] array, nuint index)
    where T : unmanaged
```

The byte at `index` bytes into `array`. Aborts when it is past the end.

**Parameters**

- `array` -- the array to read
- `index` -- which byte, counted from the start

**Type parameters**

- `T` -- the element type, which must be plain data

<sub>[stdlib/Standard/Buffer.sl:87](../../stdlib/Standard/Buffer.sl#L87)</sub>

#### SetByte *method*

```
static void SetByte<T>(T[] array, nuint index, byte value)
    where T : unmanaged
```

Sets the byte at `index` bytes into `array`. Aborts when it is past the
end.

A byte written into a `bool`, an enum or a pointer need not leave one of
its values; the element type SHOULD be a number or a struct of them.

**Parameters**

- `array` -- the array to write
- `index` -- which byte, counted from the start
- `value` -- what it becomes

**Type parameters**

- `T` -- the element type, which must be plain data

<sub>[stdlib/Standard/Buffer.sl:104](../../stdlib/Standard/Buffer.sl#L104)</sub>

#### MemoryCopy *method*

```
static void MemoryCopy(void* source, void* destination, nuint destinationSizeInBytes, nuint sourceBytesToCopy)
```

Copies `sourceBytesToCopy` bytes from `source` to `destination`, which
may overlap. Aborts when that is more than `destinationSizeInBytes`.

Nothing else is checked, as nothing can be: both pointers MUST be valid
for the bytes named, and the destination MUST NOT hold a counted
reference.

**Parameters**

- `source` -- where the bytes come from
- `destination` -- where they go
- `destinationSizeInBytes` -- how many bytes `destination` has room for
- `sourceBytesToCopy` -- how many bytes to copy

<sub>[stdlib/Standard/Buffer.sl:122](../../stdlib/Standard/Buffer.sl#L122)</sub>

### Comparison&lt;T&gt; *closure*

```
closure int Comparison<in T>(T left, T right)
```

Orders two Ts: negative if `left` comes first, positive if `right` does,
zero if neither.

This is what lets a type be sorted more than one way, and what lets a type
that implements no interface be sorted at all.

**Type parameters**

- `T` -- what is being ordered

<sub>[stdlib/Standard/Standard.sl:119](../../stdlib/Standard/Standard.sl#L119)</sub>

### Fold&lt;TAccumulate, TSource&gt; *closure*

```
closure TAccumulate Fold<TAccumulate, in TSource>(TAccumulate total, TSource value)
```

Folds one element into a running total. Two parameters rather than one,
because a fold is the one shape that carries something along with it.

**Parameters**

- `total` -- what has been accumulated so far
- `value` -- the next element to fold in

**Type parameters**

- `TAccumulate` -- what is carried along, and what the fold answers with
- `TSource` -- what is folded over

<sub>[stdlib/Standard/Standard.sl:110](../../stdlib/Standard/Standard.sl#L110)</sub>

### ForeignException *class*

```
sealed class ForeignException
```

What a foreign function threw, caught at the call that a `[Throws]`
declaration made.

**Not an exception in Stainless.** Nothing unwinds through Stainless code:
the one call a binding marks `[Throws]` catches what it throws and answers
it as a value, a `Result<T, ForeignException>` or, for a call that produces
nothing, a `ForeignException?` that is null when it worked.

```
[Throws]
[Selector("readDataOfLength:")]
public Result<NSData, ForeignException> ReadDataOfLength(nuint length);

var read = handle.ReadDataOfLength(64u);
if (!read.Ok)
    Console.WriteLine(read.Error.Name + ": " + read.Error.Reason);
```

<sub>[stdlib/Standard/ForeignException.sl:46](../../stdlib/Standard/ForeignException.sl#L46)</sub>

#### Kind *property*

```
ForeignExceptionKind Kind { get; }
```

Which language threw it.

<sub>[stdlib/Standard/ForeignException.sl:49](../../stdlib/Standard/ForeignException.sl#L49)</sub>

#### Name *property*

```
String Name { get; }
```

An `NSException`'s name -- `NSInvalidArgumentException` -- and empty
for anything else.

<sub>[stdlib/Standard/ForeignException.sl:53](../../stdlib/Standard/ForeignException.sl#L53)</sub>

#### Reason *property*

```
String Reason { get; }
```

An `NSException`'s reason, and empty for anything else.

<sub>[stdlib/Standard/ForeignException.sl:56](../../stdlib/Standard/ForeignException.sl#L56)</sub>

#### Take *method*

```
static ForeignException Take(byte* caught)
```

What was caught, from the record the call's landing pad left, which
this frees. Called by the code the compiler writes for a `[Throws]`
call and by nothing else.

<sub>[stdlib/Standard/ForeignException.sl:68](../../stdlib/Standard/ForeignException.sl#L68)</sub>

### ForeignExceptionKind *enum*

```
enum ForeignExceptionKind
```

Which language threw a `ForeignException`.

<sub>[stdlib/Standard/ForeignExceptionKind.sl:25](../../stdlib/Standard/ForeignExceptionKind.sl#L25)</sub>

#### ObjectiveC *case*

```
ObjectiveC
```

An `NSException`, or any object `@throw` threw: it has a name and a
reason.

<sub>[stdlib/Standard/ForeignExceptionKind.sl:29](../../stdlib/Standard/ForeignExceptionKind.sl#L29)</sub>

#### Cpp *case*

```
Cpp
```

A C++ exception, whose object only C++ can read.

<sub>[stdlib/Standard/ForeignExceptionKind.sl:32](../../stdlib/Standard/ForeignExceptionKind.sl#L32)</sub>

#### Other *case*

```
Other
```

Anything else the unwinder carried.

<sub>[stdlib/Standard/ForeignExceptionKind.sl:35](../../stdlib/Standard/ForeignExceptionKind.sl#L35)</sub>

### Func&lt;T, TResult&gt; *closure*

```
closure TResult Func<in T, out TResult>(T value)
```

Turns a T into a TResult. The transform half of `Select`.

**Type parameters**

- `T` -- what goes in
- `TResult` -- what comes out

<sub>[stdlib/Standard/Standard.sl:38](../../stdlib/Standard/Standard.sl#L38)</sub>

### Func&lt;T1, T2, T3, T4, TResult&gt; *closure*

```
closure TResult Func<in T1, in T2, in T3, in T4, out TResult>(T1 arg1, T2 arg2, T3 arg3, T4 arg4)
```

Turns four values into a TResult.

**Type parameters**

- `T1` -- the first thing that goes in
- `T2` -- the second
- `T3` -- the third
- `T4` -- the fourth
- `TResult` -- what comes out

<sub>[stdlib/Standard/Standard.sl:67](../../stdlib/Standard/Standard.sl#L67)</sub>

### Func&lt;T1, T2, T3, TResult&gt; *closure*

```
closure TResult Func<in T1, in T2, in T3, out TResult>(T1 arg1, T2 arg2, T3 arg3)
```

Turns three values into a TResult.

**Type parameters**

- `T1` -- the first thing that goes in
- `T2` -- the second
- `T3` -- the third
- `TResult` -- what comes out

<sub>[stdlib/Standard/Standard.sl:58](../../stdlib/Standard/Standard.sl#L58)</sub>

### Func&lt;T1, T2, TResult&gt; *closure*

```
closure TResult Func<in T1, in T2, out TResult>(T1 arg1, T2 arg2)
```

Turns two values into a TResult. The combining half of `Zip`.

**Type parameters**

- `T1` -- the first thing that goes in
- `T2` -- the second
- `TResult` -- what comes out

<sub>[stdlib/Standard/Standard.sl:50](../../stdlib/Standard/Standard.sl#L50)</sub>

### Func&lt;TResult&gt; *closure*

```
closure TResult Func<out TResult>()
```

Produces a TResult from nothing.

**Type parameters**

- `TResult` -- what comes out

<sub>[stdlib/Standard/Standard.sl:43](../../stdlib/Standard/Standard.sl#L43)</sub>

### Guid *struct*

```
struct Guid : IEquatable<Guid>, IComparable<Guid>, IHashable
```

A 128-bit identifier: C#'s `System.Guid`, and COM's `GUID`.

    var id = Guid.NewGuid();
    String text = id.ToString();             // 36 characters, in lower case

Laid out as C's `GUID` is -- a 32-bit `_a`, two 16-bit `_b` and `_c`, and
eight bytes `_d` -- so a `Guid*` is what a COM function takes. The compiler
declares that layout, because `iidof` and the COM machinery name the type;
this declaration adds the rest. `ToByteArray` and the constructor from
bytes use the layout's byte order, as .NET's do, so a value round-trips
with a .NET program byte for byte; two compare as their text does.

<sub>[stdlib/Standard/Guid.sl:43](../../stdlib/Standard/Guid.sl#L43)</sub>

#### Empty *property*

```
static Guid Empty { get; }
```

All zeros.

<sub>[stdlib/Standard/Guid.sl:47](../../stdlib/Standard/Guid.sl#L47)</sub>

#### AllBitsSet *property*

```
static Guid AllBitsSet { get; }
```

All ones, the largest.

<sub>[stdlib/Standard/Guid.sl:50](../../stdlib/Standard/Guid.sl#L50)</sub>

#### NewGuid *method*

```
static Guid NewGuid()
```

A random one: version 4, 122 random bits. Aborts if the platform will
supply no entropy, as `RandomNumberGenerator` does.

<sub>[stdlib/Standard/Guid.sl:132](../../stdlib/Standard/Guid.sl#L132)</sub>

#### CreateVersion7 *method*

```
static Guid CreateVersion7()
```

A version 7 one: the time in milliseconds first, then random bits, so
one made later sorts later.

<sub>[stdlib/Standard/Guid.sl:136](../../stdlib/Standard/Guid.sl#L136)</sub>

#### Version *property*

```
int Version { get; }
```

Which layout of RFC 9562 this is: 4 for random, 7 for time-ordered.

<sub>[stdlib/Standard/Guid.sl:146](../../stdlib/Standard/Guid.sl#L146)</sub>

#### Variant *property*

```
int Variant { get; }
```

The variant bits, 0b10 for every one this makes.

<sub>[stdlib/Standard/Guid.sl:149](../../stdlib/Standard/Guid.sl#L149)</sub>

#### ToByteArray *method*

```
byte[] ToByteArray()
```

The sixteen bytes in .NET's order, which is this layout's.

<sub>[stdlib/Standard/Guid.sl:161](../../stdlib/Standard/Guid.sl#L161)</sub>

#### TryWriteBytes *method*

```
bool TryWriteBytes(Span<byte> destination)
```

Writes the sixteen bytes in .NET's order when there is room, and answers
whether there was.

<sub>[stdlib/Standard/Guid.sl:177](../../stdlib/Standard/Guid.sl#L177)</sub>

#### ToString *method*

```
String ToString()
```

Hyphenated, in lower case.

<sub>[stdlib/Standard/Guid.sl:187](../../stdlib/Standard/Guid.sl#L187)</sub>

#### ToString *method*

```
String ToString(String format)
```

In one of C#'s formats: `N` for 32 digits, `D` for hyphens between the
groups, `B` for that in braces, `P` in parentheses. Aborts on any other.

**Parameters**

- `format` -- "N", "D", "B" or "P", in either case

<sub>[stdlib/Standard/Guid.sl:193](../../stdlib/Standard/Guid.sl#L193)</sub>

#### Parse *method*

```
static Result<Guid, ParseError> Parse(String text)
```

Reads any of the formats `ToString` writes, in either case.

**Parameters**

- `text` -- 32 hex digits, with or without hyphens, braces or parentheses

<sub>[stdlib/Standard/Guid.sl:226](../../stdlib/Standard/Guid.sl#L226)</sub>

#### Equals *method*

```
bool Equals(Guid other)
```

Whether the two are the same sixteen bytes.

<sub>[stdlib/Standard/Guid.sl:276](../../stdlib/Standard/Guid.sl#L276)</sub>

#### CompareTo *method*

```
int CompareTo(Guid other)
```

Byte by byte in text order, which is the order their text sorts in.

<sub>[stdlib/Standard/Guid.sl:279](../../stdlib/Standard/Guid.sl#L279)</sub>

#### GetHashCode *method*

```
nuint GetHashCode()
```

*No documentation.*

<sub>[stdlib/Standard/Guid.sl:291](../../stdlib/Standard/Guid.sl#L291)</sub>

#### operator == *operator*

```
static bool operator ==(Guid left, Guid right)
```

*No documentation.*

<sub>[stdlib/Standard/Guid.sl:299](../../stdlib/Standard/Guid.sl#L299)</sub>

#### operator != *operator*

```
static bool operator !=(Guid left, Guid right)
```

*No documentation.*

<sub>[stdlib/Standard/Guid.sl:300](../../stdlib/Standard/Guid.sl#L300)</sub>

#### operator &lt; *operator*

```
static bool operator <(Guid left, Guid right)
```

*No documentation.*

<sub>[stdlib/Standard/Guid.sl:301](../../stdlib/Standard/Guid.sl#L301)</sub>

#### operator &gt; *operator*

```
static bool operator >(Guid left, Guid right)
```

*No documentation.*

<sub>[stdlib/Standard/Guid.sl:302](../../stdlib/Standard/Guid.sl#L302)</sub>

#### operator &lt;= *operator*

```
static bool operator <=(Guid left, Guid right)
```

*No documentation.*

<sub>[stdlib/Standard/Guid.sl:303](../../stdlib/Standard/Guid.sl#L303)</sub>

#### operator &gt;= *operator*

```
static bool operator >=(Guid left, Guid right)
```

*No documentation.*

<sub>[stdlib/Standard/Guid.sl:304](../../stdlib/Standard/Guid.sl#L304)</sub>

### IDisposable *interface*

```
interface IDisposable
```

Something that can be finished with before its last reference goes.
.NET's `System.IDisposable`.

**A destructor already frees what an object holds** when the last
reference to it goes, so most types need neither this nor a call to it.
`Dispose` is for the moment that comes earlier: a response whose
connection should go back to its pool while the response is still held, a
client others share that should refuse further work, a registration to
undo while its owner lives on. A type that has one SHOULD let it be called
more than once, and SHOULD do it from its destructor too, so that
forgetting it costs nothing but promptness.

<sub>[stdlib/Standard/IDisposable.sl:35](../../stdlib/Standard/IDisposable.sl#L35)</sub>

#### Dispose *method*

```
void Dispose()
```

Releases now what would otherwise be released at the last reference.

<sub>[stdlib/Standard/IDisposable.sl:38](../../stdlib/Standard/IDisposable.sl#L38)</sub>

### Index *struct*

```
struct Index
```

A position in a sequence, counted from its start or back from its end.
What `^n` makes when it is kept rather than used at once, as C#'s
`System.Index` is.

    Index last = ^1;
    int x = numbers[last];

**The count is a `nuint`**, as every length here is, where C# has `int`.
`^n` takes any integer and converts it the way an index does, so a
negative one becomes a position no sequence has.

<sub>[stdlib/Standard/Index.sl:34](../../stdlib/Standard/Index.sl#L34)</sub>

#### Value *property*

```
nuint Value { get; }
```

How far from the start, or back from the end.

<sub>[stdlib/Standard/Index.sl:48](../../stdlib/Standard/Index.sl#L48)</sub>

#### IsFromEnd *property*

```
bool IsFromEnd { get; }
```

Whether `Value` counts back from the end: `^1` is the last element.

<sub>[stdlib/Standard/Index.sl:51](../../stdlib/Standard/Index.sl#L51)</sub>

#### Start *property*

```
static Index Start { get; }
```

The first position, `0`.

<sub>[stdlib/Standard/Index.sl:54](../../stdlib/Standard/Index.sl#L54)</sub>

#### End *property*

```
static Index End { get; }
```

One past the last position, `^0`.

<sub>[stdlib/Standard/Index.sl:57](../../stdlib/Standard/Index.sl#L57)</sub>

#### GetOffset *method*

```
nuint GetOffset(nuint length)
```

The position this is in a sequence of `length` elements. Nothing is
checked here; the index or slice that uses the answer checks it.

<sub>[stdlib/Standard/Index.sl:61](../../stdlib/Standard/Index.sl#L61)</sub>

#### operator Identifier *operator*

```
static Index operator Identifier(nuint value)
```

A position counted from the start, so `Index i = 3;` reads as it does in C#.

<sub>[stdlib/Standard/Index.sl:64](../../stdlib/Standard/Index.sl#L64)</sub>

### Lazy&lt;T&gt; *class*

```
threadsafe class Lazy<T>
```

A value made the first time it is asked for: C#'s `System.Lazy<T>`.

    var table = new Lazy<Dictionary<String, int>>(() => LoadTable());
    int n = table.Value.GetValue("key");     // loaded here, once

By default the factory runs once however many threads ask at once, and the
others wait for it; `LazyThreadSafetyMode` says otherwise. A factory that
reads the `Value` it is making aborts, where C#'s throws.

**Type parameters**

- `T` -- what is made; nothing is asked of it

<sub>[stdlib/Standard/Lazy.sl:43](../../stdlib/Standard/Lazy.sl#L43)</sub>

#### IsValueCreated *property*

```
bool IsValueCreated { get; }
```

Whether the value has been made yet.

<sub>[stdlib/Standard/Lazy.sl:91](../../stdlib/Standard/Lazy.sl#L91)</sub>

#### Value *property*

```
T Value { get; }
```

The value, made now if it has not been.

<sub>[stdlib/Standard/Lazy.sl:106](../../stdlib/Standard/Lazy.sl#L106)</sub>

### LazyThreadSafetyMode *enum*

```
enum LazyThreadSafetyMode
```

How a `Lazy<T>` behaves when two threads ask for its value at once.

<sub>[stdlib/Standard/LazyThreadSafetyMode.sl:25](../../stdlib/Standard/LazyThreadSafetyMode.sl#L25)</sub>

#### None *case*

```
None
```

Not at all: it is for one thread, and costs no lock.

<sub>[stdlib/Standard/LazyThreadSafetyMode.sl:28](../../stdlib/Standard/LazyThreadSafetyMode.sl#L28)</sub>

#### PublicationOnly *case*

```
PublicationOnly
```

Each may run the factory, and the first to finish is the value everyone
gets.

<sub>[stdlib/Standard/LazyThreadSafetyMode.sl:32](../../stdlib/Standard/LazyThreadSafetyMode.sl#L32)</sub>

#### ExecutionAndPublication *case*

```
ExecutionAndPublication
```

The factory runs once, and the others wait for it. The default.

<sub>[stdlib/Standard/LazyThreadSafetyMode.sl:35](../../stdlib/Standard/LazyThreadSafetyMode.sl#L35)</sub>

### Optional&lt;T&gt; *variant*

```
variant Optional<T>
```

A value, or none -- for the types `T?` cannot describe.

`C?` is a nullable reference: the null is the pointer, so it costs nothing
and the compiler narrows it. A value type has no spare bit to be null with,
so `nuint?` is refused (SLT0021), and what stood in was a magic number --
`IndexOf` answering with the largest `nuint` there is and every caller
agreeing to read that as "not there".

This is that, said properly. It is an ordinary variant, so it costs a tag
beside the value and nothing else: no allocation, and the payload is only
read where the compiler has established the case.

    if (map.IndexOf(key) is Some found) { return values[found.Value]; }
    return fallback;

**Not a replacement for `C?`.** A nullable reference stays what it is: the
representation is already free there, and `if (c != null)` narrows without
a case to name. This is for everything a null pointer cannot say -- which
is also why the names differ: `Optional<T>` is this type, and "an optional"
is what the spec calls `C?`.

**Type parameters**

- `T` -- what it may hold -- a value type, usually, since a reference already has `C?`

<sub>[stdlib/Standard/Optional.sl:46](../../stdlib/Standard/Optional.sl#L46)</sub>

#### None *case*

```
None
```

There is no value. Carries nothing, so there is nothing to read by
mistake.

<sub>[stdlib/Standard/Optional.sl:50](../../stdlib/Standard/Optional.sl#L50)</sub>

#### Some *case*

```
Some(T Value)
```

There is one, and `Some` carries it. Reached with `is Some x`, which
takes the value and names it in the same step.

<sub>[stdlib/Standard/Optional.sl:54](../../stdlib/Standard/Optional.sl#L54)</sub>

#### HasValue *property*

```
bool HasValue { get; }
```

True when there is a value. The reader for a caller that is about to
ask a second question anyway; `is Some x` is the one that gets at it.

<sub>[stdlib/Standard/Optional.sl:58](../../stdlib/Standard/Optional.sl#L58)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when there is not. The same question the other way round, because
`!x.HasValue` reads worse than the thing it means.

<sub>[stdlib/Standard/Optional.sl:70](../../stdlib/Standard/Optional.sl#L70)</sub>

#### GetValue *method*

```
T GetValue()
```

The value, aborting when there is none.

The bargain `Dictionary.GetValue` and an array index make: asking for
something that is not there is a mistake in the caller rather than a
value to return. Use `GetValueOrDefault` where a miss is ordinary, and
`is Some x` where the answer decides what happens next.

**See also** &nbsp; [Optional.GetValueOrDefault](#getvalueordefault-method)

<sub>[stdlib/Standard/Optional.sl:88](../../stdlib/Standard/Optional.sl#L88)</sub>

#### GetValueOrDefault *method*

```
T GetValueOrDefault(T fallback)
```

The value if there is one, and `fallback` if there is not.

The reader that needs no proof, because it supplies its own -- the same
bargain `Result.GetValueOrDefault` makes.

**Parameters**

- `fallback` -- what to answer when there is nothing held

**See also** &nbsp; [Optional.GetValue](#getvalue-method)

<sub>[stdlib/Standard/Optional.sl:103](../../stdlib/Standard/Optional.sl#L103)</sub>

#### Coalesce *method*

```
Optional<T> Coalesce(Optional<T> other)
```

This one if it holds anything, and `other` if it does not.

`other` is a value rather than something that produces one on demand.
A lambda would allocate a closure to save an evaluation, which is the
wrong way round at the sizes this is used at.

<sub>[stdlib/Standard/Optional.sl:115](../../stdlib/Standard/Optional.sl#L115)</sub>

#### Select *method*

```
Optional<TResult> Select<TResult>(Func<T, TResult> transform)
```

The value put through `transform`, or none.

    Optional<String> name = found.Select(i => people[i].Name);

The transform runs only where there is something to run it on, which is
the point: it is the `if` that would otherwise be written by hand.

**Type parameters**

- `TResult` -- what `transform` produces

<sub>[stdlib/Standard/Optional.sl:130](../../stdlib/Standard/Optional.sl#L130)</sub>

#### SelectMany *method*

```
Optional<TResult> SelectMany<TResult>(Func<T, Optional<TResult>> transform)
```

`Select` for a transform that answers with an optional of its own, which
would otherwise nest one inside the other.

**Type parameters**

- `TResult` -- what the transform's own optional holds

<sub>[stdlib/Standard/Optional.sl:141](../../stdlib/Standard/Optional.sl#L141)</sub>

#### Where *method*

```
Optional<T> Where(Predicate<T> keep)
```

This one when it holds something `keep` accepts, and none otherwise.

<sub>[stdlib/Standard/Optional.sl:149](../../stdlib/Standard/Optional.sl#L149)</sub>

#### InvokeIfPresent *method*

```
void InvokeIfPresent(Action<T> action)
```

Runs `action` on the value, if there is one.

<sub>[stdlib/Standard/Optional.sl:160](../../stdlib/Standard/Optional.sl#L160)</sub>

### ParseError *enum*

```
enum ParseError
```

Why text could not be read as a value: what C#'s `FormatException` and
`OverflowException` say, as the error of a `Result`.

<sub>[stdlib/Standard/ParseError.sl:27](../../stdlib/Standard/ParseError.sl#L27)</sub>

#### Empty *case*

```
Empty
```

There was nothing to read.

<sub>[stdlib/Standard/ParseError.sl:30](../../stdlib/Standard/ParseError.sl#L30)</sub>

#### Malformed *case*

```
Malformed
```

Not the shape the value is written in.

<sub>[stdlib/Standard/ParseError.sl:33](../../stdlib/Standard/ParseError.sl#L33)</sub>

#### OutOfRange *case*

```
OutOfRange
```

The right shape, and a number in it too large to hold.

<sub>[stdlib/Standard/ParseError.sl:36](../../stdlib/Standard/ParseError.sl#L36)</sub>

### Predicate&lt;T&gt; *closure*

```
closure bool Predicate<in T>(T value)
```

Answers a question about a T.

**Type parameters**

- `T` -- what the question is about

<sub>[stdlib/Standard/Standard.sl:72](../../stdlib/Standard/Standard.sl#L72)</sub>

### Range *struct*

```
struct Range
```

The half-open run of positions between two `Index`es. What `a..b` makes
when it is kept rather than used at once, as C#'s `System.Range` is.

    Range inner = 1..^1;
    Span<int> middle = numbers[inner];

Either end may be left out: `..b` starts at the start and `a..` runs to
the end.

<sub>[stdlib/Standard/Range.sl:32](../../stdlib/Standard/Range.sl#L32)</sub>

#### Start *property*

```
Index Start { get; }
```

The first position in the run.

<sub>[stdlib/Standard/Range.sl:46](../../stdlib/Standard/Range.sl#L46)</sub>

#### End *property*

```
Index End { get; }
```

The position just past the last.

<sub>[stdlib/Standard/Range.sl:49](../../stdlib/Standard/Range.sl#L49)</sub>

#### All *property*

```
static Range All { get; }
```

Every position, `..`.

<sub>[stdlib/Standard/Range.sl:52](../../stdlib/Standard/Range.sl#L52)</sub>

#### GetOffsetAndLength *method*

```
(nuint, nuint) GetOffsetAndLength(nuint length)
```

Where the run begins in a sequence of `length` elements, and how many
elements it covers. Aborts when it runs backwards or past the end, as a
slice does.

<sub>[stdlib/Standard/Range.sl:57](../../stdlib/Standard/Range.sl#L57)</sub>

### ReadOnlySpan&lt;T&gt; *struct*

```
struct ReadOnlySpan<T>
```

Part of an array, as a value, which refuses a write through it. C#'s
`System.ReadOnlySpan<T>`, and what a function that only reads takes: an
array and a `Span<T>` both convert to one.

    int Sum(ReadOnlySpan<int> values) { ... }

Assigning an element, lending one by `ref` or `out`, and calling a struct
method that writes one are refused where they are written. The array
underneath is not frozen: a `Span<T>` over the same elements still writes
them, and this sees the change.

**Type parameters**

- `T` -- the element type; nothing is asked of it

**See also** &nbsp; [Span](#spant-struct)

<sub>[stdlib/Standard/ReadOnlySpan.sl:37](../../stdlib/Standard/ReadOnlySpan.sl#L37)</sub>

#### Empty *property*

```
static ReadOnlySpan<T> Empty { get; }
```

A span of nothing.

<sub>[stdlib/Standard/ReadOnlySpan.sl:70](../../stdlib/Standard/ReadOnlySpan.sl#L70)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether it has no elements.

<sub>[stdlib/Standard/ReadOnlySpan.sl:73](../../stdlib/Standard/ReadOnlySpan.sl#L73)</sub>

#### CopyTo *method*

```
void CopyTo(Span<T> destination)
```

Copies every element into the start of `destination`, aborting when it
is shorter. The two may overlap: the elements land as they were before
the copy began.

**Elements that hold no counted reference move as one `memmove`**;
the rest are copied one at a time, so every count stays right.

**Parameters**

- `destination` -- where the elements go

**See also** &nbsp; [ReadOnlySpan.TryCopyTo](#trycopyto-method)

<sub>[stdlib/Standard/ReadOnlySpan.sl:84](../../stdlib/Standard/ReadOnlySpan.sl#L84)</sub>

#### TryCopyTo *method*

```
bool TryCopyTo(Span<T> destination)
```

Copies every element into the start of `destination` when it is long
enough, and answers whether it was.

**Parameters**

- `destination` -- where the elements go

**Returns** &nbsp; true when the elements were copied

<sub>[stdlib/Standard/ReadOnlySpan.sl:114](../../stdlib/Standard/ReadOnlySpan.sl#L114)</sub>

#### Slice *method*

```
ReadOnlySpan<T> Slice(nuint start)
```

The elements from `start` to the end, aborting when `start` is past it.

**Parameters**

- `start` -- the first element of the result

<sub>[stdlib/Standard/ReadOnlySpan.sl:125](../../stdlib/Standard/ReadOnlySpan.sl#L125)</sub>

#### Slice *method*

```
ReadOnlySpan<T> Slice(nuint start, nuint length)
```

`length` elements from `start`, aborting when they run past the end.

**Parameters**

- `start` -- the first element of the result
- `length` -- how many elements it covers

<sub>[stdlib/Standard/ReadOnlySpan.sl:131](../../stdlib/Standard/ReadOnlySpan.sl#L131)</sub>

#### ToArray *method*

```
T[] ToArray()
```

A new array holding a copy of the elements.

<sub>[stdlib/Standard/ReadOnlySpan.sl:134](../../stdlib/Standard/ReadOnlySpan.sl#L134)</sub>

#### Overlaps *method*

```
bool Overlaps(ReadOnlySpan<T> other)
```

Whether the two view any element in common.

**Parameters**

- `other` -- the span to compare with

<sub>[stdlib/Standard/ReadOnlySpan.sl:143](../../stdlib/Standard/ReadOnlySpan.sl#L143)</sub>

#### Overlaps *method*

```
bool Overlaps(ReadOnlySpan<T> other, out nint elementOffset)
```

Whether the two view any element in common, and where `other` starts
relative to this, in elements -- negative when it starts before.

**Parameters**

- `other` -- the span to compare with
- `elementOffset` -- where `other` starts, counted from this one's start

<sub>[stdlib/Standard/ReadOnlySpan.sl:152](../../stdlib/Standard/ReadOnlySpan.sl#L152)</sub>

#### operator == *operator*

```
static bool operator ==(ReadOnlySpan<T> left, ReadOnlySpan<T> right)
```

Whether the two are the same elements of the same array: C#'s rule,
which compares where they are rather than what they hold.

<sub>[stdlib/Standard/ReadOnlySpan.sl:166](../../stdlib/Standard/ReadOnlySpan.sl#L166)</sub>

#### operator != *operator*

```
static bool operator !=(ReadOnlySpan<T> left, ReadOnlySpan<T> right)
```

Whether the two are not the same elements of the same array.

<sub>[stdlib/Standard/ReadOnlySpan.sl:171](../../stdlib/Standard/ReadOnlySpan.sl#L171)</sub>

### Result&lt;T, TError&gt; *variant*

```
variant Result<T, TError>
```

What an operation produced, or why it did not.

This is the language's answer to an exception. Stainless does not unwind, so
a function that can fail says so in its return type and the caller cannot
quietly ignore it: `Value` is unreadable until the compiler has seen `Ok`
checked, and `Error` unreadable until it has seen it fail.

```
Result<Config, IOError> Load(String path) {
    var text = File.ReadAllText(path);
    if (!text.Ok) { return Fail(text.Error); }
    return Ok(Parse(text.Value));
}
```

It is an ordinary variant, and every rule it appears to have is a rule
variants have. `Ok` and `Fail` are its two cases, so `r.Ok` asks the tag;
`Value` and `Error` are the fields those cases carry, so reading one needs
the compiler to have established which case is there; and both are written
without type arguments because a case takes its variant from where it is
going, the way a lambda takes its type from what it is assigned to.

Being a variant is also what makes it small. Only one case is ever present,
so the payloads overlap: a `Result<String, IOError>` is a tag and one
pointer, not a flag and both halves. Nothing allocates either way.

**Type parameters**

- `T` -- what the call produces when it worked
- `TError` -- why it did not, usually an enum so that a failure has a name rather than a number

<sub>[stdlib/Standard/Result.sl:53](../../stdlib/Standard/Result.sl#L53)</sub>

#### Ok *case*

```
Ok(T Value)
```

It worked, and `Value` is the answer.

<sub>[stdlib/Standard/Result.sl:56](../../stdlib/Standard/Result.sl#L56)</sub>

#### Fail *case*

```
Fail(TError Error)
```

It did not, and `Error` says why. The value is not there to be read --
that is the whole of what a variant buys over a pair.

<sub>[stdlib/Standard/Result.sl:60](../../stdlib/Standard/Result.sl#L60)</sub>

#### GetValueOrDefault *method*

```
T GetValueOrDefault(T fallback)
```

The value if there is one, and `fallback` if there is not.

The one reader that needs no proof, because it supplies its own: a
caller with a sensible default has nothing to check.

<sub>[stdlib/Standard/Result.sl:66](../../stdlib/Standard/Result.sl#L66)</sub>

### RuntimeHelpers *class*

```
class RuntimeHelpers
```

What the compiler knows about a type, asked from inside a generic. C#'s
`System.Runtime.CompilerServices.RuntimeHelpers`.

<sub>[stdlib/Standard/RuntimeHelpers.sl:26](../../stdlib/Standard/RuntimeHelpers.sl#L26)</sub>

#### IsReferenceOrContainsReferences *method*

```
static bool IsReferenceOrContainsReferences<T>()
```

Whether a `T` is a counted reference or holds one anywhere: a class, an
interface, an array, a `String`, a closure, a weak reference, or a
struct, tuple or variant with one of those in it at any depth.

**Each call is a constant.** A generic is compiled once per type
argument, so the compiler answers the call where it is bound, and an
`if` on the answer compiles to the one arm it takes. That is what lets
a generic copy move reference-free elements with `memmove` and still
count every reference it copies.

    if (!RuntimeHelpers.IsReferenceOrContainsReferences<T>())
    {
        // raw bytes: no count can go out of step
    }

**Type parameters**

- `T` -- the type asked about

**Returns** &nbsp; false when a `T` is all of what it holds, so its bytes may be copied, compared or cleared with no count to keep

<sub>[stdlib/Standard/RuntimeHelpers.sl:46](../../stdlib/Standard/RuntimeHelpers.sl#L46)</sub>

#### GetTypeName *method*

```
static String GetTypeName<T>()
```

A `T`'s name, qualified by its module: `App.Worker`, `Standard.Text.String`,
or `Standard.Collections.List<App.Point>` for an instantiation.

**Each call is a constant**, as the question above is, and needs no
`[Reflect]`: it names an interface, a struct or a primitive as readily as
a class. It is what a logger's category and a message about a missing
service are written from.

**Type parameters**

- `T` -- the type named

**Returns** &nbsp; the name the compiler knows `T` by

<sub>[stdlib/Standard/RuntimeHelpers.sl:58](../../stdlib/Standard/RuntimeHelpers.sl#L58)</sub>

### Slot&lt;T&gt; *struct*

```
struct Slot<T>
```

Storage for a value that may not be there yet, at no cost beside it.

    Slot<String>[] room = new Slot<String>[8];
    room[0] = "first";
    String held = room[0].Value;
    room[0].Clear();

`new String[n]` is refused, because its elements would start as nulls
where a `String` has none. A slot's zero is empty, so an array of them may
be made at any length; it is what a collection keeps spare capacity in.

When `T` has a zero value a slot is laid out as a `T`, and an empty one
reads as that zero. When `T` has none a slot is an `Optional<T>`, which is
as wide as `T` because a never-null reference leaves its null spare, and
reading an empty one stops the program.

<sub>[stdlib/Standard/Slot.sl:39](../../stdlib/Standard/Slot.sl#L39)</sub>

#### Value *property*

```
T Value { get; }
```

What the slot holds. When `T` has no zero value an empty slot aborts;
otherwise it reads as the zero of `T`.

<sub>[stdlib/Standard/Slot.sl:47](../../stdlib/Standard/Slot.sl#L47)</sub>

#### Clear *method*

```
void Clear()
```

Empties the slot, releasing what it held.

<sub>[stdlib/Standard/Slot.sl:50](../../stdlib/Standard/Slot.sl#L50)</sub>

#### ToArray *method*

```
static T[] ToArray(ReadOnlySpan<Slot<T>> filled)
```

The values of slots that are all full, as a new array of that many.

**Parameters**

- `filled` -- the slots; each MUST hold a value when `T` has no zero value

**Returns** &nbsp; the array

<sub>[stdlib/Standard/Slot.sl:59](../../stdlib/Standard/Slot.sl#L59)</sub>

#### Copy *method*

```
static void Copy(ReadOnlySpan<T> source, Span<Slot<T>> destination)
```

Fills slots from values, in order from the start of `destination`.

**Parameters**

- `source` -- the values
- `destination` -- where they go; aborts when it is shorter than `source`

<sub>[stdlib/Standard/Slot.sl:66](../../stdlib/Standard/Slot.sl#L66)</sub>

### Span&lt;T&gt; *struct*

```
struct Span<T>
```

Part of an array, as a value, which may be written through. C#'s
`System.Span<T>`.

    Span<int> middle = numbers[1:4];
    middle.Fill(0);

The compiler knows this struct: indexing, `Length`, cutting with `[a:b]`
or `[a..b]`, `foreach`, and the conversions from an array and to a
`ReadOnlySpan<T>` are its own, and the members here are the rest. Unlike
C#'s it holds the array it views, so it may be stored and returned and
cannot dangle.

The searching C# puts in `MemoryExtensions` -- `IndexOf`, `Contains`,
`SequenceEqual`, `Sort` and the rest -- is in `Standard.Collections`, as
free functions taking a `ReadOnlySpan<T>` or a `Span<T>`, and a call written
on a span reaches them.

**Type parameters**

- `T` -- the element type; nothing is asked of it

**See also** &nbsp; [ReadOnlySpan](#readonlyspant-struct)

<sub>[stdlib/Standard/Span.sl:43](../../stdlib/Standard/Span.sl#L43)</sub>

#### Empty *property*

```
static Span<T> Empty { get; }
```

A span of nothing.

<sub>[stdlib/Standard/Span.sl:76](../../stdlib/Standard/Span.sl#L76)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether it has no elements.

<sub>[stdlib/Standard/Span.sl:79](../../stdlib/Standard/Span.sl#L79)</sub>

#### Clear *method*

```
void Clear()
    where T : zeroable
```

Sets every element to `default(T)`, releasing whatever they held.

Only for a `T` with a zero value: a span of `String` has no `Clear`,
since there is nothing its elements could be set to.

<sub>[stdlib/Standard/Span.sl:85](../../stdlib/Standard/Span.sl#L85)</sub>

#### Fill *method*

```
void Fill(T value)
```

Sets every element to `value`.

**Parameters**

- `value` -- what each element becomes

<sub>[stdlib/Standard/Span.sl:104](../../stdlib/Standard/Span.sl#L104)</sub>

#### CopyTo *method*

```
void CopyTo(Span<T> destination)
```

Copies every element into the start of `destination`, aborting when it
is shorter. The two may overlap: the elements land as they were before
the copy began.

**Parameters**

- `destination` -- where the elements go

**See also** &nbsp; [Span.TryCopyTo](#trycopyto-method)

<sub>[stdlib/Standard/Span.sl:142](../../stdlib/Standard/Span.sl#L142)</sub>

#### TryCopyTo *method*

```
bool TryCopyTo(Span<T> destination)
```

Copies every element into the start of `destination` when it is long
enough, and answers whether it was.

**Parameters**

- `destination` -- where the elements go

**Returns** &nbsp; true when the elements were copied

<sub>[stdlib/Standard/Span.sl:153](../../stdlib/Standard/Span.sl#L153)</sub>

#### Slice *method*

```
Span<T> Slice(nuint start)
```

The elements from `start` to the end, aborting when `start` is past it.

**Parameters**

- `start` -- the first element of the result

<sub>[stdlib/Standard/Span.sl:162](../../stdlib/Standard/Span.sl#L162)</sub>

#### Slice *method*

```
Span<T> Slice(nuint start, nuint length)
```

`length` elements from `start`, aborting when they run past the end.

**Parameters**

- `start` -- the first element of the result
- `length` -- how many elements it covers

<sub>[stdlib/Standard/Span.sl:168](../../stdlib/Standard/Span.sl#L168)</sub>

#### ToArray *method*

```
T[] ToArray()
```

A new array holding a copy of the elements.

<sub>[stdlib/Standard/Span.sl:171](../../stdlib/Standard/Span.sl#L171)</sub>

#### Overlaps *method*

```
bool Overlaps(ReadOnlySpan<T> other)
```

Whether the two view any element in common.

**Parameters**

- `other` -- the span to compare with

<sub>[stdlib/Standard/Span.sl:180](../../stdlib/Standard/Span.sl#L180)</sub>

#### Overlaps *method*

```
bool Overlaps(ReadOnlySpan<T> other, out nint elementOffset)
```

Whether the two view any element in common, and where `other` starts
relative to this, in elements -- negative when it starts before.

**Parameters**

- `other` -- the span to compare with
- `elementOffset` -- where `other` starts, counted from this one's start

<sub>[stdlib/Standard/Span.sl:191](../../stdlib/Standard/Span.sl#L191)</sub>

#### operator == *operator*

```
static bool operator ==(Span<T> left, Span<T> right)
```

Whether the two are the same elements of the same array: C#'s rule,
which compares where they are rather than what they hold.

<sub>[stdlib/Standard/Span.sl:199](../../stdlib/Standard/Span.sl#L199)</sub>

#### operator != *operator*

```
static bool operator !=(Span<T> left, Span<T> right)
```

Whether the two are not the same elements of the same array.

<sub>[stdlib/Standard/Span.sl:206](../../stdlib/Standard/Span.sl#L206)</sub>

### Uri *class*

```
sealed class Uri : IEquatable<Uri>, IHashable
```

A URI, read by RFC 3986: C#'s `System.Uri`.

    var page = new Uri("https://example.com/docs/guide/intro.html?v=2#top");
    page.Host;                               // "example.com"
    new Uri(page, "../api/").AbsoluteUri;    // "https://example.com/docs/api/"

An absolute one is kept in its normal form: the scheme and host in lower
case, `.` and `..` segments resolved, the scheme's default port dropped,
and a character that may not appear escaped. A Windows path or a UNC path
reads as a `file:` URI, as in C#. A relative one is kept as written, and
asking it for a part only an absolute URI has aborts, where C#'s throws.

A host with a control byte, a space, DEL, or any of `/ ? # @ \ [ ]` in it
is not one, and neither is a colon outside a bracketed IPv6 literal:
a host is copied into request lines, where any of these would end one.

`TryCreate` answers with a `Result`; the constructors abort on what is not a
URI, as C#'s throw.

<sub>[stdlib/Standard/Uri.sl:44](../../stdlib/Standard/Uri.sl#L44)</sub>

#### TryCreate *method*

```
static Result<Uri, ParseError> TryCreate(String text, UriKind kind)
```

`text` read as `kind` says, or why it could not be.

<sub>[stdlib/Standard/Uri.sl:99](../../stdlib/Standard/Uri.sl#L99)</sub>

#### TryCreate *method*

```
static Result<Uri, ParseError> TryCreate(Uri baseUri, String relative)
```

`relative` resolved against `baseUri`, or why it could not be.

<sub>[stdlib/Standard/Uri.sl:110](../../stdlib/Standard/Uri.sl#L110)</sub>

#### IsWellFormedUriString *method*

```
static bool IsWellFormedUriString(String text, UriKind kind)
```

Whether `text` reads as `kind` says.

<sub>[stdlib/Standard/Uri.sl:122](../../stdlib/Standard/Uri.sl#L122)</sub>

#### UriSchemeHttp *property*

```
static String UriSchemeHttp { get; }
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:139](../../stdlib/Standard/Uri.sl#L139)</sub>

#### UriSchemeHttps *property*

```
static String UriSchemeHttps { get; }
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:140](../../stdlib/Standard/Uri.sl#L140)</sub>

#### UriSchemeFile *property*

```
static String UriSchemeFile { get; }
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:141](../../stdlib/Standard/Uri.sl#L141)</sub>

#### UriSchemeFtp *property*

```
static String UriSchemeFtp { get; }
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:142](../../stdlib/Standard/Uri.sl#L142)</sub>

#### UriSchemeMailto *property*

```
static String UriSchemeMailto { get; }
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:143](../../stdlib/Standard/Uri.sl#L143)</sub>

#### UriSchemeWs *property*

```
static String UriSchemeWs { get; }
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:144](../../stdlib/Standard/Uri.sl#L144)</sub>

#### UriSchemeWss *property*

```
static String UriSchemeWss { get; }
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:145](../../stdlib/Standard/Uri.sl#L145)</sub>

#### CheckSchemeName *method*

```
static bool CheckSchemeName(String name)
```

Whether `name` is a scheme: a letter, then letters, digits, `+`, `-` and `.`.

<sub>[stdlib/Standard/Uri.sl:164](../../stdlib/Standard/Uri.sl#L164)</sub>

#### EscapeDataString *method*

```
static String EscapeDataString(String text)
```

`text` with everything but letters, digits and `-._~` escaped, as a
query value or a path segment needs.

<sub>[stdlib/Standard/Uri.sl:459](../../stdlib/Standard/Uri.sl#L459)</sub>

#### UnescapeDataString *method*

```
static String UnescapeDataString(String text)
```

`text` with every `%XX` replaced by the byte it stands for.

<sub>[stdlib/Standard/Uri.sl:474](../../stdlib/Standard/Uri.sl#L474)</sub>

#### IsAbsoluteUri *property*

```
bool IsAbsoluteUri { get; }
```

Whether it names a scheme.

<sub>[stdlib/Standard/Uri.sl:526](../../stdlib/Standard/Uri.sl#L526)</sub>

#### OriginalString *property*

```
String OriginalString { get; }
```

What it was made from, unchanged.

<sub>[stdlib/Standard/Uri.sl:529](../../stdlib/Standard/Uri.sl#L529)</sub>

#### Scheme *property*

```
String Scheme { get; }
```

`https`, in lower case.

<sub>[stdlib/Standard/Uri.sl:532](../../stdlib/Standard/Uri.sl#L532)</sub>

#### UserInfo *property*

```
String UserInfo { get; }
```

What came before an `@` in the authority, or "".

<sub>[stdlib/Standard/Uri.sl:542](../../stdlib/Standard/Uri.sl#L542)</sub>

#### Host *property*

```
String Host { get; }
```

The host, in lower case, bracketed when it is an IPv6 address.

<sub>[stdlib/Standard/Uri.sl:552](../../stdlib/Standard/Uri.sl#L552)</sub>

#### Port *property*

```
int Port { get; }
```

The port, the scheme's default when none was written, and -1 when the
scheme has none.

<sub>[stdlib/Standard/Uri.sl:563](../../stdlib/Standard/Uri.sl#L563)</sub>

#### IsDefaultPort *property*

```
bool IsDefaultPort { get; }
```

Whether the port is the one the scheme means anyway.

<sub>[stdlib/Standard/Uri.sl:573](../../stdlib/Standard/Uri.sl#L573)</sub>

#### Authority *property*

```
String Authority { get; }
```

The host, and the port when it is not the default.

<sub>[stdlib/Standard/Uri.sl:583](../../stdlib/Standard/Uri.sl#L583)</sub>

#### AbsolutePath *property*

```
String AbsolutePath { get; }
```

The path, escaped, `/` when an authority was given with none.

<sub>[stdlib/Standard/Uri.sl:593](../../stdlib/Standard/Uri.sl#L593)</sub>

#### Query *property*

```
String Query { get; }
```

`?` and what follows it up to the fragment, or "".

<sub>[stdlib/Standard/Uri.sl:603](../../stdlib/Standard/Uri.sl#L603)</sub>

#### Fragment *property*

```
String Fragment { get; }
```

`#` and what follows it, or "".

<sub>[stdlib/Standard/Uri.sl:613](../../stdlib/Standard/Uri.sl#L613)</sub>

#### PathAndQuery *property*

```
String PathAndQuery { get; }
```

The path and the query.

<sub>[stdlib/Standard/Uri.sl:623](../../stdlib/Standard/Uri.sl#L623)</sub>

#### AbsoluteUri *property*

```
String AbsoluteUri { get; }
```

The whole of it, in normal form.

<sub>[stdlib/Standard/Uri.sl:633](../../stdlib/Standard/Uri.sl#L633)</sub>

#### Segments *property*

```
String[] Segments { get; }
```

The path's segments, each with the `/` that ends it: `/a/b` is `/`,
`a/` and `b`.

<sub>[stdlib/Standard/Uri.sl:644](../../stdlib/Standard/Uri.sl#L644)</sub>

#### IsFile *property*

```
bool IsFile { get; }
```

Whether the scheme is `file`.

<sub>[stdlib/Standard/Uri.sl:665](../../stdlib/Standard/Uri.sl#L665)</sub>

#### IsUnc *property*

```
bool IsUnc { get; }
```

Whether it is a `file:` URI naming a machine, as a UNC path does.

<sub>[stdlib/Standard/Uri.sl:675](../../stdlib/Standard/Uri.sl#L675)</sub>

#### IsLoopback *property*

```
bool IsLoopback { get; }
```

Whether the host is this machine.

<sub>[stdlib/Standard/Uri.sl:685](../../stdlib/Standard/Uri.sl#L685)</sub>

#### LocalPath *property*

```
String LocalPath { get; }
```

The path as the operating system writes it, unescaped: a Windows path
or a UNC path for a `file:` URI there, and the path elsewhere.

<sub>[stdlib/Standard/Uri.sl:697](../../stdlib/Standard/Uri.sl#L697)</sub>

#### GetLeftPart *method*

```
String GetLeftPart(UriPartial part)
```

As much of it as `part` says, from the left.

**Parameters**

- `part` -- up to the scheme, the authority, the path or the query

<sub>[stdlib/Standard/Uri.sl:721](../../stdlib/Standard/Uri.sl#L721)</sub>

#### IsBaseOf *method*

```
bool IsBaseOf(Uri uri)
```

Whether `uri` is at or below where this points: the same scheme and
authority, and a path inside this one's directory.

**Parameters**

- `uri` -- the URI that may be below this one

<sub>[stdlib/Standard/Uri.sl:743](../../stdlib/Standard/Uri.sl#L743)</sub>

#### MakeRelativeUri *method*

```
Uri MakeRelativeUri(Uri uri)
```

The relative URI that `uri` is from here: `uri` itself when the two do
not share a scheme and authority.

**Parameters**

- `uri` -- where the result leads, resolved against this

<sub>[stdlib/Standard/Uri.sl:761](../../stdlib/Standard/Uri.sl#L761)</sub>

#### ToString *method*

```
String ToString()
```

The whole of it in normal form, or a relative one as it was written.

<sub>[stdlib/Standard/Uri.sl:785](../../stdlib/Standard/Uri.sl#L785)</sub>

#### Equals *method*

```
bool Equals(Uri other)
```

Whether the two name the same resource: equal in everything but the
fragment and the user, as C# compares them.

<sub>[stdlib/Standard/Uri.sl:789](../../stdlib/Standard/Uri.sl#L789)</sub>

#### GetHashCode *method*

```
nuint GetHashCode()
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:799](../../stdlib/Standard/Uri.sl#L799)</sub>

#### operator == *operator*

```
static bool operator ==(Uri left, Uri right)
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:808](../../stdlib/Standard/Uri.sl#L808)</sub>

#### operator != *operator*

```
static bool operator !=(Uri left, Uri right)
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:809](../../stdlib/Standard/Uri.sl#L809)</sub>

### UriKind *enum*

```
enum UriKind
```

What a `Uri` is allowed to be read as.

<sub>[stdlib/Standard/UriKind.sl:25](../../stdlib/Standard/UriKind.sl#L25)</sub>

#### RelativeOrAbsolute *case*

```
RelativeOrAbsolute
```

Either: absolute when it names a scheme, relative when it does not.

<sub>[stdlib/Standard/UriKind.sl:28](../../stdlib/Standard/UriKind.sl#L28)</sub>

#### Absolute *case*

```
Absolute
```

With a scheme, as `https://example.com/`.

<sub>[stdlib/Standard/UriKind.sl:31](../../stdlib/Standard/UriKind.sl#L31)</sub>

#### Relative *case*

```
Relative
```

Without one, as `../images/logo.png`.

<sub>[stdlib/Standard/UriKind.sl:34](../../stdlib/Standard/UriKind.sl#L34)</sub>

### UriPartial *enum*

```
enum UriPartial
```

How much of a `Uri` `GetLeftPart` keeps.

<sub>[stdlib/Standard/UriPartial.sl:25](../../stdlib/Standard/UriPartial.sl#L25)</sub>

#### Scheme *case*

```
Scheme
```

`https://`.

<sub>[stdlib/Standard/UriPartial.sl:28](../../stdlib/Standard/UriPartial.sl#L28)</sub>

#### Authority *case*

```
Authority
```

`https://user@example.com:8080`.

<sub>[stdlib/Standard/UriPartial.sl:31](../../stdlib/Standard/UriPartial.sl#L31)</sub>

#### Path *case*

```
Path
```

And the path.

<sub>[stdlib/Standard/UriPartial.sl:34](../../stdlib/Standard/UriPartial.sl#L34)</sub>

#### Query *case*

```
Query
```

And the query.

<sub>[stdlib/Standard/UriPartial.sl:37](../../stdlib/Standard/UriPartial.sl#L37)</sub>

### Version *struct*

```
struct Version : IEquatable<Version>, IComparable<Version>, IHashable
```

A version number of two to four parts: C#'s `System.Version`.

    var version = Version.Parse("1.4.2").GetValue();
    if (version >= new Version(1, 4)) { ... }

`Build` and `Revision` are -1 when the version was written without them,
and a version without a part comes before one with it: 1.4 is before 1.4.0.

<sub>[stdlib/Standard/Version.sl:34](../../stdlib/Standard/Version.sl#L34)</sub>

#### Major *property*

```
int Major { get; }
```

The first part.

<sub>[stdlib/Standard/Version.sl:37](../../stdlib/Standard/Version.sl#L37)</sub>

#### Minor *property*

```
int Minor { get; }
```

The second part.

<sub>[stdlib/Standard/Version.sl:40](../../stdlib/Standard/Version.sl#L40)</sub>

#### Build *property*

```
int Build { get; }
```

The third part, or -1 when there is none.

<sub>[stdlib/Standard/Version.sl:43](../../stdlib/Standard/Version.sl#L43)</sub>

#### Revision *property*

```
int Revision { get; }
```

The fourth part, or -1 when there is none.

<sub>[stdlib/Standard/Version.sl:46](../../stdlib/Standard/Version.sl#L46)</sub>

#### MajorRevision *property*

```
short MajorRevision { get; }
```

The high 16 bits of `Revision`.

<sub>[stdlib/Standard/Version.sl:68](../../stdlib/Standard/Version.sl#L68)</sub>

#### MinorRevision *property*

```
short MinorRevision { get; }
```

The low 16 bits of `Revision`.

<sub>[stdlib/Standard/Version.sl:71](../../stdlib/Standard/Version.sl#L71)</sub>

#### Parse *method*

```
static Result<Version, ParseError> Parse(String text)
```

Reads two to four parts separated by dots.

**Parameters**

- `text` -- the version, as `ToString` writes it

<sub>[stdlib/Standard/Version.sl:76](../../stdlib/Standard/Version.sl#L76)</sub>

#### ToString *method*

```
String ToString()
```

The parts that were given, joined by dots.

<sub>[stdlib/Standard/Version.sl:98](../../stdlib/Standard/Version.sl#L98)</sub>

#### ToString *method*

```
String ToString(int fieldCount)
```

The first `fieldCount` parts, joined by dots. Aborts when that is more
parts than there are.

**Parameters**

- `fieldCount` -- from 0 to 4

<sub>[stdlib/Standard/Version.sl:104](../../stdlib/Standard/Version.sl#L104)</sub>

#### Equals *method*

```
bool Equals(Version other)
```

Whether the two have the same parts.

<sub>[stdlib/Standard/Version.sl:122](../../stdlib/Standard/Version.sl#L122)</sub>

#### CompareTo *method*

```
int CompareTo(Version other)
```

Part by part, a missing part first.

<sub>[stdlib/Standard/Version.sl:126](../../stdlib/Standard/Version.sl#L126)</sub>

#### GetHashCode *method*

```
nuint GetHashCode()
```

*No documentation.*

<sub>[stdlib/Standard/Version.sl:135](../../stdlib/Standard/Version.sl#L135)</sub>

#### operator == *operator*

```
static bool operator ==(Version left, Version right)
```

*No documentation.*

<sub>[stdlib/Standard/Version.sl:138](../../stdlib/Standard/Version.sl#L138)</sub>

#### operator != *operator*

```
static bool operator !=(Version left, Version right)
```

*No documentation.*

<sub>[stdlib/Standard/Version.sl:139](../../stdlib/Standard/Version.sl#L139)</sub>

#### operator &lt; *operator*

```
static bool operator <(Version left, Version right)
```

*No documentation.*

<sub>[stdlib/Standard/Version.sl:140](../../stdlib/Standard/Version.sl#L140)</sub>

#### operator &gt; *operator*

```
static bool operator >(Version left, Version right)
```

*No documentation.*

<sub>[stdlib/Standard/Version.sl:141](../../stdlib/Standard/Version.sl#L141)</sub>

#### operator &lt;= *operator*

```
static bool operator <=(Version left, Version right)
```

*No documentation.*

<sub>[stdlib/Standard/Version.sl:142](../../stdlib/Standard/Version.sl#L142)</sub>

#### operator &gt;= *operator*

```
static bool operator >=(Version left, Version right)
```

*No documentation.*

<sub>[stdlib/Standard/Version.sl:143](../../stdlib/Standard/Version.sl#L143)</sub>

