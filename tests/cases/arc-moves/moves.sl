// SPDX-License-Identifier: 0BSD
//
// A value made at +1 is moved into what keeps it rather than retained there
// and released at the end of the statement. Every shape that moves one is
// here, with a destructor saying when each object goes, and every path a
// `try` can leave partway through, which is where a moved value has nothing
// but the statement's list to release it.
module Moves;

import Standard.Console;
import Standard.Collections;

extern "C" int printf(byte* format, ...);

public enum Woe { None, Bad }

class Thing
{
    public int N;
    public Thing? Next;

    public Thing(int n) { N = n; }
    ~Thing() { printf("  ~Thing %d\n", N); }
}

struct Pair
{
    public Thing First;
    public Thing Second;

    public Pair(Thing first, Thing second)
    {
        First = first;
        Second = second;
    }
}

class Box
{
    public Thing? Held;
    public Thing? Other;
    public weak Thing? Watched;
}

public interface IReader { int Read(); }

Thing Make(int n) => new Thing(n);

Thing? Maybe(int n) => n > 0 ? new Thing(n) : null;

int NumberOf(Thing? thing)
{
    if (thing is null)
        return 0;
    return thing.N;
}

void Report(Result<int, Woe> given)
{
    var held = given;
    if (held.Ok)
        printf("  = %d\n", held.Value);
    else
        printf("  refused\n");
}

Result<Thing, Woe> Succeed(int n) => Ok(new Thing(n));

Result<Thing, Woe> Refuse() => Fail(Woe.Bad);

int Weigh(Thing first, Thing second) => first.N + second.N;

Pair MakePair(int n) => new Pair(Make(n), Make(n + 1));

Pair PassPair(Pair given) => given;

Thing HandOver(int n)
{
    var made = Make(n);
    var other = Make(n + 1);
    return made;
}

Pair HandOverPair(int n)
{
    var pair = MakePair(n);
    return pair;
}

Result<int, Woe> BuildTuple(bool fail)
{
    var made = (Make(1), fail ? try Refuse() : Make(2));
    return Ok(made.Item1.N + made.Item2.N);
}

Result<int, Woe> BuildObject(bool fail)
{
    var made = new Pair(Make(3), fail ? try Refuse() : Make(4));
    return Ok(made.First.N + made.Second.N);
}

Result<int, Woe> BuildArray(bool fail)
{
    Thing[] made = [Make(5), fail ? try Refuse() : Make(6)];
    return Ok(made[0].N + made[1].N);
}

Result<int, Woe> BuildInitialized(bool fail)
{
    var made = new Box { Held = Make(7), Other = fail ? try Refuse() : Make(70) };
    return Ok(NumberOf(made.Held) + NumberOf(made.Other));
}

Result<int, Woe> SliceMade(bool fail)
{
    Thing[] all = [Make(8), Make(9)];
    var part = all[(nuint)(fail ? (try Refuse()).N : 1):];
    return Ok(part[0].N);
}

Result<int, Woe> Unwrapped()
{
    var kept = try Succeed(10);
    return Ok(kept.N);
}

int Main()
{
    Console.WriteLine("local");
    {
        var kept = Make(11);
        var copied = kept;
        printf("  %d %d\n", kept.N, copied.N);
    }

    Console.WriteLine("assigned");
    {
        var box = new Box();
        box.Held = Make(12);
        box.Held = Make(13);
        box.Held = box.Held;
        printf("  %d\n", NumberOf(box.Held));
    }

    Console.WriteLine("chained");
    {
        Thing? first = null;
        Thing? second = null;
        first = second = Make(14);
        printf("  %d %d\n", NumberOf(first), NumberOf(second));
    }

    Console.WriteLine("conditional");
    {
        var borrowed = Make(15);
        for (int i = 0; i < 2; i++)
        {
            var chosen = i == 0 ? Make(16) : borrowed;
            printf("  chose %d\n", chosen.N);
            printf("  weighed %d\n", Weigh(i == 0 ? borrowed : Make(17), chosen));
            printf("  in place %d\n", Weigh(i == 0 ? borrowed : chosen, chosen));
        }
    }

    Console.WriteLine("fallback");
    {
        var fallback = Make(18);
        var found = Maybe(19) ?? fallback;
        var missing = Maybe(0) ?? fallback;
        var fresh = Maybe(0) ?? Make(20);
        printf("  %d %d %d\n", found.N, missing.N, fresh.N);
        printf("  %d\n", Maybe(21)?.N ?? 0);
    }

    Console.WriteLine("switch");
    {
        for (int i = 0; i < 3; i++)
        {
            var picked = i switch
            {
                0 => Make(22),
                1 => i > 0 ? Make(23) : Make(24),
                _ => Make(25),
            };
            printf("  %d\n", picked.N);
        }
    }

    Console.WriteLine("struct");
    {
        var pair = MakePair(26);
        var copy = pair;
        var passed = PassPair(copy);
        var chosen = pair.First.N > 0 ? MakePair(28) : pair;
        printf("  %d %d %d\n", passed.Second.N, chosen.First.N, copy.First.N);
    }

    Console.WriteLine("handed over");
    {
        var kept = HandOver(34);
        var pair = HandOverPair(36);
        printf("  %d %d %d\n", kept.N, pair.First.N, pair.Second.N);
    }

    Console.WriteLine("bound");
    {
        var box = new Box();
        box.Held = Make(38);
        if (box.Held is Thing held)
        {
            box.Held = null;
            printf("  still %d\n", held.N);
        }
        printf("  after\n");
    }

    Console.WriteLine("weak");
    {
        var box = new Box();
        var target = Make(30);
        box.Watched = target;
        Thing? strong = box.Watched;
        printf("  %d\n", NumberOf(strong));
    }

    Console.WriteLine("collections");
    {
        var list = new List<Thing> { Make(31), Make(32) };
        List<String> words = ["a", "b" + "c"];
        printf("  %d %d\n", (int)list.Count, (int)words.Count);
    }

    Console.WriteLine("closure");
    {
        var captured = Make(33);
        IReader read = () => captured.N;
        printf("  %d\n", read.Read());
    }

    Console.WriteLine("partway");
    Report(BuildTuple(false));
    Report(BuildTuple(true));
    Report(BuildObject(false));
    Report(BuildObject(true));
    Report(BuildArray(false));
    Report(BuildArray(true));
    Report(BuildInitialized(false));
    Report(BuildInitialized(true));
    Report(SliceMade(false));
    Report(SliceMade(true));
    Report(Unwrapped());

    Console.WriteLine("done");
    return 0;
}
