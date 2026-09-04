// SPDX-License-Identifier: 0BSD
//
// The consumer. It has the library's metadata and its import library, and no
// source: every type below was declared in a compilation this one never saw.
module App;

import Standard.Console;
import Library.Shapes;

int Main() {
    var tally = new Tally();

    {
        // Allocated through the library's TypeInfo, so the object gets the
        // destructor the library compiled for it.
        var counter = new Counter("clicks", tally);
        counter.Step = 3;
        counter.Bump();
        counter.Bump();

        Console.WriteLine(counter.Describe());          // a String the library made
        Console.WriteLine(Text.FromInteger(counter.Total()));
        Console.WriteLine(Text.FromInteger(counter.Step));
        Console.WriteLine(counter.Label);

        Console.WriteLine(Text.FromInteger(tally.Destroyed));
    }

    // Reference counting reaches across the boundary: the local above was the
    // last reference, and the library's destructor ran when it went.
    Console.WriteLine("destroyed=" + Text.FromInteger(tally.Destroyed));

    // A virtual call across the boundary reaches the object's own
    // implementation, not the declaration the consumer can see.
    Note made = MakeUrgent();
    Console.WriteLine(made.Body());
    Console.WriteLine(Text.FromInteger(made.Weight()));
    Console.WriteLine(Text.FromBool(made is Urgent));

    // And one allocated on this side, through the library's own TypeInfo.
    Note here = new Urgent();
    Console.WriteLine(here.Body());

    Urgent back = (Urgent)made;
    Console.WriteLine(back.Body());

    Console.WriteLine(Text.FromInteger(KindOf(Kind.Square)));

    Point point;
    point.X = 1.5;
    point.Y = 2.0;
    var scaled = Scale(point, 4.0);
    Console.WriteLine(Text.FromDouble(scaled.X + scaled.Y));

    return 0;
}
