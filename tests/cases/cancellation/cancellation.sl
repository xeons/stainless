// SPDX-License-Identifier: 0BSD
//
// CancellationTokenSource and CancellationToken: a wait that wakes on the
// request, callbacks latest first, a registration withdrawn, CancelAfter, a
// linked source, and None.
module Cancellation;

import Standard.Console;
import Standard.Collections;
import Standard.Threading;
import Standard.Time;

void CheckWaitWakesOnCancel()
{
    var source = new CancellationTokenSource();
    var token = source.Token;
    var canceller = new Thread(() =>
    {
        Sleep(50);
        source.Cancel();
    });

    var clock = new Stopwatch();
    bool cancelled = token.WaitFor(10000u);
    long spent = (long)clock.Elapsed.TotalMilliseconds;
    Console.WriteLine($"woken {cancelled}, early {spent < 5000}, requested {token.IsCancellationRequested}");
    canceller.Join();
}

void CheckTimeout()
{
    var source = new CancellationTokenSource();
    var clock = new Stopwatch();
    bool cancelled = source.Token.WaitFor(30u);
    long spent = (long)clock.Elapsed.TotalMilliseconds;
    Console.WriteLine($"timed out {!cancelled}, waited {spent >= 25}");
}

void CheckCallbacks()
{
    var source = new CancellationTokenSource();
    var token = source.Token;
    var order = new List<String>();
    token.Register(() => order.Add("first"));
    var withdrawn = token.Register(() => order.Add("withdrawn"));
    token.Register(() => order.Add("last"));
    withdrawn.Dispose();

    source.Cancel();
    source.Cancel();
    Console.WriteLine("callbacks " + ", ".Join(order.ToArray()));

    var late = new List<String>();
    token.Register(() => late.Add("ran at once"));
    Console.WriteLine("late " + ", ".Join(late.ToArray()));
}

void CheckCancelAfter()
{
    var source = new CancellationTokenSource();
    source.CancelAfter(40u);
    var clock = new Stopwatch();
    bool cancelled = source.Token.WaitFor(10000u);
    long spent = (long)clock.Elapsed.TotalMilliseconds;
    Console.WriteLine($"cancel after {cancelled}, bounded {spent < 5000}");
}

void CheckLinked()
{
    var outer = new CancellationTokenSource();
    var other = new CancellationTokenSource();
    var linked = CancellationTokenSource.CreateLinkedTokenSource(outer.Token, other.Token);
    Console.WriteLine($"linked before {linked.IsCancellationRequested}");
    other.Cancel();
    Console.WriteLine($"linked after {linked.IsCancellationRequested}, outer {outer.IsCancellationRequested}");
}

void CheckNone()
{
    var none = CancellationToken.None;
    bool cancelled = none.WaitFor(1u);
    none.Wait();
    Console.WriteLine($"none can be canceled {none.CanBeCanceled}, cancelled {cancelled}");
}

public int Main()
{
    CheckWaitWakesOnCancel();
    CheckTimeout();
    CheckCallbacks();
    CheckCancelAfter();
    CheckLinked();
    CheckNone();
    return 0;
}
