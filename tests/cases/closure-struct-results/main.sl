// SPDX-License-Identifier: 0BSD
//
// A closure or a delegate whose result is a struct too large for registers
// answers through a slot the caller provides. What it answers is a temporary
// like any call's, so a result that is discarded, or only passed through on
// the way to another call, is released at the end of the statement.
module ClosureStructResults;

import Standard.Console;

public closure int Fn();
public closure Fn MakeFn();
public closure int Add(int x);
public closure Add AddMaker(int a);

class Tracked
{
    public int Value;
    public Tracked(int value) { Value = value; }
}

struct Pair
{
    public Tracked A;
    public Tracked B;
}

public delegate Pair PairMaker();

Pair MakePair()
{
    Pair made;
    made.A = new Tracked(1);
    made.B = new Tracked(2);
    return made;
}

int Seven() => 7;
Fn Five() => Seven;
AddMaker Adder() => (int a) => (int b) => a + b;

public int Main()
{
    MakeFn maker = Five;
    var held = maker();
    Console.WriteLine($"held      {held()}");
    Console.WriteLine($"chained   {Adder()(2)(40)}");
    maker();

    PairMaker pairs = MakePair;
    Pair kept = pairs();
    Console.WriteLine($"kept      {kept.A.Value + kept.B.Value}");
    pairs();
    Console.WriteLine($"field     {pairs().B.Value}");
    return 0;
}
