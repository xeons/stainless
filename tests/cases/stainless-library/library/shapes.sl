// SPDX-License-Identifier: 0BSD
//
// A library, compiled on its own and consumed by a separate compilation. It has
// no Main and never sees the program that uses it.
module Library.Shapes;

public enum Kind { Round = 0, Square = 1 }

public struct Point {
    public double X;
    public double Y;
}

// Something the consumer can watch, so a destructor running is observable as a
// value rather than as a line of output. Both sides now share one runtime and
// so one stdio buffer -- `shared-runtime` is the case that pins that -- and this
// one keeps watching a counter, because a count the consumer reads back proves
// the reference reached zero rather than that something printed.
public class Tally {
    public int Destroyed { get; set; }
}

public class Counter {
    int count;
    Tally tally;

    public String Label;
    public int Step { get; set; }

    public Counter(String label, Tally watcher) {
        Label = label;
        tally = watcher;
        count = 0;
        Step = 1;
    }

    ~Counter() { tally.Destroyed = tally.Destroyed + 1; }

    public void Bump() { count = count + Step; }
    public int Total() { return count; }
    public String Describe() { return Label + ":" + Text.FromInteger(count); }
}

/// A hierarchy, so that dispatch and the base relation both have to survive
/// being written to metadata and read back by a separate compilation. A
/// consumer may not derive from these -- the layout is compiled here and its
/// dispatch table would be built there -- but it can hold one, call it, ask
/// what it is, and cast back to it.
public class Note {
    public virtual String Body() { return "note"; }
    public virtual int Weight() { return 1; }
}

public class Urgent : Note {
    public override String Body() { return "urgent"; }
}

/// Made on this side, held as the base on the other.
public Note MakeUrgent() { return new Urgent(); }

public int KindOf(Kind kind) { return (int)kind; }

public Point Scale(Point p, double by) {
    Point scaled;
    scaled.X = p.X * by;
    scaled.Y = p.Y * by;
    return scaled;
}
