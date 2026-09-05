// SPDX-License-Identifier: 0BSD
//
// The unstructured half of Standard.Threading: threads you start yourself, and
// the things they wait on.
//
// Everything a thread touches here is a `static readonly` [Shared] object, and
// that is not incidental -- it is the ownership rule. A `spawn`ed job borrows
// the frame that spawned it, which is sound because the closing brace joins
// before that frame can go; a `Thread` has no such brace, so what it reaches
// has to outlive it.
module ThreadingClassic;

import Standard.Threading;

extern "C" int printf(byte* format, ...);

const int Workers = 8;
const int PerWorker = 500;

// ------------------------------------------------------------------ counting

static readonly AtomicLong Total = new AtomicLong(0);
static readonly AtomicInt Narrow = new AtomicInt(0);

void CountUp(byte* argument) {
    for (int i = 0; i < PerWorker; i += 1) {
        Total.Increment();
        Narrow.Increment();
    }
}

// ------------------------------------------------------- monitor: wait/pulse

/// A queue of one, so that the wait is a real wait: the consumer reaches
/// `Wait` before the producer has anything to hand over.
static readonly Monitor<long> Handoff = new Monitor<long>(0);

void Producer(byte* argument) {
    Threading.Sleep(5u);

    var held = Handoff.Lock();
    held.Set(42);
    held.Pulse();
}

// --------------------------------------------------------- semaphore: a limit

static readonly Semaphore Gate = new Semaphore(2);
static readonly AtomicLong Live = new AtomicLong(0);
static readonly AtomicLong Peak = new AtomicLong(0);

void Limited(byte* argument) {
    Gate.Wait();

    long now = Live.Increment();

    // Raise the high-water mark, and keep trying if another thread moved it
    // first. This is the shape every lock-free update has.
    long seen = Peak.Load();
    while (now > seen) {
        if (Peak.CompareExchange(seen, now)) { break; }
        seen = Peak.Load();
    }

    Threading.Sleep(2u);

    Live.Decrement();
    Gate.Release();
}

// --------------------------------------------------------------- events

static readonly ManualResetEvent Opened = new ManualResetEvent(false);
static readonly AtomicLong Passed = new AtomicLong(0);

void WaitForGate(byte* argument) {
    Opened.Wait();
    Passed.Increment();
}

static readonly AutoResetEvent Turnstile = new AutoResetEvent(false);
static readonly AtomicLong Through = new AtomicLong(0);

void PassTurnstile(byte* argument) {
    Turnstile.Wait();
    Through.Increment();
}

// --------------------------------------------------------- countdown, barrier

static readonly CountdownEvent Remaining = new CountdownEvent(Workers);

void ReportDone(byte* argument) {
    Threading.Sleep(1u);
    Remaining.Signal();
}

const int Phases = 3;

static readonly Barrier Round = new Barrier(4u);
static readonly AtomicLong PhaseSum = new AtomicLong(0);

void Marching(byte* argument) {
    for (int phase = 0; phase < Phases; phase += 1) {
        PhaseSum.Increment();
        Round.SignalAndWait();
    }
}

// ------------------------------------------------------------ reader/writer

static readonly RwLock<long> Shared = new RwLock<long>(100);
static readonly AtomicLong ReadSum = new AtomicLong(0);

void ReadIt(byte* argument) {
    for (int i = 0; i < 100; i += 1) {
        var view = Shared.Read();
        ReadSum.Add(view.Value());
    }
}

// ------------------------------------------------------------------- spinning

static readonly AtomicBool Ready = new AtomicBool(false);

void SetReady(byte* argument) {
    Threading.Sleep(5u);
    Ready.Store(true);
}

// ------------------------------------------------------------------- driving

Thread[] StartAll(Job body, int count) {
    var pool = new Thread[(nuint)count];
    for (int i = 0; i < count; i += 1) {
        pool[(nuint)i] = new Thread(body, null);
    }
    return pool;
}

void JoinAll(Thread[] pool) {
    foreach (var one in pool) { one.Join(); }
}

int Main() {
    // -------------------------------------------------- one thread, joined

    var single = new Thread(CountUp, null);
    printf("joinable      = %d\n", single.IsJoinable());
    single.Join();
    printf("afterJoin     = %d\n", single.IsJoinable());
    printf("oneWorker     = %lld\n", Total.Load());

    // ------------------------------------------------------------ counting

    JoinAll(StartAll(CountUp, Workers));
    printf("counted       = %lld\n", Total.Load());
    printf("narrow        = %d\n", Narrow.Load());

    // ------------------------------------------------------- wait and pulse

    var producer = new Thread(Producer, null);

    // A bare block, because a guard is released when its scope ends and there
    // is no way to put it down early: assigning null to a non-nullable
    // reference is what the compiler refuses, and rightly.
    {
        var held = Handoff.Lock();
        while (held.Value() == 0) { held.Wait(); }
        printf("handedOver    = %lld\n", held.Value());
    }

    producer.Join();

    // ------------------------------------------------------------ the limit

    JoinAll(StartAll(Limited, Workers));
    printf("everyoneRan   = %lld\n", Live.Load());
    printf("neverOverTwo  = %d\n", Peak.Load() <= 2);
    printf("reachedTwo    = %d\n", Peak.Load() >= 1);

    // -------------------------------------------------------------- events

    var waiters = StartAll(WaitForGate, Workers);
    printf("noneYet       = %lld\n", Passed.Load());
    Opened.Set();
    JoinAll(waiters);
    printf("allPassed     = %lld\n", Passed.Load());
    printf("stillOpen     = %d\n", Opened.IsSet());

    Opened.Reset();
    printf("closedAgain   = %d\n", Opened.IsSet());
    printf("timesOut      = %d\n", Opened.WaitFor(20u));

    // One `Set` lets exactly one thread through. Started one at a time on
    // purpose: with both waiting, `Set` wakes whichever the scheduler picks,
    // so joining a particular one would be a coin flip and sometimes a hang.
    var first = new Thread(PassTurnstile, null);
    Turnstile.Set();
    first.Join();
    printf("oneThrough    = %lld\n", Through.Load());

    var second = new Thread(PassTurnstile, null);
    Turnstile.Set();
    second.Join();
    printf("twoThrough    = %lld\n", Through.Load());

    // A signal with nobody waiting is remembered, so this passes immediately.
    Turnstile.Set();
    printf("remembered    = %d\n", Turnstile.WaitFor(1000u));

    // And a second one is not, so there is nothing left to take.
    printf("notCounted    = %d\n", Turnstile.WaitFor(20u));

    // ----------------------------------------------------------- countdown

    var reporters = StartAll(ReportDone, Workers);
    Remaining.Wait();
    printf("countedDown   = %lld\n", Remaining.CurrentCount());
    JoinAll(reporters);

    // ------------------------------------------------------------- barrier

    JoinAll(StartAll(Marching, 4));
    printf("phaseSum      = %lld\n", PhaseSum.Load());
    printf("participants  = %llu\n", (ulong)Round.ParticipantCount());

    // -------------------------------------------------------- reader/writer

    JoinAll(StartAll(ReadIt, 4));
    printf("readSum       = %lld\n", ReadSum.Load());

    // A read guard is held here, so a writer cannot get in and says so rather
    // than blocking forever.
    {
        var view = Shared.Read();
        printf("readerBlocks  = %d\n", Shared.TryWrite() == null);
    }

    {
        var writer = Shared.Write();
        writer.Set(7);
    }

    printf("written       = %lld\n", Shared.Read().Value());

    // ------------------------------------------------------------- spinning

    var setter = new Thread(SetReady, null);

    var spin = new SpinWait();
    while (!Ready.Load()) { spin.Once(); }

    setter.Join();
    printf("spunUntilSet  = %d\n", Ready.Load());
    printf("spunAtAll     = %d\n", spin.Count() > 0u);

    // ------------------------------------------------------------- detached

    // A detached thread is not joinable, and nothing here waits for it. It
    // touches only statics, which is why that is safe.
    var loose = new Thread(CountUp, null);
    loose.Detach();
    printf("detached      = %d\n", loose.IsJoinable());

    printf("id            = %d\n", Threading.CurrentId() != 0u);
    printf("cpus          = %d\n", Threading.ProcessorCount() > 0u);

    printf("done\n");
    return 0;
}
