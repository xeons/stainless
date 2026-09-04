// SPDX-License-Identifier: 0BSD
module Statics;

import Standard.Console;
import Standard.Threading;

extern "C" int printf(byte* format, ...);

// Declared in the wrong order on purpose: Total reads Doubled, which reads
// Base. The compiler sorts the initializers, so this runs Base first whatever
// order they are written in -- and there is no lazy guard on any access.
static readonly int Total = Doubled + 1;
static readonly int Doubled = Base * 2;
static readonly int Base = 20;

// Plain data of every shape.
public static readonly double Ratio = 1.5;
public static readonly String Greeting = "hello";

struct Point { public int X; public int Y; }
static readonly Point Origin = MakePoint(3, 4);

Point MakePoint(int x, int y) {
    Point p;
    p.X = x;
    p.Y = y;
    return p;
}

// Mutable shared state, but only through a type that says how it is safe.
static readonly AtomicLong Hits = new AtomicLong(0);
static readonly Mutex<int> Guarded = new Mutex<int>(0);

void Bump(byte* argument) {
    Hits.Increment();

    var guard = Guarded.Lock();
    guard.Set(guard.Value() + 1);
}

int Main() {
    printf("base=%d doubled=%d total=%d\n", Base, Doubled, Total);
    printf("ratio=%g\n", Ratio);
    Console.WriteLine(Greeting);
    printf("origin=%d,%d\n", Origin.X, Origin.Y);

    // A static is reachable from every thread, which is the whole reason the
    // type rules above are what they are.
    {
        var scope = new TaskScope();
        for (int i = 0; i < 64; i = i + 1) { scope.Run(Bump, null); }
        scope.Join();
    }

    printf("hits=%lld\n", Hits.Load());

    {
        var guard = Guarded.Lock();
        printf("guarded=%d\n", guard.Value());
    }

    // Statics are readable from a parallel loop without being captured: they
    // are not locals, so there is nothing to capture.
    parallel for (int i = 0; i < 100; i = i + 1) { Hits.Add(Base); }
    printf("after=%lld\n", Hits.Load());

    printf("done\n");
    return 0;
}
