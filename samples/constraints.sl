// SPDX-License-Identifier: 0BSD
module Constraints;

import Standard.Console;
import Standard.Collections;    // IComparable<T> lives here

public interface IDescribable {
    String Describe();
}

public class Money : IComparable<Money>, IDescribable {
    int cents;

    public Money(int amount) { cents = amount; }
    public int Cents() { return cents; }

    public int CompareTo(Money other) {
        if (cents < other.Cents()) { return -1; }
        if (cents > other.Cents()) { return 1; }
        return 0;
    }

    public String Describe() { return Text.FromInteger(cents) + "c"; }
}

// `where T : IComparable<T>` is F-bounded: T must be comparable to itself.
T Largest<T>(T[] values) where T : IComparable<T> {
    var best = values[0];
    for (nuint i = 1; i < values.Length; i = i + 1) {
        if (values[i].CompareTo(best) > 0) { best = values[i]; }
    }
    return best;
}

// Two constraints on one parameter.
public class Ranked<T> where T : IComparable<T>, IDescribable {
    T[] items;
    nuint count;

    public Ranked(nuint capacity) {
        items = new T[capacity];
        count = 0;
    }

    public void Add(T item) {
        items[count] = item;
        count = count + 1;
    }

    public String BestDescription() {
        var best = items[0];
        for (nuint i = 1; i < count; i = i + 1) {
            if (items[i].CompareTo(best) > 0) { best = items[i]; }
        }
        return best.Describe();
    }
}

int Main() {
    var prices = new Money[3];
    prices[0] = new Money(250);
    prices[1] = new Money(999);
    prices[2] = new Money(125);

    Console.WriteLine("largest = " + Largest(prices).Describe());

    var ranked = new Ranked<Money>(3);
    ranked.Add(new Money(10));
    ranked.Add(new Money(70));
    ranked.Add(new Money(40));
    Console.WriteLine("best    = " + ranked.BestDescription());
    return 0;
}
