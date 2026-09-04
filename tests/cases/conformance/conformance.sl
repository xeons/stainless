// SPDX-License-Identifier: 0BSD
module Conformance;

import Standard.Collections;
import Standard.Console;

extern "C" int printf(byte* format, ...);

public enum Level : byte { Low = 1, Warning = 10, Severe, Fatal = 200 }

// A user type still says what it implements; nothing here changes for it.
public class Money : IComparable<Money>, IEquatable<Money>, IHashable {
    int cents;

    public Money(int amount) { cents = amount; }
    public int Cents() { return cents; }

    public int CompareTo(Money other) { return cents.CompareTo(other.Cents()); }
    public bool EqualTo(Money other) { return cents == other.Cents(); }
    public nuint HashCode() { return cents.HashCode(); }
}

// The constraint is satisfied by 'int' and 'String' as readily as by a class.
T Middle<T>(IReadOnlyList<T> items) where T : IComparable<T> {
    var best = items.At(0);
    for (nuint i = 1; i < items.Count(); i = i + 1) {
        if (items.At(i).CompareTo(best) > 0) { best = items.At(i); }
    }
    return best;
}

nuint Digest<T>(IReadOnlyList<T> items) where T : IHashable, IEquatable<T> {
    nuint total = 0;
    for (nuint i = 0; i < items.Count(); i = i + 1) {
        total = total + items.At(i).HashCode();
    }
    return total;
}

int Main() {
    // Sorting a list of primitives, which needed a comparer before.
    var numbers = new List<int>();
    numbers.Add(30); numbers.Add(4); numbers.Add(17); numbers.Add(4);
    Sort(numbers);
    printf("sorted=%d %d %d %d\n",
        numbers.At(0), numbers.At(1), numbers.At(2), numbers.At(3));
    printf("index=%llu largest=%d smallest=%d\n",
        IndexOf(numbers, 17), Largest(numbers), Smallest(numbers));

    // Strings order by their bytes, which for UTF-8 is also by code point.
    var words = new List<String>();
    words.Add("pear"); words.Add("apple"); words.Add("fig");
    Sort(words);
    printf("words=%s %s %s\n",
        words.At(0).ToPointer(), words.At(1).ToPointer(), words.At(2).ToPointer());
    printf("longest=%s\n", Middle(words).ToPointer());

    // The three members, written out on values of each kind.
    printf("compare=%d %d %d\n", 3.CompareTo(5), 5.CompareTo(3), 4.CompareTo(4));
    printf("equal=%d %d\n", 7.EqualTo(7) ? 1 : 0, "a".EqualTo("b") ? 1 : 0);
    printf("text=%d %d\n", "apple".CompareTo("banana"), "b".CompareTo("a"));

    // An unsigned type orders unsigned, and a signed one orders signed.
    printf("signed=%d unsigned=%d\n", (-1).CompareTo(1), ((nuint)1).CompareTo((nuint)2));

    // Doubles, including the total order NaN needs so that a sort terminates.
    printf("doubles=%d %d %d\n",
        1.5.CompareTo(2.5), 2.5.CompareTo(1.5), 2.5.CompareTo(2.5));

    // Enums compare by their underlying value and hash like the integer.
    var level = Level.Severe;
    printf("enum=%d %d %d\n",
        level.CompareTo(Level.Low), level.CompareTo(Level.Fatal),
        level.EqualTo(Level.Severe) ? 1 : 0);

    // A hash is stable within a run and spreads adjacent keys apart.
    printf("hash=%d %d %d\n",
        "key".HashCode() == "key".HashCode() ? 1 : 0,
        1.HashCode() == 2.HashCode() ? 1 : 0,
        (1.HashCode() & 7) == (2.HashCode() & 7) ? 1 : 0);

    // bool and char take part too.
    printf("misc=%d %d\n", false.CompareTo(true), 'a'.CompareTo('b'));

    // A generic constrained on IHashable accepts a primitive, a String and a
    // class, and each instantiation is separately monomorphized.
    var moneys = new List<Money>();
    moneys.Add(new Money(250));
    moneys.Add(new Money(125));
    Sort(moneys);
    printf("money=%d %d hashes=%d\n",
        moneys.At(0).Cents(), moneys.At(1).Cents(),
        Digest(moneys) == Digest(moneys) ? 1 : 0);
    printf("digests=%d %d\n",
        Digest(numbers) == Digest(numbers) ? 1 : 0,
        Digest(words) == Digest(words) ? 1 : 0);

    printf("done\n");
    return 0;
}
