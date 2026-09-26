// SPDX-License-Identifier: 0BSD
//
// `goto`, and the labels it names.
//
// **A jump may leave blocks and may not enter one**, which is C#'s rule and
// what keeps the reference counting decidable. What a jump releases is every
// scope it is in that the label is not, and that is known for each jump.

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

/// A jump backwards over a declaration runs it again, and what the last
/// run left in the local is released rather than overwritten.
void Redeclaring()
{
    int k = 0;

again:
    var held = new Tag($"again {k}");
    Tag later;
    later = new Tag($"later {k}");
    k++;
    if (k < 3)
        goto again;

    Console.WriteLine($"  kept {held.Name} {later.Name}");
}

/// A label inside a block, reached from deeper inside it.
int InsideABlock(int rounds)
{
    int total = 0;

    for (int i = 0; i < rounds; i++)
    {
        var outer = new Tag($"outer {i}");

    again:
        {
            var inner = new Tag($"inner {total}");
            total++;
            if (total % 2 == 1)
                goto again;
        }
    }

    return total;
}

/// A lambda's labels are its own, and so are a local function's.
int Separately()
{
    Func<int, int> doubling = x =>
    {
    again:
        x = x * 2;
        if (x < 100)
            goto again;
        return x;
    };

    int Counting(int n)
    {
    again:
        n++;
        if (n < 10)
            goto again;
        return n;
    }

    return doubling(3) + Counting(0);
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

    Console.WriteLine("redeclaring:");
    Redeclaring();

    Console.WriteLine("inside a block:");
    Console.WriteLine($"  total {InsideABlock(2)}");

    Console.WriteLine($"separately {Separately()}");
    return 0;
}
