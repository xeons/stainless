// SPDX-License-Identifier: 0BSD
//
// A variable declared inside a condition, by `out var` or by a pattern, is
// written on every pass of the loop the condition belongs to. Each pass
// releases what the last one left, and what the last pass left is released
// where the loop's scope ends.
module OutVarLoop;

import Standard.Console;
import Standard.Text;

public class Tracked
{
    public String Name;
    public Tracked(String name) { Name = name; }
    ~Tracked() { Console.WriteLine("~" + Name); }
}

static int s_taken = 0;

bool TakeNext(out Tracked taken)
{
    s_taken++;
    taken = new Tracked("t" + Text.FromInteger(s_taken));
    return s_taken < 4;
}

Tracked? Produce(int i) => i < 3 ? new Tracked("p" + Text.FromInteger(i)) : null;

bool Name(out Tracked named)
{
    named = new Tracked("static");
    return true;
}

// An initializer is a scope of its own, and lets go of what it declared.
static String s_named = Name(out var held) ? held.Name : "none";

int Main()
{
    Console.WriteLine("named " + s_named);

    while (TakeNext(out var taken))
        Console.WriteLine("took " + taken.Name);
    Console.WriteLine("after the first loop");

    int i = 0;
    while (Produce(i++) is Tracked made)
        Console.WriteLine("made " + made.Name);
    Console.WriteLine("after the second loop");

    s_taken = 0;
    for (int pass = 0; pass < 3; pass++)
    {
        if (pass > 0 ? TakeNext(out var inner) : false)
            Console.WriteLine("inner " + inner.Name);
    }

    return 0;
}
