<sub>[Stainless](../../README.md) &rsaquo; [Language specification](index.md)</sub>

# 5. The standard library

## 5.1 What ships, and how

`String` is built into the compiler, because the runtime owns its layout and
its allocation. Everything else -- the rest of `String`, `StringBuilder`, and
every other module -- is ordinary Stainless compiled alongside your program.

**A generic that nobody instantiates costs nothing**, because there is nothing
to emit until it is instantiated. That covers `List<T>`, `Dictionary<TKey, TValue>`,
`Mutex<T>`, every container and every concurrent one.

**A module is compiled only if the program reaches it**: by an `import`, or by
a qualified name such as `Standard.Json.Parse` that spells it, from the program
or from a module that was itself reached. `Standard`, `Standard.Text`,
`Standard.Collections` and `Standard.Bits` are always reached, because the
compiler relies on them without an import. Every file of the library is lexed, which is what finding
the qualified names costs; nothing else of an unreached module is paid for.

**Within a reached module, a non-generic function or class is emitted whether or
not it is used.** Nothing prunes below the module: there is no reachability pass
from `Main`. What saves the binary is LLVM and the linker. Everything not
exported has internal linkage, so an optimised build deletes what nothing
references before optimising it, and every function goes in a section of its
own for the linker to drop.

| Module | Contents | Imported |
|---|---|---|
| `Standard.Text` | `String`, `StringBuilder`, `Utf16String`, conversions | automatically |
| `Standard.Console` | `Write`, `WriteLine`, `WriteError`, `ReadLine`, `ReadToEnd` | on request |
| `Standard.Collections` | the interfaces below, and every container | on request |
| `Standard.Concurrent` | the containers several threads may share | on request |
| `Standard.Threading` | `Mutex<T>`, atomics, the job pool | on request |
| `Standard.Math` | arithmetic that is not an operator | on request |
| `Standard.Bits` | counting bits and rotating them, as the target's own instructions | on request |
| `Standard.Limits` | what each number type holds, named rather than spelled | on request |
| `Standard.Reflection` | `[Reflect]`, `typeof`, the field tables | on request |
| `Standard.IO` | streams, `IOError`, and the readers and writers over them | on request |
| `Standard.IO.Compression` | deflate, gzip and zlib, as streams and one-shot calls ([§5.9.2](#592-standardiocompression)) | on request |
| `Standard.File` | whole-file operations | on request |
| `Standard.Directory` | making, removing and listing | on request |
| `Standard.Path` | taking paths apart, by the platform's rules | on request |
| `Standard.Ascii` | what one byte is, when ASCII is the honest answer | on request |
| `Standard.Encoding` | `IEncoding` and the six encodings ([§3.6](03-text.md#36-other-encodings)) | on request |
| `Standard.Convert` | base64, hex and number parsing ([§3.7](03-text.md#37-conversions)) | on request |
| `Standard.Process` | running another program, and signals ([§5.9.1](#591-standardprocess)) | on request |
| `Standard.Json` | JSON, as a document or onto a type ([§5.10](#510-standardjson-and-standardxml)) | on request |
| `Standard.Xml` | XML, in the same two layers ([§5.10](#510-standardjson-and-standardxml)) | on request |
| `Standard.Resources` | what a `.rc` folded into the binary, read back on every platform ([section 2.3 of packages.md](../packages.md#23-resources)) | on request |
| `Standard.Net` | TCP and UDP sockets, the same on every platform: a connect tries every address a name resolves to, within a limit if given; an accepted socket blocks whatever its listener does; no socket is inherited by a child process; a UDP receive is not failed by an earlier send to a closed port | on request |
| `Standard.Net.Security` | TLS 1.3 and 1.2, client and server, over any stream ([§5.17](#517-standardnetsecurity)) | on request |
| `Standard.Net.Http` | an HTTP/1.1 and HTTP/2 client: pooled and multiplexed connections, redirects, cookies, decompression, proxies ([§5.18](#518-standardnethttp)) | on request |
| `Standard.Env` | the command line, the environment, the working directory | on request |
| `Standard.Time` | `DateTimeOffset`, `TimeSpan`, `DateTime` and the monotonic `Stopwatch` | on request |
| `Standard.Random` | xoshiro256**, seeded by you or by the operating system | on request |
| `Standard.Drawing` | raster images: decode, draw, encode ([§5.12](#512-standarddrawing)) | on request |
| `Standard.Security.Cryptography` | hashes, MACs, key derivation, AES, ChaCha20-Poly1305, X25519, Ed25519, ECDSA and ECDH, RSA, PEM ([§5.13](#513-standardsecuritycryptography)) | on request |
| `Standard.Security.Cryptography.X509Certificates` | certificates, host names, chains, the root store, making certificates ([§5.16](#516-standardsecuritycryptographyx509certificates)) | on request |
| `Standard.Formats.Asn1` | ASN.1 in BER and DER, read and written ([§5.15](#515-standardformatsasn1)) | on request |
| `Standard.Media.Audio` | playing and recording sound ([§5.14](#514-standardmediaaudio)) | on request |
| `Standard.Com` | `IUnknown`, the HRESULTs a com method returns, and `GetClassObject` and `CanUnloadNow` for a server ([section 8.5](08-interop-libraries.md#85-com)) | on request |
| `Standard.ObjC` | `AnyObject`, `Selector` and `Class`, and `WithAutoreleasePool`, for Objective-C on macOS ([section 8.6](08-interop-libraries.md#86-objective-c)) | on request |
| `Standard` | `Result<T, TError>`, `[Flags]`, and the rest of what the language itself reads | automatically |

### 5.1.1 What `Standard` holds

`Standard` is imported everywhere, so what is in it is the language's own
vocabulary: `Optional`, `Result`, `Index`, `Range`, `Span<T>` and
`ReadOnlySpan<T>` ([§2.12](02-types.md#212-spant-and-readonlyspant--part-of-an-array)),
the `Func`, `Action`, `Predicate` and `Comparison` a lambda becomes, and C#'s
everyday values:

| | |
|---|---|
| `Guid` | 128 bits, laid out as COM's `GUID` so a `Guid*` is what a COM function takes; `NewGuid`, `CreateVersion7`, `Parse` and the `N`, `D`, `B` and `P` formats; `ToByteArray` in .NET's byte order |
| `Version` | two to four parts, `Parse`, ordered part by part with a missing part first |
| `Uri` | RFC 3986: kept normal, resolved against a base, escaped and unescaped; `Host`, `Port`, `AbsolutePath`, `Segments`, `MakeRelativeUri`, `IsBaseOf`; a Windows or UNC path reads as a `file:` URI |
| `Lazy<T>` | made on first ask, once, with C#'s three `LazyThreadSafetyMode`s |
| `Array` | .NET's `System.Array`: `Create(count, (i) => ...)` and `Repeat(value, count)`, which make an array whole ([section 2.16.3](02-types.md#2163-arrays)); `Empty`, `Copy`, `Fill`, `Reverse`, `Resize`, `ConvertAll`, `AsReadOnly` as a `ReadOnlySpan`; `IndexOf`, `LastIndexOf`, `BinarySearch`, `Exists`, `Find`, `FindIndex`, `FindLast`, `FindLastIndex`, `FindAll`, `TrueForAll`, `ForEach` and a stable `Sort`, the searches and sorts with .NET's index-and-count ranges. A search answers with an `Optional`, and `Clear` and `Resize` without a fill need `where T : zeroable` |
| `Buffer` | .NET's `System.Buffer`: `BlockCopy`, `ByteLength`, `GetByte`, `SetByte` over arrays of an `unmanaged` type ([section 4.3](04-generics.md#43-what-a-constraint-does-and-does-not-do)), in bytes and bounds-checked, and `MemoryCopy` between pointers |
| `RuntimeHelpers` | `IsReferenceOrContainsReferences<T>()`, a constant per instantiation ([§4.3](04-generics.md#43-what-a-constraint-does-and-does-not-do)) |
| `Slot<T>` | storage for a `T` that may not be there yet, empty at zero, so `new Slot<T>[n]` is legal for every `T`: written by assigning a `T`, read through `Value`, emptied by `Clear`; `ToArray` and `Copy` move values in and out. The size of `T`, and a read of an empty one aborts when `T` has no zero value ([section 2.16.3](02-types.md#2163-arrays)) |

Each parses into a `Result` with a `ParseError` rather than throwing, and a
constructor given what cannot be one aborts, as C#'s throws.

## 5.2 `Standard.Threading`

Locks, atomics and a job pool, over the runtime in
[runtime/thread.c](../../runtime/thread.c). It needed no new syntax: generic
classes carry the lock, destructors release it, and `delegate` carries the work.

```csharp
import Standard.Collections;
import Standard.Threading;

static readonly Mutex<List<String>> Registry =
    new Mutex<List<String>>(new List<String>());

void Record(String name)
{
    var guard = Registry.Enter();
    guard.Value.Add(name);
}                                   // ~Guard() unlocks, including on a return
```

The mutex **owns what it guards**, so there is no way to reach the value
without holding the lock and no way to forget which lock guards what. `lock
(obj) { }` was rejected for the opposite reason: it would put a lock word in
every object header and charge every single-threaded program for it.

**What `Value` still does not promise.** It hands out what the lock protects,
and nothing stops the caller keeping it after the guard has gone. That is a
lifetime question, and Stainless does not answer it yet; C# has the same hole
and Rust closes it with lifetimes.

**The count is safe.** `Value` retains what it returns and the
caller releases it, usually outside the lock, and reference counts are atomic,
so two threads doing that do not race on the count; see
[section 10 of concurrency.md](../concurrency.md#10-what-exists-today) for why the
narrower rule of "atomic counts for `threadsafe` types" would not do.

`AtomicInt`, `AtomicLong` and `AtomicBool` are sequentially consistent counters
and flags. They are concrete rather than `Atomic<T>` because atomics are not
generic — that would need a constraint saying `T` is an integer, and no
constraint ([§4.3](04-generics.md#43-what-a-constraint-does-and-does-not-do)) says that.

`Thread` and `Future<T>` are the unstructured pair, for work with no lexical
scope to be bracketed by. Both take a closure, which is what makes them safe to
hand something: capture is by value, so the body owns a copy rather than
borrowing a frame it might outlive.

```csharp
var writer = new Thread(() => Drain(queue));    // ~Thread() joins; Detach() lets go

var answer = new Future<int>(() => Compute(input));
// ... something else worth doing ...
int value = answer.GetResult();     // blocks until the value is there
```

A `Future<T>` is a future with no `async` in sight. `GetResult` is a condition wait
rather than a coroutine suspension, so no signature changes colour and there is
no state machine — which is what blocking being permitted buys. It costs one
detached thread per future, since there is no scope to pool against, and it is
the right reach only when the result has to outlive the frame that asked for it;
a `parallel` block is better wherever one fits, and `for parallel` is better
than both for data.

`TaskScope` runs `Job` delegates on the pool and joins them:

```csharp
var scope = new TaskScope();
scope.Run(Work, (byte*)shared);
scope.Join();                       // ~TaskScope() joins too, as a backstop
```

**Two things this is not.** A `TaskScope` job takes a `byte*` and casts it back,
so nothing checks what crosses that particular boundary — unlike `spawn`, where
[§9.5](09-statements-expressions.md#95-what-may-cross-a-thread-boundary) applies; and keeping a `Guard` alive is a discipline, not a guarantee. See [concurrency.md](../concurrency.md) for the model these are aiming
at and which parts of it the compiler does not yet enforce.

This module is not free when unused: `AtomicLong`, `AtomicBool`, `TaskScope` and the rest
are ordinary classes rather than templates, so their code is emitted whether or
not a program mentions them. That is true of every non-generic declaration in
the standard library, and [§5.1](#51-what-ships-and-how) says what it costs and why nothing prunes it.

## 5.3 Interfaces are named with a leading I

`IComparable<T>`, `IReadOnlyList<T>`, `IEnumerable<T>` — the C# convention, and
the one the standard library follows. It is a convention, not a rule the compiler
enforces.

## 5.4 `Standard.Collections`

```csharp
public interface IEquatable<in T>  { bool Equals(T other); }
public interface IComparable<in T> { int CompareTo(T other); }
public interface IHashable         { nuint GetHashCode(); }

public interface IReadOnlyList<out T> : IEnumerable<T>
{
    nuint Count { get; }
    bool IsEmpty { get; }
    T this[nuint index] { get; }
}

public interface IList<T> : IReadOnlyList<T>
{
    T this[nuint index] { get; set; }
    void Add(T item);
    void RemoveAt(nuint index);
    void Clear();
}
```

`CompareTo` returns a negative number, zero, or a positive number when the
value orders before, with, or after the argument.

**A primitive, an enum and a String implement all three without saying so.**
None of them can carry a declaration — a primitive is not a class, an enum is
its integer, and `String` belongs to the runtime — but they are exactly the
types people sort by and use as keys, so a rule that excluded them would
exclude the point of having constraints. The compiler recognises `CompareTo`,
`Equals` and `GetHashCode` on those types and lowers each to a comparison or a
runtime call:

```csharp
var numbers = new List<int>();
Sort(numbers);                          // int satisfies IComparable<int>

var ages = new Dictionary<String, int>();
ages.SetValue("ada", 36);               // String satisfies IEquatable + IHashable

3.CompareTo(5);                         // -1
"apple".CompareTo("banana");            // -1, by bytes, which for UTF-8 is by code point
```

**A float's `Equals` is `CompareTo`'s equality, not `==`.** NaN equals NaN
and `-0.0` equals `0.0`, which is what lets a NaN key be found in a
`Dictionary<double, …>` at all. The operator keeps IEEE's answer, so
`nan == nan` is still false.

A class still says what it implements, and a declared member always wins over
the built-in one.

**The containers**

| Type | Backed by | Notes |
|---|---|---|
| `List<T>` | one array, doubling | `IList<T>`, `IEnumerable<T>`; `list[i]` |
| `Dictionary<TKey, TValue>` | open addressing | `TKey : IEquatable<TKey>, IHashable`; iterates `KeyValuePair<TKey, TValue>`; `map[k]` -> `Optional<TValue>` |
| `HashSet<T>` | open addressing | `UnionWith`, `IntersectWith`, `ExceptWith` |
| `Queue<T>` | circular buffer | `Enqueue`, `Dequeue`, `Peek` |
| `Stack<T>` | one array | `Push`, `Pop`, `Peek` |
| `LinkedList<T>` | an index pool | handles, not references — see below |
| `SortedList<TKey, TValue>` | two sorted arrays | `TKey : IComparable<TKey>`; binary search, ordered iteration |

`List<T>` carries an indexer ([§7.5](07-functions-members.md#75-indexers)), so `list[i] += 1` reads and writes the
way an array does, and `IReadOnlyList<T>` and `IList<T>` declare the same
indexer.

**A dictionary's indexer answers `Optional<TValue>`**, which is Swift's design and
right for the same reason. An index is a position the caller worked out, so
`list[i]` out of range is the same mistake `array[i]` is. A key is data that
arrived from a file, a socket or a person, so a key that is not there is an
ordinary outcome rather than a mistake in the program — the line [§2.6](02-types.md#26-variant--a-value-that-is-one-of-several-things) draws
between a value to return and a reason to stop. An indexer returning `TValue` would
have to stop, and `map[key]` carries no verb to warn anyone that it might.

```csharp
if (settings["timeout"] is Some found)
    Use(found.Value);
int port = settings["port"].GetValueOrDefault(8080);
```

A getter and a setter share one type ([§7.5](07-functions-members.md#75-indexers)), so the setter takes an
`Optional<TValue>` as well. That says something rather than costing something: a
value promotes to the optional holding it, so an ordinary write reads as one,
and `None` is the absence of a value, which is what removing a key means.

```csharp
settings["retries"] = 3;             // set
settings["retries"] = None;          // remove
```

What it cannot do is `map[key] += 1`, because there is nothing to add to when
the key is absent. That is the question being asked out loud rather than a
limitation: `map[key] = map[key].GetValueOrDefault(0) + 1` says what should happen, and
Swift's `dict[key, default: 0] += 1` exists for the same reason.

The named forms remain, each saying which question it asks:

| | |
|---|---|
| `map[key]`, `TryGetValue(key)` | `Optional<TValue>`, and **what to reach for** |
| `GetValueOrDefault(key, fallback)` | the value or a default |
| `ContainsKey(key)` | whether it is there |
| `GetValue(key)` | the value, **aborting** when there is none |

`TryGetValue` costs one probe where `ContainsKey` then `GetValue` costs two, and it has no
sentinel to collide with a real value the way `GetValueOrDefault` does. `GetValue` is the
asserting form and it asserts: use it where the key is there by construction.
`SortedList<TKey, TValue>` answers the same ways, minus the indexer.

Every one of them is **walked in place when iterated**, so iterating a queue
allocates nothing rather than a whole `List<T>` built before the first step.

Every one of them is array-backed, which for the last two is not the usual
choice. It is the right one here: ARC cannot collect a cycle, so a doubly
linked list of objects would leak unless every back-link were weak, and a weak
reference is not usable without a way to prove it is still there. Links as
indices into a pool have neither problem.

`Dictionary` and `HashSet` probe linearly and **shift the following cluster
back on removal rather than leaving a tombstone**, so a table that is added to
and removed from for a long time does not slowly fill with markers that only a
rehash could clear.

`LinkedList<T>` names each node with a **handle**: a `nint` that stays valid
until that node is removed, and is `-1` for "no node". Handles are what make
the middle of the list reachable in constant time, which is the only reason to
choose it over a `List<T>`:

```csharp
var line = new LinkedList<String>();
var first = line.AddLast("a");
line.AddLast("c");
line.InsertAfter(first, "b");

for (nint at = line.First; at >= 0; at = line.GetNext(at))
{
    Console.WriteLine(line.GetValueAt(at));
}
```

`OrderedDictionary<TKey, TValue>` keeps the order its keys were added in and finds one
by scanning rather than hashing. That is the whole difference from
`Dictionary`, and it is the right trade wherever the order is part of the data
— a parsed document read back the way it was written, a configuration a person
edits. It is a scan, so it is for the sizes documents actually are; something
large enough for O(n) lookup to hurt wants a `Dictionary` beside it as an
index. `Standard.Json`'s object members and `Standard.Xml`'s attributes are
both one of these.

Asking a container for something it does not have — `GetValue` with an absent key,
`Dequeue` on an empty queue — aborts, the same way an out-of-range index does.
Use `GetValueOrDefault`, `ContainsKey` or `IsEmpty` where a miss is an ordinary outcome.
`OrderedDictionary.IndexOf` answers with an `Optional<nuint>` ([§2.8.1](02-types.md#281-optionalt--a-value-or-none)), which is
the one that needs no rule to be remembered.

Alongside the containers are `Max`, `Min`, `IndexOf` and `Sort`, each
constrained to what it actually needs:

```csharp
import Standard.Collections;

public class Money : IComparable<Money>, IEquatable<Money>
{
    int cents;
    public int CompareTo(Money other) { ... }
    public bool Equals(Money other)  { ... }
}

var prices = new List<Money>();
prices.Add(new Money(250));
prices.Add(new Money(40));

Sort(prices);                       // needs IComparable<Money>
Max(prices);                        // and works on any IReadOnlyList
```

`Sort` takes an `IList<T>`; `Max`, `Min` and `IndexOf` take an
`IReadOnlyList<T>`, so they accept a mutable list without being able to change
it.

## 5.5 Doing something to every element

A lambda becomes a `closure` ([§2.15](02-types.md#215-lambdas-and-closures)), so the
combinators need no special case in the compiler — they are ordinary generic functions over ordinary generic closures.

```csharp
public closure TResult     Func<in T, out TResult>(T value);
public closure bool        Predicate<in T>(T value);
public closure void        Action<in T>(T value);
public closure TAccumulate Fold<TAccumulate, in TSource>(TAccumulate total, TSource value);
public closure int         Comparison<in T>(T left, T right);
```

These five, with `Func` and `Action` of up to four parameters, are declared in
`Standard` rather than here, so they need no import:
they are what [§2.15](02-types.md#215-lambdas-and-closures) says a lambda may become, rather than anything a collection
owns, and `Optional.Select` ([§2.8.1](02-types.md#281-optionalt--a-value-or-none)) wants them too.

**They are closures rather than one-method interfaces**, and the difference is
not cosmetic. An interface needs an object that implements it, so
passing a method that already existed would mean writing a class whose only purpose
would be to carry it:

```csharp
ForEach(lines, report.Note);        // a method bound to an object
ForEach(lines, (l) => log.Add(l));  // or a lambda that captures
```

Both are the same two words ([§2.14.1](02-types.md#2141-closure--a-method-and-the-object-it-belongs-to)), and neither needs a declaration to hold
it.

```csharp
var adults = Where(people, p => p.Age >= 18);
var names  = Select(adults, p => p.Name);
long total = Aggregate(numbers, (long)0, (sum, n) => sum + (long)n);

Sort(people, (a, b) => a.Age - b.Age);
```

LINQ's operators, each over a `ReadOnlySpan<T>` — which an array and a
`Span<T>` convert to — and over any `IEnumerable<T>`, named as LINQ names
them, so a reader arriving from C# has nothing to translate:

| | |
|---|---|
| filtering and shaping | `Where`, `Select`, `SelectMany`, `Distinct`, `DistinctBy` |
| one element | `First`, `Last`, `Single` and their `OrDefault` forms, `ElementAt`, `ElementAtOrDefault`, and over a span only `Find` and `FindIndex` |
| asking | `Any`, `All`, `Count`, `Contains`, `SequenceEqual` |
| reducing | `Sum`, `Average`, `Min`, `Max`, `MinBy`, `MaxBy`, `Aggregate` |
| ordering | `OrderBy`, `OrderByDescending`, `Order`, `OrderDescending`, then `ThenBy` and `ThenByDescending` |
| grouping and gathering | `GroupBy`, `ToDictionary`, `ToHashSet`, `ToList`, `ToArray` |
| cutting | `Take`, `Skip`, `TakeWhile`, `SkipWhile`, `TakeLast`, `SkipLast`, `Chunk` |
| joining and comparing | `Concat`, `Append`, `Prepend`, `Zip`, `Union`, `Intersect`, `Except` and their `By` forms |
| making | `Enumerable.Range`, `Enumerable.Repeat`, `Enumerable.Empty` |

Where C# throws — `First` of nothing, `Single` of two, `Average` of nothing,
`ToDictionary` given a key twice — these abort, as an index out of range
does, and an integer `Sum` is `checked`. An `OrDefault` form takes the value to
answer instead, since a struct has no null. `Sum` and `Average` come for
`int`, `long`, `float` and `double`, each with a selector form, and a lambda
picks between those by what it returns
([§4.4](04-generics.md#44-what-is-and-is-not-supported)). `OrderBy` answers
with an `OrderedList<T>`, a `List<T>` that remembers its order so that
`ThenBy` can break its ties; `GroupBy` with `Grouping<TKey, T>`s, each a
sequence with its `Key`, in the order their keys were first met.

**`Find` and `FindIndex` answer with an `Optional`** ([§2.8.1](02-types.md#281-optionalt--a-value-or-none)), and so does
`Collections.IndexOf`: a length standing in for "not there" is the sentinel
that type exists to retire, and `Optional`'s own documentation names `IndexOf`
as the example. `FirstOrDefault` is still there for the caller who has a sensible
default and nothing to check. So do `List.Find` and `List.FindLast`, where
.NET's answer `default(T)`, and `MinBy` and `MaxBy`, which answer `None` for an
empty sequence rather than aborting: a `T` that is never null has no default to
answer with ([§2.16](02-types.md#216-zero-values)).

`RemoveWhere(list, predicate)` removes every item the predicate accepts.
A predicate rather than a value, which is what makes it work for a `T` that
implements nothing: a `closure` is not `IEquatable`, so a list of callbacks
could not be removed from by value at all. `RemoveFirst(list, value)` is the
`IEquatable` version beside it.

**Eager, not lazy.** Every one walks its input to the end and returns a
`List<T>`, so `Where` then `Select` builds two lists. Lazy chaining wants
generators, and there is no `yield` here; a name borrowed from a language that
has one would imply otherwise.

**Spans have C#'s `MemoryExtensions` here** — `IndexOf`, `Contains`,
`SequenceEqual`, `StartsWith`, `Trim` and the rest, listed in
[§2.12](02-types.md#212-spant-and-readonlyspant--part-of-an-array) — taking a
`ReadOnlySpan<T>` where they read and a `Span<T>` where they write, and a call
written on a span or an array reaches them.

**Sorting is a stable merge sort**, over a `Span<T>` or an `IList<T>`, either by
`IComparable<T>` or by a `Comparison<T>` given at the call. Stability is the
property worth the scratch array it costs: sorting by one key and then another
is how a multi-key order gets built, and that only works if the second sort
leaves equal elements where the first put them. An in-place quicksort would
save the allocation and lose that.

`BinarySearch` finds a value in an ordered slice, answering with an
`Optional<nuint>` as `IndexOf` does. `FindLowerBound` returns where it would go
instead — two functions rather than C#'s one negative number, because a caller
usually wants one answer or the other.

## 5.6 `Standard.Env`, `Standard.Time` and `Standard.Random`

**A program reads its command line through `Main`.**

```csharp
int Main(String[] args)
{
    if (args.Length < 1u) { Console.WriteError("usage: wc <file>"); return 2; }
    ...
}
```

`Main` takes either nothing or a `String[]`, and nothing else (SL0282). The
array holds the arguments only — the program's own name is `Env.GetProcessPath()`,
because it is not one of them and treating it as one is the mistake C's argv
invites. `Standard.Env` reaches the same list from anywhere, which is for code
that is nowhere near `Main`; taking the array as a parameter is better where it
is possible.

`Env` also has variables and the working directory. **An empty value is a
value**: `SetEnvironmentVariable(name, "")` leaves the variable set and empty on
both platforms, `GetEnvironmentVariable` then answers `""` rather than null,
and `GetEnvironmentVariableOrDefault` answers its fallback only for a variable
that is not set. `RemoveEnvironmentVariable` is how one is unset.

**`Standard.Time` keeps two kinds of time apart, because confusing them is the
usual bug.** A `DateTimeOffset` is a point on the wall clock and can jump — a
user sets it, NTP corrects it, a laptop wakes. A `TimeSpan` is a length, and
`Stopwatch` reads a **monotonic** counter that only goes forward:

```csharp
var clock = new Stopwatch();
DoTheWork();
Console.WriteLine(clock.Elapsed.Format());
```

Subtracting two `DateTimeOffset`s to measure something is the thing not to do,
and is why the timing type is a separate one. Both are structs over a single
`long` of nanoseconds, so they cost nothing, and both declare the operators
that go with that: `hour + minute` is a `TimeSpan`, `later - earlier` is the
`TimeSpan` between two points, and `point + span` is another point. Adding two
points is not defined, because the sum of two dates is not a date.

They are made by naming the unit — `TimeSpan.FromSeconds(30)`,
`DateTimeOffset.FromUtc(...)` — rather than by a free function, since a bare
count of nanoseconds at a call site says nothing about which unit was meant.

`TotalSeconds` and the rest are doubles that keep the fraction, as .NET's are.
A caller counting whole units casts, which is also the only spelling that says
which way it wanted the remainder to go.

The UTC calendar is computed rather than delegated to `gmtime`, because the
platforms disagree about the past: Windows refuses a negative `time_t`, so
it has no answer for a date before 1970. Local time still asks the platform,
which is the only thing that knows the zone rules.

**`Standard.Random` is a class, not a set of functions.** The state has to live
somewhere, and a hidden one shared by every caller is what makes a program
impossible to replay — so it lives in an object the caller holds. A
`Random(seed)` repeats exactly, on any machine; a `Random()` is seeded by the
operating system and does not. (The language has a mutable static to put such
a thing in, and that is the reason not to.)

It is **not cryptographic** — xoshiro256** is fast and its whole future
follows from its state, which is what makes a seeded run reproducible and what
makes it unfit for a key. `Random.FillSecureBytes` goes straight to the platform's
source for that.

### 5.6.1 Dates, times of day and time zones

`DateOnly` and `TimeOnly` are C#'s: a Gregorian date from 0001-01-01 to
9999-12-31, and a time of day to the nanosecond, each a struct that sorts and
keys a set. Both are written and read as ISO 8601 — `2026-09-30`, `14:30:00` —
rather than in a culture's form, and a date that does not exist, or an hour of
24, aborts where C# throws. `DayOfWeek` is an `int`, 0 for Sunday, as
`DateTime.DayOfWeek` is.

**`TimeZoneInfo` is the platform's zones.** On Linux and macOS it reads the IANA
database from `/usr/share/zoneinfo` (or `TZDIR`) itself, TZif file and POSIX
rule both, and names each zone as that database does. On Windows it asks the
system for each zone's rule by the year, and names zones by their registry
keys; an IANA name finds the zone it maps to through the ICU that Windows 10
carries, as `TryConvertIanaIdToWindowsId` does.

```csharp
if (TimeZoneInfo.FindSystemTimeZoneById("Europe/Paris") is Ok paris)
{
    DateTime there = TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, paris.Value);
    TimeSpan offset = paris.Value.GetUtcOffset(DateTimeOffset.UtcNow);
}
```

`DateTimeOffset` here is an instant with no offset of its own, so what a zone
converts one to is the `DateTime` its clocks read, where C# answers with a
`DateTimeOffset` carrying the offset. The other way, `ConvertTimeToUtc`, is a
`Result`: a wall-clock time the zone skips is `TimeError.Invalid`, where C#
throws, and one it reads twice is taken as standard time, as C# takes it.
`IsInvalidTime` and `IsAmbiguousTime` ask the same thing without converting.

## 5.7 `Standard.Math`

```csharp
import Standard.Math;

Math.Sqrt(2.0);
Math.Clamp(x, 0, 10);
Math.GreatestCommonDivisor(48, 18);
```

A module is a scope, so this needs no static class to live in: `Math.Sqrt(x)`
is a module-qualified call. The floating-point functions are the C library's,
declared and called directly — there is no wrapper layer and no conversion,
because a Stainless `double` *is* a C `double`.

`Min`, `Max` and `Clamp` are overloaded across `int`, `long`, `nuint` and
`double`, and `Abs` and `Sign` across `int`, `long` and `double`, resolved by
argument type. Alongside them are the usual
transcendentals, `Floor`/`Ceiling`/`Round`/`Truncate`, `IsNaN`/`IsInfinity`/
`IsFinite`, `Lerp` and `IsNear`, `RadiansToDegrees` and `DegreesToRadians`, the integer
`GreatestCommonDivisor`, `LeastCommonMultiple` and `DivideCeiling`, `BigMul` for
the whole product of two integers (a 64-bit one from two 32-bit ones, and the
high half of a 128-bit one with the low half in an `out`). The bit functions --
`PopCount`, `LeadingZeroCount`, `TrailingZeroCount`, `IsPowerOfTwo`,
`RoundUpToPowerOfTwo` and the rotates -- are `Standard.Bits`'.

`Round` takes halves away from zero, which is C's rule rather than the banker's
rounding C# uses by default.

## 5.8 `Standard.Concurrent`

```csharp
import Standard.Concurrent;

var work = new ConcurrentQueue<int>();
parallel
{
    spawn Fill(work, 0, 500);
    spawn Fill(work, 500, 1000);
}

var got = work.TryDequeue();
if (got is Some held)
    Console.WriteLine(Text.FromInteger(held.Value));
```

`ConcurrentQueue<T>`, `ConcurrentStack<T>`, `ConcurrentDictionary<TKey, TValue>` and
`Channel<T>`, each `threadsafe` and each safe for several threads at once.

Every operation that takes something out returns an `Optional<T>`
([section 2.8.1](02-types.md#281-optionalt--a-value-or-none)) -- whether there was
anything, and what it was — rather than answering in two calls. There is no
`Peek` and then `Dequeue`, because between the two another thread may have
taken it. `DequeueOrDefault(fallback)` and `PopOrDefault(fallback)` answer the
fallback instead, for a caller that need not tell an empty container from a
stored fallback.

`Channel<T>` is the producer-consumer hand-off: `Take` **blocks** until
something arrives or the channel is closed, and `Close` wakes every waiter.
What was already sent is still delivered; once it is drained, every `Take`
returns `None` at once.

**Each of these owns an ordinary collection in a field and never hands out a
reference to it.** Reference counts are atomic, so this is not what keeps a
count right; it is still the right shape -- reading a field to call a method on
it borrows, and a container that never hands its collection out cannot be used
wrongly by a caller who keeps what it lent.

## 5.9 `Standard.IO`, `File`, `Directory` and `Path`

```csharp
import Standard.File;
import Standard.IO;

var read = File.ReadAllText("config.json");
if (read.Ok) { Console.WriteLine(read.Value); }
else         { Console.WriteError(IO.DescribeIOError(read.Error)); }
```

A module is what C# uses a static class for, so what C# spells
`File.ReadAllText` is a module-qualified call to a module-level function. That is the mapping
throughout: a module is the static class. What lives on a type instead is what
*makes* one: `FileStream.Open` and its shorthands ([§7.6](07-functions-members.md#76-static-members)), because a constructor
cannot report why an open failed.

**How failure is reported.** Stainless does not unwind ([§2.8](02-types.md#28-resultt-terror--how-a-function-fails)), so the outcome
comes back as a value, in one of three shapes:

| Shape | Used by | Reads as |
|---|---|---|
| `Result<T, IOError>` | anything that produces a value | `if (r.Ok) { r.Value }` |
| `IOError` | anything that does not | `if (File.Delete(p) != IOError.None)` |
| the stream's own `Error` | streams | checked after a loop, not each step |

Three shapes rather than one is deliberate: a single shape makes the common
cases read worse than the rare one. There is no failed value to read by
mistake — `Value` does not compile until the check has happened — and a caller
that would rather carry on writes `read.GetValueOrDefault("")`.

**Streams.** `IStream` is `Read`/`Write`/`Seek`/`Length`/`Position`/`Flush`/
`Close` plus `CanRead`/`CanWrite`/`CanSeek` and `Error`. `FileStream` and `MemoryStream`
implement it.

```csharp
var file = try FileStream.OpenRead("data.bin");
var whole = IO.ReadTextToEnd(file);
file.Close();
```

`FileStream.Open` and its three shorthands are the way to make one, and the
constructor is private ([§2.9](02-types.md#29-how-the-library-reports-failure)): a constructor cannot say why an open failed, and
the best it could do would be to hand back a stream holding nothing. `IsOpen` and
`Error` remain for what happens *after* it is open. Closing is the
destructor's job, so a stream that goes out of scope releases its handle
whether or not `Close` was called.

Opening takes a `FileMode` (`Open`, `Create`, `Append`) and a `[Flags]`
`FileAccess` (`None`, `Read`, `Write`, `ReadWrite`).

**`File`** has `Exists`, `GetSize`, `GetLastWriteTime`, `Delete`, `Move`, `Copy`,
and the whole-file pairs `ReadAllText`/`WriteAllText`,
`ReadAllBytes`/`WriteAllBytes`, `ReadAllLines`/`WriteAllLines`, and
`AppendAllText`. The openers are `FileStream`'s.

**`Directory`** has `Exists`, `CreateDirectory`, `CreateDirectoryTree`, `Delete`,
and the listings `GetEntries`, `GetFiles`, `GetDirectories` and `GetAllFiles`.
Listings return full paths rather than bare names, in the platform's order;
`GetEntries` answers an `Entry` for each, with its `Path`, `Name` and
`IsDirectory`.

**`Path`** is purely textual and touches no disk: `Join`, `GetFileName`,
`GetDirectoryName`, `GetExtension`, `GetFileNameWithoutExtension`,
`ChangeExtension`, `IsPathRooted`, `IsSamePath` and `SplitPath`. Both `/` and `\` are accepted when reading a path apart, because
Windows accepts both and a path from a config file may use either.

**Paths are UTF-8, and stay correct.** A Stainless `String` is already UTF-8,
and on Windows the runtime widens every path to UTF-16 before it reaches the
operating system — the narrow CRT entry points would read those bytes in the
active code page, which works by accident for ASCII and fails for everything
else.

### 5.9.1 `Standard.Process`

```csharp
var done = try RunProcess("git", ["rev-parse", "HEAD"]);
if (done.Succeeded)
    Console.WriteLine(done.StandardOutput.Trim());
```

Running another program, on both platforms, with the same answers.

**There is no shell**, and there is no overload that takes one command line to
be split. The program and its arguments are a list, so a `>`, a `|` or a space
in a filename is a character the child receives rather than something a shell
acts on. That is the whole of shell injection, designed out rather than warned
about.

**A failure to start and a failure of the program are different things.**
`ProcessError` is only about starting -- `NotFound`, `Denied`, `NoResource`,
`Failed` -- and a program that ran and returned 1 is a `ProcessResult` with
`ExitCode` 1, which
is an outcome rather than a fault. `grep` answering 1 for "no match" is the
ordinary case.

Telling those apart takes work on POSIX, and it is worth knowing why. A child
cannot report a failed exec through its exit code: 127 is the shell's
convention for "could not run it" and is also a perfectly ordinary code a real
program might return. So the child is given a close-on-exec pipe and writes
`errno` into it; a successful exec closes it and the parent reads end-of-file.
One pipe, one read, and `RunProcess("/no/such/thing", [])` says `NotFound` while
`RunProcess("sh", ["-c", "exit 127"])` says the program ran and answered 127.

**Both streams are drained while the child runs.** A pipe holds about 64KB, so
a parent that waits for the child before reading waits forever on a child that
writes more — and reading one stream to the end while the child fills the other
is the same deadlock in a different order. `poll` does it on POSIX and
`PeekNamedPipe` on Windows.

**Input is written while the output is read**, for the same reason from the
other side: a filter stops reading once its output pipe is full, so a parent
that wrote all of its input first would wait on it forever. POSIX writes it
from the same `poll`; Windows, which cannot poll an anonymous pipe for room,
from a thread. Without input the child reads end of input at once rather than
the parent's own.

`StandardOutput` and `StandardError` are kept apart, so a program that prints progress to one
does not corrupt what was captured from the other.

**`Start` hands back a `Process`** for a program to be waited on later, or
asked whether it has finished, or stopped. Its streams are the parent's. A
`Process` let go of is reaped, by its destructor or, if it is still running,
when it exits, so nothing is left a zombie; it is not killed, letting go saying
nothing about wanting it stopped.

`Stop` is `SIGTERM` and `Kill` is `SIGKILL`. On Windows both are
`TerminateProcess`: there is no polite signal for a process that is not a
console group of its own, and saying so is better than pretending `Stop` can be
gentle there.

**Signals are asked for rather than delivered.** A handler runs between two
instructions of whatever was executing, so almost nothing is legal inside one —
no allocation, no locks, and therefore no Stainless at all. `Signals.StartWatching()`
installs a handler that stores to a flag, and `Signals.Interrupted` reads it
where a program can act on it:

```csharp
Signals.StartWatching();
while (!Signals.Interrupted)
    DoAPieceOfWork();
```

### 5.9.2 `Standard.IO.Compression`

```csharp
import Standard.IO.Compression;

var file = try FileStream.OpenRead("log.gz");
var text = try IO.ReadTextToEnd(new GZipStream(file, CompressionMode.Decompress));

byte[] packed = Compression.CompressZLib(data, CompressionLevel.SmallestSize);
var unpacked = Compression.DecompressZLib(packed);      // Result<byte[], CompressionError>
```

RFC 1951, 1952 and 1950, in `System.IO.Compression`'s shape: `DeflateStream`,
`GZipStream` and `ZLibStream` wrap another `IStream`, made with a
`CompressionMode` or a `CompressionLevel` and a `leaveOpen` flag. A
compressing stream writes output as it fills and the final block and trailer
on `Close`; a decompressing one reads its source only when a symbol needs
bits. `Crc32` and `Adler32` are public, because zip and PNG want them too.

**Failure is the IO module's third shape.** A stream carries `Error`, and data
that breaks its format — a reserved block type, an over-subscribed or
incomplete code, a distance before the start, a stored length that disagrees
with its complement, a checksum or length that does not match — reads as
`IOError.InvalidData`, which is .NET's `InvalidDataException`. The exact
reason is a `CompressionError` in `CompressionErrorCode` beside it, as
`TcpClient` keeps the exact socket error beside the rounded one. Over memory
the data is the only thing that can be wrong, so the one-shot
`DecompressGZip`, `DecompressZLib` and `DecompressDeflate` return
`Result<byte[], CompressionError>`. Nothing a stream contains can make the
decoder abort, loop or read out of bounds.

**Decompressing reads ahead**, in blocks of 16 KiB, so bytes after the
compressed data on the same source may be consumed. For a file, or an HTTP
body behind a stream that stops at its length or its last chunk, that is
nothing; it is why raw deflate cannot be followed by other data on one
stream, as in .NET. Concatenated gzip members read as one stream.

The levels are zlib's: `Fastest` is greedy matching over chains of four,
`Optimal` lazy matching over 128, `SmallestSize` over 4096, and
`NoCompression` stored blocks. Each block is written as stored, fixed or
dynamic Huffman, whichever is smallest, with codes limited to fifteen bits.
On a megabyte of mixed data the sizes are within a percent of zlib's at each
level, in one and a half to four times the time.

## 5.10 `Standard.Json` and `Standard.Xml`

Both have the same two layers, and the split is the point.

**A document, which needs no type.** `Json.Parse` gives a `JsonValue` — a
variant that is exactly one of the six things JSON has — and `Xml.Parse` gives
an `XmlNode`. Reading the wrong case is a compile error rather than a null:

```csharp
var parsed = try Json.Parse(text);

switch (parsed)
{
    case Object held: Console.WriteLine(Json.GetTextOrDefault(held.Members.GetValueOrNull("name"), "?")); break;
    default: break;
}
```

**A mapping onto a type**, through the field tables of a `[Reflect]` type
([§6](06-attributes-reflection.md#6-attributes-and-reflection)). `Json.Serialize(value)` reads an object's fields and `Json.PopulateObject`
writes them, walking into a nested object rather than stopping at it.
`[JsonName("id")]` renames a field and `[JsonIgnore]` leaves it out; XML has
`[XmlName]`, `[XmlIgnore]` and `[XmlAttribute]`, which writes a field as an
attribute rather than as a child element.

**Reading fills an object rather than making one**, and that is the design
rather than a limitation:

```csharp
var settings = new Settings();          // the constructor establishes the type
Json.PopulateObject(settings, text);    // the document overwrites what it names
```

A constructor is what makes a type's invariants true. A deserializer that
allocated zeroed memory would hand back an object whose non-nullable fields
were null — a hole in the type system rather than a value — so the object comes
from the program and a field the document does not mention keeps what the
constructor chose. It is also why there is no `Deserialize<T>(text)` returning
a fresh `T`: making one means calling a constructor found through reflection,
and the metadata describes fields and properties but no constructor.

A value whose JSON type does not fit its field is **skipped**, not converted:
`{"Years": "40"}` leaves `Years` alone. Guessing at a conversion is how a
document silently becomes a different one.

**An array is walked; a `List<T>` is not.** Field metadata describes an
array's elements ([§6.6](06-attributes-reflection.md#66-writing-a-field)), so `String[]`, `int[]` and `Point[]` all round-trip.
A `List<T>` is a class whose own fields are its private storage and whose way
in is `Add`, which needs method metadata nothing emits — so it is omitted from
the document rather than written as `{}`, which is what a reader would have
believed. A type holding one wants the document layer, where a `JsonValue`
says exactly what is there.

**An array is filled, never replaced.** Its length is the one the constructor
chose: a document with more elements fills what fits and stops, one with fewer
leaves the rest alone. Allocating from the document would mean a message
deciding how much memory to take.

**An array that may be absent is a `T[]?`.** One the constructor left null is
written as `null`, and made at the document's length when the document gives
one, which is the one place a message sizes an allocation. A `T[]` field is
never null, so its constructor chose a length for it
([§2.16.2](02-types.md#2162-fields)).

A nested object the constructor left null is skipped, unless the field carries
`[JsonCreate]` or is `required` — opt-in per field, because the type is what
knows whether the document may decide the object is there. Such an object is
made as `new` would make it, by its public parameterless constructor
([§6.6.1](06-attributes-reflection.md#661-making-an-object)), and so is each
object element of an array the reader allocates. The document then fills it,
and it is stored only once it is complete: **every `required` member given by
the document with a value of its type, and nothing whose type has no zero
value left null.** An element the document gives no value of its type keeps
its zero where that is a value — `0`, `false`, null for a `String?` — and
otherwise the array is incomplete. Anything incomplete fails the whole call
with `JsonError.MissingMember` and is released rather than left reachable; a
type with no constructor to make it with is `JsonError.NotCreatable`. What was
filled before the failure stays filled.

`required` members of the object handed to `PopulateObject` are not asked for:
the `new` that made it was refused unless it set them. A `null` in the document
clears a member whose type allows one.

**What XML reads**: elements, attributes, text, CDATA, comments, the five
predefined entities and numeric character references, and a declaration or
doctype at the front. **What it does not**: namespaces are not resolved, so
`<x:name>` is an element whose name is all of `x:name`; and a DTD is skipped
rather than applied, so an entity a document declares for itself is an error
rather than a silent nothing. An `XmlNode`'s text is every character run inside
it joined, which suits the data XML mostly carries and is the wrong model for
mixed content.

## 5.11 Interfaces may extend interfaces

```csharp
public interface IWritable : IReadable { void Write(String text); }
```

An `IWritable` answers `IReadable`'s methods and converts to it for free: a
reference is a plain pointer either way, and a class implementing the derived
interface carries a dispatch table for both. Implementing `IWritable` therefore
obliges a class to implement `IReadable` as well, and the compiler checks it.

## 5.12 `Standard.Drawing`

A picture in memory: read from a PNG, drawn on, written back.

```csharp
var loaded = Image.FromFile("logo.png");
if (!loaded.Ok)
    return;

var logo = loaded.Value;
logo.FillRectangle(Rgba.FromRgb(200, 30, 30), 8, 8, 64, 24);
logo.DrawEllipse(Rgba.Black, 4, 4, 72, 32, 2);
logo.Save("out.png", ImageFormat.Png);
```

**Written in Stainless, with the platform library loaded by name.** GDI+ on
Windows and libgd elsewhere, both reached through `delegate`s resolved by
`GetProcAddress` or `dlsym` at the first call. Nothing is linked, and that is
what lets this ship in the standard library at all: a `#pragma comment(lib,
"gdiplus")` would put an import in every Stainless binary including the ones
that never make an image, and `-lgd` wants libgd's *development* package where
what a machine has is the runtime one. A program that makes no image pays
nothing, and a machine with no imaging library answers `ImageError.NoBackend`
— a value to print, rather than a link error to decipher.

It is the one module here that reaches an operating system directly rather than
through `runtime/`, because what it needs from the platform is a whole library
rather than a handful of calls to wrap. That is also what
`delegate __stdcall` ([§2.14](02-types.md#214-delegate--a-named-function-pointer))
and the pointer-to-delegate cast are for.

**There is no text**, and that is stated rather than pending. Drawing a string
needs a font, and the two backends disagree about everything to do with one:
GDI+ takes a family name and a device context, libgd wants FreeType and a path
to a `.ttf`.

**`Rgba`, and no `Point`, `Size` or `Rectangle` at all.** `Forms.Drawing`
declares a `Color` and all three of those, and a program that loaded a PNG to
put it on a form would otherwise have to qualify every mention of whichever one
it meant. A polygon therefore takes its points as a flat `int[]`.


## 5.13 `Standard.Security.Cryptography`

```csharp
var digest = Sha256.HashData(Encoding.CreateUtf8().GetBytes("hello"));
var mac    = HmacSha256.HashData(key, message);
var box    = try AesGcm.FromKey(key);
var shared = try X25519.DeriveSharedSecret(myPrivateKey, theirPublicKey);
var signed = try Ed25519.Sign(signingKey, message);
```

**The shape is `System.Security.Cryptography`'s**, so a program being ported
finds the names where it left them. Three things differ, and each is a rule
this language already has: the casing is the house rule's (`Sha256`, not
`SHA256`); anything that can fail returns a `Result` rather than throwing a
`CryptographicException`; and `SHA256.Create()` is `new Sha256()`, because
.NET's factory exists to choose an implementation at run time and there is one
here.

| | |
|---|---|
| hashes | `Md5`, `Sha1`, `Sha256`, `Sha384`, `Sha512`, `Blake2b`, over `IHashAlgorithm` |
| MACs | `Hmac` over any of them, and `HmacSha256` and its siblings |
| derivation | `Rfc2898DeriveBytes.Pbkdf2`, `Hkdf`, `Scrypt`, `Argon2id` |
| ciphers | `Aes` in ECB, CBC, CFB and CTR; `AesGcm`; `ChaCha20`, `Poly1305` and `ChaCha20Poly1305` |
| key agreement | `X25519` (RFC 7748); `ECDiffieHellman` on P-256 and P-384 |
| signatures | `Ed25519` (RFC 8032, pure); `ECDsa` on P-256 and P-384 |
| elliptic curves | `ECCurve`, `ECParameters`, `ECPoint`, `HashAlgorithmName`, `DsaSignatureFormat` |
| public key | `Rsa`, with `RsaParameters`, `HashAlgorithmName`, `RsaSignaturePadding` and `RsaEncryptionPadding` |
| text | `PemEncoding`: RFC 7468 blocks found in text and written at 64 columns |
| the rest | `RandomNumberGenerator`, `CryptographicOperations.FixedTimeEquals` and `ZeroMemory` |

**The ciphers and MACs are constant time in software.** AES is bitsliced, four
blocks at a time with a logic circuit for the S-box, as BearSSL's `aes_ct64`
is; GHASH multiplies with integer multiplies rather than a table; the rest is
arithmetic on words. Nothing indexes memory by a key or by data, or branches
on either. The claim is about timing and the cache, not power or
electromagnetic analysis, and it assumes a multiply whose time does not depend
on its operands.

Every answer is pinned against a published test vector — FIPS-180 and RFC 1321
for the digests, RFC 2202 and 4231 for HMAC, RFC 6070 for PBKDF2, RFC 5869 for
HKDF — by `tests/cases/cryptography`; FIPS-197, SP 800-38A for every mode at
every key length, and all eighteen cases of the GCM specification by
`tests/cases/crypto-aes`; every vector of RFC 8439 by
`tests/cases/crypto-chacha`; RFC 7914's scrypt, RFC 7693's BLAKE2b and RFC
9106's Argon2id by `tests/cases/crypto-kdf`; and RFC 7748 and RFC 8032's own
vectors by `tests/cases/crypto-25519`. The AES and Curve25519 cases run again
as 32-bit x86 programs.

**What is constant time.** Every cipher and MAC — AES bitsliced, GHASH
without a table, ChaCha20, Poly1305 — along with `FixedTimeEquals`, all of
`X25519`, `Ed25519` signing, and everything `ECDsa` and `ECDiffieHellman` do
with a private scalar or a nonce: no branch and no memory index there depends
on a secret, and every secret-dependent choice is a mask passed through
`Bits.OpaqueCopy`. Removing PKCS #7 or ANSI X9.23 padding after CBC or ECB is
the same: the whole last block is examined under masks and there is one
verdict, so the time does not say which byte was wrong. Verification, for both signature schemes, is variable time
and touches only public data. The claim is timing and cache only; the module's
own documentation says what it does not cover.

**Ed25519 verification is strict and cofactorless.** An S at or above the
group order is refused, as is a public key that is not the one canonical
encoding of a point on the curve, and the equation checked is [S]B = R + [k]A
rather than that multiplied by the cofactor. RFC 8032 §5.1.7 allows either.
A public key of small order, one whose eightfold multiple is the identity, is
refused too, as libsodium refuses it: no secret stands behind such a key, and
under the identity R = B and S = 1 sign every message. RFC 8032 does not ask
for that check.

**Every length and every cost has a ceiling**, and passing one is
`CryptoError.Parameter` before anything is allocated. `AesGcm` takes at most
2^36 - 32 bytes of text, past which its 32-bit counter would wrap onto the
block that masks the tag, and less than 2^61 bytes of associated data;
`ChaCha20` stops where its block counter would wrap. PBKDF2 derives at most
2^32 - 1 digests, where its block index would wrap. `Scrypt` holds V and B
together within `MaxMemoryBytes`, 4 GiB, and N * r * p within `MaxWork`, 2^30.
`Argon2id` holds memory within `MaxMemoryKiB`, 4 GiB, passes times memory
within `MaxWorkKiB`, 2^28 KiB, and its output within `MaxLength`, 1 MiB. The
work limits are minutes of computation, and exist because the parameters of a
stored password hash are input like any other.

**Key material is overwritten when the object holding it is destroyed.**
`Aes`, `AesGcm`, `ChaCha20`, `Poly1305`, `Hmac`, the SHA-1, SHA-2 and MD5
hashes (whose state holds `Hmac`'s keyed pad), `Blake2b`, the NIST-curve keys
and the RSA private key each clear their keys, schedules and state in their
destructors, through a write the optimiser may not remove. PBKDF2 and HKDF
clear each intermediate block as they go. That covers what the library copied;
an array the caller passed in is the caller's to clear, with
`CryptographicOperations.ZeroMemory`, and a copy the compiler left in a
register or on the stack is not reached. An object stored in a `static
readonly` is immortal and never destroyed, so its key stays in memory until
the process ends.

**The NIST curves are fixed-width arithmetic, not a bignum.** P-256 and P-384
are Montgomery multiplication over four or six 64-bit limbs held inline, with
the complete addition formulas of Renes, Costello and Batina, so no point is a
special case. Signatures are RFC 6979's, so the same key and message always
sign the same. `ECDsa.SignHash(hash)` has only a digest, so it chooses the
nonce's HMAC by the digest's length; the overload that names the hash is the
one that gives the same bytes as another RFC 6979 implementation. Keys travel as `ECParameters`, SEC 1 points, SEC 1 and PKCS #8
private keys, `SubjectPublicKeyInfo` and PEM, and every point and scalar
imported is checked. RFC 6979's own vectors, NIST's CDH vectors, a spread of
Wycheproof's and keys, signatures and secrets made by OpenSSL pin it, in
`tests/cases/crypto-ecc`.

**`Rsa` is RFC 8017 over a constant-time bignum.** Signatures in PKCS #1 v1.5
and PSS, encryption in OAEP and PKCS #1 v1.5, keys generated as FIPS 186-5
§A.1.3 describes, and keys read and written as PKCS #1, PKCS #8, X.509
`SubjectPublicKeyInfo` and PEM through `Standard.Formats.Asn1`. It differs from
.NET's `RSA` in one more way than the rest of the module: an `Rsa` always holds
a key, so an import is a static method that answers one —
`Rsa.ImportFromPem(pem)` — rather than a method that changes one.

**Sizes are bounded.** Every key read or built from its numbers has a modulus
of 1024 to 8192 bits and a public exponent of at most 33 bits, as in
BoringSSL, so that one verification with a key from the network costs a few
milliseconds and no more; `Rsa.Create(int)` makes 2048 to 8192. The PEM search
under `PemEncoding.Find` and `FindUtf8` is one forward pass over the text.

```csharp
var key = try Rsa.Create(2048);
byte[] signature = try key.SignData(data, HashAlgorithmName.Sha256, RsaSignaturePadding.Pss);
bool genuine = key.VerifyData(data, signature, HashAlgorithmName.Sha256, RsaSignaturePadding.Pss);
```

**Everything done with a secret is constant time**: the Montgomery
exponentiation reads its whole window table for every window, the private
operation is blinded and its result checked against the public key before it
is released, OAEP decodes under masks, and PKCS #1 v1.5 decryption uses
implicit rejection, so a badly padded ciphertext decrypts to a synthetic
message rather than failing. Verifying, encrypting and choosing primes are not,
and need not be. `tests/cases/crypto-rsa` pins it against Wycheproof and
against OpenSSL, byte for byte, and `x86-crypto-rsa` repeats it on 32-bit x86.

X.509 certificates, chains and the root store are the next module,
[§5.16](#516-standardsecuritycryptographyx509certificates).

## 5.14 `Standard.Media.Audio`

```csharp
var clip = try Wav.FromFile("chime.wav");
Audio.PlayClip(clip);

var heard = try Audio.RecordClip(AudioFormat.Voice, 3.0);
Wav.Save(heard, "heard.wav");
```

Interleaved PCM and nothing else: 8-bit unsigned or 16-bit signed, one channel
or two. That is what every platform agrees about and what a WAV file holds.
`AudioPlayer` and `AudioRecorder` are the streaming halves, `Wav` is the
container, and `Tone` makes a sound to check a device with.

**WASAPI on Windows, ALSA everywhere else, and neither is linked.** Both are
reached by name the first time a device is opened, exactly as `Standard.Drawing`
reaches GDI+ and libgd — so a program that makes no sound pays nothing, and a
machine with no audio library answers `AudioError.NoBackend`, which is a value
to print rather than a link error.

WASAPI rather than `winmm`'s `waveOut`: the latter still exists on Windows 11
and has been an emulation on top of WASAPI since Vista, so it adds a buffer of
latency to reach the same mixer and does not work inside an app container. A
program that wants a game engine's mixing and 3D positioning wants
`Win32.XAudio2`, which is bound separately.

## 5.15 `Standard.Formats.Asn1`

```csharp
var certificate = try new AsnReader(der, AsnEncodingRules.Der).ReadSequence();
var signed = try certificate.ReadSequence();

var writer = new AsnWriter();
writer.PushSequence();
writer.WriteInteger(2);
writer.WriteObjectIdentifier("1.2.840.10045.4.3.2");
writer.PopSequence();
byte[] encoded = writer.Encode();
```

**The shape is `System.Formats.Asn1`'s**, with a `Result` where .NET throws.
`AsnReader` reads one value after another and hands back a nested reader for a
`SEQUENCE` or a `SET OF`; a read that fails leaves the reader where it was.
`AsnWriter` writes DER only, with `PushSequence` and `PopSequence` in place of
.NET's `using` scope. An implicit tag is the optional last argument of every
read and write, and an explicit one is a sequence opened with the context tag.

**Nothing aborts on input.** Every length is checked against the value that
contains it, so a nested reader cannot see past its parent. DER is held
strictly: minimal lengths and tag numbers, no redundant `INTEGER` octet, a
`BOOLEAN` of `0x00` or `0xFF`, zero unused bits, primitive strings, and times
in exactly their canonical form. BER is read where it is cheap; an indefinite
length and a constructed string answer `AsnError.Unsupported`. SET OF order is
not checked on reading and is sorted on writing.

**A time is seconds since 1970 in a `long`**, because a `GeneralizedTime`
reaches 9999 and a `DateTimeOffset` ends in 2262.
`ConvertAsnTimeToDateTimeOffset` crosses over where it can and answers
`OutOfRange` where it cannot. A `UTCTime` year follows RFC 5280: `50` to `99`
are the 1900s, `00` to `49` the 2000s.

Object identifiers are dotted strings, and `Oid` converts them to and from
their contents octets. Which identifier means what belongs to the format that
uses it. `tests/cases/asn1` pins X.690's own examples, a refusal for every
`AsnError`, and a walk of a certificate OpenSSL made.

## 5.16 `Standard.Security.Cryptography.X509Certificates`

```csharp
var leaf = try X509Certificate2.FromPem(pem);
var chain = new X509Chain();
chain.ChainPolicy.ExtraStore.AddRange(intermediates);
chain.ChainPolicy.ApplicationPolicy.Add(X509EnhancedKeyUsageExtension.ServerAuthenticationOid);
bool trusted = chain.Build(leaf) && leaf.MatchesHostname("www.example.com");
```

**The shape is .NET's**, with a `Result` where .NET throws, and every
failure a `CryptoError`: a certificate that does not parse is `Encoding`
whatever was wrong with it. A chain that does not validate is not a failure
of the call; `Build` answers `false` and `StatusFlags` says why, in .NET's
`X509ChainStatusFlags`.

**Reading is strict and complete.** The DER is held to the letter and every
extension the module knows is decoded as the certificate is read, so a
malformed key usage is a certificate that does not parse rather than a
surprise later. What browsers tolerate is tolerated: serial numbers of up to
20 octets that are zero or negative, an explicit `critical FALSE`, a
`PrintableString` holding `*` or `@`. An explicit version 1, the DEFAULT, is
not DER and is refused.

**Host names never fall back to the common name**, which no current browser
does. A wildcard is the whole left-most label, stands for one label, and needs
two after it; an address matches only an address entry, as bytes. There is no
public suffix list: a wildcard over a common second-level label under a
two-letter country code, `*.co.uk` or `*.com.au`, matches nothing, and any
other public suffix is taken for a name.

**A chain is built, not just checked.** Every issuer whose name and key
identifier fit is tried in turn, anchors first, so a cross-signed
intermediate or a second CA of the same name is found when the first leads
nowhere. Along the chosen path it checks validity at the moment of the
`Build`, or at `VerificationTime` when that was set; every signature, with
SHA-1 (RSASSA-PSS over SHA-1 included) and RSA keys under 2048 bits reported
as `HasWeakSignature`; basic constraints and path length; key usage and
extended key usage, a TLS leaf's key usage allowing a digital signature;
name constraints over the DNS names, addresses, e-mail addresses and
directory names of every certificate below the constraining CA, subjects
included; and critical extensions it does not understand, which include name
constraints holding a URI or another kind of subtree it does not enforce.
There is no revocation: asking for it fails the chain with
`RevocationStatusUnknown` rather than passing silently.

**The work of a `Build` is bounded**, since its certificates usually come
from the network: at most eight certificates in a path, 128 candidates tried,
the first 64 of the extra store read, and 100 signatures verified, each pair
of certificate and issuer once. A signature the budget leaves unverified does
not verify. With the RSA bounds above, the worst a crafted chain can cost is
about half a second.

`X509Store.Open(StoreName.Root)` is crypt32's store on Windows, loaded by
name so that no program links it, less whatever the user's or the machine's
`Disallowed` store holds, and the system PEM bundle elsewhere; each is read
once per process. `CertificateRequest` makes certificates signed by
Ed25519, ECDSA or RSA through an `X509SignatureGenerator`.
`tests/cases/x509` pins every field, thumbprint and host name against
OpenSSL's reading of a small PKI and of Let's Encrypt's roots and
intermediates, a status flag for each broken chain, and certificates made
here that OpenSSL verifies.

## 5.17 `Standard.Net.Security`

```csharp
var options = new TlsClientOptions();
options.TargetHost = "example.com";
options.CertificateValidator = PinnedLeaf;
var tls = try TlsSocket.Connect("example.com", 443u, options);

var server = new TlsServerOptions();
server.CertificateChain.Add(leafDer);
if (TlsSigningKey.ImportFromPem(keyPem) is Ok key)    // a CryptoError, not a TlsError
    server.PrivateKey = key.Value;
var accepted = try TlsStream.AuthenticateAsServer(tcpClient, server);
```

TLS 1.3 (RFC 8446) and TLS 1.2 (RFC 5246), client and server, written in
Stainless over the cryptography module. **The shape is `System.Net.Security`'s**: `TlsStream` is
`SslStream`, an `IStream` over another, and `AuthenticateAsClient` and
`AuthenticateAsServer` are static methods that answer a
`Result<TlsStream, TlsError>` where .NET throws. `TlsSocket` owns the TCP
connection as well. Each `TlsError` is also the alert sent to the peer, and a
failure the peer found arrives as `AlertReceived`, with its
`TlsAlertDescription` beside it.

In TLS 1.3: all three AEAD suites, X25519, P-256 and P-384 with a
HelloRetryRequest when the client's guess was wrong, and certificates on
Ed25519, ECDSA and RSA-PSS keys, for a client as well as a server. ALPN,
server_name, KeyUpdate and the exporter are there; session tickets are read
and handed to a handler, and nothing offers one back yet. **Never 0-RTT.**

**TLS 1.2 is the modern subset of it.** ECDHE over the same three groups,
with the six AES-GCM and ChaCha20-Poly1305 suites of RFC 5289 and RFC 7905,
signed with Ed25519 (RFC 8422), ECDSA, RSA-PSS or PKCS #1 v1.5; client
certificates, ALPN, server_name, the exporter of RFC 5705, and session
tickets handed to the same handler. **The extended master secret of RFC 7627
is required** of the peer, whichever end it is, since without it a master
secret binds nothing but the randoms. There is no CBC, no static RSA, no
DHE, no compression, and no renegotiation: a request for one from either
side is answered with a `no_renegotiation` warning. `EnabledProtocols`
decides what is offered and accepted; a ClientHello offers both versions,
TLS 1.3 wins wherever both ends have it, and a server that could have
spoken TLS 1.3 writes the downgrade sentinel into a TLS 1.2 random, which a
client that offered TLS 1.3 checks. `NegotiatedProtocol` says which it was.

**Trust is the program's.** A `TlsCertificateValidator` is given the peer's
chain and the name asked for, and answers `TlsError.None` or the refusal to
send. The default is the platform's: an `X509Chain` to a root in the system
store ([§5.16](#516-standardsecuritycryptographyx509certificates)), the
server-authentication usage, and the host name asked for. A program that pins
a certificate or trusts a private CA supplies its own. A server judges a
client's chain with `ValidateTlsClientCertificateChainByDefault`, which wants
the client-authentication usage and has no name to match. The CertificateVerify
signature against the leaf is checked after the validator accepts, and never
after it refuses: a refused chain's key is not used for anything.

**A client MUST have a name to check, or a validator of its own.** An empty
`TargetHost` with the default validator fails with `InternalError` before
anything is sent, and the default validator refuses an empty name however it
is reached. `TlsSocket.Connect` fills an empty `TargetHost` in with its host.

**What a peer can make this end do is bounded.** A ClientHello's extensions
and key shares are checked for repeats with a bitmap, so one of 64 KiB parses
in well under a millisecond. More than 32 records in a row that carry nothing
-- empty application data, warning alerts, TLS 1.2 renegotiation requests --
end the connection with `unexpected_message`. An RSA key in a certificate is
refused over 8192 bits or with an exponent over 33 bits. A sequence number is
never allowed to wrap. A server skips up to 32.5 KiB of 0-RTT data a client
sends although it was never accepted (RFC 8446 section 4.2.10). An exporter
asked for more than it can give, a label or a context too long for its length
prefix, fails with `InternalError` rather than truncating.

**Secrets are overwritten when they are done with**: the ECDHE shared secret
and the X25519 private key once they are agreed, the handshake secrets once
both Finished messages are, the old traffic secret at each KeyUpdate, the TLS
1.2 premaster secret and key block once they are used, and the rest at
`Close`. A NIST curve's private key is inside its `ECDiffieHellman` and is
dropped rather than overwritten, and so are the AEADs' expanded keys.

`tests/cases/tls13-rfc8448` replays RFC 8448's 1-RTT trace against both
halves: the client writes the trace's records byte for byte and verifies its
RSA-PSS signature, and the server writes the trace's ServerHello and a flight
the trace's keys open. `tls12-prf` checks TLS 1.2's PRF against its published
vectors, and its key block and records against values computed
independently. `tls13-handshake` and `tls12-handshake` run every suite, group
and key over the loopback, and `tls13-refusals` and `tls12-refusals` pin the
alert for each refusal. `tls-hardening` and `tls-hardening-internals` pin the
limits above.

## 5.18 `Standard.Net.Http`

```csharp
var client = new HttpClient();
client.Timeout = TimeSpan.FromSeconds(10);
String page = try client.GetString("https://example.com/");

var request = new HttpRequestMessage(HttpMethod.Post, "https://example.com/items");
request.Content = new StringContent(json, null, "application/json");
var response = client.Send(request, HttpCompletionOption.ResponseContentRead,
                           out HttpFailure failure);
```

An HTTP/1.1 (RFC 9112) and HTTP/2 (RFC 9113) client over TCP and TLS. **The shape is
`System.Net.Http`'s, blocking**: `SendAsync` is `Send`, `GetStringAsync` is
`GetString`, and so on, and each answers a `Result<…, HttpError>` where .NET
throws. `HttpError` is the case — `Timeout`, `ConnectFailure`, `TlsFailure`,
`InvalidResponse`, `TooManyRedirects`, `ProxyFailure` and the rest — and the
overloads taking `out HttpFailure` say more: the socket error, the TLS error
and alert, the status a proxy refused with, the decompressor's error.

`HttpClientHandler` is where the behaviour is, with .NET's names and
defaults. **Connections are pooled** per scheme, host, port and proxy, held
to `MaxConnectionsPerServer`, dropped after `PooledConnectionIdleTimeout`, and
given back only once a body has been read to its end; a response disposed
before then closes its connection. A request that fails before any byte of
the answer on a pooled connection is sent once more on a new one when its
method is idempotent. **`HttpClient.Timeout` covers the whole request**: the
connect is made without blocking and waited for, trying each address the name
resolves to with an equal share of what is left, and every read and write
after it is given what is left, including each read of the response head, of
the TLS handshake and of a proxy's answer to `CONNECT`, so a peer sending a
byte at a time cannot stretch it. Name resolution is the one step it cannot
cover, since the platform's resolver takes no timeout. A host holding a control byte, a space,
or one of `/ ? # @ \` is refused before anything connects, since it would
split the request line or the `CONNECT` authority it is written into.

**Responses are parsed strictly**, because each leniency is a way to smuggle
one message inside another: a malformed status line, a folded field, a field
with whitespace before its colon, a bare CR, a head over its limits, a chunk
size that is not hexadecimal, two `Content-Length`s that disagree, and a
`Content-Length` beside a `Transfer-Encoding` are all refused as
`InvalidResponse` or `ResponseTooLarge`. Bodies are framed by length, by
chunks with their trailer in `TrailingHeaders`, or by the close; 1xx answers
are skipped, and HEAD, 204 and 304 have no body whatever they declare. A
body sent with `Expect: 100-continue` waits for 100, or for the continue
time to pass; another 1xx such as 103 is read past rather than taken as the
answer.

**Requests are held to what they declare**, for the same reason. A body
longer than its `Content-Length` fails with `ContentFailure` before a byte
past the length is written, and its connection is closed; a multipart part
with a control character in a field fails with `InvalidRequest`. `Uri`
refuses a host with a control byte, a space, DEL, or any of `/ ? # @ \ [ ]`
and `:` outside a bracketed IPv6 literal, so no host can end a request line
or a `CONNECT`.

Redirects follow RFC 9110 as browsers and .NET do: 303 makes any method but
HEAD a `GET` without a body, 301 and 302 do so to `POST` alone, and every
other method, like 307 and 308, keeps its method and its body when the body
can be sent twice. Once a redirect leaves the origin, `Authorization`, a
`Cookie` set by hand and a `Host` override are dropped; a hand-set
`Proxy-Authorization` goes only to a plain proxy of the first origin. https
to http is not followed. `CookieContainer` is RFC 6265 with a short built-in
list of public suffixes rather than the Public Suffix List; it holds at most
`PerDomainCapacity` cookies for a domain and `Capacity` in all, 50 and 3000,
evicting what has expired and then the oldest, and takes a `Max-Age` past 400
days as 400 days (RFC 6265bis). `AutomaticDecompression` undoes gzip and
deflate — zlib or raw, as browsers accept — as the body is read. Proxies are
HTTP proxies: absolute-form for http, a `CONNECT` tunnel carrying the TLS for
https, Basic `Proxy-Authorization`, and `HttpClient.DefaultProxy` read from
`http_proxy`, `https_proxy`, `all_proxy` and `no_proxy` as curl reads them.
Variable names are matched case and all, on Windows too, so that under CGI
`HTTP_PROXY`, which is a request's `Proxy` header, is never taken for
`http_proxy`; a `no_proxy` entry with a port that cannot be read is ignored.
`DateTimeOffset.FormatHttpDate` and `ParseHttpDate` in `Standard.Time` write
and read the HTTP-date the fields use.

**Certificates are the TLS module's to judge** unless
`ServerCertificateCustomValidationCallback` is set, and then the callback is
told what the default would have answered, as .NET passes `SslPolicyErrors`.

**HTTP/2 (RFC 9113) is the second kind of connection**, beneath the same
pool, redirects, cookies and decompression. **Which version a request goes
in follows .NET exactly**: `HttpRequestMessage.Version` is 1.1 and
`VersionPolicy` is `RequestVersionOrLower` unless set, so a request uses h2
only when it asks. `HttpClient.DefaultRequestVersion` and
`DefaultVersionPolicy` set what `Get`, `Post` and the rest ask for.

```csharp
var client = new HttpClient();
client.DefaultRequestVersion = HttpVersion.Version20;   // h2 where ALPN agrees
```

| Version | Policy | https | http |
|---|---|---|---|
| 1.1 | `RequestVersionOrLower`, `RequestVersionExact` | 1.1 | 1.1 |
| 1.1 | `RequestVersionOrHigher` | h2 if ALPN agrees, else 1.1 | 1.1 |
| 2.0 | `RequestVersionOrLower` | h2 if ALPN agrees, else 1.1 | 1.1 |
| 2.0 | `RequestVersionOrHigher`, `RequestVersionExact` | h2, or `VersionNegotiationFailure` | h2 with prior knowledge |

TLS offers `h2` then `http/1.1`, as far as the policy allows each. Plain http
never upgrades: HTTP/2 is spoken there only when nothing else will do, from
the first byte. Through a plain proxy a request is always HTTP/1.1; through a
`CONNECT` tunnel it is https as above. 3.0 is not spoken, and is taken as 2.0
when the policy allows lower.

**An HTTP/2 connection is shared**, a stream for each request, up to the
server's `MAX_CONCURRENT_STREAMS`; a request past it waits for a stream to
end, or opens a second connection when `EnableMultipleHttp2Connections` is
set; a request whose new connection comes up allowing no streams waits on
it rather than opening another. One reader thread per connection applies each
frame to its stream, and
ends with the connection. HPACK keeps a dynamic table both ways with
Huffman coding, and never indexes `authorization`, `proxy-authorization` or
`cookie`. Flow control is kept at both levels in both directions: a request
body waits for window, and a response body gives window back as it is read,
so one read slowly holds its server back without holding the connection up.
`InitialHttp2StreamWindowSize` is that window, fixed at 1 MiB unless set,
since .NET's 65 535 relies on growing it by measurement, which is not here.

A GOAWAY lets the streams it covers finish and sends the rest again on a new
connection, as it does a stream the server refused with REFUSED_STREAM,
whatever the method, since neither was processed. A timeout or a body closed
early resets its stream with CANCEL and leaves the connection to the others.
A peer that breaks the protocol ends the connection with GOAWAY and the
error RFC 9113 names, `ProtocolError`; a malformed response — upper-case or
connection-specific fields, a missing `:status`, a body unlike its
`content-length` — resets its stream and is `InvalidResponse`.
`HttpFailure.ProtocolErrorCode` carries the code. Server push is refused, and
`Dispose` sends GOAWAY and closes each connection once its streams are done.

**A peer that stops reading cannot hold a request past its timeout.** Each
write on the connection sets the socket's send timeout from the deadline of
the request making it, a request waiting behind another's write waits no
longer than its own deadline, and a write that times out part-way ends the
connection, since a partial frame leaves the peer unable to find the next.
What the reader thread owes the peer, SETTINGS and PING acknowledgements,
WINDOW_UPDATEs and RST_STREAMs, is queued for whichever request writes next;
when nobody is writing the reader writes it, and a write of it that takes
longer than 5 seconds ends the connection.
The queue holds at most 1000 acknowledgements and 64 KiB; a peer that
provokes more is sent GOAWAY with ENHANCE_YOUR_CALM (RFC 9113 section 10.5,
the PING and SETTINGS floods of CVE-2019-9512 and CVE-2019-9515).
WINDOW_UPDATEs for one stream are merged while they wait.

Frames on a stream this end reset are dropped however many streams have been
reset since, DATA credited back to the connection's window and a header block
still decoded, so that the HPACK tables stay in step. A frame after the
peer's own END_STREAM remains a STREAM_CLOSED connection error while its
stream is among the last 128 the peer ended. When `SETTINGS_HEADER_TABLE_SIZE`
changes more than once before the next header block, that block announces
the smallest size and then the last (RFC 7541 section 4.2), and no SETTINGS
acknowledgement goes out ahead of a block encoded under the old size. A
connection whose stream identifiers run out takes no new stream, and sends
GOAWAY and closes once the last of them is done.

`tests/cases/http-*`, `http2-*` and `https-basics` run the client against
scripted servers on the loopback, a small proxy among them; `hpack` checks
every example of RFC 7541 Appendix C byte for byte. Nothing in the suite
reaches the network.

---

<sub>[&larr; Generics](04-generics.md) &nbsp;&middot;&nbsp; [Attributes and reflection &rarr;](06-attributes-reflection.md)</sub>
