// A lambda that reads a member of a class something else writes.
//
// **The capture is by value and the write is not connected to it** (spec
// §2.15): the closure holds what the member said when it was made. That is the
// language's rule and it is the right one -- a closure may outlive its object,
// and by-value capture is why there is no lifetime question to answer.
//
// It is also the one capture rule that reads like the opposite of itself.
// `if (busy)` inside a handler is a line nobody reads twice, and what it means
// is "if `busy` was set when this handler was made" -- which is almost always
// no. SL0610 is what says so.
//
// This is not a made-up shape. It is what a GUI backend's guard against
// reporting its own writes back to the program looks like, and writing it this
// way made a checked menu item set from its own click handler recurse until the
// stack ran out.
module Captured;

import Standard.Console;

public closure void Act();

public class Guarded
{
    /// Written by `Run` below, and read by the lambda in the constructor. Those
    /// two are not the same storage, which is the whole point of the warning.
    bool _busy;

    public Act Body;

    public Guarded()
    {
        // `busy = false` here is a constructor and raises nothing: a member a
        // constructor sets and nothing else changes cannot surprise a closure.
        _busy = false;

        Body = () =>
        {
            if (_busy)              // SL0610
                return;
            Console.WriteLine("ran");
        };
    }

    /// The write that makes the capture above a warning rather than a fact.
    public void Run()
    {
        _busy = true;
        Body();
        _busy = false;
    }
}

/// A property is the same question: the getter's answer is copied.
public class Counted
{
    public int Total { get; set; }

    public Act Report;

    public Counted()
    {
        Total = 0;
        Report = () => { Console.WriteLine(Text.FromInteger((long)Total)); };  // SL0610
    }

    public void Bump() => Total = Total + 1;
}

/// Nothing writes `label` outside a constructor, so capturing it is exactly
/// what it looks like and there is no warning.
public class Fixed
{
    String _label;
    public Act Say;

    public Fixed()
    {
        _label = "settled";
        Say = () => { Console.WriteLine(_label); };
    }
}

/// Naming the receiver is the fix the warning names, and it is one word:
/// `this` is captured -- an object reference, by the same by-value rule -- and
/// the field is read through it, so the closure sees what the object says when
/// it runs. No warning, and the guard works.
public class Named
{
    bool _busy;
    public Act Body;

    public Named()
    {
        _busy = false;
        Body = () =>
        {
            if (this._busy)
                return;
            Console.WriteLine("named ran");
        };
    }

    public void Run()
    {
        _busy = true;
        Body();
        _busy = false;
    }
}

/// A method call does the same thing for the same reason, and reads better
/// where the test is worth a name.
public class Correct
{
    bool _busy;
    public Act Body;

    bool Busy() => _busy;

    public Correct()
    {
        _busy = false;
        Body = () =>
        {
            if (Busy())
                return;
            Console.WriteLine("ran");
        };
    }

    public void Run()
    {
        _busy = true;
        Body();
        _busy = false;
    }
}

/// **The same guard as `Correct`, spelled as a property.** `Busy` here is a
/// bare member read, so the lambda holds the value `_busy` had when the handler
/// was built -- `false`, for ever -- and the guard never guards.
///
/// The capture is recorded against the property and the write against the
/// field, which is why this went unwarned for a while: the two are different
/// symbols and matching one list against the other found nothing. Every
/// `Echoing` guard in the GTK backend was this shape, having been converted
/// from the method form `Correct` still uses, and one of them recursed until
/// the stack ran out.
public class Stale
{
    bool _busy;
    public Act Body;

    bool Busy => _busy;

    public Stale()
    {
        _busy = false;
        Body = () =>
        {
            if (Busy)                   // SL0610
                return;
            Console.WriteLine("stale ran");
        };
    }

    public void Run()
    {
        _busy = true;
        Body();
        _busy = false;
    }
}

/// **A struct has no live spelling at all**, and the warning says so rather
/// than naming a fix that is not one. `this` in a struct method is the struct,
/// so capturing it copies the value; on a class it is a counted reference, and
/// a copy of a reference still names the one object.
public struct Tally
{
    public int Count;

    public Act Show()
    {
        return () => { Console.WriteLine("tally " + Text.FromInteger((long)Count)); };  // SL0610
    }
}

public void Main()
{
    var guarded = new Guarded();
    guarded.Run();

    var counted = new Counted();
    counted.Bump();
    counted.Report();

    new Fixed().Say();

    var named = new Named();
    named.Run();

    var correct = new Correct();
    correct.Run();

    // Prints, because the guard is a copy: `Correct` above prints nothing.
    new Stale().Run();

    Tally tally;
    tally.Count = 1;
    var show = tally.Show();
    tally.Count = 2;      // the closure holds the copy it was made with
    show();
}
