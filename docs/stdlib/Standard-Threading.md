# Standard.Threading

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Locks, atomics and the job pool.

This is step 2 of docs/concurrency.md: the library surface over the runtime
primitives, with no new syntax. `spawn` and `parallel` are step 3, and the
move and sendability analysis that makes any of this checkable is step 6 --
so for now the rules in that document are conventions the compiler does not
yet enforce.

The one rule that matters most: threads share plain data and frozen data,
and move ownership of everything else. Reference counts are atomic, so
sharing an object no longer corrupts its count; what the rule protects is
the object's *contents*, which nothing synchronizes on its behalf.

## Contents

**Types** &nbsp; [Action](#action-closure) &middot; [AtomicBool](#atomicbool-class) &middot; [AtomicInt](#atomicint-class) &middot; [AtomicLong](#atomiclong-class) &middot; [AutoResetEvent](#autoresetevent-class) &middot; [Barrier](#barrier-class) &middot; [CountdownEvent](#countdownevent-class) &middot; [Future&lt;T&gt;](#futuret-class) &middot; [Guard&lt;T&gt;](#guardt-class) &middot; [IConsume&lt;T&gt;](#iconsumet-interface) &middot; [IProduce&lt;T&gt;](#iproducet-interface) &middot; [Job](#job-delegate) &middot; [ManualResetEvent](#manualresetevent-class) &middot; [Monitor&lt;T&gt;](#monitort-class) &middot; [MonitorGuard&lt;T&gt;](#monitorguardt-class) &middot; [Mutex&lt;T&gt;](#mutext-class) &middot; [ReadGuard&lt;T&gt;](#readguardt-class) &middot; [RwLock&lt;T&gt;](#rwlockt-class) &middot; [Semaphore](#semaphore-class) &middot; [SpinWait](#spinwait-class) &middot; [TaskScope](#taskscope-class) &middot; [Thread](#thread-class) &middot; [WriteGuard&lt;T&gt;](#writeguardt-class)

**Functions** &nbsp; [CurrentId](#currentid-function) &middot; [ProcessorCount](#processorcount-function) &middot; [Sleep](#sleep-function) &middot; [StartPool](#startpool-function) &middot; [WorkerCount](#workercount-function) &middot; [Yield](#yield-function)

## Types

### Action *closure*

```
closure void Action()
```

Work with nothing to pass in and nothing to hand back: what a `Thread` runs.

A closure rather than a delegate, because the point of it is to carry what
it captured -- and capture is by value, so it may outlive the scope that
built it. That is the whole reason a closure is safe here where a pointer to
a local is not.

<sub>[stdlib/Threading.sl:1108](../../stdlib/Threading.sl#L1108)</sub>

### AtomicBool *class*

```
threadsafe class AtomicBool
```

A flag several threads may set and read. One-way latches -- "has this
started", "should this stop" -- are what it is for.

<sub>[stdlib/Threading.sl:544](../../stdlib/Threading.sl#L544)</sub>

#### Read *method*

```
bool Read()
```

The flag now. Cheap enough to read in a spin loop's condition.

<sub>[stdlib/Threading.sl:557](../../stdlib/Threading.sl#L557)</sub>

#### Write *method*

```
void Write(bool value)
```

Sets the flag, losing whatever it was. `Exchange` is the one to use
when exactly one thread must win.

**See also** &nbsp; [AtomicBool.Exchange](#exchange-method)

<sub>[stdlib/Threading.sl:563](../../stdlib/Threading.sl#L563)</sub>

#### Exchange *method*

```
bool Exchange(bool value)
```

Sets the flag and returns what it was, which is how one thread wins a race.

<sub>[stdlib/Threading.sl:572](../../stdlib/Threading.sl#L572)</sub>

### AtomicInt *class*

```
threadsafe class AtomicInt
```

The same counter in 32 bits, for a cell that has to stay an `int` -- one
shared with C, usually. Prefer `AtomicLong` when the width is your choice:
it is the same speed on any machine this targets and cannot wrap in
practice.

<sub>[stdlib/Threading.sl:506](../../stdlib/Threading.sl#L506)</sub>

#### Read *method*

```
int Read()
```

The value now, stale the moment it is returned.

<sub>[stdlib/Threading.sl:514](../../stdlib/Threading.sl#L514)</sub>

#### Write *method*

```
void Write(int value)
```

Overwrites the value, losing whatever was there.

<sub>[stdlib/Threading.sl:517](../../stdlib/Threading.sl#L517)</sub>

#### Add *method*

```
int Add(int delta)
```

Adds and returns the new value. Wraps at 32 bits, silently, which is
the reason to prefer `AtomicLong` where the width is a free choice.

<sub>[stdlib/Threading.sl:521](../../stdlib/Threading.sl#L521)</sub>

#### Increment *method*

```
int Increment()
```

Adds one and returns the new value.

<sub>[stdlib/Threading.sl:524](../../stdlib/Threading.sl#L524)</sub>

#### Decrement *method*

```
int Decrement()
```

Subtracts one and returns the new value.

<sub>[stdlib/Threading.sl:527](../../stdlib/Threading.sl#L527)</sub>

#### Exchange *method*

```
int Exchange(int value)
```

Stores `value` and returns what was there before.

<sub>[stdlib/Threading.sl:530](../../stdlib/Threading.sl#L530)</sub>

#### CompareExchange *method*

```
bool CompareExchange(int expected, int desired)
```

Stores `desired` only if the current value is `expected`, and reports
whether it did. A false answer means somebody else got there first --
re-read and try again, which is the shape of every lock-free loop.

<sub>[stdlib/Threading.sl:535](../../stdlib/Threading.sl#L535)</sub>

### AtomicLong *class*

```
threadsafe class AtomicLong
```

A 64-bit counter that several threads may touch at once.

Every operation is sequentially consistent. Weaker orderings are worth
having only once something measures as too slow, and getting them wrong is
invisible until it is expensive.

It is `long` rather than generic because atomics are not: `Atomic<T>` would
need a constraint saying T is an integer, and Stainless constrains by
interface only. A shared counter wants 64 bits anyway.

<sub>[stdlib/Threading.sl:447](../../stdlib/Threading.sl#L447)</sub>

#### Read *method*

```
long Read()
```

The value now. A read of a moving counter is stale the moment it is
returned, so this is for reporting; `Add` and `CompareExchange` are
what a decision is built on.

**See also** &nbsp; [AtomicLong.CompareExchange](#compareexchange-method)

<sub>[stdlib/Threading.sl:459](../../stdlib/Threading.sl#L459)</sub>

#### Write *method*

```
void Write(long value)
```

Overwrites the value, losing whatever was there. `Exchange` is the one
that tells you what it replaced.

**See also** &nbsp; [AtomicLong.Exchange](#exchange-method)

<sub>[stdlib/Threading.sl:465](../../stdlib/Threading.sl#L465)</sub>

#### Add *method*

```
long Add(long delta)
```

Adds and returns the new value, so two threads never see the same result.

<sub>[stdlib/Threading.sl:468](../../stdlib/Threading.sl#L468)</sub>

#### Increment *method*

```
long Increment()
```

Adds one and returns the new value, so two threads never see the same
number. Note that this is not C's `++`, which answers the old one.

<sub>[stdlib/Threading.sl:472](../../stdlib/Threading.sl#L472)</sub>

#### Decrement *method*

```
long Decrement()
```

Subtracts one and returns the new value. A reference count reaching
zero is exactly one thread's result.

<sub>[stdlib/Threading.sl:476](../../stdlib/Threading.sl#L476)</sub>

#### Exchange *method*

```
long Exchange(long value)
```

Stores `value` and returns what was there before.

<sub>[stdlib/Threading.sl:479](../../stdlib/Threading.sl#L479)</sub>

#### CompareExchange *method*

```
bool CompareExchange(long expected, long desired)
```

Stores `desired` only if the current value is `expected`, and reports
whether it did. The building block for anything lock-free.

<sub>[stdlib/Threading.sl:483](../../stdlib/Threading.sl#L483)</sub>

#### And *method*

```
long And(long mask)
```

Bitwise, for a set of flags several threads maintain. Each returns the
new value, as `Add` does.

**Parameters**

- `mask` — the bits to keep; every bit outside it is cleared

<sub>[stdlib/Threading.sl:493](../../stdlib/Threading.sl#L493)</sub>

#### Or *method*

```
long Or(long mask)
```

Sets the bits in `mask`, returning the new value.

<sub>[stdlib/Threading.sl:496](../../stdlib/Threading.sl#L496)</sub>

#### Xor *method*

```
long Xor(long mask)
```

Flips the bits in `mask`, returning the new value.

<sub>[stdlib/Threading.sl:499](../../stdlib/Threading.sl#L499)</sub>

### AutoResetEvent *class*

```
threadsafe class AutoResetEvent
```

A turnstile: `Set` lets exactly one waiter through, and closes behind it.

A signal with no waiter is remembered, so the next `Wait` passes straight
away -- one signal, one pass, whichever order they happen in. A second
`Set` before anyone waits is *not* remembered, which is the difference
between this and a `Semaphore`.

<sub>[stdlib/Threading.sl:793](../../stdlib/Threading.sl#L793)</sub>

#### Wait *method*

```
void Wait()
```

Blocks until the turnstile is armed, then passes and closes it behind.
Exactly one waiter passes per `Set`.

<sub>[stdlib/Threading.sl:816](../../stdlib/Threading.sl#L816)</sub>

#### WaitFor *method*

```
bool WaitFor(ulong milliseconds)
```

The same with a deadline. Answers whether it got through; a false
leaves the turnstile as it found it.

**Parameters**

- `milliseconds` — how long to wait at most, measured from the call rather than from the last wake

<sub>[stdlib/Threading.sl:830](../../stdlib/Threading.sl#L830)</sub>

#### Set *method*

```
void Set()
```

Lets one waiter through, or arms the next one.

<sub>[stdlib/Threading.sl:848](../../stdlib/Threading.sl#L848)</sub>

### Barrier *class*

```
threadsafe class Barrier
```

A rendezvous a fixed number of threads reach together, over and over.

Every participant calls `SignalAndWait`; none returns until all have
arrived, and then the barrier re-arms for the next round. Phase-by-phase
simulation is what it is for -- everyone finishes step N before anyone
starts step N+1.

The phase number is what makes it reusable: a thread released from round 3
that loops straight back in cannot be counted into round 3 a second time,
because the number it is waiting on has already moved.

<sub>[stdlib/Threading.sl:988](../../stdlib/Threading.sl#L988)</sub>

#### SignalAndWait *method*

```
long SignalAndWait()
```

Blocks until every participant has arrived. Returns the number of the
phase that just finished.

<sub>[stdlib/Threading.sl:1018](../../stdlib/Threading.sl#L1018)</sub>

#### ParticipantCount *property*

```
nuint ParticipantCount { get; }
```

How many participants the barrier was made for. Fixed, so unlike most
readings here it cannot be stale.

<sub>[stdlib/Threading.sl:1043](../../stdlib/Threading.sl#L1043)</sub>

### CountdownEvent *class*

```
threadsafe class CountdownEvent
```

Counts down to zero, and opens when it gets there.

The join half of fork-join, for work that `parallel` cannot bracket --
jobs handed to threads that outlive the function that started them.
Inside a `parallel` block the closing brace already does this.

<sub>[stdlib/Threading.sl:862](../../stdlib/Threading.sl#L862)</sub>

#### Signal *method*

```
bool Signal()
```

Counts one off. Returns true if that was the last one, and false for a
signal after the count had already reached zero.

**See also** &nbsp; [CountdownEvent.Wait](#wait-method)

<sub>[stdlib/Threading.sl:887](../../stdlib/Threading.sl#L887)</sub>

#### TryAddCount *method*

```
bool TryAddCount(long count)
```

Adds work before it is started. Adding after the count reaches zero is
a race nobody wins, so it is refused rather than reopening the latch.

A negative `count` counts that many off at once, stopping at zero and
opening the latch there as `Signal` would.

<sub>[stdlib/Threading.sl:909](../../stdlib/Threading.sl#L909)</sub>

#### Wait *method*

```
void Wait()
```

Blocks until the count reaches zero. Every waiter passes, and a later
`Wait` returns at once -- the latch does not re-arm.

The calling thread blocks rather than helping: this is not a `parallel`
block, so there is no queue for it to work off.

**See also** &nbsp; [CountdownEvent.Signal](#signal-method)

<sub>[stdlib/Threading.sl:936](../../stdlib/Threading.sl#L936)</sub>

#### WaitFor *method*

```
bool WaitFor(ulong milliseconds)
```

The same with a deadline. Answers whether the count reached zero.

**Parameters**

- `milliseconds` — how long to wait at most, measured from the call rather than from the last wake

<sub>[stdlib/Threading.sl:948](../../stdlib/Threading.sl#L948)</sub>

#### CurrentCount *property*

```
long CurrentCount { get; }
```

How many signals are still outstanding. A snapshot, and stale the
moment you have it.

<sub>[stdlib/Threading.sl:966](../../stdlib/Threading.sl#L966)</sub>

### Future&lt;T&gt; *class*

```
threadsafe class Future<T>
```

A value another thread is still computing.

    var answer = new Future<int>(() => Compute(input));
    // ... do something else ...
    int value = answer.GetResult(); // blocks until it is there

**This is a future without `async`.** `GetResult` blocks, which costs nothing here
that it does not cost anywhere else: Stainless has real OS threads and
permits blocking, so waiting needs no coroutine transform and no colour in
any signature. See §12 of docs/concurrency.md for why that is the whole of
the difference between this and a `Task<T>`.

**It is the unstructured half, and it is third.** `parallel` and `spawn`
have no handle to lose and no join to forget, and a `for parallel` loop
beats both for data. A `Future<T>` earns its place only where the result is
wanted somewhere the scope that started it cannot reach -- returned from a
function, stored in a field, waited on by whoever gets there first. That
freedom is the cost: no lexical join means nothing checks what the body
touches.

**One thread per future**, detached, which is the honest price of having no
scope to pool against. Dozens of these are fine and thousands are not; a
program that wants thousands wants a different mechanism than this one.

**The future cannot be destroyed while its thread runs.** The box handed to
the thread holds a reference to it, so the last release happens on the
worker after the value has landed -- which is what lets the destructor free
the condition variable without checking whether anyone is still waiting on
it.

**Type parameters**

- `T` — what the body produces, and what every `GetResult` answers with

<sub>[stdlib/Threading.sl:1302](../../stdlib/Threading.sl#L1302)</sub>

#### GetResult *method*

```
T GetResult()
```

The value, waiting for it if it is not there yet. Asking twice is
harmless and the second ask does not block: a future is filled once and
then read as often as you like, by as many threads as you like.

<sub>[stdlib/Threading.sl:1323](../../stdlib/Threading.sl#L1323)</sub>

#### IsReady *property*

```
bool IsReady { get; }
```

Whether the value has landed. False here means nothing a moment later,
so this answers "is there anything else worth doing first" and never
"is it safe to skip the wait".

<sub>[stdlib/Threading.sl:1336](../../stdlib/Threading.sl#L1336)</sub>

### Guard&lt;T&gt; *class*

```
class Guard<T>
```

Proof that a lock is held, and the only route to what it guards.

A guard keeps its mutex alive, so the lock cannot be freed while it is
held. Releasing is the destructor's job; there is no `Exit` to forget.

**Type parameters**

- `T` — what the mutex guards, taken from the mutex rather than chosen here

<sub>[stdlib/Threading.sl:214](../../stdlib/Threading.sl#L214)</sub>

#### Value *property*

```
T Value { get; }
```

What the lock guards.

See the hole described on `Mutex`: what this hands back must not
outlive the guard, and nothing yet enforces it.

<sub>[stdlib/Threading.sl:226](../../stdlib/Threading.sl#L226)</sub>

#### SetValue *method*

```
void SetValue(T updated)
```

Replaces the guarded value. For a class `T` this swaps which object is
guarded; mutating the one `Value` gave back is the usual thing.

<sub>[stdlib/Threading.sl:230](../../stdlib/Threading.sl#L230)</sub>

### IConsume&lt;T&gt; *interface*

```
interface IConsume<T>
```

Work that takes a value: the other half of a handoff, and what a
continuation is.

An interface for the same reason `IProduce<T>` is one -- a closure type
cannot be generic -- and a lambda reaches it the same way.

**Type parameters**

- `T` — what the work is handed

<sub>[stdlib/Threading.sl:1266](../../stdlib/Threading.sl#L1266)</sub>

#### Invoke *method*

```
void Invoke(T value)
```

*No documentation.*

<sub>[stdlib/Threading.sl:1268](../../stdlib/Threading.sl#L1268)</sub>

### IProduce&lt;T&gt; *interface*

```
interface IProduce<T>
```

Work that produces a value: what a `Future<T>` runs.

An interface rather than a `closure` because a closure type cannot be
generic, and a lambda targets either -- so `() => Compute(x)` reaches it the
same way it reaches `Action`.

**Type parameters**

- `T` — what the work produces

<sub>[stdlib/Threading.sl:1254](../../stdlib/Threading.sl#L1254)</sub>

#### Invoke *method*

```
T Invoke()
```

*No documentation.*

<sub>[stdlib/Threading.sl:1256](../../stdlib/Threading.sl#L1256)</sub>

### Job *delegate*

```
delegate void Job(byte* argument)
```

The work a pool thread runs. It is a plain function pointer, so whatever it
needs arrives as the argument -- usually an object cast to `byte*`, which
the job casts back.

<sub>[stdlib/Threading.sl:1051](../../stdlib/Threading.sl#L1051)</sub>

### ManualResetEvent *class*

```
threadsafe class ManualResetEvent
```

A latch that stays open once opened: every waiter passes, and every later
`Wait` returns at once until something calls `Reset`.

"Is the server up yet" is the shape it fits.

<sub>[stdlib/Threading.sl:700](../../stdlib/Threading.sl#L700)</sub>

#### Wait *method*

```
void Wait()
```

Blocks until the latch is open, and returns at once if it already is.
Every waiter passes -- the latch is not consumed.

<sub>[stdlib/Threading.sl:723](../../stdlib/Threading.sl#L723)</sub>

#### WaitFor *method*

```
bool WaitFor(ulong milliseconds)
```

The same with a deadline. Answers whether the latch was open, so a
false means the time ran out.

**Parameters**

- `milliseconds` — how long to wait at most, measured from the call rather than from the last wake

<sub>[stdlib/Threading.sl:736](../../stdlib/Threading.sl#L736)</sub>

#### Set *method*

```
void Set()
```

Opens the latch and releases everybody waiting.

**See also** &nbsp; [ManualResetEvent.Reset](#reset-method)

<sub>[stdlib/Threading.sl:755](../../stdlib/Threading.sl#L755)</sub>

#### Reset *method*

```
void Reset()
```

Closes it again, so the next `Wait` blocks.

**See also** &nbsp; [ManualResetEvent.Set](#set-method)

<sub>[stdlib/Threading.sl:766](../../stdlib/Threading.sl#L766)</sub>

#### IsSet *property*

```
bool IsSet { get; }
```

Whether the latch is open *now*. `Reset` can close it before you act
on the answer, so this is for reporting rather than for deciding.

<sub>[stdlib/Threading.sl:775](../../stdlib/Threading.sl#L775)</sub>

### Monitor&lt;T&gt; *class*

```
threadsafe class Monitor<T>
```

A `Mutex<T>` that can also be waited on -- C#'s `Monitor`, with the same
`Wait`, `Pulse` and `PulseAll`, and with the lock and the data still tied
together.

A monitor is what you want when a thread has to wait for a *condition* on
the guarded value rather than just for the lock. `Wait` releases the lock,
sleeps, and takes it again before returning, so a waiter never misses a
pulse that lands while it is going to sleep.

**Always wait in a loop.** Both platforms permit a spurious wake, and the
pulse says only "the value changed", never "it changed the way you want":

    var held = queue.Enter();
    while (held.Value.IsEmpty) { held.Wait(); }
    var item = held.Value.Take();

**Type parameters**

- `T` — what the monitor guards, and what a waiter's condition is about

<sub>[stdlib/Threading.sl:252](../../stdlib/Threading.sl#L252)</sub>

#### Enter *method*

```
MonitorGuard<T> Enter()
```

Blocks until the lock is free. Keep the result in a variable -- a
temporary unlocks at the end of the statement.

<sub>[stdlib/Threading.sl:274](../../stdlib/Threading.sl#L274)</sub>

### MonitorGuard&lt;T&gt; *class*

```
class MonitorGuard<T>
```

Proof that a monitor is held, and the only route to what it guards.

**Type parameters**

- `T` — what the monitor guards, taken from the monitor rather than chosen here

<sub>[stdlib/Threading.sl:296](../../stdlib/Threading.sl#L296)</sub>

#### Value *property*

```
T Value { get; }
```

What the monitor guards, with the same lifetime caveat as `Guard`.

<sub>[stdlib/Threading.sl:305](../../stdlib/Threading.sl#L305)</sub>

#### SetValue *method*

```
void SetValue(T updated)
```

Replaces the guarded value. Pulse afterwards if anyone is waiting on a
condition this changed -- nothing wakes on its own.

<sub>[stdlib/Threading.sl:309](../../stdlib/Threading.sl#L309)</sub>

#### Wait *method*

```
void Wait()
```

Releases the lock, waits for a pulse, and takes the lock again. Call it
in a loop that re-checks what you are waiting for.

<sub>[stdlib/Threading.sl:313](../../stdlib/Threading.sl#L313)</sub>

#### WaitFor *method*

```
bool WaitFor(ulong milliseconds)
```

The same with a deadline. Returns false if the time ran out -- and the
lock is held either way, because the predicate still has to be checked.

**True means the wait did not time out, not that a pulse arrived.** A
spurious wake reports success, which is the other reason the predicate
is checked in a loop rather than read once.

**Parameters**

- `milliseconds` — how long to wait for, from now

<sub>[stdlib/Threading.sl:323](../../stdlib/Threading.sl#L323)</sub>

#### Pulse *method*

```
void Pulse()
```

Wakes one waiter. It cannot run until this guard is dropped.

<sub>[stdlib/Threading.sl:326](../../stdlib/Threading.sl#L326)</sub>

#### PulseAll *method*

```
void PulseAll()
```

Wakes every waiter. Use it when more than one could make progress, or
when waiters are waiting for different conditions on the same value.

<sub>[stdlib/Threading.sl:330](../../stdlib/Threading.sl#L330)</sub>

### Mutex&lt;T&gt; *class*

```
threadsafe class Mutex<T>
```

A value and the lock that guards it, as one thing.

Tying the two together is the whole point: there is no way to reach the
value without holding the lock, and no way to forget which lock guards
what. Compare `lock (obj) { }`, which would put a lock word in every object
header and charge every single-threaded program for it.

Unlocking is a destructor, so ARC already does it -- including on an early
`return`, and including when a `Guard` is dropped in a branch you forgot
about.

    var guard = registry.Enter();
    guard.Value.Add(name);
    // ~Guard() unlocks here

**Known hole.** `Value` hands out what the lock protects, and nothing yet
stops you storing it somewhere and using it after the guard has gone. C#
has the same hole and worse; Rust closes it with lifetimes. Stainless
closes it when the analysis in step 6 of docs/concurrency.md lands, and not
before. Until then this is a discipline, not a guarantee.

It used to be unsound for a class `T`: `Value` retains what it hands out
and the caller releases it, often outside the lock, so two threads performed
an unsynchronized read-modify-write on that object's count. The count drifted
down and the object was freed while the mutex still held it. Reference counts
are atomic now, which closes that; what remains is the lifetime hole above,
which is about how long a borrowed thing lives rather than about counting.

**Type parameters**

- `T` — what the lock guards. Nothing is required of it: safety comes from the lock rather than from the type, and a `T` reached any other way is unguarded.

<sub>[stdlib/Threading.sl:164](../../stdlib/Threading.sl#L164)</sub>

#### Enter *method*

```
Guard<T> Enter()
```

Blocks until the lock is free, then returns the guard that holds it.

Keep the result in a variable. `registry.Enter();` on its own locks and
then immediately unlocks, because the guard is a temporary and dies at
the end of the statement.

**See also** &nbsp; [Mutex.TryEnter](#tryenter-method)

<sub>[stdlib/Threading.sl:186](../../stdlib/Threading.sl#L186)</sub>

#### TryEnter *method*

```
Guard<T>? TryEnter()
```

Takes the lock only if it is free. Returns null rather than blocking.

**See also** &nbsp; [Mutex.Enter](#enter-method)

<sub>[stdlib/Threading.sl:195](../../stdlib/Threading.sl#L195)</sub>

### ReadGuard&lt;T&gt; *class*

```
class ReadGuard<T>
```

Shared access. There is no `SetValue`, which is the point.

**Type parameters**

- `T` — what the lock guards, taken from the lock rather than chosen here

<sub>[stdlib/Threading.sl:404](../../stdlib/Threading.sl#L404)</sub>

#### Value *property*

```
T Value { get; }
```

What the lock guards, shared with every other reader. Treat it as
read-only: nothing stops a `T` with mutating methods being mutated
through this, and doing so races with the other readers.

<sub>[stdlib/Threading.sl:415](../../stdlib/Threading.sl#L415)</sub>

### RwLock&lt;T&gt; *class*

```
threadsafe class RwLock<T>
```

A value that many may read at once, or one may write.

Worth it only when reads greatly outnumber writes and each one is long
enough to pay for the extra bookkeeping -- a reader/writer lock is slower
uncontended than a plain mutex. Reach for `Mutex<T>` first and change to
this when a measurement says to.

**A reader cannot upgrade to a writer.** Neither platform's primitive
offers it, and neither should: two readers upgrading at once is a deadlock
with no way out. Drop the read guard, take a write guard, and re-check what
you read -- it may have changed in between.

**Type parameters**

- `T` — what the lock guards. Nothing is required of it, and nothing stops a reader mutating one through `ReadGuard.Value`; see the note there.

<sub>[stdlib/Threading.sl:349](../../stdlib/Threading.sl#L349)</sub>

#### EnterReadLock *method*

```
ReadGuard<T> EnterReadLock()
```

Blocks until no writer holds the lock. Other readers are welcome.

<sub>[stdlib/Threading.sl:364](../../stdlib/Threading.sl#L364)</sub>

#### TryEnterReadLock *method*

```
ReadGuard<T>? TryEnterReadLock()
```

Takes a read guard only if no writer holds the lock. Answers null
rather than blocking.

<sub>[stdlib/Threading.sl:372](../../stdlib/Threading.sl#L372)</sub>

#### EnterWriteLock *method*

```
WriteGuard<T> EnterWriteLock()
```

Blocks until nothing holds the lock at all.

<sub>[stdlib/Threading.sl:380](../../stdlib/Threading.sl#L380)</sub>

#### TryEnterWriteLock *method*

```
WriteGuard<T>? TryEnterWriteLock()
```

Takes a write guard only if nothing holds the lock at all. Answers
null rather than blocking.

<sub>[stdlib/Threading.sl:388](../../stdlib/Threading.sl#L388)</sub>

### Semaphore *class*

```
threadsafe class Semaphore
```

A permit counter: `Wait` takes one and blocks while there are none,
`Release` puts one back.

A semaphore with one permit is a mutex you can unlock from a different
thread than locked it, which is occasionally what you want and usually a
sign that `Mutex<T>` was the right answer. Its real use is a limit -- at
most eight downloads at once, at most one writer per file.

<sub>[stdlib/Threading.sl:590](../../stdlib/Threading.sl#L590)</sub>

#### Wait *method*

```
void Wait()
```

Blocks until a permit is available, and takes it.

**See also** &nbsp; [Semaphore.Release](#release-method)

<sub>[stdlib/Threading.sl:615](../../stdlib/Threading.sl#L615)</sub>

#### TryWait *method*

```
bool TryWait()
```

Takes a permit only if one is free right now.

<sub>[stdlib/Threading.sl:625](../../stdlib/Threading.sl#L625)</sub>

#### WaitFor *method*

```
bool WaitFor(ulong milliseconds)
```

Blocks for at most `milliseconds`. Returns whether it got a permit.

**Parameters**

- `milliseconds` — how long to wait at most. The deadline is taken once, so a wake that finds no permit does not start the wait again.

<sub>[stdlib/Threading.sl:639](../../stdlib/Threading.sl#L639)</sub>

#### Release *method*

```
void Release()
```

Puts one permit back and wakes a waiter.

**See also** &nbsp; [Semaphore.Wait](#wait-method)

<sub>[stdlib/Threading.sl:665](../../stdlib/Threading.sl#L665)</sub>

#### Release *method*

```
void Release(long count)
```

Puts several back at once, waking as many waiters as could proceed.

<sub>[stdlib/Threading.sl:668](../../stdlib/Threading.sl#L668)</sub>

#### CurrentCount *property*

```
long CurrentCount { get; }
```

How many permits are free. A snapshot, and stale the moment you have it.

<sub>[stdlib/Threading.sl:684](../../stdlib/Threading.sl#L684)</sub>

### SpinWait *class*

```
class SpinWait
```

Backs off in a loop that is waiting for something another core will do very
soon -- spinning at first, then yielding once it is clear this will take a
while.

Spinning is right only when the wait is shorter than a context switch, and
wrong every other time. If what you are waiting on takes a lock, does I/O,
or might not happen at all, use a `Monitor` or an event and let the
scheduler have the core back.

    var spin = new SpinWait();
    while (!ready.Read()) { spin.SpinOnce(); }

<sub>[stdlib/Threading.sl:1394](../../stdlib/Threading.sl#L1394)</sub>

#### SpinOnce *method*

```
void SpinOnce()
```

One step of backing off.

<sub>[stdlib/Threading.sl:1402](../../stdlib/Threading.sl#L1402)</sub>

#### Count *property*

```
nuint Count { get; }
```

How many times `SpinOnce` has been called.

<sub>[stdlib/Threading.sl:1419](../../stdlib/Threading.sl#L1419)</sub>

#### Reset *method*

```
void Reset()
```

Starts over, for a loop that is being reused.

<sub>[stdlib/Threading.sl:1422](../../stdlib/Threading.sl#L1422)</sub>

### TaskScope *class*

```
class TaskScope
```

A set of jobs that must all finish before the scope does.

This is the join counter behind `parallel`, exposed as a class until the
syntax exists. `Join` does not return until every job submitted to this
scope has run, and the calling thread runs queued work while it waits
rather than idling.

**Nothing is checked yet.** A job receives a raw pointer, so keeping the
object it points at alive across the join is on you -- holding it in a
local of the function that owns the scope is enough, since the scope joins
before that function returns. Step 6 of docs/concurrency.md is what turns
this from a convention into a rule.

<sub>[stdlib/Threading.sl:1065](../../stdlib/Threading.sl#L1065)</sub>

#### Run *method*

```
void Run(Job job, byte* argument)
```

Queues a job. It may already be running when this returns.

**Parameters**

- `job` — the work a pool thread runs
- `argument` — what it is handed, uninterpreted. It is not owned and not counted, so it MUST outlive the join.

**See also** &nbsp; [TaskScope.Join](#join-method)

<sub>[stdlib/Threading.sl:1081](../../stdlib/Threading.sl#L1081)</sub>

#### Join *method*

```
void Join()
```

Waits for every job submitted so far. Doing it twice is harmless, which
is what lets the destructor be a backstop for a scope nobody joined.

<sub>[stdlib/Threading.sl:1088](../../stdlib/Threading.sl#L1088)</sub>

### Thread *class*

```
class Thread
```

One OS thread, started and joinable.

This is the unstructured option, and it is deliberately second: `parallel`
and `spawn` cover the common case with no handle to lose, no join to
forget, and a compiler check that a job cannot outlive the frame it
borrows. Reach for a `Thread` when the work has no lexical scope -- a
listener that runs for the life of the program, a background writer draining
a queue.

**The ownership rule is different, and it is the whole difference.** A
`spawn`ed job *borrows* the parent's frame, which is sound because the
closing brace cannot be passed until the job has finished. A thread has no
such brace, so whatever it touches has to outlive it: a `threadsafe` object
held in a `static readonly`, or a block the thread frees itself. Passing a
pointer to a local and returning is a use-after-free the compiler does not
yet catch.

**The destructor joins.** A `Thread` that goes out of scope unjoined blocks
there until its thread finishes, which is C++'s `jthread` and is the safe
default: the alternative is a thread still running against storage that has
gone. Say `Detach()` when you mean to let it run loose.

<sub>[stdlib/Threading.sl:1170](../../stdlib/Threading.sl#L1170)</sub>

#### Join *method*

```
void Join()
```

Waits for it to finish. Doing it twice is harmless, which is what lets
the destructor be a backstop.

**See also** &nbsp; [Thread.Detach](#detach-method)

<sub>[stdlib/Threading.sl:1205](../../stdlib/Threading.sl#L1205)</sub>

#### Detach *method*

```
void Detach()
```

Gives up the handle without waiting. The thread runs on and cleans up
after itself; nothing can join it afterwards.

**See also** &nbsp; [Thread.Join](#join-method)

<sub>[stdlib/Threading.sl:1218](../../stdlib/Threading.sl#L1218)</sub>

#### IsJoinable *property*

```
bool IsJoinable { get; }
```

Whether this handle still refers to a thread -- false after `Join` or
`Detach`. It does not say whether the thread is still running.

<sub>[stdlib/Threading.sl:1229](../../stdlib/Threading.sl#L1229)</sub>

### WriteGuard&lt;T&gt; *class*

```
class WriteGuard<T>
```

Exclusive access.

**Type parameters**

- `T` — what the lock guards, taken from the lock rather than chosen here

<sub>[stdlib/Threading.sl:421](../../stdlib/Threading.sl#L421)</sub>

#### Value *property*

```
T Value { get; }
```

What the lock guards, exclusively. Safe to mutate through.

<sub>[stdlib/Threading.sl:430](../../stdlib/Threading.sl#L430)</sub>

#### SetValue *method*

```
void SetValue(T updated)
```

Replaces the guarded value.

<sub>[stdlib/Threading.sl:433](../../stdlib/Threading.sl#L433)</sub>

## Functions

### CurrentId *function*

```
nuint CurrentId()
```

An identifier for the calling thread, unique among those running. It is the
OS's number and means nothing across a restart.

<sub>[stdlib/Threading.sl:1243](../../stdlib/Threading.sl#L1243)</sub>

### ProcessorCount *function*

```
nuint ProcessorCount()
```

How many hardware threads the machine reports.

<sub>[stdlib/Threading.sl:1433](../../stdlib/Threading.sl#L1433)</sub>

### Sleep *function*

```
void Sleep(ulong milliseconds)
```

Stops the calling thread for at least this long. It may be longer: this is
the scheduler's floor, not a timer.

<sub>[stdlib/Threading.sl:1236](../../stdlib/Threading.sl#L1236)</sub>

### StartPool *function*

```
void StartPool(nuint workers)
```

Starts the pool with a chosen number of workers, before any scope does it
automatically. Passing zero sizes it from the processor count.

**See also** &nbsp; [Threading.ProcessorCount](#processorcount-function)

<sub>[stdlib/Threading.sl:1439](../../stdlib/Threading.sl#L1439)</sub>

### WorkerCount *function*

```
nuint WorkerCount()
```

How many threads the pool is running. Zero until the first scope starts it.

**See also** &nbsp; [Threading.StartPool](#startpool-function)

<sub>[stdlib/Threading.sl:1430](../../stdlib/Threading.sl#L1430)</sub>

### Yield *function*

```
void Yield()
```

Offers the rest of this thread's slice to anything else that is ready.

<sub>[stdlib/Threading.sl:1239](../../stdlib/Threading.sl#L1239)</sub>

