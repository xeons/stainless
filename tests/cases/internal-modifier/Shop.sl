// SPDX-License-Identifier: 0BSD
//
// `internal` in every place a visibility word may go. It is the visibility a
// declaration has with no word at all, written down, so each of these is
// reachable from anywhere in this module and from nowhere outside it.
module Shop;

import Standard.Console;

internal const int Shelves = 3;

internal static readonly String s_motto = "open late";

internal using Cents = long;

internal enum Aisle { Front, Back }

internal delegate int Pricer(int count);

internal closure int Discount(int price);

internal interface ICounted
{
    int Count { get; }
}

internal struct Tally
{
    internal int Items;
}

internal extern "C" int abs(int value);

internal int DoubleCount(int count) => count * 2;

public class Till : ICounted
{
    internal int _opened;

    internal Till(int opened)
    {
        _opened = opened;
    }

    public Till() : this(1)
    {
    }

    internal Cents Total { get; internal set; }

    public int Count => _opened;

    internal int Ring(int count) => DoubleCount(count);

    // C#'s union of the two, and what 'protected' alone means here.
    protected internal int Drawer() => 40;

    internal class Receipt
    {
        internal String Line = "thank you";
    }

    public String Summary()
    {
        var receipt = new Receipt();
        return $"{receipt.Line}, drawer {Drawer()}";
    }
}

public void ShowShop()
{
    var till = new Till(2);
    till.Total = 250;

    Tally tally;
    tally.Items = till.Ring(Shelves);

    Pricer pricer = DoubleCount;
    Discount discount = (int price) => price - 5;
    var aisle = Aisle.Back;
    ICounted counted = till;

    Console.WriteLine($"{s_motto}: {tally.Items} items, {till.Total} cents");
    Console.WriteLine($"{pricer(4)} {discount(20)} {aisle == Aisle.Back} {counted.Count} {abs(-7)}");
    Console.WriteLine(till.Summary());
}
