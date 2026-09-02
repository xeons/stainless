module Collections;

import Standard.Console;
import Standard.Collections;

// Interfaces are named with a leading I, as in C#.
public class Money : IComparable<Money>, IEquatable<Money> {
    int cents;

    public Money(int amount) { cents = amount; }
    public int Cents() { return cents; }

    public int CompareTo(Money other) {
        if (cents < other.Cents()) { return -1; }
        if (cents > other.Cents()) { return 1; }
        return 0;
    }

    public bool EqualTo(Money other) { return cents == other.Cents(); }

    public String Show() { return Text.FromInteger(cents) + "c"; }
}

// IList<T> extends IReadOnlyList<T>, so a list passed here can only be read.
String Describe(IReadOnlyList<Money> prices) {
    var text = new StringBuilder();
    for (nuint i = 0; i < prices.Count(); i = i + 1) {
        text.Append(prices.At(i).Show());
        text.Append(" ");
    }
    return text.ToText();
}

int Main() {
    var prices = new List<Money>();
    prices.Add(new Money(250));
    prices.Add(new Money(125));
    prices.Add(new Money(999));
    prices.Add(new Money(40));
    prices.Add(new Money(600));      // grows past the initial capacity of 4

    Console.WriteLine("count    = " + Text.FromInteger(prices.Count()));
    Console.WriteLine("capacity = " + Text.FromInteger(prices.Capacity()));

    // A List<Money> is accepted wherever an IReadOnlyList<Money> is wanted.
    Console.WriteLine("items    = " + Describe(prices));

    Console.WriteLine("largest  = " + Largest(prices).Show());
    Console.WriteLine("smallest = " + Smallest(prices).Show());
    Console.WriteLine("index of 999c = " + Text.FromInteger(IndexOf(prices, new Money(999))));

    Sort(prices);
    Console.WriteLine("sorted   = " + Describe(prices));

    prices.Clear();
    Console.WriteLine("cleared  = " + Text.FromBool(prices.IsEmpty()));
    return 0;
}
