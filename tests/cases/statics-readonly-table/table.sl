// SPDX-License-Identifier: 0BSD
//
// `readonly` is a promise about the slot, not about what the slot points at.
// A table allocated once and written to for the life of the program is what
// the word is for: the reference never changes, so the static is immortal and
// nothing releases it at exit, and its elements are ordinary storage.
module Table;

import Standard.Console;
import Standard.Collections;
import Standard.Convert;

public struct Pair
{
    public int Key;
    public int Value;
}

public class Counter
{
    public int Hits;
    public Counter() { Hits = 0; }
}

static readonly ulong[] s_bits = new ulong[4];
static readonly Counter s_counter = new Counter();
static readonly List<int> s_seen = new List<int>();
static readonly Pair s_pair = MakePair();

Pair MakePair()
{
    Pair made;
    made.Key = 1;
    made.Value = 2;
    return made;
}

int Main()
{
    s_bits[2u] = 0xFFu;
    s_counter.Hits = 7;
    s_seen.Add(11);

    Console.WriteLine("bits " + FromLong((long)s_bits[2u], 10u));
    Console.WriteLine("hits " + FromLong((long)s_counter.Hits, 10u));
    Console.WriteLine("seen " + FromLong((long)s_seen[0u], 10u));
    Console.WriteLine("pair " + FromLong((long)s_pair.Value, 10u));
    return 0;
}
