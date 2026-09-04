// SPDX-License-Identifier: 0BSD
module Threads;

// Drives the runtime job pool from C; see native.c. The language cannot spawn
// work itself yet, so this reaches the pool the way any C consumer would.
extern "C" {
    int  printf(byte* format, ...);
    long c_parallel_sum(long count);
    long c_nested_count(long depth, long branch);
    long c_worker_count();
}

class Counter {
    int value;

    Counter(int start) { value = start; }

    public int Get() { return value; }
    public void Bump() { value = value + 1; }
}

// Called concurrently from every pool worker. Each call allocates, aliases,
// mutates and destroys entirely within one thread, which is exactly the
// ownership rule docs/concurrency.md relies on: the counts stay non-atomic
// because no two threads ever touch one object.
export "C" int sl_worker(int seed) {
    int total = 0;

    for (int i = 0; i < 16; i = i + 1) {
        var counter = new Counter(seed + i);
        var alias = counter;            // +1, so the object outlives neither alone
        alias.Bump();
        total = total + counter.Get();  // the alias mutated the same object
    }                                   // both released; destroyed on this thread

    // A literal is immortal and shared by every thread with no reference
    // traffic at all; the concatenation below allocates a fresh, thread-local
    // String each time round.
    String text = "job-" + FromInteger(seed);
    total = total + (int)text.ByteLength();

    return total;
}

int Main() {
    printf("sum=%lld\n", c_parallel_sum(1000));
    printf("nested=%lld\n", c_nested_count(3, 4));

    // Queried last: the pool starts on first use, not at program start.
    int busy = 0;
    if (c_worker_count() > 0) busy = 1;
    printf("workers>0=%d\n", busy);

    printf("done\n");
    return 0;
}
