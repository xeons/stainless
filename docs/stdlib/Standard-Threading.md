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

**Types** &nbsp; [AtomicBool](#atomicbool) &middot; [AtomicInt](#atomicint) &middot; [AtomicLong](#atomiclong) &middot; [AutoResetEvent](#autoresetevent) &middot; [Barrier](#barrier) &middot; [CountdownEvent](#countdownevent) &middot; [Guard&lt;T&gt;](#guardt) &middot; [Job](#job) &middot; [ManualResetEvent](#manualresetevent) &middot; [Monitor&lt;T&gt;](#monitort) &middot; [MonitorGuard&lt;T&gt;](#monitorguardt) &middot; [Mutex&lt;T&gt;](#mutext) &middot; [ReadGuard&lt;T&gt;](#readguardt) &middot; [RwLock&lt;T&gt;](#rwlockt) &middot; [Semaphore](#semaphore) &middot; [SpinWait](#spinwait) &middot; [TaskScope](#taskscope) &middot; [Thread](#thread) &middot; [WriteGuard&lt;T&gt;](#writeguardt)

**Functions** &nbsp; [CurrentId](#currentid) &middot; [ProcessorCount](#processorcount) &middot; [Sleep](#sleep) &middot; [StartPool](#startpool) &middot; [WorkerCount](#workercount) &middot; [Yield](#yield)

## Types

### AtomicBool *class*

```
threadsafe class AtomicBool
```

A flag several threads may set and read. One-way latches -- "has this
started", "should this stop" -- are what it is for.

<sub>[stdlib/Threading.sl:447](../../stdlib/Threading.sl#L447)</sub>

#### Load *method*

```
bool Load()
```

The flag now. Cheap enough to read in a spin loop's condition.

<sub>[stdlib/Threading.sl:457](../../stdlib/Threading.sl#L457)</sub>

#### Store *method*

```
void Store(bool value)
```

Sets the flag, losing whatever it was. `Exchange` is the one to use
when exactly one thread must win.

<sub>[stdlib/Threading.sl:461](../../stdlib/Threading.sl#L461)</sub>

#### Exchange *method*

```
bool Exchange(bool value)
```

Sets the flag and returns what it was, which is how one thread wins a race.

<sub>[stdlib/Threading.sl:468](../../stdlib/Threading.sl#L468)</sub>

### AtomicInt *class*

```
threadsafe class AtomicInt
```

The same counter in 32 bits, for a cell that has to stay an `int` -- one
shared with C, usually. Prefer `AtomicLong` when the width is your choice:
it is the same speed on any machine this targets and cannot wrap in
practice.

<sub>[stdlib/Threading.sl:411](../../stdlib/Threading.sl#L411)</sub>

#### Load *method*

```
int Load()
```

The value now, stale the moment it is returned.

<sub>[stdlib/Threading.sl:418](../../stdlib/Threading.sl#L418)</sub>

#### Store *method*

```
void Store(int value)
```

Overwrites the value, losing whatever was there.

<sub>[stdlib/Threading.sl:421](../../stdlib/Threading.sl#L421)</sub>

#### Add *method*

```
int Add(int delta)
```

Adds and returns the new value. Wraps at 32 bits, silently, which is
the reason to prefer `AtomicLong` where the width is a free choice.

<sub>[stdlib/Threading.sl:425](../../stdlib/Threading.sl#L425)</sub>

#### Increment *method*

```
int Increment()
```

Adds one and returns the new value.

<sub>[stdlib/Threading.sl:428](../../stdlib/Threading.sl#L428)</sub>

#### Decrement *method*

```
int Decrement()
```

Subtracts one and returns the new value.

<sub>[stdlib/Threading.sl:431](../../stdlib/Threading.sl#L431)</sub>

#### Exchange *method*

```
int Exchange(int value)
```

Stores `value` and returns what was there before.

<sub>[stdlib/Threading.sl:434](../../stdlib/Threading.sl#L434)</sub>

#### CompareExchange *method*

```
bool CompareExchange(int expected, int desired)
```

Stores `desired` only if the current value is `expected`, and reports
whether it did. A false answer means somebody else got there first --
re-read and try again, which is the shape of every lock-free loop.

<sub>[stdlib/Threading.sl:439](../../stdlib/Threading.sl#L439)</sub>

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

<sub>[stdlib/Threading.sl:360](../../stdlib/Threading.sl#L360)</sub>

#### Load *method*

```
long Load()
```

The value now. A read of a moving counter is stale the moment it is
returned, so this is for reporting; `Add` and `CompareExchange` are
what a decision is built on.

<sub>[stdlib/Threading.sl:369](../../stdlib/Threading.sl#L369)</sub>

#### Store *method*

```
void Store(long value)
```

Overwrites the value, losing whatever was there. `Exchange` is the one
that tells you what it replaced.

<sub>[stdlib/Threading.sl:373](../../stdlib/Threading.sl#L373)</sub>

#### Add *method*

```
long Add(long delta)
```

Adds and returns the new value, so two threads never see the same result.

<sub>[stdlib/Threading.sl:376](../../stdlib/Threading.sl#L376)</sub>

#### Increment *method*

```
long Increment()
```

Adds one and returns the new value, so two threads never see the same
number. Note that this is not C's `++`, which answers the old one.

<sub>[stdlib/Threading.sl:380](../../stdlib/Threading.sl#L380)</sub>

#### Decrement *method*

```
long Decrement()
```

Subtracts one and returns the new value. A reference count reaching
zero is exactly one thread's result.

<sub>[stdlib/Threading.sl:384](../../stdlib/Threading.sl#L384)</sub>

#### Exchange *method*

```
long Exchange(long value)
```

Stores `value` and returns what was there before.

<sub>[stdlib/Threading.sl:387](../../stdlib/Threading.sl#L387)</sub>

#### CompareExchange *method*

```
bool CompareExchange(long expected, long desired)
```

Stores `desired` only if the current value is `expected`, and reports
whether it did. The building block for anything lock-free.

<sub>[stdlib/Threading.sl:391](../../stdlib/Threading.sl#L391)</sub>

#### And *method*

```
long And(long mask)
```

Bitwise, for a set of flags several threads maintain. Each returns the
new value, as `Add` does.

<sub>[stdlib/Threading.sl:398](../../stdlib/Threading.sl#L398)</sub>

#### Or *method*

```
long Or(long mask)
```

Sets the bits in `mask`, returning the new value.

<sub>[stdlib/Threading.sl:401](../../stdlib/Threading.sl#L401)</sub>

#### Xor *method*

```
long Xor(long mask)
```

Flips the bits in `mask`, returning the new value.

<sub>[stdlib/Threading.sl:404](../../stdlib/Threading.sl#L404)</sub>

### AutoResetEvent *class*

```
threadsafe class AutoResetEvent
```

A turnstile: `Set` lets exactly one waiter through, and closes behind it.

A signal with no waiter is remembered, so the next `Wait` passes straight
away -- one signal, one pass, whichever order they happen in. A second
`Set` before anyone waits is *not* remembered, which is the difference
between this and a `Semaphore`.

<sub>[stdlib/Threading.sl:635](../../stdlib/Threading.sl#L635)</sub>

#### Wait *method*

```
void Wait()
```

Blocks until the turnstile is armed, then passes and closes it behind.
Exactly one waiter passes per `Set`.

<sub>[stdlib/Threading.sl:655](../../stdlib/Threading.sl#L655)</sub>

#### WaitFor *method*

```
bool WaitFor(ulong milliseconds)
```

The same with a deadline. Answers whether it got through; a false
leaves the turnstile as it found it.

<sub>[stdlib/Threading.sl:664](../../stdlib/Threading.sl#L664)</sub>

#### Set *method*

```
void Set()
```

Lets one waiter through, or arms the next one.

<sub>[stdlib/Threading.sl:680](../../stdlib/Threading.sl#L680)</sub>

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

<sub>[stdlib/Threading.sl:778](../../stdlib/Threading.sl#L778)</sub>

#### SignalAndWait *method*

```
long SignalAndWait()
```

Blocks until every participant has arrived. Returns the number of the
phase that just finished.

<sub>[stdlib/Threading.sl:805](../../stdlib/Threading.sl#L805)</sub>

#### ParticipantCount *method*

```
nuint ParticipantCount()
```

How many participants the barrier was made for. Fixed, so unlike most
readings here it cannot be stale.

<sub>[stdlib/Threading.sl:827](../../stdlib/Threading.sl#L827)</sub>

### CountdownEvent *class*

```
threadsafe class CountdownEvent
```

Counts down to zero, and opens when it gets there.

The join half of fork-join, for work that `parallel` cannot bracket --
jobs handed to threads that outlive the function that started them.
Inside a `parallel` block the closing brace already does this.

<sub>[stdlib/Threading.sl:693](../../stdlib/Threading.sl#L693)</sub>

#### Signal *method*

```
bool Signal()
```

Counts one off. Returns true if that was the last one.

<sub>[stdlib/Threading.sl:712](../../stdlib/Threading.sl#L712)</sub>

#### TryAddCount *method*

```
bool TryAddCount(long count)
```

Adds work before it is started. Adding after the count reaches zero is
a race nobody wins, so it is refused rather than reopening the latch.

<sub>[stdlib/Threading.sl:725](../../stdlib/Threading.sl#L725)</sub>

#### Wait *method*

```
void Wait()
```

Blocks until the count reaches zero. Every waiter passes, and a later
`Wait` returns at once -- the latch does not re-arm.

The calling thread blocks rather than helping: this is not a `parallel`
block, so there is no queue for it to work off.

<sub>[stdlib/Threading.sl:738](../../stdlib/Threading.sl#L738)</sub>

#### WaitFor *method*

```
bool WaitFor(ulong milliseconds)
```

The same with a deadline. Answers whether the count reached zero.

<sub>[stdlib/Threading.sl:745](../../stdlib/Threading.sl#L745)</sub>

#### CurrentCount *method*

```
long CurrentCount()
```

How many signals are still outstanding. A snapshot, and stale the
moment you have it.

<sub>[stdlib/Threading.sl:760](../../stdlib/Threading.sl#L760)</sub>

### Guard&lt;T&gt; *class*

```
class Guard<T>
```

Proof that a lock is held, and the only route to what it guards.

A guard keeps its mutex alive, so the lock cannot be freed while it is
held. Releasing is the destructor's job; there is no `Unlock` to forget.

<sub>[stdlib/Threading.sl:161](../../stdlib/Threading.sl#L161)</sub>

#### Value *method*

```
T Value()
```

What the lock guards.

See the hole described on `Mutex`: what this hands back must not
outlive the guard, and nothing yet enforces it.

<sub>[stdlib/Threading.sl:172](../../stdlib/Threading.sl#L172)</sub>

#### Set *method*

```
void Set(T updated)
```

Replaces the guarded value. For a class `T` this swaps which object is
guarded; mutating the one `Value` gave back is the usual thing.

<sub>[stdlib/Threading.sl:176](../../stdlib/Threading.sl#L176)</sub>

### Job *delegate*

```
delegate void Job(byte* argument)
```

The work a pool thread runs. It is a plain function pointer, so whatever it
needs arrives as the argument -- usually an object cast to `byte*`, which
the job casts back.

<sub>[stdlib/Threading.sl:835](../../stdlib/Threading.sl#L835)</sub>

### ManualResetEvent *class*

```
threadsafe class ManualResetEvent
```

A latch that stays open once opened: every waiter passes, and every later
`Wait` returns at once until something calls `Reset`.

"Is the server up yet" is the shape it fits.

<sub>[stdlib/Threading.sl:563](../../stdlib/Threading.sl#L563)</sub>

#### Wait *method*

```
void Wait()
```

Blocks until the latch is open, and returns at once if it already is.
Every waiter passes -- the latch is not consumed.

<sub>[stdlib/Threading.sl:583](../../stdlib/Threading.sl#L583)</sub>

#### WaitFor *method*

```
bool WaitFor(ulong milliseconds)
```

The same with a deadline. Answers whether the latch was open, so a
false means the time ran out.

<sub>[stdlib/Threading.sl:591](../../stdlib/Threading.sl#L591)</sub>

#### Set *method*

```
void Set()
```

Opens the latch and releases everybody waiting.

<sub>[stdlib/Threading.sl:605](../../stdlib/Threading.sl#L605)</sub>

#### Reset *method*

```
void Reset()
```

Closes it again, so the next `Wait` blocks.

<sub>[stdlib/Threading.sl:613](../../stdlib/Threading.sl#L613)</sub>

#### IsSet *method*

```
bool IsSet()
```

Whether the latch is open *now*. `Reset` can close it before you act
on the answer, so this is for reporting rather than for deciding.

<sub>[stdlib/Threading.sl:621](../../stdlib/Threading.sl#L621)</sub>

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

    var held = queue.Lock();
    while (held.Value().IsEmpty()) { held.Wait(); }
    var item = held.Value().Take();

<sub>[stdlib/Threading.sl:196](../../stdlib/Threading.sl#L196)</sub>

#### Lock *method*

```
MonitorGuard<T> Lock()
```

Blocks until the lock is free. Keep the result in a variable -- a
temporary unlocks at the end of the statement.

<sub>[stdlib/Threading.sl:215](../../stdlib/Threading.sl#L215)</sub>

### MonitorGuard&lt;T&gt; *class*

```
class MonitorGuard<T>
```

Proof that a monitor is held, and the only route to what it guards.

<sub>[stdlib/Threading.sl:233](../../stdlib/Threading.sl#L233)</sub>

#### Value *method*

```
T Value()
```

What the monitor guards, with the same lifetime caveat as `Guard`.

<sub>[stdlib/Threading.sl:241](../../stdlib/Threading.sl#L241)</sub>

#### Set *method*

```
void Set(T updated)
```

Replaces the guarded value. Pulse afterwards if anyone is waiting on a
condition this changed -- nothing wakes on its own.

<sub>[stdlib/Threading.sl:245](../../stdlib/Threading.sl#L245)</sub>

#### Wait *method*

```
void Wait()
```

Releases the lock, waits for a pulse, and takes the lock again. Call it
in a loop that re-checks what you are waiting for.

<sub>[stdlib/Threading.sl:249](../../stdlib/Threading.sl#L249)</sub>

#### WaitFor *method*

```
bool WaitFor(ulong milliseconds)
```

The same with a deadline. Returns false if the time ran out -- and the
lock is held either way, because the predicate still has to be checked.

<sub>[stdlib/Threading.sl:253](../../stdlib/Threading.sl#L253)</sub>

#### Pulse *method*

```
void Pulse()
```

Wakes one waiter. It cannot run until this guard is dropped.

<sub>[stdlib/Threading.sl:256](../../stdlib/Threading.sl#L256)</sub>

#### PulseAll *method*

```
void PulseAll()
```

Wakes every waiter. Use it when more than one could make progress, or
when waiters are waiting for different conditions on the same value.

<sub>[stdlib/Threading.sl:260](../../stdlib/Threading.sl#L260)</sub>

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

    var guard = registry.Lock();
    guard.Value().Add(name);
    // ~Guard() unlocks here

**Known hole.** `Value()` hands out what the lock protects, and nothing yet
stops you storing it somewhere and using it after the guard has gone. C#
has the same hole and worse; Rust closes it with lifetimes. Stainless
closes it when the analysis in step 6 of docs/concurrency.md lands, and not
before. Until then this is a discipline, not a guarantee.

It used to be unsound for a class `T`: `Value()` retains what it hands out
and the caller releases it, often outside the lock, so two threads performed
an unsynchronized read-modify-write on that object's count. The count drifted
down and the object was freed while the mutex still held it. Reference counts
are atomic now, which closes that; what remains is the lifetime hole above,
which is about how long a borrowed thing lives rather than about counting.

<sub>[stdlib/Threading.sl:122](../../stdlib/Threading.sl#L122)</sub>

#### Lock *method*

```
Guard<T> Lock()
```

Blocks until the lock is free, then returns the guard that holds it.

Keep the result in a variable. `registry.Lock();` on its own locks and
then immediately unlocks, because the guard is a temporary and dies at
the end of the statement.

<sub>[stdlib/Threading.sl:140](../../stdlib/Threading.sl#L140)</sub>

#### TryLock *method*

```
Guard<T>? TryLock()
```

Takes the lock only if it is free. Returns null rather than blocking.

<sub>[stdlib/Threading.sl:146](../../stdlib/Threading.sl#L146)</sub>

### ReadGuard&lt;T&gt; *class*

```
class ReadGuard<T>
```

Shared access. There is no `Set`, which is the point.

<sub>[stdlib/Threading.sl:321](../../stdlib/Threading.sl#L321)</sub>

#### Value *method*

```
T Value()
```

What the lock guards, shared with every other reader. Treat it as
read-only: nothing stops a `T` with mutating methods being mutated
through this, and doing so races with the other readers.

<sub>[stdlib/Threading.sl:331](../../stdlib/Threading.sl#L331)</sub>

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

<sub>[stdlib/Threading.sl:276](../../stdlib/Threading.sl#L276)</sub>

#### Read *method*

```
ReadGuard<T> Read()
```

Blocks until no writer holds the lock. Other readers are welcome.

<sub>[stdlib/Threading.sl:289](../../stdlib/Threading.sl#L289)</sub>

#### TryRead *method*

```
ReadGuard<T>? TryRead()
```

Takes a read guard only if no writer holds the lock. Answers null
rather than blocking.

<sub>[stdlib/Threading.sl:296](../../stdlib/Threading.sl#L296)</sub>

#### Write *method*

```
WriteGuard<T> Write()
```

Blocks until nothing holds the lock at all.

<sub>[stdlib/Threading.sl:302](../../stdlib/Threading.sl#L302)</sub>

#### TryWrite *method*

```
WriteGuard<T>? TryWrite()
```

Takes a write guard only if nothing holds the lock at all. Answers
null rather than blocking.

<sub>[stdlib/Threading.sl:309](../../stdlib/Threading.sl#L309)</sub>

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

<sub>[stdlib/Threading.sl:484](../../stdlib/Threading.sl#L484)</sub>

#### Wait *method*

```
void Wait()
```

Blocks until a permit is available, and takes it.

<sub>[stdlib/Threading.sl:504](../../stdlib/Threading.sl#L504)</sub>

#### TryWait *method*

```
bool TryWait()
```

Takes a permit only if one is free right now.

<sub>[stdlib/Threading.sl:512](../../stdlib/Threading.sl#L512)</sub>

#### WaitFor *method*

```
bool WaitFor(ulong milliseconds)
```

Blocks for at most `milliseconds`. Returns whether it got a permit.

<sub>[stdlib/Threading.sl:521](../../stdlib/Threading.sl#L521)</sub>

#### Release *method*

```
void Release()
```

Puts one permit back and wakes a waiter.

<sub>[stdlib/Threading.sl:539](../../stdlib/Threading.sl#L539)</sub>

#### ReleaseMany *method*

```
void ReleaseMany(long count)
```

Puts several back at once, waking as many waiters as could proceed.

<sub>[stdlib/Threading.sl:542](../../stdlib/Threading.sl#L542)</sub>

#### Available *method*

```
long Available()
```

How many permits are free. A snapshot, and stale the moment you have it.

<sub>[stdlib/Threading.sl:551](../../stdlib/Threading.sl#L551)</sub>

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
    while (!ready.Load()) { spin.Once(); }

<sub>[stdlib/Threading.sl:953](../../stdlib/Threading.sl#L953)</sub>

#### Once *method*

```
void Once()
```

One step of backing off.

<sub>[stdlib/Threading.sl:960](../../stdlib/Threading.sl#L960)</sub>

#### Count *method*

```
nuint Count()
```

How many times `Once` has been called.

<sub>[stdlib/Threading.sl:975](../../stdlib/Threading.sl#L975)</sub>

#### Reset *method*

```
void Reset()
```

Starts over, for a loop that is being reused.

<sub>[stdlib/Threading.sl:978](../../stdlib/Threading.sl#L978)</sub>

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

<sub>[stdlib/Threading.sl:849](../../stdlib/Threading.sl#L849)</sub>

#### Run *method*

```
void Run(Job job, byte* argument)
```

Queues a job. It may already be running when this returns.

<sub>[stdlib/Threading.sl:857](../../stdlib/Threading.sl#L857)</sub>

#### Join *method*

```
void Join()
```

Waits for every job submitted so far. Doing it twice is harmless, which
is what lets the destructor be a backstop for a scope nobody joined.

<sub>[stdlib/Threading.sl:863](../../stdlib/Threading.sl#L863)</sub>

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

<sub>[stdlib/Threading.sl:896](../../stdlib/Threading.sl#L896)</sub>

#### Join *method*

```
void Join()
```

Waits for it to finish. Doing it twice is harmless, which is what lets
the destructor be a backstop.

<sub>[stdlib/Threading.sl:908](../../stdlib/Threading.sl#L908)</sub>

#### Detach *method*

```
void Detach()
```

Gives up the handle without waiting. The thread runs on and cleans up
after itself; nothing can join it afterwards.

<sub>[stdlib/Threading.sl:917](../../stdlib/Threading.sl#L917)</sub>

#### IsJoinable *method*

```
bool IsJoinable()
```

Whether this handle still refers to a thread -- false after `Join` or
`Detach`. It does not say whether the thread is still running.

<sub>[stdlib/Threading.sl:926](../../stdlib/Threading.sl#L926)</sub>

### WriteGuard&lt;T&gt; *class*

```
class WriteGuard<T>
```

Exclusive access.

<sub>[stdlib/Threading.sl:335](../../stdlib/Threading.sl#L335)</sub>

#### Value *method*

```
T Value()
```

What the lock guards, exclusively. Safe to mutate through.

<sub>[stdlib/Threading.sl:343](../../stdlib/Threading.sl#L343)</sub>

#### Set *method*

```
void Set(T updated)
```

Replaces the guarded value.

<sub>[stdlib/Threading.sl:346](../../stdlib/Threading.sl#L346)</sub>

## Functions

### CurrentId *function*

```
nuint CurrentId()
```

An identifier for the calling thread, unique among those running. It is the
OS's number and means nothing across a restart.

<sub>[stdlib/Threading.sl:940](../../stdlib/Threading.sl#L940)</sub>

### ProcessorCount *function*

```
nuint ProcessorCount()
```

How many hardware threads the machine reports.

<sub>[stdlib/Threading.sl:987](../../stdlib/Threading.sl#L987)</sub>

### Sleep *function*

```
void Sleep(ulong milliseconds)
```

Stops the calling thread for at least this long. It may be longer: this is
the scheduler's floor, not a timer.

<sub>[stdlib/Threading.sl:933](../../stdlib/Threading.sl#L933)</sub>

### StartPool *function*

```
void StartPool(nuint workers)
```

Starts the pool with a chosen number of workers, before any scope does it
automatically. Passing zero sizes it from the processor count.

<sub>[stdlib/Threading.sl:991](../../stdlib/Threading.sl#L991)</sub>

### WorkerCount *function*

```
nuint WorkerCount()
```

How many threads the pool is running. Zero until the first scope starts it.

<sub>[stdlib/Threading.sl:984](../../stdlib/Threading.sl#L984)</sub>

### Yield *function*

```
void Yield()
```

Offers the rest of this thread's slice to anything else that is ready.

<sub>[stdlib/Threading.sl:936](../../stdlib/Threading.sl#L936)</sub>

