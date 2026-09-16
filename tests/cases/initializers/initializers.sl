// SPDX-License-Identifier: 0BSD
//
// Four things that are all one idea: a value written where the storage is
// declared, and a value written where the object is made.
//
//   int Width = 80;                 a field initializer
//   int W { get; set; } = 80;       which an automatic property owns too
//   new Panel { Width = 3 }         an object initializer
//   new List<int> { 1, 2 }          and a collection one
//
// The first two run at the head of every constructor; the last two are short
// for writes after the construction, and are lowered to exactly that.
module Initializers;

import Standard.Console;
import Standard.Text;
import Standard.Collections;

public const int Wide = 80;

public class Watch
{
    public int Destroyed;
}

public class Panel
{
    public int Width = Wide;
    public String Title = "untitled";
    public bool Visible { get; set; } = true;
    public int Id { get; } = 7;
    public int Height;

    int _hits = 0;

    public Panel() { }

    /// The body has the last word: the initializer ran before it.
    public Panel(String title) => Title = title;

    /// Chaining to another constructor runs the initializers there and not
    /// again here, so `Width` is 10 rather than 80 at the end of this.
    public Panel(String title, int width)
    {
        this(title);
        Width = width;
    }

    public String Describe()
    {
        return Title + " " + Text.FromInteger(Width) + " " + Text.FromInteger(Height) +
               " " + Text.FromBool(Visible) + " " + Text.FromInteger(Id) +
               " " + Text.FromInteger(_hits);
    }
}

/// No constructor at all, so one is made to run the initializers in.
public class Counter
{
    public String Name = "counter";
    public int Value = 3;
}

public class Framed : Panel
{
    public int Border = 2;

    public Framed() => base("framed");

    public String More() => Describe() + " " + Text.FromInteger(Border);
}

/// Something with a destructor, to show the lowering leaks nothing: an object
/// initializer is a name holding the construction and then some writes, and
/// the name is the temporary the statement already dropped.
public class Tracked
{
    Watch _watch;

    public String Label = "none";

    public Tracked(Watch w) => _watch = w;

    ~Tracked() { _watch.Destroyed = _watch.Destroyed + 1; }
}

int Main()
{
    Console.WriteLine(new Panel().Describe());
    Console.WriteLine(new Panel("named").Describe());
    Console.WriteLine(new Panel("both", 10).Describe());

    var counter = new Counter();
    Console.WriteLine(counter.Name + " " + Text.FromInteger(counter.Value));

    Console.WriteLine(new Framed().More());

    // An object initializer, over a field and over a property.
    var written = new Panel { Title = "written", Width = 12, Visible = false, Height = 4 };
    Console.WriteLine(written.Describe());

    // With constructor arguments as well: the arguments run first, then these.
    var both = new Panel("ctor") { Height = 9 };
    Console.WriteLine(both.Describe());

    // It is an expression, so it can be passed straight on.
    Console.WriteLine(Describe(new Panel { Title = "inline" }));

    // A collection initializer, which is one `Add` per element -- found by
    // name, the way `foreach` finds `GetEnumerator`.
    var numbers = new List<int> { 1, 2, 3 };
    int total = 0;

    foreach (int n in numbers)
        total += n;

    Console.WriteLine(Text.FromInteger(total) + " of " + Text.FromInteger((int)numbers.Count));

    var names = new List<String> { "a", "b" };
    Console.WriteLine(", ".Join(names.ToArray()));

    // And nothing is left behind by either half.
    var watch = new Watch();
    {
        var one = new Tracked(watch) { Label = "kept" };
        Console.WriteLine(one.Label);
    }
    Console.WriteLine(Text.FromInteger(watch.Destroyed));
    return 0;
}

String Describe(Panel p) => p.Title + "/" + Text.FromInteger(p.Width);
