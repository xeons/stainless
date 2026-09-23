// SPDX-License-Identifier: 0BSD
//
// `record` — a class written as its constructor.
//
// The positional parameters become get-only properties and the constructor
// that fills them, and the type gets `Equals` and `GetHashCode` over all of
// them. Those two names rather than C#'s `Equals` and `GetHashCode` because
// they are what `IEquatable` and `IHashable` declare, and what a `Dictionary`
// probes with -- being usable as a key without saying anything is most of what
// the form is for, and the last case here is that.
//
// There is no `ToString`: this language has none for any type ([§3.7](../../../docs/spec/03-text.md)),
// and a record is not the place to invent one.
module Records;

import Standard.Console;
import Standard.Text;
import Standard.Collections;

/// The short form, which is a class.
public record Point(int X, int Y);

/// The same, said in full.
public record class Named(String Label, double Weight)
{
    /// A body beside the parameters, whose members are ordinary members.
    public String Describe() => Label + " " + Text.FromDouble(Weight);
}

/// One parameter, where the hash has nothing to fold against.
public record Single(int Only);

/// Several, and of different kinds.
public record Tagged(String Name, int Number, bool Flag);

void Says(String what, bool value)
{
    Console.WriteLine(what + " " + (value ? "yes" : "no"));
}

int Main()
{
    // ------------------------------------------------------ what it built

    var p = new Point(3, 4);
    Console.WriteLine("point " + Text.FromInteger((long)p.X) + "," + Text.FromInteger((long)p.Y));

    var n = new Named("widget", 1.5);
    Console.WriteLine("named " + n.Describe());

    // ---------------------------------------------------------- equality

    var same = new Point(3, 4);
    var other = new Point(3, 5);

    Says("equalto", p.Equals(same));
    Says("differs", p.Equals(other));
    Says("operator", p == same);
    Says("notoperator", p != other);

    // Equality is by value, so two objects that are not the same object are
    // still equal -- which is the whole difference from a class.
    Says("notidentity", new Point(1, 2) == new Point(1, 2));

    // ----------------------------------------------------------- hashing

    Says("hashagrees", p.GetHashCode() == same.GetHashCode());
    Says("hashdiffers", p.GetHashCode() != other.GetHashCode());
    Says("onefield", new Single(9).Equals(new Single(9)));
    Says("onefieldhash", new Single(9).GetHashCode() == new Single(9).GetHashCode());

    // Every field counts, including the last.
    var t1 = new Tagged("alpha", 1, true);
    Says("allfields", t1.Equals(new Tagged("alpha", 1, true)));
    Says("lastfield", t1.Equals(new Tagged("alpha", 1, false)));
    Says("middlefield", t1.Equals(new Tagged("alpha", 2, true)));
    Says("firstfield", t1.Equals(new Tagged("beta", 1, true)));

    // -------------------------------------------------------- as a key

    var seen = new Dictionary<Point, String>();
    seen.SetValue(new Point(1, 1), "one");
    seen.SetValue(new Point(2, 2), "two");

    // A different object with the same values finds what the first one put
    // there, which is what IEquatable and IHashable were for.
    Console.WriteLine("lookup " + seen.GetValueOrDefault(new Point(1, 1), "<missing>"));
    Console.WriteLine("missing " + seen.GetValueOrDefault(new Point(9, 9), "<missing>"));
    Console.WriteLine("count " + Text.FromInteger(seen.Count));

    // Setting the same value twice replaces rather than adds.
    seen.SetValue(new Point(1, 1), "again");
    Console.WriteLine("replaced " + seen.GetValueOrDefault(new Point(1, 1), "<missing>")
                      + " " + Text.FromInteger(seen.Count));

    return 0;
}
