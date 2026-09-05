// SPDX-License-Identifier: 0BSD
//
// What a program gets from outside itself: its arguments, its environment,
// its standard input, the clock and a source of randomness.
//
// Everything here has to be deterministic to be a test, so a reading that
// cannot be predicted is checked for the property that must hold rather than
// for a value -- a monotonic clock does not go backwards, a seeded generator
// repeats, a number in a range is in the range.
module Environment;

import Standard.Console;
import Standard.Env;
import Standard.Time;
import Standard.Random;
import Standard.Collections;

extern "C" int printf(byte* format, ...);

int Main(String[] args) {
    // ------------------------------------------------------------ arguments

    printf("argc      = %llu\n", (ulong)args.Length);
    foreach (var one in args) { printf("  arg     %s\n", one.ToPointer()); }

    // The same list, reached from away from Main.
    printf("viaEnv    = %llu\n", (ulong)Env.ArgumentCount());
    printf("agree     = %d\n", Env.ArgumentAt(0u) == args[0u]);
    printf("program   = %d\n", Env.Program().ByteLength() > 0u);

    // --------------------------------------------------------- environment

    // A variable this test sets, so the value is known. Round-tripping it is
    // the check; what the machine already had in its environment is not.
    printf("setOk     = %d\n", Env.Set("SL_TEST_VARIABLE", "a value"));
    printf("readBack  = %s\n", Env.GetOr("SL_TEST_VARIABLE", "<missing>").ToPointer());
    printf("has       = %d\n", Env.Has("SL_TEST_VARIABLE"));

    printf("removeOk  = %d\n", Env.Remove("SL_TEST_VARIABLE"));
    printf("gone      = %d\n", !Env.Has("SL_TEST_VARIABLE"));
    printf("fallback  = %s\n", Env.GetOr("SL_TEST_VARIABLE", "<missing>").ToPointer());

    // An empty value is where the platforms part company: Windows treats
    // setting one as removal, Unix keeps an empty variable. So what is checked
    // is the part both agree on -- that it is accepted, and that reading it
    // back gives nothing either way, which is why the library says to treat
    // empty and unset alike.
    printf("emptyOk   = %d\n", Env.Set("SL_TEST_EMPTY", ""));
    printf("emptyRead = %llu\n", (ulong)Env.GetOr("SL_TEST_EMPTY", "").ByteLength());
    Env.Remove("SL_TEST_EMPTY");

    printf("names     = %d\n", Env.Names().Length > 0u);
    printf("cwd       = %d\n", Env.CurrentDirectory().ByteLength() > 0u);

    // ---------------------------------------------------------------- time

    // A date the calendar arithmetic can be checked against by hand.
    var moon = Time.FromUtc(1969, 7, 20, 20, 17, 40);
    printf("moon      = %s\n", Time.FormatIso(moon).ToPointer());
    printf("moonUnix  = %lld\n", Time.ToUnixSeconds(moon));

    var broken = Time.ToUtc(moon);
    printf("moonDay   = %d\n", broken.DayOfWeek);        // a Sunday
    printf("moonYday  = %d\n", broken.DayOfYear);

    // Before the epoch, which is where truncating division goes wrong.
    var early = Time.FromUtc(1960, 1, 1, 0, 0, 0);
    printf("early     = %s\n", Time.FormatIso(early).ToPointer());
    printf("earlyUnix = %lld\n", Time.ToUnixSeconds(early));

    // The epoch itself.
    printf("epoch     = %s\n", Time.FormatIso(Time.Epoch()).ToPointer());

    // Round trip, which is what makes the format worth having.
    var parsed = Time.ParseIso("2026-09-05T14:30:00Z");
    switch (parsed) {
        case Ok ok:
            printf("parsed    = %s\n", Time.FormatIso(ok.Value).ToPointer());
            break;
        case Fail:
            printf("parsed    = failed\n");
            break;
    }

    printf("malformed = %d\n", Time.ParseIso("not a date").Ok);
    printf("shortForm = %d\n", Time.ParseIso("2026-09-05").Ok);
    printf("badMonth  = %d\n", Time.ParseIso("2026-13-05T14:30:00Z").Ok);
    printf("feb30     = %d\n", Time.ParseIso("2026-02-30T00:00:00Z").Ok);
    printf("feb29leap = %d\n", Time.ParseIso("2024-02-29T00:00:00Z").Ok);
    printf("feb29not  = %d\n", Time.ParseIso("2026-02-29T00:00:00Z").Ok);

    printf("leap2024  = %d\n", Time.IsLeapYear(2024));
    printf("leap1900  = %d\n", Time.IsLeapYear(1900));
    printf("leap2000  = %d\n", Time.IsLeapYear(2000));
    printf("febLeap   = %d\n", Time.DaysInMonth(2024, 2));
    printf("febPlain  = %d\n", Time.DaysInMonth(2026, 2));

    // Durations, which are ordinary arithmetic on a number of nanoseconds.
    var hour = Time.FromHours(1);
    var minute = Time.FromMinutes(1);

    printf("hourSecs  = %lld\n", Time.TotalSeconds(hour));
    printf("sum       = %lld\n", Time.TotalSeconds(Time.Add(hour, minute)));
    printf("diff      = %lld\n", Time.TotalSeconds(Time.Subtract(hour, minute)));
    printf("negative  = %d\n", Time.IsNegative(Time.Subtract(minute, hour)));
    printf("format    = %s\n", Time.FormatDuration(Time.FromMilliseconds(3661004)).ToPointer());
    printf("small     = %s\n", Time.FormatDuration(Time.FromMilliseconds(42)).ToPointer());
    printf("negFormat = %s\n", Time.FormatDuration(Time.FromMilliseconds(-1500)).ToPointer());

    // Two instants an hour apart, which is a fact about the arithmetic rather
    // than about the machine's clock.
    var later = Time.Plus(moon, hour);
    printf("apart     = %lld\n", Time.TotalSeconds(Time.Since(later, moon)));

    // The wall clock is somewhere in this century, and the monotonic one does
    // not go backwards. Neither is a value that can be written down.
    var now = Time.ToUtc(Time.Now());
    printf("thisEra   = %d\n", now.Year >= 2020 && now.Year < 2200);

    var clock = new Clock();
    var first = clock.Elapsed();
    var second = clock.Elapsed();
    printf("forwards  = %d\n", Time.Compare(second, first) >= 0);

    // -------------------------------------------------------------- random

    // A seed is a promise: the same one gives the same sequence, here and on
    // any other machine.
    var left = new Random(12345);
    var right = new Random(12345);

    bool same = true;
    for (int i = 0; i < 100; i += 1) {
        if (left.NextULong() != right.NextULong()) { same = false; }
    }
    printf("repeats   = %d\n", same);

    // A different seed does not.
    var other = new Random(54321);
    printf("differs   = %d\n", new Random(12345).NextULong() != other.NextULong());

    // Every draw lands in its range, and every value in the range is drawn.
    var draws = new Random(7);
    bool inRange = true;
    var seen = new bool[6];
    for (int i = 0; i < 600; i += 1) {
        int roll = draws.NextInt(6);
        if (roll < 0 || roll >= 6) { inRange = false; }
        seen[(nuint)roll] = true;
    }
    printf("inRange   = %d\n", inRange);
    printf("allSeen   = %d\n", All(seen, s => s));

    bool unit = true;
    for (int i = 0; i < 200; i += 1) {
        double value = draws.NextDouble();
        if (value < 0.0 || value >= 1.0) { unit = false; }
    }
    printf("unit      = %d\n", unit);

    printf("between   = %d\n", InRange(draws, 10, 20));

    // A shuffle keeps every element and, on a fixed seed, is reproducible.
    var deck = new long[8];
    for (nuint i = 0u; i < deck.Length; i += 1u) { deck[i] = (long)i; }

    var shuffler = new Random(99);
    shuffler.Shuffle(deck);
    printf("shuffled  = %lld\n", Reduce(deck, (long)0, (sum, n) => sum + n));

    var again = new long[8];
    for (nuint i = 0u; i < again.Length; i += 1u) { again[i] = (long)i; }
    new Random(99).Shuffle(again);
    printf("sameOrder = %d\n", SameOrder(deck, again));

    // Bytes from the platform, which cannot be predicted and can only be
    // checked for having arrived at all.
    var noise = new byte[32];
    printf("entropy   = %d\n", Random.Bytes(noise));

    // ---------------------------------------------------------------- stdin

    var firstLine = Console.ReadLine();
    if (firstLine == null) { printf("line1     = <none>\n"); }
    else { printf("line1     = %s\n", firstLine.ToPointer()); }

    var blank = Console.ReadLine();
    if (blank == null) { printf("line2     = <none>\n"); }
    else { printf("line2     = [%llu bytes]\n", (ulong)blank.ByteLength()); }

    printf("rest      = %s", Console.ReadToEnd().ToPointer());
    printf("atEnd     = %d\n", Console.AtEnd());

    var afterEnd = Console.ReadLine();
    printf("pastEnd   = %d\n", afterEnd == null);

    printf("done\n");
    return 0;
}

/// A hundred draws, all inside the half-open range asked for.
bool InRange(Random source, long low, long high) {
    for (int i = 0; i < 100; i += 1) {
        long drawn = source.NextBetween(low, high);
        if (drawn < low || drawn >= high) { return false; }
    }
    return true;
}

bool SameOrder(long[] left, long[] right) {
    if (left.Length != right.Length) { return false; }
    for (nuint i = 0u; i < left.Length; i += 1u) {
        if (left[i] != right[i]) { return false; }
    }
    return true;
}
