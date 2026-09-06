// SPDX-License-Identifier: 0BSD
//
// `do { ... } while (c);` -- the loop that asks its question afterwards.
//
// The whole of the difference from `while` is that the body runs before the
// condition is first tested, so a `do` loop always runs at least once. It is
// kept as its own thing in the bound tree rather than lowered to a `while`
// with a copy of the body: a copy would emit the body twice, and would give
// `continue` two places to go.
module DoWhile;

import Standard.Console;

public int Main() {
    // Runs three times, asking afterwards each time.
    int spins = 0;
    do { spins++; } while (spins < 3);
    Console.WriteLine($"spins  {spins}");

    // Runs once even though the condition was never true.
    int once = 0;
    do { once++; } while (false);
    Console.WriteLine($"once   {once}");

    // Which is exactly what the `while` beside it does not do.
    int never = 0;
    while (false) { never++; }
    Console.WriteLine($"never  {never}");

    // `continue` goes to the condition, as C says: it means "ask again",
    // not "start over". So the odd numbers are skipped and the loop still ends.
    int evens = 0;
    int n = 0;
    do {
        n++;
        if (n % 2 == 1) { continue; }
        evens += n;
    } while (n < 10);
    Console.WriteLine($"evens  {evens}");

    // `break` leaves it, from inside the body.
    int found = 0;
    int probe = 0;
    do {
        probe++;
        if (probe * probe > 30) { found = probe; break; }
    } while (probe < 100);
    Console.WriteLine($"found  {found}");

    // Nested, with a single statement rather than a block for a body.
    int rows = 0;
    int cells = 0;
    do {
        rows++;
        int column = 0;
        do { column++; cells++; } while (column < 3);
    } while (rows < 4);
    Console.WriteLine($"grid   {rows} by 3 is {cells}");

    // A reference counted local declared inside the body: made and dropped
    // once per turn, which is what the `-` lines below count.
    int turn = 0;
    do {
        var tag = new Tag($"turn {turn}");
        turn++;
        Console.WriteLine($"  held {tag.Name}");
    } while (turn < 2);

    Console.WriteLine("done");
    return 0;
}

class Tag {
    public String Name;
    public Tag(String name) { Name = name; }
    ~Tag() { Console.WriteLine($"  dropped {Name}"); }
}
