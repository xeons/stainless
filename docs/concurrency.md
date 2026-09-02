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

---

## 1. The three sharing classes

Every value in Stainless falls into one of three categories, and the category is
decided by the type, not by an annotation.

| Class | What it is | How it crosses a thread | Refcount cost |
|---|---|---|---|
| **Plain data** | `struct`, primitives, pointers | copied | none — no header at all |
| **Owned graph** | `class` instances, `String`, `T[]` | **moved**; one owner at a time | non-atomic, as today |
| **Frozen** | immortal, and immutable in its own right | shared freely by everyone | none — retain/release are no-ops |

The first row is free because of a decision already made:
[a `struct` cannot hold a managed reference](../tests/cases/err-struct-holds-class/).
A struct is raw bytes, so it is *always* safe to hand to another thread. That
bright line already exists and cost nothing to draw.

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
| plain data — primitives, enums, pointers, delegates, `struct` | there is no reference count to race over |
| `String` | immutable, and its bytes live inside the object |
| a class marked `[Shared]` | the author asserts it synchronizes itself |
| `T[]` where `T` is plain data | a job borrows it without retaining it |

Everything else is rejected, and the error names all three ways out.

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
| atomics | clang `__atomic_*` builtins | same |

A mutex is also available on the heap, as `sl_mutex_new` / `sl_mutex_free`,
because a Stainless class cannot embed an `SlMutex`: its size is a platform
detail the language is never told.

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
- **Async I/O.** The isolation model does not foreclose it. When it arrives, the
  colour-free option is stackful fibers, not stackless coroutines — but fibers
  fight the C ABI, since a blocking `extern "C"` call stalls the carrier thread.
  That is the machinery Go needed years to build, and it is not free.
- **`RwLock<T>`**, recursive locks, lock-free collections.
- **Cancellation and failure.** Cancellation works as a shared flag today (§9);
  what is missing is a reason, and a reason wants an error type, which the
  language does not have.

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

**Saying why.** A cancelled operation usually wants to report a reason, and
that needs an error type, which the language does not have. Until then a
cancelled job returns whatever it would have returned, and the flag is the only
signal.

---

## 10. What exists today

`parallel`, `spawn` and `parallel for` are in the language, over the runtime of
§5 and the library of [stdlib/Threading.sl](../stdlib/Threading.sl).

`static readonly` gives it module-level storage, initialized in dependency order
before `Main`, and §1.3's sendability rule is checked wherever a value can reach
a second thread. An unsynchronized class can no longer cross a thread boundary
at all.

All seven steps are done. Two things are still open, and both are named where
they live: a `Guard` can outlive its lock (§4.2), and a job could retain a
plain-data array it was only lent (§1.3). Both are lifetime questions rather
than type questions, and neither is closed by anything built so far — closing
them is the next piece of work, not a step in this plan.

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
