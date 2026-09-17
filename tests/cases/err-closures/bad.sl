// SPDX-License-Identifier: 0BSD
//
// Where a closure is refused, and why.
module Bad;

import Standard.Console;

public closure void Two(int a, int b);
public delegate void Plain(int value);

class Counter
{
    public int Total;
    public Counter() => Total = 0;
    public void Add(int value) => Total = Total + value;
}

void Uses(Counter counter)
{
    // Wrong shape for the closure.
    Two b = counter.Add;

    // A bound method carries a receiver; a delegate is one pointer.
    Plain c = counter.Add;

    // A method group nothing settles.
    var d = counter.Add;

    Console.WriteLine("unreachable");
}

public int Main() => 0;
