<sub>[Stainless](../../README.md) &rsaquo; [Language specification](index.md)</sub>

# 5. The standard library

## 5.1 What ships, and how

`Standard.Text` is built into the compiler, because `String` and
`StringBuilder` need runtime support. Everything else is ordinary Stainless
compiled alongside your program.

**A generic that nobody instantiates costs nothing**, because there is nothing
to emit until it is instantiated. That covers `List<T>`, `Dictionary<TKey, TValue>`,
`Mutex<T>`, every container and every concurrent one.

**A non-generic function or class is emitted whether or not it is used**, and
that is a real cost the compiler should not be charging: every stdlib module is
compiled with your program whether you import it or not. A hello-world that
calls `puts` and returns emits **every standard-library function and reaches
none of them** — the whole of `Standard.Net`, `Standard.Encoding`,
`Standard.Text`, `Standard.Math`, `Standard.Collections` and the rest. Nothing
in the compiler prunes them: there is no reachability pass.

What saves it is the linker. Every function and datum goes in a section of its
own and the linker drops the ones nothing reached, so the binary is the size it
should be. The IR is not: compile time pays for all of it, and a reachability
pass from `Main` would fix that. It is not done.

Each thing written in Stainless since — the text library, the sockets, the
threading — has grown what a program that imports none of them must compile,
and the stripped binary has come out the same size every time. That invariance
is the measure of how completely the compiler is leaving the job to the linker.

| Module | Contents | Imported |
|---|---|---|
| `Standard.Text` | `String`, `StringBuilder`, `Utf16String`, conversions | automatically |
| `Standard.Console` | `Write`, `WriteLine`, `WriteError` | on request |
| `Standard.Collections` | the interfaces below, and every container | on request |
| `Standard.Concurrent` | the containers several threads may share | on request |
| `Standard.Threading` | `Mutex<T>`, atomics, the job pool | on request |
| `Standard.Math` | arithmetic that is not an operator | on request |
| `Standard.Bits` | counting bits and rotating them, as the target's own instructions | on request |
| `Standard.Reflection` | `[Reflect]`, `typeof`, the field tables | on request |
| `Standard.IO` | streams and `IOError` | on request |
| `Standard.File` | whole-file operations | on request |
| `Standard.Directory` | making, removing and listing | on request |
| `Standard.Path` | taking paths apart, by the platform's rules | on request |
| `Standard.Ascii` | what one byte is, when ASCII is the honest answer | on request |
| `Standard.Encoding` | `IEncoding` and the six encodings ([§3.6](03-text.md#36-other-encodings)) | on request |
| `Standard.Convert` | base64, hex and number parsing ([§3.7](03-text.md#37-conversions)) | on request |
| `Standard.Process` | running another program, and signals ([§5.9.1](#591-standardprocess)) | on request |
| `Standard.Json` | JSON, as a document or onto a type ([§5.10](#510-standardjson-and-standardxml)) | on request |
| `Standard.Xml` | XML, in the same two layers ([§5.10](#510-standardjson-and-standardxml)) | on request |
| `Standard.Resources` | what a `.rc` folded into the binary, read back on every platform ([§2.2 of packages.md](../packages.md#22-resources)) | on request |
| `Standard.Net` | TCP and UDP sockets, the same on every platform | on request |
| `Standard.Env` | the command line, the environment, the working directory | on request |
| `Standard.Time` | `Instant`, `Duration`, `DateTime` and the monotonic `Clock` | on request |
| `Standard.Random` | xoshiro256**, seeded by you or by the operating system | on request |
| `Standard.Drawing` | raster images: decode, draw, encode ([§5.12](#512-standarddrawing)) | on request |
| `Standard.Security.Cryptography` | hashes, MACs, key derivation, AES ([§5.13](#513-standardsecuritycryptography)) | on request |
| `Standard.Media.Audio` | playing and recording sound ([§5.14](#514-standardmediaaudio)) | on request |
| `Standard.Com` | `Guid` and `IUnknown`, for `com interface` ([§8.5](08-interop-libraries.md#85-com)) | on request |
| `Standard` | `Result<T, TError>`, `[Flags]`, and the rest of what the language itself reads | automatically |

## 5.2 `Standard.Threading`

Locks, atomics and a job pool, over the runtime in
[runtime/thread.c](../../runtime/thread.c). It needed no new syntax: generic
classes carry the lock, destructors release it, and `delegate` carries the work.

```csharp
import Standard.Collections;
import Standard.Threading;

static readonly Mutex<List<String>> Registry =
    new Mutex<List<String>>(new List<String>());

void Record(String name) {
    var guard = Registry.Lock();
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

It used to be worse than a discipline. `Value` retains what it returns and the
caller releases it, usually outside the lock, so two threads performed an
unsynchronized read-modify-write on the count — it drifted down and the object
was freed while the mutex still held it. Reference counts are atomic now, which
closes that half; see [§10 of concurrency.md](../concurrency.md#10-what-exists-today) for why the narrower
fix of "atomic counts for `threadsafe` types" would not have.

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
int value = answer.Get();           // blocks until the value is there
```

A `Future<T>` is a future with no `async` in sight. `Get` is a condition wait
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
public interface IEquatable<T>     { bool EqualTo(T other); }
public interface IComparable<T>    { int CompareTo(T other); }
public interface IHashable         { nuint HashCode(); }

public interface IReadOnlyList<T>  { nuint Count { get; } T At(nuint index); }

public interface IList<T> : IReadOnlyList<T> {
    void Add(T item);
    void Set(nuint index, T item);
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
`EqualTo` and `HashCode` on those types and lowers each to a comparison or a
runtime call:

```csharp
var numbers = new List<int>();
Sort(numbers);                          // int satisfies IComparable<int>

var ages = new Dictionary<String, int>();
ages.Set("ada", 36);                    // String satisfies IEquatable + IHashable

3.CompareTo(5);                         // -1
"apple".CompareTo("banana");            // -1, by bytes, which for UTF-8 is by code point
```

A class still says what it implements, and a declared member always wins over
the built-in one.

**The containers**

| Type | Backed by | Notes |
|---|---|---|
| `List<T>` | one array, doubling | `IList<T>`, `IEnumerable<T>`; `list[i]` |
| `Dictionary<TKey, TValue>` | open addressing | `TKey : IEquatable<TKey>, IHashable`; iterates `Pair<TKey, TValue>`; `map[k]` → `Optional<TValue>` |
| `HashSet<T>` | open addressing | `UnionWith`, `IntersectWith`, `ExceptWith` |
| `Queue<T>` | circular buffer | `Enqueue`, `Dequeue`, `Peek` |
| `Stack<T>` | one array | `Push`, `Pop`, `Peek` |
| `LinkedList<T>` | an index pool | handles, not references — see below |
| `SortedList<TKey, TValue>` | two sorted arrays | `TKey : IComparable<TKey>`; binary search, ordered iteration |

`List<T>` carries an indexer ([§7.5](07-functions-members.md#75-indexers)), so `list[i] += 1` reads and writes the
way an array does. `At` and `Set` remain, because an interface has no indexers
and `IReadOnlyList<T>` declares them; the brackets are what to reach for where
the type is known.

**A dictionary's indexer answers `Optional<TValue>`**, which is Swift's design and
right for the same reason. An index is a position the caller worked out, so
`list[i]` out of range is the same mistake `array[i]` is. A key is data that
arrived from a file, a socket or a person, so a key that is not there is an
ordinary outcome rather than a mistake in the program — the line [§2.6](02-types.md#26-variant--a-value-that-is-one-of-several-things) draws
between a value to return and a reason to stop. An indexer returning `TValue` would
have to stop, and `map[key]` carries no verb to warn anyone that it might.

```csharp
if (settings["timeout"] is Some found) { Use(found.Value); }
int port = settings["port"].ValueOr(8080);
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
limitation: `map[key] = map[key].ValueOr(0) + 1` says what should happen, and
Swift's `dict[key, default: 0] += 1` exists for the same reason.

The named forms remain, each saying which question it asks:

| | |
|---|---|
| `map[key]`, `Find(key)` | `Optional<TValue>`, and **what to reach for** |
| `GetOr(key, fallback)` | the value or a default |
| `ContainsKey(key)` | whether it is there |
| `Get(key)` | the value, **aborting** when there is none |

`Find` costs one probe where `ContainsKey` then `Get` costs two, and it has no
sentinel to collide with a real value the way `GetOr` does. `Get` is the
asserting form and it asserts: use it where the key is there by construction.
`SortedList<TKey, TValue>` answers the same ways, minus the indexer.

Every one of them is **walked in place when iterated**. That is worth saying
because it was not always so: several used to build a whole `List<T>` before
the first step, which made iterating a queue allocate as much again as the
queue held.

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

for (nint at = line.First(); at >= 0; at = line.After(at)) {
    Console.WriteLine(line.ValueAt(at));
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

Asking a container for something it does not have — `Get` with an absent key,
`Dequeue` on an empty queue — aborts, the same way an out-of-range index does.
Use `GetOr`, `ContainsKey` or `IsEmpty` where a miss is an ordinary outcome.
`OrderedDictionary.IndexOf` answers with an `Optional<nuint>` ([§2.8.1](02-types.md#281-optionalt--a-value-or-none)), which is
the one that needs no rule to be remembered.

Alongside the containers are `Largest`, `Smallest`, `IndexOf` and `Sort`, each
constrained to what it actually needs:

```csharp
import Standard.Collections;

public class Money : IComparable<Money>, IEquatable<Money> {
    int cents;
    public int CompareTo(Money other) { ... }
    public bool EqualTo(Money other)  { ... }
}

var prices = new List<Money>();
prices.Add(new Money(250));
prices.Add(new Money(40));

Sort(prices);                       // needs IComparable<Money>
Largest(prices);                    // and works on any IReadOnlyList
```

`Sort` takes an `IList<T>`; `Largest`, `Smallest` and `IndexOf` take an
`IReadOnlyList<T>`, so they accept a mutable list without being able to change
it.

## 5.5 Doing something to every element

A lambda becomes a `closure` ([§2.15](02-types.md#215-lambdas-and-closures)), so the
combinators need no special case in the compiler — they are ordinary generic functions over ordinary generic closures.

```csharp
public closure R    Func<T, R>(T value);
public closure bool Predicate<T>(T value);
public closure void Action<T>(T value);
public closure A    Fold<A, T>(A total, T value);
public closure int  Comparer<T>(T left, T right);
```

These five are declared in `Standard` rather than here, so they need no import:
they are what [§2.15](02-types.md#215-lambdas-and-closures) says a lambda may become, rather than anything a collection
owns, and `Optional.Map` ([§2.8.1](02-types.md#281-optionalt--a-value-or-none)) wants them too.

**They were one-method interfaces until a closure could be generic**, and the
difference is not cosmetic. An interface needs an object that implements it, so
passing a method that already existed meant writing a class whose only purpose
was to carry it:

```csharp
ForEach(lines, report.Note);        // a method bound to an object
ForEach(lines, (l) => count++);     // or a lambda that captures
```

Both are the same two words ([§2.14.1](02-types.md#2141-closure--a-method-and-the-object-it-belongs-to)), and neither needs a declaration to hold
it.

```csharp
var adults = Filter(people, p => p.Age >= 18);
var names  = Map(adults, p => p.Name);
long total = Reduce(numbers, (long)0, (sum, n) => sum + (long)n);

Sort(people, (a, b) => a.Age - b.Age);
```

`Map`, `Filter`, `Reduce`, `Any`, `All`, `CountWhere`, `Find`, `FirstOr`,
`IndexWhere`, `ForEach`, `Take`, `Skip`, `Distinct`, `OrderBy`, `ToList` and
`ToArray`, each over a `T[:]` — which an array converts to — and over any
`IEnumerable<T>`. `Select`, `Where` and `Aggregate` are `Map`, `Filter` and
`Reduce` spelled as LINQ spells them.

**`Find` and `IndexWhere` answer with an `Optional`** ([§2.8.1](02-types.md#281-optionalt--a-value-or-none)), and so does
`Collections.IndexOf`: a length standing in for "not there" is the sentinel
that type exists to retire, and `Optional`'s own documentation names `IndexOf`
as the example. `FirstOr` is still there for the caller who has a sensible
default and nothing to check.

`RemoveWhere(list, predicate)` removes every item the predicate accepts.
A predicate rather than a value, which is what makes it work for a `T` that
implements nothing: a `closure` is not `IEquatable`, so a list of callbacks
could not be removed from at all before this. `RemoveFirst(list, value)` is the
`IEquatable` version beside it.

**Eager, not lazy.** Every one walks its input to the end and returns a
`List<T>`, so `Filter` then `Map` builds two lists. Lazy chaining wants
generators, and there is no `yield` here; a name borrowed from a language that
has one would imply otherwise.

**Sorting is a stable merge sort**, over a `T[:]` or an `IList<T>`, either by
`IComparable<T>` or by a `Comparer<T>` given at the call. Stability is the
property worth the scratch array it costs: sorting by one key and then another
is how a multi-key order gets built, and that only works if the second sort
leaves equal elements where the first put them. An in-place quicksort would
save the allocation and lose that.

`BinarySearch` finds a value in an ordered slice, returning the length when it
is absent. `LowerBound` returns where it would go instead — two functions
rather than one with a flag, because a caller usually wants one answer or the
other, and now that `out` exists neither has to pretend otherwise.

## 5.6 `Standard.Env`, `Standard.Time` and `Standard.Random`

**A program reads its command line through `Main`.**

```csharp
int Main(String[] args) {
    if (args.Length < 1u) { Console.WriteError("usage: wc <file>"); return 2; }
    ...
}
```

`Main` takes either nothing or a `String[]`, and nothing else (SL0282). The
array holds the arguments only — the program's own name is `Env.Program()`,
because it is not one of them and treating it as one is the mistake C's argv
invites. `Standard.Env` reaches the same list from anywhere, which is for code
that is nowhere near `Main`; taking the array as a parameter is better where it
is possible.

`Env` also has variables and the working directory. **An empty value is not
portable**: Windows defines setting one as removal, so `Set(name, "")` deletes
the variable there and keeps an empty one on Unix. Treat empty and unset alike,
which is what `GetOr` does.

**`Standard.Time` keeps two kinds of time apart, because confusing them is the
usual bug.** An `Instant` is a point on the wall clock and can jump — a user
sets it, NTP corrects it, a laptop wakes. A `Duration` is a length, and `Clock`
reads a **monotonic** counter that only goes forward:

```csharp
var clock = new Clock();
DoTheWork();
Console.WriteLine(clock.Elapsed().Format());
```

Subtracting two `Instant`s to measure something is the thing not to do, and is
why the timing type is a separate one. Both are structs over a single `long` of
nanoseconds, so they cost nothing, and both declare the operators that go with
that: `hour + minute` is a `Duration`, `later - earlier` is the `Duration`
between two instants, and `instant + span` is another instant. Adding two
instants is not defined, because the sum of two dates is not a date.

They are made by naming the unit — `Duration.FromSeconds(30)`,
`Instant.FromUtc(...)` — rather than by a free function, since a bare count of
nanoseconds at a call site says nothing about which unit was meant.

The UTC calendar is computed rather than delegated to `gmtime`, because the
platforms disagree about the past: Windows refuses a negative `time_t`, so
every date before 1970 came back empty. Local time still asks the platform,
which is the only thing that knows the zone rules.

**`Standard.Random` is a class, not a set of functions.** The state has to live
somewhere, and a hidden one shared by every caller is what makes a program
impossible to replay — so it lives in an object the caller holds. A
`Random(seed)` repeats exactly, on any machine; a `Random()` is seeded by the
operating system and does not. (The language does now have a mutable static to
put such a thing in, and that is the reason not to.)

It is **not cryptographic** — xoshiro256** is fast and its whole future
follows from its state, which is what makes a seeded run reproducible and what
makes it unfit for a key. `Random.Bytes` goes straight to the platform's
source for that.

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

`Abs`, `Min`, `Max`, `Clamp` and `Sign` are overloaded across `int`, `long`,
`nuint` and `double`, resolved by argument type. Alongside them are the usual
transcendentals, `Floor`/`Ceiling`/`Round`/`Truncate`, `IsNaN`/`IsInfinite`/
`IsFinite`, `Lerp` and `Near`, the integer `GreatestCommonDivisor`,
`LeastCommonMultiple` and `DivideCeiling`, and the bit functions `PopCount`, `LeadingZeros`,
`TrailingZeros`, `IsPowerOfTwo` and `NextPowerOfTwo`.

`Round` takes halves away from zero, which is C's rule rather than the banker's
rounding C# uses by default.

## 5.8 `Standard.Concurrent`

```csharp
import Standard.Concurrent;

var work = new ConcurrentQueue<int>();
parallel {
    spawn Fill(work, 0, 500);
    spawn Fill(work, 500, 1000);
}

var got = work.TryDequeue();
if (got.Ok) { Console.WriteLine(Text.FromInteger(got.Value)); }
```

`ConcurrentQueue<T>`, `ConcurrentStack<T>`, `ConcurrentDictionary<TKey, TValue>` and
`Channel<T>`, each `threadsafe` and each safe for several threads at once.

Every operation that can fail returns a `Taken<T>` — whether there was
anything, and what it was — rather than answering in two calls. There is no
`Peek` and then `Dequeue`, because between the two another thread may have
taken it. `DequeueOr(fallback)` is the same answer without the allocation.

`Channel<T>` is the producer-consumer hand-off: `Take` **blocks** until
something arrives or the channel is closed, and `Close` wakes every waiter.
What was already sent is still delivered; once it is drained, every `Take`
returns at once with `Ok` false.

**Each of these owns an ordinary collection in a field and never hands out a
reference to it.** That began as a correctness requirement: reference counts
were not atomic, so an object returned out of a lock was retained and released
by several threads at once and its count drifted down until it was freed while
still in use. Counts are atomic now and the hazard is gone, but the shape is
still the right one — reading a field to call a method on it borrows, and a
container that never hands its collection out cannot be used wrongly by a caller
who keeps what it lent.

## 5.9 `Standard.IO`, `File`, `Directory` and `Path`

```csharp
import Standard.File;
import Standard.IO;

var read = File.ReadAllText("config.json");
if (read.Ok) { Console.WriteLine(read.Value); }
else         { Console.WriteError(IO.Describe(read.Error)); }
```

Stainless has no static classes, so what C# spells `File.ReadAllText` is a
module-qualified call to a module-level function. That is the mapping
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
that would rather carry on writes `read.ValueOr("")`.

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
the best it could do was hand back a stream holding nothing. `IsOpen` and
`Error` remain for what happens *after* it is open. Closing is the
destructor's job, so a stream that goes out of scope releases its handle
whether or not `Close` was called.

Opening takes a `FileMode` (`Open`, `Create`, `Append`) and a `[Flags]`
`FileAccess` (`Read`, `Write`, `ReadWrite`).

**`File`** has `Exists`, `Size`, `Modified`, `Delete`, `Rename`, `Copy`, the
openers, and the whole-file pairs `ReadAllText`/`WriteAllText`,
`ReadAllBytes`/`WriteAllBytes`, `ReadAllLines`/`WriteAllLines`, and
`AppendText`.

**`Directory`** has `Exists`, `Create`, `CreateAll`, `Delete`, and the listings
`Entries`, `Files`, `Directories` and `AllFiles`. Listings return full paths
rather than bare names, in the platform's order.

**`Path`** is purely textual and touches no disk: `Join`, `FileName`,
`DirectoryName`, `Extension`, `WithoutExtension`, `WithExtension`, `IsRooted`
and `Split`. Both `/` and `\` are accepted when reading a path apart, because
Windows accepts both and a path from a config file may use either.

**Paths are UTF-8, and stay correct.** A Stainless `String` is already UTF-8,
and on Windows the runtime widens every path to UTF-16 before it reaches the
operating system — the narrow CRT entry points would read those bytes in the
active code page, which works by accident for ASCII and fails for everything
else.

### 5.9.1 `Standard.Process`

```csharp
var done = try Run("git", ["rev-parse", "HEAD"]);
if (done.Ok()) { Console.WriteLine(done.Output.Trim()); }
```

Running another program, on both platforms, with the same answers.

**There is no shell**, and there is no overload that takes one command line to
be split. The program and its arguments are a list, so a `>`, a `|` or a space
in a filename is a character the child receives rather than something a shell
acts on. That is the whole of shell injection, designed out rather than warned
about.

**A failure to start and a failure of the program are different things.**
`ProcessError` is only about starting — `NotFound`, `Denied`, `NoResource` —
and a program that ran and returned 1 is a `Completed` with `ExitCode` 1, which
is an outcome rather than a fault. `grep` answering 1 for "no match" is the
ordinary case.

Telling those apart takes work on POSIX, and it is worth knowing why. A child
cannot report a failed exec through its exit code: 127 is the shell's
convention for "could not run it" and is also a perfectly ordinary code a real
program might return. So the child is given a close-on-exec pipe and writes
`errno` into it; a successful exec closes it and the parent reads end-of-file.
One pipe, one read, and `Run("/no/such/thing")` says `NotFound` while
`Run("sh", ["-c", "exit 127"])` says the program ran and answered 127.

**Both streams are drained while the child runs.** A pipe holds about 64KB, so
a parent that waits for the child before reading waits forever on a child that
writes more — and reading one stream to the end while the child fills the other
is the same deadlock in a different order. `poll` does it on POSIX and
`PeekNamedPipe` on Windows.

`Output` and `Errors` are kept apart, so a program that prints progress to one
does not corrupt what was captured from the other.

**`Start` hands back a `Process`** for a program to be waited on later, or
asked whether it has finished, or stopped. Its streams are the parent's. A
`Process` let go of is reaped by its destructor, so nothing is left a zombie;
it is not killed, letting go saying nothing about wanting it stopped.

`Stop` is `SIGTERM` and `Kill` is `SIGKILL`. On Windows both are
`TerminateProcess`: there is no polite signal for a process that is not a
console group of its own, and saying so is better than pretending `Stop` can be
gentle there.

**Signals are asked for rather than delivered.** A handler runs between two
instructions of whatever was executing, so almost nothing is legal inside one —
no allocation, no locks, and therefore no Stainless at all. `Signals.Watch()`
installs a handler that stores to a flag, and `Signals.Interrupted` reads it
where a program can act on it:

```csharp
Signals.Watch();
while (!Signals.Interrupted) { DoAPieceOfWork(); }
```

## 5.10 `Standard.Json` and `Standard.Xml`

Both have the same two layers, and the split is the point.

**A document, which needs no type.** `Json.Parse` gives a `JsonValue` — a
variant that is exactly one of the six things JSON has — and `Xml.Parse` gives
an `XmlNode`. Reading the wrong case is a compile error rather than a null:

```csharp
var parsed = try Json.Parse(text);

switch (parsed) {
    case Object held: Console.WriteLine(Json.TextOr(held.Members.Find("name"), "?")); break;
    default: break;
}
```

**A mapping onto a type**, through the field tables of a `[Reflect]` type
([§6](06-attributes-reflection.md#6-attributes-and-reflection)). `Json.Serialize(value)` reads an object's fields and `Json.Populate`
writes them, walking into a nested object rather than stopping at it.
`[JsonName("id")]` renames a field and `[JsonIgnore]` leaves it out; XML has
`[XmlName]`, `[XmlIgnore]` and `[XmlAttribute]`, which writes a field as an
attribute rather than as a child element.

**Reading fills an object rather than making one**, and that is the design
rather than a limitation:

```csharp
var settings = new Settings();          // the constructor establishes the type
Json.Populate(settings, text);          // the document overwrites what it names
```

A constructor is what makes a type's invariants true. A deserializer that
allocated zeroed memory would hand back an object whose non-nullable fields
were null — a hole in the type system rather than a value — so the object comes
from the program and a field the document does not mention keeps what the
constructor chose. It is also why there is no `Deserialize<T>(text)` returning
a fresh `T`: a type argument cannot be written at a call ([§4.4](04-generics.md#44-what-is-and-is-not-supported)), so a function
whose only mention of `T` is its return type could never be called.

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

A nested object the constructor left null is skipped, unless the field carries
`[JsonCreate]` — opt-in per field, because the type is what knows whether an
object made from a document rather than a constructor is safe. What such an
object starts as is zeroed, so only the document gives its fields values.

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
if (!loaded.Ok) { return; }

var logo = loaded.Value;
logo.FillRectangle(Rgba.Rgb(200, 30, 30), 8, 8, 64, 24);
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
var digest = Sha256.HashData(Encoding.Utf8().GetBytes("hello"));
var mac    = HmacSha256.HashData(key, message);
var box    = try AesGcm.FromKey(key);
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
| hashes | `Md5`, `Sha1`, `Sha256`, `Sha384`, `Sha512`, over `IHashAlgorithm` |
| MACs | `Hmac` over any of them, and `HmacSha256` and its siblings |
| derivation | `Rfc2898DeriveBytes.Pbkdf2`, `Hkdf` |
| ciphers | `Aes` in ECB, CBC, CFB and CTR; `AesGcm` |
| the rest | `RandomNumberGenerator`, `CryptographicOperations.FixedTimeEquals` |

Every answer is pinned against a published test vector — FIPS-180 and RFC 1321
for the digests, RFC 2202 and 4231 for HMAC, RFC 6070 for PBKDF2, RFC 5869 for
HKDF, FIPS-197 for the AES blocks, SP 800-38A for the modes and the GCM
specification's own case 3 — by `tests/cases/cryptography`.

**What is not there is public-key.** RSA, ECDsa, ECDiffieHellman and X.509 all
rest on arbitrary-precision integer arithmetic, which this standard library
does not have; [TODO.md](../../TODO.md) carries the shape that would take.

## 5.14 `Standard.Media.Audio`

```csharp
var clip = try Wav.FromFile("chime.wav");
Audio.Play(clip);

var heard = try Audio.Record(AudioFormat.Voice, 3.0);
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

---

<sub>[&larr; Generics](04-generics.md) &nbsp;&middot;&nbsp; [Attributes and reflection &rarr;](06-attributes-reflection.md)</sub>
