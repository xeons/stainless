# Standard

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

The language's own vocabulary: the markers and types that are rules rather
than library features, and so need no import to reach.

## Contents

**Types** &nbsp; [Action](#action-closure) &middot; [Action&lt;T1, T2, T3, T4&gt;](#actiont1-t2-t3-t4-closure) &middot; [Action&lt;T1, T2, T3&gt;](#actiont1-t2-t3-closure) &middot; [Action&lt;T1, T2&gt;](#actiont1-t2-closure) &middot; [Action&lt;T&gt;](#actiont-closure) &middot; [Comparison&lt;T&gt;](#comparisont-closure) &middot; [Fold&lt;TAccumulate, TSource&gt;](#foldtaccumulate-tsource-closure) &middot; [Func&lt;T, TResult&gt;](#funct-tresult-closure) &middot; [Func&lt;T1, T2, T3, T4, TResult&gt;](#funct1-t2-t3-t4-tresult-closure) &middot; [Func&lt;T1, T2, T3, TResult&gt;](#funct1-t2-t3-tresult-closure) &middot; [Func&lt;T1, T2, TResult&gt;](#funct1-t2-tresult-closure) &middot; [Func&lt;TResult&gt;](#functresult-closure) &middot; [Guid](#guid-struct) &middot; [Index](#index-struct) &middot; [Lazy&lt;T&gt;](#lazyt-class) &middot; [LazyThreadSafetyMode](#lazythreadsafetymode-enum) &middot; [Optional&lt;T&gt;](#optionalt-variant) &middot; [ParseError](#parseerror-enum) &middot; [Predicate&lt;T&gt;](#predicatet-closure) &middot; [Range](#range-struct) &middot; [ReadOnlySpan&lt;T&gt;](#readonlyspant-struct) &middot; [Result&lt;T, TError&gt;](#resultt-terror-variant) &middot; [RuntimeHelpers](#runtimehelpers-class) &middot; [Span&lt;T&gt;](#spant-struct) &middot; [Uri](#uri-class) &middot; [UriKind](#urikind-enum) &middot; [UriPartial](#uripartial-enum) &middot; [Version](#version-struct)

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

- `T1` — the first thing handed to it
- `T2` — the second
- `T3` — the third
- `T4` — the fourth

<sub>[stdlib/Standard/Standard.sl:101](../../stdlib/Standard/Standard.sl#L101)</sub>

### Action&lt;T1, T2, T3&gt; *closure*

```
closure void Action<in T1, in T2, in T3>(T1 arg1, T2 arg2, T3 arg3)
```

Does something with three values and returns nothing.

**Type parameters**

- `T1` — the first thing handed to it
- `T2` — the second
- `T3` — the third

<sub>[stdlib/Standard/Standard.sl:93](../../stdlib/Standard/Standard.sl#L93)</sub>

### Action&lt;T1, T2&gt; *closure*

```
closure void Action<in T1, in T2>(T1 arg1, T2 arg2)
```

Does something with two values and returns nothing.

**Type parameters**

- `T1` — the first thing handed to it
- `T2` — the second

<sub>[stdlib/Standard/Standard.sl:86](../../stdlib/Standard/Standard.sl#L86)</sub>

### Action&lt;T&gt; *closure*

```
closure void Action<in T>(T value)
```

Does something with a T and returns nothing.

**Type parameters**

- `T` — what is handed to it

<sub>[stdlib/Standard/Standard.sl:77](../../stdlib/Standard/Standard.sl#L77)</sub>

### Comparison&lt;T&gt; *closure*

```
closure int Comparison<in T>(T left, T right)
```

Orders two Ts: negative if `left` comes first, positive if `right` does,
zero if neither.

This is what lets a type be sorted more than one way, and what lets a type
that implements no interface be sorted at all.

**Type parameters**

- `T` — what is being ordered

<sub>[stdlib/Standard/Standard.sl:119](../../stdlib/Standard/Standard.sl#L119)</sub>

### Fold&lt;TAccumulate, TSource&gt; *closure*

```
closure TAccumulate Fold<TAccumulate, in TSource>(TAccumulate total, TSource value)
```

Folds one element into a running total. Two parameters rather than one,
because a fold is the one shape that carries something along with it.

**Parameters**

- `total` — what has been accumulated so far
- `value` — the next element to fold in

**Type parameters**

- `TAccumulate` — what is carried along, and what the fold answers with
- `TSource` — what is folded over

<sub>[stdlib/Standard/Standard.sl:110](../../stdlib/Standard/Standard.sl#L110)</sub>

### Func&lt;T, TResult&gt; *closure*

```
closure TResult Func<in T, out TResult>(T value)
```

Turns a T into a TResult. The transform half of `Select`.

**Type parameters**

- `T` — what goes in
- `TResult` — what comes out

<sub>[stdlib/Standard/Standard.sl:38](../../stdlib/Standard/Standard.sl#L38)</sub>

### Func&lt;T1, T2, T3, T4, TResult&gt; *closure*

```
closure TResult Func<in T1, in T2, in T3, in T4, out TResult>(T1 arg1, T2 arg2, T3 arg3, T4 arg4)
```

Turns four values into a TResult.

**Type parameters**

- `T1` — the first thing that goes in
- `T2` — the second
- `T3` — the third
- `T4` — the fourth
- `TResult` — what comes out

<sub>[stdlib/Standard/Standard.sl:67](../../stdlib/Standard/Standard.sl#L67)</sub>

### Func&lt;T1, T2, T3, TResult&gt; *closure*

```
closure TResult Func<in T1, in T2, in T3, out TResult>(T1 arg1, T2 arg2, T3 arg3)
```

Turns three values into a TResult.

**Type parameters**

- `T1` — the first thing that goes in
- `T2` — the second
- `T3` — the third
- `TResult` — what comes out

<sub>[stdlib/Standard/Standard.sl:58](../../stdlib/Standard/Standard.sl#L58)</sub>

### Func&lt;T1, T2, TResult&gt; *closure*

```
closure TResult Func<in T1, in T2, out TResult>(T1 arg1, T2 arg2)
```

Turns two values into a TResult. The combining half of `Zip`.

**Type parameters**

- `T1` — the first thing that goes in
- `T2` — the second
- `TResult` — what comes out

<sub>[stdlib/Standard/Standard.sl:50](../../stdlib/Standard/Standard.sl#L50)</sub>

### Func&lt;TResult&gt; *closure*

```
closure TResult Func<out TResult>()
```

Produces a TResult from nothing.

**Type parameters**

- `TResult` — what comes out

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

- `format` — "N", "D", "B" or "P", in either case

<sub>[stdlib/Standard/Guid.sl:193](../../stdlib/Standard/Guid.sl#L193)</sub>

#### Parse *method*

```
static Result<Guid, ParseError> Parse(String text)
```

Reads any of the formats `ToString` writes, in either case.

**Parameters**

- `text` — 32 hex digits, with or without hyphens, braces or parentheses

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

- `T` — what is made; nothing is asked of it

<sub>[stdlib/Standard/Lazy.sl:43](../../stdlib/Standard/Lazy.sl#L43)</sub>

#### IsValueCreated *property*

```
bool IsValueCreated { get; }
```

Whether the value has been made yet.

<sub>[stdlib/Standard/Lazy.sl:89](../../stdlib/Standard/Lazy.sl#L89)</sub>

#### Value *property*

```
T Value { get; }
```

The value, made now if it has not been.

<sub>[stdlib/Standard/Lazy.sl:104](../../stdlib/Standard/Lazy.sl#L104)</sub>

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
so `nuint?` is refused (SL0271), and what stood in was a magic number --
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

- `T` — what it may hold -- a value type, usually, since a reference already has `C?`

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

- `fallback` — what to answer when there is nothing held

**See also** &nbsp; [Optional.GetValue](#getvalue-method)

<sub>[stdlib/Standard/Optional.sl:107](../../stdlib/Standard/Optional.sl#L107)</sub>

#### Coalesce *method*

```
Optional<T> Coalesce(Optional<T> other)
```

This one if it holds anything, and `other` if it does not.

`other` is a value rather than something that produces one on demand.
A lambda would allocate a closure to save an evaluation, which is the
wrong way round at the sizes this is used at.

<sub>[stdlib/Standard/Optional.sl:119](../../stdlib/Standard/Optional.sl#L119)</sub>

#### Select *method*

```
Optional<TResult> Select<TResult>(Func<T, TResult> transform)
```

The value put through `transform`, or none.

    Optional<String> name = found.Select(i => people[i].Name);

The transform runs only where there is something to run it on, which is
the point: it is the `if` that would otherwise be written by hand.

**Type parameters**

- `TResult` — what `transform` produces

<sub>[stdlib/Standard/Optional.sl:134](../../stdlib/Standard/Optional.sl#L134)</sub>

#### SelectMany *method*

```
Optional<TResult> SelectMany<TResult>(Func<T, Optional<TResult>> transform)
```

`Select` for a transform that answers with an optional of its own, which
would otherwise nest one inside the other.

**Type parameters**

- `TResult` — what the transform's own optional holds

<sub>[stdlib/Standard/Optional.sl:145](../../stdlib/Standard/Optional.sl#L145)</sub>

#### Where *method*

```
Optional<T> Where(Predicate<T> keep)
```

This one when it holds something `keep` accepts, and none otherwise.

<sub>[stdlib/Standard/Optional.sl:153](../../stdlib/Standard/Optional.sl#L153)</sub>

#### InvokeIfPresent *method*

```
void InvokeIfPresent(Action<T> action)
```

Runs `action` on the value, if there is one.

<sub>[stdlib/Standard/Optional.sl:164](../../stdlib/Standard/Optional.sl#L164)</sub>

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

- `T` — what the question is about

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

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [Span](#spant-struct)

<sub>[stdlib/Standard/ReadOnlySpan.sl:37](../../stdlib/Standard/ReadOnlySpan.sl#L37)</sub>

#### Empty *property*

```
static ReadOnlySpan<T> Empty { get; }
```

A span of nothing.

<sub>[stdlib/Standard/ReadOnlySpan.sl:69](../../stdlib/Standard/ReadOnlySpan.sl#L69)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether it has no elements.

<sub>[stdlib/Standard/ReadOnlySpan.sl:72](../../stdlib/Standard/ReadOnlySpan.sl#L72)</sub>

#### CopyTo *method*

```
void CopyTo(Span<T> destination)
```

Copies every element into the start of `destination`, aborting when it
is shorter. The two may overlap: the elements land as they were before
the copy began.

**Parameters**

- `destination` — where the elements go

**See also** &nbsp; [ReadOnlySpan.TryCopyTo](#trycopyto-method)

<sub>[stdlib/Standard/ReadOnlySpan.sl:80](../../stdlib/Standard/ReadOnlySpan.sl#L80)</sub>

#### TryCopyTo *method*

```
bool TryCopyTo(Span<T> destination)
```

Copies every element into the start of `destination` when it is long
enough, and answers whether it was.

**Parameters**

- `destination` — where the elements go

**Returns** &nbsp; true when the elements were copied

<sub>[stdlib/Standard/ReadOnlySpan.sl:102](../../stdlib/Standard/ReadOnlySpan.sl#L102)</sub>

#### Slice *method*

```
ReadOnlySpan<T> Slice(nuint start)
```

The elements from `start` to the end, aborting when `start` is past it.

**Parameters**

- `start` — the first element of the result

<sub>[stdlib/Standard/ReadOnlySpan.sl:113](../../stdlib/Standard/ReadOnlySpan.sl#L113)</sub>

#### Slice *method*

```
ReadOnlySpan<T> Slice(nuint start, nuint length)
```

`length` elements from `start`, aborting when they run past the end.

**Parameters**

- `start` — the first element of the result
- `length` — how many elements it covers

<sub>[stdlib/Standard/ReadOnlySpan.sl:119](../../stdlib/Standard/ReadOnlySpan.sl#L119)</sub>

#### ToArray *method*

```
T[] ToArray()
```

A new array holding a copy of the elements.

<sub>[stdlib/Standard/ReadOnlySpan.sl:122](../../stdlib/Standard/ReadOnlySpan.sl#L122)</sub>

#### Overlaps *method*

```
bool Overlaps(ReadOnlySpan<T> other)
```

Whether the two view any element in common.

**Parameters**

- `other` — the span to compare with

<sub>[stdlib/Standard/ReadOnlySpan.sl:133](../../stdlib/Standard/ReadOnlySpan.sl#L133)</sub>

#### Overlaps *method*

```
bool Overlaps(ReadOnlySpan<T> other, out nint elementOffset)
```

Whether the two view any element in common, and where `other` starts
relative to this, in elements -- negative when it starts before.

**Parameters**

- `other` — the span to compare with
- `elementOffset` — where `other` starts, counted from this one's start

<sub>[stdlib/Standard/ReadOnlySpan.sl:142](../../stdlib/Standard/ReadOnlySpan.sl#L142)</sub>

#### operator == *operator*

```
static bool operator ==(ReadOnlySpan<T> left, ReadOnlySpan<T> right)
```

Whether the two are the same elements of the same array: C#'s rule,
which compares where they are rather than what they hold.

<sub>[stdlib/Standard/ReadOnlySpan.sl:156](../../stdlib/Standard/ReadOnlySpan.sl#L156)</sub>

#### operator != *operator*

```
static bool operator !=(ReadOnlySpan<T> left, ReadOnlySpan<T> right)
```

Whether the two are not the same elements of the same array.

<sub>[stdlib/Standard/ReadOnlySpan.sl:161](../../stdlib/Standard/ReadOnlySpan.sl#L161)</sub>

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

- `T` — what the call produces when it worked
- `TError` — why it did not, usually an enum so that a failure has a name rather than a number

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

- `T` — the type asked about

**Returns** &nbsp; false when a `T` is all of what it holds, so its bytes may be copied, compared or cleared with no count to keep

<sub>[stdlib/Standard/RuntimeHelpers.sl:46](../../stdlib/Standard/RuntimeHelpers.sl#L46)</sub>

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

- `T` — the element type; nothing is asked of it

**See also** &nbsp; [ReadOnlySpan](#readonlyspant-struct)

<sub>[stdlib/Standard/Span.sl:43](../../stdlib/Standard/Span.sl#L43)</sub>

#### Empty *property*

```
static Span<T> Empty { get; }
```

A span of nothing.

<sub>[stdlib/Standard/Span.sl:75](../../stdlib/Standard/Span.sl#L75)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

Whether it has no elements.

<sub>[stdlib/Standard/Span.sl:78](../../stdlib/Standard/Span.sl#L78)</sub>

#### Clear *method*

```
void Clear()
```

Sets every element to `default(T)`, releasing whatever they held.

<sub>[stdlib/Standard/Span.sl:81](../../stdlib/Standard/Span.sl#L81)</sub>

#### Fill *method*

```
void Fill(T value)
```

Sets every element to `value`.

**Parameters**

- `value` — what each element becomes

<sub>[stdlib/Standard/Span.sl:90](../../stdlib/Standard/Span.sl#L90)</sub>

#### CopyTo *method*

```
void CopyTo(Span<T> destination)
```

Copies every element into the start of `destination`, aborting when it
is shorter. The two may overlap: the elements land as they were before
the copy began.

**Parameters**

- `destination` — where the elements go

**See also** &nbsp; [Span.TryCopyTo](#trycopyto-method)

<sub>[stdlib/Standard/Span.sl:102](../../stdlib/Standard/Span.sl#L102)</sub>

#### TryCopyTo *method*

```
bool TryCopyTo(Span<T> destination)
```

Copies every element into the start of `destination` when it is long
enough, and answers whether it was.

**Parameters**

- `destination` — where the elements go

**Returns** &nbsp; true when the elements were copied

<sub>[stdlib/Standard/Span.sl:113](../../stdlib/Standard/Span.sl#L113)</sub>

#### Slice *method*

```
Span<T> Slice(nuint start)
```

The elements from `start` to the end, aborting when `start` is past it.

**Parameters**

- `start` — the first element of the result

<sub>[stdlib/Standard/Span.sl:122](../../stdlib/Standard/Span.sl#L122)</sub>

#### Slice *method*

```
Span<T> Slice(nuint start, nuint length)
```

`length` elements from `start`, aborting when they run past the end.

**Parameters**

- `start` — the first element of the result
- `length` — how many elements it covers

<sub>[stdlib/Standard/Span.sl:128](../../stdlib/Standard/Span.sl#L128)</sub>

#### ToArray *method*

```
T[] ToArray()
```

A new array holding a copy of the elements.

<sub>[stdlib/Standard/Span.sl:131](../../stdlib/Standard/Span.sl#L131)</sub>

#### Overlaps *method*

```
bool Overlaps(ReadOnlySpan<T> other)
```

Whether the two view any element in common.

**Parameters**

- `other` — the span to compare with

<sub>[stdlib/Standard/Span.sl:140](../../stdlib/Standard/Span.sl#L140)</sub>

#### Overlaps *method*

```
bool Overlaps(ReadOnlySpan<T> other, out nint elementOffset)
```

Whether the two view any element in common, and where `other` starts
relative to this, in elements -- negative when it starts before.

**Parameters**

- `other` — the span to compare with
- `elementOffset` — where `other` starts, counted from this one's start

<sub>[stdlib/Standard/Span.sl:151](../../stdlib/Standard/Span.sl#L151)</sub>

#### operator == *operator*

```
static bool operator ==(Span<T> left, Span<T> right)
```

Whether the two are the same elements of the same array: C#'s rule,
which compares where they are rather than what they hold.

<sub>[stdlib/Standard/Span.sl:159](../../stdlib/Standard/Span.sl#L159)</sub>

#### operator != *operator*

```
static bool operator !=(Span<T> left, Span<T> right)
```

Whether the two are not the same elements of the same array.

<sub>[stdlib/Standard/Span.sl:166](../../stdlib/Standard/Span.sl#L166)</sub>

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

`TryCreate` answers with a `Result`; the constructors abort on what is not a
URI, as C#'s throw.

<sub>[stdlib/Standard/Uri.sl:40](../../stdlib/Standard/Uri.sl#L40)</sub>

#### TryCreate *method*

```
static Result<Uri, ParseError> TryCreate(String text, UriKind kind)
```

`text` read as `kind` says, or why it could not be.

<sub>[stdlib/Standard/Uri.sl:92](../../stdlib/Standard/Uri.sl#L92)</sub>

#### TryCreate *method*

```
static Result<Uri, ParseError> TryCreate(Uri baseUri, String relative)
```

`relative` resolved against `baseUri`, or why it could not be.

<sub>[stdlib/Standard/Uri.sl:103](../../stdlib/Standard/Uri.sl#L103)</sub>

#### IsWellFormedUriString *method*

```
static bool IsWellFormedUriString(String text, UriKind kind)
```

Whether `text` reads as `kind` says.

<sub>[stdlib/Standard/Uri.sl:113](../../stdlib/Standard/Uri.sl#L113)</sub>

#### UriSchemeHttp *property*

```
static String UriSchemeHttp { get; }
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:130](../../stdlib/Standard/Uri.sl#L130)</sub>

#### UriSchemeHttps *property*

```
static String UriSchemeHttps { get; }
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:131](../../stdlib/Standard/Uri.sl#L131)</sub>

#### UriSchemeFile *property*

```
static String UriSchemeFile { get; }
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:132](../../stdlib/Standard/Uri.sl#L132)</sub>

#### UriSchemeFtp *property*

```
static String UriSchemeFtp { get; }
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:133](../../stdlib/Standard/Uri.sl#L133)</sub>

#### UriSchemeMailto *property*

```
static String UriSchemeMailto { get; }
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:134](../../stdlib/Standard/Uri.sl#L134)</sub>

#### UriSchemeWs *property*

```
static String UriSchemeWs { get; }
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:135](../../stdlib/Standard/Uri.sl#L135)</sub>

#### UriSchemeWss *property*

```
static String UriSchemeWss { get; }
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:136](../../stdlib/Standard/Uri.sl#L136)</sub>

#### CheckSchemeName *method*

```
static bool CheckSchemeName(String name)
```

Whether `name` is a scheme: a letter, then letters, digits, `+`, `-` and `.`.

<sub>[stdlib/Standard/Uri.sl:155](../../stdlib/Standard/Uri.sl#L155)</sub>

#### EscapeDataString *method*

```
static String EscapeDataString(String text)
```

`text` with everything but letters, digits and `-._~` escaped, as a
query value or a path segment needs.

<sub>[stdlib/Standard/Uri.sl:424](../../stdlib/Standard/Uri.sl#L424)</sub>

#### UnescapeDataString *method*

```
static String UnescapeDataString(String text)
```

`text` with every `%XX` replaced by the byte it stands for.

<sub>[stdlib/Standard/Uri.sl:439](../../stdlib/Standard/Uri.sl#L439)</sub>

#### IsAbsoluteUri *property*

```
bool IsAbsoluteUri { get; }
```

Whether it names a scheme.

<sub>[stdlib/Standard/Uri.sl:491](../../stdlib/Standard/Uri.sl#L491)</sub>

#### OriginalString *property*

```
String OriginalString { get; }
```

What it was made from, unchanged.

<sub>[stdlib/Standard/Uri.sl:494](../../stdlib/Standard/Uri.sl#L494)</sub>

#### Scheme *property*

```
String Scheme { get; }
```

`https`, in lower case.

<sub>[stdlib/Standard/Uri.sl:497](../../stdlib/Standard/Uri.sl#L497)</sub>

#### UserInfo *property*

```
String UserInfo { get; }
```

What came before an `@` in the authority, or "".

<sub>[stdlib/Standard/Uri.sl:507](../../stdlib/Standard/Uri.sl#L507)</sub>

#### Host *property*

```
String Host { get; }
```

The host, in lower case, bracketed when it is an IPv6 address.

<sub>[stdlib/Standard/Uri.sl:517](../../stdlib/Standard/Uri.sl#L517)</sub>

#### Port *property*

```
int Port { get; }
```

The port, the scheme's default when none was written, and -1 when the
scheme has none.

<sub>[stdlib/Standard/Uri.sl:528](../../stdlib/Standard/Uri.sl#L528)</sub>

#### IsDefaultPort *property*

```
bool IsDefaultPort { get; }
```

Whether the port is the one the scheme means anyway.

<sub>[stdlib/Standard/Uri.sl:538](../../stdlib/Standard/Uri.sl#L538)</sub>

#### Authority *property*

```
String Authority { get; }
```

The host, and the port when it is not the default.

<sub>[stdlib/Standard/Uri.sl:548](../../stdlib/Standard/Uri.sl#L548)</sub>

#### AbsolutePath *property*

```
String AbsolutePath { get; }
```

The path, escaped, `/` when an authority was given with none.

<sub>[stdlib/Standard/Uri.sl:558](../../stdlib/Standard/Uri.sl#L558)</sub>

#### Query *property*

```
String Query { get; }
```

`?` and what follows it up to the fragment, or "".

<sub>[stdlib/Standard/Uri.sl:568](../../stdlib/Standard/Uri.sl#L568)</sub>

#### Fragment *property*

```
String Fragment { get; }
```

`#` and what follows it, or "".

<sub>[stdlib/Standard/Uri.sl:578](../../stdlib/Standard/Uri.sl#L578)</sub>

#### PathAndQuery *property*

```
String PathAndQuery { get; }
```

The path and the query.

<sub>[stdlib/Standard/Uri.sl:588](../../stdlib/Standard/Uri.sl#L588)</sub>

#### AbsoluteUri *property*

```
String AbsoluteUri { get; }
```

The whole of it, in normal form.

<sub>[stdlib/Standard/Uri.sl:598](../../stdlib/Standard/Uri.sl#L598)</sub>

#### Segments *property*

```
String[] Segments { get; }
```

The path's segments, each with the `/` that ends it: `/a/b` is `/`,
`a/` and `b`.

<sub>[stdlib/Standard/Uri.sl:609](../../stdlib/Standard/Uri.sl#L609)</sub>

#### IsFile *property*

```
bool IsFile { get; }
```

Whether the scheme is `file`.

<sub>[stdlib/Standard/Uri.sl:630](../../stdlib/Standard/Uri.sl#L630)</sub>

#### IsUnc *property*

```
bool IsUnc { get; }
```

Whether it is a `file:` URI naming a machine, as a UNC path does.

<sub>[stdlib/Standard/Uri.sl:640](../../stdlib/Standard/Uri.sl#L640)</sub>

#### IsLoopback *property*

```
bool IsLoopback { get; }
```

Whether the host is this machine.

<sub>[stdlib/Standard/Uri.sl:650](../../stdlib/Standard/Uri.sl#L650)</sub>

#### LocalPath *property*

```
String LocalPath { get; }
```

The path as the operating system writes it, unescaped: a Windows path
or a UNC path for a `file:` URI there, and the path elsewhere.

<sub>[stdlib/Standard/Uri.sl:662](../../stdlib/Standard/Uri.sl#L662)</sub>

#### GetLeftPart *method*

```
String GetLeftPart(UriPartial part)
```

As much of it as `part` says, from the left.

**Parameters**

- `part` — up to the scheme, the authority, the path or the query

<sub>[stdlib/Standard/Uri.sl:686](../../stdlib/Standard/Uri.sl#L686)</sub>

#### IsBaseOf *method*

```
bool IsBaseOf(Uri uri)
```

Whether `uri` is at or below where this points: the same scheme and
authority, and a path inside this one's directory.

**Parameters**

- `uri` — the URI that may be below this one

<sub>[stdlib/Standard/Uri.sl:708](../../stdlib/Standard/Uri.sl#L708)</sub>

#### MakeRelativeUri *method*

```
Uri MakeRelativeUri(Uri uri)
```

The relative URI that `uri` is from here: `uri` itself when the two do
not share a scheme and authority.

**Parameters**

- `uri` — where the result leads, resolved against this

<sub>[stdlib/Standard/Uri.sl:726](../../stdlib/Standard/Uri.sl#L726)</sub>

#### ToString *method*

```
String ToString()
```

The whole of it in normal form, or a relative one as it was written.

<sub>[stdlib/Standard/Uri.sl:750](../../stdlib/Standard/Uri.sl#L750)</sub>

#### Equals *method*

```
bool Equals(Uri other)
```

Whether the two name the same resource: equal in everything but the
fragment and the user, as C# compares them.

<sub>[stdlib/Standard/Uri.sl:754](../../stdlib/Standard/Uri.sl#L754)</sub>

#### GetHashCode *method*

```
nuint GetHashCode()
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:764](../../stdlib/Standard/Uri.sl#L764)</sub>

#### operator == *operator*

```
static bool operator ==(Uri left, Uri right)
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:773](../../stdlib/Standard/Uri.sl#L773)</sub>

#### operator != *operator*

```
static bool operator !=(Uri left, Uri right)
```

*No documentation.*

<sub>[stdlib/Standard/Uri.sl:774](../../stdlib/Standard/Uri.sl#L774)</sub>

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

- `text` — the version, as `ToString` writes it

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

- `fieldCount` — from 0 to 4

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

