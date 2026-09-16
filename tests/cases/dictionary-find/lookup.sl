// SPDX-License-Identifier: 0BSD
//
// A key that is not there is an outcome, not a crash.
//
// The distinction the library draws is between a position and a key. An index
// is something the caller worked out, so `list[i]` out of range is the mistake
// `array[i]` is. A key arrives from a file, a socket or a person, so a lookup
// that misses is an ordinary answer -- and the program has to be able to carry
// on and say so.
//
// `Find` is that answer. `Get` still asserts, for a key that is there by
// construction, and this case proves the two coexist: everything below runs to
// the end, missing keys and all.
module Lookup;

import Standard.Console;
import Standard.Text;
import Standard.Collections;

String N(long v) => Text.FromInteger(v);

// A miss read the way any other variant is, which is the shape to reach for.
String Describe(Dictionary<String, int> settings, String name)
{
    if (settings.Find(name) is Some found)
        return name + "=" + N((long)found.Value);
    return name + "=unset";
}

int Main()
{
    var settings = new Dictionary<String, int>();
    settings.Set("timeout", 30);
    settings.Set("retries", 0);

    Console.WriteLine(Describe(settings, "timeout"));
    Console.WriteLine(Describe(settings, "retries"));
    Console.WriteLine(Describe(settings, "absent"));

    // `GetOr` cannot tell a missing key from one mapped to the fallback;
    // `Find` can, which is the reason it exists beside it. Both keys below
    // answer 0 to `GetOr` and different things to `Find`.
    Console.WriteLine("or " + N((long)settings.GetOr("retries", 0)) + " " +
        N((long)settings.GetOr("absent", 0)));
    Console.WriteLine("told apart " +
        (settings.Find("retries").HasValue() ? "set" : "unset") + " " +
        (settings.Find("absent").HasValue() ? "set" : "unset"));

    // The combinators come free, Optional being an ordinary variant.
    Console.WriteLine("valueOr " + N((long)settings.Find("absent").ValueOr(-1)));
    Console.WriteLine("empty " + (settings.Find("absent").IsEmpty() ? "y" : "n"));

    // A key that is there by construction: `Get` is honest here.
    Console.WriteLine("asserted " + N((long)settings.Get("timeout")));

    // Over a reference type, so the miss has a counted value to not return.
    var names = new Dictionary<int, String>();
    names.Set(1, "one");
    Console.WriteLine("ref " + names.Find(1).ValueOr("?") + " " +
        names.Find(2).ValueOr("?"));

    // `map[key]` is Swift's subscript: it answers `Optional<V>`, so it cannot
    // stop the program, and the setter takes one too -- which is what makes
    // `None` mean "remove". A value promotes to the optional holding it, so an
    // ordinary write still reads as one.
    var counts = new Dictionary<String, int>();
    counts["hits"] = 1;
    counts["misses"] = 9;

    if (counts["hits"] is Some hit)
        Console.WriteLine("subscript " + N((long)hit.Value));
    Console.WriteLine("subscript-miss " + (counts["absent"].IsEmpty() ? "empty" : "?"));
    Console.WriteLine("subscript-or " + N((long)counts["absent"].ValueOr(8080)));

    counts["misses"] = None;
    Console.WriteLine("removed " + (counts.ContainsKey("misses") ? "no" : "yes") +
        " " + N((long)counts.Count()));

    // No `+= 1`, because there is nothing to add to when the key is absent.
    // Saying what should happen instead is the point rather than the cost.
    counts["hits"] = counts["hits"].ValueOr(0) + 1;
    counts["fresh"] = counts["fresh"].ValueOr(0) + 1;
    Console.WriteLine("counted " + N((long)counts["hits"].ValueOr(-1)) + " " +
        N((long)counts["fresh"].ValueOr(-1)));

    // A sorted map answers the same four ways.
    var prices = new SortedList<String, int>();
    prices.Set("apple", 5);
    Console.WriteLine("sorted " + N((long)prices.Find("apple").ValueOr(-1)) + " " +
        N((long)prices.Find("pear").ValueOr(-1)));

    // Every miss above was survivable, and here is the proof.
    Console.WriteLine("still running");
    return 0;
}
