# Stainless Concurrency (v0.1 draft)

> **A design record.** All seven steps of the plan below are now built. The
> file exists so the decisions survive between sessions, and so the reasons
> survive with them — including the ones that turned out to be wrong, which are
> marked where they were corrected rather than quietly rewritten. Section 10
> tracks what actually exists and what is still open.

Stainless has a problem that most languages get to ignore: its reference counts
are not atomic ([runtime/arc.c](../runtime/arc.c)), and making them atomic taxes
every single-threaded program to buy a feature only some programs use. That
constraint drives the whole design, and it turns out to drive it somewhere good.

The short version: **threads never share mutable managed objects.** They share
plain data, they share types that synchronize themselves, and they move
ownership of everything else. Reference counts stay non-atomic because no two
threads ever touch one, and as of step 6 that is checked rather than trusted.

> **The premise above did not hold, and the counts are atomic now.** `Mutex<T>`
> is the counter-example, found after this was written and detailed in §10: a
> reference handed out of a lock is retained inside it and released outside it,
> so two threads do touch one count, and it drifts until the object is freed
> while still in use. The obvious narrowing — atomic counts for `[Shared]` types
> only — does not close it either, because `Mutex<List<T>>` guards a List and a
> List is not `[Shared]`; what would have to be atomic is everything reachable
> from a shared type.
>
> So all counts are atomic, measured at about 5.7ns per retain/release pair over
> the plain version, and roughly 3x on a program that does nothing but ARC
> traffic. Most of that traffic should not exist: retain/release around a borrow
> is redundant, and the +0/+1 pass that removes it is now the thing worth
> building. **Everything below about what may cross a thread still stands** — it
> is about races on an object's *contents*, which no counting scheme fixes.

---

## 1. The three sharing classes

Every value in Stainless falls into one of three categories, and the category is
decided by the type, not by an annotation.

| Class | What it is | How it crosses a thread | Refcount cost |
|---|---|---|---|
| **Plain data** | `struct`, primitives, pointers | copied | none — no header at all |
| **Owned graph** | `class` instances, `String`, `T[]` | **moved**; one owner at a time | non-atomic, as today |
| **Frozen** | immortal, and immutable in its own right | shared freely by everyone | none — retain/release are no-ops |

The first row is free because of a decision already made: a `struct` cannot hold
a managed reference. A struct is raw bytes, so it is *always* safe to hand to
another thread. That bright line already exists and cost nothing to draw.

> **Two of the three rows above have since moved.** A struct *may* hold a
> reference now — `Result<T, E>` is one, and copying such a struct retains what
> it holds ([tests/cases/struct-references](../tests/cases/struct-references/)).
> So the first row is no longer free by construction, and sendability follows a
> struct's fields rather than its kind: one of primitives and Strings crosses,
> one holding a `List<T>` does not. What a struct still cannot do is cross
> `extern "C"` while holding a reference, which is
> [SL0284](../tests/cases/err-struct-crosses-c/).
>
> And "non-atomic, as today" in the second row is the premise corrected at the
> top of this file: every count is atomic. The row is left as written because
> the rest of §1 reasons from it, and §1.1 is the reasoning.

### 1.1 Why non-atomic counts survive this

A non-atomic reference count is correct whenever a single thread at a time
touches the object and the handoff between threads carries a barrier. Both
transfer points provide one:

- a **channel send** pairs a release store with an acquire load in the receiver;
- a **scope join** pairs the spawned job's exit with the parent's resumption.

So the owned-graph case needs **no change to `sl_retain` or `sl_release`**. The
work is in the type system, not in the runtime.

### 1.2 Freezing, and what it does not do

`SL_IMMORTAL` already exists ([stainless.h](../runtime/stainless.h)). It marks
an object that retain and release skip entirely, which is how a string literal
costs no allocation and no reference traffic. A `static readonly` reference is
marked the same way as it is stored, so a value every thread can see has no
reference traffic at all — not "cheap", actually zero.

**An earlier draft of this document overstated what that buys.** Freezing makes
the *reference count* immortal. It does not make the object's *contents*
immutable, and two threads writing one frozen object's field race exactly as
they would have without it. Immortality removes one hazard, not the hazard.

So safety comes from the type rules in §1.3, not from freezing. Freezing is
what makes those rules free once they are satisfied.

A genuinely deep freeze — walking a graph and sealing it — would need a
per-type trace hook in `SlTypeInfo`, and would still leave the mutability
question open. It is not built, and §1.3 is what took its place.

### 1.3 What may cross a thread boundary

Checked, as of step 6, at the three places a value can reach another thread: a
`spawn` argument or receiver, a `parallel for` capture, and a `static readonly`.

| Allowed | Why it is safe |
|---|---|
| plain data — primitives, enums, pointers, delegates, and a `struct` of the same | there is no reference count to race over |
| `String` | immutable, and its bytes live inside the object |
| a class marked `[Shared]` | the author asserts it synchronizes itself |
| `T[]` where `T` is plain data | a job borrows it without retaining it |

Everything else is rejected, and the error names all three ways out. A `struct`
that holds a reference is rejected with everything else: copying one retains
what it holds, and a retain two threads can both perform is the race this rule
exists to stop.

The fourth row is the pragmatic one, and worth being honest about: borrowing
without retaining is sound as far as it goes, but nothing yet stops a job from
storing the array somewhere and retaining it then. It earns its place because
data parallelism is the point of `parallel for`, and rejecting it would leave
the feature with nothing to iterate.

`[Shared]` is an assertion, not a proof. It is the same bargain Rust's `unsafe
impl Sync` makes, spelled as an attribute, and it is the only place in this
design where a human promise stands in for a check.

---

## 2. Structured concurrency, and no function coloring

`async`/`await` as C# and JavaScript have it is two things bolted
together: a way to express concurrency, and a stackless coroutine transform.
The transform is what produces the state machines, and it is what makes `async`
viral up the call stack — a function that awaits must itself be `async`, so the
colour spreads until the whole program has it.

Stainless does not need the transform. It is a native language with real OS
threads and a C ABI to honour, so **blocking is allowed**. That removes the
colour entirely:

```csharp
int left  = 0;
int right = 0;

parallel {
    spawn left  = Sum(values, 0, half);
    spawn right = Sum(values, half, count);
}                                                // the join

return left + right;
```

There is no `Task` type at all, and no `Wait()`. The closing brace **is** the
synchronization, so a job simply writes its result into a local the parent
still owns — which is sound precisely because the parent cannot leave before
the join. This is Cilk's model, and it was chosen over `Task<T>` handles for
three reasons: it needs no new generic type, it needs no per-task completion in
the runtime, and inside a block that already joins a second `Wait()` is a
synchronization that mostly is not needed and invites confusion about which one
actually waits.

A function that spawns work has the same signature as one that does not, and no
function anywhere needs an annotation.

### 2.1 Why the scope is lexical

A job cannot outlive the `parallel` block that spawned it; the closing brace
joins every outstanding job before control passes it. That is not just tidiness
— it is what makes **borrowing the parent's locals sound**. An unscoped thread
must own everything it touches, which forces heap allocation and moves on data
that never needed either. A scoped one can read `values` off the parent's stack,
because the parent provably has not left.

This is Rust's `thread::scope` and Swift's task groups. It is the highest-value
single decision available here, and it is cheap to implement precisely because
the join point is syntactic.

### 2.2 What the rules buy, and what they cost

Three restrictions fall out of taking the join seriously, and each is reported
as an error rather than left to be discovered:

- **No `return`, `break` or `continue` out of a `parallel` block.** Any of them
  would skip the join and leave jobs running against a dead frame. Put the
  block first and the `return` after it.
- **A spawned call's arguments must be named.** Arguments are borrowed, exactly
  as every other call's are, so nothing crosses a thread as a reference count.
  That only holds if the parent still owns them: `spawn f(new Buffer())` would
  destroy the buffer at the end of the statement, before the job ran.
- **A `parallel for` body may not assign to a variable declared outside it.**
  Every chunk would be racing on one slot. Writing *through* a captured array is
  the point and is allowed; accumulating into a captured `int` is the classic
  bug, and the error says to use an `AtomicLong` instead.

The costs, measured rather than assumed: **one `malloc` per `spawn`**, for the
block the worker unpacks. A per-scope arena would remove it, and is the obvious
change if fine-grained spawning ever matters. `parallel for` does not pay it per
iteration — its captures live on the parent's stack, and the runtime allocates
once per chunk, not once per index.

### 2.3 It shipped before closures, and that was right

The plan called for building this against an `IJob` interface and adding
closures later as sugar. In the event the Cilk-style `spawn` never needed them:
a job is a call, and a call already has arguments.

Closures landed anyway, as their own feature (§2 of the spec), and they lower
exactly as predicted — a compiler-generated class implementing a call interface,
the way C# handles delegates and Rust handles `Fn`, with no new runtime concept
because interfaces with vtables and monomorphized generics already existed.

They are worth having and they are not a concurrency feature. A closure captures
by value into an ordinary class, so it is a class at a thread boundary like any
other and needs `[Shared]` to cross one.

---

## 3. Statics

Implemented. Stainless already had module-level `const`, folded at compile time
with no storage. Real static *storage* follows Swift's model, including the part
Swift arrived at late — but spelled the way C# spells it.

Swift has `static let` / `static var` and file-scope globals, lazily initialized
through `swift_once`. Then Swift 6 (SE-0412) made mutable ones a concurrency
error: a `var` global must be `let` and `Sendable`, or isolated to a global
actor, or explicitly marked `nonisolated(unsafe)`. Rust reaches the same place
from the other side — a `static` must be `Sync`, and `static mut` is an error as
of edition 2024. C# is the counterexample both were reacting to.

Stainless takes the destination without the detour, and writes it as C# would:

| Tier | Form | Rule |
|---|---|---|
| 0 | `const int Limit = 64;` | compile-time value, no storage |
| 1 | `static readonly int Base = 20;` | plain data or a `String`; frozen on store |
| 2 | `static readonly AtomicLong Count = new AtomicLong(0);` | mutable only through a `[Shared]` type |
| 3 | `threadstatic ...` | per-thread storage; deferred |

**There is no `static` without `readonly`**, and that is the whole design: a
plainly mutable global is shared state nothing synchronizes, so the language
does not have one. `static readonly` is not a weaker `static` — it is the only
one, and the error for writing `static` alone says so.

The type rules of §1.3 do the rest. Tier 1 is safe because plain data has no
reference count and a `String` cannot be written; tier 2 is safe because the
type says how. A `static readonly List<int>` is rejected, and the error points
at `Mutex<T>`.

### 3.1 Initialization order

Swift avoids C++'s static initialization order fiasco by making every static
lazy, and pays a `swift_once` guard check on every access — a check that must
become atomic the moment threads exist.

Stainless can do better, because it compiles the whole program at once. The
compiler sees the dependency graph between static initializers, sorts it
topologically, and emits them in order at startup. No guard, no per-access cost,
no atomics, and a **compile error** on a cycle instead of a runtime mystery.

### 3.2 Teardown

There is none. A static reference is made immortal as it is stored, so it is
never destroyed and the process exit reclaims the memory. This sidesteps C++'s
static *destruction* order problem entirely, and is exactly how string literals
already behave — which is also why `sl_make_immortal` reads before it writes: a
literal lives in read-only storage, and storing the marker again would fault.

### 3.3 Libraries

A `--shared` build has no entry point, so there is nothing to run the
initializers from. A static in a library is a compile error rather than a
silently zeroed global; hold the value behind an exported function instead.

---

## 4. Locking

A lock is the escape hatch for everything the rules above reject. It should
look like a deliberate act, not like a keyword you sprinkle.

This is **implemented**, in [stdlib/Threading.sl](../stdlib/Threading.sl).

### 4.1 The rejected design: `lock (obj) { }`

C# lets any object be locked, which means every object header reserves room for
a lock. Stainless headers are 24 bytes ([abi.md](abi.md)); adding a lock word
makes them 32, and every program pays it — including the single-threaded ones
this language is otherwise built to make fast. Rejected on that basis alone.

### 4.2 The chosen design: the mutex owns the data

```csharp
static readonly Mutex<List<String>> Registry = new Mutex<List<String>>(new List<String>());

void Record(String name) {
    var guard = Registry.Lock();      // Guard<List<String>>
    guard.Value().Add(name);
}                                     // ~Guard() unlocks
```

The lock is tied to the data it protects, so there is no way to reach the list
without holding the lock, and no way to forget which lock guards what. Unlocking
is a destructor, so ARC already does it — including on an early `return`.

> **This example was unsound if `Record` was called from two threads**, for a
> reason that only turned up when Standard.Concurrent was built on it: See §10:
> `guard.Value()` retains the list, and that count was not atomic. Everything in
> this section was right about the *lock* and wrong about the *count*. Counts
> are atomic now, so the example is sound as written; the lifetime hole above,
> which is about how long the borrow lives, is untouched by that.

The notable thing about this design is that **it needs no new language surface**.
Generic classes, destructors and interfaces all exist. Only the runtime
primitives in §5 are missing. Locking can therefore ship before closures, before
`spawn`, and before any sendability analysis.

**Still open after step 6.** Sendability is a rule about *types*, and this is a
rule about *lifetimes*, so the analysis that landed does not touch it.

**The known hole:** `guard.Value()` hands out a reference that can outlive the
guard. Nothing today prevents storing it somewhere and using it unlocked. C#
has the same hole and worse; Rust closes it with lifetimes. Stainless closes it
later, when the move and sendability analysis of §1 lands, and not before. It is
written down here so it is a known gap rather than a discovered one.

**A second hole, smaller and sharper:** `registry.Lock();` as a statement locks
and immediately unlocks, because the guard is a temporary that dies at the end
of the statement. The result has to be kept in a variable. A warning for a
discarded `Guard` would catch it, and is worth adding.

---

## 5. What the runtime provides

A new translation unit, [runtime/thread.c](../runtime/thread.c), split by
platform — Win32 today, pthreads behind the same interface, matching the
"Win64 only" honesty elsewhere.

| Primitive | Windows | POSIX |
|---|---|---|
| thread | `CreateThread` | `pthread_create` |
| mutex | `SRWLOCK` | `pthread_mutex_t` |
| condition | `CONDITION_VARIABLE` | `pthread_cond_t` |
| timed wait | `SleepConditionVariableSRW` | `pthread_cond_timedwait` |
| reader/writer | `SRWLOCK`, taken shared | `pthread_rwlock_t` |
| thread-local | `FlsAlloc` | `pthread_key_create` |
| sleep | `Sleep` | `nanosleep` |
| atomics | clang `__atomic_*` builtins | same |
| spin hint | `pause` / `yield` | same |

Windows FLS rather than TLS for the thread-local slots, because `FlsAlloc`
takes a callback that runs when a thread ends and `TlsAlloc` has no equivalent.
Without it an object left in a slot outlives every reference to it, on every
thread that ever touched the slot.

A mutex is also available on the heap, as `sl_mutex_new` / `sl_mutex_free`, and
a condition variable as `sl_condition_new` / `sl_condition_free`, because a
Stainless class cannot embed either: their sizes are platform details the
language is never told. A class holds the handle in a `byte*` instead, which is
how `Channel<T>` waits.

`SRWLOCK` is chosen over `CRITICAL_SECTION`: it is pointer-sized, needs no
initialization or destruction call, and is faster uncontended. It is not
recursive, which is the correct default — a recursive lock mostly hides a bug.

On top of those sits the pool: a fixed set of worker threads, a shared queue,
and the join counters that make `parallel` blocks work.

---

## 6. Data parallelism

```csharp
parallel for (int i = 0; i < pixels.Length; i = i + 1) {
    pixels[i] = Shade(pixels[i]);
}
```

Implemented, and the first thing here that pays for itself: on 31 workers this
runs about 18x faster than the same loop written serially, with identical
results.

The loop must be a **counted** one — `i = start`, `i < limit` or `i <= limit`,
`i = i + stride` with a positive literal stride. A general C-style `for` has no
trip count, and the iteration space has to be divided before the body runs.
Anything else is rejected with that explanation.

The split itself lives in [runtime/thread.c](../runtime/thread.c) as
`sl_parallel_range`, not in emitted code: it depends on the pool's size, which
the compiler does not know, and it is a performance question rather than a
correctness one — so the right place to change it later is one C function. It
currently cuts four chunks per worker, so a thread that finishes early picks up
more instead of waiting on the slowest chunk.

---

## 7. Interoperability

Two obligations the C ABI imposes, neither yet met:

- **`export "C"` re-entrancy.** C may call into Stainless on a thread the
  runtime never created. That thread must be adopted before it touches any
  managed object, or its reference counting has no owner.
- **Blocking C calls are fine.** This is a feature of choosing OS threads over
  green threads: an `extern "C"` call that blocks stalls one worker, not a
  scheduler. It is also the argument against fibers in §8.

---

## 8. Deliberately deferred

- **Atomically counted shared classes.** The freeable counterpart to freezing.
  Needs a per-class atomic count and a way to spell it.
- **Async I/O.** The isolation model does not foreclose it. The colour-free
  option is stackful fibers, not stackless coroutines -- but fibers fight the C
  ABI, since a blocking `extern "C"` call stalls the carrier thread. That is the
  machinery Go needed years to build, and it is not free. §12 works through why
  the other two mechanisms are not available here at all.
- ~~**`RwLock<T>`**~~ -- shipped, with `ReadGuard<T>` and `WriteGuard<T>`
  (§11). Recursive locks and lock-free collections are still deferred, the first
  deliberately.
- **Cancellation and failure.** Cancellation works as a shared flag today (§9);
  what is missing is a reason. `Result<T, E>` now exists, so the sentence that
  used to sit here -- that a reason wants an error type the language does not
  have -- is no longer the obstacle. What is left is plumbing a scope handle
  into a job.

---

## 9. Cancellation

Cancellation is **independent of how results come back**. It is easy to think
otherwise, because .NET ships `CancellationToken` alongside `Task` — but the
token is the mechanism, and a token is just a flag two threads can see. The
result-passing choice in §2 neither helps nor hinders it.

### 9.1 What works now

Cooperative cancellation, with the `AtomicBool` from §4:

```csharp
var stop = new AtomicBool(false);

parallel {
    spawn foundLeft  = Search(data, 0, half, stop);
    spawn foundRight = Search(data, half, count, stop);
}
```

`Search` checks `stop.Load()` every so often and returns early; whichever call
finds an answer sets `stop.Store(true)`. Nothing else is needed, and nothing
else was needed before this section existed.

### 9.2 What will never work

**Preemptive cancellation** — stopping a thread where it stands. A thread killed
mid-call leaves destructors unrun and reference counts wrong, and no amount of
runtime support fixes that. .NET shipped `Thread.Abort`, then removed it. This
language will not have it.

**A scope that stops waiting.** `parallel` joins, always. That join is the
entire reason a job may borrow the frame that spawned it, so "cancel" here can
only ever mean *the jobs finish early* — never *the scope gives up on them*.

### 9.3 What is worth adding, and is not built

**Skipping queued work.** A cancelled scope could drop the tasks it has not
started yet. When a search answers from the first chunk while ninety more sit
in the queue, that is most of the work saved. It needs a flag on `SlScope` and
one check in the worker loop before it runs a task — small, and worth doing
once there is a workload that shows it.

Reaching it from inside a job is the harder half: a job has no handle to its
scope today. Passing the scope into the thunk would give it one, and then
either a `Cancel()` on a scope value or a `cancel;` statement valid inside
`parallel` would express it.

**Saying why.** A cancelled operation usually wants to report a reason. That
needs an error type, and `Result<T, E>` is now one -- so this is a question of
plumbing rather than of a missing feature. Today a cancelled job returns
whatever it would have returned, and the flag is the only signal.

---

## 10. What exists today

`parallel`, `spawn` and `parallel for` are in the language, over the runtime of
§5 and the library of [stdlib/Threading.sl](../stdlib/Threading.sl).

`static readonly` gives it module-level storage, initialized in dependency order
before `Main`, and §1.3's sendability rule is checked wherever a value can reach
a second thread. An unsynchronized class can no longer cross a thread boundary
at all.

All seven steps are done. Three things are still open.

**The one that matters most, found while building Standard.Concurrent:**
`Mutex<T>` is unsound when `T` is a class and the mutex is used from more than
one thread. `Guard.Value()` returns the guarded object, which retains it, and
dropping the result releases it — so two threads locking *in turn* still do an
unsynchronized read-modify-write on that object's reference count. The lock
protects the contents; nothing protects the count. It drifts down and the
object is destroyed while the mutex still holds it. A four-thread test destroys
it hundreds of times in a second.

`Mutex<long>` is fine, because a plain value is never retained — which is why
the existing test never showed this. So is any design that keeps the shared
object in a field and never hands it out, because reading a field to call a
method on it borrows, and borrowing touches no count. Every container in
Standard.Concurrent is built that way, and none of them uses `Mutex<T>`.

Closing it properly means **atomic reference counts for `[Shared]` types**.
That is affordable in the spirit of §1: only a type that opts into sharing pays,
and every single-threaded program keeps exactly what it has today. It is a
decision about the ARC model rather than a bug in the library, and it is not
made here.

> **Done, and not the way this paragraph proposed.** `[Shared]`-only atomics
> does not close it: `Mutex<List<String>>` is the spec's own example, the
> `Mutex` is `[Shared]` and the `List` inside it is not, and it is the List's
> count that races. Soundness would need everything reachable from a `[Shared]`
> type to be atomic, which in any program where the question arises is most of
> the heap — and the type can be laundered anyway, since a job takes its
> argument as a `byte*`.
>
> So every count is atomic. Reproduced first: sixteen threads returning
> `guard.Value()` out of the lock crashed about one run in six, and does not in
> twenty-five since. Measured: 1.45ns to 7.11ns per retain/release pair in
> isolation, and 110ms to 320ms on a loop that does nothing else. The bill lands
> on redundant traffic the compiler should not emit, which makes the +0/+1 pass
> the next thing worth building rather than a nicety.

The two already known: a `Guard` can outlive its lock (§4.2), and a job could
retain a plain-data array it was only lent (§1.3). Both are lifetime questions
rather than type questions, and neither is closed by anything built so far.

Order of work, each step useful on its own:

1. ~~`runtime/thread.c` — threads, mutex, condition, atomics, and the pool.~~
   Done. No language changes; validates that non-atomic ARC survives a handoff.
2. ~~`Mutex<T>` and atomics in the standard library (§4.2).~~ Done, with no new
   syntax: generic classes, destructors and delegates were enough.
3. ~~`spawn` / `parallel` with a lexical join (§2).~~ Done. Results land in the
   parent's locals; the closing brace is the synchronization.
4. ~~`parallel for` over plain data (§6).~~ Done, and about 18x on 31 workers.
5. ~~Statics, tiers 1 and 2, with topological initialization (§3).~~ Done, as
   `static readonly`.
6. ~~The sendability analysis (§1.3).~~ Done at the three boundaries. It did
   **not** close §4.2's hole, which is about lifetimes rather than types.
7. ~~Closures (§2.3).~~ Done, though not as sugar over step 3: `spawn` never
   needed them. A lambda becomes a closure for a single-method interface, or a
   plain function pointer for a delegate when it captures nothing.
8. ~~Atomic reference counts.~~ Done, and not the way §10 proposed — see the
   note there. Every count is atomic rather than only a `[Shared]` type's,
   because `Mutex<List<T>>` guards a List and a List is not `[Shared]`. The
   remaining gaps are the two lifetime ones, which no counting scheme touches.

What is still open, in the order it is worth doing:

1. **The +0/+1 dataflow pass.** A retain/release pair around a borrow is
   redundant, and since the counts became atomic each redundant pair costs about
   5.7ns rather than about 1.2ns. This was a nicety and is now the obvious next
   piece of work.
2. **Lifetimes.** A `Guard` can outlive the lock it proves (§4.2), and a job can
   retain a plain-data array it was only lent (§1.3). Both are questions about
   how long a borrowed thing lives, which sendability — a rule about types —
   cannot answer.
3. **The runtime as a shared library.** Each binary links its own copy, so two
   sides of a library boundary have separate allocators and separate stdio
   buffers. That is visible today as output from a library not interleaving with
   its consumer's in the order it was written.

---

## 11. The classic surface

`parallel` and `spawn` cover the common case with no handle to lose and no join
to forget. They do not cover everything: a listener that runs for the life of
the program has no lexical scope to be bracketed by, and a background writer
draining a queue does not want one. So `Standard.Threading` also carries the
unstructured set, and it is deliberately second rather than absent.

| | |
|---|---|
| `Thread` | one OS thread, started with a `Job` and a `byte*`; `Join`, `Detach`, `IsJoinable` |
| `Threading.Sleep` / `Yield` / `CurrentId` | the free functions a thread needs about itself |
| `Monitor<T>` / `MonitorGuard<T>` | a `Mutex<T>` that can be waited on: `Wait`, `WaitFor`, `Pulse`, `PulseAll` |
| `RwLock<T>` / `ReadGuard<T>` / `WriteGuard<T>` | many readers or one writer, with `TryRead` and `TryWrite` |
| `Semaphore` | a permit count: `Wait`, `TryWait`, `WaitFor`, `Release`, `ReleaseMany` |
| `ManualResetEvent` | a latch that stays open until `Reset` |
| `AutoResetEvent` | a turnstile: one `Set`, one passage |
| `CountdownEvent` | counts down to zero and opens |
| `Barrier` | a reusable rendezvous for a fixed number of threads |
| `AtomicInt` | the 32-bit counter, for a cell shared with C |
| `AtomicLong.And` / `Or` / `Xor` | bitwise, for a flag set several threads maintain |
| `SpinWait` | pause, then yield, for a wait shorter than a context switch |

Underneath, [runtime/thread.c](../runtime/thread.c) gained the timed condition
wait these are built on (`SleepConditionVariableSRW` / `pthread_cond_timedwait`),
`SlRwLock` (a shared-mode `SRWLOCK`; `pthread_rwlock_t`), thread-local slots
with a destructor that runs on thread exit (Windows **FLS** rather than TLS,
because `TlsAlloc` has no such callback), `sl_thread_detach`, `sl_thread_sleep`,
the 32-bit and pointer atomic sets, and `sl_cpu_pause`.

### 11.1 The ownership rule is the whole difference

A `spawn`ed job **borrows** the frame that spawned it. That is sound for exactly
one reason: the closing brace cannot be passed until the job has finished, so
the frame provably outlives it (§2.1).

A `Thread` has no closing brace. Whatever it touches has to outlive it on its
own — a `[Shared]` object held in a `static readonly`, or a block the thread
frees itself. Handing it a pointer to a local and returning is a use-after-free,
and nothing catches it: the argument is a `byte*`, which is the same hole §1.3
leaves open for `spawn` and the reason step 6's lifetime analysis is still the
open item.

**The destructor joins.** A `Thread` dropped unjoined blocks where it is
dropped, which is C++'s `jthread` and the safe default — the alternative is a
thread still running against storage that has gone. `Detach()` says the other
thing out loud.

### 11.2 What was not added, and why

**`Volatile.Read` / `Volatile.Write`.** Every atomic here is sequentially
consistent, so `Volatile.Read` would be `AtomicLong.Load` under a second name
that suggests a weaker guarantee than it gives. Two spellings for one operation
is worse than one.

**`ThreadLocal<T>`.** The slots exist in the runtime; the type does not.
Stainless constrains by interface only — there is no `where T : class` — so a
generic `ThreadLocal<T>` would accept `ThreadLocal<int>` and have nowhere to put
the `int`. This is the same reason `AtomicLong` is not `Atomic<T>`. It wants
either a non-generic pair of types or a constraint the language does not have,
and neither is worth guessing at before something needs it.

**Recursive locks.** A recursive lock usually means an ownership question went
unanswered, and neither platform's default primitive is one.

**`Thread.Abort` and anything like it.** §9.2, unchanged: a thread killed
mid-call leaves destructors unrun and counts wrong.

---

## 12. Async, and why this does not have it

`async`/`await` is two things bolted together (§2): a way to express
concurrency, and a stackless coroutine transform. Stainless takes the first and
refuses the second, and the reason is worth writing down properly, because "we
could add `await` later" is only true for one of the three ways to build it.

### 12.1 The three mechanisms

**A compiler CPS transform.** C# today, Rust, JavaScript, Python. The function
is split at every suspend point, and locals that live across one become fields
of a heap object with a state number and a resume method. This is the state
machine, and it is what makes the colour viral: to suspend, your caller must be
split too.

**Runtime-built continuations.** .NET's "runtime async" stops the compiler
emitting state machines; `await` becomes a call to a runtime intrinsic, and the
JIT gives an async method two entry points, copying live frames into a heap
continuation chain on suspend. Worth being precise about what it buys: it
removes the *state machine*, not the *colour* — `async` is still in the
signature. It needs a JIT and a precise GC stack map, and it works because
managed code has no raw `&local` escaping into unmanaged code.

**Stackful coroutines.** Go, Java's virtual threads. No transform, no colour,
and no `await` keyword at all: every task has a real stack and blocking is a
scheduler yield. Go pays for it with **movable** stacks — grown by copying,
which needs precise pointer maps and pointer rewriting — and that is exactly
why a cgo call has to switch to the system stack. Java pays at the same wall
from the other side: a native frame pins the carrier thread.

Swift is the interesting middle. Its async functions are neither: the compiler
emits **split functions** whose frames are heap-allocated async contexts, linked
to the caller's and drawn from a per-task slab, under a calling convention of
their own. The task's stack is a heap linked list, so it grows on demand with no
fixed reservation. It is still stackless CPS and still coloured, and a C
function still cannot call into a suspended one.

### 12.2 What is available here, and what is not

Stainless is AOT, has raw pointers, and honours the C ABI. A caller can take
`&local` and hand it to C, which decides two of the three:

| | Available? | |
|---|---|---|
| Stack copying — Go, .NET runtime async | **No** | a frame cannot move behind a C caller's back, and there is no GC map saying which words are pointers |
| LLVM `llvm.coro.*` | Yes | `coro-split` builds the machine, as it does for Swift and for clang's C++20 coroutines. The colour comes back with it |
| Fixed-size fibers — `swapcontext`, Win32 Fibers, boost.context | Yes | no colour, blocking allowed. Costs a stack per task, and a blocking `extern "C"` call pins its carrier |

So the menu is **fibers and no `await`**, or **`await` and the colour back**.
There is no third door for a language in this position, and the first door is
the one §8 already points at.

### 12.3 The question that actually decides it

`async`/`await` exists to solve a problem this language does not have. In C# and
JavaScript the problem is *one thread, or expensive threads, and a great deal of
I/O*; the fix is either cheap tasks on few threads or cheap threads. Stainless
has real OS threads and permits blocking, so what is left is only: **how many
concurrent I/O operations does a program need?**

Thousands, and M:N scheduling is unavoidable — fibers, with the pinning problem
and the per-task stack. Dozens, and a thread each is correct, simpler, and
already built. Nothing in `Standard.Net` or `Standard.IO` has needed more than
dozens yet, and the honest position is that fibers should wait for a program
that does.

What such a program wants first is not `await`. It is a carrier pool that grows
when a worker blocks in a syscall — Java's managed blockers, Go's `sysmon`
handoff — and that needs no language change at all.
