// SPDX-License-Identifier: 0BSD
module Futures;

import Standard.Console;
import Standard.Threading;

int Doubled(int value)
{
    Sleep(20u);
    return value * 2;
}

/// A future that outlives the function that started it. This is the whole
/// reason the type exists: a `parallel` block joins before it returns, so it
/// has no way to hand back work that is still running.
Future<int> Later(int value) => new Future<int>(() => Doubled(value));

static readonly AtomicLong Counted = new AtomicLong(0);

void Bump(byte* argument) => Counted.Add(35);

int Main()
{
    // The value is computed on a thread of its own, and `Get` waits for it.
    int input = 21;
    var answer = new Future<int>(() => Doubled(input));
    Console.WriteLine("started");
    Console.WriteLine(Text.FromInteger(answer.GetResult()));

    // Filled once, read as often as you like.
    Console.WriteLine(Text.FromInteger(answer.GetResult()));

    // The starting frame is long gone by the time this is asked.
    var escaped = Later(50);
    Console.WriteLine(Text.FromInteger(escaped.GetResult()));
    Console.WriteLine(escaped.IsReady ? "ready" : "not ready");

    // Several at once, each on its own thread.
    var first = new Future<int>(() => Doubled(1));
    var second = new Future<int>(() => Doubled(2));
    var third = new Future<int>(() => Doubled(3));
    Console.WriteLine(Text.FromInteger(first.GetResult() + second.GetResult() + third.GetResult()));

    // A thread from a closure: it carries what it captured, so there is no
    // frame for it to outlive and no `byte*` to keep alive by hand.
    var tally = new AtomicLong(0);
    var worker = new Thread(() => tally.Add(7));
    worker.Join();
    Console.WriteLine(Text.FromInteger((int)tally.Read()));

    // The raw form still works. It owns nothing, so what it touches has to
    // outlive it on its own -- here a static, which outlives everything.
    var raw = new Thread(Bump, null);
    raw.Join();
    Console.WriteLine(Text.FromInteger((int)Counted.Read()));

    return 0;
}
