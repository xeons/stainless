// SPDX-License-Identifier: 0BSD
module Constraints;

import Standard.Console;
import Standard.Collections;    // IComparable<T> lives here

public interface IDescribable
{
    String Description { get; }
}

public class Money : IComparable<Money>, IDescribable
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

    public String Description => Text.FromInteger(_cents) + "c";
}

// `where T : IComparable<T>` is F-bounded: T must be comparable to itself.
T FindLargest<T>(T[] values) where T : IComparable<T>
{
    var best = values[0];
    for (nuint i = 1; i < values.Length; i++)
    {
        if (values[i].CompareTo(best) > 0)
            best = values[i];
    }
    return best;
}

// Two constraints on one parameter.
public class Ranked<T> where T : IComparable<T>, IDescribable
{
    // Slots past `_count` are empty until they are written.
    Slot<T>[] _items;
    nuint _count;

    public Ranked(nuint capacity)
    {
        _items = new Slot<T>[capacity];
        _count = 0;
    }

    public void Add(T item)
    {
        _items[_count] = item;
        _count++;
    }

    public String FindBestDescription()
    {
        var best = _items[0].Value;
        for (nuint i = 1; i < _count; i++)
        {
            if (_items[i].Value.CompareTo(best) > 0)
                best = _items[i].Value;
        }
        return best.Description;
    }
}

int Main()
{
    Money[] prices = [new Money(250), new Money(999), new Money(125)];

    Console.WriteLine("largest = " + FindLargest(prices).Description);

    var ranked = new Ranked<Money>(3);
    ranked.Add(new Money(10));
    ranked.Add(new Money(70));
    ranked.Add(new Money(40));
    Console.WriteLine("best    = " + ranked.FindBestDescription());
    return 0;
}
