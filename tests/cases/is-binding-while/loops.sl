// SPDX-License-Identifier: 0BSD
//
// `x is Some v` as the whole condition of a `while`.
//
// The binding used to be offered only on an `if`, for a reason that was about
// the spill rather than about the loop: a test whose subject is a call has to
// hold what it tested in a name, and an `if` can declare that name around
// itself because the condition runs once. A `while` asks again on every pass,
// so the loop is entered unconditionally and left by the test, with the spill
// at the top of the body where it happens again each time.
//
// What that has to get right is here: a fresh subject per pass, `continue`
// re-testing rather than looping on a stale value, `break` leaving, the name
// gone afterwards, and every object the spill held released.
module Loops;

import Standard.Console;
import Standard.Text;
import Standard.Collections;

class Counted
{
    public static int Live = 0;
    public int Tag;
    public Counted(int tag) { Tag = tag; Live = Live + 1; }
    ~Counted() { Live = Live - 1; }
}

// A call, so the test has something to spill.
Optional<int> TakeLast(List<int> from)
{
    if (from.Count == 0u)
        return None;
    int last = from[from.Count - 1u];
    from.RemoveAt(from.Count - 1u);
    return Some(last);
}

Optional<Counted> TakeCounted(List<int> from)
{
    if (from.Count == 0u)
        return None;
    int tag = from[from.Count - 1u];
    from.RemoveAt(from.Count - 1u);
    return Some(new Counted(tag));
}

List<int> Numbers(int upto)
{
    var made = new List<int>();
    for (int i = 1; i <= upto; i++)
        made.Add(i);
    return made;
}

int Main()
{
    // The subject is a call, so it is taken again on every pass.
    var items = Numbers(4);
    long total = 0;
    while (TakeLast(items) is Some got)
        total = total + (long)got.Value;
    Console.WriteLine("drained " + Text.FromInteger(total)
                      + " left " + Text.FromInteger((long)items.Count));

    // A local needs no spill, so the loop keeps its ordinary shape.
    Optional<int> held = Some(7);
    int rounds = 0;
    while (held is Some one)
    {
        rounds++;
        total = total + (long)one.Value;
        held = None;
    }
    Console.WriteLine("local " + Text.FromInteger((long)rounds)
                      + " " + Text.FromInteger(total));

    // continue re-takes and re-tests; break leaves.
    var again = Numbers(5);
    long odds = 0;
    while (TakeLast(again) is Some n)
    {
        if (n.Value == 4)
            continue;
        if (n.Value == 2)
            break;
        odds = odds + (long)n.Value;
    }
    Console.WriteLine("odds " + Text.FromInteger(odds)
                      + " unread " + Text.FromInteger((long)again.Count));

    // The name is a copy of the payload, and the body may write through it
    // without the next pass seeing it.
    var third = Numbers(3);
    long doubled = 0;
    while (TakeLast(third) is Some each)
    {
        int mine = each.Value * 2;
        doubled = doubled + (long)mine;
    }
    Console.WriteLine("doubled " + Text.FromInteger(doubled));

    // Every object the spill held must go: a count that climbed with the
    // iterations would be the spill never released.
    var counted = Numbers(64);
    long tags = 0;
    while (TakeCounted(counted) is Some one)
        tags = tags + (long)one.Value.Tag;
    Console.WriteLine("tags " + Text.FromInteger(tags)
                      + " live " + Text.FromInteger((long)Counted.Live));

    return 0;
}
