// SPDX-License-Identifier: 0BSD
//
// `init` is a setter for an object that is still being made: an object
// initializer, a `with`, and the constructors and `init` accessors of its own
// type or a type deriving from it may call it, and nothing may afterwards.
module InitAccessors;

import Standard.Console;
import Standard.Text;

public class Node
{
    public String Name;

    public Node(String name)
    {
        Name = name;
    }

    ~Node()
    {
        Console.WriteLine("released " + Name);
    }
}

public interface IIdentified
{
    int Id { get; init; }
}

public class Account : IIdentified
{
    public int Id { get; init; }
    public String Owner { get; init; } = "nobody";
    public Node? Card { get; init; }

    /// An `init` with a body, which writes another `init` property of the
    /// same object through `this`.
    public String Handle
    {
        get => field;
        init
        {
            field = "@" + value;
            this.Owner = value;
        }
    } = "";

    public Account() { }

    public Account(int id)
    {
        Id = id;
    }
}

public class Savings : Account
{
    public double Rate { get; init; }

    /// A derived constructor may set what its base declared `init`.
    public Savings(double rate)
    {
        Id = 900;
        Rate = rate;
    }
}

/// On a struct: the value is written while it is being made.
public struct Range
{
    public int Low { get; init; }
    public int High { get; init; }

    public Range(int low)
    {
        Low = low;
        High = low;
    }
}

/// A record's positional properties are `init`, and so may its own be.
public record Point(int X, int Y)
{
    public String Label { get; init; } = "point";
    public int Visits { get; set; }
}

public class Box<T>
{
    public required T Content { get; init; }
}

String Describe(Point p) =>
    Text.FromInteger(p.X) + "," + Text.FromInteger(p.Y) + " " + p.Label + " " +
    Text.FromInteger(p.Visits);

int Main()
{
    var plain = new Account { Id = 7, Card = new Node("card") };
    Console.WriteLine(Text.FromInteger(plain.Id) + " " + plain.Owner + " " + (plain.Card?.Name ?? "-"));

    Account typed = new(3) { Handle = "ada" };
    Console.WriteLine(Text.FromInteger(typed.Id) + " " + typed.Handle + " " + typed.Owner);

    IIdentified seen = new Savings(1.5) { Owner = "bank" };
    Console.WriteLine(Text.FromInteger(seen.Id));

    var range = new Range(4) { High = 9 };
    Console.WriteLine(Text.FromInteger(range.Low) + ".." + Text.FromInteger(range.High));

    var first = new Point(1, 2) { Label = "first", Visits = 4 };
    var moved = first with { Y = 5, Label = "moved" };
    var kept = first with { X = 0 };
    var direct = new Point(8, 8) { X = 9 };
    Console.WriteLine(Describe(first));
    Console.WriteLine(Describe(moved));
    Console.WriteLine(Describe(kept));
    Console.WriteLine(Describe(direct));

    var box = new Box<Node> { Content = new Node("boxed") };
    Console.WriteLine(box.Content.Name);
    return 0;
}
