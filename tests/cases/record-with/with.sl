// SPDX-License-Identifier: 0BSD
//
// `point with { Y = 5 }` — a record again, with some of it changed.
//
// It is the record's constructor called with a mixture of what was named and
// what was carried over, so the case checks that the carried-over values keep
// their positions: the middle of three is changed and the two either side have
// to arrive where they started.
//
// The last check is the one this had to be written in the binder for. The
// target is named once per field it did not supply, so a `with` that spliced
// its target in as text would evaluate it once per field -- and `Made()` would
// be called twice for a record of two.
module RecordWith;

import Standard.Console;
import Standard.Text;

public record Point(int X, int Y);
public record Three(String Name, int Number, bool Flag);

static int s_calls = 0;

/// Counts its calls, so evaluating the target more than once would show.
Point Made()
{
    s_calls++;
    return new Point(10, 20);
}

void Pair(String what, Point value)
{
    Console.WriteLine(what + " " + Text.FromInteger((long)value.X)
                      + "," + Text.FromInteger((long)value.Y));
}

int Main()
{
    var p = new Point(3, 4);

    Pair("one", p with { Y = 9 });
    Pair("first", p with { X = 8 });
    Pair("both", p with { X = 1, Y = 2 });

    // Nothing named is a copy, which is a legal thing to want.
    Pair("none", p with { });

    // The original is not touched by any of it.
    Pair("original", p);

    // What comes out is a record like any other.
    Console.WriteLine("equal " + ((p with { }) == p ? "yes" : "no"));
    Console.WriteLine("changed " + ((p with { Y = 9 }) == p ? "yes" : "no"));
    Console.WriteLine("hash " + ((p with { }).HashCode() == p.HashCode() ? "yes" : "no"));

    // The middle of three: the outer two keep their positions.
    var t = new Three("alpha", 1, true);
    var middle = t with { Number = 7 };
    Console.WriteLine("middle " + middle.Name + " " + Text.FromInteger((long)middle.Number)
                      + " " + (middle.Flag ? "true" : "false"));

    var last = t with { Flag = false };
    Console.WriteLine("last " + last.Name + " " + Text.FromInteger((long)last.Number)
                      + " " + (last.Flag ? "true" : "false"));

    // One after another, each on what the one before produced.
    Pair("chained", p with { X = 5 } with { Y = 6 });

    // A value on the right may be any expression, including one that reads the
    // target it is changing.
    Pair("computed", p with { Y = p.X + p.Y });

    // Evaluated once, whatever the record's width.
    var fromCall = Made() with { Y = 99 };
    Console.WriteLine("calls " + Text.FromInteger((long)s_calls));
    Pair("fromcall", fromCall);

    return 0;
}
