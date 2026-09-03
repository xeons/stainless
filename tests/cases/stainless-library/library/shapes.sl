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

// Something the consumer can watch, so a destructor running is observable
// without printing from this side. Output from a library goes through that
// binary's own copy of the C runtime and so its own stdout buffer, which is
// why the two do not interleave predictably.
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

public int KindOf(Kind kind) { return (int)kind; }

public Point Scale(Point p, double by) {
    Point scaled;
    scaled.X = p.X * by;
    scaled.Y = p.Y * by;
    return scaled;
}
