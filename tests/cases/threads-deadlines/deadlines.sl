// SPDX-License-Identifier: 0BSD
module Deadlines;

import Standard.Console;
import Standard.Threading;
import Standard.Time;

// Release(0) broadcasts with no permit to take, which is a wake the
// waiter MUST NOT treat as a fresh start of its timeout.
void Nudge(byte* argument)
{
    var permits = (Semaphore)argument;
    for (int i = 0; i < 150; i++)
    {
        permits.Release(0);
        Sleep(10);
    }
}

// Set then Reset: a waiter woken by the first finds the latch closed again.
void Flicker(byte* argument)
{
    var latch = (ManualResetEvent)argument;
    for (int i = 0; i < 150; i++)
    {
        latch.Set();
        latch.Reset();
        Sleep(10);
    }
}

void Drain(byte* argument)
{
    var countdown = (CountdownEvent)argument;
    Sleep(100);
    countdown.TryAddCount(-2);
}

void CheckSemaphore()
{
    var permits = new Semaphore(0);
    var nudger = new Thread(Nudge, (byte*)permits);

    var clock = new Stopwatch();
    bool took = permits.WaitFor(100);
    long spent = (long)clock.Elapsed.TotalMilliseconds;
    Console.WriteLine($"semaphore took {took}, bounded {spent < 1000}");
    nudger.Join();
}

void CheckManualReset()
{
    var latch = new ManualResetEvent(false);
    var flicker = new Thread(Flicker, (byte*)latch);

    var clock = new Stopwatch();
    latch.WaitFor(100);
    long spent = (long)clock.Elapsed.TotalMilliseconds;
    Console.WriteLine($"manual reset bounded {spent < 1000}");
    flicker.Join();
}

void CheckTimeouts()
{
    var turnstile = new AutoResetEvent(false);
    Console.WriteLine($"auto reset {turnstile.WaitFor(20)}");
    turnstile.Set();
    Console.WriteLine($"auto reset armed {turnstile.WaitFor(20)}");

    var countdown = new CountdownEvent(1);
    Console.WriteLine($"countdown {countdown.WaitFor(20)}");
    Console.WriteLine($"semaphore zero wait {new Semaphore(0).WaitFor(0)}");
}

void CheckCountdown()
{
    var countdown = new CountdownEvent(1);
    Console.WriteLine($"signal last {countdown.Signal()}");
    Console.WriteLine($"signal extra {countdown.Signal()}");

    var draining = new CountdownEvent(2);
    var drainer = new Thread(Drain, (byte*)draining);
    var clock = new Stopwatch();
    bool drained = draining.WaitFor(5000);
    long spent = (long)clock.Elapsed.TotalMilliseconds;
    Console.WriteLine($"drained by a negative count {drained}, woken {spent < 2500}");
    drainer.Join();
    Console.WriteLine($"remaining {draining.CurrentCount}");
}

public int Main()
{
    CheckSemaphore();
    CheckManualReset();
    CheckTimeouts();
    CheckCountdown();
    return 0;
}
