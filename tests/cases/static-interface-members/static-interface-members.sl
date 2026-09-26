// SPDX-License-Identifier: 0BSD
module StaticInterfaceMembers;

import Standard.Console;

// What every implementing type supplies, and what one may fall back on.
public interface IAdditive<TSelf> where TSelf : IAdditive<TSelf>
{
    static abstract TSelf Zero { get; }
    static abstract TSelf operator +(TSelf a, TSelf b);

    static virtual TSelf Twice(TSelf x) => x + x;
    static virtual String Unit => "?";

    // The interface's own, reached by naming it.
    static String Describe() => "additive";
}

public interface IParse<TSelf> where TSelf : IParse<TSelf>
{
    static abstract TSelf Parse(String text);
}

// A struct implements an interface all of whose members are static.
public struct Money : IAdditive<Money>, IParse<Money>
{
    public long Cents;

    public Money(long cents) => Cents = cents;

    public static Money Zero => new Money(0);
    public static Money operator +(Money a, Money b) => new Money(a.Cents + b.Cents);
    public static String Unit => "c";
    public static Money Parse(String text) => new Money((long)text.ByteLength());
}

// A class does too, and a counted one is released as usual.
public class Meters : IAdditive<Meters>
{
    public double Value;

    public Meters(double value) => Value = value;
    ~Meters() { Console.WriteLine("~Meters " + Text.FromDouble(Value)); }

    public static Meters Zero => new Meters(0.0);
    public static Meters operator +(Meters a, Meters b) => new Meters(a.Value + b.Value);
    public static Meters Twice(Meters x) => new Meters(x.Value * 10.0);
}

T Sum<T>(T[] items) where T : IAdditive<T>
{
    T total = T.Zero;
    foreach (var item in items)
        total = total + item;
    return total;
}

T Double<T>(T x) where T : IAdditive<T> => T.Twice(x);

String UnitOf<T>() where T : IAdditive<T> => T.Unit;

T Read<T>(String text) where T : IParse<T> => T.Parse(text);

// A generic type reaching the same members, from a field and a lambda.
public class Accumulator<T> where T : IAdditive<T>
{
    T _total = T.Zero;

    public void Add(T item) => _total = _total + item;
    public T Total => _total;

    public T AddAll(T[] items)
    {
        var add = (T a, T b) => a + b;
        foreach (var item in items)
            _total = add(_total, item);
        return _total;
    }
}

int Main()
{
    Money[] coins = [new Money(5), new Money(10)];
    var total = Sum(coins);
    Console.WriteLine(Text.FromInteger(total.Cents) + UnitOf<Money>());
    Console.WriteLine(Text.FromInteger(Double(total).Cents));
    Console.WriteLine(Text.FromInteger(Read<Money>("four").Cents));

    Meters[] lengths = [new Meters(1.5), new Meters(2.0)];
    Console.WriteLine(Text.FromDouble(Sum(lengths).Value) + UnitOf<Meters>());
    Console.WriteLine(Text.FromDouble(Double(new Meters(1.0)).Value));

    var purse = new Accumulator<Money>();
    purse.Add(new Money(3));
    Console.WriteLine(Text.FromInteger(purse.AddAll(coins).Cents));

    Console.WriteLine(IAdditive<Money>.Describe());
    return 0;
}
