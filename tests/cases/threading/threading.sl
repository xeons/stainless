// SPDX-License-Identifier: 0BSD
module Threading;

import Standard.Threading;

extern "C" int printf(byte* format, ...);

const int Jobs = 64;
const int PerJob = 500;

// Each job receives its object as a raw pointer and casts it back. That is the
// callback-with-context shape, and for now nothing checks it -- the sendability
// analysis that would is step 6 of docs/concurrency.md.

/// Increments a guarded counter, taking and dropping the lock every time.
/// If the guard's destructor did not unlock, the second iteration would hang.
void BumpGuarded(byte* argument) {
    var counter = (Mutex<long>)argument;

    for (int i = 0; i < PerJob; i = i + 1) {
        var guard = counter.Lock();
        guard.Set(guard.Value() + 1);
    }
}

/// The same count without a lock. A plain `cell = cell + 1` here would lose
/// updates on 31 threads; the atomic is what makes the total exact.
void BumpAtomic(byte* argument) {
    var counter = (AtomicLong)argument;

    for (int i = 0; i < PerJob; i = i + 1) {
        counter.Increment();
    }
}

int Main() {
    var guarded = new Mutex<long>(0);
    var counted = new AtomicLong(0);

    {
        var scope = new TaskScope();
        for (int i = 0; i < Jobs; i = i + 1) {
            scope.Run(BumpGuarded, (byte*)guarded);
            scope.Run(BumpAtomic, (byte*)counted);
        }
        scope.Join();
    }

    printf("workers>0=%d\n", WorkerCount() > 0 ? 1 : 0);

    {
        var guard = guarded.Lock();
        printf("guarded=%lld\n", guard.Value());
    }

    printf("counted=%lld\n", counted.Load());

    // The lock is free again, which is only true if every guard above unlocked.
    {
        var free = guarded.TryLock();
        printf("tryWhenFree=%d\n", free != null ? 1 : 0);
    }

    var flag = new AtomicBool(false);
    printf("flagStart=%d\n", flag.Load() ? 1 : 0);
    printf("flagWon=%d\n", flag.Exchange(true) ? 1 : 0);
    printf("flagNow=%d\n", flag.Load() ? 1 : 0);

    var swap = new AtomicLong(10);
    printf("casOk=%d\n", swap.CompareExchange(10, 20) ? 1 : 0);
    printf("casNo=%d\n", swap.CompareExchange(10, 30) ? 1 : 0);
    printf("casValue=%lld\n", swap.Load());

    // A mutex over a reference type: the guard hands out the object, and it is
    // mutated through the lock rather than replaced.
    var shared = new Mutex<AtomicLong>(new AtomicLong(7));
    {
        var guard = shared.Lock();
        guard.Value().Add(35);
    }
    {
        var guard = shared.Lock();
        printf("shared=%lld\n", guard.Value().Load());
    }

    printf("done\n");
    return 0;
}
