// SPDX-License-Identifier: 0BSD
module Collections;

import Standard.Console;
import Standard.Collections;

// Interfaces are named with a leading I, as in C#.
public class Money : IComparable<Money>, IEquatable<Money>
{
    int _cents;

    public Money(int amount) => _cents = amount;
    public int Cents => _cents;

    public int CompareTo(Money other)
    {
        if (_cents < other.Cents)
            return -1;
        if (_cents > other.Cents)
            return 1;
        return 0;
    }

    public bool Equals(Money other) => _cents == other.Cents;

    public String ToText() => Text.FromInteger(_cents) + "c";
}

// IList<T> extends IReadOnlyList<T>, so a list passed here can only be read.
String DescribePrices(IReadOnlyList<Money> prices)
{
    var text = new StringBuilder();
    for (nuint i = 0; i < prices.Count; i++)
    {
        text.Append(prices[i].ToText());
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

    Console.WriteLine($"count    = {prices.Count}");
    Console.WriteLine($"capacity = {prices.Capacity}");

    // A List<Money> is accepted wherever an IReadOnlyList<Money> is wanted.
    Console.WriteLine($"items    = {DescribePrices(prices)}");

    Console.WriteLine($"largest  = {Max(prices).ToText()}");
    Console.WriteLine($"smallest = {Min(prices).ToText()}");

    // `IndexOf` answers with an `Optional<nuint>`. A list's length standing in
    // for "not there" is exactly the sentinel that type exists to retire.
    if (IndexOf(prices, new Money(999)) is Some at)
    {
        Console.WriteLine($"index of 999c = {at.Value}");
    }
    Console.WriteLine($"index of 1c   = {IndexOf(prices, new Money(1)).IsEmpty}");

    Sort(prices);
    Console.WriteLine($"sorted   = {DescribePrices(prices)}");

    prices.Clear();
    Console.WriteLine($"cleared  = {prices.IsEmpty}");
    return 0;
}
