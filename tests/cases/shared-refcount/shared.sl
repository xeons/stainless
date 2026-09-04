// SPDX-License-Identifier: 0BSD
//
// Reference counts are atomic, so an object reached from more than one thread
// keeps an accurate count.
//
// The shape that used to break: the retain happens inside the lock, the guard
// dies at the return, and so the release happens outside it. Two threads then
// performed an unsynchronized read-modify-write on the count, it drifted down,
// and the object was freed while the mutex still held it. This crashed about
// one run in six.
module Shared;

import Standard.Threading;

extern "C" int printf(byte* format, ...);

const int Jobs = 16;
const int PerJob = 20000;

AtomicLong Grab(Mutex<AtomicLong> held) {
    var guard = held.Lock();
    return guard.Value();
}

void Touch(byte* argument) {
    var held = (Mutex<AtomicLong>)argument;

    for (int i = 0; i < PerJob; i = i + 1) {
        var inner = Grab(held);
        inner.Increment();
    }
}

int Main() {
    var counter = new AtomicLong(0);
    var held = new Mutex<AtomicLong>(counter);

    {
        var scope = new TaskScope();
        for (int i = 0; i < Jobs; i = i + 1) { scope.Run(Touch, (byte*)held); }
        scope.Join();
    }

    // Alive, and counted exactly: had the count drifted, this would be reading
    // freed memory rather than reporting a total.
    printf("total=%lld\n", counter.Load());
    printf("guarded=%lld\n", Grab(held).Load());
    printf("done\n");
    return 0;
}
