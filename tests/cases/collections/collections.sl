// SPDX-License-Identifier: 0BSD
module Collections;

import Standard.Console;
import Standard.Collections;

// Interfaces are named with a leading I, as in C#.
public class Money : IComparable<Money>, IEquatable<Money>
{
    int _cents;

    public Money(int amount) => _cents = amount;
    public int Cents() => _cents;

    public int CompareTo(Money other)
    {
        if (_cents < other.Cents())
            return -1;
        if (_cents > other.Cents())
            return 1;
        return 0;
    }

    public bool EqualTo(Money other) => _cents == other.Cents();

    public String Show() => Text.FromInteger(_cents) + "c";
}

// IList<T> extends IReadOnlyList<T>, so a list passed here can only be read.
String Describe(IReadOnlyList<Money> prices)
{
    var text = new StringBuilder();
    for (nuint i = 0; i < prices.Count; i = i + 1)
    {
        text.Append(prices[i].Show());
        text.Append(" ");
    }
    return text.ToText();
}

int Main()
{
    var prices = new List<Money>();
    prices.Add(new Money(250));
    prices.Add(new Money(125));
    prices.Add(new Money(999));
    prices.Add(new Money(40));
    prices.Add(new Money(600));      // grows past the initial capacity of 4

    Console.WriteLine("count    = " + Text.FromInteger(prices.Count));
    Console.WriteLine("capacity = " + Text.FromInteger(prices.Capacity));

    // A List<Money> is accepted wherever an IReadOnlyList<Money> is wanted.
    Console.WriteLine("items    = " + Describe(prices));

    Console.WriteLine("largest  = " + Largest(prices).Show());
    Console.WriteLine("smallest = " + Smallest(prices).Show());
    // `IndexOf` answers with an `Optional<nuint>`: a list's length standing in
    // for "not there" is the sentinel that type exists to retire.
    Console.WriteLine($"index of 999c = {IndexOf(prices, new Money(999)).ValueOr(99u)}");
    Console.WriteLine($"index of 1c   = {IndexOf(prices, new Money(1)).IsEmpty}");

    Sort(prices);
    Console.WriteLine("sorted   = " + Describe(prices));

    // The members that came over from .NET. `IsEmpty` is a property rather
    // than a method, which .NET has neither of -- it reads better than
    // `Count == 0` at the point of use, and docs/style.md makes a
    // zero-argument side-effect-free getter a property.
    var some = new List<Money>();
    some.Add(new Money(5));
    some.Add(new Money(9));
    some.Add(new Money(5));

    Console.WriteLine("contains = " + Text.FromBool(Contains(some, new Money(9))));
    Console.WriteLine("last of 5c = " + Text.FromInteger((long)LastIndexOf(some, new Money(5)).ValueOr(99u)));
    Console.WriteLine("exists   = " + Text.FromBool(some.Exists((m) => m.Cents() > 8)));
    Console.WriteLine("all      = " + Text.FromBool(some.TrueForAll((m) => m.Cents() > 0)));
    Console.WriteLine("found    = " + Text.FromInteger((long)some.FindAll((m) => m.Cents() == 5).Count));
    Console.WriteLine("removed  = " + Text.FromInteger((long)some.RemoveAll((m) => m.Cents() == 5)));

    some.Reverse();
    Console.WriteLine("toarray  = " + Text.FromInteger((long)some.ToArray().Length));
    Console.WriteLine("slice    = " + Text.FromInteger((long)some.Slice(0u, 1u).Count));

    // The indexer, which is the only way in: `At` and `Set` are gone, because
    // two spellings of one operation is how a codebase ends up using the
    // longer one everywhere -- which is what had happened.
    some[0u] = new Money(42);
    Console.WriteLine("indexer  = " + Text.FromInteger((long)some[0u].Cents()) + "c");

    IReadOnlyList<Money> view = some.AsReadOnly();
    Console.WriteLine("view     = " + Text.FromInteger((long)view.Count) + " " +
                      Text.FromBool(view.IsEmpty));

    prices.Clear();
    Console.WriteLine("cleared  = " + Text.FromBool(prices.IsEmpty));
    return 0;
}
