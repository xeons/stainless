// SPDX-License-Identifier: 0BSD
//
// `goto`, and the labels it names.
//
// **A label goes at the top level of a function**, and that restriction is
// what makes the reference counting decidable. A jump has to release
// everything the scopes between it and the label were holding; put a label
// inside a block and the answer would depend on which jump arrived, because
// two jumps from different depths would have different amounts to let go of.
// At the top level there is one answer: release down to the function's own
// block. Every use a `goto` is actually for fits there -- out of nested loops,
// forward to a cleanup, back to a retry.
module Goto;

import Standard.Console;

class Tag
{
    public String Name;
    public Tag(String name)
    {
        Name = name;
        Console.WriteLine($"  + {name}");
    }
    ~Tag() { Console.WriteLine($"  - {Name}"); }
}

/// Out of two loops at once, which is the thing `break` cannot do.
int FirstProduct(int wanted)
{
    for (int a = 1; a < 10; a++)
    {
        for (int b = 1; b < 10; b++)
        {
            if (a * b == wanted)
                return a * 10 + b;
        }
    }
    return -1;
}

/// The same, written with a jump, so the answer lands in one place.
int FirstProductByJump(int wanted)
{
    int answer = -1;

    for (int a = 1; a < 10; a++)
    {
        for (int b = 1; b < 10; b++)
        {
            if (a * b == wanted)
            {
                answer = a * 10 + b;
                goto found;
            }
        }
    }

found:
    return answer;
}

/// A jump forwards, over a declaration that is therefore never made.
///
/// The local it skips is a counted reference, and the block it is in still
/// releases what it holds on the way out. That is safe because an owned slot
/// is cleared on entry to the function as well as where it is declared -- so
/// the release is handed a null rather than whatever the stack had.
void Skipping(bool leave)
{
    var kept = new Tag("kept");

    if (leave)
        goto after;

    var skipped = new Tag("skipped");
    Console.WriteLine($"  saw {skipped.Name}");

after:
    Console.WriteLine("  after");
}

/// A jump backwards, out of a nested scope each time round.
void Retrying()
{
    int spins = 0;

retry:
    {
        var inner = new Tag($"inner {spins}");
        spins++;
        if (spins < 3)
            goto retry;
    }

    Console.WriteLine($"  spun {spins}");
}

public int Main()
{
    Console.WriteLine($"return {FirstProduct(6)}");
    Console.WriteLine($"jump   {FirstProductByJump(6)}");
    Console.WriteLine($"none   {FirstProductByJump(97)}");

    Console.WriteLine("skipping, leaving early:");
    Skipping(true);

    Console.WriteLine("skipping, going through:");
    Skipping(false);

    Console.WriteLine("retrying:");
    Retrying();
    return 0;
}
