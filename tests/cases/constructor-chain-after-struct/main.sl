// SPDX-License-Identifier: 0BSD
//
// A struct's constructor that chains with `: this(...)`, bound before a class
// whose constructor leaves its base to be called for it. The base MUST still
// be constructed: what the struct's chain wrote is not the class's.
module ConstructorChainAfterStruct;

import Standard.Console;
import Standard.Text;

public struct Pair
{
    public int A { get; }
    public int B { get; }

    public Pair(int a) : this(a, 0) { }

    public Pair(int a, int b)
    {
        A = a;
        B = b;
    }
}

public class Base
{
    protected int[] _items;

    public Base()
    {
        _items = new int[3];
        _items[0] = 7;
    }
}

public class Derived : Base
{
    public Derived() { }

    public int First => _items[0];
}

int Main()
{
    var pair = new Pair(5);
    var derived = new Derived();
    Console.WriteLine(Text.FromInteger(pair.A + pair.B) + " " + Text.FromInteger(derived.First));
    return 0;
}
